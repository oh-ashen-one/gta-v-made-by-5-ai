class_name HeliFX
extends Node3D
## Helicopter presentation layer (opus55 helicopter piece): motion-blurred
## main/tail rotor discs, a dithered rotor-disc shadow that follows the sun,
## a soft ground-contact shadow, rotor downwash (dust on land, spray and a
## ruffled ripple ring on water) and navigation / anti-collision lights.
## All procedural; nothing here has collision or affects flight.

const WATER_Y := -0.4
const WASH_HEIGHT := 26.0

var heli: CharacterBody3D
var spin := 0.0 ## 0 = stopped, 1 = flight rpm (driven by Helicopter)
var main_hub := Vector3(0.077, 3.45, -0.84)
var main_radius := 3.45
var tail_hub := Vector3(-0.70, 2.31, 3.21)
var tail_radius := 0.62
var attach: Node3D ## the visual root that tilts with the body

var _main_disc: MeshInstance3D
var _main_mat: ShaderMaterial
var _tail_disc: MeshInstance3D
var _tail_mat: ShaderMaterial
var _disc_shadow: MeshInstance3D
var _contact: Decal
var _dust: GPUParticles3D
var _dust_mat: ParticleProcessMaterial
var _dust_draw: StandardMaterial3D
var _wash: MeshInstance3D
var _wash_mat: ShaderMaterial
var _beacons: Array[MeshInstance3D] = []
var _strobes: Array[MeshInstance3D] = []
var _phase := 0.0
var _clock := 0.0
var wash_intensity := 0.0
var over_water := false

const DISC_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float spin = 1.0;
uniform float phase = 0.0;
uniform float blades = 4.0;
uniform vec3 tint : source_color = vec3(0.055, 0.058, 0.062);
uniform vec3 tip_tint : source_color = vec3(0.62, 0.60, 0.52);
uniform float hub = 0.10;
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float r = length(lp);
	if (r > 1.0) { discard; }
	float a = atan(lp.y, lp.x) + phase;
	float k = fract(a * blades / 6.2831853);
	// leading edge is crisp, the trailing smear fades over the sector
	float smear = smoothstep(0.0, 0.035, k) * pow(1.0 - k, 2.6);
	float band = 0.86 + 0.14 * sin(r * 71.0 + k * 3.0);
	float radial = smoothstep(hub, hub + 0.18, r) * (1.0 - smoothstep(0.955, 1.0, r));
	float tip = smoothstep(0.86, 0.90, r) * (1.0 - smoothstep(0.93, 0.965, r));
	float body = (0.11 + 0.36 * smear) * band;
	float alpha = spin * radial * (body + tip * (0.10 + 0.25 * smear));
	// a thin disc seen at a grazing angle still reads (optical density grows)
	float graze = 1.0 - abs(dot(NORMAL, VIEW));
	alpha *= 1.0 + 2.2 * graze * graze;
	float hubcap = 1.0 - smoothstep(hub * 0.55, hub * 0.75, r);
	alpha = max(alpha, hubcap * 0.92);
	ALBEDO = mix(tint, tip_tint, tip * 0.75 * (1.0 - hubcap));
	// matte: a blurred disc must never flare into a white glare streak
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
"""

const WASH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float intensity = 0.0;
uniform float water = 1.0;
uniform vec3 foam : source_color = vec3(0.86, 0.90, 0.91);
uniform vec3 deep : source_color = vec3(0.08, 0.15, 0.17);
uniform vec3 dust : source_color = vec3(0.60, 0.54, 0.45);
varying vec2 lp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float r = length(lp);
	if (r > 1.0) { discard; }
	float ang = atan(lp.y, lp.x);
	float n = noise(vec2(ang * 5.0, r * 9.0 - TIME * 3.2)) * 0.6 + noise(lp * 23.0 + TIME * 0.7) * 0.4;
	// ripple trains running outward from under the rotor
	float rings = pow(0.5 + 0.5 * sin(r * 38.0 - TIME * 11.0 + n * 7.0), 3.0) * smoothstep(0.25, 0.75, noise(vec2(ang * 9.0, r * 4.0 - TIME * 2.0)));
	float edge = smoothstep(0.08, 0.30, r) * (1.0 - smoothstep(0.62, 1.0, r));
	float core = 1.0 - smoothstep(0.0, 0.55, r);
	// a broken foam crest where the wash meets still water
	float crest = smoothstep(0.30, 0.42, r) * (1.0 - smoothstep(0.46, 0.70, r)) * smoothstep(0.35, 0.75, n);
	float foam_amt = clamp(rings * edge * 0.40 + crest * 0.8, 0.0, 1.0);
	vec3 water_col = mix(deep, foam, foam_amt);
	float water_a = intensity * clamp(core * 0.45 + foam_amt * 0.85 + edge * 0.18, 0.0, 0.92);
	float dust_a = intensity * clamp((rings * 0.25 + n * 0.35) * edge + crest * 0.35, 0.0, 0.55);
	ALBEDO = mix(dust, water_col, water);
	ROUGHNESS = mix(0.95, 0.55, water);
	ALPHA = mix(dust_a, water_a, water);
}
"""

