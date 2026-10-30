extends Node3D
## In-game hotel visit. Keeps the same city scene, player, vehicles and mission.
## Interiors are isolated streaming regions reached through a doorway/lift;
## their staging coordinates are never written into the legacy city save.
const Layout = preload("res://src/world/mbs_interior/city_access_layout.gd")
const Public = preload("res://src/world/mbs_interior/public_l1.gd")
const Guest = preload("res://src/world/mbs_interior/guest_floor.gd")
const Program = preload("res://src/world/mbs_interior/program_floor.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
var player: Player
var main: Node3D
var world: WorldBuilder
var active_space := ""
var transitioning := false
var _generation := 0
var _cooldown_ms := 0
var _previous_z := 0.0
var _region: Node3D
var _module: Node3D
var _entrance: Node3D
var _spawn := Vector3.ZERO
var _suspended: Array[Dictionary] = []
var _overlay: CanvasLayer
var _loading_label: Label
var _outside_landing := Vector3.ZERO
var _paused_before_transition := false

class DoorStation extends Node3D:
	var access: Node
	var target := ""
	var prompt_text := ""
	func _ready() -> void: add_to_group("interactables")
	func can_interact() -> bool: return access.can_use(self)
	func interact(actor: Node) -> void:
		if actor!=access.player or not can_interact(): return
		if target=="city": access.leave_hotel()
		else: access.enter_space(target)

func setup(scene: Node3D) -> void:
	main=scene;world=main.world;player=main.player
	_outside_landing=Layout.exit_position()
	add_to_group("city_hotel_access")
	_build_entrance()
	_overlay=CanvasLayer.new();_overlay.layer=90;add_child(_overlay)
	var shade:=ColorRect.new();shade.color=Color(.025,.035,.04,1);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_overlay.add_child(shade)
	_loading_label=Label.new();_loading_label.text="Entering Marina Bay Sands…";_loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER);_loading_label.position=Vector2(-220,-20);_loading_label.size=Vector2(440,40);_loading_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;shade.add_child(_loading_label)
	_overlay.hide();_previous_z=player.global_position.z
	world.locations["mbs_hotel_entrance"]=Layout.entrance()

func _build_entrance() -> void:
	_entrance=Node3D.new();_entrance.name="MBSHotelEntrance";add_child(_entrance)
	var at:=Layout.entrance()
	var kit=Kit.new(_entrance,"HotelEntranceFrame")
	# Existing landward tower facade is z=-45 relative to MBS. This entry sits
	# 2m in front of it: the crossing happens before the closed exterior shell.
	for dx:float in [-2.55,2.55]:
		kit.box(Looks.get_mat("steel_satin"),at+Vector3(dx,1.8,0),Vector3(.3,3.6,.4))
		kit.col_box(Vector3(.3,3.6,.4),at+Vector3(dx,1.8,0))
	kit.box(Looks.get_mat("steel_white"),at+Vector3(0,3.7,0),Vector3(5.4,.25,1.4))
	kit.col_box(Vector3(5.4,.25,1.4),at+Vector3(0,3.7,0))
	_label(_entrance,at+Vector3(0,3.05,-.25),"MARINA BAY SANDS\nHOTEL LOBBY",PI)
	_station(_entrance,at-Vector3(0,0,1.1),"lobby","[E] Enter Marina Bay Sands",false)
	# Existing road=.06m, footway=.10m and forecourt are already walkable.
	# Only an entrance mat is added; no raised ramp blocks a driving lane.
	kit.box(Looks.get_mat("granite_light"),at+Vector3(0,-.06,-1.0),Vector3(4.4,.08,3.0))
	kit.commit(_entrance,"HotelEntranceMaterials",false,180.0)

func _label(parent:Node3D,at:Vector3,text:String,yaw:float=0.0)->void:
	var label:=Label3D.new();label.text=text;label.font_size=42;label.pixel_size=.0035;label.outline_size=3;label.position=at;label.rotation.y=yaw;label.visibility_range_end=45.0;parent.add_child(label)

func _station(parent:Node3D,at:Vector3,target:String,text:String,board:bool=true)->DoorStation:
	var station:=DoorStation.new();station.access=self;station.target=target;station.prompt_text=text;station.position=at;parent.add_child(station)
	if board:
		_label(parent,at+Vector3.UP*1.6,text.replace("[E] ",""))
	return station

