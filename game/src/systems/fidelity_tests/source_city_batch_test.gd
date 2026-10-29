extends Node3D
## Exact triangle grouping/native source-hit identity fixture. Synthetic80km
## geometry plus one real source tile, not normal-game/visual/FPS acceptance.
const Scene = preload("res://src/world/geography/city_scene.gd")
const Tiles = preload("res://src/world/geography/runtimecity_tiles.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const FIXTURE := "res://data/geography/compiled-country/osm-2026-10-27/qa-fixture-v2"
const FIXTURE_ID := "4e8dcc308c104905c1d2b8c77ee6a37a6f6140d04da2ca9c9bd5ae10186dccc8"
const REAL := "/private/tmp/singapore-fidelity/city-geometry/candidate-r2"
const REAL_ID := "8b84896f8c9134b5933b2f6c3b036d025a1120d526ab12668e32181d4f148963"
const SNAPSHOT := "d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983"
const DEM := "5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var output := ""
var finished := false
var material := StandardMaterial3D.new()
var may_remove := false
var character: CharacterBody3D
var falling := false

func check(label: String,value: bool,detail: Variant = "") -> bool:
	checks += 1
	print("[city-batch] %s %s %s" % ["PASS" if value else "FAIL",label,str(detail)])
	if not value: failures.append(label)
	return value

func _material(_id: String,_role: String) -> Material: return material
func _retire(_key: String,_receipt: Dictionary) -> bool: return may_remove
func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(bytes); return h.finish().hex_encode()
func _safe(path: String) -> bool:
	if not path.begins_with("/private/tmp/singapore-fidelity/") or path!=path.simplify_path(): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/",false):
		var folder := DirAccess.open(parent)
		if folder!=null and folder.is_link(part): return false
		parent = parent.path_join(part)
	return true
func _ready() -> void:
	var args := OS.get_cmdline_user_args(); var at := args.find("--qa-session")
	if at<0 or at+1>=args.size(): get_tree().quit(2); return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	output = base.path_join("city-batch")
	if not _safe(output) or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output)!=OK: get_tree().quit(2); return
	get_tree().create_timer(180.0,true,false,true).timeout.connect(func():
		if not finished: check("bounded native city batch fixture",false,"180wall; Root outer240"); _finish())
	_run.call_deferred()
func _physics_process(delta: float) -> void:
	if falling and is_instance_valid(character):
		character.velocity.y -= 9.8*delta
		character.move_and_slide()
func _frames(count: int) -> void:
	for i in count: await get_tree().physics_frame
