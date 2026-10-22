extends Node3D
## Vehicle presentation layer (opus55 "driving" piece). One child of every Car.
##
## Every car: sprung body roll / pitch / heave driven by the real longitudinal and
## lateral acceleration of the kinematic body, clear-coat paint, and tail-light
## coronas that flare when the car brakes.
## Player-driven car only (built lazily on first entry): a weighted chase camera
## (yaw lag, longitudinal spring, speed FOV kick, collision impulse kick only),
## a moving reflection probe so the paint mirrors the street, headlight beams,
## rear-tyre smoke, skid marks (one MultiMesh ring buffer), impact sparks,
## damage smoke, and a speed-scaled radial blur at the frame edges.
## No assets are loaded: every texture, mesh and shader here is generated.

const ROLL_PER_G := 0.0062        # rad of body roll per m/s^2 lateral
const PITCH_PER_G := 0.0034       # rad of body pitch per m/s^2 longitudinal
const MAX_ROLL := 0.075
const MAX_PITCH := 0.055
const SPRING_K := 70.0            # body spring stiffness (1/s^2)
const SPRING_D := 7.5             # damping (under-damped: one visible settle)
const SKID_COUNT := 2400
const VISUAL_LAYER_SELF := 1 << 19   # player car body, hidden from its own probe
const CarDamageScript := preload("res://src/actors/car_damage.gd")

var car: Car
var _base_xform := Transform3D.IDENTITY
var _body_node: Node3D = null
var _pivot := Vector3(0.0, 0.45, 0.0)
var _aabb := AABB()
var _prev_speed := 0.0
var _prev_yaw := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _pitch := 0.0
var _pitch_v := 0.0
var _heave := 0.0
var _heave_v := 0.0
var _prev_y := 0.0
var _long_acc := 0.0
var _lat_acc := 0.0
var _braking := false
var _lights_on := true
var _player_rig_built := false

# shared resources (built once)
static var _corona_tex: Texture2D
static var _smoke_tex: Texture2D
static var _tail_mat: StandardMaterial3D
static var _brake_mat: StandardMaterial3D
static var _head_mat: StandardMaterial3D
static var _paint_cache: Dictionary = {}
static var _corona_mesh: QuadMesh
static var _probe_prewarmed := false

var _tail_coronas: Array[MeshInstance3D] = []
var _head_coronas: Array[MeshInstance3D] = []

# player rig
var camera: Camera3D
var _cam_yaw := 0.0
var _cam_pos := Vector3.ZERO
var _cam_long := 0.0
var _cam_long_v := 0.0
var _cam_fov := 70.0
var _cam_snap := true
var _trauma := 0.0
var _shake_t := 0.0
var _probe: ReflectionProbe
var _brake_light: OmniLight3D
var _head_beams: Array[SpotLight3D] = []
var _smoke: Array[GPUParticles3D] = []
var _sparks: GPUParticles3D
var _damage_smoke: GPUParticles3D
var _skids: MultiMeshInstance3D
var _skid_head := 0
var _skid_last: Array[Vector3] = [Vector3.INF, Vector3.INF]
## driving-q: chase-camera motion blur (compositor effect) and its state.
var motion_blur: CarMotionBlur = null
var _blur_frames := 0             # frames since the chase camera went live
var _blur_prev_cam := Transform3D.IDENTITY
const SHUTTER_S := 0.8 / 60.0     # exposure: 0.8 of a 60 Hz frame (~290-degree shutter)
var _slip := 0.0
var _probe_timer := 0.0
var _debris_t := 0.0
var _squeal: AudioStreamPlayer3D
## Gearbox model for the engine note: upper speed (m/s) of each gear.
const GEARS := [8.5, 14.0, 19.5, 24.5, 30.0]
const PROBE_STEP := 0.45
var _impact_cool := 0.0
## driving-p: on-foot -> chase camera blend on entry, lateral weight swing.
var _entry_from := Transform3D.IDENTITY
var _entry_fov := 68.0
var _entry_t := 1.0
var _cam_lat := 0.0
var _cam_lat_v := 0.0
## QA readback (self_test / showcase): last values applied to the body.
var last_roll := 0.0
var last_pitch := 0.0
var skid_marks_laid := 0
var sparks_fired := 0

func setup(owner_car: Car, provider_root: Node3D) -> void:
	car = owner_car
	name = "CarFx"
	_body_node = provider_root
	if _body_node != null:
		_base_xform = _body_node.transform
		_aabb = _visual_aabb(_body_node)
	if _aabb.size == Vector3.ZERO:
		_aabb = AABB(Vector3(-0.92, 0.0, -2.2), Vector3(1.85, 1.45, 4.4))
	if _body_node != null:
		# driving-p: clean clear-coat body shader, dents, debris and glass.
		var dmg := CarDamageScript.new()
		add_child(dmg)
		dmg.setup(car, _body_node, _aabb, _base_xform)
		car.damage = dmg
	_pivot = Vector3(0.0, _aabb.position.y + _aabb.size.y * 0.32, _aabb.get_center().z)
	_build_coronas()
	_build_contact_shadow()
	_build_rear_detail()
	_prev_yaw = car.rotation.y
	if not _probe_prewarmed and not "--no-car-probe" in OS.get_cmdline_user_args():
		_probe_prewarmed = true
		_prewarm_probe.call_deferred()