func can_use(station:DoorStation)->bool:
	if transitioning or Game.simulation_paused or not main.started or not player.alive or Game.health<=0: return false
	if Game.mode!=Game.MODE_FOOT or player.current_vehicle!=null or player.busy: return false
	if Time.get_ticks_msec()<_cooldown_ms or not station.is_visible_in_tree():return false
	return player.global_position.distance_to(station.global_position)<3.1 and player._interaction_visible(station)

func _physics_process(_delta:float)->void:
	if not is_instance_valid(player):return
	var p:=player.global_position
	if not transitioning and not Game.simulation_paused and main.started and player.alive and not player.busy and Game.health>0 and Game.mode==Game.MODE_FOOT and player.current_vehicle==null and Time.get_ticks_msec()>=_cooldown_ms:
		if active_space.is_empty():
			var door:=Layout.entrance()
			if absf(p.x-door.x)<float(Layout.data().door_width)*.5-.4 and absf(p.y-door.y)<.8 and _previous_z<door.z and p.z>=door.z and p.z<door.z+float(Layout.data().trigger_depth):
				enter_space("lobby")
		elif active_space=="lobby" and is_instance_valid(_module):
			var local:Vector3=_module.to_local(p)
			var portal:Dictionary=_module.get("portal_local")
			var edge:Vector3=portal.hotel_entrance
			if absf(local.x-edge.x)<2.0 and local.z<edge.z-.65:leave_hotel()
		if not active_space.is_empty() and p.y<float(Layout.data().stage_heights[active_space])-5.0:
			# A failed floor/support path is recoverable, never a successful QA gate.
			_move_player(_spawn,player.yaw);Events.toast("Returned to the hotel landing.","warn")
	_previous_z=p.z

func enter_space(kind:String)->bool:
	if kind not in ["lobby","guest","spa"] or transitioning:return false
	if not player.alive or Game.health<=0 or player.current_vehicle!=null or Game.mode!=Game.MODE_FOOT:return false
	if kind==active_space:return true
	transitioning=true;_generation+=1;var token:=_generation
	var was_paused:=Game.simulation_paused;_paused_before_transition=was_paused;Game.simulation_paused=true
	_loading_label.text="Entering Marina Bay Sands…" if kind=="lobby" else "Taking the hotel lift…";_overlay.show()
	await get_tree().process_frame
	if token!=_generation:return false
	var built:Dictionary=_construct_region(kind)
	var candidate:Node3D=built.get("root")
	if not built.get("ok",false):
		if is_instance_valid(candidate):candidate.queue_free()
		return _abort_transition(was_paused,"Hotel area could not be loaded. You remain where you were.")
	for tick in 3:await get_tree().physics_frame
	if token!=_generation:
		if is_instance_valid(candidate):candidate.queue_free()
		return false
	var landing:Vector3=built.spawn
	if not _arrival_clear(landing,candidate):
		candidate.queue_free()
		return _abort_transition(was_paused,"Hotel arrival is obstructed. Please try again later.")
	if active_space.is_empty():
		var outside:=_city_landing(Layout.exit_position())
		if not outside.is_finite():
			candidate.queue_free()
			return _abort_transition(was_paused,"The hotel exit is obstructed. Please clear the doorway first.")
		_outside_landing=outside
		_suspend_city();Game.mark_safe_position(_outside_landing,0.0)
	if is_instance_valid(_region):_region.queue_free()
	_region=candidate;_module=built.module;_spawn=landing;active_space=kind
	_region.show();_entrance.hide();_move_player(landing,float(built.yaw))
	main.hud.set_hotel_status({"lobby":"MBS lobby · Walk back through the entrance to exit. Use the hotel lift for rooms and spa.","guest":"MBS guest floor · Use the lift to return to the lobby.","spa":"MBS spa · Use the lift to return to the lobby."}[kind])
	_cooldown_ms=Time.get_ticks_msec()+1000;_previous_z=player.global_position.z
	transitioning=false;Game.simulation_paused=was_paused;_overlay.hide()
	return true

func _abort_transition(was_paused:bool,message:String)->bool:
	transitioning=false;Game.simulation_paused=was_paused;_overlay.hide();Events.toast(message,"warn");return false

