class_name Helicopter
extends CharacterBody3D
## Original arcade helicopter: modelled fuselage, cockpit, pilot seat, main and
## tail rotors, skids. It is a real controllable vehicle, not a moving camera.

const MAX_TILT := 0.45
const LIFT := 26.0
const GRAVITY := 12.0
const MAX_FORWARD := 38.0

var pilot_is_player := false
var health := 100.0
var disabled := false
var _yaw_input := 0.0
var _pitch_input := 0.0
var _lift_input := 0.0
var _rotor: Node3D
var _tail_rotor: Node3D
var _body: Node3D
var _camera: Camera3D
var _landed := false
var _provider_root: Node3D = null
var _provider_main_rotor: Node3D = null
var _provider_tail_rotor: Node3D = null
var _procedural_visuals: Array[Node3D] = []
var _last_good_position := Vector3.ZERO
const AIR_LIMIT_X := 820.0
const AIR_LIMIT_NORTH := -1080.0
const AIR_LIMIT_SOUTH := 820.0
const AIR_CEILING := 420.0
var _envelope_notice := 0.0
var _impact_cooldown := 0.0
# opus55 helicopter piece: rotor spool, presentation FX and a lagged chase rig.
var _fx: HeliFX = null
var rotor_spin := 0.15
var _cam_ready := false
var _cam_yaw := 0.0
var _cam_pos := Vector3.ZERO
var _cam_roll := 0.0
var _cam_look := Vector3.ZERO
var _prev_forward_speed := 0.0
var _accel_pitch := 0.0
var _hover_clock := 0.0
var _yaw_rate := 0.0
var _agl := 0.0
var _touch_dip := 0.0
var _was_on_floor := true
var last_touchdown_speed := 0.0 ## vertical speed (m/s) at the last skid contact
var _cam_vel := Vector3.ZERO
var _cam_yaw_vel := 0.0
var _cam_drag := Vector3.ZERO