func setup(owner_heli: CharacterBody3D, visual_root: Node3D) -> void:
	heli = owner_heli
	attach = visual_root

func _ready() -> void:
	_build_discs()
	_build_ground_fx()
	_build_lights()

## Soft round sprite / mask textures generated once (no external files).
static func _radial_texture(size: int, inner: float, outer: float, peak: float, noisy: bool) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var r := Vector2(x - c, y - c).length() / c
			var a := 0.0
			if r < 1.0:
				a = (1.0 - smoothstep(outer, 1.0, r)) * smoothstep(0.0, maxf(inner, 0.0001), r) if inner > 0.0 else (1.0 - smoothstep(outer, 1.0, r))
				if noisy:
					a *= 0.65 + 0.35 * rng.randf()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a * peak, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Gaussian-soft puff with low-frequency breakup (no per-pixel grain).
static func _soft_puff(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.09
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var r := Vector2(x - c, y - c).length() / c
			var a := exp(-r * r * 3.2) * (0.7 + 0.3 * (noise.get_noise_2d(x, y) * 0.5 + 0.5))
			a *= 1.0 - smoothstep(0.85, 1.0, r)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _disc_material(blades: float, hub: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = DISC_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("blades", blades)
	m.set_shader_parameter("hub", hub)
	m.set_shader_parameter("spin", 0.0)
	return m

func _build_discs() -> void:
	var parent: Node3D = attach if attach != null else self
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 0
	_main_disc = MeshInstance3D.new()
	_main_disc.name = "RotorDisc"
	_main_disc.mesh = plane
	_main_mat = _disc_material(4.0, 0.07)
	_main_disc.material_override = _main_mat
	_main_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_main_disc.position = main_hub + Vector3(0.0, 0.03, 0.0)
	_main_disc.scale = Vector3(main_radius, 1.0, main_radius)
	parent.add_child(_main_disc)
	# Shadow-only twin: an alpha-hashed annulus so the spinning disc casts a
	# partial, sun-aligned shadow on the pad / water instead of four hard bars.
	_disc_shadow = MeshInstance3D.new()
	_disc_shadow.name = "RotorDiscShadow"
	_disc_shadow.mesh = plane
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	sm.albedo_texture = _radial_texture(128, 0.18, 0.93, 0.42, true)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_shadow.material_override = sm
	_disc_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_disc_shadow.position = _main_disc.position
	_disc_shadow.scale = _main_disc.scale
	_disc_shadow.visible = false
	parent.add_child(_disc_shadow)
	_tail_disc = MeshInstance3D.new()
	_tail_disc.name = "TailRotorDisc"
	_tail_disc.mesh = plane
	_tail_mat = _disc_material(2.0, 0.12)
	_tail_disc.material_override = _tail_mat
	_tail_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail_disc.position = tail_hub
	_tail_disc.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	_tail_disc.scale = Vector3(tail_radius, 1.0, tail_radius)
	parent.add_child(_tail_disc)

func _build_ground_fx() -> void:
	# soft contact shadow / ambient occlusion under the airframe
	_contact = Decal.new()
	_contact.name = "ContactShadow"
	_contact.top_level = true
	_contact.size = Vector3(6.5, 4.0, 9.5)
	_contact.texture_albedo = _radial_texture(96, 0.0, 0.25, 0.85, false)
	_contact.modulate = Color(0.0, 0.0, 0.0, 0.0)
	_contact.albedo_mix = 1.0
	_contact.upper_fade = 0.3
	_contact.lower_fade = 0.3
	add_child(_contact)
	# ripple / dust ring under the rotor
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_wash = MeshInstance3D.new()
	_wash.name = "DownwashRing"
	_wash.top_level = true
	_wash.mesh = plane
	var shader := Shader.new()
	shader.code = WASH_SHADER
	_wash_mat = ShaderMaterial.new()
	_wash_mat.shader = shader
	_wash.material_override = _wash_mat
	_wash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wash.visible = false
	add_child(_wash)
	# dust / spray particles thrown radially out of the wash
	_dust = GPUParticles3D.new()
	_dust.name = "DownwashParticles"
	_dust.top_level = true
	_dust.amount = 140
	_dust.lifetime = 2.2
	_dust.preprocess = 0.0
	_dust.randomness = 0.6
	_dust.local_coords = false
	_dust.emitting = false
	_dust.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 24, 80))
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust_mat = ParticleProcessMaterial.new()
	_dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_dust_mat.emission_ring_axis = Vector3.UP
	_dust_mat.emission_ring_radius = 4.5
	_dust_mat.emission_ring_inner_radius = 1.5
	_dust_mat.emission_ring_height = 0.3
	_dust_mat.direction = Vector3(0.0, 1.0, 0.0)
	_dust_mat.spread = 25.0
	_dust_mat.initial_velocity_min = 0.6
	_dust_mat.initial_velocity_max = 2.4
	_dust_mat.radial_velocity_min = 7.0
	_dust_mat.radial_velocity_max = 15.0
	_dust_mat.damping_min = 2.5
	_dust_mat.damping_max = 4.5
	_dust_mat.gravity = Vector3(0.0, -0.6, 0.0)
	_dust_mat.angle_min = -180.0
	_dust_mat.angle_max = 180.0
	_dust_mat.angular_velocity_min = -40.0
	_dust_mat.angular_velocity_max = 40.0
	_dust_mat.scale_min = 0.8
	_dust_mat.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	_dust_mat.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 0.13))
	ramp.add_point(0.55, Color(1, 1, 1, 0.06))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	_dust_mat.color_ramp = gt
	_dust.process_material = _dust_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 3.2)
	_dust_draw = StandardMaterial3D.new()
	_dust_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_draw.billboard_keep_scale = true
	_dust_draw.vertex_color_use_as_albedo = true
	_dust_draw.albedo_texture = _soft_puff(64)
	_dust_draw.albedo_color = Color(0.78, 0.72, 0.62)
	_dust_draw.proximity_fade_enabled = true
	_dust_draw.proximity_fade_distance = 0.8
	_dust_draw.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_dust_draw.distance_fade_min_distance = 0.6
	_dust_draw.distance_fade_max_distance = 3.0
	quad.material = _dust_draw
	_dust.draw_pass_1 = quad
	add_child(_dust)

