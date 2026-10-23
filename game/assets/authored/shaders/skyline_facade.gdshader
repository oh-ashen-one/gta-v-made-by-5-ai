// Skyline facade (wave A round 2, Opus 5.5). World-space facades for the
// landmark towers and the procedural background city. Round 1 used one pale
// punched-window material for almost everything, so the CBD read as a beige
// cardboard wall with a dot grid. Round 2 gives every tower one of seven
// distinct cladding systems, a lobby base and a plant-screen crown, keeps
// daytime interiors unlit and holds glass roughness high enough that no face
// clips to a flat white bar (light claddings stay at or below ~0.5 linear
// albedo so sun-facing faces keep their pattern).
//
// Materials (MultiMesh custom data .r = (id + 0.5) / 8):
//   0 dark blue-green reflective curtain wall, slim mullions, mottled reflections
//   1 light limestone, deep-set paired windows, string courses
//   2 silver-blue glass, white aluminium mullions and spandrels
//   3 bronze glass in a dark anodised frame
//   4 white aluminium panel with continuous dark ribbon windows
//   5 painted concrete residential slab (cream / grey), balconies, colour band
//   6 grey-green glass behind deep vertical white fins
// Patterns fade to their mean with distance (fwidth) so far towers do not moire.
//
// Per-instance control (MultiMesh custom data, or the uniforms for single meshes):
//   INSTANCE_CUSTOM.r  material id (see above)
//   INSTANCE_CUSTOM.g  tint variation 0..1
//   INSTANCE_CUSTOM.b  floor height scale (0.5..1.0 -> 2.8..4.2 m)
//   INSTANCE_CUSTOM.a  random seed
// Single meshes (Marina Bay Sands, near-shore towers) use the legacy uniforms:
// style 0 = glass (palette picks 0/2/6/3), style 1 = punched stone.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform bool use_instance_custom = false;
uniform float style = 0.0;
uniform float palette = 0.3;
uniform float floor_scale = 0.8;
uniform float seed = 0.0;
// Legacy colour overrides kept for the Marina Bay Sands material.
uniform vec3 glass_b : source_color = vec3(0.33, 0.41, 0.48);
uniform vec3 frame_col : source_color = vec3(0.72, 0.73, 0.72);
// Aerial perspective (skyline_haze.gdshaderinc). Round 4: the haze is a cool
// blue-grey below the horizon sky (warm toward the sun) instead of a white
// veil, so far towers stay darker silhouettes. SkylineAtmosphere.sync
// overwrites sun_dir / fog / horizon from the live world at build time.
uniform vec3 haze_col : source_color = vec3(0.55, 0.61, 0.69);
uniform vec3 haze_sun_col : source_color = vec3(0.96, 0.82, 0.62);
uniform vec3 horizon_col : source_color = vec3(0.84, 0.80, 0.76);
uniform vec3 sun_dir = vec3(0.85, 0.28, 0.45);
uniform float haze_start = 200.0;
uniform float haze_density = 0.0018;
uniform float haze_max = 0.7;
uniform float horizon_start = 1700.0;
uniform float horizon_end = 3600.0;
uniform float far_full = 0.55;
// Environment-fog stand-in (match WorldBuilder/lighting fog colour + density).
uniform vec3 fog_col : source_color = vec3(0.80, 0.78, 0.74);
uniform float fog_density_ref = 0.00024;
uniform float fog_scale = 1.0;
uniform vec3 roof_col : source_color = vec3(0.32, 0.31, 0.30);
// Round 4: low-rise hinterland roofs vary per instance (terracotta, grey,
// pale membrane, dark metal) instead of one grey deck.
uniform float roof_variety = 0.0;
// Round 4: per-face sun shading boost. The aerial views see the far towers
// front-lit, and haze flattened lit and shaded faces to one tone; this
// deepens faces turned away from the sun (and lifts sun-facing ones a
// little) so every tower reads as a solid with a light and a dark side.
uniform float form_contrast = 0.0;
uniform float band_frac = 0.20;
// Coarse refuge-floor bands (round 4). 0 keeps only the fine per-floor grid
// (Marina Bay Sands: its curtain wall has no plant floors; wave M integration).
uniform float refuge_bands = 1.0;
uniform float mullion_m = 2.6;
// Daytime build: interiors stay dark. >0 only for dusk variants, and then the
// lit panes are masked to the glazing so they never straddle the grid.
uniform float lit_chance = 0.0;
// Single-mesh towers can opt into the lobby base / crown: world y of the
// ground and the tower height (0 = off).
uniform float legacy_base = 0.0;
uniform float legacy_height = 0.0;

