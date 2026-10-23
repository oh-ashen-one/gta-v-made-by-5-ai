class_name CrowdPeople
extends RefCounted
## Street-life M2: who the crowd is. Blind critic M1: "every pedestrian I could
## resolve is a young adult man of one build and face, recoloured".
##
## Every civilian is still the one provider rig (no other body exists in the
## build and paid generation is off), so this turns it into different people
## procedurally, per figure and for life:
## - kind: man, woman, elderly man/woman (aunties and uncles), child
## - stature and build (non-uniform scale of the visual), a child's larger head
## - skin tone (Chinese / Malay / Indian / Eurasian range) on the skin surface,
##   grey hair for elders, a cleaner, softer lower face for women
## - generated hair for women and elders (bob, long, ponytail, bun, pixie,
##   permed curls) on the head bone, strand-shaded with ragged tips
## - A-line skirts and dresses (skirt on the pelvis bone, legs re-dyed skin or
##   tights below the hem)
## - props: phone (texting pose, head down), coffee / bubble-tea cup, open
##   sun umbrella, cross-body handbag, backpack, shopping bag
## Poses for props and the elders' stoop come from a small SkeletonModifier3D
## that runs after the animation (people_pose.gd).
## Nothing here touches collision or simulation: the NPC stays the authority.

enum Kind { MAN, WOMAN, ELDER_M, ELDER_F, CHILD }
const KIND_NAMES := ["man", "woman", "elder_m", "elder_f", "child"]

## Character-space head and hip fit of civilian_rigged_v2 (measured from the
## mesh: crown 1.753 m, head bone origin (0, 1.54, 0.02), pelvis 0.90 m).
const HEAD_C := Vector3(0.0, 1.645, 0.016)
const HEAD_R := Vector3(0.094, 0.112, 0.113)
const WAIST_Y := 0.985
const HEM_Y := 0.56

const HAIR_COLOURS: Array[Color] = [
	Color(0.022, 0.018, 0.016), Color(0.03, 0.022, 0.018), Color(0.055, 0.035, 0.025),
	Color(0.10, 0.06, 0.035), Color(0.16, 0.09, 0.05), Color(0.035, 0.028, 0.026),
]
const GREY_HAIR: Array[Color] = [Color(0.42, 0.41, 0.4), Color(0.6, 0.59, 0.57), Color(0.28, 0.27, 0.27)]
## Multipliers on the provider skin texture (a warm light-medium tone).
const SKIN_TONES: Array[Color] = [
	Color(1.10, 1.06, 1.02), Color(1.04, 1.0, 0.95), Color(0.98, 0.93, 0.88),   # Chinese
	Color(0.84, 0.76, 0.68), Color(0.78, 0.70, 0.62),                              # Malay
	Color(0.62, 0.53, 0.48), Color(0.54, 0.46, 0.42),                              # Indian
	Color(1.12, 1.04, 1.0),                                                         # Eurasian / expat
]
const DRESS_COLOURS: Array[Color] = [
	Color(0.72, 0.16, 0.2), Color(0.12, 0.2, 0.42), Color(0.9, 0.86, 0.78), Color(0.1, 0.1, 0.11),
	Color(0.85, 0.55, 0.62), Color(0.2, 0.45, 0.42), Color(0.86, 0.68, 0.3), Color(0.45, 0.32, 0.55),
	Color(0.55, 0.62, 0.42), Color(0.3, 0.52, 0.75),
]
const PROP_COLOURS: Array[Color] = [
	Color(0.08, 0.08, 0.09), Color(0.55, 0.12, 0.12), Color(0.75, 0.62, 0.45), Color(0.15, 0.25, 0.45),
	Color(0.85, 0.82, 0.75), Color(0.3, 0.2, 0.14), Color(0.6, 0.5, 0.7),
]
const UMBRELLA_COLOURS: Array[Color] = [
	Color(0.1, 0.12, 0.3), Color(0.7, 0.12, 0.15), Color(0.12, 0.12, 0.13), Color(0.85, 0.7, 0.25),
	Color(0.25, 0.5, 0.45), Color(0.82, 0.55, 0.65), Color(0.95, 0.95, 0.92),
]

static var _hair_meshes: Dictionary = {}
static var _misc_meshes: Dictionary = {}
static var _hair_shader: Shader
static var _skin_shader: Shader
static var _cloth_shader: Shader
static var _plain_mats: Dictionary = {}
static var stats := {}

## Deterministic choice of a person for this figure.
static func pick(seed_value: int) -> Dictionary:
	var h := posmod(hash(seed_value * 2246822519 + 7), 1 << 30)
	var r := float(h % 1000) / 1000.0
	var kind: int
	if r < 0.40: kind = Kind.WOMAN
	elif r < 0.75: kind = Kind.MAN
	elif r < 0.83: kind = Kind.ELDER_F
	elif r < 0.91: kind = Kind.ELDER_M
	else: kind = Kind.CHILD
	return person(kind, h)