## The first render of a reflection probe compiles the probe-pass pipelines
## for every nearby material (~0.6 s measured on car entry, merged build).
## Pay that once at load, behind the title/start, with a throwaway probe.
func _prewarm_probe() -> void:
	if not is_inside_tree(): return
	var warm := ReflectionProbe.new()
	warm.update_mode = ReflectionProbe.UPDATE_ONCE
	warm.size = Vector3(90.0, 40.0, 90.0)
	warm.max_distance = 160.0
	warm.mesh_lod_threshold = 12.0
	warm.enable_shadows = false
	warm.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	warm.intensity = 0.0
	warm.top_level = true
	get_tree().current_scene.add_child(warm)
	warm.global_position = Game.player_position + Vector3(0.0, 1.4, 0.0)
	# Sweep it over the road grid so materials across the district are seen
	# once (a single start-point warm-up left a 0.43 s hitch mid-drive).
	var spots: Array[Vector3] = [Game.player_position]
	var world_node = get_tree().current_scene.get("world")
	if world_node != null and world_node.get("traffic_nodes") != null:
		var nodes: Array = world_node.traffic_nodes
		for i in range(0, nodes.size(), 2):
			spots.append(nodes[i])
	for spot in spots:
		if not is_instance_valid(warm): return
		warm.global_position = spot + Vector3(0.0, 1.4, 0.0)
		for f in 7:
			await get_tree().process_frame
	if is_instance_valid(warm): warm.queue_free()

## Merged visual bounds of the provider body in Car space.
func _visual_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := car.global_transform.affine_inverse() if car.is_inside_tree() else Transform3D.IDENTITY
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		if String(m.name).begins_with("wheel_"): continue
		var xf: Transform3D = inv * m.global_transform if car.is_inside_tree() else _local_chain(m, root)
		var box: AABB = xf * m.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

func _local_chain(node: Node3D, stop: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != car:
		if n is Node3D: xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

## Clear-coat over the provider's baked albedo: the base keeps its texture and
## metal map, the coat adds a sharp sky/street reflection on top.
func _upgrade_paint(root: Node3D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		for i in m.mesh.get_surface_count():
			var src: Material = m.get_surface_override_material(i)
			if src == null: src = m.mesh.surface_get_material(i)
			if not src is StandardMaterial3D: continue
			var key := src.get_instance_id()
			var coat: StandardMaterial3D = _paint_cache.get(key)
			if coat == null:
				coat = (src as StandardMaterial3D).duplicate()
				coat.clearcoat_enabled = true
				coat.clearcoat = 1.0
				# C2: a 0.06 coat turned the sun into single-pixel fireflies and a
				# blown roof hotspot; 0.16 keeps sharp sky/building reflections.
				coat.clearcoat_roughness = 0.16
				# The Tripo maps report metal 1 / rough 1 scaled by texture. Full
				# metal read as a dark murky mass in shade (critic C1): a dielectric
				# base under the coat keeps the body colour lit by sun and sky.
				coat.metallic = minf(coat.metallic, 0.22)
				coat.roughness = 0.42
				coat.metallic_specular = 0.5
				coat.albedo_color = coat.albedo_color * Color(1.18, 1.18, 1.18, 1.0)
				_paint_cache[key] = coat
			m.set_surface_override_material(i, coat)

static func _make_corona_tex() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var core := clampf(1.0 - d * 3.4, 0.0, 1.0)
			var halo := pow(clampf(1.0 - d, 0.0, 1.0), 4.0)
			var a := clampf(core + halo * 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)

static func _make_smoke_tex() -> Texture2D:
	var size := 64
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.35, 0.0, 1.0)
			a = a * a * (0.45 + n * 0.75)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

static func _corona_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.albedo_texture = _corona_tex
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, 1.0)
	m.disable_receive_shadows = true
	m.render_priority = 2
	return m

func _build_coronas() -> void:
	if _corona_tex == null:
		_corona_tex = _make_corona_tex()
		_smoke_tex = _make_smoke_tex()
		_corona_mesh = QuadMesh.new()
		_corona_mesh.size = Vector2(1.0, 1.0)
		_tail_mat = _corona_material(Color(1.0, 0.10, 0.05), 0.55)
		_brake_mat = _corona_material(Color(1.0, 0.16, 0.08), 2.6)
		_head_mat = _corona_material(Color(1.0, 0.93, 0.80), 1.0)
	var rear_z := _aabb.end.z - 0.16
	var front_z := _aabb.position.z + 0.10
	var hx := _aabb.size.x * 0.33
	var tail_y := _aabb.position.y + _aabb.size.y * 0.56
	var head_y := _aabb.position.y + _aabb.size.y * 0.47
	for sx in [-1.0, 1.0]:
		var t := MeshInstance3D.new()
		t.mesh = _corona_mesh
		t.material_override = _tail_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.position = Vector3(hx * sx, tail_y, rear_z + 0.06)
		t.scale = Vector3.ONE * 0.17
		t.visibility_range_end = 160.0
		add_child(t)
		_tail_coronas.append(t)
		var h := MeshInstance3D.new()
		h.mesh = _corona_mesh
		h.material_override = _head_mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.position = Vector3(hx * 0.98 * sx, head_y, front_z - 0.06)
		h.scale = Vector3.ONE * 0.26
		h.visibility_range_end = 160.0
		add_child(h)
		_head_coronas.append(h)