func _construct_region(kind:String)->Dictionary:
	var root:=Node3D.new();root.name="MBSInterior_"+kind;add_child(root);root.hide()
	var module:Node3D
	var at:=DowntownPlan.anchor("marina_bay_sands");at.y=float(Layout.data().stage_heights[kind])
	var result:Dictionary={};var spawn:=Vector3.ZERO;var yaw:=0.0
	if kind=="lobby":
		module=Public.new();root.add_child(module)
		var raw:=FileAccess.get_file_as_bytes("res://data/geography/osm-2026-10-27/manifest.json")
		var data:Variant=JSON.parse_string(raw.get_string_from_utf8())
		var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(raw)
		var origin:Array=Reference.DATA.origin_world_xz;var frame:=Frame.new()
		if not data is Dictionary or not frame.configure(data.georeference,[float(origin[0])-at.x,0.0,float(origin[1])-at.z],h.finish().hex_encode(),{"status":"staging","reference":"Game interior streaming region; not geographic/as-built placement"}):return {"ok":false,"root":root}
		result=module.build({"source_frame":frame,"floor_elevation_m":at.y,"entrance_side":"landward"})
		if result.get("built",false):
			var portal:Dictionary=module.get("portal_local")
			spawn=module.to_global(portal.inside)+Vector3.UP*.08
			var direction:Vector3=module.to_global(portal.inside)-module.to_global(portal.outside);yaw=atan2(-direction.x,-direction.z)
			var edge:Vector3=module.to_global(portal.inside)
			_station(root,edge,"city","[E] Exit to Bayfront Avenue")
			# Lift call points are offset into the reserved entrance aisle; labels
			# are floor destinations, not a separate scene-selection menu.
			_lobby_lift(root,module,portal.inside+Vector3(-2.8,0,3.0),"guest","GUEST FLOOR")
			_lobby_lift(root,module,portal.inside+Vector3(2.8,0,3.0),"spa","LEVEL 5 · SPA")
	else:
		module=Guest.new() if kind=="guest" else Program.new();root.add_child(module);module.position=at
		result=module.build(Inventory.floor_record(String(Layout.data().floor_ids[kind])))
		if result.get("built",false):
			var plan:Dictionary=module.get("_plan");var wing:Dictionary=plan.wings[0]
			spawn=module.to_global(Vector3(0,.08,float(wing.corridor_center_z)))
			_seal_stairs(module)
			for door:Variant in module.get("doors").values():
				if door.transition_kind in ["guest_lift","service_lift"]:door.prompt_text="[E] Hotel lift · Lobby / Bayfront Avenue"
			module.transition_requested.connect(func(_floor:String,_portal:String,action:String):
				if action in ["guest_lift","service_lift"]:enter_space("lobby")
				else:Events.toast("Use the hotel lift to return to the lobby.","info"))
	return {"ok":result.get("built",false),"root":root,"module":module,"spawn":spawn,"yaw":yaw}

func _lobby_lift(root:Node3D,module:Node3D,local_at:Vector3,target:String,title:String)->void:
	var lift:=Node3D.new();root.add_child(lift)
	lift.global_transform=Transform3D(module.global_basis,module.to_global(local_at))
	var kit=Kit.new(lift,"HotelLiftDoorCollision")
	kit.box(Looks.get_mat("steel_dark"),Vector3(0,1.5,.95),Vector3(2.6,3.0,.3))
	kit.col_box(Vector3(2.6,3.0,.3),Vector3(0,1.5,.95))
	for side:float in [-1.0,1.0]:
		kit.box(Looks.get_mat("steel_satin"),Vector3(side*.55,1.3,.76),Vector3(1.06,2.6,.05))
	kit.commit(lift,"HotelLiftDoors",true)
	_label(lift,Vector3(0,2.85,.70),title,PI)
	_station(lift,Vector3.ZERO,target,"[E] Hotel lift · "+title.to_lower(),false)

func _seal_stairs(module:Node3D)->void:
	var kit=Kit.new(module,"ClosedUnbuiltStairConnections")
	for portal:Dictionary in module.get("portals"):
		if portal.get("kind")!="stair":continue
		var side:float=-1.0 if portal.wing=="east" else 1.0
		var lower:Vector3=portal.lower;var upper:Vector3=portal.upper
		var at:=Vector3((lower.x+upper.x)*.5,1.25,lower.z+side*.60)
		kit.box(Looks.get_mat("steel_white"),at,Vector3(3.2,2.5,.18),Basis.IDENTITY,false)
		kit.col_box(Vector3(3.2,2.5,.18),at)
		_label(module,at+Vector3(0,.2,-side*.11),"STAIRS CLOSED\nPLEASE USE HOTEL LIFT",0.0 if side<0 else PI)
	kit.commit(module,"ClosedStairDoorMaterials",true)

