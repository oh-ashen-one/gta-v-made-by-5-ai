shader_type spatial;
// Spray droplets and stern mist for boats under way (water piece round 4).
// Each quad is one droplet on a ballistic path computed here: thrown off a
// bow shoulder or kicked up behind the transom with a velocity relative to
// the water, then left behind as the boat drives on (the -speed * age term in
// the boat frame). No particle system: one MultiMesh per hull type.
// COLOR.r: emitter (0 starboard bow, 0.5 port bow, 1 stern); COLOR.gba seeds.
// INSTANCE_CUSTOM: r spray strength 0..1.3, g seed, b speed m/s.
render_mode skip_vertex_transform, blend_mix, cull_disabled, depth_draw_never, unshaded, fog_disabled;

uniform float half_len = 3.6;
uniform float half_beam = 1.2;
uniform float planing = 1.0;
uniform vec3 tint : source_color = vec3(0.95, 0.97, 0.98);

varying float v_alpha;
varying vec2 v_uv;
varying float v_shade;

void vertex() {
	float s = INSTANCE_CUSTOM.r;
	float seed = INSTANCE_CUSTOM.g * 13.0;
	float spd = INSTANCE_CUSTOM.b;
	float region = COLOR.r;
	float r1 = COLOR.g;
	float r2 = COLOR.b;
	float r3 = COLOR.a;
	bool stern = region > 0.75;
	float life = stern ? 1.4 : 0.85;
	float ph = fract(TIME / life + r1 * 7.31 + seed);
	float age = ph * life;
	vec3 p0;
	vec3 v0;
	float size;
	if (!stern) {
		float side = region < 0.25 ? 1.0 : -1.0;
		float along = mix(0.05, 0.75, r2);
		float w = along > 0.16 ? (1.0 - pow((along - 0.16) / 0.84, 2.1)) * 0.96 + 0.04 : 1.0;
		p0 = vec3(half_len * along, 0.12, side * half_beam * (w + 0.05));
		float lift = mix(0.5, 1.0, planing);
		v0 = vec3(-0.3 - 1.4 * r3, (1.6 + 3.4 * r2) * lift, side * (1.0 + 2.6 * r1)) * clamp(s, 0.0, 1.2);
		size = mix(0.07, 0.20, r3 * r3) * mix(0.8, 1.2, s);
	} else {
		p0 = vec3(-half_len - 0.1 - r2 * 0.7, 0.15, (r3 * 2.0 - 1.0) * half_beam * 0.8);
		v0 = vec3(-0.6 - 2.2 * r1, (0.6 + 2.6 * r2) * mix(0.4, 1.0, planing), (r3 * 2.0 - 1.0) * 1.6) * clamp(s, 0.0, 1.2);
		size = mix(0.10, 0.36, r2 * r2) * mix(0.6, 1.2, s) * mix(0.6, 1.0, planing);
	}
	vec3 p = p0 + v0 * age + vec3(-spd * age * 0.92, -4.9 * age * age, 0.0);
	float alive = step(-0.02, p.y) * step(0.05, s);
	// fade in fast, out as it falls apart
	// Integration A (critic water-A4: "uniform opaque round white discs"):
	// translucent, varied, and stretched along the droplet's motion below.
	v_alpha = alive * smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.45, 1.0, ph)) * (stern ? 0.28 : 0.55) * mix(0.45, 1.0, r2);
	v_shade = 0.8 + 0.2 * r1;
	v_uv = UV;
	vec3 centre = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	vec3 vel = v0 + vec3(-spd * 0.92, -9.8 * age, 0.0);
	vec2 vdir = (MODELVIEW_MATRIX * vec4(vel, 0.0)).xy;
	float vlen = length(vdir);
	vec2 ax = vlen > 1e-3 ? vdir / vlen : vec2(0.0, 1.0);
	vec2 ay = vec2(-ax.y, ax.x);
	float stretch = 1.0 + clamp(vlen * 0.09, 0.0, 2.2);
	vec2 q = (UV - 0.5) * size * alive;
	vec2 corner = ax * q.y * stretch + ay * q.x * 0.55;
	VERTEX = centre + vec3(corner, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float d = length(v_uv - 0.5) * 2.0;
	// Soft misty falloff instead of a hard-edged disc.
	float a = exp(-d * d * 3.2) * smoothstep(1.0, 0.7, d) * v_alpha;
	if (a < 0.02) {
		discard;
	}
	ALBEDO = tint * v_shade;
	ALPHA = a;
}
