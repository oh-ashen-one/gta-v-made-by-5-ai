shader_type spatial;
// Vehicle body (opus55 driving-p). Replaces the provider car material.
// - Clean clear-coat paint: the lumpy generated mesh normals are blended toward
//   a rounded-box proxy normal so sky and street reflections sweep cleanly
//   across the panels instead of breaking into grain.
// - Glass: dark cabin texels become a near-mirror dielectric.
// - Lamps: red rear texels glow (tail) and flare when braking.
// - Damage: up to four dents displace the body in model space with a crumpled
//   falloff; crumpled facets, bare-metal scrapes, cracked glass and dead lamps
//   follow the dents. Everything is per instance (instance uniforms), so one
//   material serves every car of a kind.
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float paint_kind = 0.0;          // 0: light/neutral paint (sedan, van, police), 1: saturated paint (coupe)
uniform float proxy_normal_mix = 0.62;   // how much the panels follow the smooth proxy shape
uniform float lamp_glow = 1.0;           // 0 disables shader lamps (kinds whose texture has no lamp texels)
uniform float badge_mask = 0.0;          // 1 paints over the generated model's boot badge (no marque on our cars)

// Model -> normalised car space rows: x in [-1,1] (right), y in [0,1] (up),
// z in [-1,1] (front -1 .. rear +1). Set per instance from the car's bounds.
instance uniform vec4 car_row_x = vec4(0.0);
instance uniform vec4 car_row_y = vec4(0.0);
instance uniform vec4 car_row_z = vec4(0.0);
// x: brake (0..1), y: lamps on (0..1), z: overall wear (0..1), w: paint override strength
instance uniform vec4 car_state = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform vec4 paint_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// Dents: centre (model space) + radius, push direction (model space) + depth.
instance uniform vec4 dent0 = vec4(0.0);
instance uniform vec4 dent1 = vec4(0.0);
instance uniform vec4 dent2 = vec4(0.0);
instance uniform vec4 dent3 = vec4(0.0);
instance uniform vec4 dent_dir0 = vec4(0.0);
instance uniform vec4 dent_dir1 = vec4(0.0);
instance uniform vec4 dent_dir2 = vec4(0.0);
instance uniform vec4 dent_dir3 = vec4(0.0);

varying vec3 v_car;        // normalised car-space position (undeformed)
varying vec3 v_proxy_n;    // view-space proxy normal
varying float v_dent;      // 0..1 dent weight
varying vec3 v_model;      // model-space undeformed position

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
				   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
				   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float dent_weight(vec3 p, vec4 d) {
	if (d.w <= 0.0) return 0.0;
	float r = distance(p, d.xyz) / d.w;
	float f = clamp(1.0 - r * r, 0.0, 1.0);
	return f * f;
}