## C2: a soft ground-contact shadow (decal) so every car sits on the road
## even where the sun shadow falls behind it (critic C1: no contact shadow).
static var _contact_tex: Texture2D
func _build_contact_shadow() -> void:
	if _contact_tex == null:
		var w := 32
		var h := 64
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var u := absf((x + 0.5) / w * 2.0 - 1.0)
				var v := absf((y + 0.5) / h * 2.0 - 1.0)
				var d := pow(pow(u, 4.0) + pow(v, 4.0), 0.25)
				var a := clampf((1.0 - d) / 0.45, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * a * (3.0 - 2.0 * a)))
		_contact_tex = ImageTexture.create_from_image(img)
	var decal := Decal.new()
	decal.name = "ContactShadow"
	decal.texture_albedo = _contact_tex
	decal.modulate = Color(1.0, 1.0, 1.0, 0.5)
	decal.size = Vector3(_aabb.size.x * 1.12, 0.6, _aabb.size.z * 1.02)
	decal.position = Vector3(_aabb.get_center().x, _aabb.position.y - 0.08, _aabb.get_center().z)
	decal.upper_fade = 0.15
	decal.lower_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 70.0
	decal.distance_fade_length = 20.0
	decal.cull_mask = 1
	add_child(decal)

## C2: readable rear at 720p (critic C1: plate and rear detail lost): a
## Singapore-style rear plate (black characters on yellow). Original
## lettering, no brands.
static var _plate_mat: StandardMaterial3D
const PLATE_PREFIX := ["SJK", "SKF", "SLA", "SGB", "SMT", "SNX", "SDR", "SKP"]
func _build_rear_detail() -> void:
	if car.kind == "van": return
	if _plate_mat == null:
		_plate_mat = StandardMaterial3D.new()
		_plate_mat.albedo_color = Color(0.93, 0.76, 0.12)
		_plate_mat.roughness = 0.45
	var rear := _aabb.end.z
	var y0 := _aabb.position.y
	var h := _aabb.size.y
	# Ride on the sprung body (roll/pitch) rather than the chassis.
	var holder := Node3D.new()
	holder.name = "RearDetail"
	if _body_node != null:
		_body_node.add_child(holder)
		holder.transform = _base_xform.affine_inverse()
	else:
		add_child(holder)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.56, 0.135, 0.012)
	plate.mesh = pm
	plate.material_override = _plate_mat
	# Covers the provider model's baked (unreadable) plate recess.
	plate.position = Vector3(0.0, y0 + h * 0.385, rear + 0.004)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.visibility_range_end = 60.0
	holder.add_child(plate)
	var label := Label3D.new()
	var seed_n := absi(car.get_instance_id())
	label.text = "%s %d %s" % [PLATE_PREFIX[seed_n % PLATE_PREFIX.size()], 1000 + seed_n % 8999, "ABCDEGHJKLMPRSTUXYZ"[seed_n % 19]]
	label.font_size = 64
	label.pixel_size = 0.0011
	label.outline_size = 0
	label.modulate = Color(0.03, 0.03, 0.03)
	label.shaded = true
	label.double_sided = false
	label.position = Vector3(0.0, 0.0, 0.0075)
	label.rotation = Vector3(0.0, 0.0, 0.0)
	label.visibility_range_end = 45.0
	plate.add_child(label)

func body_node() -> Node3D:
	return _body_node

# ------------------------------------------------------------------ simulation
func _physics_process(delta: float) -> void:
	if car == null or delta <= 0.0: return
	var active := car.driver_is_player or car.has_ai
	_set_lights(active or car.occupied_by_npc)
	if not active and absf(_roll) + absf(_pitch) + absf(_heave) < 0.0005 and absf(_roll_v) + absf(_pitch_v) < 0.001:
		_set_brake(false)
		return
	if car.has_ai and not car.driver_is_player and car.global_position.distance_squared_to(Game.player_position) > 120.0 * 120.0:
		return
	var speed := car.forward_speed()
	var pre_speed := _prev_speed
	_long_acc = lerpf(_long_acc, (speed - _prev_speed) / delta, clampf(delta * 14.0, 0.0, 1.0))
	var yaw_rate := angle_difference(_prev_yaw, car.rotation.y) / delta
	_lat_acc = lerpf(_lat_acc, speed * yaw_rate, clampf(delta * 12.0, 0.0, 1.0))
	_prev_speed = speed
	_prev_yaw = car.rotation.y
	# Sprung body: braking dives the nose, acceleration squats, cornering rolls
	# outward. Under-damped so it settles with one visible rebound.
	var roll_target := clampf(_lat_acc * ROLL_PER_G, -MAX_ROLL, MAX_ROLL)
	var pitch_target := clampf(-_long_acc * PITCH_PER_G, -MAX_PITCH, MAX_PITCH)
	_roll_v += ((roll_target - _roll) * SPRING_K - _roll_v * SPRING_D) * delta
	_roll += _roll_v * delta
	_pitch_v += ((pitch_target - _pitch) * SPRING_K - _pitch_v * SPRING_D) * delta
	_pitch += _pitch_v * delta
	var dy := car.global_position.y - _prev_y
	_prev_y = car.global_position.y
	if absf(dy) > 0.08 and absf(dy) < 0.5: _heave_v -= dy * 9.0   # kerb step jolt
	_heave_v += ((0.0 - _heave) * SPRING_K * 1.4 - _heave_v * SPRING_D) * delta
	_heave += _heave_v * delta
	_apply_body()
	_set_brake(_long_acc < -3.0 and absf(speed) > 0.6 or (car.driver_is_player and Input.is_action_pressed("move_back") and speed > 0.3))
	if car.driver_is_player:
		_player_fx(delta, speed, pre_speed)