func disc_shown() -> bool:
	return _main_disc != null and _main_disc.visible

func _light_bulb(pos: Vector3, color: Color, energy: float, radius: float) -> MeshInstance3D:
	var parent: Node3D = attach if attach != null else self
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	bulb.mesh = sphere
	bulb.material_override = Palette.emissive(color, energy)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.position = pos
	parent.add_child(bulb)
	return bulb

func _build_lights() -> void:
	# navigation lights: red to port (-X), green to starboard (+X), white tail
	_light_bulb(Vector3(-0.98, 1.05, -0.9), Color(1.0, 0.12, 0.08), 1.2, 0.045)
	_light_bulb(Vector3(0.98, 1.05, -0.9), Color(0.15, 1.0, 0.35), 1.2, 0.045)
	_light_bulb(Vector3(-0.66, 2.95, 3.55), Color(1.0, 0.95, 0.85), 1.0, 0.04)
	# red anti-collision beacons (top of the engine fairing and the belly)
	_beacons.append(_light_bulb(Vector3(0.08, 3.30, 0.45), Color(1.0, 0.08, 0.05), 3.0, 0.06))
	_beacons.append(_light_bulb(Vector3(0.0, 0.62, 0.2), Color(1.0, 0.08, 0.05), 3.0, 0.055))
	# white strobe at the tail
	_strobes.append(_light_bulb(Vector3(-0.66, 3.05, 3.6), Color(1.0, 1.0, 1.0), 4.0, 0.045))