func _ready() -> void:
	add_to_group("vehicles")
	add_to_group("helicopters")
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	# Road vehicles stand on world geometry, never on their own passenger
	# or a pedestrian as a moving platform.
	platform_floor_layers = 1
	platform_wall_layers = 0
	_build()

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)

	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.5
	sm.height = 3.4
	sm.radial_segments = 16
	sm.rings = 8
	shell.mesh = sm
	shell.material_override = Palette.mat(Color(0.20, 0.28, 0.33), 0.35, 0.6)
	shell.position = Vector3(0.0, 1.7, 0.0)
	shell.scale = Vector3(1.0, 0.86, 1.5)
	_body.add_child(shell)

	var tail_body := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.42, 0.42, 4.4)
	tail_body.mesh = tb
	tail_body.material_override = Palette.mat(Color(0.20, 0.28, 0.33), 0.35, 0.6)
	tail_body.position = Vector3(0.0, 1.8, 3.3)
	tail_body.rotation_degrees = Vector3(7.0, 0.0, 0.0)
	_body.add_child(tail_body)

	var fin := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.16, 1.5, 1.0)
	fin.mesh = fb
	fin.material_override = Palette.mat(Color(0.20, 0.28, 0.33), 0.35, 0.6)
	fin.position = Vector3(0.0, 2.4, 5.3)
	_body.add_child(fin)

	# cockpit glazing + pilot seat
	var glass := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 1.05
	gs.height = 1.7
	gs.radial_segments = 14
	gs.rings = 6
	glass.mesh = gs
	glass.material_override = Palette.glass()
	glass.position = Vector3(0.0, 1.55, -1.15)
	glass.scale = Vector3(1.0, 0.9, 1.1)
	_body.add_child(glass)
	var seat := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.55, 0.7, 0.55)
	seat.mesh = sb
	seat.material_override = Palette.mat(Color(0.12, 0.12, 0.14), 0.85)
	seat.position = Vector3(0.0, 1.25, -0.75)
	_body.add_child(seat)
	var dash := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(0.9, 0.22, 0.3)
	dash.mesh = db
	dash.material_override = Palette.mat(Color(0.12, 0.12, 0.14), 0.7)
	dash.position = Vector3(0.0, 1.35, -1.55)
	_body.add_child(dash)

	# main rotor (spinning) + mast
	var mast := MeshInstance3D.new()
	var mb := BoxMesh.new()
	mb.size = Vector3(0.2, 0.7, 0.2)
	mast.mesh = mb
	mast.material_override = Palette.mat(Color(0.15, 0.16, 0.17), 0.5, 0.5)
	mast.position = Vector3(0.0, 3.3, 0.0)
	_body.add_child(mast)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0.0, 3.6, 0.0)
	_body.add_child(_rotor)
	for i in 4:
		var blade := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.35, 0.06, 7.6)
		blade.mesh = bb
		blade.material_override = Palette.mat(Color(0.10, 0.10, 0.11), 0.6, 0.3)
		blade.rotation_degrees = Vector3(0.0, i * 45.0, 3.0)
		_rotor.add_child(blade)
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(0.28, 2.4, 5.3)
	_body.add_child(_tail_rotor)
	for i in 2:
		var tb2 := MeshInstance3D.new()
		var bb2 := BoxMesh.new()
		bb2.size = Vector3(0.1, 2.2, 0.18)
		tb2.mesh = bb2
		tb2.material_override = Palette.mat(Color(0.10, 0.10, 0.11), 0.6, 0.3)
		tb2.rotation_degrees = Vector3(0.0, 0.0, i * 90.0)
		_tail_rotor.add_child(tb2)

	# skids
	for sx in [-1.0, 1.0]:
		var skid := MeshInstance3D.new()
		var skb := BoxMesh.new()
		skb.size = Vector3(0.14, 0.14, 3.4)
		skid.mesh = skb
		skid.material_override = Palette.mat(Color(0.18, 0.19, 0.20), 0.5, 0.5)
		skid.position = Vector3(1.1 * sx, 0.35, 0.2)
		_body.add_child(skid)
		for sz in [-1.0, 1.0]:
			var strut := MeshInstance3D.new()
			var stb := BoxMesh.new()
			stb.size = Vector3(0.12, 1.0, 0.12)
			strut.mesh = stb
			strut.material_override = Palette.mat(Color(0.18, 0.19, 0.20), 0.5, 0.5)
			strut.position = Vector3(1.1 * sx, 0.9, 0.2 + 1.2 * sz)
			_body.add_child(strut)

	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 2.6, 5.6)
	shape.shape = bs
	shape.position = Vector3(0.0, 1.6, 0.4)
	add_child(shape)

	# Chase camera: a free (top-level) camera that trails the aircraft with
	# positional and yaw lag and leans into banks (see _update_chase_camera).
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.fov = 64.0
	_camera.top_level = true
	add_child(_camera)

	for child in get_children():
		if child is MeshInstance3D:
			_procedural_visuals.append(child)
	_try_provider_asset()
	_fx = HeliFX.new()
	_fx.name = "HeliFX"
	if _provider_root != null:
		_fx.setup(self, _provider_root)
	else:
		_fx.setup(self, _body)
		_fx.main_hub = Vector3(0.0, 3.62, 0.0)
		_fx.main_radius = 3.8
		_fx.tail_hub = Vector3(0.34, 2.4, 5.3)
		_fx.tail_radius = 1.1
	add_child(_fx)

## Swap in the generated helicopter when it has been cleaned and staged.
func _try_provider_asset() -> void:
	if not AssetLibrary.has_asset("helicopter_refined.glb"):
		return
	var root := AssetLibrary.instantiate("helicopter_refined.glb", self)
	if root == null:
		return
	_provider_root = root
	root.position.y = 0.30 # skids meet the collider lower extent
	_body.visible = false
	for part in _procedural_visuals:
		part.visible = false
	var main_rotor := AssetLibrary.find_named(root, "main_rotor")
	if main_rotor is Node3D:
		_provider_main_rotor = main_rotor
	var tail_rotor := AssetLibrary.find_named(root, "tail_rotor")
	if tail_rotor is Node3D:
		_provider_tail_rotor = tail_rotor
	_paint_finish(root)