func _apply_body() -> void:
	last_roll = _roll
	last_pitch = _pitch
	if _body_node == null: return
	# Pitch: positive _pitch lifts the nose (car faces -Z, so +X rotation).
	var rot := Basis(Vector3.FORWARD, _roll) * Basis(Vector3.RIGHT, _pitch)
	var pivot_xf := Transform3D(Basis.IDENTITY, _pivot + Vector3(0.0, _heave, 0.0))
	_body_node.transform = pivot_xf * Transform3D(rot, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -_pivot) * _base_xform

## Parked, empty cars sit dark; driven ones show tail and head lamps.
func _set_lights(on: bool) -> void:
	if on == _lights_on: return
	_lights_on = on
	for c in _tail_coronas + _head_coronas:
		c.visible = on
	if car.damage != null: car.damage.set_lamps(1.0 if _braking else 0.0, 1.0 if on else 0.0)

func _set_brake(on: bool) -> void:
	if on == _braking: return
	_braking = on
	for t in _tail_coronas:
		t.material_override = _brake_mat if on else _tail_mat
		if t.scale != Vector3.ZERO: t.scale = Vector3.ONE * (0.30 if on else 0.17)
	if _brake_light != null:
		_brake_light.visible = on
	if car.damage != null: car.damage.set_lamps(1.0 if on else 0.0, 1.0 if _lights_on else 0.0)

# ------------------------------------------------------------- player rig
func build_player_rig() -> void:
	if _player_rig_built: return
	_player_rig_built = true
	camera = car._camera
	camera.top_level = true
	_cam_snap = true
	# Moving reflection probe: the paint and glass mirror the real street and
	# sky around the car instead of only the sky dome.
	_probe = ReflectionProbe.new()
	# Time-sliced: UPDATE_ONCE re-renders over six frames whenever the probe
	# moves, and it is only re-placed every PROBE_STEP seconds (UPDATE_ALWAYS
	# cost about a third of the frame rate in the showcase run).
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.top_level = true
	_probe.size = Vector3(90.0, 40.0, 90.0)
	_probe.origin_offset = Vector3(0.0, 1.2, 0.0)
	_probe.position = Vector3(0.0, 1.4, 0.0)
	_probe.max_distance = 160.0
	_probe.intensity = 1.0
	_probe.box_projection = false
	_probe.enable_shadows = false
	_probe.mesh_lod_threshold = 12.0
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_probe.cull_mask = 0xFFFFF & ~VISUAL_LAYER_SELF
	_probe.visible = false
	add_child(_probe)
	# QA A/B switch: --no-car-probe keeps the paint on sky-only reflections.
	if "--no-car-probe" in OS.get_cmdline_user_args():
		_probe.queue_free()
		_probe = null
	# Brake glow spilling on the road and the body behind the car.
	_brake_light = OmniLight3D.new()
	_brake_light.light_color = Color(1.0, 0.12, 0.06)
	_brake_light.light_energy = 0.9
	_brake_light.omni_range = 4.0
	_brake_light.shadow_enabled = false
	_brake_light.position = Vector3(0.0, _aabb.position.y + _aabb.size.y * 0.5, _aabb.end.z + 0.5)
	_brake_light.visible = _braking
	add_child(_brake_light)
	for sx in [-1.0, 1.0]:
		var beam := SpotLight3D.new()
		beam.light_color = Color(1.0, 0.94, 0.82)
		beam.light_energy = 3.0
		beam.spot_range = 34.0
		beam.spot_angle = 24.0
		beam.spot_attenuation = 1.2
		beam.shadow_enabled = false
		beam.position = Vector3(_aabb.size.x * 0.35 * sx, _aabb.position.y + _aabb.size.y * 0.45, _aabb.position.z)
		beam.rotation_degrees = Vector3(-7.0, 0.0, 0.0)
		beam.visible = false
		add_child(beam)
		_head_beams.append(beam)
	# Rear-tyre smoke.
	for sx in [-1.0, 1.0]:
		var p := _make_smoke(Color(0.84, 0.84, 0.85, 0.34), 80)
		p.position = Vector3(_aabb.size.x * 0.42 * sx, 0.25, _aabb.end.z - _aabb.size.z * 0.22)
		add_child(p)
		_smoke.append(p)
	_damage_smoke = _make_smoke(Color(0.2, 0.2, 0.22, 0.6), 48)
	_damage_smoke.position = Vector3(0.0, _aabb.end.y - 0.1, _aabb.position.z + _aabb.size.z * 0.18)
	add_child(_damage_smoke)
	_sparks = _make_sparks()
	add_child(_sparks)
	var squeal_stream: AudioStream = Sfx.loop_stream("tyre")
	if squeal_stream != null and DisplayServer.get_name() != "headless":
		_squeal = AudioStreamPlayer3D.new()
		_squeal.stream = squeal_stream
		_squeal.volume_db = -80.0
		_squeal.unit_size = 10.0
		_squeal.max_distance = 120.0
		_squeal.position = Vector3(0.0, 0.3, _aabb.end.z - 0.8)
		add_child(_squeal)
	_build_skids()
	_build_blur()