func _process(delta: float) -> void:
	_clock += delta
	# visual blade sweep: slow enough to read as a smeared, strobing disc
	_phase = fmod(_phase + delta * (2.6 + 3.4 * spin), TAU)
	var disc_alpha := smoothstep(0.30, 0.85, spin)
	_main_mat.set_shader_parameter("spin", disc_alpha)
	_main_mat.set_shader_parameter("phase", _phase)
	_tail_mat.set_shader_parameter("spin", smoothstep(0.2, 0.7, spin))
	_tail_mat.set_shader_parameter("phase", -_phase * 2.3)
	_main_disc.visible = disc_alpha > 0.01
	_tail_disc.visible = spin > 0.2
	_disc_shadow.visible = disc_alpha > 0.5
	# beacons pulse at ~1 Hz, strobe double-flashes
	var beat := fmod(_clock, 1.1)
	for b in _beacons:
		b.visible = beat < 0.16
	var sbeat := fmod(_clock + 0.4, 1.3)
	for s in _strobes:
		s.visible = sbeat < 0.05 or (sbeat > 0.14 and sbeat < 0.19)

func _physics_process(delta: float) -> void:
	if heli == null or not is_inside_tree():
		return
	var origin := heli.global_position + Vector3.UP * 1.0
	var space := heli.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * (WASH_HEIGHT + 4.0), 1)
	query.exclude = [heli.get_rid()]
	var hit := space.intersect_ray(query)
	var ground := Vector3.ZERO
	var has_ground := false
	over_water = false
	if not hit.is_empty():
		ground = hit["position"]
		has_ground = true
		if ground.y < WATER_Y + 0.05:
			over_water = true
	elif origin.y - WATER_Y < WASH_HEIGHT + 4.0:
		ground = Vector3(origin.x, WATER_Y, origin.z)
		has_ground = true
		over_water = true
	var agl := (heli.global_position.y - ground.y) if has_ground else 999.0
	# contact shadow under the skids
	if has_ground and agl < 14.0:
		_contact.global_position = ground + Vector3.UP * 0.4
		_contact.rotation = Vector3(0.0, heli.rotation.y, 0.0)
		_contact.modulate = Color(0.0, 0.0, 0.0, clampf(0.75 * (1.0 - agl / 14.0), 0.0, 0.75))
		_contact.visible = true
	else:
		_contact.visible = false
	# downwash strength: rpm x proximity
	var target := 0.0
	if has_ground:
		target = smoothstep(0.6, 1.0, spin) * clampf(1.0 - (agl - 2.0) / (WASH_HEIGHT - 2.0), 0.0, 1.0)
	wash_intensity = lerpf(wash_intensity, target, clampf(delta * 3.0, 0.0, 1.0))
	var active := wash_intensity > 0.03
	_wash.visible = active
	_dust.emitting = active
	if not active:
		return
	var radius := lerpf(7.0, 15.0, clampf(agl / WASH_HEIGHT, 0.0, 1.0)) * (0.7 + 0.3 * wash_intensity)
	_wash.global_position = ground + Vector3.UP * (0.06 if over_water else 0.05)
	_wash.scale = Vector3(radius, 1.0, radius)
	_wash_mat.set_shader_parameter("intensity", wash_intensity)
	_wash_mat.set_shader_parameter("water", 1.0 if over_water else 0.0)
	_dust.global_position = ground + Vector3.UP * 0.25
	_dust.amount_ratio = clampf(wash_intensity, 0.05, 1.0)
	_dust_mat.emission_ring_radius = radius * 0.32
	_dust_mat.emission_ring_inner_radius = radius * 0.12
	if over_water:
		_dust_draw.albedo_color = Color(0.90, 0.94, 0.96, 0.9)
		_dust_mat.initial_velocity_min = 1.5
		_dust_mat.initial_velocity_max = 4.5
		_dust_mat.gravity = Vector3(0.0, -2.2, 0.0)
	else:
		_dust_draw.albedo_color = Color(0.80, 0.75, 0.66, 0.55)
		_dust_mat.initial_velocity_min = 0.2
		_dust_mat.initial_velocity_max = 1.2
		_dust_mat.gravity = Vector3(0.0, -0.6, 0.0)
