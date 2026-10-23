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
			// nearfield R2: size, colour and curl vary leaf to leaf. Small
			// rain-tree leaflets (3-5 cm) and fewer larger angsana leaves (7-11 cm);
			// fresh green, olive, yellow, tan and dark decayed; curled leaves are
			// lit on one edge and shaded on the other, with a soft contact shadow.
			float sz = w_hash12(c + 8.1);
			float len = sz < 0.65 ? 0.09 + 0.06 * sz : 0.20 + 0.12 * (sz - 0.65);
			float wid = len * (0.36 + 0.16 * w_hash12(c + 2.2));
			float e = length(r / vec2(len, wid));
			float leaf = 1.0 - smoothstep(0.80, 1.0, e);
			float shadow = (1.0 - smoothstep(0.9, 1.45, length((r - vec2(0.02, 0.025)) / vec2(len, wid)))) * (1.0 - leaf);
			float t = w_hash12(c + 9.7);
			vec3 col;
			if (t < 0.22) col = vec3(0.24, 0.32, 0.12);        // fresh green
			else if (t < 0.42) col = vec3(0.36, 0.36, 0.15);   // olive
			else if (t < 0.58) col = vec3(0.58, 0.46, 0.16);   // yellow
			else if (t < 0.84) col = vec3(0.42, 0.28, 0.14);   // tan-brown
			else col = vec3(0.20, 0.14, 0.09);                 // dark, decayed
			col *= 0.88 + 0.24 * w_hash12(c + 4.4);
			float curl = w_hash12(c + 6.6);
			float side = clamp(r.y / wid, -1.0, 1.0);
			col *= 1.0 + (curl - 0.3) * 0.55 * side;                     // curled: one edge lit
			col *= 0.82 + 0.22 * (1.0 - abs(side));                    // midrib ridge
			col *= 1.0 - 0.35 * step(0.55, abs(side) * curl) * smoothstep(0.6, 1.0, abs(side));
			acc.rgb = mix(acc.rgb, acc.rgb * 0.55, shadow * acc.a);
			acc = mix(acc, vec4(vec3(0.0), 0.45), shadow * (1.0 - acc.a));
			acc = mix(acc, vec4(col, 1.0), leaf);
		}
	}
	acc.a *= 1.0 - smoothstep(0.015, 0.05, px);
	return acc;
}