func _make_smoke(color: Color, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.1
	p.local_coords = false
	p.emitting = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 25, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.0, 0.55, 0.0)
	pm.damping_min = 1.2
	pm.damping_max = 2.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.9
	pm.scale_max = 1.5
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(1.0, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, color.a))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	grad.add_point(0.15, Color(color.r, color.g, color.b, color.a))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _smoke_tex
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	m.disable_receive_shadows = true
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.5, 0.5)
	quad.material = m
	p.draw_pass_1 = quad
	return p

func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 0.85
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-15, -3, -15), Vector3(30, 10, 30))
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 62.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0.0, -18.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.55, 1.0))
	grad.set_color(1, Color(1.0, 0.28, 0.04, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.010, 0.11)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(3.2, 1.5, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# C2: streaks that reach the lens fade out instead of filling the frame.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 1.2
	m.distance_fade_max_distance = 3.5
	quad.material = m
	p.draw_pass_1 = quad
	return p

func _build_skids() -> void:
	_skids = MultiMeshInstance3D.new()
	_skids.top_level = true
	_skids.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.012, 0.011, 0.010, 1.0)
	# C2: at 0.38 the rubber mirrored the sky and read as a light-grey line.
	m.roughness = 0.95
	m.metallic_specular = 0.08
	m.disable_receive_shadows = false
	m.render_priority = -1
	quad.material = m
	mm.mesh = quad
	mm.instance_count = SKID_COUNT
	mm.visible_instance_count = 0
	_skids.multimesh = mm
	_skids.custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 400, 8000))
	add_child(_skids)
	_skids.global_transform = Transform3D.IDENTITY

## driving-q: the old frame-edge radial blur (a screen-texture quad that only
## touched the outer frame and left the lower-third road as static speckle)
## is replaced by per-pixel motion blur along the engine's motion vectors, a
## compositor effect on the chase camera only (car_motion_blur.gd).
func _build_blur() -> void:
	if "--no-motion-blur" in OS.get_cmdline_user_args(): return
	motion_blur = CarMotionBlur.new()
	var comp := Compositor.new()
	comp.compositor_effects = [motion_blur]
	camera.compositor = comp

## Start the chase camera from where the on-foot camera was (no hard cut).
func begin_entry_blend(from_cam: Camera3D) -> void:
	if from_cam == null or not from_cam.is_inside_tree(): return
	# The route's fixed 05_car_entered comparison frame is shot on the entry
	# tick; keep it the settled chase view there.
	if "--capture" in OS.get_cmdline_user_args(): return
	_entry_from = from_cam.global_transform
	_entry_fov = from_cam.fov
	_entry_t = 0.0

## Called by the car when the player takes or leaves it.
func on_player_changed(driving: bool) -> void:
	if driving:
		build_player_rig()
		_cam_snap = true
	_set_self_layer(driving)
	if _probe != null:
		_probe.visible = driving
		_probe_timer = 0.0
	for b in _head_beams: b.visible = driving
	_blur_frames = 0
	if motion_blur != null: motion_blur.shutter = 0.0
	for p in _smoke: p.emitting = false
	if _squeal != null and not driving: _squeal.stop()
	if not driving and camera != null:
		camera.fov = 64.0

func _set_self_layer(on: bool) -> void:
	if _body_node == null: return
	for mi in _body_node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = (1 | VISUAL_LAYER_SELF) if on else 1

func _player_fx(delta: float, speed: float, pre_speed: float) -> void:
	_impact_cool = maxf(0.0, _impact_cool - delta)
	var aspeed := absf(speed)
	# Tyre slip: lateral load, hard braking, launch wheelspin and handbrake.
	var lat := absf(_lat_acc)
	var slip := clampf((lat - 15.0) / 12.0, 0.0, 1.0)
	# Hard braking only marks the road (ABS-style), with a wisp of smoke at most.
	if _long_acc < -18.0 and aspeed > 8.0: slip = maxf(slip, clampf((-_long_acc - 18.0) / 6.0, 0.0, 1.0) * 0.3)
	if Input.is_action_pressed("move_forward") and aspeed < 7.0 and aspeed > 0.3 and _long_acc > 8.0: slip = maxf(slip, 0.5)
	slip = maxf(slip, car.drift_amount())
	_slip = lerpf(_slip, slip, clampf(delta * 10.0, 0.0, 1.0))
	var smoking := _slip > 0.34 and aspeed > 1.0
	for p in _smoke:
		p.emitting = smoking
		p.amount_ratio = clampf((_slip - 0.3) * 1.3, 0.08, 1.0)
	if _slip > 0.22 and aspeed > 2.0:
		_lay_skids()
	else:
		_skid_last[0] = Vector3.INF
		_skid_last[1] = Vector3.INF
	_debris_t -= delta
	_damage_smoke.emitting = car.health < 45.0 or _debris_t > 0.0
	_audio(aspeed)

