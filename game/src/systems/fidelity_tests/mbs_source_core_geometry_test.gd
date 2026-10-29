extends "res://src/systems/fidelity_tests/mbs_guest_floor_test.gd"
## Root-run actual source-core physics. Three bounded core modules, not rooms,
## full hotel or city acceptance. Production Player walks every route segment.
const Core = preload("res://src/world/mbs_interior/source_core_geometry.gd")
const CoreLayout = preload("res://src/world/mbs_interior/source_core_layout.gd")
const SourceGates = preload("res://src/world/mbs_interior/source_stair_gates.gd")
const Partial = preload("res://src/world/mbs_interior/partial_mezzanine.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Exterior = preload("res://src/world/mbs_interior/exterior_shell.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Context = preload("res://src/world/geography/source_world_context.gd")
const Runtime = preload("res://src/world/geography/source_runtime.gd")
const Domain = preload("res://src/world/geography/source_domain.gd")
const FEATURE := "mbs/source-core-native-fixture"
const WALL_SECONDS := 720.0

class CoreFloor extends Node3D:
	const Geometry = preload("res://src/world/mbs_interior/source_core_geometry.gd")
	const MeshKit = preload("res://src/world/downtown/landmarks/kit.gd")
	var floor_record: Dictionary = {}
	var construction: Dictionary = {}
	var portals: Array = []
	var source_core_schema: String = Geometry.SCHEMA
	var _built := false
	var structure: StaticBody3D
	func build(record: Dictionary) -> Dictionary:
		if _built: return {"built":false,"error":"Core fixture already built"}
		floor_record = record.duplicate(true)
		construction = Geometry.plan(floor_record)
		if not construction.get("valid",false): return {"built":false,"error":construction.get("error","")}
		var kit = MeshKit.new(self,"OwnedSourceCoreStructure")
		var result: Dictionary = Geometry.append_to_kit(kit,construction)
		if not result.get("built",false): return result
		kit.commit(self,"ActualSourceCoreMaterials",true)
		structure = kit.body
		portals = result.portals.duplicate(true)
		_built = true
		return result

var frame: RefCounted
var context: RefCounted
var runtime: Node3D
var domain: RefCounted
var gates: Node3D
var modules: Dictionary = {}
var source_tower: Dictionary = {}
var tower_basis := Basis.IDENTITY
var selected_variant := "normal"
var levels: Array[String] = []
var generations: Dictionary = {}
var regions_committed := false
var started_ms := 0
var evidence: Dictionary = {}
var native_actions: Array[Dictionary] = []
var actor_spawns := 0
var output := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at<0 or at+1>=args.size(): get_tree().quit(2); return
	var base: String = args[at+1]
	if base.begins_with("/tmp/"): base = "/private/tmp/"+base.trim_prefix("/tmp/")
	if not base.begins_with("/private/tmp/singapore-fidelity/") or base!=base.simplify_path(): get_tree().quit(2); return
	output = base.path_join("source-core-geometry.json")
	if FileAccess.file_exists(output): get_tree().quit(2); return
	if DirAccess.make_dir_recursive_absolute(base)!=OK: get_tree().quit(2); return
	var variant := args.find("--source-core-variant")
	if variant>=0 and variant+1<args.size(): selected_variant=args[variant+1]
	if selected_variant not in ["normal","low"]: get_tree().quit(2); return
	started_ms=Time.get_ticks_msec()
	get_tree().create_timer(WALL_SECONDS,true,false,true).timeout.connect(func():
		if not finished: check("bounded actual source core route",false,str(WALL_SECONDS));finish())
	run.call_deferred()

func _hash(value: String) -> String:
	var h := HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(value.to_utf8_buffer());return h.finish().hex_encode()

func _record(id: String,top: bool=false) -> Dictionary:
	var record: Dictionary = Inventory.floor_record(id).duplicate(true)
	if id.ends_with("-B2") or id.ends_with("-B2M"):
		var planned: Dictionary = Partial.plan(record)
		if not planned.get("valid",false): return {}
		record.geometry = planned.geometry.duplicate(true)
	elif id.ends_with("-B1"):
		record.geometry.storey_height_m=5.0
	# This is a bounded three-core fixture. The top module supplies the next
	# real slab/landing, without pretending that its further floors are built.
	record.has_upper_floor=not top
	record.has_lower_floor=true
	return record

func _canonical(record: Dictionary,own: Vector3) -> Array:
	var centre: Array = source_tower.centroid_world_xz
	var p: Vector3 = tower_basis*own
	return [float(centre[0])+float(p.x),float(record.elevation_m)+float(own.y),float(centre[1])+float(p.z)]

func _source_volume(record: Dictionary,label: String,pose: Transform3D,centre: Vector3,half: Vector3) -> Dictionary:
	var local: Vector3 = pose*centre
	var basis: Basis = tower_basis*pose.basis
	return {"schema":Context.OBOX_SCHEMA,"volume_id":label,"center_xyz":_canonical(record,local),"half_extents_xyz":[float(half.x),float(half.y),float(half.z)],"axis_x_xyz":[float(basis.x.x),0.0,float(basis.x.z)],"axis_z_xyz":[float(basis.z.x),0.0,float(basis.z.z)],"dry":true}

func _collect(node: Node,bodies: Array) -> void:
	if node is CollisionObject3D and node.collision_layer!=0: bodies.append(node)
	for child: Node in node.get_children(): _collect(child,bodies)

func _native_hall(module: CoreFloor) -> bool:
	if not is_instance_valid(module) or not module._built or module.structure.collision_layer==0: return false
	var point: Vector3 = module.to_global(_hall(module,0.0))
	var hit: Dictionary = ray(point+Vector3.UP*.15,point-Vector3.UP*.25)
	return not hit.is_empty() and hit.collider==module.structure and absf((hit.position as Vector3).y-point.y)<.015

func _provider(id: String) -> Dictionary:
	if not modules.has(id): return {"floor_id":id,"ready":false,"collision_generation":""}
	var module: CoreFloor = modules[id]
	var physical: bool = _native_hall(module)
	var live: bool = regions_committed and runtime.region_status("source-core/"+id).get("live",false)
	return {"floor_id":id,"ready":physical and live,"collision_generation":generations.get(id,"") if physical else "","receiving_door_height_m":module.floor_record.geometry.get("core_door_height_m",2.35),"receiving_clear_height_m":module.floor_record.geometry.clear_height_m}

func _register() -> bool:
	var bodies: Array=[]
	for module: CoreFloor in modules.values(): _collect(module,bodies)
	for id: String in levels:
		var module: CoreFloor=modules[id];var record: Dictionary=module.floor_record
		var volumes: Array=[];var clear: float=record.geometry.clear_height_m
		for index in module.construction.slab_cells.size():
			var b: Array=module.construction.slab_cells[index].bounds_xz
			volumes.append(_source_volume(record,"slab-air/"+str(index),Transform3D.IDENTITY,Vector3((b[0]+b[2])*.5,clear*.5-.10,(b[1]+b[3])*.5),Vector3((b[2]-b[0])*.5,clear*.5+.15,(b[3]-b[1])*.5)))
		for port: Dictionary in module.construction.stair_ports:
			var pose: Transform3D=port.source_core_local_pose
			volumes.append(_source_volume(record,port.source_core_alias+"/actual-stair-air",pose,Vector3(0,float(module.construction.rise_m)*.5+1.0,2.55),Vector3(1.60,float(module.construction.rise_m)*.5+1.25,2.55)))
		var definition: Dictionary={"feature_id":FEATURE,"floor_id":id,"geometry_sha256":_hash(JSON.stringify(module.construction,"",true,true)),"support_ids":["owned-core-structure"],"volumes":volumes,"provenance":"Bounded actual source-core geometry; source tower axes and reconstructed inventory heights, not full rooms/hotel or surveyed interiors."}
		if not check("precise actual slab/stair architecture registers "+id,context.register_floor(definition),context.last_error): return false
		var bank: Array=module.construction.bank_bounds_xz
		var minimum: Array=[INF,INF,INF];var maximum: Array=[-INF,-INF,-INF]
		for x: float in [float(bank[0])-2.0,float(bank[2])+2.0]:
			for z: float in [float(bank[1])-2.0,float(bank[3])+2.0]:
				for y: float in [-3.0,float(module.construction.rise_m)+3.0]:
					var point: Array=_canonical(record,Vector3(x,y,z))
					for axis in 3: minimum[axis]=minf(minimum[axis],point[axis]);maximum[axis]=maxf(maximum[axis],point[axis])
		if not check("complete three-core body/door union commits "+id,runtime.commit_region("source-core/"+id,minimum,maximum,bodies,[{"body":module.structure,"feature_id":FEATURE,"floor_id":id,"support_id":"owned-core-structure"}]),runtime.last_error): return false
	regions_committed=true
	return true

func _hall(module: CoreFloor,x: float) -> Vector3:
	return Vector3(x,0,float(module.construction.core_layout.own_center_xz[1])-2.20)

func _port(module: CoreFloor,wing: String) -> Dictionary:
	for port: Dictionary in module.portals:
		if port.kind=="stair" and port.wing==wing:return port
	return {}

func _gate(owner: String,wing: String) -> Dictionary:
	for gate: Dictionary in gates.geometry_descriptor(owner).get("gates",[]):
		if gate.wing==wing and gate.lane=="upper_return":return gate
	return {}

func _point(module: CoreFloor,port: Dictionary,local: Vector3) -> Vector3:
	return module.to_global((port.source_core_local_pose as Transform3D)*local)

func _native_geometry() -> bool:
	for id: String in levels:
		var module: CoreFloor=modules[id]
		check("actual hall supported by owning floor "+id,_native_hall(module))
		var bank: Array=module.construction.bank_bounds_xz
		var area: float=(float(bank[2])-float(bank[0]))*(float(bank[3])-float(bank[1]))
		check("exact core slab partition area "+id,absf(module.construction.slab_support_area_m2+module.construction.slab_cut_area_m2-area)<.0001)
		for hole: Dictionary in module.construction.cutouts:
			if hole.kind!="continuous_lift_shaft":continue
			var b: Array=hole.bounds_xz;var centre:=Vector3((b[0]+b[2])*.5,0,(b[1]+b[3])*.5)
			check("real shaft void is not a slab plug "+id+"/"+hole.id,ray(module.to_global(centre+Vector3.UP*.05),module.to_global(centre-Vector3.UP*.30)).is_empty())
		for port: Dictionary in module.construction.stair_ports:
			var pose: Transform3D=port.source_core_local_pose
			var hole_point: Vector3=pose*Vector3(-.78,0,2.55)
			check("incoming stair slab aperture stays physically open "+id+"/"+port.wing,ray(module.to_global(hole_point+Vector3.UP*.05),module.to_global(hole_point-Vector3.UP*.30)).is_empty())
	for index in range(levels.size()-1):
		var lower: CoreFloor=modules[levels[index]];var upper: CoreFloor=modules[levels[index+1]]
		for port: Dictionary in lower.construction.stair_ports:
			var top: Vector3=_point(lower,port,Vector3(.78,lower.construction.rise_m,.60))
			var hit: Dictionary=ray(top+Vector3.UP*.05,top-Vector3.UP*.30)
			check("upper arrival support belongs to actual receiving floor "+String(lower.floor_record.id)+"/"+port.wing,not hit.is_empty() and hit.collider==upper.structure,str(hit.get("collider")))
			var probe:=PhysicsShapeQueryParameters3D.new();var sphere:=SphereShape3D.new();sphere.radius=.01
			probe.shape=sphere;probe.transform=Transform3D(Basis.IDENTITY,top-Vector3.UP*.10);probe.collision_mask=1;probe.margin=0.0
			var contacts:Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(probe,16)
			check("single receiver-owned landing has no duplicate lower platform "+String(lower.floor_record.id)+"/"+port.wing,contacts.size()==1 and contacts[0].collider==upper.structure,str(contacts.size()))
			for stage in 2:
				var height:float=float(lower.construction.rise_m)*(.25 if stage==0 else .75)
				var flight:Vector3=_point(lower,port,Vector3(-.78 if stage==0 else .78,height,Core.LANDING+Core.RUN*.5))
				var slope_hit:Dictionary=ray(flight+Vector3.UP*.08,flight-Vector3.UP*.12)
				check("both rotated real ramp faces return upward native support "+String(lower.floor_record.id)+"/"+port.wing+"/"+str(stage),not slope_hit.is_empty() and slope_hit.collider==lower.structure and slope_hit.normal.y>cos(deg_to_rad(52.0)) and absf((slope_hit.position as Vector3).y-flight.y)<.015,str(slope_hit.get("normal",Vector3.ZERO)))
	return failures.is_empty()

func _closed_guards() -> bool:
	var owner:CoreFloor=modules[levels[0]]
	for geometry:Dictionary in gates.geometry_descriptor(levels[0]).gates:
		var pose:Transform3D=geometry.stair_to_floor_local
		var local:=Vector3(geometry.opening_center_x_local_m,geometry.rise_m+1.0,geometry.gate_plane_z_local_m)
		var hit:Dictionary=ray(owner.to_global(pose*(local+Vector3(0,0,.8))),owner.to_global(pose*(local-Vector3(0,0,.8))))
		check("closed actual rotated leaf seals its declared opening "+geometry.gate_id,not hit.is_empty() and hit.collider==gates.doors[geometry.gate_id])
		var height:float=2.10 if selected_variant=="low" else 2.35
		check("destination-specific native gate height retained "+geometry.gate_id,absf(geometry.height_m-height)<.001)
	return failures.is_empty()

func _press_gate(geometry: Dictionary,label: String) -> bool:
	if not await settle_native_motion(label):return false
	var door: Node3D=gates.doors[geometry.gate_id]
	Input.action_release("interact");await get_tree().process_frame;await get_tree().process_frame
	if not check("native exact E target and LOS "+label,player._interaction_target()==door and player._interaction_visible(door)):return false
	var before: Vector3=player.global_position
	Input.action_press("interact");await frames(6);await get_tree().process_frame;await get_tree().process_frame
	Input.action_release("interact");await frames(5)
	var begun: int=Time.get_ticks_msec()
	while not finished and Time.get_ticks_msec()-begun<6000 and absf(door.motion_angle-door.swing_delta)>.002:await get_tree().physics_frame
	native_actions.append({"label":label,"gate_id":geometry.gate_id,"actor_delta_during_E":player.global_position.distance_to(before),"motion_angle":door.motion_angle,"native_gate_state":gates.report().gates[geometry.gate_id]})
	return check("native E opens fully without actor displacement "+label,door.opened and absf(door.motion_angle-door.swing_delta)<.002 and player.global_position.distance_to(before)<.02,str(native_actions.back()))

func _walk(target: Vector3,label: String,radius: float=.15) -> bool:
	walk_stage=label
	return await walk_to(target,radius)

func _rear_landing(lower: CoreFloor,port: Dictionary) -> bool:
	var foot_offset: float=capsule_transform.origin.y-(capsule as CapsuleShape3D).height*.5
	var root_y: float=float(lower.construction.rise_m)*.5-foot_offset+player.safe_margin
	var rear: Vector3=_point(lower,port,Vector3(0,root_y,4.67))
	if not await _walk(rear,"full capsule rear landing, beyond centre-only route",.025):return false
	var local: Vector3=(port.source_core_local_pose as Transform3D).affine_inverse()*lower.to_local(player.global_position)
	var state: Dictionary=runtime.inspect_player(player)
	evidence["rear_landing_"+port.wing]={"actual_local_pose":local,"native":state,"owned_floor":lower.floor_record.id}
	return check("rear landing retains real full-height capsule and support "+port.wing,state.support.state=="supported" and state.clearance.state=="clear" and player.is_on_floor() and absf(local.z-4.67)<.035,str(state))

func _route() -> bool:
	var lower: CoreFloor=modules[levels[0]];var upper: CoreFloor=modules[levels[1]]
	var east: Dictionary=_port(lower,"east");var west: Dictionary=_port(lower,"west")
	var pose: Transform3D=east.source_core_local_pose
	var lower_entry: Vector3=pose*Vector3(-.78,0,-.60)
	if not await _walk(lower.to_global(_hall(lower,lower_entry.x)),"lower hall to rotated east core"):return false
	if not await _walk(lower.to_global(lower_entry),"east lower stair approach"):return false
	for i in range(1,5):
		if not await _walk(lower.to_global(east.walk_route[i]),"east U ascent segment"+str(i),.16):return false
	if not await _rear_landing(lower,east):return false
	for i in range(5,east.walk_route.size()):
		if not await _walk(lower.to_global(east.walk_route[i]),"east U return segment"+str(i),.16):return false
	var east_gate: Dictionary=_gate(levels[0],"east")
	if not await _press_gate(east_gate,"east stair-side upper return"):return false
	if not await _walk(_point(lower,east,Vector3(.78,lower.construction.rise_m,-1.72)),"east exit across actual receiving landing"):return false
	var east_exit: Vector3=upper.to_local(player.global_position)
	if not await _walk(upper.to_global(_hall(upper,east_exit.x)),"upper clear hall east"):return false
	var west_approach: Vector3=(west.source_core_local_pose as Transform3D)*Vector3(.78,0,CoreLayout.STAIR_APPROACH_Z)
	if not await _walk(upper.to_global(_hall(upper,west_approach.x)),"upper clear hall across source core"):return false
	if not await _walk(upper.to_global(west_approach),"west receiving-side gate approach"):return false
	if not await _press_gate(_gate(levels[0],"west"),"west receiving-side upper return"):return false
	for i in range(west.walk_route.size()-1,4,-1):
		if not await _walk(lower.to_global(west.walk_route[i]),"west U descent segment"+str(i),.16):return false
	if not await _rear_landing(lower,west):return false
	for i in range(4,-1,-1):
		if not await _walk(lower.to_global(west.walk_route[i]),"west U lower return segment"+str(i),.16):return false
	var exit: Vector3=lower.to_local(player.global_position)
	if not await _walk(lower.to_global(_hall(lower,exit.x)),"lower hall west return"):return false
	if not await _walk(lower.to_global(_hall(lower,0.0)),"continuous route returns to original shared hall"):return false
	var final: Dictionary=runtime.inspect_player(player)
	return check("route ends on real original floor with no death",Game.death_count==0 and final.support.state=="supported" and final.support.floor_id==levels[0],str(final))

func run() -> void:
	Game.simulation_paused=false;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.death_count=0
	levels.assign(["T3-B2","T3-B2M","T3-B1"] if selected_variant=="low" else ["T3-L47","T3-L48","T3-L49"])
	var raw: String=FileAccess.get_file_as_string("res://data/geography/osm-2026-10-27/manifest.json")
	var manifest: Dictionary=JSON.parse_string(raw)
	for tower: Dictionary in Reference.DATA.towers:
		if tower.tower=="T3":source_tower=tower
	var shell: Dictionary=Exterior.reference_plan();var actual: Dictionary={}
	for tower: Dictionary in shell.get("towers",[]):
		if tower.tower=="T3":actual=tower
	if not check("current source T3 own-axis profile exists",not actual.is_empty()):finish();return
	var common: Basis=Basis(Vector3(Reference.DATA.axis_south_xz[0],0,Reference.DATA.axis_south_xz[1]),Vector3.UP,Vector3(Reference.DATA.axis_bayward_xz[0],0,Reference.DATA.axis_bayward_xz[1]))
	var direction: Vector3=common*Vector3(actual.axis_south[0],0,actual.axis_south[1])
	tower_basis=Basis(Vector3.UP,atan2(-direction.z,direction.x))
	var first: Dictionary=_record(levels[0])
	frame=Frame.new()
	if not check("uncompressed actual source frame",frame.configure(manifest.georeference,[source_tower.centroid_world_xz[0],first.elevation_m,source_tower.centroid_world_xz[1]],_hash(raw),{"status":"staging","reference":"Reconstructed inventory heights; actual source horizontal tower basis"})):finish();return
	context=Context.new()
	var profile: Dictionary={"profile_id":"production-player-upright","radius_m":.36,"height_m":1.75,"center_offset_xyz":[0.0,.9,0.0],"min_support_normal_y":cos(deg_to_rad(52.0)),"max_support_drop_m":.35,"max_support_rise_m":.1,"max_support_lateral_m":.4}
	if not check("native source Context",context.configure(frame,_hash(FileAccess.get_file_as_string("res://src/world/mbs_interior/source_core_geometry.gd")),_hash("source core inventory elevations"),profile,get_world_3d())):finish();return
	domain=Domain.new()
	if not check("pinned actual country domain",domain.configure("res://data/geography/domain/osm-2026-10-27","82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834",_hash(raw))):finish();return
	for provider: Dictionary in domain.provider_descriptors():context.register_provider(provider.kind,provider.provider_id,provider.source_reference)
	context.register_provider("physics","source-core/native","Owned actual source-core triangles, slabs and guarded rotated gates")
	runtime=Runtime.new();add_child(runtime)
	if not check("native same-frame runtime",runtime.configure(frame,context,domain.observe)):finish();return
	for i in levels.size():
		var record: Dictionary=_record(levels[i],i==levels.size()-1)
		var module:=CoreFloor.new();module.name="ActualSourceCore_"+levels[i];add_child(module)
		module.global_transform=Transform3D(tower_basis,frame.to_local(_canonical(record,Vector3.ZERO)).position)
		var built: Dictionary=module.build(record)
		if not check("actual source core builds "+levels[i],built.get("built",false),str(built)):finish();return
		modules[levels[i]]=module
	await frames(5)
	if not _native_geometry():finish();return
	for id: String in levels:
		var module: CoreFloor=modules[id]
		generations[id]="source-core/"+id+"/"+str(module.structure.get_instance_id())+"/"+str(frame.metadata().origin_revision)
	gates=SourceGates.new();add_child(gates)
	var lower: CoreFloor=modules[levels[0]];var upper: CoreFloor=modules[levels[1]]
	var original: Array=lower.portals.duplicate(true)
	for port: Dictionary in lower.portals:
		if port.kind=="stair":port.lower.x+=.02;break
	var child_count: int=lower.get_child_count()
	check("changed source stair portal refuses before scene mutation",not gates.bind_floor(lower,levels[0],levels[1],_provider,upper.floor_record).get("bound",false) and lower.get_child_count()==child_count)
	lower.portals=original
	var bound: Dictionary=gates.bind_floor(lower,levels[0],levels[1],_provider,upper.floor_record)
	if not check("actual two rotated stairs bind strict source adapter",bound.get("bound",false),str(bound)):finish();return
	check("gates remain unready before complete native region commit",not gates.report().gates[_gate(levels[0],"east").gate_id].ready)
	await frames(5)
	if not _closed_guards():finish();return
	if not _register():finish();return
	gates.refresh_now()
	check("actual region support enables receiving gate",gates.report().gates[_gate(levels[0],"east").gate_id].ready)
	upper.structure.collision_layer=0;gates.refresh_now()
	check("actual missing receiver collider revokes readiness",not gates.report().gates[_gate(levels[0],"east").gate_id].ready and not runtime.region_status("source-core/"+levels[1]).live)
	upper.structure.collision_layer=1;await frames(3);gates.refresh_now()
	if not check("restored owned receiver physics becomes ready",gates.report().gates[_gate(levels[0],"east").gate_id].ready):finish();return
	if not prepare_player():finish();return
	player.collision_layer=player_layer;player.collision_mask=mask;player.process_mode=Node.PROCESS_MODE_INHERIT;player.show()
	player.respawn_at(lower.to_global(_hall(lower,0.0))+Vector3.UP*.08,0);actor_spawns+=1
	if not check("unchanged production Player binds source runtime",runtime.bind_player(player)):finish();return
	await frames(30);previous=player.global_position;travel=0;max_step=0;tracking=true
	var initial: Dictionary=runtime.inspect_player(player)
	if not check("actual initial hall support belongs to lower floor",initial.support.state=="supported" and initial.support.floor_id==levels[0] and initial.residency.state=="resident",str(initial)):finish();return
	await _route()
	finish()

func finish() -> void:
	if finished:return
	finished=true;tracking=false;release_motion_input();Input.action_release("interact")
	if is_instance_valid(runtime) and is_instance_valid(player):evidence["final_native_player"]=runtime.inspect_player(player)
	evidence["native_actions"]=native_actions;evidence["distance_m"]=travel;evidence["max_step_m"]=max_step
	if is_instance_valid(gates):evidence["gates"]=gates.report()
	var report: Dictionary={"schema":"source_core_geometry_native_fixture_v1","variant":selected_variant,"levels":levels,"checks":checks,"failed":failures.size(),"failures":failures,"elapsed_s":float(Time.get_ticks_msec()-started_ms)/1000.0,"initial_spawns":actor_spawns,"later_pose_velocity_or_reparent_writes":0,"evidence":evidence,"full_rooms_whole_hotel_visual_or_city_acceptance":false}
	print("[source-core-geometry] RESULT ",JSON.stringify(report,"",true,true))
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	Sfx.shutdown_audio();get_tree().quit(0 if failures.is_empty() else 1)
