// Downtown blocks facade (wave M, downtown-blocks piece, Opus 5.5). Original work.
//
// One shader for every downtown building shell (CBD and MBFC towers, podiums,
// mid-rises, residential condos, civic blocks). The mesh generator in
// src/world/downtown/block_kits/tower_kit.gd writes per-vertex data, so all
// buildings share this one material and still look different:
//   UV    = (metres along the facade, metres above the building's ground)
//           roof faces: (0..1, 0..1) across the roof, randomly rotated per roof
//   UV2   = (total building height, lobby / shopfront band height)
//   COLOR = (cladding id (id + 0.5) / 10, tint 0..1, floor-height 0..1, seed 0..1)
// Cladding systems:
//   0 blue-green reflective curtain wall, slim silver mullions, dark spandrels
//   1 warm granite, deep punched windows
//   2 silver ribbon: white aluminium spandrel bands, continuous glazing
//   3 bronze glass in dark anodised frames with shadowed vertical fins
//   4 white aluminium panel grid with square windows
//   5 grey-green glass behind white vertical fins (bayfront offices)
//   6 residential: painted concrete, balcony slabs, glass balustrades
//   7 dark granite piers alternating with tall glass bays
//   8 colonial: white plaster, tall shuttered windows, cornices
//   9 shophouse plaster (pastel tint from COLOR.g), louvred windows
// Glazing uses interior mapping (a room box behind every pane: lit ceiling
// panels, back wall, floor, desks, part-drawn blinds) under a reflective,
// slightly pillowed pane, so the glass has depth up close and a mottled sky
// reflection from the air. Patterns fade to their mean with distance (fwidth)
// so far towers do not moire.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roof_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float has_roof_tex = 0.0;
uniform float interior_energy = 0.55;
uniform float lobby_energy = 1.6;
uniform float reflect_metal = 0.55;

varying vec3 wpos;
varying vec3 wn;
varying vec4 vc;
varying vec2 fac;
varying vec2 bld;

vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float h1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), u.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), u.x), u.y);
}
// Box-filtered "inside [a, b)" of the unit period, filtered over width fw.
float band(float x, float a, float b, float fw) {
	float f = fract(x);
	float w = max(fw, 1e-4);
	float s = clamp((f - a) / w + 0.5, 0.0, 1.0) - clamp((f - b) / w + 0.5, 0.0, 1.0);
	return mix(s, b - a, clamp(fw * 1.5 - 0.15, 0.0, 1.0));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vc = COLOR;
	fac = UV;
	bld = UV2;
}

// Interior behind a pane. p = position inside the cell (0..1, 0..1), v = view
// ray in room space (x across the bay, y up, z into the room, all in room
// units). Returns rgb radiance (linear, unlit by the sun).
vec3 room(vec2 p, vec3 v, float rs, float office, vec3 wall_c) {
	vec3 o = vec3(p, 0.0);
	vec3 inv = 1.0 / max(abs(v), vec3(1e-4)) * sign(v + 1e-6);
	float tx = ((v.x > 0.0 ? 1.0 : 0.0) - o.x) * inv.x;
	float ty = ((v.y > 0.0 ? 1.0 : 0.0) - o.y) * inv.y;
	float tz = (1.0 - o.z) * inv.z;
	float t = min(min(tx, ty), tz);
	vec3 hp = o + v * t;
	float depth = clamp(hp.z, 0.0, 1.0);
	vec3 c;
	if (t == ty && v.y > 0.0) {
		// ceiling: office panel lights in a grid, dark in between
		float grid = band(hp.x * 2.0, 0.15, 0.85, 0.02) * band(hp.z * 3.0, 0.2, 0.8, 0.02);
		c = mix(vec3(0.20, 0.20, 0.21), vec3(1.0, 0.97, 0.90) * (1.2 + office), grid * office);
		c = mix(c, vec3(0.55, 0.52, 0.47), 1.0 - office);
	} else if (t == ty) {
		// floor: carpet, a desk silhouette near the window
		c = vec3(0.10, 0.10, 0.11) + vec3(0.05) * h1(rs * 9.1);
	} else if (t == tz) {
		// back wall: tinted, with a door or a partition
		c = wall_c;
		float door = step(abs(hp.x - fract(rs * 3.3) * 0.6 - 0.2), 0.08) * step(hp.y, 0.75);
		c = mix(c, c * 0.35, door);
	} else {
		c = wall_c * 0.75;
	}
	// desks / furniture band in the lower third
	float desk = step(hp.y, 0.30) * step(0.22, hp.y) * step(hp.z, 0.75) * step(0.15, hp.z);
	c = mix(c, vec3(0.06, 0.06, 0.07), desk * 0.8 * office);
	// light falloff into the room
	c *= mix(1.0, 0.35, depth);
	return c;
}

