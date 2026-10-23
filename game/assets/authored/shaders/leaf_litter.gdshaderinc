// Fallen rain-tree / angsana leaf litter (nearfield, opus55 wave R). World-
// space scatter of small elliptical leaves, brown to olive-yellow with a few
// dark decayed ones; two offset jitter grids so it never reads as a lattice.
// Faded out by pixel footprint (leaves are ~6-10 cm) so distance stays calm.
// Requires weathering.gdshaderinc (w_hash12, w_rot).
vec4 leaf_litter(vec2 p, float density, float px) {
	vec4 acc = vec4(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = p / 0.32 + float(k) * vec2(0.37, 0.71);
		vec2 c = floor(q) + float(k) * 57.0;
		float h = w_hash12(c + 11.3);
		if (h < density) {
			vec2 f = fract(q) - 0.5 - (vec2(w_hash12(c + 1.7), w_hash12(c + 5.9)) - 0.5) * 0.5;
			vec2 r = w_rot(f, w_hash12(c + 3.3) * 6.2832);
			float len = 0.20 + 0.10 * w_hash12(c + 8.1);
			float e = length(r / vec2(len, len * 0.42));
			float leaf = 1.0 - smoothstep(0.80, 1.0, e);
			float t = w_hash12(c + 9.7);
			vec3 col = mix(vec3(0.40, 0.28, 0.13), vec3(0.52, 0.46, 0.17), t);
			col = mix(col, vec3(0.22, 0.17, 0.10), step(0.82, t));
			col *= 0.85 + 0.3 * (0.5 - abs(r.y / (len * 0.42)) * 0.5);   // midrib shading
			acc = mix(acc, vec4(col, 1.0), leaf);
		}
	}
	acc.a *= 1.0 - smoothstep(0.015, 0.05, px);
	return acc;
}