## Factory paint for the provider airframe. Its generated texture atlas is
## a patchwork of noisy chunks and its ORM map scatters fully-metallic
## patches, which read as camouflage blotches in sunlit chase frames. The body
## is repainted with a clean, clear-coated dark-navy finish: the atlas only
## modulates it softly (sampled at a coarse mip) and keeps its darkest areas
## (glazing, rubber, intakes) dark and glossy; the normal map and AO stay.
const PAINT_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 paint : source_color = vec3(0.075, 0.095, 0.13);
uniform vec3 trim : source_color = vec3(0.55, 0.57, 0.60);
void fragment() {
	vec3 t = texture(albedo_tex, UV, 2.5).rgb;
	float l = dot(t, vec3(0.299, 0.587, 0.114));
	float dark = 1.0 - smoothstep(0.07, 0.17, l);
	float light = smoothstep(0.62, 0.82, l);
	vec3 c = paint * (0.85 + 0.35 * smoothstep(0.15, 0.6, l));
	c = mix(c, trim, light * 0.55);
	c = mix(c, vec3(0.018, 0.02, 0.024), dark * 0.85);
	ALBEDO = c;
	METALLIC = mix(0.45, 0.1, dark);
	ROUGHNESS = mix(0.30, 0.14, dark);
	SPECULAR = 0.55;
	CLEARCOAT = 0.9;
	CLEARCOAT_ROUGHNESS = 0.07;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.55;
	AO = texture(orm_tex, UV).r;
	AO_LIGHT_AFFECT = 0.35;
}
"""

func _paint_finish(node: Node) -> void:
	if node is MeshInstance3D and node != _provider_main_rotor and node != _provider_tail_rotor:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
					var sm := mat as StandardMaterial3D
					if sm.albedo_texture == null:
						continue
					var shader := Shader.new()
					shader.code = PAINT_SHADER
					var m := ShaderMaterial.new()
					m.shader = shader
					m.set_shader_parameter("albedo_tex", sm.albedo_texture)
					if sm.roughness_texture != null:
						m.set_shader_parameter("orm_tex", sm.roughness_texture)
					if sm.normal_texture != null:
						m.set_shader_parameter("normal_tex", sm.normal_texture)
					mi.set_surface_override_material(i, m)
	for child in node.get_children():
		if child != _provider_main_rotor and child != _provider_tail_rotor:
			_paint_finish(child)

func _physics_process(delta: float) -> void:
	if Game.simulation_paused:
		return
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	if _provider_root != null:
		_provider_root.rotation.x = _body.rotation.x
		_provider_root.rotation.z = _body.rotation.z
		_provider_root.position.y = 0.30 + _body.position.y
	# Rotor spool: the turbine winds up over ~2 s after boarding and runs down
	# slowly after shutdown, instead of snapping between two speeds.
	var spin_target := 1.0 if pilot_is_player and not disabled else 0.12
	rotor_spin = move_toward(rotor_spin, spin_target, delta * (0.55 if spin_target > rotor_spin else 0.30))
	var rotor_speed := lerpf(3.0, 26.0, rotor_spin)
	if _fx != null:
		_fx.spin = rotor_spin
	# Above ~60 % rpm the blades are drawn as the motion-blurred disc only.
	var blades_visible := rotor_spin < 0.6
	if _provider_main_rotor != null:
		_provider_main_rotor.visible = blades_visible
	elif _rotor != null:
		_rotor.visible = blades_visible
	if _provider_tail_rotor != null:
		_provider_tail_rotor.visible = rotor_spin < 0.45
	elif _tail_rotor != null:
		_tail_rotor.visible = rotor_spin < 0.45
	if _rotor:
		_rotor.rotate_y(delta * rotor_speed)
	if _tail_rotor:
		_tail_rotor.rotate_x(delta * rotor_speed * 1.5)
	if _provider_main_rotor != null:
		AssetLibrary.spin_part(_provider_main_rotor, _provider_root, Vector3.UP, delta * rotor_speed * 1.6)
	if _provider_tail_rotor != null:
		AssetLibrary.spin_part(_provider_tail_rotor, _provider_root, Vector3.RIGHT, delta * rotor_speed * 2.4)
	if pilot_is_player and not disabled:
		_pilot_input(delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * delta)
		velocity.y -= GRAVITY * delta
		_body.rotation.x = lerp_angle(_body.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
		_body.rotation.z = lerp_angle(_body.rotation.z, 0.0, clampf(delta * 3.0, 0.0, 1.0))
		_body.position.y = lerpf(_body.position.y, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	# Aerial envelope (WORLD-06, wave 5): beyond the far-shore skyline the
	# aircraft is turned back rather than flying into empty scenery.
	var off_x := absf(global_position.x) - AIR_LIMIT_X
	var off_n := AIR_LIMIT_NORTH - global_position.z
	var off_s := global_position.z - AIR_LIMIT_SOUTH
	if off_x > 0.0 or off_n > 0.0 or off_s > 0.0 or global_position.y > AIR_CEILING:
		var home := Vector3(-global_position.x, 0.0, -150.0 - global_position.z).normalized()
		velocity.x = lerpf(velocity.x, home.x * 18.0, clampf(delta * 1.5, 0.0, 1.0))
		velocity.z = lerpf(velocity.z, home.z * 18.0, clampf(delta * 1.5, 0.0, 1.0))
		velocity.y = minf(velocity.y, 0.0) if global_position.y > AIR_CEILING else velocity.y
		if pilot_is_player and _envelope_notice <= 0.0:
			_envelope_notice = 6.0
			Events.notify.emit("Restricted airspace - turning back over the bay.", "warn")
	_envelope_notice = maxf(0.0, _envelope_notice - delta)
	var before := velocity
	move_and_slide()
	# A ditched aircraft (below the water line, where nothing supports it) is
	# recovered to its last supported position instead of falling forever.
	if global_position.y < -3.0:
		global_position = _last_good_position + Vector3(0.0, 1.5, 0.0) if _last_good_position != Vector3.ZERO else Vector3(0.0, 2.0, -337.0)
		velocity = Vector3.ZERO
		if pilot_is_player:
			Events.notify.emit("Aircraft recovered to its last landing site.", "warn")
	if _impact_cooldown <= 0.0:
		var impact_speed := 0.0
		for index in get_slide_collision_count():
			impact_speed = maxf(impact_speed, -before.dot(get_slide_collision(index).get_normal()))
		if impact_speed > 9.0:
			_impact_cooldown = 1.0
			take_damage((impact_speed - 9.0) * 4.0, global_position, false)
	if is_on_floor():
		if not _was_on_floor:
			last_touchdown_speed = maxf(-before.y, 0.0)
		if not _was_on_floor and before.y < -0.4:
			# skids compress and the airframe settles on touchdown
			_touch_dip = clampf(-before.y * 0.07, 0.03, 0.16)
		if velocity.length() < 2.0:
			_landed = true
		_last_good_position = global_position
	else:
		_landed = false
	_was_on_floor = is_on_floor()

func _pilot_input(delta: float) -> void:
	var yaw_in := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var pitch_in := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var lift_in := Input.get_action_strength("jump") - Input.get_action_strength("sprint")
	_yaw_input = lerpf(_yaw_input, yaw_in, clampf(delta * 5.0, 0.0, 1.0))
	_pitch_input = lerpf(_pitch_input, pitch_in, clampf(delta * 3.5, 0.0, 1.0))
	_lift_input = lerpf(_lift_input, lift_in, clampf(delta * 6.0, 0.0, 1.0))
	var basis_now := global_transform.basis
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	var forward_speed := flat_vel.dot(-basis_now.z)
	var lateral_speed := flat_vel.dot(basis_now.x)
	var speed_frac := clampf(absf(forward_speed) / MAX_FORWARD, 0.0, 1.0)
	# Yaw has angular inertia: the turn rate builds and decays instead of
	# snapping, and a fast aircraft turns a little wider than a hovering one.
	# (A node that faces -Z turns left when its yaw increases.)
	var yaw_target := _yaw_input * lerpf(1.55, 1.15, speed_frac)
	_yaw_rate = lerpf(_yaw_rate, yaw_target, clampf(delta * 3.2, 0.0, 1.0))
	rotation.y += _yaw_rate * delta
	# Ground proximity (skids / water) for the landing cushion and auto-level.
	_agl = _probe_agl()
	var near_ground := clampf(1.0 - (_agl - 0.6) / 4.0, 0.0, 1.0)
	# Momentum: horizontal velocity eases toward the commanded velocity along
	# the current heading, so the aircraft carries speed through turns (it
	# drifts wide, then the new heading takes over) and needs room to stop.
	var dir := -global_transform.basis.z
	var target_speed := _pitch_input * MAX_FORWARD
	var commanded := dir * target_speed
	var braking := flat_vel.length() > commanded.length() + 0.5
	var response := 1.85 if braking else 1.35
	velocity.x = lerpf(velocity.x, commanded.x, clampf(delta * response, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, commanded.z, clampf(delta * response, 0.0, 1.0))
	# Attitude follows the physics: the rotor disc tilts the way the aircraft
	# is accelerating. Cruise flies nose-down, throttle-up dips the nose
	# further, braking flares the nose up; turns are coordinated, banking by
	# atan(v * yaw_rate / g), so a fast turn is a steep, dramatic bank.
	var accel := (forward_speed - _prev_forward_speed) / maxf(delta, 0.001)
	_prev_forward_speed = forward_speed
	_accel_pitch = lerpf(_accel_pitch, clampf(-accel * 0.045, -0.26, 0.24), clampf(delta * 3.0, 0.0, 1.0))
	var cruise_pitch := -0.17 * clampf(forward_speed / MAX_FORWARD, -0.5, 1.0)
	var target_pitch := clampf(cruise_pitch + _accel_pitch - _pitch_input * 0.04, -0.38, 0.30)
	var coordinated := atan(forward_speed * _yaw_rate / 9.8) * 0.85
	var target_bank := clampf(coordinated + _yaw_input * 0.07 - lateral_speed * 0.018, -0.62, 0.62)
	target_pitch *= 1.0 - near_ground * 0.85
	target_bank *= 1.0 - near_ground * 0.9
	_body.rotation.x = lerp_angle(_body.rotation.x, target_pitch, clampf(delta * 2.4, 0.0, 1.0))
	_body.rotation.z = lerp_angle(_body.rotation.z, target_bank, clampf(delta * 2.0, 0.0, 1.0))
	# gentle hover bob while airborne (visual only); skids compress on touchdown
	_hover_clock += delta
	var bob := (sin(_hover_clock * 1.3) * 0.06 + sin(_hover_clock * 2.9) * 0.025) * (1.0 - near_ground) if not is_on_floor() else 0.0
	_touch_dip = move_toward(_touch_dip, 0.0, delta * 0.45)
	_body.position.y = lerpf(_body.position.y, bob - _touch_dip, clampf(delta * 6.0, 0.0, 1.0))
	# Collective with inertia. Neutral lift holds altitude; descent is capped
	# by a ground cushion so the last few metres always settle gently.
	var target_vertical_speed := _lift_input * (12.0 if _lift_input >= 0.0 else 7.0)
	if target_vertical_speed < 0.0:
		target_vertical_speed = maxf(target_vertical_speed, -lerpf(0.9, 7.0, clampf((_agl - 0.5) / 9.0, 0.0, 1.0)))
	# the collective arrests a climb or sink faster than it builds one, so a
	# released stick settles into a hover without bouncing
	var arresting := absf(target_vertical_speed) < absf(velocity.y)
	velocity.y = move_toward(velocity.y, target_vertical_speed, (22.0 if arresting else 15.0) * delta)
	if is_on_floor() and _lift_input <= 0.0:
		velocity.y = minf(velocity.y, 0.0)

## Height of the skids above the ground or water below (metres).
func _probe_agl() -> float:
	var origin := global_position + Vector3.UP * 0.8
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 40.0, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	var ground_y := -0.4
	if not hit.is_empty():
		ground_y = maxf((hit["position"] as Vector3).y, -0.4)
	elif global_position.y > 39.0:
		return 99.0
	return maxf(global_position.y - ground_y, 0.0)

func _process(delta: float) -> void:
	if pilot_is_player:
		Sfx.set_rotor_pitch(clampf(velocity.length() / 30.0, 0.0, 1.0))
	if _camera != null and (_camera.current or pilot_is_player):
		_update_chase_camera(delta)
	else:
		_cam_ready = false

## Chase camera with weight. Position and heading ride damped springs
## (slightly under-damped), so in a banking turn the camera swings wide,
## lags, then settles back in behind; it sits high enough above the rotor
## plane that the blurred disc always reads, pulls back and widens with
## speed, rolls with part of the bank and dips on a hard touchdown.
## A ray keeps it out of buildings.
func _update_chase_camera(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var speed_frac := clampf(ground_speed / MAX_FORWARD, 0.0, 1.0)
	if not _cam_ready:
		_cam_yaw = rotation.y
		_cam_yaw_vel = 0.0
		_cam_ready = true
		_cam_pos = _chase_target(ground_speed) - global_position
		_cam_vel = Vector3.ZERO
		_cam_drag = Vector3.ZERO
		_cam_look = global_position + Vector3.UP * 3.4
		_cam_roll = 0.0
	var steps := clampi(int(ceil(delta / 0.0167)), 1, 6)
	var h := minf(delta, 0.1) / float(steps)
	for _i in steps:
		# heading spring: omega 4.5 rad/s, damping 0.65 (swings wide, settles)
		var yaw_err := wrapf(rotation.y - _cam_yaw, -PI, PI)
		_cam_yaw_vel += (yaw_err * 20.0 - _cam_yaw_vel * 5.8) * h
		_cam_yaw += _cam_yaw_vel * h
		# offset spring in the aircraft frame (no steady-state lag at speed):
		# omega 3.4 rad/s, damping 0.78, height stiffer
		var err := (_chase_target(ground_speed) - global_position) - _cam_pos
		var acc := Vector3(err.x * 11.56, err.y * 20.0, err.z * 11.56) - Vector3(_cam_vel.x * 5.3, _cam_vel.y * 7.2, _cam_vel.z * 5.3)
		_cam_vel += acc * h
		_cam_pos += _cam_vel * h
	# a touch of world-space drag: the camera trails a little further when the
	# aircraft accelerates hard and catches up as speed settles
	_cam_drag = _cam_drag.lerp(Vector3(velocity.x, velocity.y * 0.5, velocity.z) * -0.025, clampf(delta * 1.5, 0.0, 1.0))
	var pivot := global_position + Vector3.UP * 3.2
	var cam_pos := global_position + _cam_pos + _cam_drag
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot, cam_pos, 1)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		cam_pos = (hit["position"] as Vector3) + (pivot - cam_pos).normalized() * 0.6
	var look := global_position + Vector3.UP * 3.4 + Vector3(velocity.x, 0.0, velocity.z) * 0.12
	_cam_look = _cam_look.lerp(look, clampf(delta * 4.5, 0.0, 1.0))
	_camera.global_position = cam_pos + Vector3.DOWN * _touch_dip * 0.6
	if cam_pos.distance_to(_cam_look) > 0.5:
		_camera.look_at(_cam_look, Vector3.UP)
	_cam_roll = lerpf(_cam_roll, _body.rotation.z * 0.38, clampf(delta * 2.0, 0.0, 1.0))
	_camera.rotate_object_local(Vector3.FORWARD, -_cam_roll)
	_camera.fov = lerpf(_camera.fov, 62.0 + 8.0 * speed_frac, clampf(delta * 1.2, 0.0, 1.0))

func _chase_target(ground_speed: float) -> Vector3:
	var back := Basis(Vector3.UP, _cam_yaw) * Vector3(0.0, 0.0, 1.0)
	var distance := 10.2 + ground_speed * 0.03
	# rises with speed so the forward-tilted rotor disc is still seen from above
	var height := 6.8 + ground_speed * 0.085 + clampf(absf(velocity.y) * 0.08, 0.0, 1.2)
	return global_position + back * distance + Vector3.UP * height

## Snapshot of the presentation layer for regression checks.
func presentation_state() -> Dictionary:
	var blades: Node3D = _provider_main_rotor if _provider_main_rotor != null else _rotor
	var offset := _camera.global_position - global_position
	return {"rotor_spin": rotor_spin,
		"disc_visible": _fx != null and _fx.disc_shown(),
		"blades_visible": blades != null and blades.visible,
		"camera_current": _camera.current,
		"camera_distance": offset.length(),
		"camera_height": offset.y,
		"camera_behind": offset.dot(-global_transform.basis.z) < 0.0,
		"wash": _fx.wash_intensity if _fx != null else 0.0,
		"wash_visible": _fx != null and _fx.wash_intensity > 0.03}

func is_landed() -> bool:
	return _landed

func is_disabled() -> bool:
	return disabled

func interact(player: Node) -> void:
	if disabled:
		Events.notify.emit("This helicopter will not start.", "warn")
		return
	if pilot_is_player:
		exit_vehicle(player)
		return
	pilot_is_player = true
	# Disable the passenger immediately, before moving it into the vehicle.
	# Waiting for the next player physics tick lets this body cache the
	# passenger as a floor/platform during the transition.
	if player is CollisionObject3D:
		(player as CollisionObject3D).collision_layer = 0
		(player as CollisionObject3D).collision_mask = 0
	player.current_vehicle = self
	player.busy = true
	player.visible = false
	player.global_position = global_position
	_camera.current = true
	Game.set_mode(Game.MODE_HELI)
	Sfx.start_rotor()
	player.busy = false            # the transition is complete
	Events.vehicle_entered.emit(self)
	Events.notify.emit("Helicopter: [Space] climb, [Shift] descend, [W/S] forward/back, [A/D] yaw, [E] exit when landed.", "info")

func exit_vehicle(player: Node) -> void:
	if not pilot_is_player:
		return
	if not is_on_floor():
		Events.notify.emit("Land before exiting.", "warn")
		return
	# The far shore is landable scenery, not walkable district (on foot beyond
	# the district is out of bounds), so exits stay inside the playable area.
	if absf(global_position.x) > 395.0 or global_position.z < -365.0 or global_position.z > 405.0:
		if disabled:
			# A downed aircraft out of bounds cannot fly back: recover the pilot
			# to the last safe point instead of trapping them (release critic).
			Events.notify.emit("Aircraft down outside the district - recovered to your last safe point.", "warn")
			player.respawn_at(Game.last_safe_position, Game.last_safe_rotation)
			return
		Events.notify.emit("Restricted landing area - fly back over the district to exit.", "warn")
		return
	var side := global_transform.basis.x
	var forward := -global_transform.basis.z
	var offsets: Array[Vector3] = [side * 2.8, -side * 2.8, forward * 4.0, -forward * 4.0]
	var exit_pos := Car.find_safe_exit(self, offsets)
	if exit_pos == Vector3.ZERO:
		Events.notify.emit("No clear landing-side exit. Reposition the helicopter.", "warn")
		return
	pilot_is_player = false
	player.global_position = exit_pos
	player.yaw = rotation.y
	player.rotation.y = rotation.y
	player.visible = true
	player.current_vehicle = null
	player.camera.current = true
	player.busy = false
	Game.set_mode(Game.MODE_FOOT)
	Sfx.stop_rotor()
	Events.vehicle_exited.emit(self)
	Events.notify.emit("Landed and on foot.", "info")

func force_exit() -> void:
	pilot_is_player = false
	_yaw_input = 0.0
	_pitch_input = 0.0
	_lift_input = 0.0
	Sfx.stop_rotor()

func take_damage(amount: float, _from_position: Vector3, _by_player: bool = false) -> void:
	if disabled:
		return
	health = maxf(0.0, health - maxf(amount, 0.0))
	if health <= 0.0:
		disabled = true
		Events.notify.emit("Helicopter damaged beyond flight. Descending.", "bad")
