// Shared aerial perspective for the skyline piece (wave A round 4, Opus 5.5).
// Included by skyline_facade, city_carpet and skyline_hills. The including
// shader declares these uniforms (SkylineAtmosphere.sync sets them at runtime
// from the live sun, sky and environment fog):
//   vec3 haze_col, haze_sun_col, horizon_col, fog_col, sun_dir
//   float haze_start, haze_density, haze_max, fog_density_ref, fog_scale,
//         horizon_start, horizon_end
//
// Round 3 hazed the far city toward a near-white veil (0.80/0.78/0.76): the
// CBD ended only ~0.05 darker than the sky behind it and the silhouettes
// dissolved into pale cardboard (critic A3). Real aerial perspective is
// in-scattered light, which is bluer and darker than the bright horizon sky
// the towers occlude (GTAV-15 / GTAV-20: towers ~0.11 below the sky). So:
//  - away from the sun the haze is a cool blue-grey well below the horizon sky;
//  - toward the sun it warms and brightens (forward scattering glow);
//  - ground (far_full = 1) merges completely into the horizon sky by
//    horizon_end, so no camera far plane or land edge ever shows; towers
//    (far_full < 1) keep a darker silhouette even at 2-3 km;
//  - everything also dissolves into the horizon colour over the last ~25% of
//    the camera's far range and meets the camera-following horizon skirt
//    (skyline_horizon_skirt.gdshader), so a 2 km photo camera never shows a hard
//    cut through the land, a half-clipped tower or the sky's below-horizon band
//    (inv_proj = INV_PROJECTION_MATRIX, view_depth = -VERTEX.z).
float skyline_cam_far(mat4 inv_proj) {
	vec4 a = inv_proj * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 b = inv_proj * vec4(0.0, 0.0, 1.0, 1.0);
	float za = abs(a.w) > 1e-6 ? abs(a.z / a.w) : 1e9;
	float zb = abs(b.w) > 1e-6 ? abs(b.z / b.w) : 1e9;
	return min(max(za, zb), 1e6);
}
vec4 skyline_haze(vec3 world_pos, vec3 cam_pos, float full_amt) {
	vec3 ray = world_pos - cam_pos;
	float d = max(length(ray), 0.001);
	vec3 rd = ray / d;
	float env_amt = (1.0 - exp(-d * fog_density_ref)) * fog_scale;
	float hz = (1.0 - exp(-max(d - haze_start, 0.0) * haze_density)) * haze_max;
	float amt = clamp(max(env_amt, hz), 0.0, 0.9);
	vec3 sd = normalize(sun_dir);
	vec3 flat_rd = normalize(vec3(rd.x, rd.y * 0.35, rd.z));
	float sunf = max(dot(flat_rd, normalize(vec3(sd.x, sd.y * 0.35, sd.z))), 0.0);
	vec3 col = mix(haze_col, haze_sun_col, pow(sunf, 5.0) * 0.9);
	// Within the near district keep the environment fog colour; the cool
	// aerial tint takes over as the extra haze builds up.
	col = mix(fog_col, col, smoothstep(0.0, 0.3, hz));
	float far_t = smoothstep(horizon_start, horizon_end, d);
	col = mix(col, horizon_col, far_t * full_amt);
	amt = mix(amt, 1.0, far_t * full_amt);
	return vec4(col, amt);
}

vec4 skyline_haze_clip(vec3 world_pos, vec3 cam_pos, float full_amt, float view_depth, mat4 inv_proj) {
	vec4 f = skyline_haze(world_pos, cam_pos, full_amt);
	float cf = skyline_cam_far(inv_proj);
	// Horizontal distance, not view depth: the horizon skirt is a ring at
	// 0.955 x far, so whatever stands just in front of it (also at the frame
	// edges, where view depth is shorter) must already be fully faded.
	float dh = length((world_pos - cam_pos).xz);
	float clip_t = max(smoothstep(cf * 0.74, cf * 0.94, dh), smoothstep(cf * 0.8, cf * 0.97, view_depth));
	f.rgb = mix(f.rgb, horizon_col, clip_t);
	f.a = mix(f.a, 1.0, clip_t);
	return f;
}
