extends Node3D
## Root-run actual-source neighborhood/native geometry fixture. Not normal
## World bootstrap, surveyed ground, full hydrology or architectural acceptance.
const TerrainScene = preload("res://src/world/geography/terrain_scene.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Tiles = preload("res://src/world/geography/runtimecity_tiles.gd")
const DIRECTORY := "/private/tmp/singapore-fidelity/terrain-scene/mbs-neighborhood-r1"
const TERRAIN_ID := "f8488742dd93726276b33ca12cda7c6d0a38b967123a0be0d574b9145b7f469c"
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
const DEM := "5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841"
const MASKS := "9d91185dab9c936316b1397a7faad778556b28fb29e44f01f03b4fe04d498625"
class RootPolicy extends RefCounted:
	var allow_retire := false
	var material := StandardMaterial3D.new()
	func material_for(_id: String,_role: String) -> Material: return material
	func may_retire(_key: String,_receipt: Dictionary) -> bool: return allow_retire
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var report_path := ""
var finished := false
var body: CharacterBody3D
var settle := false
func check(label: String,ok: bool,detail: String = "") -> bool:
	checks += 1
	print("[terrain-scene] %s %s %s" % ["PASS" if ok else "FAIL",label,detail])
	if not ok: failures.append(label)
	return ok
func _owned(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path != path.simplify_path(): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(parent)
		if folder != null and folder.is_link(part): return false
		parent = parent.path_join(part)
	return true
func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--qa-session")
	if at < 0 or at+1 >= args.size():
		push_error("Terrain scene QA requires private --qa-session")
		get_tree().quit(2)
		return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	base = base.path_join("terrain-scene")
	if not _owned(base) or DirAccess.dir_exists_absolute(base) or FileAccess.file_exists(base) or DirAccess.make_dir_recursive_absolute(base) != OK:
		push_error("Terrain QA refuses unsafe/existing evidence")
		get_tree().quit(2)
		return
	report_path = base.path_join("report.json")
	var watchdog := Timer.new()
	watchdog.one_shot = true
	watchdog.ignore_time_scale = true
	add_child(watchdog)
	watchdog.timeout.connect(func():
		if not finished:
			check("bounded actual terrain scene QA",false,"90-second watchdog")
			_finish())
	watchdog.start(90.0)
	_run.call_deferred()
func _physics_process(delta: float) -> void:
	if settle and is_instance_valid(body):
		body.velocity.y -= 9.8*delta
		body.move_and_slide()
func _ray(x: float,z: float) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,100,z),Vector3(x,-100,z),1))
func _run() -> void:
	var frame := Frame.new()
	if not check("actual source frame/explicit game datum configures",frame.configure(Frame.EXPECTED_FRAME,[0,0,-1000],SNAPSHOT,{"status":"source_tag","reference":Tiles.YMODE})): _finish(); return
	var policy := RootPolicy.new()
	var terrain := TerrainScene.new()
	add_child(terrain)
	check("root frame/material/retirement callbacks configure",terrain.configure(frame,policy.material_for,policy.may_retire,9,16))
	check("wrong Rootmask identity rejected",not terrain.open_prepared(DIRECTORY,TERRAIN_ID,SNAPSHOT,DEM,"0".repeat(64),{"mode":Tiles.YMODE,"offset_m":0.0}))
	if not check("actual terrain coast/water/mask preparation opens",terrain.open_prepared(DIRECTORY,TERRAIN_ID,SNAPSHOT,DEM,MASKS,{"mode":Tiles.YMODE,"offset_m":0.0}),terrain.last_error): _finish(); return
	check("unprepared data never installs fallbackland",not (await terrain.install_tile({"ok":false})).get("ok",false))
	check("unloaded cell remains unknown",not terrain.prepare_tile(999,999).get("ok",false))
	var keys: Array = terrain.mesh_keys()
	keys.sort()
	if not check("actual bounded neighborhood contains9preparedtiles",keys.size()==9): _finish(); return
	var all_bodies: Array = []
	for key: String in keys:
		var components: PackedStringArray = key.split("_")
		var prepared: Dictionary = terrain.prepare_tile(int(components[0]),int(components[1]))
		if not check("actual terrain tile validates "+key,prepared.get("ok",false),str(prepared.get("reason",""))): continue
		var result: Dictionary = await terrain.install_tile(prepared)
		if not check("actual ArrayMesh/trimesh committed "+key,result.get("ok",false),str(result)): continue
		check("commit doesnotclaim runtime hydrology/drysurvey "+key,result.receipt.native_collision_committed and not result.receipt.source_runtime_residency_registered and not result.receipt.hydrology_or_surveyed_dry_ground_verified)
		all_bodies.append_array(terrain.collision_bodies(key))
	check("all9nativecollisionbodies available forRootregistry",all_bodies.size()==9)
	var duplicate: Dictionary = await terrain.install_tile(terrain.prepare_tile(0,-1))
	check("duplicate terrain generation rejected",not duplicate.get("ok",false))
	for i in 4: await get_tree().physics_frame
	# Actual source point [700,8.883132934570312,-900], 0.6m selection
	# margin only; no source geometry buffer/repair was used.
	var positive: Dictionary = _ray(700,100)
	check("actual source DEM native support height",not positive.is_empty() and absf(positive.get("position",Vector3.ZERO).y-8.883132934570312)<.002 and positive.get("normal",Vector3.ZERO).y>.7,str(positive))
	check("actualhotelRootmask stays physicallyopen",_ray(543.1836056341219,10.1438).is_empty())
	check("canonicalRainOculuswaterfootprint stays unsupported",_ray(404.5706593955882,175.586).is_empty())
	check("administrativesea outsidecoast doesnotbecome DEMland",_ray(1831.265432172604,-621.2843591141263).is_empty())
	var seam: Dictionary = _ray(1000,-900)
	check("shared source tileedge has actual native support",not seam.is_empty() and seam.get("normal",Vector3.ZERO).y>.7,str(seam))
	var l: Dictionary = _ray(999.99,-900)
	var r: Dictionary = _ray(1000.01,-900)
	check("no gap or step across tile seam",not l.is_empty() and not r.is_empty() and absf(l.get("position",Vector3.ZERO).y-r.get("position",Vector3.ZERO).y)<.02,str([l,r]))
	body = CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	add_child(body)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .36
	capsule.height = 1.75
	collision.shape = capsule
	collision.position = Vector3(0,.9,0)
	body.add_child(collision)
	body.position = Vector3(700,11.883132934570312,100)
	settle = true
	for i in 150: await get_tree().physics_frame
	check("actual native capsule rests on sourced groundmesh",body.is_on_floor() and absf(body.position.y-(8.883132934570312-.025))<.12 and absf(body.velocity.y)<.1,str(body.position))
	settle = false
	var denied: Dictionary = await terrain.retire_tile("0_-1")
	check("Rootcollision-retirement guard denies destruction",not denied.get("ok",false) and not terrain.collision_bodies("0_-1").is_empty())
	body.queue_free()
	for i in 3: await get_tree().physics_frame
	policy.allow_retire = true
	for key: String in keys:
		var old: Array = terrain.collision_bodies(key)
		var retired: Dictionary = await terrain.retire_tile(key)
		check("Rootapproved ownedterrain generation reaped "+key,retired.get("ok",false) and retired.get("owned_geometry_reaped",false) and terrain.collision_bodies(key).is_empty())
		for item in old: check("owned native terrainbodygone "+key,not is_instance_valid(item))
	metrics["terrain_metadata"] = terrain.metadata()
	metrics["scope"] = "Actual sourced DEM/coast/canonicalwater/Rootmask9tileArrayMesh+collision/nativecapsule/guard fixture; not current survey/MBSfloor/hydrology/Rootnormalbootstrap or visual/performanceacceptance"
	_finish()
func _finish() -> void:
	if finished: return
	finished = true
	settle = false
	var report := {"checks":checks,"failures":failures,"metrics":metrics}
	var f := FileAccess.open(report_path,FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report,"\t"))
		f.close()
	print("[terrain-scene] RESULT ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