func _lay_skids() -> void:
	var mm := _skids.multimesh
	var basis_car := car.global_transform.basis
	var side := basis_car.x.normalized()
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		var local := Vector3(_aabb.size.x * 0.40 * sx, 0.0, _aabb.end.z - _aabb.size.z * 0.21)
		var p := car.global_transform * local
		# Sit on the actual road surface (the body origin rides a few cm low).
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.7, p - Vector3.UP * 0.7)
		q.collision_mask = 1
		q.exclude = [car.get_rid()]
		var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
		p.y = (float(hit["position"].y) if not hit.is_empty() else car.global_position.y + 0.06) + 0.022
		var last := _skid_last[i]
		if last == Vector3.INF:
			_skid_last[i] = p
			continue
		var seg := p - last
		seg.y = 0.0
		var length := seg.length()
		if length < 0.35: continue
		var fwd := seg / length
		var right := Vector3.UP.cross(fwd).normalized()
		var b := Basis(right * 0.27, Vector3.UP, fwd * (length + 0.06))
		var mid := (p + last) * 0.5
		mid.y = p.y
		mm.set_instance_transform(_skid_head, Transform3D(b, mid))
		# Patchy rubber: per-segment opacity jitter so the line is not a ruled stripe.
		var patch := 0.72 + 0.28 * sin(float(skid_marks_laid) * 1.7 + float(i) * 2.3) * sin(float(skid_marks_laid) * 0.37)
		mm.set_instance_color(_skid_head, Color(1.0, 1.0, 1.0, clampf((0.78 + _slip * 0.3) * patch, 0.0, 0.95)))
		_skid_head = (_skid_head + 1) % SKID_COUNT
		mm.visible_instance_count = mini(SKID_COUNT, maxi(mm.visible_instance_count, _skid_head if mm.visible_instance_count < SKID_COUNT else SKID_COUNT))
		if skid_marks_laid >= SKID_COUNT: mm.visible_instance_count = SKID_COUNT
		skid_marks_laid += 1
		_skid_last[i] = p

func _check_contacts(pre_speed: float) -> void:
	if _impact_cool > 0.0: return
	for i in car.get_slide_collision_count():
		var col := car.get_slide_collision(i)
		var n := col.get_normal()
		if n.y > 0.65: continue
		if col.get_collider() is NPC: continue
		# A kerb face (under the 0.24 m step) is not a crash.
		if not col.get_collider() is Car and col.get_position().y - car.global_position.y < 0.32: continue
		# Closing speed from the drivetrain speed before this tick's contact
		# (Car._check_impact has already clamped _forward to the blocked speed).
		var heading := Vector3(-sin(car._vel_yaw), 0.0, -cos(car._vel_yaw))
		var closing := -(heading * pre_speed).dot(n)
		if closing < 3.0: continue
		var energy := clampf(closing / 18.0, 0.25, 1.0)
		impact_at(col.get_position(), n, energy)
		return

func _audio(aspeed: float) -> void:
	# Engine: revs climb through each gear and drop at the shift.
	var lo := 0.0
	var rpm := 0.0
	for hi in GEARS:
		if aspeed <= hi or hi == GEARS[GEARS.size() - 1]:
			rpm = clampf((aspeed - lo) / (hi - lo), 0.0, 1.0)
			break
		lo = hi
	var throttle_load := 0.12 if Input.is_action_pressed("move_forward") else 0.0
	var pitch := 0.72 + rpm * 0.95 + throttle_load + (0.25 if _slip > 0.5 and aspeed < 8.0 else 0.0)
	Sfx.drive_engine(car, pitch, -16.0 + throttle_load * 25.0)
	if _squeal != null:
		var level := clampf((_slip - 0.25) / 0.6, 0.0, 1.0)
		if level > 0.01 and not _squeal.playing: _squeal.play()
		_squeal.volume_db = lerpf(-50.0, -9.0, level) if level > 0.01 else -80.0
		_squeal.pitch_scale = 0.9 + clampf(aspeed / 30.0, 0.0, 1.0) * 0.25
		if level <= 0.01 and _squeal.playing: _squeal.stop()