void fragment() {
	int cid = clamp(int(vc.r * 10.0), 0, 9);
	float tint = vc.g;
	float seed = vc.a * 113.0;
	float H = max(bld.x, 1.0);
	float lobby = bld.y;
	vec3 n = normalize(wn);
	vec3 V = normalize(wpos - CAMERA_POSITION_WORLD);   // camera -> fragment
	float dist = length(wpos - CAMERA_POSITION_WORLD);

	vec3 alb = vec3(0.5);
	float rough = 0.85;
	float metal = 0.0;
	float spec = 0.5;
	vec3 emis = vec3(0.0);
	vec3 nmap_t = vec3(0.0);  // tangent-space normal tilt (x across, y up)

	if (n.y > 0.55) {
		// ---------------------------------------------------------- roof
		vec2 q = fac;
		vec3 rc;
		if (has_roof_tex > 0.5) {
			rc = texture(roof_tex, q).rgb;
			rc *= mix(0.85, 1.1, tint);
		} else {
			float st = vnoise(wpos.xz * 0.12 + seed) * 0.6 + vnoise(wpos.xz * 0.5 - seed) * 0.4;
			rc = lin(vec3(0.52, 0.51, 0.49)) * (0.75 + 0.4 * st);
		}
		// residential / colonial / shophouse roofs: terracotta or green membrane
		if (cid == 9) {
			// clay pan tiles: courses across the slope, rolls down it
			float roll = band(fac.x / 0.24, 0.0, 0.35, fwidth(fac.x / 0.24));
			float course = band(fac.y / 0.36, 0.0, 0.12, fwidth(fac.y / 0.36));
			rc = lin(mix(vec3(0.55, 0.27, 0.19), vec3(0.45, 0.22, 0.16), tint)) * (0.78 + 0.35 * vnoise(wpos.xz * 1.3 + seed));
			rc *= 1.0 - 0.28 * roll - 0.35 * course;
			rc = mix(rc, lin(vec3(0.22, 0.20, 0.16)), smoothstep(0.65, 0.9, vnoise(wpos.xz * 0.4 + seed)) * 0.4);
		}
		alb = rc;
		rough = 0.9;
		spec = 0.3;
	} else if (n.y < -0.55) {
		// soffits: light concrete with downlights
		alb = lin(vec3(0.62, 0.60, 0.57));
		float dl = band(wpos.x / 2.4, 0.45, 0.55, fwidth(wpos.x / 2.4)) * band(wpos.z / 2.4, 0.45, 0.55, fwidth(wpos.z / 2.4));
		emis = vec3(1.0, 0.85, 0.62) * dl * 3.0;
		rough = 0.9;
	} else {
		// ---------------------------------------------------------- walls
		vec3 t = normalize(vec3(n.z, 0.0, -n.x));
		float u = fac.x;
		float y = fac.y;
		bool is_lobby = y < lobby;
		float fh = (cid == 6) ? 3.1 : ((cid == 9) ? 3.4 : ((cid == 8) ? 4.2 : mix(3.7, 4.3, vc.b)));
		float bw = 1.5;
		if (cid == 1 || cid == 7 || cid == 8) bw = 3.0;
		if (cid == 4) bw = 2.4;
		if (cid == 5) bw = 3.0;
		if (cid == 6) bw = 3.6;
		if (cid == 9) bw = 2.2;
		float yy = is_lobby ? y : (y - lobby);
		float fy = is_lobby ? (y / max(lobby, 1.0)) : (yy / fh);
		float fx = u / (is_lobby ? 3.0 : bw);
		float fwx = fwidth(fx);
		float fwy = fwidth(fy);
		float cell_far = clamp(max(fwx, fwy) * 2.5 - 0.25, 0.0, 1.0);   // 0 near, 1 when a cell < ~2 px
		vec2 cell = vec2(floor(fx), floor(fy));
		vec2 cf = vec2(fract(fx), fract(fy));
		float r = h2(cell + seed);
		float rfl = h2(vec2(floor(fy), seed));
		// cladding palette
		vec3 glass_c = lin(vec3(0.18, 0.27, 0.30));
		vec3 frame_c = lin(vec3(0.70, 0.72, 0.72));
		vec3 solid_c = lin(vec3(0.22, 0.30, 0.32));
		vec3 wall_room = lin(vec3(0.62, 0.60, 0.56));
		float glass_frac_x = 0.94;  // pane share of the bay
		float glass_y0 = 0.22;      // spandrel / sill share of the floor
		float glass_y1 = 0.97;
		float office = 1.0;
		if (cid == 0) {
			glass_c = lin(mix(vec3(0.16, 0.30, 0.31), vec3(0.20, 0.28, 0.36), tint));
			solid_c = glass_c * 0.55;
			frame_c = lin(vec3(0.66, 0.69, 0.70));
			glass_frac_x = 0.95; glass_y0 = 0.24;
		} else if (cid == 1) {
			solid_c = lin(mix(vec3(0.70, 0.64, 0.56), vec3(0.62, 0.60, 0.58), tint));
			glass_c = lin(vec3(0.13, 0.16, 0.18));
			frame_c = lin(vec3(0.25, 0.25, 0.26));
			glass_frac_x = 0.55; glass_y0 = 0.30; glass_y1 = 0.86;
		} else if (cid == 2) {
			solid_c = lin(vec3(0.80, 0.81, 0.80));
			glass_c = lin(mix(vec3(0.24, 0.32, 0.40), vec3(0.30, 0.36, 0.42), tint));
			frame_c = lin(vec3(0.78, 0.79, 0.79));
			glass_frac_x = 0.97; glass_y0 = 0.32; glass_y1 = 0.96;
		} else if (cid == 3) {
			solid_c = lin(vec3(0.16, 0.13, 0.11));
			glass_c = lin(mix(vec3(0.24, 0.19, 0.14), vec3(0.20, 0.18, 0.16), tint));
			frame_c = lin(vec3(0.12, 0.11, 0.10));
			glass_frac_x = 0.80; glass_y0 = 0.20;
		} else if (cid == 4) {
			solid_c = lin(mix(vec3(0.84, 0.84, 0.82), vec3(0.76, 0.78, 0.80), tint));
			glass_c = lin(vec3(0.17, 0.22, 0.26));
			frame_c = lin(vec3(0.55, 0.56, 0.57));
			glass_frac_x = 0.72; glass_y0 = 0.30; glass_y1 = 0.90;
		} else if (cid == 5) {
			solid_c = lin(vec3(0.86, 0.87, 0.86));
			glass_c = lin(mix(vec3(0.22, 0.31, 0.29), vec3(0.20, 0.28, 0.30), tint));
			frame_c = lin(vec3(0.88, 0.89, 0.88));
			glass_frac_x = 0.86; glass_y0 = 0.10; glass_y1 = 0.98;
		} else if (cid == 6) {
			solid_c = lin(mix(vec3(0.86, 0.83, 0.76), vec3(0.78, 0.80, 0.80), tint));
			glass_c = lin(vec3(0.20, 0.26, 0.29));
			frame_c = lin(vec3(0.30, 0.31, 0.32));
			glass_frac_x = 0.70; glass_y0 = 0.30; glass_y1 = 0.92;
			office = 0.0;
			wall_room = lin(vec3(0.80, 0.72, 0.60));
		} else if (cid == 7) {
			solid_c = lin(mix(vec3(0.27, 0.26, 0.26), vec3(0.36, 0.33, 0.30), tint));
			glass_c = lin(vec3(0.17, 0.22, 0.26));
			frame_c = lin(vec3(0.20, 0.20, 0.21));
			glass_frac_x = 0.62; glass_y0 = 0.08; glass_y1 = 1.0;
		} else if (cid == 8) {
			solid_c = lin(mix(vec3(0.90, 0.88, 0.82), vec3(0.86, 0.84, 0.76), tint));
			glass_c = lin(vec3(0.10, 0.14, 0.13));
			frame_c = lin(vec3(0.16, 0.30, 0.22));
			glass_frac_x = 0.42; glass_y0 = 0.22; glass_y1 = 0.80;
			office = 0.3;
		} else {
			// shophouse plaster: pastel family picked by tint
			vec3 p0 = vec3(0.62, 0.71, 0.69); vec3 p1 = vec3(0.78, 0.66, 0.63);
			vec3 p2 = vec3(0.80, 0.70, 0.48); vec3 p3 = vec3(0.68, 0.71, 0.63);
			vec3 p4 = vec3(0.72, 0.68, 0.76); vec3 p5 = vec3(0.86, 0.81, 0.73);
			float k = tint * 6.0;
			vec3 pc = k < 1.0 ? p0 : (k < 2.0 ? p1 : (k < 3.0 ? p2 : (k < 4.0 ? p3 : (k < 5.0 ? p4 : p5))));
			solid_c = lin(pc);
			glass_c = lin(vec3(0.10, 0.12, 0.12));
			frame_c = lin(vec3(0.20, 0.32, 0.26) + vec3(0.1) * h1(seed));
			glass_frac_x = 0.50; glass_y0 = 0.28; glass_y1 = 0.82;
			office = 0.15;
			wall_room = lin(vec3(0.70, 0.55, 0.40));
		}
		if (is_lobby) {
			// shopfront / lobby band: tall glazing, transom, kick plate
			glass_frac_x = 0.94; glass_y0 = 0.06; glass_y1 = 0.97;
			frame_c = (cid == 8 || cid == 9) ? frame_c : lin(vec3(0.20, 0.19, 0.18));
		}
		// pane masks (filtered)
		float px0 = (1.0 - glass_frac_x) * 0.5;
		float gx = band(fx, px0, 1.0 - px0, fwx);
		float gy = band(fy, glass_y0, glass_y1, fwy);
		float pane = gx * gy;
		// mullion vs solid: the frame strips right next to the pane read as
		// mullions; the rest of the bay is the cladding material
		float mull = band(fx, px0 - 0.035, px0, fwx) + band(fx, 1.0 - px0, 1.0 - px0 + 0.035, fwx);
		float transom = is_lobby ? band(fy, 0.70, 0.725, fwy) : 0.0;
		vec3 base = solid_c;
		// stone texture breakup
		float stn = vnoise(vec2(u, y) * vec2(0.9, 0.6) + seed) * 0.5 + vnoise(vec2(u, y) * 4.0) * 0.5;
		if (cid == 1 || cid == 7 || cid == 8 || cid == 9) base *= 0.86 + 0.24 * stn;
		// rain streak weathering under sills on solid claddings
		float streak = vnoise(vec2(u * 3.0, y * 0.05 + seed)) * smoothstep(0.0, 0.25, 1.0 - fract(fy));
		base *= 1.0 - 0.10 * streak * float(cid != 0 && cid != 5);
		// fins (cid 3, 5): shadowed strips beside the fin
		if (cid == 3 || cid == 5) {
			float fin = band(fx, 0.0, 0.06, fwx);
			base = mix(base, frame_c, fin);
		}
		// horizontal slab edge line at every floor
		float slab = band(fy, 0.0, 0.05, fwy) * float(!is_lobby);
		// ---- glass shading
		// view ray into the room (tangent space of this face)
		float room_w = (is_lobby ? 3.0 : bw);
		float room_h = (is_lobby ? max(lobby, 1.0) : fh);
		float room_d = is_lobby ? 9.0 : 6.5;
		vec3 vr = vec3(dot(V, t) / room_w, V.y / room_h, dot(V, -n) / room_d);
		float rs = r + seed;
		vec3 wr = wall_room * mix(0.7, 1.1, h1(rs * 5.7));
		float lit = (is_lobby ? 1.0 : step(0.18, h1(rs * 2.3)));  // ~18% of rooms dark
		vec3 interior = room(cf, vr, rs, office * lit, wr) * (is_lobby ? lobby_energy : interior_energy);
		if (is_lobby) interior *= vec3(1.15, 0.95, 0.75);   // warm shop light
		// blinds: part-drawn per room (not in the lobby)
		float blind_h = is_lobby ? 1.1 : mix(0.95, 0.35, step(0.55, h1(rs * 7.9)) * h1(rs * 3.1));
		float blind = step(blind_h, cf.y) * (1.0 - float(is_lobby));
		interior = mix(interior, vec3(0.42, 0.42, 0.40) * interior_energy * 0.8, blind);
		// fresnel: more reflection at grazing angles
		float ndv = clamp(dot(-V, n), 0.0, 1.0);
		float fres = pow(1.0 - ndv, 4.0);
		float see = (1.0 - fres) * (1.0 - cell_far * 0.6) * 0.85;
		// pillowed panes: each pane tilts a little so the sky reflection breaks up
		nmap_t = vec3((h2(cell * 1.7 + seed) - 0.5) * 0.06, (h2(cell * 3.1 - seed) - 0.5) * 0.05, 0.0) * pane;
		// ---- combine
		vec3 frame_mix = mix(base, frame_c, clamp(mull + transom + slab, 0.0, 1.0));
		alb = mix(frame_mix, glass_c, pane);
		rough = mix(cid == 1 || cid == 7 ? 0.75 : (cid >= 8 ? 0.88 : 0.45), 0.06 + 0.04 * r, pane);
		metal = mix((cid == 2 || cid == 4 || cid == 5) ? 0.35 : 0.0, reflect_metal, pane);
		spec = mix(0.5, 0.9, pane);
		emis = interior * pane * see;
		// lobby: dark bronze kick plate + plinth
		if (y < 0.45) {
			alb = lin(vec3(0.20, 0.19, 0.18)); rough = 0.6; metal = 0.0; emis = vec3(0.0);
		}
		// crown louvres on tall buildings (top ~4 m)
		if (H > 45.0 && y > H - 4.2 && cid <= 7) {
			float lv = band(y / 0.32, 0.0, 0.55, fwidth(y / 0.32));
			alb = mix(lin(vec3(0.46, 0.47, 0.48)), lin(vec3(0.12, 0.12, 0.13)), lv);
			rough = 0.55; metal = 0.4; emis = vec3(0.0);
		}
		// grime toward the base and the parapet
		alb *= 1.0 - 0.12 * smoothstep(6.0, 0.0, y) * (1.0 - pane);
		// distant towers: lift the mean slightly so the mass keeps a light/dark
		// side instead of going uniformly black glass
		alb = mix(alb, alb * 1.15 + vec3(0.01), cell_far * 0.5);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emis;
	// tilt the normal per pane (view-space)
	if (length(nmap_t) > 0.0) {
		vec3 tw = normalize(vec3(n.z, 0.0, -n.x));
		vec3 nw = normalize(n + tw * nmap_t.x + vec3(0.0, 1.0, 0.0) * nmap_t.y);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
}
