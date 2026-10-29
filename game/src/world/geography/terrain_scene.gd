class_name SingaporeTerrainScene
extends Node3D
## Root-controlled real terrain mesh/collision assembly. The shared verified
## city-scene commit/epoch/retirement mechanics remain one scene authority.
const SourceFrame = preload("res://src/world/geography/source_frame.gd")
const Tiles = preload("res://src/world/geography/runtimecity_tiles.gd")
const SceneInstaller = preload("res://src/world/geography/city_scene.gd")
const OUTER_SCHEMA := "singapore_source_terrain_scene_identity_v1"
const WATER_POLICY := "exclude_canonical_water_horizontal_footprints_from_terrain_support_not_3d_hydrology"
signal terrain_tile_committed(tile_key: String,receipt: Dictionary)
signal terrain_tile_retired(tile_key: String)
var last_error := ""
var _frame: RefCounted
var _material: Callable
var _guard: Callable
var _material_owner: RefCounted
var _guard_owner: RefCounted
var _provider: RefCounted
var _installer: Variant = null
var _configured := false
var _opened := false
var _maximum := 9
var _batch := 16
var _outer: Dictionary = {}
var _outer_sha := ""
var _receipts: Dictionary = {}
var _sha_re := RegEx.new()
func _init() -> void:
	_sha_re.compile("^[0-9a-f]{64}$")