func _ray(a: Vector3,b: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
func _new(frame: RefCounted,identity: String,options: Dictionary = {}) -> Node3D:
	var scene := Scene.new(); add_child(scene)
	if not scene.configure(frame,_material,_retire,2,1,{"geometry_identity_sha256":identity,"snapshot_manifest_sha256":frame.metadata().snapshot_manifest_sha256},options):
		scene.queue_free(); return null
	return scene
func _visuals(scene: Node3D,key: String) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in scene._tiles[key].node.get_children():
		if not child is MeshInstance3D: continue
		var data: Array = []
		for index in child.mesh.get_surface_count():
			data.append({"arrays":child.mesh.surface_get_arrays(index),"material_id":child.mesh.surface_get_material(index).get_instance_id()})
		result[child.get_meta("source_fragment_id")] = _sha(var_to_bytes(data))
	return result
func _faces(scene: Node3D,key: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	for body: StaticBody3D in scene.collision_bodies(key):
		for child: Node in body.get_children():
			if child is CollisionShape3D and child.shape is ConcavePolygonShape3D: result.append_array(child.shape.get_faces())
	return result
func _expect(scene: Node3D,label: String,a: Vector3,b: Vector3,feature: String,fragment: String = "") -> Dictionary:
	var hit: Dictionary = _ray(a,b)
	var source: Dictionary = scene.resolve_source_hit(hit)
	check("native shape/face index resolves original source "+label,not hit.is_empty() and hit.get("face_index",-1)>=0 and source.get("ok",false) and source.feature_id==feature and (fragment.is_empty() or source.fragment_id==fragment),{"hit":hit,"resolved":source})
	return hit
func _retire_all(scene: Node3D,keys: Array) -> bool:
	may_remove = true
	for key: String in keys:
		var retired: Dictionary = await scene.retire_tile(key)
		if not check("owned collision generation retires "+key,retired.get("ok",false) and retired.owned_geometry_reaped,retired): return false
	scene.queue_free(); await _frames(3)
	return true

func _run() -> void:
	var policy := {"mode":Tiles.YMODE,"offset_m":0.0}
	var provider := Tiles.new()
	if not check("verified triangle fixture opens",provider.configure(FIXTURE,FIXTURE_ID,"a".repeat(64),"b".repeat(64),policy,2),provider.last_error): _finish(); return
	var frame := Frame.new(); frame.configure(Frame.EXPECTED_FRAME,[80000,0,80000],"a".repeat(64))
	var legacy: Node3D = _new(frame,FIXTURE_ID)
	if not check("default per-feature mode configures unchanged",is_instance_valid(legacy)): _finish(); return
	var committed: Dictionary = await legacy.install_tile(provider.tile(80,80))
	if not check("default collision remains two original bodies",committed.get("ok",false) and committed.receipt.collision_mode=="per_feature" and legacy.collision_bodies("80_80").size()==2,committed): _finish(); return
	var baseline_faces: PackedVector3Array = _faces(legacy,"80_80")
	var baseline_visuals: Dictionary = _visuals(legacy,"80_80")
	var old_hit: Dictionary = _ray(Vector3(3,25,3),Vector3(3,-5,3))
	check("default original collider metadata retained",not old_hit.is_empty() and old_hit.collider.get_meta("source_feature_id")=="building|way/10001")
	if not await _retire_all(legacy,["80_80"]): _finish(); return

	var batch: Node3D = _new(frame,FIXTURE_ID,{"collision_mode":"static_batches","faces_per_frame":128})
	if not check("explicit collision batching configures",is_instance_valid(batch)): _finish(); return
	var duplicate: Dictionary = provider.tile(80,80); duplicate.features.append(duplicate.features[0].duplicate(true))
	var refused_duplicate: Dictionary = await batch.install_tile(duplicate)
	check("duplicate source fragment discards pending batch generation",not refused_duplicate.get("ok",false) and refused_duplicate.get("owned_partial_geometry_reaped",false) and batch.get_child_count()==0,refused_duplicate)
	var foreign: Dictionary = provider.tile(80,80); foreign.identity_sha256 = "f".repeat(64)
	check("batched foreign identity rejects before construction",not (await batch.install_tile(foreign)).get("ok",false) and batch.get_child_count()==0)
	for tx in [80,81]:
		committed = await batch.install_tile(provider.tile(tx,80))
		if not check("batched exact native tile commits "+str(tx),committed.get("ok",false),committed): _finish(); return
	check("two logical sources share one native shape/body without loss",batch.collision_bodies("80_80").size()==1 and batch.tile_receipt("80_80").feature_count==2 and batch.tile_receipt("80_80").triangles==42)
	check("collision triangle triples byte-equal original trimeshes",_faces(batch,"80_80")==baseline_faces)
	check("all visual vertices normals UVs indices and materials unchanged",_visuals(batch,"80_80")==baseline_visuals)
	var roof: Dictionary = _expect(batch,"courtyard roof",Vector3(3,25,3),Vector3(3,-5,3),"building|way/10001","building|way/10001@80_80")
	check("batched roof has unchanged native height/normal",not roof.is_empty() and absf(roof.position.y-12.0)<.001 and roof.normal.y>.95)
	check("exact courtyard hole is not filled by batching",_ray(Vector3(7,25,7),Vector3(7,-5,7)).is_empty())
	var exterior: Dictionary = _expect(batch,"outer wall",Vector3(1,6,3),Vector3(4,6,3),"building|way/10001")
	check("outer wall winding stays outward",not exterior.is_empty() and exterior.normal.x<-.95)
	var courtyard: Dictionary = _expect(batch,"inner wall",Vector3(7,6,7),Vector3(4,6,7),"building|way/10001")
	check("courtyard wall winding stays toward void",not courtyard.is_empty() and courtyard.normal.x>.95)
	var underside: Dictionary = _expect(batch,"underside",Vector3(3,-2,3),Vector3(3,2,3),"building|way/10001")
	check("underside winding stays downward",not underside.is_empty() and underside.normal.y<-.95)
	_expect(batch,"second feature same concave shape",Vector3(998,25,30),Vector3(998,-5,30),"building|way/10002","building|way/10002@80_80")
	_expect(batch,"same source across real tile seam",Vector3(1005,25,30),Vector3(1005,-5,30),"building|way/10002","building|way/10002@81_80")
	check("batching adds no artificial seam wall",_ray(Vector3(999,5,30),Vector3(1001,5,30)).is_empty())
	var malformed: Dictionary = roof.duplicate(); malformed.shape = "0"
	check("malformed native shape index never invents source",not batch.resolve_source_hit(malformed).get("ok",false))
	malformed = roof.duplicate(); malformed.face_index = -1
	check("ambiguous missing native face index fails closed",not batch.resolve_source_hit(malformed).get("ok",false))
	malformed = roof.duplicate(); malformed.face_index = 1000000
	check("out-of-range native face index fails closed",not batch.resolve_source_hit(malformed).get("ok",false))
	var foreign_body := StaticBody3D.new(); add_child(foreign_body)
	check("foreign body cannot resolve as source city",not batch.resolve_source_hit({"collider":foreign_body,"shape":0,"face_index":0}).get("ok",false)); foreign_body.queue_free()
	may_remove = false
	check("retirement guard preserves batched native support",not (await batch.retire_tile("80_80")).get("ok",false) and not _ray(Vector3(3,25,3),Vector3(3,-5,3)).is_empty())
	character = CharacterBody3D.new(); character.collision_layer = 2; character.collision_mask = 1
	var capsule_node := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = .36; capsule.height = 1.75; capsule_node.shape = capsule; capsule_node.position.y = .9
	character.add_child(capsule_node); character.position = Vector3(3,15,3); add_child(character); falling = true
	var quiet := 0
	for index in 150:
		await get_tree().physics_frame
		quiet = quiet+1 if character.is_on_floor() and character.velocity.length()<=.12 else 0
		if quiet>=3: break
	falling = false
	check("actual native capsule settles on exact batched roof",quiet>=3 and absf(character.global_position.y+.025-12.0)<.005,{"root_y":character.global_position.y,"capsule_bottom_y":character.global_position.y+.025,"on_floor":character.is_on_floor()})
	character.queue_free(); await _frames(3)
	metrics["synthetic_batch_receipt"] = batch.tile_receipt("80_80")
	may_remove = true
	var retired: Dictionary = await batch.retire_tile("80_80")
	check("retired native hit cannot resolve within live installer",retired.get("ok",false) and not batch.resolve_source_hit(roof).get("ok",false) and _ray(Vector3(3,25,3),Vector3(3,-5,3)).is_empty(),retired)
	_expect(batch,"neighbor survives another tile retirement",Vector3(1005,25,30),Vector3(1005,-5,30),"building|way/10002")
	if not await _retire_all(batch,["81_80"]): _finish(); return

	# Deliberately tiny explicit batch limit exercises feature splitting/ranges,
	# not a recommended production setting or claimed body reduction.
	var split: Node3D = _new(frame,FIXTURE_ID,{"collision_mode":"static_batches","faces_per_body":8,"faces_per_frame":128})
	committed = await split.install_tile(provider.tile(80,80))
	if not check("one original feature may span bounded exact batches",committed.get("ok",false) and split.collision_bodies("80_80").size()==6,committed): _finish(); return
	check("bounded batch split preserves every triangle triple",_faces(split,"80_80")==baseline_faces)
	var split_hit: Dictionary = _expect(split,"split feature source identity",Vector3(3,25,3),Vector3(3,-5,3),"building|way/10001")
	_expect(split,"split neighbor source identity",Vector3(998,25,30),Vector3(998,-5,30),"building|way/10002")
	var changed_origin: Dictionary = frame.prepare_rebase([80512,0,80000])
	check("actor-free fixture source origin commits explicitly",changed_origin.get("ok",false) and frame.commit_rebase(changed_origin.plan))
	check("committed old-origin hit cannot resolve as current source",not split.resolve_source_hit(split_hit).get("ok",false))
	if not await _retire_all(split,["80_80"]): _finish(); return
	# Actor-free origin change during a bounded yield must discard every partial
	# batch and publish no source-hit map. No real game frame is rebased here.
	var epoch_frame := Frame.new(); epoch_frame.configure(Frame.EXPECTED_FRAME,[80000,0,80000],"a".repeat(64))
	var epoch: Node3D = _new(epoch_frame,FIXTURE_ID,{"collision_mode":"static_batches"})
	var rebase_once: Callable = func() -> void:
		var plan: Dictionary = epoch_frame.prepare_rebase([80512,0,80000])
		if plan.get("ok",false): epoch_frame.commit_rebase(plan.plan)
	get_tree().process_frame.connect(rebase_once,CONNECT_ONE_SHOT)
	var invalidated: Dictionary = await epoch.install_tile(provider.tile(80,80))
	check("source epoch change discards uncommitted batches",not invalidated.get("ok",false) and invalidated.get("owned_partial_geometry_reaped",false) and epoch.get_child_count()==0 and epoch.collision_bodies("80_80").is_empty(),invalidated)
	epoch.queue_free(); await _frames(3)
	await _real_source_tile()
	_finish()

func _real_source_tile() -> void:
	var provider := Tiles.new(); var policy := {"mode":Tiles.YMODE,"offset_m":0.0}
	if not check("actual immutable country geometry opens",provider.configure(REAL,REAL_ID,SNAPSHOT,DEM,policy,2),provider.last_error): return
	var frame := Frame.new(); frame.configure(Frame.EXPECTED_FRAME,[0,0,-1000],SNAPSHOT,{"status":"source_tag","reference":Tiles.YMODE})
	var limited: Node3D = _new(frame,REAL_ID,{"collision_mode":"static_batches","maximum_collision_faces_per_tile":128})
	var limited_tile: Dictionary = provider.tile(0,-1)
	if not check("actual source tile decodes before bounded scene work",limited_tile.get("ok",false),limited_tile.get("reason","")): return
	var refused: Dictionary = await limited.install_tile(limited_tile)
	check("explicit collision work bound rejects before scene allocation",not refused.get("ok",false) and limited.get_child_count()==0,refused)
	limited.queue_free(); await _frames(2)
	var scene: Node3D = _new(frame,REAL_ID,{"collision_mode":"static_batches"})
	if not check("actual city batch scene configures",is_instance_valid(scene)): return
	var tile: Dictionary = provider.tile(0,-1)
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = await scene.install_tile(tile)
	if not check("actual source city tile natively commits batches",result.get("ok",false),result): return
	check("actual source body count falls without omitted features",result.receipt.feature_count==tile.features.size() and scene.collision_bodies("0_-1").size()<tile.features.size() and result.receipt.triangles>0,result.receipt)
	check("all actual source triangles exist in native concave arrays",_faces(scene,"0_-1").size()/3==result.receipt.triangles)
	var resolved := 0; var overlaps: Array[Dictionary] = []
	var projection: Dictionary = frame.to_local(tile.anchor_source_xyz)
	for feature: Dictionary in tile.features:
		if resolved>=4: break
		for surface: Dictionary in feature.surfaces:
			if surface.role!="roof": continue
			var vertices: PackedVector3Array = surface.arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = surface.arrays[Mesh.ARRAY_INDEX]
			var point: Vector3 = projection.position+(vertices[indices[0]]+vertices[indices[1]]+vertices[indices[2]])/3.0
			var hit: Dictionary = _ray(point+Vector3.UP*.10,point-Vector3.UP*.10)
			var source: Dictionary = scene.resolve_source_hit(hit)
			if source.get("ok",false) and source.feature_id==feature.feature_key and source.fragment_id==feature.fragment_key:
				resolved += 1
				check("real source native face resolves original feature "+feature.feature_key,source.geometry_identity_sha256==REAL_ID and source.logical_feature_source_sha256==feature.logical_feature_source_sha256,source)
			else: overlaps.append({"seed_feature":feature.feature_key,"hit":source})
			break
	check("multiple actual source feature rays resolve unambiguously",resolved>=4,{"resolved":resolved,"overlap_or_unhit_seeds":overlaps})
	metrics["real_source_tile"] = {"receipt":result.receipt,"native_feature_probes":resolved,"overlap_or_unhit_seeds":overlaps,"wall_us_including_native_commit":Time.get_ticks_usec()-started,"not_performance_acceptance":true}
	await _retire_all(scene,["0_-1"])

func _finish() -> void:
	if finished: return
	finished = true; falling = false
	var path: String = output.path_join("report.json")
	if not _safe(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path): get_tree().quit(2); return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: get_tree().quit(2); return
	file.store_string(JSON.stringify({"schema":"source_city_native_batch_fixture_v1","checks":checks,"failed":failures.size(),"failures":failures,"metrics":metrics,"visual_data_parity_not_render_acceptance":true,"full_world_player_and_performance_acceptance":false},"\t",true,true)); file.close()
	print("[city-batch] FINISHED checks=%d failed=%d" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
