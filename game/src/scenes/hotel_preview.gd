extends Node3D
## Playable milestone preview of the completed interior components. It never
## writes the city save or claims the unfinished whole-hotel allocation is live.
const Public = preload("res://src/world/mbs_interior/public_l1.gd")
const Guest = preload("res://src/world/mbs_interior/guest_floor.gd")
const Program = preload("res://src/world/mbs_interior/program_floor.gd")
const Inventory = preload("res://src/world/mbs_interior/inventory.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const CITY_SCENE = "res://main.tscn"
const STATE_KEYS = ["mode","health","death_count","wanted_level","wanted_heat","mission_stage","checkpoint_index","elapsed_seconds","player_position","player_rotation","carried_weapon","ammo","in_mission","search_timer","last_safe_position","last_safe_rotation","simulation_paused"]
var player: Player
var module: Node3D
var barriers: Node3D
var menu: PanelContainer
var title: Label
var prompt: Label
var status: Label
var _saved_state: Dictionary = {}
var _spawn := Vector3.ZERO
var _yaw := 0.0
var _loading := false
var _space := ""
var _smoke := false
var _recoveries := 0

func _ready() -> void:
	for key:String in STATE_KEYS:
		var value:Variant=Game.get(key)
		_saved_state[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	Game.simulation_paused=true;Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH
	Game.wanted_heat=0;Game.wanted_level=0;Game.in_mission=false
	var rig:Dictionary=Lighting.build_environment(self)
	(rig.sun as DirectionalLight3D).light_energy=1.2
	(rig.environment as WorldEnvironment).environment.tonemap_exposure=.95
	_build_ui()
	Events.interaction_prompt.connect(func(text:String):prompt.text=text)
	Events.notify.connect(func(text:String,_kind:String):status.text=text)
	var args:=OS.get_cmdline_user_args();_smoke="--hotel-preview-smoke" in args
	var selected:="lobby"
	for arg:String in args:
		if arg.begins_with("--hotel-preview-space="):selected=arg.trim_prefix("--hotel-preview-space=")
	if _smoke:_run_smoke.call_deferred()
	else:_load_space.call_deferred(selected)

func _build_ui() -> void:
	var layer:=CanvasLayer.new();layer.layer=20;add_child(layer)
	var root:=Control.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(root)
	var top:=PanelContainer.new();top.position=Vector2(24,24);top.custom_minimum_size=Vector2(620,96);root.add_child(top)
	var text:=VBoxContainer.new();top.add_child(text)
	title=Label.new();title.add_theme_font_size_override("font_size",24);text.add_child(title)
	var info:=Label.new();info.text="Interior preview · Lobby, a furnished guest floor and spa\nWASD move · Mouse look · E doors · Shift run · Esc areas/menu";text.add_child(info)
	status=Label.new();status.position=Vector2(28,135);status.add_theme_font_size_override("font_size",17);root.add_child(status)
	prompt=Label.new();prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);prompt.position=Vector2(-300,-72);prompt.size=Vector2(600,40);prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.add_theme_font_size_override("font_size",20);root.add_child(prompt)
	menu=PanelContainer.new();menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER);menu.position=Vector2(-220,-190);menu.custom_minimum_size=Vector2(440,380);root.add_child(menu)
	var choices:=VBoxContainer.new();choices.add_theme_constant_override("separation",12);menu.add_child(choices)
	var heading:=Label.new();heading.text="MARINA BAY SANDS";heading.add_theme_font_size_override("font_size",26);choices.add_child(heading)
	var scope:=Label.new();scope.text="Selected reconstructed spaces.\nThe complete hotel is not included yet.";choices.add_child(scope)
	for entry:Array in [["lobby","Hotel lobby"],["guest","Furnished guest floor"],["spa","Tower 2 · Level 5 spa"]]:
		var id:String=entry[0];var button:=Button.new();button.text=entry[1];button.custom_minimum_size=Vector2(400,42);button.pressed.connect(func():_load_space(id));choices.add_child(button)
	var resume:=Button.new();resume.text="Continue exploring";resume.pressed.connect(func():_set_menu(false));choices.add_child(resume)
	var back:=Button.new();back.text="Back to city menu";back.pressed.connect(_return_to_city);choices.add_child(back)
	menu.visible=false

func _hash(bytes:PackedByteArray)->String:
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);return h.finish().hex_encode()