static func person(kind: int, h: int) -> Dictionary:
	var u := func(salt: int) -> float: return float(posmod(hash(h * 31 + salt * 977), 10000)) / 10000.0
	var p := {"kind": kind, "name": KIND_NAMES[kind], "seed": h}
	var female: bool = kind == Kind.WOMAN or kind == Kind.ELDER_F or (kind == Kind.CHILD and u.call(1) < 0.5)
	p["female"] = female
	p["skin"] = SKIN_TONES[int(u.call(2) * SKIN_TONES.size()) % SKIN_TONES.size()]
	match kind:
		Kind.WOMAN:
			var hh := lerpf(0.9, 0.97, u.call(3))
			p["scale"] = Vector3(lerpf(0.86, 0.93, u.call(4)), hh, lerpf(0.88, 0.95, u.call(5)))
			p["hair"] = ["bob", "long", "pony", "bun", "pixie", "long", "bob_bangs"][int(u.call(6) * 7.0) % 7]
			p["hair_colour"] = HAIR_COLOURS[int(u.call(7) * HAIR_COLOURS.size()) % HAIR_COLOURS.size()]
			p["skirt"] = u.call(8) < 0.5
			p["dress"] = p["skirt"] and u.call(9) < 0.45
			p["pace"] = lerpf(0.88, 1.12, u.call(10))
			p["prop"] = ["phone", "cup", "handbag", "handbag", "umbrella", "shopping", "none", "phone", "cup"][int(u.call(11) * 9.0) % 9]
		Kind.MAN:
			var hm := lerpf(0.97, 1.06, u.call(3))
			var w := lerpf(0.97, 1.12, u.call(4))
			p["scale"] = Vector3(w, hm, lerpf(0.97, 1.1, u.call(5)))
			p["hair"] = "cap" if u.call(6) < 0.14 else ""
			p["hair_colour"] = PROP_COLOURS[int(u.call(7) * PROP_COLOURS.size()) % PROP_COLOURS.size()]
			p["pace"] = lerpf(0.9, 1.18, u.call(10))
			p["prop"] = ["phone", "cup", "backpack", "none", "none", "shopping", "phone", "backpack", "umbrella"][int(u.call(11) * 9.0) % 9]
		Kind.ELDER_F:
			p["scale"] = Vector3(lerpf(0.92, 1.0, u.call(4)), lerpf(0.86, 0.92, u.call(3)), lerpf(0.94, 1.02, u.call(5)))
			p["hair"] = ["perm", "perm", "bun", "pixie"][int(u.call(6) * 4.0) % 4]
			p["hair_colour"] = GREY_HAIR[int(u.call(7) * GREY_HAIR.size()) % GREY_HAIR.size()]
			p["grey"] = true
			p["skirt"] = u.call(8) < 0.3
			p["pace"] = lerpf(0.62, 0.8, u.call(10))
			p["stoop"] = lerpf(0.1, 0.24, u.call(12))
			p["prop"] = ["shopping", "umbrella", "shopping", "handbag", "none"][int(u.call(11) * 5.0) % 5]
		Kind.ELDER_M:
			p["scale"] = Vector3(lerpf(0.95, 1.04, u.call(4)), lerpf(0.9, 0.97, u.call(3)), lerpf(0.97, 1.05, u.call(5)))
			p["hair"] = "cap" if u.call(6) < 0.3 else ""
			p["hair_colour"] = PROP_COLOURS[int(u.call(7) * PROP_COLOURS.size()) % PROP_COLOURS.size()]
			p["grey"] = true
			p["pace"] = lerpf(0.6, 0.78, u.call(10))
			p["stoop"] = lerpf(0.12, 0.28, u.call(12))
			p["prop"] = ["shopping", "none", "cup", "none", "umbrella"][int(u.call(11) * 5.0) % 5]
		Kind.CHILD:
			var c := lerpf(0.56, 0.72, u.call(3))
			p["scale"] = Vector3(c * 1.06, c, c * 1.04)
			p["head_scale"] = lerpf(1.32, 1.18, (c - 0.56) / 0.16)
			p["hair"] = (["pony", "bob_bangs", "long"][int(u.call(6) * 3.0) % 3]) if female else ""
			p["hair_colour"] = HAIR_COLOURS[int(u.call(7) * 3.0) % 3]
			p["skirt"] = female and u.call(8) < 0.5
			p["pace"] = lerpf(0.95, 1.15, u.call(10))
			p["prop"] = "backpack" if u.call(11) < 0.55 else "none"
	p["dress_colour"] = DRESS_COLOURS[int(u.call(13) * DRESS_COLOURS.size()) % DRESS_COLOURS.size()]
	p["prop_colour"] = PROP_COLOURS[int(u.call(14) * PROP_COLOURS.size()) % PROP_COLOURS.size()]
	p["umbrella_colour"] = UMBRELLA_COLOURS[int(u.call(15) * UMBRELLA_COLOURS.size()) % UMBRELLA_COLOURS.size()]
	p["legs"] = Color(0.07, 0.065, 0.07) if u.call(16) < 0.3 else Color(-1, 0, 0)   # dark tights, else bare
	return p