void vertex() {
	vec3 p = VERTEX;
	v_model = p;
	v_car = vec3(dot(car_row_x.xyz, p) + car_row_x.w, dot(car_row_y.xyz, p) + car_row_y.w, dot(car_row_z.xyz, p) + car_row_z.w);
	// Rounded-box (superellipse, k = 4) proxy normal in car space.
	vec3 q = vec3(v_car.x, (v_car.y - 0.42) / 0.58, v_car.z);
	vec3 g = sign(q) * pow(abs(q), vec3(3.0));
	g = g / vec3(1.0, 0.58, 1.0);
	// Car space axes back to model space via the row vectors (their gradient).
	vec3 n_model = normalize(car_row_x.xyz * g.x + car_row_y.xyz * g.y + car_row_z.xyz * g.z + vec3(1e-5));
	v_proxy_n = normalize((MODELVIEW_MATRIX * vec4(n_model, 0.0)).xyz);
	// Dents: crumpled push along the impact direction.
	float crumple = 0.55 + 0.9 * vnoise(p * 7.0);
	vec3 disp = vec3(0.0);
	float w = 0.0;
	float w0 = dent_weight(p, dent0); disp += dent_dir0.xyz * dent_dir0.w * w0 * crumple; w = max(w, w0 * step(0.001, dent_dir0.w));
	float w1 = dent_weight(p, dent1); disp += dent_dir1.xyz * dent_dir1.w * w1 * crumple; w = max(w, w1 * step(0.001, dent_dir1.w));
	float w2 = dent_weight(p, dent2); disp += dent_dir2.xyz * dent_dir2.w * w2 * crumple; w = max(w, w2 * step(0.001, dent_dir2.w));
	float w3 = dent_weight(p, dent3); disp += dent_dir3.xyz * dent_dir3.w * w3 * crumple; w = max(w, w3 * step(0.001, dent_dir3.w));
	// Buckling: panels wrinkle across the push, not just recess along it.
	vec3 wob = (vec3(vnoise(p * 5.0 + 3.0), vnoise(p * 5.0 + 11.0), vnoise(p * 5.0 + 23.0)) - 0.5) * 2.0;
	float dlen = dent_dir0.w * w0 + dent_dir1.w * w1 + dent_dir2.w * w2 + dent_dir3.w * w3;
	disp += wob * dlen * 0.85;
	VERTEX = p + disp;
	v_dent = w;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_tint;
	vec3 col = a.rgb;
	vec3 orm = texture(orm_tex, UV).rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float mx = max(col.r, max(col.g, col.b));
	float mn = min(col.r, min(col.g, col.b));
	float sat = (mx - mn) / (mx + 0.001);
	float upper = smoothstep(0.50, 0.60, v_car.y);
	// Cabin glass: dark, unsaturated texels above the belt line.
	float glass = (1.0 - smoothstep(0.09, 0.20, lum)) * (1.0 - smoothstep(0.35, 0.6, sat)) * upper;
	// Paint: the main body colour family of this kind.
	float paint = 0.0;
	if (paint_kind < 0.5) {
		paint = smoothstep(0.30, 0.48, lum) * (1.0 - smoothstep(0.16, 0.30, sat));
	} else {
		paint = smoothstep(0.45, 0.65, sat) * smoothstep(0.10, 0.22, mx) * step(col.g, col.r);
	}
	paint *= 1.0 - glass;
	// Tail lamps: strongly red texels on the rear quarter.
	float red = smoothstep(0.22, 0.42, col.r - max(col.g, col.b)) * smoothstep(0.66, 0.86, v_car.z) * (1.0 - upper * 0.7);
	red *= lamp_glow * (1.0 - step(0.5, paint_kind));
	// The generated sedan carries a marque-like badge on the boot lid: paint it out.
	float badge = badge_mask * (1.0 - smoothstep(0.07, 0.10, abs(v_car.x))) * smoothstep(0.86, 0.91, v_car.z) * smoothstep(0.36, 0.40, v_car.y) * (1.0 - smoothstep(0.62, 0.66, v_car.y));
	vec3 badge_col = car_state.w > 0.0 ? paint_color.rgb : vec3(0.70, 0.71, 0.72) * albedo_tint.rgb;
	// ...and the ring on the grille: fill it with dark grille mesh colour.
	float grille_badge = badge_mask * (1.0 - smoothstep(0.06, 0.09, abs(v_car.x))) * (1.0 - smoothstep(-0.93, -0.88, v_car.z)) * smoothstep(0.38, 0.42, v_car.y) * (1.0 - smoothstep(0.60, 0.64, v_car.y));
	col = mix(col, vec3(0.045, 0.047, 0.05), grille_badge);
	// Optional per-car paint colour (luminance-preserving).
	if (car_state.w > 0.0) {
		float ref_l = paint_kind < 0.5 ? 0.62 : 0.22;
		vec3 recol = paint_color.rgb * clamp(lum / ref_l, 0.55, 1.25);
		col = mix(col, recol, paint * car_state.w);
	}
	if (badge > 0.0) {
		col = mix(col, badge_col, badge);
		paint = max(paint, badge);
		red *= 1.0 - badge;
	}
	// Smooth reflections on paint and glass.
	float smooth_mix = proxy_normal_mix * max(paint, glass);
	vec3 n = normalize(mix(NORMAL, v_proxy_n, smooth_mix));
	// Damage: crumpled facets, scraped paint, cracked glass, dead lamps.
	float dmg = v_dent;
	if (dmg > 0.01) {
		vec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(fn, n) < 0.0) fn = -fn;
		n = normalize(mix(n, fn, clamp(dmg * 1.2, 0.0, 0.6)));
		float streak = vnoise(v_model * vec3(3.0, 38.0, 3.0)) * vnoise(v_model * vec3(31.0, 4.0, 31.0) + 7.0);
		float scrape = smoothstep(0.18, 0.42, dmg) * smoothstep(0.18, 0.34, streak);
		// driving-q: duller, darker scuffed steel; the 0.55 grey under a 0.2
		// clear-coat lit up a crumpled boot as a white blob in the chase view.
		vec3 bare = vec3(0.30, 0.31, 0.32) * (0.8 + 0.4 * vnoise(v_model * 60.0));
		vec3 grime = col * 0.45;
		col = mix(col, grime, smoothstep(0.08, 0.5, dmg) * 0.55 * paint);
		col = mix(col, bare, scrape * (paint + 0.4) * 0.7);
		// Spider cracks: thin bright lines in the glass near the dent.
		float cell = abs(sin(v_model.x * 41.0 + vnoise(v_model * 9.0) * 6.0) * sin(v_model.y * 37.0 + v_model.z * 29.0));
		float crack = (1.0 - smoothstep(0.0, 0.07, cell)) * glass * smoothstep(0.05, 0.3, dmg);
		col = mix(col, vec3(0.78, 0.82, 0.84), crack);
		glass *= 1.0 - crack;
		red *= 1.0 - smoothstep(0.25, 0.55, dmg);
	}
	NORMAL = n;
	ALBEDO = col;
	float rough = mix(orm.g, 0.2, paint);
	rough = mix(rough, 0.05, glass);
	float metal = mix(orm.b, 0.12, max(paint, glass));
	rough = mix(rough, 0.62, smoothstep(0.08, 0.45, dmg) * paint);
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	SPECULAR = mix(mix(0.5, 0.62, paint), 0.7, glass);
	CLEARCOAT = max(paint, glass) * (1.0 - smoothstep(0.08, 0.4, dmg));
	CLEARCOAT_ROUGHNESS = 0.06;
	// Glass reads darker and deeper so reflections dominate.
	ALBEDO = mix(ALBEDO, ALBEDO * 0.35, glass);
	// Lamp emission: tail lamps on when driven, flare under braking.
	float lamp = red * (car_state.y * 0.9 + car_state.x * 5.5);
	EMISSION = vec3(1.0, 0.07, 0.03) * lamp;
}
