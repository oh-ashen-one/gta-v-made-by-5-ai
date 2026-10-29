extends Node3D
## Native transition fixture, not MBS as-built geometry. The guard uses exact
## Root source masks; these two small slabs deliberately model lifecycle only.
const Guard = preload("res://src/world/geography/source_world_guard.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
const MASKS := "9d91185dab9c936316b1397a7faad778556b28fb29e44f01f03b4fe04d498625"
const DOMAIN := "82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834"
const EDGE_A := [552.3119,-951.7166]
const EDGE_B := [581.8681,-994.5531]
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var finished := false
var runtime: Node3D
var player: Player
var frame: RefCounted
var context: RefCounted
var domain: RefCounted
var inside_native_ready := false
var assessment_state := "required"
var normal := Vector3.ZERO
var origin: Array = []

func _hash(text: String) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
	hash.update(text.to_utf8_buffer()); return hash.finish().hex_encode()

func check(label: String, value: bool, detail: Variant = "") -> bool:
	checks += 1
	print("[source-world-guard] %s %s %s" % ["PASS" if value else "FAIL",label,str(detail)])
	if not value: failures.append(label)
	return value

func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path!=path.simplify_path(): return false
	var current := "/private/tmp"
	for segment in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(current)
		if folder!=null and folder.is_link(segment): return false
		current = current.path_join(segment)
	return true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at<0 or at+1>=args.size(): get_tree().quit(2); return
	var path: String = args[at+1]
	if path.begins_with("/tmp/"): path = "/private/tmp/"+path.trim_prefix("/tmp/")
	output = path.path_join("source-world-guard")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: get_tree().quit(2); return
	get_tree().create_timer(60.0,true,false,true).timeout.connect(func():
		if not finished: check("bounded guard fixture",false); _finish())
	_run.call_deferred()

func assessment(_mask: String,_source: Array,_actor: CharacterBody3D) -> Dictionary:
	return {"state":assessment_state,"floor_ids":["qa-only-required-interior"],"ready":inside_native_ready,"provenance":"QA lifecycle mapping on exact source mask; synthetic slab is NOT a real MBS floor"}

func _source(local: Vector3) -> Array:
	return [float(origin[0])+float(local.x),float(local.y),float(origin[2])+float(local.z)]

func _slab(side: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "QAExterior" if side>0 else "QARequiredInterior"
	body.collision_layer = 1
	body.basis = Basis(Vector3(normal.z,0,-normal.x),Vector3.UP,normal)
	body.position = normal*(side*2.0)+Vector3(0,-.15,0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(10,.30,4)
	collision.shape = box; body.add_child(collision); add_child(body)
	return body

func _register(label: String,body: StaticBody3D) -> bool:
	var definition := {"feature_id":"qa-only/"+label,"floor_id":"staged-ground","geometry_sha256":_hash("QA-synthetic-native-slab-"+label),"support_ids":[label],"volumes":[{"volume_id":"nondry-test-support-identity","min_xyz":_source(Vector3(-10,-1,-10)),"max_xyz":_source(Vector3(10,3,10)),"dry":false}],"provenance":"Synthetic lifecycle fixture, not actual MBS slab, measured floor or dryland"}
	if not context.register_floor(definition): return false
	return runtime.commit_region("qa-only/"+label,_source(Vector3(-10,-10,-10)),_source(Vector3(10,10,10)),[body],[{"body":body,"feature_id":"qa-only/"+label,"floor_id":"staged-ground","support_id":label}])

func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _run() -> void:
	Game.simulation_paused = true
	origin = [(EDGE_A[0]+EDGE_B[0])*.5,0.0,(EDGE_A[1]+EDGE_B[1])*.5]
	frame = Frame.new()
	if not check("source metre frame binds exact T1 source edge",frame.configure(Frame.EXPECTED_FRAME,origin,SNAPSHOT)): _finish(); return
	context = Context.new()
	var profile := {"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("same native context configures",context.configure(frame,_hash("QA-source-guard-slabs"),_hash("QA-staging-Y0-not-MBSdatum"),profile,get_world_3d())): _finish(); return
	domain = Domain.new()
	if not check("actual country/coast identity opens",domain.configure("res://data/geography/domain/osm-2026-10-27",DOMAIN,SNAPSHOT)): _finish(); return
	for descriptor: Dictionary in domain.provider_descriptors(): context.register_provider(descriptor.kind,descriptor.provider_id,descriptor.source_reference)
	context.register_provider("physics","qa-native-guard","Native fixture collision only, not MBS physical source survey")
	runtime = Guard.new(); add_child(runtime)
	if not check("guard runtime configures actual common frame",runtime.configure(frame,context,domain.observe)): _finish(); return
	check("wrong source-mask hash fails closed",not runtime.configure_architecture("res://data/geography/mbs-root-holes.json","0".repeat(64),assessment))
	if not check("verified source mask guard configures",runtime.configure_architecture("res://data/geography/mbs-root-holes.json",MASKS,assessment),runtime.guard_configuration_error): _finish(); return
	var source_types: Dictionary = {}
	for actual_mask: Dictionary in runtime._masks:
		source_types[actual_mask.source_geometry_type] = int(source_types.get(actual_mask.source_geometry_type,0))+1
	check("all exact OSM and Root constructed mask geometry types retained",runtime._masks.size()==5 and source_types.get("MultiPolygon")==4 and source_types.get("Polygon")==1,source_types)
	var mask: Dictionary = runtime._masks[0]
	for candidate: Dictionary in runtime._masks:
		if candidate.mask_id=="source-foundation/way/116801004": mask = candidate
	var edge := Vector2(EDGE_B[0]-EDGE_A[0],EDGE_B[1]-EDGE_A[1]).normalized()
	normal = Vector3(-edge.y,0,edge.x)
	if runtime._contains(_source(normal),mask): normal = -normal
	check("exact original edge separates inside and outside",not runtime._contains(_source(normal),mask) and runtime._contains(_source(-normal),mask))
	var exterior := _slab(1.0)
	await _frames(4)
	if not check("actual exterior collider commits before player",_register("exterior",exterior)): _finish(); return
	player = Player.new()
	player.position = normal*2.0+Vector3.UP*.05
	player.uses_source_world = true; player.source_world_runtime = runtime
	player.yaw = atan2(normal.x,normal.z)
	add_child(player)
	if not check("actual production player binds",runtime.bind_player(player)): _finish(); return
	Game.simulation_paused = false
	await _frames(70)
	var initial: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _frames(150)
	Input.action_release("move_forward")
	await _frames(5)
	var held: Vector3 = player.global_position
	metrics["before_commit"] = {"edge_side_m":held.dot(normal),"walked_m":held.distance_to(initial),"y":held.y,"guard":runtime.architecture_guard_metadata()}
	check("player walks continuously to unloaded architecture boundary",held.distance_to(initial)>1.0 and held.dot(normal)>=-.02,metrics.before_commit)
	check("missing planned floor is held rather than fallen through",held.y>-.02 and runtime.last_transition.get("assessment",{}).get("state")=="required",metrics.before_commit)
	var inside_ray := PhysicsRayQueryParameters3D.create(-normal*2.0+Vector3.UP*3.0,-normal*2.0-Vector3.UP*2.0,1)
	check("guard did not fabricate the missing interior support",get_world_3d().direct_space_state.intersect_ray(inside_ray).is_empty())
	assessment_state = "known_physical_void"
	check("explicit known physical void is not relabeled unloaded",runtime._assessed(_source(normal),_source(-normal),player))
	check("known void assessment does not add a floor",get_world_3d().direct_space_state.intersect_ray(inside_ray).is_empty())
	assessment_state = "required"
	var interior := _slab(-1.0)
	await _frames(4)
	if not check("real interior collision commits before release",_register("interior",interior)): _finish(); return
	inside_native_ready = PhysicsServer3D.body_get_space(interior.get_rid())==get_world_3d().space and PhysicsServer3D.body_get_shape_count(interior.get_rid())>0
	Input.action_press("move_forward")
	var crossed := false
	for i in 120:
		await get_tree().physics_frame
		if player.global_position.dot(normal)<-1.2: crossed = true; break
	Input.action_release("move_forward")
	await _frames(10)
	var final: Dictionary = runtime.inspect_player(player)
	metrics["after_commit"] = {"edge_side_m":player.global_position.dot(normal),"y":player.global_position.y,"state":final,"teleports":0,"guard":runtime.architecture_guard_metadata()}
	check("same player continuously crosses after actual native commit",crossed and player.global_position.y>-.02,metrics.after_commit)
	check("crossed player has actual new-floor support",final.get("ok",false) and final.support.state=="supported" and final.support.feature_id=="qa-only/interior",final)
	check("outdoor source water remains unresolved",final.get("ok",false) and final.water.state=="unknown" and final.land.state=="unknown")
	check("mask identity retained in transition receipt",runtime.architecture_guard_metadata().root_masks_sha256==MASKS)
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	if InputMap.has_action("move_forward"): Input.action_release("move_forward")
	Game.simulation_paused = true
	var file_path := output.path_join("report.json")
	if not _safe(file_path) or FileAccess.file_exists(file_path) or DirAccess.dir_exists_absolute(file_path): get_tree().quit(2); return
	var file := FileAccess.open(file_path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify({"schema":"source_world_guard_native_lifecycle_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"exact_root_masks_sha256":MASKS,"synthetic_slabs_not_MBS_as_built":true,"visual_or_whole_world_acceptance":false},"\t")); file.close()
	get_tree().quit(0 if failures.is_empty() else 1)