## Turn an NPC's provider figure into the person `p` (pick() if omitted).
static func dress(npc: Node3D, cv: CharacterVisual, p: Dictionary, seated: bool = false) -> void:
	if cv == null or not cv.loaded or cv.skeleton == null or cv.has_meta("people"):
		return
	cv.set_meta("people", p)
	npc.set_meta("people", p)
	stats[p["name"]] = int(stats.get(p["name"], 0)) + 1
	var sk := cv.skeleton
	var sc: Vector3 = p["scale"]
	cv.scale = sc
	var kind: int = p["kind"]
	var female: bool = p["female"]
	var prop: String = String(p.get("prop", "none"))
	if seated and prop in ["umbrella", "backpack", "shopping"]:
		prop = "none"
	var skirt := bool(p.get("skirt", false)) and not seated
	# Surfaces: skin tone / grey hair / softer lower face; dress colour; legs.
	_retint(cv, p, skirt)
	var hair := String(p.get("hair", ""))
	var range_hair := 60.0
	if hair != "":
		var hmat: Material = _cloth_material(p["hair_colour"]) if hair == "cap" else _hair_material(p["hair_colour"], int(p["seed"]))
		var hn := _attach(sk, "head", _hair_mesh(hair), hmat, Transform3D(Basis(), HEAD_C), range_hair, false)
		hn.name = "PeopleHair"
	if skirt:
		var col: Color = p["dress_colour"]
		var sn := _attach(sk, "pelvis", _misc("skirt"), _cloth_material(col), Transform3D(), 60.0, false)
		sn.name = "PeopleSkirt"
	var pose := ""
	match prop:
		"phone":
			pose = "phone"
			var hand := _attach_posed(sk, "hand.l", _misc("phone"), _plain(Color(0.04, 0.04, 0.05), 0.25, 0.4),
				Basis(Vector3.RIGHT, -0.93), Vector3(-0.01, 0.025, 0.0), 45.0)
			hand.name = "PeoplePhone"
			var screen := _attach_posed(sk, "hand.l", _misc("phone_screen"), _emissive(Color(0.55, 0.7, 0.95), 0.6),
				Basis(Vector3.RIGHT, -0.93), Vector3(-0.01, 0.025, 0.0), 30.0)
			screen.name = "PeoplePhoneScreen"
		"cup":
			pose = "cup"
			var tea := posmod(int(p["seed"]), 3) == 0
			var cup := _attach_posed(sk, "hand.l", _misc("bubble_tea" if tea else "cup"),
				_plain(Color(0.86, 0.72, 0.55) if tea else Color(0.92, 0.9, 0.86), 0.5, 0.0), Basis(), Vector3(-0.02, 0.02, 0.0), 45.0)
			cup.name = "PeopleCup"
			var lid := _attach_posed(sk, "hand.l", _misc("cup_lid"), _plain(Color(0.25, 0.14, 0.08) if not tea else Color(0.95, 0.95, 0.95), 0.4, 0.0),
				Basis(), Vector3(-0.02, 0.02, 0.0), 40.0)
			lid.name = "PeopleCupLid"
		"umbrella":
			pose = "umbrella"
			var col_u: Color = p["umbrella_colour"]
			var shaft := _attach_posed(sk, "hand.l", _misc("umbrella_shaft"), _plain(Color(0.12, 0.12, 0.12), 0.35, 0.6),
				Basis(Vector3.BACK, 0.22) * Basis(Vector3.RIGHT, 0.3), Vector3(-0.015, 0.0, 0.0), 40.0)
			shaft.name = "PeopleUmbrellaShaft"
			var canopy := _attach_posed(sk, "hand.l", _misc("umbrella"), _cloth_material(col_u, true),
				Basis(Vector3.BACK, 0.22) * Basis(Vector3.RIGHT, 0.3), Vector3(-0.015, 0.0, 0.0), 40.0, true)
			canopy.name = "PeopleUmbrella"
		"handbag":
			var hb := _attach(sk, "chest", _misc("handbag"), _plain(p["prop_colour"], 0.45, 0.0), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), 45.0, false)
			hb.name = "PeopleHandbag"
		"backpack":
			var bp := _attach(sk, "chest", _misc("backpack"), _cloth_material(p["prop_colour"]), Transform3D(), 60.0, false)
			bp.name = "PeopleBackpack"
		"shopping":
			var sb := _attach(sk, "hand.r", _misc("shopping"), _plain(Color(0.93, 0.92, 0.88) if posmod(int(p["seed"]), 2) == 0 else Color(0.85, 0.3, 0.18), 0.7, 0.0),
				Transform3D(Basis(), Vector3(-0.255, 0.74, 0.02)), 45.0, false)
			sb.name = "PeopleShopping"
	var stoop := float(p.get("stoop", 0.0))
	var head_scale := float(p.get("head_scale", 1.0))
	if pose != "" or stoop > 0.0 or head_scale != 1.0:
		var mod := PeoplePose.new()
		mod.name = "PeoplePose"
		mod.pose = pose
		mod.stoop = stoop
		mod.head_scale = head_scale
		sk.add_child(mod)
	# Hidden-near rule from the NPC (the lens must not fill with a face) also
	# applies to the new parts.
	for mi in cv.find_children("People*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).visibility_range_begin = NPC.NEAR_HIDE

# ------------------------------------------------------------------ helpers
static func _attach(sk: Skeleton3D, bone: String, mesh: Mesh, mat: Material, char_xf: Transform3D, range_end: float, shadow: bool = false) -> MeshInstance3D:
	var id := sk.find_bone(bone)
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	sk.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = range_end
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The skeleton has an identity transform in the visual: rest globals are
	# character space.
	var rest := sk.get_bone_global_rest(id) if id >= 0 else Transform3D()
	mi.transform = rest.affine_inverse() * char_xf
	att.add_child(mi)
	return mi

## Attachment to a hand that PeoplePose lifts in front of the body: the
## prop's orientation is authored in character space for the posed arm, at
## the palm (7 cm down the hand bone) plus `offset`.
static func _attach_posed(sk: Skeleton3D, bone: String, mesh: Mesh, mat: Material, basis: Basis, offset: Vector3, range_end: float, shadow: bool = false) -> MeshInstance3D:
	var mi := _attach(sk, bone, mesh, mat, Transform3D(), range_end, shadow)
	var posed := PeoplePose.posed_hand_rest(sk, bone)
	var palm := posed * Vector3(0.0, 0.07, 0.0)
	mi.transform = posed.affine_inverse() * Transform3D(basis, palm + offset)
	return mi

static func _retint(cv: CharacterVisual, p: Dictionary, skirt: bool) -> void:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER
	var dress := bool(p.get("dress", false))
	for node in cv.model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(i) as StandardMaterial3D
			var mname := String(base.resource_name) if base != null else ""
			if mname.contains("Skin") and base != null and base.albedo_texture != null:
				var sm := ShaderMaterial.new()
				sm.shader = _skin_shader
				sm.set_shader_parameter("albedo_tex", base.albedo_texture)
				if base.normal_texture != null:
					sm.set_shader_parameter("normal_tex", base.normal_texture)
				if base.roughness_texture != null:
					sm.set_shader_parameter("orm_tex", base.roughness_texture)
				var tone: Color = p["skin"]
				sm.set_shader_parameter("skin_mul", Vector3(tone.r, tone.g, tone.b))
				sm.set_shader_parameter("grey_hair", 1.0 if bool(p.get("grey", false)) else 0.0)
				sm.set_shader_parameter("feminine", 1.0 if bool(p["female"]) else 0.0)
				var hc: Color = p.get("hair_colour", Color(0.03, 0.025, 0.02))
				sm.set_shader_parameter("hair_col", Vector3(hc.r, hc.g, hc.b))
				# Wave-M integration: the trousers live in this skin atlas (the
				# "CharcoalTextile" surface is the shoes, y 0.03-0.18 m), so every
				# civilian wore the same grey camo cargo trousers (critic
				# street-life-M2). Dye the leg texels per person; under a skirt
				# they become bare legs or tights.
				var tc := _trouser_colour(p, skirt)
				sm.set_shader_parameter("trouser_col", Vector3(tc.r, tc.g, tc.b))
				mi.set_surface_override_material(i, sm)
			elif mname.contains("CharacterClothing") and dress:
				var cur := mi.get_surface_override_material(i) as ShaderMaterial
				if cur != null:
					var dc: Color = p["dress_colour"]
					cur.set_shader_parameter("tint", dc)

const TROUSERS: Array[Color] = [
	Color(0.16, 0.24, 0.42), Color(0.07, 0.07, 0.08), Color(0.55, 0.49, 0.36), Color(0.1, 0.12, 0.22),
	Color(0.46, 0.47, 0.48), Color(0.7, 0.66, 0.57), Color(0.27, 0.29, 0.19), Color(0.3, 0.39, 0.57),
	Color(0.22, 0.22, 0.24), Color(0.84, 0.82, 0.76), Color(0.38, 0.25, 0.16), Color(0.21, 0.31, 0.5),
]
static func _trouser_colour(p: Dictionary, skirt: bool) -> Color:
	if skirt:
		var legs: Color = p["legs"]
		if legs.r < 0.0:
			var t: Color = p["skin"]
			legs = Color(0.62 * t.r, 0.44 * t.g, 0.34 * t.b)
		return legs
	var h := posmod(hash(int(p.get("seed", 0)) * 40503 + 7), 1 << 30)
	var c: Color = TROUSERS[h % TROUSERS.size()]
	var j := 0.86 + float((h / 131) % 28) / 100.0
	return Color(c.r * j, c.g * j, c.b * j)

const SKIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 skin_mul = vec3(1.0);
uniform vec3 hair_col = vec3(0.03, 0.025, 0.02);
uniform float grey_hair = 0.0;
uniform float feminine = 0.0;
uniform vec3 trouser_col = vec3(-1.0);
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mx = max(c.r, max(c.g, c.b));
	float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.0001);
	// Skin texels: warm, red over green over blue, mid luminance.
	float skin = step(c.b, c.g) * step(c.g, c.r) * smoothstep(0.035, 0.07, l) * (1.0 - smoothstep(0.55, 0.7, l)) * smoothstep(0.12, 0.25, sat);
	vec3 col = mix(c, c * skin_mul, skin);
	// Trousers (non-skin texels on the legs): one dye per person, the weave's
	// shading kept at low contrast so it no longer reads as camo.
	float legs = (1.0 - skin) * step(0.0, trouser_col.r) * smoothstep(0.13, 0.18, lp.y)
			* (1.0 - smoothstep(0.92, 0.97, lp.y)) * (1.0 - smoothstep(0.2, 0.26, abs(lp.x)));
	float weave = clamp(mix(1.0, l / 0.1, 0.3), 0.72, 1.25);
	col = mix(col, trouser_col * weave, legs);
	// Women: soften the stubbled lower face toward the cheek tone; a lip tint.
	float face = smoothstep(1.50, 1.53, lp.y) * (1.0 - smoothstep(1.595, 1.615, lp.y)) * smoothstep(-0.03, -0.07, lp.z);
	vec3 cheek = vec3(0.42, 0.25, 0.17) * skin_mul;
	col = mix(col, mix(col, cheek, 0.75), feminine * face * (1.0 - skin * 0.4));
	float lips = feminine * smoothstep(0.03, 0.018, abs(lp.x)) * smoothstep(0.012, 0.004, abs(lp.y - 1.548)) * smoothstep(-0.07, -0.085, lp.z);
	col = mix(col, vec3(0.42, 0.12, 0.12) * skin_mul.r, lips * 0.75);
	// Hair texels (dark, on the scalp): elders grey, others their own colour.
	float scalp = smoothstep(1.6, 1.64, lp.y) * (1.0 - skin) * (1.0 - smoothstep(0.06, 0.12, l));
	float back_scalp = smoothstep(1.5, 1.56, lp.y) * smoothstep(0.02, 0.06, lp.z) * (1.0 - skin) * (1.0 - smoothstep(0.06, 0.12, l));
	float hairmask = max(scalp, back_scalp);
	col = mix(col, hair_col * (0.6 + 6.0 * l), hairmask * max(grey_hair, 0.6));
	ALBEDO = col;
	vec4 orm = texture(orm_tex, UV);
	ROUGHNESS = clamp(orm.g * 0.85, 0.35, 1.0);
	SPECULAR = 0.4;
	AO = 1.0;
	SSS_STRENGTH = 0.3 * skin;
	RIM = 0.2;
	RIM_TINT = 0.5;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.1;
}
"""

const HAIR_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform vec3 base : source_color = vec3(0.03, 0.025, 0.02);
uniform float seed = 0.0;
float h1(float x) { return fract(sin(x * 12.9898 + seed * 78.233) * 43758.5453); }
void fragment() {
	// UV.x runs round the head, UV.y from the crown (0) to the tips (1).
	float sx = UV.x * 120.0;
	float s = h1(floor(sx));
	float s2 = h1(floor(UV.x * 61.0) + 17.0);
	float tip = 0.9 + 0.1 * h1(floor(UV.x * 140.0) + 3.0);
	// Ragged ends: individual clumps stop at different lengths.
	if (UV.y > tip - 0.06 * s2) { discard; }
	float strand = 0.72 + 0.42 * s * (0.6 + 0.4 * s2);
	float root = mix(0.8, 1.0, smoothstep(0.0, 0.15, UV.y));
	ALBEDO = base * strand * root;
	ROUGHNESS = 0.42 + 0.18 * s;
	SPECULAR = 0.55;
	ANISOTROPY = 0.75;
	ANISOTROPY_FLOW = vec2(0.0, 1.0);
	RIM = 0.35;
	RIM_TINT = 0.6;
	BACKLIGHT = vec3(0.08) + base * 0.5;
}
"""

