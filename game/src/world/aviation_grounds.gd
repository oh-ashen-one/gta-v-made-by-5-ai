class_name AviationGrounds
extends RefCounted
## Aviation compound grounds (opus55 helicopter piece, wave P). The block
## interior used to be one bare brown concrete field around the pad, which the
## run-1 critic called "bare dirt lots" in every take-off and boarding frame.
## A single procedural ground layer now plans it like a real heliport: a
## sealed asphalt apron in front of the hangar with taxi guidance lines, a
## tarmac ring and taxiway around the primary pad, concrete kerbs, and mown
## airside turf (stripes, wear, dry patches) everywhere else, plus low clipped
## hedges along the perimeter (one MultiMesh). Visual only: no collision, so
## the walking, driving and landing routes are unaffected.

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec2 half_size = vec2(58.0, 58.0);
uniform vec4 apron_rect = vec4(-56.0, -8.0, -4.0, 22.0);   // x0, z0, x1, z1
uniform vec4 taxi_rect = vec4(-6.0, 15.0, 30.0, 31.0);
uniform vec3 pad_c = vec3(30.0, 24.0, 23.0);               // x, z, tarmac radius
varying vec3 wp;
varying vec2 lp;
float h21(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 q) { return vn(q) * 0.5 + vn(q * 2.03) * 0.25 + vn(q * 4.1) * 0.125 + vn(q * 8.3) * 0.0625; }
float rect_d(vec2 p, vec4 r) {
	vec2 c = (r.xy + r.zw) * 0.5; vec2 h = (r.zw - r.xy) * 0.5;
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
void vertex() { lp = VERTEX.xz; wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = lp;
	// signed distance to the sealed surfaces (negative = on tarmac)
	float d = min(min(rect_d(p, apron_rect), rect_d(p, taxi_rect)), length(p - pad_c.xy) - pad_c.z);
	float large = fbm(p * 0.045);
	float mid = fbm(p * 0.21 + 3.0);
	float fine = vn(p * 7.0) * 0.6 + h21(floor(p * 28.0)) * 0.4;
	// --- airside turf: mown stripes, clumps, wear and dry patches
	float stripe = step(0.5, fract(p.x / 7.0));
	vec3 grass = mix(vec3(0.15, 0.25, 0.075), vec3(0.20, 0.31, 0.095), stripe);
	grass *= 0.80 + 0.32 * large + 0.10 * (fine - 0.5);
	float dry = smoothstep(0.58, 0.78, fbm(p * 0.07 + 11.0));
	grass = mix(grass, vec3(0.34, 0.33, 0.17), dry * 0.55);
	float clover = smoothstep(0.72, 0.86, vn(p * 1.7 + 5.0)) * 0.5;
	grass = mix(grass, vec3(0.11, 0.21, 0.07), clover);
	// worn, compacted strip where turf meets the tarmac edge
	grass = mix(grass, vec3(0.30, 0.28, 0.20), (1.0 - smoothstep(0.4, 1.6, d)) * 0.45 * mid);
	// --- tarmac: aggregate grain, sealed crack lines, patch repairs, stains
	vec3 tar = vec3(0.115, 0.118, 0.122) * (0.86 + 0.24 * large) * (0.9 + 0.18 * fine);
	float patch_m = step(0.62, fbm(floor(p / 6.0) * 0.9 + 2.0));
	tar = mix(tar, tar * 0.72, patch_m * 0.6);
	float crack = 1.0 - smoothstep(0.0, 0.06, abs(fbm(p * 0.35 + 9.0) - 0.5));
	tar = mix(tar, vec3(0.05), crack * 0.55);
	float stain = smoothstep(0.66, 0.82, fbm(p * 0.25 + 17.0));
	tar = mix(tar, vec3(0.06, 0.06, 0.058), stain * 0.5);
	// yellow taxi guidance: hangar lead-in, taxiway centreline, pad ring
	float paint = 0.0;
	float wear = 0.55 + 0.45 * smoothstep(0.25, 0.6, fbm(p * 1.9));
	paint += (1.0 - smoothstep(0.10, 0.16, abs(p.x + 30.0))) * step(-8.0, p.y) * step(p.y, 23.0);
	paint += (1.0 - smoothstep(0.10, 0.16, abs(p.y - 23.0))) * step(-30.0, p.x) * step(p.x, 30.0 - 17.5);
	paint += (1.0 - smoothstep(0.10, 0.16, abs(length(p - pad_c.xy) - 19.5)));
	// hold-short bars where the taxiway meets the pad ring
	paint += (1.0 - step(0.9, abs(p.x - 9.0))) * (1.0 - step(2.6, abs(p.y - 23.0))) * step(0.5, fract(p.y * 1.4));
	paint = clamp(paint, 0.0, 1.0) * wear;
	tar = mix(tar, vec3(0.78, 0.58, 0.12), paint);
	// --- concrete kerb band between turf and tarmac
	float kerb = 1.0 - smoothstep(0.0, 0.08, abs(d - 0.35) - 0.25);
	vec3 conc = vec3(0.44, 0.43, 0.40) * (0.85 + 0.25 * mid);
	float on_tar = 1.0 - smoothstep(-0.05, 0.05, d);
	vec3 col = mix(grass, tar, on_tar);
	col = mix(col, conc, kerb);
	// fade out at the block edge into the existing apron so there is no seam
	float edge = smoothstep(0.0, 3.0, min(half_size.x - abs(p.x), half_size.y - abs(p.y)));
	ALBEDO = col;
	ROUGHNESS = mix(0.97, 0.88, on_tar) - stain * on_tar * 0.25;
	SPECULAR = mix(0.25, 0.4, on_tar);
	ALPHA = edge;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

static func build(root: Node3D, centre: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "AviationGrounds"
	holder.position = Vector3(centre.x, 0.0, centre.z)
	root.add_child(holder)
	var plane := PlaneMesh.new()
	plane.size = Vector2(116.0, 116.0)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var ground := MeshInstance3D.new()
	ground.name = "AviationGround"
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# just above the block's service apron (top ~0.21), below the service
	# lanes, kerbs and pad decks, which all sit higher
	ground.position = Vector3(0.0, 0.214, 0.0)
	holder.add_child(ground)
	_hedges(holder)

## Low clipped hedges inside the perimeter, batched into one MultiMesh.
static func _hedges(holder: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var xforms: Array[Transform3D] = []
	# south boundary, just inside the fence line (gap left at the lane)
	for i in 22:
		var x := -54.0 + i * 5.0
		if absf(x) < 6.0:
			continue
		xforms.append(_hedge_xf(rng, Vector3(x, 0.0, 51.5), 0.0))
	# west boundary and the strip behind the hangar
	for i in 19:
		var z := -54.0 + i * 5.6
		if absf(z) < 6.0:
			continue
		xforms.append(_hedge_xf(rng, Vector3(-55.5, 0.0, z), PI * 0.5))
	for i in 9:
		xforms.append(_hedge_xf(rng, Vector3(-50.0 + i * 5.2, 0.0, -40.0), 0.0))
	# north boundary east of the lane
	for i in 10:
		xforms.append(_hedge_xf(rng, Vector3(8.0 + i * 5.0, 0.0, -55.0), 0.0))
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		var tint := rng.randf_range(0.85, 1.12)
		mm.set_instance_color(i, Color(0.13 * tint, 0.24 * tint, 0.08 * tint))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Palette.tex("foliage")
	mat.roughness = 0.95
	mat.uv1_scale = Vector3(3.0, 2.0, 1.0)
	var inst := MultiMeshInstance3D.new()
	inst.name = "PerimeterHedges"
	inst.multimesh = mm
	inst.material_override = mat
	holder.add_child(inst)

static func _hedge_xf(rng: RandomNumberGenerator, at: Vector3, yaw: float) -> Transform3D:
	var size := Vector3(rng.randf_range(4.6, 5.6), rng.randf_range(1.1, 1.5), rng.randf_range(1.3, 1.7))
	var b := Basis(Vector3.UP, yaw + rng.randf_range(-0.04, 0.04)).scaled(size)
	return Transform3D(b, at + Vector3(0.0, 0.21 + size.y * 0.42, 0.0))
