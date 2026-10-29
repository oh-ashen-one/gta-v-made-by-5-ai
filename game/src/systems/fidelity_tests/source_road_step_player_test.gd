extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Real production Player over separately visible source-step fixture geometry.
## Collision is the declared continuous walking incline, not step animation QA.
const Roads=preload("res://src/world/geography/source_roads.gd")
const Frame=preload("res://src/world/geography/source_frame.gd")
const TYPED_SHA="db2ba665dc60d9cf3f839f9dc1f8b1191cbf6d13bcb3573b172a9979cdf1477b"
var roads:RefCounted
var selected_direction:="up"
var feature_id:=""
var source_start:=Vector3.ZERO
var source_end:=Vector3.ZERO
var tread_indices:Dictionary={}
var source_supports:Dictionary={}
var route_samples:Array[Dictionary]=[]
var supported_ticks:=0
var route_ticks:=0
var started_ms:=0
var output:=""
var phase:="setup"
var spawns:=0

func _directory()->String:
	return ProjectSettings.globalize_path("res://").path_join("../loop/singapore-fidelity/source-roads/typed-physical-fixtures/native-contract-r1").simplify_path()

func _ready()->void:
	var args:=OS.get_cmdline_user_args();var at:=args.find("--qa-session")
	if at<0 or at+1>=args.size():get_tree().quit(2);return
	var folder:String=args[at+1]
	if folder.begins_with("/tmp/"):folder="/private/tmp/"+folder.trim_prefix("/tmp/")
	if not folder.begins_with("/private/tmp/singapore-fidelity/") or folder!=folder.simplify_path():get_tree().quit(2);return
	output=folder.path_join("typed-step-player.json")
	if FileAccess.file_exists(output) or DirAccess.make_dir_recursive_absolute(folder)!=OK:get_tree().quit(2);return
	at=args.find("--typed-step-direction")
	if at>=0 and at+1<args.size():selected_direction=args[at+1]
	if selected_direction not in ["up","down"]:get_tree().quit(2);return
	feature_id="fixture/steps_"+selected_direction
	started_ms=Time.get_ticks_msec()
	get_tree().create_timer(240.0,true,false,true).timeout.connect(func():
		if not finished:check("bounded real Player step route",false,"240s");finish())
	run.call_deferred()

func _sha(raw:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(raw);return h.finish().hex_encode()

func _v(a:Array)->Vector3:return Vector3(float(a[0]),float(a[1]),float(a[2]))

func _physics_process(delta:float)->void:
	super._physics_process(delta)
	if not tracking:return
	route_ticks+=1
	if player.is_on_floor():supported_ticks+=1
	var along:Vector3=source_end-source_start;along.y=0
	var point:Vector3=player.global_position-source_start;point.y=0
	var t:float=point.dot(along)/along.length_squared()
	tread_indices[clampi(int(floor(t*10.0)),0,9)]=true
	if route_ticks%6==0:
		var hit:Dictionary=ray(player.global_position+Vector3.UP*.10,player.global_position-Vector3.UP*.25)
		var source:Dictionary=roads.resolve_source_hit(hit)
		if source.get("ok",false):source_supports[source.source_way]=true
		route_samples.append({"phase":phase,"position":player.global_position,"velocity":player.velocity,"native_floor":player.is_on_floor(),"source_hit":source,"source_fraction":t})

func run()->void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	var raw:PackedByteArray=FileAccess.get_file_as_bytes("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest:Dictionary=JSON.parse_string(raw.get_string_from_utf8());var frame:=Frame.new()
	if not check("explicit uncompressed synthetic component frame",frame.configure(manifest.georeference,[0.0,0.0,0.0],_sha(raw))):finish();return
	roads=Roads.new()
	if not check("pinned typed component fixture",roads.configure(_directory(),TYPED_SHA,frame),roads.last_error):finish();return
	var prepared:Dictionary=roads.prepare_physical("fixture")
	if not check("typed walking geometry prepares",prepared.ok):finish();return
	var feature:Dictionary={}
	for row:Dictionary in prepared.plan.data.features:
		if row.id==feature_id:feature=row
	if not check("original declared ten-step visual source fixture exists",not feature.is_empty() and feature.source_tags.step_count=="10" and feature.physical_contract.surface_class=="foot_steps" and feature.has("visual_mesh")):finish();return
	var built:Dictionary=roads.build_physical(prepared.plan,self,null,{"collision_mode":"static_batches"})
	if not check("real visible tread and inclined walking meshes build",built.ok and built.visible_faces>built.collision_faces,str(built)):finish();return
	await frames(5)
	source_start=_v(feature.source_points_xyz[0]);source_end=_v(feature.source_points_xyz[-1])
	if not prepare_player():finish();return
	player.collision_layer=player_layer;player.collision_mask=mask;player.process_mode=Node.PROCESS_MODE_INHERIT;player.show()
	# Both disconnected fixture stairs are tested in separate fresh runs. The
	# capsule starts within the first tread and returns after the last tread;
	# no fake connecting bridge/platform or later relocation is introduced.
	var start:Vector3=source_start.lerp(source_end,.07)
	var target:Vector3=source_start.lerp(source_end,.93)
	player.respawn_at(start+Vector3.UP*.12,atan2(-(target-start).x,-(target-start).z));spawns+=1
	await frames(35)
	if not check("actual unchanged Player capsule rests on first real tread",player.is_on_floor(),str(player.global_position)):finish();return
	if DisplayServer.get_name()!="headless":_light_fixture()
	previous=player.global_position;travel=0;max_step=0;tracking=true
	walk_stage="native step fixture outward "+selected_direction;phase="outward"
	if not await walk_to(target,.12):finish();return
	var upper_or_lower:Vector3=player.global_position
	walk_stage="native step fixture reverse "+selected_direction;phase="return"
	if not await walk_to(start,.12):finish();return
	tracking=false
	check("all ten visible tread intervals visited through actual input",tread_indices.size()==10,str(tread_indices.keys()))
	check("native ray support never substituted another source surface",source_supports.size()==1 and source_supports.has(feature_id),str(source_supports))
	check("real Player walked both directions without death or teleport",travel>8.0 and max_step<.20 and Game.death_count==0 and supported_ticks>=int(route_ticks*.97),str({"travel":travel,"max_step":max_step,"supported":supported_ticks,"ticks":route_ticks}))
	check("actual source incline direction matches body height change",(upper_or_lower.y-start.y)>1.30 if selected_direction=="up" else (start.y-upper_or_lower.y)>1.30,str(upper_or_lower))
	finish()

func finish()->void:
	if finished:return
	finished=true;tracking=false;release_motion_input();Input.action_release("interact")
	var report:Dictionary={"schema":"typed_step_production_player_fixture_v1","source_feature":feature_id,"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-started_ms)/1000.0,"distance_m":travel,"max_step_m":max_step,"initial_spawns":spawns,"fixture_direct_pose_velocity_or_reparent_writes_after_setup":0,"supported_ticks":supported_ticks,"route_ticks":route_ticks,"tread_intervals":tread_indices.keys(),"native_source_supports":source_supports.keys(),"native_route_samples":route_samples,"collision_model":"declared continuous walking incline with separate actual visible treads and risers","synthetic_component_not_actual_country_route":true,"native_animation_foot_contacts_or_visual_quality_accepted":false}
	print("[typed-step-player] RESULT ",JSON.stringify(report,"",true,true))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