varying vec3 wpos;
varying vec3 wnorm;
#include "res://assets/authored/shaders/skyline_haze.gdshaderinc"
varying vec4 icustom;
varying float inst_base;
varying float inst_h;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), u.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), u.x), u.y);
}
// Box-filtered pulse train: fraction of [0,1) period covered by [0,w), filtered over fw.
float pulse(float x, float w, float fw) {
	float f = fract(x);
	float p = step(f, w);
	return mix(p, w, clamp(fw * 1.6 - 0.2, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (use_instance_custom) {
		icustom = INSTANCE_CUSTOM;
		inst_base = MODEL_MATRIX[3].y;
		inst_h = length(MODEL_MATRIX[1].xyz);
	} else {
		float legacy = style > 0.5 ? 1.0 : (palette < 0.3 ? 0.0 : (palette < 0.55 ? 2.0 : (palette < 0.8 ? 6.0 : 3.0)));
		icustom = vec4((legacy + 0.5) / 8.0, fract(seed * 3.7), floor_scale, seed);
		inst_base = legacy_base;
		inst_h = legacy_height;
	}
}

void fragment() {
	int mat_id = clamp(int(icustom.r * 8.0), 0, 6);
	float tv = icustom.g;
	float fh = mix(2.8, 4.2, clamp(icustom.b, 0.0, 1.0));
	float sd = icustom.a * 97.0;
	vec3 n = normalize(wnorm);
	float metal = 0.0;
	float rough = 0.85;
	float spec = 0.4;
	float glazing = 0.0;  // 1 where the pixel is a window pane (for lit masking)
	if (n.y > 0.6) {
		// Roof deck: weathered membrane with stains, panel seams and a lighter rim.
		vec2 q = wpos.xz;
		float stain = vnoise(q * 0.08 + sd) * 0.6 + vnoise(q * 0.31 - sd) * 0.4;
		float seam = max(pulse(q.x / 3.0, 0.05, fwidth(q.x / 3.0)), pulse(q.y / 3.0, 0.05, fwidth(q.y / 3.0)));
		vec3 rc = roof_col;
		if (roof_variety > 0.5) {
			float k = fract(icustom.a * 13.7);
			rc = k < 0.34 ? lin(vec3(0.58, 0.33, 0.24)) : (k < 0.6 ? lin(vec3(0.52, 0.52, 0.50)) : (k < 0.82 ? lin(vec3(0.70, 0.69, 0.66)) : lin(vec3(0.26, 0.29, 0.30))));
		}
		vec3 c = rc * (0.78 + 0.42 * stain);
		c = mix(c, c * 0.72, seam * 0.6);
		c = mix(c, lin(vec3(0.30, 0.34, 0.30)), smoothstep(0.72, 0.9, vnoise(q * 0.05 + 3.0 + sd)) * 0.5);
		ALBEDO = c;
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
		SPECULAR = 0.3;
	} else {
		// Horizontal coordinate along the face. Picking x or z by the larger
		// normal component flipped on 45-degree faces (octagon towers), which
		// blew fwidth up and filtered the whole face to one flat bright tone.
		vec2 tang = normalize(vec2(-n.z, n.x) + vec2(1e-5, 0.0));
		float hz = dot(wpos.xz, tang);
		float fy = wpos.y / fh;
		float fwy = fwidth(fy);
		float bay = hz / mullion_m;
		float fwx = fwidth(bay);
		vec2 cell = vec2(floor(bay), floor(fy));
		float r = hash2(cell + sd);
		float rf = hash2(vec2(floor(fy), sd));
		// Large soft patches: reflections of neighbouring towers and sky.
		float refl = vnoise(vec2(hz * 0.035, wpos.y * 0.012) + sd);
		float filt = clamp(fwy * 2.0, 0.0, 1.0);
		vec3 c;
		if (mat_id == 0) {
			// Dark blue-green reflective curtain wall.
			vec3 g = lin(mix(vec3(0.04, 0.11, 0.13), vec3(0.05, 0.12, 0.17), tv));
			g *= 0.8 + 0.35 * refl + 0.12 * r * (1.0 - filt);
			// Sky reflection brightens the glass toward the top of the tower.
			if (inst_h > 0.0) {
				g *= mix(0.85, 1.45, smoothstep(0.0, 1.0, (wpos.y - inst_base) / inst_h));
			}
			float band = pulse(fy, 0.1, fwy);
			float mull = pulse(bay * 1.25, 0.06, fwx * 1.25);
			c = mix(g, lin(vec3(0.27, 0.31, 0.32)), max(band, mull) * 0.85);
			glazing = 1.0 - max(band, mull);
			metal = 0.0; rough = mix(0.6, 0.34, glazing); spec = mix(0.4, 0.3, glazing);
		} else if (mat_id == 1) {
			// Light limestone with paired, deep-set windows and string courses.
			vec3 wall = lin(mix(vec3(0.72, 0.69, 0.63), vec3(0.67, 0.65, 0.61), tv));
			wall *= 0.9 + 0.14 * vnoise(vec2(hz, wpos.y) * 0.06 + sd);
			float wx = pulse(bay * 0.5 + 0.12, 0.76, fwx * 0.5) * (1.0 - pulse(bay * 0.5 + 0.12 + 0.36, 0.04, fwx * 0.5));
			float wy = pulse(fy + 0.3, 0.6, fwy);
			float reveal = pulse(fy + 0.3 - 0.6, 0.06, fwy) * wx;  // shadowed head of the opening
			vec3 win = lin(vec3(0.06, 0.08, 0.10)) * (0.8 + 0.5 * r * (1.0 - filt));
			c = mix(wall, win, wx * wy);
			c = mix(c, wall * 0.55, reveal);
			float course = pulse(fy / 4.0, 0.06, fwy / 4.0);
			c = mix(c, wall * 1.08, course);
			glazing = wx * wy;
			rough = mix(0.88, 0.3, glazing); spec = 0.45;
		} else if (mat_id == 2) {
			// Silver-blue glass, white aluminium grid.
			vec3 g = glass_b * (0.85 + 0.3 * refl + 0.1 * r * (1.0 - filt)) * mix(0.9, 1.1, tv);
			float band = pulse(fy, band_frac, fwy);
			float mull = pulse(bay, 0.09, fwx);
			c = mix(g, frame_col, max(band, mull * 0.85));
			glazing = 1.0 - max(band, mull);
			metal = 0.0; rough = mix(0.55, 0.34, glazing); spec = 0.42;
		} else if (mat_id == 3) {
			// Bronze glass in a dark anodised frame.
			vec3 g = lin(mix(vec3(0.27, 0.23, 0.17), vec3(0.32, 0.27, 0.19), tv)) * (0.8 + 0.4 * refl);
			float band = pulse(fy, 0.16, fwy);
			float mull = pulse(bay, 0.1, fwx);
			c = mix(g, lin(vec3(0.20, 0.18, 0.15)), max(band, mull));
			glazing = 1.0 - max(band, mull);
			metal = 0.0; rough = mix(0.5, 0.34, glazing); spec = 0.35;
		} else if (mat_id == 4) {
			// White aluminium panel with continuous dark ribbon windows.
			vec3 wall = lin(mix(vec3(0.76, 0.76, 0.74), vec3(0.71, 0.73, 0.74), tv));
			float ribbon = pulse(fy + 0.15, 0.48, fwy);
			float mull = pulse(bay * 0.8, 0.05, fwx * 0.8);
			vec3 win = lin(vec3(0.07, 0.11, 0.15)) * (0.75 + 0.5 * refl);
			c = mix(wall, win, ribbon * (1.0 - mull * 0.8));
			glazing = ribbon * (1.0 - mull);
			metal = 0.1 * glazing; rough = mix(0.6, 0.25, glazing); spec = 0.5;
		} else if (mat_id == 5) {
			// Painted concrete residential slab: balconies, dark windows, colour band.
			vec3 wall = lin(tv < 0.33 ? vec3(0.76, 0.72, 0.63) : (tv < 0.66 ? vec3(0.69, 0.70, 0.68) : vec3(0.72, 0.67, 0.60)));
			wall *= 0.9 + 0.12 * vnoise(vec2(hz, wpos.y) * 0.05 + sd);
			float wx = pulse(bay * 0.5, 0.62, fwx * 0.5);
			float wy = pulse(fy + 0.2, 0.5, fwy);
			float slab = pulse(fy, 0.12, fwy);
			vec3 win = lin(vec3(0.10, 0.11, 0.12)) * (0.8 + 0.5 * r * (1.0 - filt));
			c = mix(wall, win, wx * wy);
			c = mix(c, wall * 1.06, slab);
			float stripe = pulse(bay / 9.0, 0.08, fwx / 9.0);
			// Round 4: muted accents (full-strength red stripes read as toy-like).
			vec3 accent = lin(tv < 0.5 ? vec3(0.60, 0.40, 0.33) : vec3(0.38, 0.47, 0.53));
			c = mix(c, accent, stripe * 0.5);
			glazing = wx * wy;
			rough = 0.85; spec = 0.35;
		} else {
			// Grey-green glass behind deep white vertical fins.
			vec3 g = lin(mix(vec3(0.16, 0.22, 0.21), vec3(0.20, 0.26, 0.27), tv)) * (0.8 + 0.4 * refl);
			float fin = pulse(bay * 0.75, 0.24, fwx * 0.75);
			float band = pulse(fy, 0.08, fwy);
			vec3 fin_col = lin(vec3(0.74, 0.74, 0.72));
			c = mix(g, fin_col * 0.62, band);
			c = mix(c, fin_col, fin);
			glazing = (1.0 - fin) * (1.0 - band);
			metal = 0.0; rough = mix(0.7, 0.34, glazing); spec = 0.42;
		}
		// Round 4: coarse banding that survives at 1-3 km, where the per-floor
		// grid filters to its mean. Every 6-11 floors a refuge / plant floor
		// (spandrel band with louvres) crosses the face, and glass faces carry
		// broad vertical reflection streaks of neighbouring towers and sky.
		float nb = floor(mix(6.0, 11.0, fract(icustom.a * 5.3)));
		float mband = pulse(fy / nb + fract(icustom.a * 3.1), 1.0 / nb, fwy / nb);
		vec3 band_col = (mat_id == 0 || mat_id == 3) ? lin(vec3(0.30, 0.32, 0.32)) : (mat_id == 2 || mat_id == 6 ? lin(vec3(0.82, 0.82, 0.80)) : c * 0.6);
		c = mix(c, band_col, mband * 0.85 * refuge_bands);
		if (mat_id == 0 || mat_id == 2 || mat_id == 3 || mat_id == 6) {
			float streak = vnoise(vec2(hz * 0.06 + sd, 0.5));
			c *= 0.78 + 0.5 * streak;
		}
		// Lobby base and plant-screen crown (procedural towers only).
		if (inst_h > 0.0) {
			float ly = wpos.y - inst_base;
			float base_h = min(9.0, inst_h * 0.12);
			if (ly < base_h) {
				float col = pulse(hz / 7.5, 0.18, fwidth(hz / 7.5));
				vec3 lobby = lin(vec3(0.05, 0.06, 0.07)) * (0.8 + 0.4 * refl);
				c = mix(lobby, lin(vec3(0.62, 0.60, 0.56)), max(col, step(base_h - 1.0, ly)));
				glazing = 0.0;
				rough = 0.5;
			}
			float crown0 = inst_h - min(7.0, inst_h * 0.06);
			if (ly > crown0 && mat_id != 5) {
				float louvre = pulse(hz / 0.9, 0.5, fwidth(hz / 0.9));
				vec3 screen = lin(mat_id == 3 ? vec3(0.22, 0.19, 0.15) : vec3(0.70, 0.71, 0.70));
				c = mix(screen, screen * 0.62, louvre * 0.6);
				c = mix(c, screen * 1.1, step(inst_h - 0.8, ly));
				glazing = 0.0;
				rough = 0.7; metal = 0.0;
			}
		}
		// Optional lit interiors (dusk variants only), masked to whole panes.
		float lit = step(1.0 - lit_chance, r) * glazing * (1.0 - filt);
		c = mix(c, lin(vec3(0.95, 0.78, 0.52)), lit * 0.7);
		EMISSION = vec3(1.0, 0.78, 0.5) * lit * 0.25;
		// Grime gathers at the base; whole towers vary slightly in value.
		c *= 0.9 + 0.1 * smoothstep(0.0, 12.0, wpos.y);
		c *= mix(0.88, 1.06, fract(icustom.a * 7.31));
		if (form_contrast > 0.0) {
			vec3 sdn = normalize(vec3(sun_dir.x, 0.0, sun_dir.z));
			float facing = dot(normalize(vec3(n.x, 0.0, n.z)), sdn);
			c *= mix(1.0 - 0.45 * form_contrast, 1.0 + 0.12 * form_contrast, smoothstep(-0.35, 0.6, facing));
		}
		ALBEDO = c;
		// Each glazed panel is tilted a little ("oil-canning"), so a flat face
		// turned to the sun breaks into a mosaic of brighter and darker panes
		// instead of one uniform specular slab with no gradient.
		vec3 tw = vec3(tang.x, 0.0, tang.y);
		float tilt = mix(0.035, 0.14, glazing);
		vec3 nw = normalize(n + tw * (hash2(cell + sd + 7.1) - 0.5) * tilt + vec3(0.0, 1.0, 0.0) * (hash2(cell + sd + 3.3) - 0.5) * tilt);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		// Grazing faces (slim fins, tower flanks seen edge-on) would mirror the
		// bright sky into a flat clipped-white bar; damp the Fresnel spike.
		float ndv = clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0);
		float graze = smoothstep(0.02, 0.4, ndv);
		METALLIC = metal * graze;
		ROUGHNESS = mix(0.75, rough, graze);
		SPECULAR = spec * mix(0.25, 1.0, graze);
		// Single-mesh glass towers stand near the airfield and face the low
		// sun: a mirror-sharp sun highlight clipped into a white blob that
		// bloomed past the outline (critic A2, photo_09). Keep them satin.
		if (!use_instance_custom) {
			ROUGHNESS = max(ROUGHNESS, 0.52);
			SPECULAR *= 0.55;
			METALLIC = 0.0;
		}
	}
	// Aerial perspective, written to FOG so it replaces (not stacks on) the
	// environment fog: ~36% at 600 m, ~53% at 1 km toward a cool blue-grey
	// (warm toward the sun) that stays below the horizon sky, so each farther
	// layer is flatter and sky-tinted but still a darker silhouette.
	FOG = skyline_haze_clip(wpos, CAMERA_POSITION_WORLD, far_full, -VERTEX.z, INV_PROJECTION_MATRIX);
}