func _arrival_clear(at:Vector3,expected_root:Node3D=null)->bool:
	var space:=get_world_3d().direct_space_state
	var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*.4,1))
	if floor_hit.is_empty() or absf(float(floor_hit.position.y)-at.y)>.20:return false
	if expected_root!=null and not expected_root.is_ancestor_of(floor_hit.collider):return false
	var shape:=CapsuleShape3D.new();shape.radius=.38;shape.height=1.75
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.93);query.collision_mask=1|4|8;query.exclude=[player.get_rid()]
	return space.intersect_shape(query,1).is_empty()

func _suspend_city()->void:
	_suspended.clear()
	for child:Node in main.get_children():
		if child==self or child==player or child==main.hud:continue
		_suspended.append({"node":child,"mode":child.process_mode})
		child.process_mode=Node.PROCESS_MODE_DISABLED
		var visual:Node=world.get_node_or_null("District") if child==world else child
		if visual is Node3D or visual is CanvasLayer:
			_suspended.append({"node":visual,"visible":visual.visible});visual.hide()
		var stack:Array[Node]=[child]
		while not stack.is_empty():
			var n:Node=stack.pop_back()
			for descendant:Node in n.get_children():stack.append(descendant)
			if n is RigidBody3D:
				_suspended.append({"node":n,"freeze":n.freeze,"sleeping":n.sleeping});n.freeze=true
			elif n is CanvasLayer and n!=visual:
				_suspended.append({"node":n,"visible":n.visible});n.hide()

func _restore_city()->void:
	for record:Dictionary in _suspended:
		var n:Node=record.node
		if not is_instance_valid(n):continue
		if record.has("mode"):n.process_mode=int(record.mode)
		if record.has("visible"):n.visible=bool(record.visible)
		if record.has("freeze"):n.freeze=bool(record.freeze);n.sleeping=bool(record.sleeping)
	_suspended.clear()

func _city_landing(at:Vector3)->Vector3:
	for delta:Vector3 in [Vector3.ZERO,Vector3(-2.5,0,0),Vector3(2.5,0,0),Vector3(0,0,-2.5)]:
		var p:=at+delta
		var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p-Vector3.UP,1))
		if not hit.is_empty():
			p.y=float(hit.position.y)+.08
			if _arrival_clear(p):return p
	return Vector3(INF,INF,INF)

func leave_hotel(move_player:bool=true)->bool:
	if active_space.is_empty() and not transitioning:return true
	var at:=_outside_landing
	if move_player and not active_space.is_empty():
		at=_city_landing(Layout.exit_position())
		if not at.is_finite():Events.toast("The hotel exit is blocked. Please try again.","warn");return false
	if transitioning:Game.simulation_paused=_paused_before_transition
	_generation+=1;transitioning=false;active_space=""
	_restore_city();_entrance.show();_overlay.hide()
	if is_instance_valid(_region):_region.queue_free()
	_region=null;_module=null
	main.hud.set_hotel_status("")
	if move_player:_move_player(at,0.0)
	_cooldown_ms=Time.get_ticks_msec()+1200;_previous_z=player.global_position.z
	return true

func _move_player(at:Vector3,yaw:float)->void:
	player.global_position=at;player.velocity=Vector3.ZERO;player.yaw=yaw;player.rotation.y=yaw;player._heading=yaw
	player._speed=0.0;player._prev_speed=0.0;player._fall_speed=0.0;player._airborne_time=0.0;player._jump_windup=-1.0;player._cam_ready=false
	player.reset_action_state(false);player._press_armed["interact"]=false;Game.player_position=at;Game.player_rotation=yaw

func decorate_save(data:Dictionary)->void:
	if active_space.is_empty():return
	var at:=_outside_landing
	data["hotel_visit"]={"version":1,"space":active_space}
	data["player_position"]=[at.x,at.y,at.z];data["player_rotation"]=0.0
	data["last_safe_position"]=[at.x,at.y,at.z];data["last_safe_rotation"]=0.0

func restore_visit(value:Variant)->void:
	if Layout.valid_visit(value):enter_space.call_deferred(String(value.space))
