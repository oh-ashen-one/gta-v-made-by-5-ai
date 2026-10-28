extends Node
## File-integrity/spatial-query fixtures, not terrain/gameplay acceptance.
const MapData = preload("res://src/world/geography/map_data.gd")
var checks := 0
var failures: Array[String] = []
var qa := ""
var actual_status := "NOT_RUN"
var actual_metrics: Dictionary = {}
const FRAME := {"source_crs": "EPSG:4326", "origin_easting": 30000.0, "origin_northing": 30000.0, "survey_crs": "EPSG:3414", "metres_per_unit": 1.0, "distance_compression": false, "world_axes": {"x": "south", "y": "up", "z": "west"}}

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("[geography-data] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)

func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _feature(id: String, kind: String, geometry: Dictionary) -> Dictionary:
	var f := {"id": id, "kind": kind, "tags": {}, "geometry": geometry}
	if kind == "building":
		f["height_m"] = null
		f["height_status"] = "unknown"
	return f

func _fixture(name: String) -> Dictionary:
	var base := qa.path_join(name)
	DirAccess.make_dir_recursive_absolute(base)
	var long_road := _feature("way/1", "road", {"type": "LineString", "coordinates": [[-100,100],[3100,100]]})
	var building := _feature("way/1", "building", {"type": "Polygon", "coordinates": [[[100,100],[200,100],[200,200],[100,200],[100,100]]]})
	var water := _feature("way/2", "waterway", {"type": "LineString", "coordinates": [[3000,50],[3200,50]]})
	var files := {"0_0.json": [building], "1_0.json": [long_road], "3_0.json": [long_road.duplicate(true), water]}
	var inventory: Array = []
	for filename in files:
		var text := JSON.stringify({"tile": filename.trim_suffix(".json"), "features": files[filename]})
		_write(base.path_join(filename), text)
		inventory.append({"file": filename, "features": files[filename].size(), "bytes": text.to_utf8_buffer().size(), "sha256": _sha(text.to_utf8_buffer())})
	var boundary := JSON.stringify({"type": "Polygon", "coordinates": [[[103,1],[104,1],[104,2],[103,2],[103,1]]]})
	_write(base.path_join("singapore-boundary.geojson"), boundary)
	var manifest := {"georeference": FRAME.duplicate(true), "tile_metres": 1000, "tiles": inventory, "data_license": "ODbL-1.0", "attribution": "Labeled synthetic test fixture; not Singapore geometry"}
	var raw := JSON.stringify(manifest)
	_write(base.path_join("manifest.json"), raw)
	var index := {"schema": MapData.SCHEMA, "snapshot_manifest_sha256": _sha(raw.to_utf8_buffer()), "boundary_sha256": _sha(boundary.to_utf8_buffer()), "georeference": FRAME.duplicate(true), "tile_metres": 1000,
		"indexed_cells": 4, "owner_files": 3, "features_indexed": 4,
		"cells": {"0_0": ["0_0.json","1_0.json","3_0.json"], "1_0": ["1_0.json"], "2_0": ["1_0.json","3_0.json"], "3_0": ["1_0.json","3_0.json"]}}
	var fixture := {"base": base, "index": base.path_join("index.json"), "manifest": manifest, "index_payload": index}
	_seal_fixture_index(fixture)
	return fixture

## Synthetic publisher only. Corruption tests deliberately do NOT reseal.
func _seal_fixture_index(fixture: Dictionary) -> void:
	var bytes := JSON.stringify(fixture.index_payload).to_utf8_buffer()
	_write(fixture.index, bytes.get_string_from_utf8())
	var identity := {"schema": MapData.IDENTITY_SCHEMA, "index_sha256": _sha(bytes), "index_bytes": bytes.size(),
		"snapshot_manifest_sha256": _sha(FileAccess.get_file_as_bytes(fixture.base.path_join("manifest.json"))),
		"boundary_sha256": _sha(FileAccess.get_file_as_bytes(fixture.base.path_join("singapore-boundary.geojson"))),
		"indexed_cells": fixture.index_payload.indexed_cells, "owner_files": fixture.index_payload.owner_files,
		"features_indexed": fixture.index_payload.features_indexed}
	_write(fixture.base.path_join("spatial-index.identity.json"), JSON.stringify(identity))

func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var d := DirAccess.open(parent)
		if d != null and d.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size():
		push_error("Geography data test requires an explicit owned --qa-session")
		get_tree().quit(2)
		return
	qa = args[at + 1]
	if qa.begins_with("/tmp/"): qa = "/private/tmp/" + qa.trim_prefix("/tmp/")
	qa = qa.path_join("geography-data-fixtures")
	if not _owned(qa) or DirAccess.dir_exists_absolute(qa):
		push_error("Geography fixtures refuse unsafe paths or existing evidence")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(qa)
	_run.call_deferred()

func _run() -> void:
	var good := _fixture("good")
	var map := MapData.new()
	check("snapshot/index/frame hashes open", map.open_snapshot(good.base,good.index,1), map.last_error)
	var near := map.features_in_region(Rect2(0,0,800,800))
	check("far centroid owner supplies crossing road", near.any(func(f: Dictionary) -> bool: return f.id == "way/1" and f.kind == "road"), map.last_error)
	check("deduplicate identical source identity, preserve different semantic kind", near.size() == 2)
	var b: Dictionary = {}
	for f in near:
		if f.kind == "building": b = f
	check("unknown building height remains unknown", not b.is_empty() and b.height_m == null and b.height_status == "unknown")
	var roads := map.features_in_region(Rect2(0,0,800,800),["road"])
	check("kind filter retains only requested role", roads.size() == 1 and roads[0].kind == "road")
	var far := map.features_in_region(Rect2(2990,0,200,300))
	check("long feature present at opposite edge", far.any(func(f: Dictionary) -> bool: return f.id == "way/1") and far.any(func(f: Dictionary) -> bool: return f.id == "way/2"))
	check("LRU cache stays bounded and evicts", map.cached_tile_count() <= 1 and map.stats.max_cached_tiles <= 1 and map.stats.evictions > 0, str(map.stats))
	var warm := MapData.new()
	check("warm cache fixture opens", warm.open_snapshot(good.base,good.index,3))
	warm.features_in_region(Rect2(0,0,800,800))
	var loaded: int = warm.stats.tile_loads
	warm.features_in_region(Rect2(0,0,800,800))
	check("repeat query uses cache without disk reload", warm.stats.tile_loads == loaded and warm.stats.cache_hits >= 3)
	check("outside dependency cells returns empty without error", map.features_in_region(Rect2(20000,20000,100,100)).is_empty() and map.last_error.is_empty())
	check("oversized query refuses without partial result", map.features_in_region(Rect2(-100000,-100000,200000,200000)).is_empty() and not map.last_error.is_empty())
	check("extreme finite query cannot overflow the cell budget", map.features_in_region(Rect2(1000,1000,4294967295000.0,4294967295000.0)).is_empty() and not map.last_error.is_empty())
	check("finite inputs with an overflowing rectangle end are rejected", map.features_in_region(Rect2(3e38,0,3e38,1)).is_empty() and not map.last_error.is_empty())
	var removed_cell := _fixture("removed-cell")
	removed_cell.index_payload.cells.erase("0_0")
	_write(removed_cell.index, JSON.stringify(removed_cell.index_payload))
	var damaged := MapData.new()
	check("removed dependency cell fails full index identity", not damaged.open_snapshot(removed_cell.base,removed_cell.index) and "identity" in damaged.last_error, damaged.last_error)
	var removed_owner := _fixture("removed-owner")
	removed_owner.index_payload.cells["0_0"].erase("0_0.json")
	_seal_fixture_index(removed_owner)
	var incomplete := MapData.new()
	check("even a resealed index cannot omit a nonempty owner", not incomplete.open_snapshot(removed_owner.base,removed_owner.index) and "omits" in incomplete.last_error, incomplete.last_error)
	var empty_cells := _fixture("empty-cells")
	empty_cells.index_payload.cells = {}
	_seal_fixture_index(empty_cells)
	var count_mismatch := MapData.new()
	check("dependency inventory counts reject an empty table", not count_mismatch.open_snapshot(empty_cells.base,empty_cells.index) and "count" in count_mismatch.last_error, count_mismatch.last_error)
	_write(good.base.path_join("0_0.json"), "{}")
	map.clear_cache()
	check("changed tile hash refuses entire query", map.features_in_region(Rect2(0,0,800,800)).is_empty() and "checksum" in map.last_error)
	var bad_path := _fixture("bad-path")
	bad_path.index_payload.cells["0_0"] = ["../0_0.json"]
	_seal_fixture_index(bad_path)
	check("dependency path traversal is refused", not MapData.new().open_snapshot(bad_path.base,bad_path.index))
	var bad_manifest := _fixture("bad-manifest-hash")
	bad_manifest.index_payload.snapshot_manifest_sha256 = "0".repeat(64)
	_seal_fixture_index(bad_manifest)
	check("different snapshot index is refused", not MapData.new().open_snapshot(bad_manifest.base,bad_manifest.index))
	var bad_boundary := _fixture("bad-boundary")
	_write(bad_boundary.base.path_join("singapore-boundary.geojson"), "{}")
	check("different country boundary is refused", not MapData.new().open_snapshot(bad_boundary.base,bad_boundary.index))
	var compressed := _fixture("compressed")
	compressed.manifest.georeference.distance_compression = true
	_write(compressed.base.path_join("manifest.json"), JSON.stringify(compressed.manifest))
	check("compressed frame is refused", not MapData.new().open_snapshot(compressed.base,compressed.index))
	var shifted := _fixture("shifted-origin")
	shifted.manifest.georeference.origin_easting = 0.0
	_write(shifted.base.path_join("manifest.json"), JSON.stringify(shifted.manifest))
	check("shifted geography origin is refused", not MapData.new().open_snapshot(shifted.base,shifted.index))
	var index_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--geography-index="): index_path = arg.trim_prefix("--geography-index=")
	if not index_path.is_empty(): _actual_snapshot(index_path)
	else: print("[geography-data] ACTUAL_SOURCE_NOT_RUN: provide --geography-index=<built sidecar>; synthetic fixtures are not national-data proof")
	var report := {"checks": checks, "failures": failures, "actual_source_status": actual_status, "actual_source_metrics": actual_metrics,
		"scope": "Source integrity, bounded cache and spatial broadphase data queries. Not terrain, city migration, appearance, gameplay or FPS acceptance."}
	_write(qa.path_join("report.json"), JSON.stringify(report,"\t"))
	print("[geography-data] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func _actual_snapshot(index_path: String) -> void:
	actual_status = "FAILED"
	var map := MapData.new()
	var opened := map.open_snapshot("res://data/geography/osm-2026-10-27",index_path,12)
	check("actual national source/index opens", opened, map.last_error)
	if not opened: return
	var fs := map.features_in_region(Rect2(-300,-1800,1600,1800),["building"])
	check("actual regional query has no source failure", map.last_error.is_empty(), map.last_error)
	var ids: Dictionary = {}
	for f in fs: ids[f.id] = true
	for id in ["way/116801004","way/172307472","way/172307471","relation/2298319"]:
		check("actual MBS source component " + id, ids.has(id))
	check("actual source cache remains bounded", map.cached_tile_count() <= 12 and map.stats.max_cached_tiles <= 12)
	actual_metrics = map.stats.duplicate(true)
	actual_metrics["returned_building_candidates"] = fs.size()
	actual_metrics["source_snapshot_utc"] = map.metadata().get("source_snapshot_utc")
	actual_status = "PASS" if map.last_error.is_empty() and ids.has("way/116801004") and ids.has("way/172307472") and ids.has("way/172307471") and ids.has("relation/2298319") else "FAILED"
