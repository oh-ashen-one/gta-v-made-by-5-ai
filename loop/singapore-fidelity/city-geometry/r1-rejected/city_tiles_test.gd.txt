extends Node3D
## Parent owns native execution. Real ArrayMesh/trimesh geometry fixture, not
## the root World/Game authority or whole-city/gameplay/visual acceptance.
const Tiles = preload("res://src/world/geography/runtimecity_tiles.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const FIXTURE := "res://data/geography/compiled-country/osm-2026-10-27/qa-fixture-v1"
const FIXTURE_ID := "055bc31a84c3d919907fce3020c1594e377b639f90dd1981b54f9beb166ba97e"
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
const DEM := "5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var finished := false
var geometry: Node3D
var character: CharacterBody3D
var settle := false
func check(label: String,ok: bool,detail: String = "") -> bool:
	checks += 1
	print("[city-tiles] %s %s %s" % ["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok
func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(parent)
		if folder != null and folder.is_link(part): return false
		parent = parent.path_join(part)
	return true
func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--qa-session")
	if index < 0 or index+1 >= args.size():
		push_error("City tile QA requires isolated private --qa-session")
		get_tree().quit(2)
		return
	var base: String = args[index+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	base = base.path_join("city-tiles")
	if not _owned(base) or DirAccess.dir_exists_absolute(base) or FileAccess.file_exists(base) or DirAccess.make_dir_recursive_absolute(base) != OK:
		push_error("City tile QA refuses unsafe/existing evidence")
		get_tree().quit(2)
		return
	output = base.path_join("report.json")
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not finished:
			check("bounded native city tile QA",false,"75-second watchdog")
			_finish())
	watchdog.start(75.0)
	_run.call_deferred()
func _physics_process(delta: float) -> void:
	if settle and is_instance_valid(character):
		character.velocity.y -= 9.8*delta
		character.move_and_slide()
func _ray(a: Vector3,b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a,b,1)
	return get_world_3d().direct_space_state.intersect_ray(query)
func _install_feature(feature: Dictionary,anchor: Vector3) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface: Dictionary in feature.surfaces: mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface.arrays)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = anchor
	geometry.add_child(visual)
	var body := StaticBody3D.new()
	body.position = anchor
	body.collision_layer = 1
	geometry.add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	return mesh
func _run() -> void:
	var provider := Tiles.new()
	var policy := {"mode":Tiles.YMODE,"offset_m":0.0}
	if not check("versioned generated mesh fixture configures",provider.configure(FIXTURE,FIXTURE_ID,"a".repeat(64),"b".repeat(64),policy,1),provider.last_error):
		_finish()
		return
	check("wrong snapshot refused",not Tiles.new().configure(FIXTURE,FIXTURE_ID,"f".repeat(64),"b".repeat(64),policy))
	check("wrong DEMidentity refused",not Tiles.new().configure(FIXTURE,FIXTURE_ID,"a".repeat(64),"f".repeat(64),policy))
	check("implicit/unsupportedYpolicy refused",not Tiles.new().configure(FIXTURE,FIXTURE_ID,"a".repeat(64),"b".repeat(64),{"mode":"implicit-ground","offset_m":0.0}))
	var frame := Frame.new()
	check("canonical80km frame configured before localvectors",frame.configure(Frame.EXPECTED_FRAME,[80000,0,80000],"a".repeat(64),{"status":"staging","reference":"SYNTHETIC_NOT_REAL_EGM96"}))
	geometry = Node3D.new()
	add_child(geometry)
	var fragment_ids: Dictionary = {}
	for key: String in ["80_80","81_80"]:
		var split: PackedStringArray = key.split("_")
		var tile: Dictionary = provider.tile(int(split[0]),int(split[1]))
		if not check("fixture tile byte/topology decodes "+key,tile.get("ok",false),str(tile.get("reason",""))): continue
		var projected: Dictionary = frame.to_local(tile.anchor_source_xyz)
		if not check("canonicalanchor subtracts before localVector "+key,projected.get("ok",false),str(projected)): continue
		for feature: Dictionary in tile.features:
			check("spatialfragment identity unique",not fragment_ids.has(feature.fragment_key))
			fragment_ids[feature.fragment_key] = true
			var mesh: ArrayMesh = _install_feature(feature,projected.position)
			check("actualArrayMesh surfaces andtrimesh created",mesh.get_surface_count() == feature.surfaces.size() and mesh.get_surface_count() > 0)
	check("logicalfeature canownmultiple distincttilefragments",fragment_ids.has("building|way/10002@80_80") and fragment_ids.has("building|way/10002@81_80"))
	for i in 4: await get_tree().physics_frame
	var roof: Dictionary = _ray(Vector3(3,25,3),Vector3(3,-5,3))
	check("generated courtyardroof has actual native support",not roof.is_empty() and absf(roof.get("position",Vector3.ZERO).y-12.0)<.001 and roof.get("normal",Vector3.ZERO).y>.95,str(roof))
	check("courtyardhole stays physicallyopen throughroofandbottom",_ray(Vector3(7,25,7),Vector3(7,-5,7)).is_empty())
	var seam: Dictionary = _ray(Vector3(1000,25,30),Vector3(1000,-5,30))
	check("spanningroof supports across canonical tileedge",not seam.is_empty() and absf(seam.get("position",Vector3.ZERO).y-9.6)<.001,str(seam))
	check("tilepartition didnotcreate an artificial verticalwall",_ray(Vector3(999,5,30),Vector3(1001,5,30)).is_empty())
	character = CharacterBody3D.new()
	character.collision_layer = 2
	character.collision_mask = 1
	geometry.add_child(character)
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.75
	shape_node.shape = capsule
	shape_node.position = Vector3(0,.9,0)
	character.add_child(shape_node)
	character.position = Vector3(3,15,3)
	settle = true
	for i in 150: await get_tree().physics_frame
	check("actualcapsule settles oncompiledroof",character.is_on_floor() and absf(character.position.y-11.975)<.06 and absf(character.velocity.y)<.1,str(character.position))
	settle = false
	var before: Dictionary = provider.metadata().stats
	provider.tile(81,80)
	var middle: Dictionary = provider.metadata().stats
	provider.tile(81,80)
	check("cached mesh query doesnotreread",provider.metadata().stats.file_reads == middle.file_reads)
	provider.tile(80,80)
	check("mesh LRU staysbounded",provider.metadata().stats.max_cached_mesh_tiles <= 1 and provider.metadata().stats.evictions > 0)
	var catalog: Dictionary = provider.catalog("80_80")
	check("logicalcatalogretainsfeatureIDs",catalog.get("ok",false) and catalog.catalog.features.size() == 2)
	check("unknowncell creates nofakeemptyland",not provider.tile(0,0).get("ok",false))
	check("liveprovider cannotreconfigure",not provider.configure(FIXTURE,FIXTURE_ID,"a".repeat(64),"b".repeat(64),policy))
	metrics["fixture_provider"] = provider.metadata()
	geometry.queue_free()
	for i in 3: await get_tree().physics_frame
	await _actual(policy)
	_finish()
func _actual(policy: Dictionary) -> void:
	var directory := "res://data/geography/compiled-country/osm-2026-10-27/candidate-r1"
	var identity := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--city-dir="): directory = arg.trim_prefix("--city-dir=")
		if arg.begins_with("--city-identity="): identity = arg.trim_prefix("--city-identity=")
	if identity.is_empty():
		metrics["actual_country_status"] = "NOT_RUN; explicit trusted --city-identity required"
		return
	var provider := Tiles.new()
	if not check("actualwholecountry identityconfigures",provider.configure(directory,identity,SNAPSHOT,DEM,policy,1),provider.last_error): return
	var keys: Array = provider.mesh_keys()
	keys.sort()
	if not check("actualcountry hasrenderable mesh tiles",not keys.is_empty()): return
	var parsed: PackedStringArray = String(keys[0]).split("_")
	var tile: Dictionary = provider.tile(int(parsed[0]),int(parsed[1]))
	if not check("actualcountry tileandcollisiontopology decode",tile.get("ok",false),str(tile.get("reason",""))): return
	var frame := Frame.new()
	check("actualtile source frameconfigures",frame.configure(Frame.EXPECTED_FRAME,tile.anchor_source_xyz,SNAPSHOT,{"status":"source_tag","reference":"EGM96gameDEMreference_not_survey"}))
	var local: Dictionary = frame.to_local(tile.anchor_source_xyz)
	geometry = Node3D.new()
	add_child(geometry)
	if not tile.features.is_empty() and local.get("ok",false):
		var mesh: ArrayMesh = _install_feature(tile.features[0],local.position)
		check("actualnationalbuilding ArrayMesh/trimesh instantiates",mesh.get_surface_count()>0)
		for i in 3: await get_tree().physics_frame
	metrics["actual_country_status"] = "Actualboundedtile source geometry instantiated; not normalbootstrap or visualacceptance"
	metrics["actual_provider"] = provider.metadata()
	metrics["actual_tested_tile"] = tile.tile_key
	geometry.queue_free()
func _finish() -> void:
	if finished: return
	finished = true
	settle = false
	var report := {"checks":checks,"failures":failures,"metrics":metrics,"scope":"ActualgeneratedArrayMesh/trimesh nativefixture/support/holes/seams and optional boundednationaltile; notfullcitygame/visual/material/physicsresidency acceptance"}
	var f := FileAccess.open(output,FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report,"\t"))
		f.close()
	print("[city-tiles] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