const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 base : source_color = vec3(0.5);
uniform float gloss = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float n2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	// Woven grain plus soft fold shading toward the hem.
	float weave = 0.94 + 0.06 * n2(floor(UV * vec2(260.0, 140.0)));
	float fold = 0.88 + 0.12 * sin(UV.x * 6.2831 * 9.0 + sin(UV.x * 40.0) * 0.6);
	ALBEDO = base * weave * mix(1.0, fold, UV.y);
	ROUGHNESS = mix(0.86, 0.4, gloss);
	SPECULAR = mix(0.3, 0.5, gloss);
	RIM = 0.4;
	RIM_TINT = 0.7;
	BACKLIGHT = base * 0.35 * gloss;
}
"""

static func _hair_material(col: Color, seed_value: int) -> ShaderMaterial:
	if _hair_shader == null:
		_hair_shader = Shader.new()
		_hair_shader.code = HAIR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _hair_shader
	m.set_shader_parameter("base", col)
	m.set_shader_parameter("seed", float(posmod(seed_value, 997)) * 0.37)
	return m

static func _cloth_material(col: Color, glossy: bool = false) -> ShaderMaterial:
	if _cloth_shader == null:
		_cloth_shader = Shader.new()
		_cloth_shader.code = CLOTH_SHADER
	var m := ShaderMaterial.new()
	m.shader = _cloth_shader
	m.set_shader_parameter("base", col)
	m.set_shader_parameter("gloss", 0.6 if glossy else 0.0)
	return m

static func _plain(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [col.to_html(), rough, metal]
	if _plain_mats.has(key):
		return _plain_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_plain_mats[key] = m
	return m

static func _emissive(col: Color, energy: float) -> StandardMaterial3D:
	var key := "e%s/%.2f" % [col.to_html(), energy]
	if _plain_mats.has(key):
		return _plain_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.15
	_plain_mats[key] = m
	return m

# -------------------------------------------------------------- hair meshes
## Hair as a shell over the skull that continues as a hanging curtain: each
## of NA columns round the head runs from the crown down its own length (the
## face sector stops at the hairline). Lengths are arc units: pi/2 = the
## head's equator, beyond that metres of hang / head radius.
const NA := 56
const NR := 22
static func _hair_mesh(style: String) -> Mesh:
	if _hair_meshes.has(style):
		return _hair_meshes[style]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match style:
		"pixie": _shell(st, 2.05, 1.62, 1.0, 1.04, 0.0)
		"bob": _shell(st, 3.05, 2.95, 1.05, 1.05, 0.0)
		"bob_bangs": _shell(st, 3.0, 2.9, 1.42, 1.05, 0.0)
		"long": _shell(st, 4.6, 2.95, 1.05, 1.05, 0.0)
		"pony":
			_shell(st, 2.0, 1.64, 1.0, 1.03, 0.0)
			_tube(st, Vector3(0.0, 0.07, 0.1), Vector3(0.0, -0.2, 0.17), 0.04, 0.012)
		"bun":
			_shell(st, 2.0, 1.64, 1.0, 1.03, 0.0)
			_blob(st, Vector3(0.0, 0.085, 0.085), 0.052)
		"perm": _shell(st, 1.95, 1.7, 1.02, 1.14, 1.0)
		"cap": _cap(st)
	st.generate_normals()
	var m := st.commit()
	_hair_meshes[style] = m
	return m

static func _shell(st: SurfaceTool, back_len: float, side_len: float, front_len: float, puff: float, curls: float) -> void:
	var r_eff := (HEAD_R.x + HEAD_R.z) * 0.5
	var verts: Array = []
	for i in NA + 1:
		var a := float(i) / NA * TAU        # 0 = back (+Z), PI = face (-Z)
		var w := absf(wrapf(a, -PI, PI)) / PI   # 0 back .. 1 front
		var length := back_len
		if w > 0.2:
			length = lerpf(back_len, side_len, smoothstep(0.2, 0.42, w))
		if w > 0.62:
			length = lerpf(side_len, front_len, smoothstep(0.66, 0.84, w))
		var col: Array = []
		for j in NR + 1:
			var t := float(j) / NR
			var u := t * length
			var pt: Vector3
			var cu := minf(u, PI * 0.5)
			var bump := 1.0 + curls * 0.05 * sin(a * 23.0) * sin(cu * 17.0)
			var ex := HEAD_R.x * puff * bump
			var ez := HEAD_R.z * puff * bump
			pt = Vector3(ex * sin(cu) * sin(a), HEAD_R.y * puff * cos(cu), ez * sin(cu) * cos(a))
			if u > PI * 0.5:
				var hang := (u - PI * 0.5) * r_eff
				var out := Vector3(sin(a), 0.0, cos(a))
				# Hang straight down, flaring a little; the back drapes over the
				# shoulders and upper back, the face-side ends tuck in.
				var flare := hang * 0.1
				if hang > 0.12:
					flare += (hang - 0.12) * 0.3 * (1.0 - w)
				pt += Vector3(0.0, -hang, 0.0) + out * flare
			pt.y -= 0.004
			col.append(pt)
		verts.append(col)
	for i in NA:
		for j in NR:
			var p00: Vector3 = verts[i][j]
			var p10: Vector3 = verts[i + 1][j]
			var p01: Vector3 = verts[i][j + 1]
			var p11: Vector3 = verts[i + 1][j + 1]
			var u0 := float(i) / NA
			var u1 := float(i + 1) / NA
			var v0 := float(j) / NR
			var v1 := float(j + 1) / NR
			_tri(st, p00, p01, p11, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			_tri(st, p00, p11, p10, Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_uv(ua); st.add_vertex(a)
	st.set_uv(ub); st.add_vertex(b)
	st.set_uv(uc); st.add_vertex(c)

## Tapered tube from a to b (ponytail), uv.y along it.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.RIGHT).normalized()
	var up := side.cross(axis).normalized()
	var seg := 12
	var rows := 8
	for i in seg:
		for j in rows:
			var q := func(ii: int, jj: int) -> Vector3:
				var t := float(jj) / rows
				var ang := float(ii) / seg * TAU
				var r := lerpf(r0, r1, t) * (1.0 + 0.25 * sin(t * PI))
				return a.lerp(b, t) + (side * cos(ang) + up * sin(ang)) * r + Vector3(0, 0, 0.03 * sin(t * PI))
			var u0 := float(i) / seg
			var u1 := float(i + 1) / seg
			var v0 := float(j) / rows * 0.9
			var v1 := float(j + 1) / rows * 0.9
			_tri(st, q.call(i, j), q.call(i, j + 1), q.call(i + 1, j + 1), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			_tri(st, q.call(i, j), q.call(i + 1, j + 1), q.call(i + 1, j), Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0))

static func _blob(st: SurfaceTool, c: Vector3, r: float) -> void:
	var seg := 14
	var rows := 8
	for i in seg:
		for j in rows:
			var q := func(ii: int, jj: int) -> Vector3:
				var th := float(jj) / rows * PI
				var ph := float(ii) / seg * TAU
				return c + Vector3(sin(th) * cos(ph), cos(th) * 0.85, sin(th) * sin(ph)) * r
			var uv := Vector2(float(i) / seg, float(j) / rows * 0.8)
			var uv2 := Vector2(float(i + 1) / seg, float(j + 1) / rows * 0.8)
			_tri(st, q.call(i, j), q.call(i, j + 1), q.call(i + 1, j + 1), uv, Vector2(uv.x, uv2.y), uv2)
			_tri(st, q.call(i, j), q.call(i + 1, j + 1), q.call(i + 1, j), uv, uv2, Vector2(uv2.x, uv.y))

## A baseball cap: crown dome plus a brim at the forehead (uv.y < 0.5 so the
## hair shader never trims it).
static func _cap(st: SurfaceTool) -> void:
	var seg := 20
	var rows := 6
	for i in seg:
		for j in rows:
			var q := func(ii: int, jj: int) -> Vector3:
				var th := float(jj) / rows * PI * 0.5
				var ph := float(ii) / seg * TAU
				return Vector3(sin(th) * sin(ph) * HEAD_R.x * 1.1, cos(th) * HEAD_R.y * 1.04 - 0.012, sin(th) * cos(ph) * HEAD_R.z * 1.08)
			var uv := Vector2(float(i) / seg, float(j) / rows * 0.4)
			_tri(st, q.call(i, j), q.call(i, j + 1), q.call(i + 1, j + 1), uv, uv, uv)
			_tri(st, q.call(i, j), q.call(i + 1, j + 1), q.call(i + 1, j), uv, uv, uv)
	# Brim, a flattened half-disc over the face.
	var c := Vector3(0.0, -0.012, -HEAD_R.z * 0.9)
	for i in 10:
		var a0 := PI * 0.5 + float(i) / 10.0 * PI
		var a1 := PI * 0.5 + float(i + 1) / 10.0 * PI
		var p0 := Vector3(-cos(a0) * 0.1, -0.01, sin(a0) * -0.075) + Vector3(0, 0, -HEAD_R.z * 0.75)
		var p1 := Vector3(-cos(a1) * 0.1, -0.01, sin(a1) * -0.075) + Vector3(0, 0, -HEAD_R.z * 0.75)
		_tri(st, c, p0, p1, Vector2(0.1, 0.1), Vector2(0.1, 0.1), Vector2(0.1, 0.1))

# --------------------------------------------------------------- misc meshes
static func _misc(id: String) -> Mesh:
	if _misc_meshes.has(id):
		return _misc_meshes[id]
	var m: Mesh
	match id:
		"skirt": m = _skirt_mesh()
		"phone":
			var b := BoxMesh.new(); b.size = Vector3(0.072, 0.15, 0.009); m = b
		"phone_screen":
			var q := QuadMesh.new(); q.size = Vector2(0.064, 0.138); q.center_offset = Vector3(0, 0, 0.0048)
			m = q
		"cup":
			var c := CylinderMesh.new(); c.top_radius = 0.042; c.bottom_radius = 0.032; c.height = 0.13; c.radial_segments = 14; m = c
		"bubble_tea":
			var c2 := CylinderMesh.new(); c2.top_radius = 0.045; c2.bottom_radius = 0.037; c2.height = 0.16; c2.radial_segments = 14; m = c2
		"cup_lid":
			var c3 := CylinderMesh.new(); c3.top_radius = 0.03; c3.bottom_radius = 0.046; c3.height = 0.022; c3.radial_segments = 14
			var st := SurfaceTool.new()
			st.append_from(c3, 0, Transform3D(Basis(), Vector3(0, 0.075, 0)))
			m = st.commit()
		"umbrella_shaft":
			var c4 := CylinderMesh.new(); c4.top_radius = 0.009; c4.bottom_radius = 0.009; c4.height = 0.95; c4.radial_segments = 6
			var st2 := SurfaceTool.new()
			st2.append_from(c4, 0, Transform3D(Basis(), Vector3(0, 0.42, 0)))
			m = st2.commit()
		"umbrella": m = _umbrella_mesh()
		"handbag": m = _handbag_mesh()
		"backpack": m = _backpack_mesh()
		"shopping": m = _shopping_mesh()
	_misc_meshes[id] = m
	return m

## A-line skirt from the waist to just above the knee, in pelvis-bone space
## (the pelvis rest frame is the identity at (0, 0.90, 0.055)).
static func _skirt_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 32
	var rows := 6
	var q := func(i: int, j: int) -> Vector3:
		var t := float(j) / rows
		var a := float(i) / seg * TAU
		var y := lerpf(WAIST_Y, HEM_Y, t)
		var rx := lerpf(0.19, 0.29, t)
		var rz := lerpf(0.165, 0.27, t)
		var fold := 1.0 + 0.045 * t * sin(a * 9.0) + 0.02 * t * sin(a * 4.0 + 1.3)
		return Vector3(sin(a) * rx * fold, y, 0.04 + cos(a) * rz * fold)
	for i in seg:
		for j in rows:
			var u0 := float(i) / seg
			var u1 := float(i + 1) / seg
			var v0 := float(j) / rows
			var v1 := float(j + 1) / rows
			_tri(st, q.call(i, j), q.call(i, j + 1), q.call(i + 1, j + 1), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			_tri(st, q.call(i, j), q.call(i + 1, j + 1), q.call(i + 1, j), Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0))
	# Waistband ring closing the top.
	for i in seg:
		var a0 := q.call(i, 0) as Vector3
		var a1 := q.call(i + 1, 0) as Vector3
		var cc := Vector3(0.0, WAIST_Y, 0.04)
		_tri(st, cc, a1, a0, Vector2(0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 0.0))
	st.generate_normals()
	return st.commit()

## Open sun umbrella in hand space: shaft up from the hand, an eight-panel
## canopy (scalloped edge) about 0.9 m above the grip.
static func _umbrella_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, 0.93, 0.0)
	var r := 0.5
	var ribs := 8
	var rows := 4
	for k in ribs:
		for sub in 4:
			var a0 := (float(k) + float(sub) / 4.0) / ribs * TAU
			var a1 := (float(k) + float(sub + 1) / 4.0) / ribs * TAU
			for j in rows:
				var pt := func(a: float, jj: int, ss: float) -> Vector3:
					var t := float(jj) / rows
					# Panels sag between ribs.
					var sag := 0.035 * sin(ss * PI) * t
					var rr := r * sin(t * PI * 0.5) * (1.0 - 0.06 * sin(ss * PI))
					return top + Vector3(sin(a) * rr, -0.24 * (1.0 - cos(t * PI * 0.5)) - sag, cos(a) * rr)
				var s0 := float(sub) / 4.0
				var s1 := float(sub + 1) / 4.0
				var uv := Vector2(float(k) / ribs, float(j) / rows * 0.5)
				_tri(st, pt.call(a0, j, s0), pt.call(a0, j + 1, s0), pt.call(a1, j + 1, s1), uv, uv, uv)
				_tri(st, pt.call(a0, j, s0), pt.call(a1, j + 1, s1), pt.call(a1, j, s1), uv, uv, uv)
	st.generate_normals()
	return st.commit()

## Cross-body bag at the hip (chest-bone space; chest rest origin
## (0, 1.22, 0.065)) with a strap from the opposite shoulder.
static func _handbag_mesh() -> Mesh:
	# M2r: a slim bag carried at the front of the hip on a short strap that
	# runs up the body's side (a long free-standing strap read as a stick).
	var st := SurfaceTool.new()
	var bag := BoxMesh.new()
	bag.size = Vector3(0.2, 0.15, 0.06)
	st.append_from(bag, 0, Transform3D(Basis(Vector3.UP, 0.5), Vector3(-0.135, 0.96, -0.115)))
	var flap := BoxMesh.new()
	flap.size = Vector3(0.205, 0.06, 0.065)
	st.append_from(flap, 0, Transform3D(Basis(Vector3.UP, 0.5), Vector3(-0.135, 1.01, -0.117)))
	var strap := BoxMesh.new()
	strap.size = Vector3(0.016, 0.2, 0.012)
	st.append_from(strap, 0, Transform3D(Basis(Vector3.FORWARD, 0.25), Vector3(-0.19, 1.1, -0.09)))
	st.generate_normals()
	return st.commit()

static func _backpack_mesh() -> Mesh:
	var st := SurfaceTool.new()
	var body := BoxMesh.new()
	body.size = Vector3(0.25, 0.36, 0.12)
	st.append_from(body, 0, Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0.0, 1.17, 0.215)))
	var pocket := BoxMesh.new()
	pocket.size = Vector3(0.22, 0.15, 0.05)
	st.append_from(pocket, 0, Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0.0, 1.06, 0.3)))
	for sx: float in [-0.09, 0.09]:
		var strap := BoxMesh.new()
		strap.size = Vector3(0.045, 0.34, 0.02)
		st.append_from(strap, 0, Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(sx, 1.27, -0.095)))
	st.generate_normals()
	return st.commit()

## Shopping bag hanging from the hand (hand rest origin (-0.247, 0.88, 0.024)).
static func _shopping_mesh() -> Mesh:
	var st := SurfaceTool.new()
	var bag := BoxMesh.new()
	bag.size = Vector3(0.11, 0.3, 0.32)
	st.append_from(bag, 0, Transform3D(Basis(), Vector3(0.0, -0.06, 0.0)))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.012, 0.12, 0.012)
	for sz: float in [-0.06, 0.06]:
		st.append_from(handle, 0, Transform3D(Basis(Vector3.RIGHT, sz * 4.0), Vector3(0.0, 0.14, sz * 0.5)))
	st.generate_normals()
	return st.commit()

## Per-kind counts of a set of NPCs (QA and the self-test).
static func census(npcs: Array) -> Dictionary:
	var out := {}
	for n in npcs:
		if n is Node and is_instance_valid(n) and (n as Node).has_meta("people"):
			var p: Dictionary = (n as Node).get_meta("people")
			out[p["name"]] = int(out.get(p["name"], 0)) + 1
			if String(p.get("prop", "none")) != "none":
				out["with_prop"] = int(out.get("with_prop", 0)) + 1
	return out