func _hash(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and _sha_re.search(value) != null
func _text(value: Variant,expected: String) -> bool:
	return typeof(value) == TYPE_STRING and value == expected
func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
func _integer(value: Variant,lo: int,hi: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and float(value) >= lo and float(value) <= hi
func _fail(reason: String) -> bool:
	last_error = reason
	return false
func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _read(path: String,maximum: int) -> PackedByteArray:
	var f := FileAccess.open(path,FileAccess.READ)
	if f == null or f.get_length() <= 0 or f.get_length() > maximum: return PackedByteArray()
	return f.get_buffer(f.get_length())

## Explicit root callbacks and frame. No source dataset is selected here.
func configure(frame: RefCounted,material_for_surface: Callable,may_retire: Callable,maximum_tiles: int = 9,features_per_frame: int = 16) -> bool:
	if _configured or not is_inside_tree() or not frame is SourceFrame or not frame.metadata().configured or not material_for_surface.is_valid() or not may_retire.is_valid(): return _fail("Explicit live frame/root material/retirement authority required")
	if maximum_tiles < 1 or maximum_tiles > 25 or features_per_frame < 1 or features_per_frame > 64: return _fail("Invalid bounded terrain install budget")
	_frame = frame
	_material = material_for_surface
	_guard = may_retire
	if _material.get_object() is RefCounted: _material_owner = _material.get_object()
	if _guard.get_object() is RefCounted: _guard_owner = _guard.get_object()
	_maximum = maximum_tiles
	_batch = features_per_frame
	_configured = true
	return true

## Identity is verified independently of the generic mesh encoding. Explicit
## root mask SHA is mandatory, even if root intentionally approved emptymasks.
func open_prepared(directory: String,terrain_identity_sha256: String,snapshot_sha256: String,dem_identity_sha256: String,root_holes_sha256: String,world_y_policy: Dictionary,cache_capacity: int = 2) -> bool:
	if not _configured or _opened: return _fail("Configure once, then open one immutable terrain preparation")
	for value in [terrain_identity_sha256,snapshot_sha256,dem_identity_sha256,root_holes_sha256]:
		if not _hash(value): return _fail("Trusted source/terrain/root mask identities required")
	if not _text(_frame.metadata().snapshot_manifest_sha256,snapshot_sha256): return _fail("Terrain/source frame snapshot mismatch")
	var base: String = directory.trim_suffix("/")
	var folder := DirAccess.open(base)
	if folder == null or base != base.simplify_path() or folder.is_link("terrain-identity.json"): return _fail("Unsafe/unavailable terrain preparation")
	var raw: PackedByteArray = _read(base.path_join("terrain-identity.json"),262144)
	if raw.is_empty() or _sha(raw) != terrain_identity_sha256: return _fail("Terrain preparation identity checksum mismatch")
	var outer: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not outer is Dictionary or not _text(outer.get("schema"),OUTER_SCHEMA) or not _integer(outer.get("version"),1,1) or not outer.get("bindings") is Dictionary or not outer.get("geometry_identity") is Dictionary or not outer.get("world_y_policy") is Dictionary or not outer.get("water_registry") is Dictionary: return _fail("Invalid terrain preparation schema")
	for field: String in ["snapshot_sha","dem_identity","domain_identity","root_holes_sha256","canonical_water_registry_sha256","compiler_sha256","preparation_sha256"]:
		if not _hash(outer.bindings.get(field)): return _fail("Incomplete terrain provenance binding")
	if not _text(outer.bindings.snapshot_sha,snapshot_sha256) or not _text(outer.bindings.dem_identity,dem_identity_sha256) or not _text(outer.bindings.root_holes_sha256,root_holes_sha256) or not _text(outer.get("water_policy"),WATER_POLICY): return _fail("Terrain source/DEM/root holes/water policy mismatch")
	if not _text(world_y_policy.get("mode"),Tiles.YMODE) or not _number(world_y_policy.get("offset_m")) or not _text(outer.world_y_policy.get("mode"),Tiles.YMODE) or not _number(outer.world_y_policy.get("offset_m")) or float(world_y_policy.offset_m) != float(outer.world_y_policy.offset_m): return _fail("Explicit EGM96 game-world Y policy mismatch")
	if not _text(outer.geometry_identity.get("file"),"identity.json") or not _hash(outer.geometry_identity.get("sha256")) or not _integer(outer.geometry_identity.get("bytes"),1,65536) or folder.is_link("identity.json"): return _fail("Invalid terrain geometry identity descriptor")
	var geometry_raw: PackedByteArray = _read(base.path_join("identity.json"),65536)
	if geometry_raw.size() != int(outer.geometry_identity.bytes) or _sha(geometry_raw) != outer.geometry_identity.sha256: return _fail("Terrain generic mesh identity differs")
	if not _text(outer.water_registry.get("file"),"water-registry.json") or not _text(outer.water_registry.get("sha256"),outer.bindings.canonical_water_registry_sha256): return _fail("Terrain water registry descriptor mismatch")
	if not _integer(outer.water_registry.get("bytes"),1,32*1024*1024) or folder.is_link("water-registry.json"): return _fail("Terrain water registry exceeds bounds or is a symlink")
	var water_raw: PackedByteArray = _read(base.path_join("water-registry.json"),32*1024*1024)
	if water_raw.size() != int(outer.water_registry.bytes) or _sha(water_raw) != outer.water_registry.sha256: return _fail("Canonical water registry bytes differ from preparation")
	var provider := Tiles.new()
	if not provider.configure(base,outer.geometry_identity.sha256,snapshot_sha256,dem_identity_sha256,world_y_policy,cache_capacity): return _fail(provider.last_error)
	var installer := SceneInstaller.new()
	installer.name = "RootOwnedTerrainInstaller"
	add_child(installer)
	# Root's new explicit geometry/snapshot ABI; no implicit frame identity.
	if not installer.configure(_frame,_material,_guard,_maximum,_batch,{"geometry_identity_sha256":outer.geometry_identity.sha256,"snapshot_manifest_sha256":snapshot_sha256}):
		installer.queue_free()
		return _fail("Root scene installer rejected terrain identity/context")
	_provider = provider
	_installer = installer
	_outer = outer.duplicate(true)
	_outer_sha = terrain_identity_sha256
	_opened = true
	last_error = ""
	return true

func metadata() -> Dictionary:
	return {"configured":_configured,"opened":_opened,"terrain_identity_sha256":_outer_sha,
		"bindings":_outer.get("bindings",{}).duplicate(true),"counts":_outer.get("counts",{}).duplicate(true),
		"root_masks_are_surveyed_basements":false,"water_columns_or_dryland_certified":false,"older_coarse_DEM_not_current_ground":true,
		"source_runtime_residency_registered":false}
func mesh_keys() -> Array:
	return _provider.mesh_keys() if _opened else []
func prepare_tile(tx: int,tz: int) -> Dictionary:
	if not _opened: return {"ok":false,"state":"unknown","reason":"Terrain preparation not explicitly opened"}
	var decoded: Dictionary = _provider.tile(tx,tz)
	if not decoded.get("ok",false): return decoded
	var p: Variant = decoded.get("terrain_reference")
	if not p is Dictionary or not _text(p.get("schema"),OUTER_SCHEMA) or not _text(p.get("preparation_sha256"),_outer.bindings.preparation_sha256) or not _text(p.get("root_holes_sha256"),_outer.bindings.root_holes_sha256) or not _text(p.get("water_registry_sha256"),_outer.bindings.canonical_water_registry_sha256) or not _text(p.get("water_policy"),WATER_POLICY): return {"ok":false,"state":"unknown","reason":"Terrain tile lost declared hole/water provenance"}
	decoded["terrain_scene_binding"] = {"terrain_identity_sha256":_outer_sha,"preparation_sha256":_outer.bindings.preparation_sha256,"root_holes_sha256":_outer.bindings.root_holes_sha256}
	return decoded
func install_tile(prepared: Dictionary) -> Dictionary:
	if not _opened or not prepared.get("terrain_scene_binding") is Dictionary or not _text(prepared.terrain_scene_binding.get("terrain_identity_sha256"),_outer_sha) or not _text(prepared.terrain_scene_binding.get("root_holes_sha256"),_outer.bindings.root_holes_sha256): return {"ok":false,"reason":"Explicit current terrain/hollow-mask preparation required"}
	var result: Dictionary = await _installer.install_tile(prepared)
	if not result.get("ok",false): return result
	var receipt: Dictionary = result.receipt.duplicate(true)
	receipt["terrain_identity_sha256"] = _outer_sha
	receipt["terrain_provenance"] = prepared.terrain_reference.duplicate(true)
	receipt["hydrology_or_surveyed_dry_ground_verified"] = false
	for body in _installer.collision_bodies(prepared.tile_key):
		body.set_meta("source_terrain_root_holes_sha256",_outer.bindings.root_holes_sha256)
		body.set_meta("source_terrain_reference","coarse_EGM96_game_surface_not_current_survey")
	_receipts[prepared.tile_key] = receipt
	terrain_tile_committed.emit(prepared.tile_key,receipt.duplicate(true))
	return {"ok":true,"receipt":receipt.duplicate(true)}
func collision_bodies(key: String) -> Array:
	return _installer.collision_bodies(key) if _opened else []
func tile_receipt(key: String) -> Dictionary:
	return _receipts.get(key,{}).duplicate(true)
func retire_tile(key: String) -> Dictionary:
	if not _opened: return {"ok":false,"reason":"Terrain not open"}
	var result: Dictionary = await _installer.retire_tile(key)
	if result.get("ok",false):
		_receipts.erase(key)
		terrain_tile_retired.emit(key)
	return result