## Player car contact (called by Car._player_collision_response): sparks scaled
## to the closing speed, debris, glass, a body jolt, a camera kick and sound.
func crash(where: Vector3, normal: Vector3, closing: float, struck_car: bool) -> void:
	var energy := clampf((closing - 2.0) / 20.0, 0.05, 1.0)
	_impact_cool = 0.25
	sparks_fired += 1
	if _sparks != null:
		var spm := _sparks.process_material as ParticleProcessMaterial
		spm.initial_velocity_min = 1.5 + energy * 3.0
		spm.initial_velocity_max = 3.5 + energy * 7.0
		spm.scale_min = 0.4 + energy * 0.3
		spm.scale_max = 0.7 + energy * 0.6
		spm.direction = (normal + Vector3.UP * 0.6).normalized()
		_sparks.global_position = where + normal * 0.12
		_sparks.amount_ratio = clampf(0.08 + energy * 0.92, 0.0, 1.0)
		_sparks.restart()
		_sparks.emitting = true
	_debris_t = 0.3 + energy * 0.6
	if _damage_smoke != null and energy > 0.35: _damage_smoke.emitting = true
	var car_v := Vector3(car.velocity.x, 0.0, car.velocity.z)
	if car.damage != null:
		CarDamageScript.ensure_sounds()
		if energy > 0.12: car.damage.spawn_debris(where, normal, energy, car_v)
		if energy > 0.32: car.damage.glass_burst(where, normal, energy, car_v)
	_trauma = minf(1.0, _trauma + (0.2 + energy * 0.7) * (0.5 if bool(Game.settings.get("reduced_shake", false)) else 1.0))
	var local_n := car.global_transform.basis.inverse() * normal
	# A hard hit on a corner kills the lamp there.
	if energy > 0.45:
		var lp := car.global_transform.affine_inverse() * where
		var lamps := _head_coronas if lp.z < 0.0 else _tail_coronas
		for c in lamps:
			if signf(c.position.x) == signf(lp.x) or absf(lp.x) < 0.3:
				c.scale = Vector3.ZERO
	_pitch_v += clampf(local_n.z, -1.0, 1.0) * 2.2 * energy
	_roll_v += clampf(-local_n.x, -1.0, 1.0) * 2.0 * energy
	_heave_v += 0.6 * energy
	Sfx.play_at("car_crash" if energy > 0.15 else "impact", where, lerpf(-8.0, 2.0, energy), 0.85 + randf() * 0.25)
	if energy > 0.32: Sfx.play_at("glass_break", where, lerpf(-6.0, 0.0, energy), 0.9 + randf() * 0.2)

## Sparks, a body jolt and a short camera kick for one hard contact.
func impact_at(where: Vector3, normal: Vector3, energy: float) -> void:
	_impact_cool = 0.35
	sparks_fired += 1
	if _sparks != null:
		_sparks.global_position = where + normal * 0.15
		_sparks.amount_ratio = clampf(0.4 + energy * 0.6, 0.0, 1.0)
		_sparks.restart()
		_sparks.emitting = true
	_debris_t = 0.45
	if _damage_smoke != null: _damage_smoke.emitting = true
	_trauma = minf(1.0, _trauma + (0.35 + energy * 0.5) * (0.5 if bool(Game.settings.get("reduced_shake", false)) else 1.0))
	var local_n := car.global_transform.basis.inverse() * normal
	_pitch_v += clampf(local_n.z, -1.0, 1.0) * 1.6 * energy
	_roll_v += clampf(-local_n.x, -1.0, 1.0) * 1.4 * energy
	Sfx.play_at("impact", where, -2.0, 0.7 + randf() * 0.2)

# ------------------------------------------------------------ chase camera
func _process(delta: float) -> void:
	if car == null or not car.driver_is_player or camera == null: return
	if Game.simulation_paused: return
	_update_camera(delta)
	_probe_timer -= delta
	if _probe != null and _probe_timer <= 0.0:
		_probe_timer = PROBE_STEP
		_probe.global_position = car.global_position + Vector3(0.0, 1.4, 0.0) - car.global_transform.basis.z * clampf(car.forward_speed() * 0.4, -4.0, 10.0)