func _load_space(kind:String)->bool:
	if _loading:return false
	if kind not in ["lobby","guest","spa"]:kind="lobby"
	_loading=true;Game.simulation_paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;menu.visible=false;status.text="Preparing the hotel…";prompt.text=""
	if is_instance_valid(player):player.queue_free()
	if is_instance_valid(module):module.queue_free()
	if is_instance_valid(barriers):barriers.queue_free()
	for tick in 3:await get_tree().physics_frame
	var result:Dictionary={}
	if kind=="lobby":
		var raw:=FileAccess.get_file_as_bytes("res://data/geography/osm-2026-10-27/manifest.json")
		var data:Variant=JSON.parse_string(raw.get_string_from_utf8())
		var frame:=Frame.new();var origin:Array=Reference.DATA.origin_world_xz
		if not data is Dictionary or not frame.configure(data.georeference,[origin[0],0.0,origin[1]],_hash(raw),{"status":"staging","reference":"Local preview of reconstructed public L1; not a whole-city placement claim"}):return _load_failed("Public reference frame unavailable")
		module=Public.new();add_child(module);result=module.build({"source_frame":frame})
		if result.get("built",false):
			_spawn=module.to_global(module.portal_local.outside)+Vector3.UP*.08
			var direction:Vector3=module.to_global(module.portal_local.inside)-_spawn;_yaw=atan2(-direction.x,-direction.z)
	else:
		module=Guest.new() if kind=="guest" else Program.new();add_child(module)
		result=module.build(Inventory.floor_record("T3-L24" if kind=="guest" else "T2-L5"))
		if result.get("built",false):
			var plan:Dictionary=module.get("_plan");var wing:Dictionary=plan.wings[0]
			_spawn=Vector3(0,.08,float(wing.corridor_center_z));_yaw=0.0
			_seal_unavailable_stairs()
			module.transition_requested.connect(func(_floor:String,_portal:String,_kind:String):status.text="Choose another area from the Esc menu. Other floors are not open in this preview.")
	if not result.get("built",false):return _load_failed(str(result.get("error","Area construction failed")))
	for tick in 3:await get_tree().physics_frame
	player=Player.new();player.name="Player";player.position=_spawn;player.yaw=_yaw;player.pitch=-.10;player.basis=Basis(Vector3.UP,_yaw);add_child(player)
	Game.mode=Game.MODE_FOOT;Game.health=Game.MAX_HEALTH;Game.mark_safe_position(_spawn,_yaw)
	_space=kind;title.text={"lobby":"MBS · Hotel lobby","guest":"MBS · Guest-floor layout","spa":"MBS · Level 5 spa layout"}[kind]
	status.text="Press Esc to choose another area or return to the city menu."
	_loading=false;Game.simulation_paused=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	print("[hotel-preview] READY ",JSON.stringify({"space":kind,"built":true,"player_spawn":_spawn,"preview_only":true,"city_save_written":false}))
	return true

func _seal_unavailable_stairs() -> void:
	barriers=Node3D.new();barriers.name="ClosedPreviewFloorConnections";add_child(barriers)
	var kit=Kit.new(barriers,"VisibleClosedStairDoors")
	for portal:Dictionary in module.get("portals"):
		if portal.get("kind")!="stair":continue
		var side:float=-1.0 if portal.wing=="east" else 1.0
		var lower:Vector3=portal.lower;var upper:Vector3=portal.upper
		var point:=Vector3((lower.x+upper.x)*.5,1.25,lower.z+side*.60)
		var size:=Vector3(3.20,2.50,.18)
		kit.box(Looks.get_mat("steel_white"),point,size,Basis.IDENTITY,false);kit.col_box(size,point)
		var label:=Label3D.new();label.text="OTHER FLOORS\nNOT OPEN IN THIS PREVIEW";label.font_size=32;label.pixel_size=.0018;label.position=point+Vector3(0,.2,-side*.10);label.rotation.y=0.0 if side<0 else PI;barriers.add_child(label)
	kit.commit(barriers,"ClosedStairDoorMaterials",true)

func _load_failed(reason:String)->bool:
	_loading=false;Game.simulation_paused=true;status.text="This area could not be prepared. Choose another area or return to the city menu.";menu.visible=true
	push_error("Hotel preview: "+reason);return false

func _set_menu(show:bool)->void:
	if _loading:return
	menu.visible=show;Game.simulation_paused=show;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if show else Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("pause"):
		_set_menu(not menu.visible);get_viewport().set_input_as_handled()

func _physics_process(_delta:float)->void:
	if _loading or not is_instance_valid(player):return
	if player.position.y< -4.0:
		_recoveries+=1;player.respawn_at(_spawn,_yaw);status.text="Returned to the hotel entrance."

func _return_to_city()->void:
	if _loading:return
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(CITY_SCENE)

func _exit_tree()->void:
	if not is_instance_valid(Game):return
	for key:String in _saved_state:Game.set(key,_saved_state[key])

func _run_smoke()->void:
	var checks:Array=[]
	for kind:String in ["lobby","guest","spa"]:
		var built:bool=await _load_space(kind)
		if built:
			for tick in 120:await get_tree().physics_frame
		checks.append({"space":kind,"built":built,"standing":built and player.is_on_floor(),"recoveries":_recoveries,"module_room_count":module.get("rooms").size() if module.get("rooms") is Array else 0})
	var ok:bool=checks.all(func(row:Dictionary):return row.built and row.standing and row.recoveries==0)
	print("[hotel-preview] SMOKE ",JSON.stringify({"ok":ok,"checks":checks,"scope":"Three scene builds, native floor support and teardown only; not whole-hotel traversal or rendered acceptance"}))
	get_tree().quit(0 if ok else 1)
