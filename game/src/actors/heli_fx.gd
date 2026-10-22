class_name HeliFX
extends Node3D
## Helicopter presentation layer (opus55 helicopter piece): motion-blurred
## main/tail rotor discs, a dithered rotor-disc shadow that follows the sun,
## a soft ground-contact shadow, rotor downwash (dust on land, spray and a
## ruffled ripple ring on water) and navigation / anti-collision lights.
## All procedural; nothing here has collision or affects flight.
## Wave P: the main disc is a slightly coned mesh whose optical density grows
## as it is seen edge-on (so it never vanishes in a chase frame); downwash on
## water is a ruffled, matte cat's-paw zone with fine whitecap flecks, a lit
## mist skirt and small droplets instead of flat white blotches.

const WATER_Y := -0.4
const WASH_HEIGHT := 24.0
const CONE := 0.05 ## rotor coning: tip rise per unit radius

var heli: CharacterBody3D
var spin := 0.0 ## 0 = stopped, 1 = flight rpm (driven by Helicopter)
var main_hub := Vector3(0.077, 3.45, -0.84)
var main_radius := 3.9
var tail_hub := Vector3(-0.70, 2.31, 3.21)
var tail_radius := 0.66
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
var _drops: GPUParticles3D
var _drops_mat: ParticleProcessMaterial
var _drops_draw: StandardMaterial3D
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
uniform vec3 tint : source_color = vec3(0.075, 0.078, 0.084);
uniform vec3 sheen : source_color = vec3(0.50, 0.52, 0.55);
uniform float hub = 0.08;
uniform float veil = 0.08;
uniform float near_fade = 2.5;
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
// One motion-blurred blade: a crisp leading edge and a smear trailing it.
float smear(float k, float len) {
	return smoothstep(0.0, 0.018, k) * exp(-k / len);
}
void fragment() {
	float r = length(lp);
	if (r > 1.0) { discard; }
	float a = atan(lp.y, lp.x) + phase;
	float k = fract(a * blades / 6.2831853);
	// ghost blades (shutter blur) plus a fainter earlier exposure
	float s = smear(k, 0.24) * 0.78 + smear(fract(k + 0.5), 0.10) * 0.16;
	// blade root starts outside the hub; soft tip edge
	float span = smoothstep(hub + 0.02, hub + 0.16, r) * (1.0 - smoothstep(0.94, 1.0, r));
	// the swept disc is a faint veil everywhere, a little denser to the tips,
	// with a darker tip-path band where the blade tips run
	float v = veil * (0.70 + 0.30 * r) + 0.07 * smoothstep(0.84, 0.93, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float dens = span * clamp(v + s * (1.0 - v), 0.0, 0.95);
	// optical depth: seen edge-on the disc thickens into a dark blurred band
	float c = clamp(abs(dot(NORMAL, VIEW)), 0.30, 1.0);
	float alpha = 1.0 - pow(1.0 - dens, 1.0 / c);
	alpha = min(alpha, 0.80) * spin;
	// a blade sweeping past the camera must not fill the lens
	alpha *= smoothstep(near_fade, near_fade + 3.0, length(VERTEX));
	// visible rotor head
	float hubcap = 1.0 - smoothstep(hub * 0.75, hub * 1.02, r);
	alpha = max(alpha, hubcap * 0.97 * step(0.02, spin));
	// seen from above, the smeared blades catch sky and sun (light grey
	// streaks over dark ground); seen from below they stay dark
	float top = FRONT_FACING ? 1.0 : 0.0;
	vec3 lit = mix(tint, sheen, clamp(s * (0.55 + 0.45 * top) + (0.15 + 0.25 * top) * r, 0.0, 1.0));
	ALBEDO = lit * (1.0 - hubcap) + tint * hubcap;
	ROUGHNESS = mix(0.45, 0.6, hubcap);
	METALLIC = mix(0.15, 0.6, hubcap);
	SPECULAR = 0.45;
	ALPHA = clamp(alpha, 0.0, 0.97);
}
"""

const WASH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float intensity = 0.0;
uniform float water = 1.0;
uniform float radius_m = 10.0;
uniform vec3 matte : source_color = vec3(0.46, 0.55, 0.56);
uniform vec3 foam : source_color = vec3(0.90, 0.93, 0.94);
uniform vec3 dust : source_color = vec3(0.66, 0.60, 0.50);
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
	float rm = r * radius_m;            // metres from the rotor axis
	float circ = 6.2831853 * max(rm, 0.5);
	// cat's paws: wind-roughened streaks stretched radially, running outward
	float paws = noise(vec2(ang * circ / 1.6, rm * 0.9 - TIME * 3.4));
	paws = paws * 0.65 + noise(vec2(ang * circ / 0.5, rm * 2.6 - TIME * 6.0)) * 0.35;
	// ripple trains: fine concentric wavelets travelling out
	float ripple = (0.5 + 0.5 * sin(rm * 5.5 - TIME * 13.0 + paws * 6.0)) * smoothstep(0.35, 0.75, noise(vec2(ang * circ / 3.0, rm * 0.5 - TIME * 2.0)));
	float zone = smoothstep(0.02, 0.18, r) * (1.0 - smoothstep(0.70, 1.0, r));
	// whitecap flecks: small, many, densest in a ring around 0.5-0.75 R
	float ring = smoothstep(0.30, 0.52, r) * (1.0 - smoothstep(0.72, 0.95, r));
	float fleck_n = noise(vec2(ang * circ / 0.35, rm * 3.2 - TIME * 7.5)) * 0.6 + noise(lp * radius_m * 2.2 + TIME * 1.3) * 0.4;
	float flecks = smoothstep(0.60, 0.80, fleck_n) * ring * (0.65 + 0.35 * ripple);
	vec3 water_col = matte * (0.85 + 0.30 * paws + 0.05 * ripple);
	water_col = mix(water_col, foam, clamp(flecks * 1.4, 0.0, 1.0));
	float water_a = intensity * clamp(zone * (0.16 + 0.22 * paws + 0.05 * ripple) + flecks * 0.85, 0.0, 0.85);
	// on land: a thin streaked dust film, no decal blot
	float dust_a = intensity * zone * clamp(paws * 0.42 + flecks * 0.35, 0.0, 0.45);
	ALBEDO = mix(dust * (0.85 + 0.3 * paws), water_col, water);
	ROUGHNESS = mix(0.95, 0.42, water);
	SPECULAR = mix(0.2, 0.35, water);
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

## Unit rotor disc with real coning: the tips ride CONE above the hub, so a
## disc seen almost edge-on still shows a thin swept arc instead of nothing.
static func _coned_disc(rings: int, segments: int, cone: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ri in rings:
		var r0 := float(ri) / float(rings)
		var r1 := float(ri + 1) / float(rings)
		for si in segments:
			var a0 := TAU * float(si) / float(segments)
			var a1 := TAU * float(si + 1) / float(segments)
			var p00 := Vector3(cos(a0) * r0, r0 * cone, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, r0 * cone, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, r1 * cone, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, r1 * cone, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				var radial := Vector3(v.x, 0.0, v.z)
				st.set_normal((Vector3.UP - radial.normalized() * cone).normalized() if radial.length() > 0.001 else Vector3.UP)
				st.add_vertex(v)
	return st.commit()

func _build_discs() -> void:
	var parent: Node3D = attach if attach != null else self
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 0
	_main_disc = MeshInstance3D.new()
	_main_disc.name = "RotorDisc"
	_main_disc.mesh = _coned_disc(6, 48, CONE)
	_main_mat = _disc_material(4.0, 0.07)
	_main_disc.material_override = _main_mat
	_main_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_main_disc.position = main_hub + Vector3(0.0, 0.03, 0.0)
	_main_disc.scale = Vector3(main_radius, main_radius, main_radius)
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
	_disc_shadow.scale = Vector3(main_radius, 1.0, main_radius)
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
	# mist skirt (spray over water, dust over land): big, soft, LIT puffs
	# rolling outward from under the rotor and rising a few metres
	_dust = GPUParticles3D.new()
	_dust.name = "DownwashParticles"
	_dust.top_level = true
	_dust.amount = 150
	_dust.lifetime = 2.8
	_dust.randomness = 0.5
	_dust.local_coords = false
	_dust.emitting = false
	_dust.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 24, 80))
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust_mat = ParticleProcessMaterial.new()
	_dust_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_dust_mat.emission_ring_axis = Vector3.UP
	_dust_mat.emission_ring_radius = 4.5
	_dust_mat.emission_ring_inner_radius = 2.0
	_dust_mat.emission_ring_height = 0.2
	_dust_mat.direction = Vector3(0.0, 1.0, 0.0)
	_dust_mat.spread = 20.0
	_dust_mat.initial_velocity_min = 0.6
	_dust_mat.initial_velocity_max = 2.2
	_dust_mat.radial_velocity_min = 2.0
	_dust_mat.radial_velocity_max = 5.0
	_dust_mat.damping_min = 2.0
	_dust_mat.damping_max = 3.5
	_dust_mat.gravity = Vector3(0.0, -0.3, 0.0)
	_dust_mat.angle_min = -180.0
	_dust_mat.angle_max = 180.0
	_dust_mat.angular_velocity_min = -30.0
	_dust_mat.angular_velocity_max = 30.0
	_dust_mat.scale_min = 0.8
	_dust_mat.scale_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	curve.max_value = 1.0
	var ct := CurveTexture.new()
	ct.curve = curve
	_dust_mat.scale_curve = ct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 0.2))
	ramp.add_point(0.55, Color(1, 1, 1, 0.09))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	_dust_mat.color_ramp = gt
	_dust.process_material = _dust_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 2.4)
	_dust_draw = StandardMaterial3D.new()
	_dust_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_draw.billboard_keep_scale = true
	_dust_draw.vertex_color_use_as_albedo = true
	_dust_draw.albedo_texture = _soft_puff(64)
	_dust_draw.albedo_color = Color(0.78, 0.72, 0.62)
	_dust_draw.roughness = 1.0
	_dust_draw.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_dust_draw.proximity_fade_enabled = true
	_dust_draw.proximity_fade_distance = 0.35
	_dust_draw.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	_dust_draw.distance_fade_min_distance = 1.0
	_dust_draw.distance_fade_max_distance = 4.0
	quad.material = _dust_draw
	_dust.draw_pass_1 = quad
	add_child(_dust)
	# fine spray droplets (water) / grit (land): many small fast specks on
	# ballistic arcs, so the spray reads as spray, not as cotton blobs
	_drops = GPUParticles3D.new()
	_drops.name = "DownwashDroplets"
	_drops.top_level = true
	_drops.amount = 420
	_drops.lifetime = 1.1
	_drops.randomness = 0.6
	_drops.local_coords = false
	_drops.emitting = false
	_drops.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 20, 80))
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops_mat = ParticleProcessMaterial.new()
	_drops_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_drops_mat.emission_ring_axis = Vector3.UP
	_drops_mat.emission_ring_radius = 5.0
	_drops_mat.emission_ring_inner_radius = 2.5
	_drops_mat.emission_ring_height = 0.1
	_drops_mat.direction = Vector3(0.0, 1.0, 0.0)
	_drops_mat.spread = 30.0
	_drops_mat.initial_velocity_min = 2.0
	_drops_mat.initial_velocity_max = 5.0
	_drops_mat.radial_velocity_min = 6.0
	_drops_mat.radial_velocity_max = 13.0
	_drops_mat.damping_min = 0.5
	_drops_mat.damping_max = 1.5
	_drops_mat.gravity = Vector3(0.0, -9.0, 0.0)
	_drops_mat.scale_min = 0.5
	_drops_mat.scale_max = 1.2
	var dramp := Gradient.new()
	dramp.set_color(0, Color(1, 1, 1, 0.0))
	dramp.set_color(1, Color(1, 1, 1, 0.0))
	dramp.add_point(0.08, Color(1, 1, 1, 0.75))
	dramp.add_point(0.7, Color(1, 1, 1, 0.35))
	var dgt := GradientTexture1D.new()
	dgt.gradient = dramp
	_drops_mat.color_ramp = dgt
	_drops.process_material = _drops_mat
	var dquad := QuadMesh.new()
	dquad.size = Vector2(0.17, 0.17)
	_drops_draw = StandardMaterial3D.new()
	_drops_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drops_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_drops_draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_drops_draw.billboard_keep_scale = true
	_drops_draw.vertex_color_use_as_albedo = true
	_drops_draw.albedo_texture = _radial_texture(32, 0.0, 0.2, 1.0, false)
	_drops_draw.albedo_color = Color(0.92, 0.95, 0.97)
	dquad.material = _drops_draw
	_drops.draw_pass_1 = dquad
	add_child(_drops)

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
	_drops.emitting = active
	if not active:
		return
	var radius := lerpf(8.0, 16.0, clampf(agl / WASH_HEIGHT, 0.0, 1.0)) * (0.75 + 0.25 * wash_intensity)
	# pad decks and markings sit up to ~8 cm above the collision top
	_wash.global_position = ground + Vector3.UP * (0.06 if over_water else 0.13)
	_wash.scale = Vector3(radius, 1.0, radius)
	_wash_mat.set_shader_parameter("intensity", wash_intensity)
	_wash_mat.set_shader_parameter("water", 1.0 if over_water else 0.0)
	_wash_mat.set_shader_parameter("radius_m", radius)
	_dust.global_position = ground + Vector3.UP * 0.5
	_dust.amount_ratio = clampf(wash_intensity, 0.05, 1.0)
	_dust_mat.emission_ring_radius = radius * 0.55
	_dust_mat.emission_ring_inner_radius = radius * 0.30
	_drops.global_position = ground + Vector3.UP * 0.1
	_drops.amount_ratio = clampf(wash_intensity * 1.2, 0.05, 1.0)
	_drops_mat.emission_ring_radius = radius * 0.62
	_drops_mat.emission_ring_inner_radius = radius * 0.36
	if over_water:
		_dust_draw.albedo_color = Color(0.80, 0.84, 0.86, 0.5)
		_dust_mat.initial_velocity_min = 0.3
		_dust_mat.initial_velocity_max = 1.4
		_drops_draw.albedo_color = Color(0.93, 0.96, 0.98, 1.0)
		_drops_mat.initial_velocity_min = 2.0
		_drops_mat.initial_velocity_max = 5.5
		_drops_mat.scale_min = 0.5
		_drops_mat.scale_max = 1.3
	else:
		_dust_draw.albedo_color = Color(0.68, 0.62, 0.52, 1.0)
		_dust_mat.initial_velocity_min = 0.9
		_dust_mat.initial_velocity_max = 2.4
		_drops_draw.albedo_color = Color(0.36, 0.32, 0.27, 0.9)
		_drops_mat.initial_velocity_min = 0.8
		_drops_mat.initial_velocity_max = 2.4
		_drops_mat.scale_min = 0.3
		_drops_mat.scale_max = 0.8