func _update_camera(delta: float) -> void:
	var speed := car.forward_speed()
	var aspeed := absf(speed)
	var ratio := clampf(aspeed / car.max_speed, 0.0, 1.0)
	var car_xf := car.global_transform
	var car_yaw := car.rotation.y
	# Travel heading (velocity) when moving fast enough, so a drift shows the
	# car's flank; while reversing the camera stays behind the nose.
	var vel := Vector2(car.velocity.x, car.velocity.z)
	var target_yaw := car_yaw
	if vel.length() > 4.0 and speed > 0.0:
		target_yaw = lerp_angle(car_yaw, atan2(-vel.x, -vel.y), 0.55)
	if _cam_snap:
		_cam_yaw = car_yaw
		_cam_long = 0.0
		_cam_long_v = 0.0
		_cam_fov = 64.0
	# Yaw lag: the camera swings round after the car, faster at speed.
	var yaw_k := lerpf(2.6, 4.2, ratio)
	_cam_yaw = lerp_angle(_cam_yaw, target_yaw, clampf(delta * yaw_k, 0.0, 1.0))
	# Longitudinal spring: the car pulls away under throttle and the camera
	# closes in under braking, then settles.
	# integ-P seam: closing in under hard braking/reverse is capped (critic: the
	# van's rear filled 60-70% of the frame).
	var long_target := clampf(_long_acc * 0.05, -0.35, 0.55)
	_cam_long_v += ((long_target - _cam_long) * 26.0 - _cam_long_v * 7.0) * delta
	_cam_long += _cam_long_v * delta
	# Framing scales with the body (van is taller/longer than a coupe).
	var size_k: float = {"van": 1.38, "coupe": 0.96, "police": 1.03}.get(car.kind, 1.0)
	var dist := (4.7 + ratio * 0.3) * size_k + _cam_long
	# driving-q: the lens settles lower as speed builds (1.93 m -> ~1.67 m
	# above the road at top speed) for a lower, more cinematic chase angle
	# with more grazing road in the lower third.
	var height := (1.38 - 0.26 * smoothstep(0.25, 0.9, ratio)) * size_k
	var fwd := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
	var cam_right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	# Weight swing: the camera is thrown outward in a corner and settles back.
	var lat_target := clampf(_lat_acc * 0.022, -0.55, 0.55)
	_cam_lat_v += ((lat_target - _cam_lat) * 18.0 - _cam_lat_v * 6.5) * delta
	_cam_lat += _cam_lat_v * delta
	var base := car.global_position
	var pivot := base + Vector3(0.0, 1.25 * size_k, 0.0)
	var desired := base - fwd * dist + cam_right * _cam_lat + Vector3(0.0, height + 0.55, 0.0)
	# Keep the lens out of walls: pull in along the pivot ray.
	var space := car.get_world_3d().direct_space_state
	# integ-P seam: a sphere sweep instead of a thin ray, so a wall beside the
	# lens (not only one straight behind it) pulls the camera in.
	var sq := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.38
	sq.shape = sph
	sq.transform = Transform3D(Basis.IDENTITY, pivot)
	sq.motion = desired - pivot
	sq.collision_mask = 1
	sq.exclude = [car.get_rid()]
	var frac: PackedFloat32Array = space.cast_motion(sq)
	if frac.size() >= 1 and frac[0] < 1.0:
		desired = pivot + (desired - pivot) * maxf(frac[0], 0.12)
	if _cam_snap:
		_cam_pos = desired
	else:
		_cam_pos = _cam_pos.lerp(desired, clampf(delta * 14.0, 0.0, 1.0))
	var look := base + Vector3(0.0, 1.0 * size_k, 0.0) + fwd * (2.6 + ratio * 3.5)
	var xf := Transform3D(Basis.IDENTITY, _cam_pos).looking_at(look, Vector3.UP)
	# Collision kick only (LOOK_DEV: no default shake); decays in ~0.4 s.
	if _trauma > 0.001:
		_shake_t += delta * 38.0
		var amp := _trauma * _trauma
		xf.origin += xf.basis.x * sin(_shake_t * 1.3) * 0.07 * amp + xf.basis.y * sin(_shake_t * 1.7 + 1.0) * 0.05 * amp
		xf.basis = xf.basis.rotated(xf.basis.z.normalized(), sin(_shake_t * 0.9) * 0.012 * amp)
		_trauma = maxf(0.0, _trauma - delta * 2.4)
	# Speed FOV kick, eased so it breathes in rather than snapping.
	var fov_target := 64.0 + 12.0 * pow(ratio, 1.4)
	_cam_fov = lerpf(_cam_fov, fov_target, clampf(delta * 2.2, 0.0, 1.0))
	var fov := _cam_fov
	if _entry_t < 1.0:
		_entry_t = minf(1.0, _entry_t + delta / 0.65)
		var k := _entry_t * _entry_t * (3.0 - 2.0 * _entry_t)
		xf = _entry_from.interpolate_with(xf, k)
		fov = lerpf(_entry_fov, _cam_fov, k)
	camera.global_transform = xf
	camera.fov = fov
	_update_motion_blur(delta, aspeed, xf)
	_cam_snap = false

## Exposure for the motion blur: a fixed shutter time expressed as a fraction
## of this frame, faded in with speed. Off for the first frames on the chase
## camera, during the entry blend and on any camera jump (a cut would smear
## the whole frame along stale motion vectors).
func _update_motion_blur(delta: float, aspeed: float, xf: Transform3D) -> void:
	if motion_blur == null: return
	var jump := xf.origin.distance_to(_blur_prev_cam.origin) > maxf(3.0, aspeed * delta * 3.0) \
		or xf.basis.z.dot(_blur_prev_cam.basis.z) < 0.94
	_blur_prev_cam = xf
	_blur_frames = 0 if (jump or _cam_snap or not camera.current or _entry_t < 1.0) else _blur_frames + 1
	var speed_k := smoothstep(3.0, 13.0, aspeed)
	var frac := clampf(SHUTTER_S / maxf(delta, 1e-4), 0.0, 2.0)
	var vp := camera.get_viewport()
	var vs := vp.get_visible_rect().size if vp != null else Vector2(16.0, 9.0)
	var box := _aabb.grow(0.1)
	box.position.y = maxf(box.position.y, 0.04)
	box.end.y = _aabb.end.y + 0.15
	motion_blur.set_car_mask(camera, car.global_transform, box, vs.x / maxf(vs.y, 1.0))
	motion_blur.debug_mask = "--motion-blur-debug" in OS.get_cmdline_user_args()
	motion_blur.shutter = frac * speed_k if _blur_frames >= 2 else 0.0
