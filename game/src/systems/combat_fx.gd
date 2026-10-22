class_name CombatFx
extends Node3D
## Firearm presentation (combat piece, opus55 wave P): muzzle flash (flame
## cone + star + flash light + smoke), tracers, impact sparks / dust / chips /
## restrained hit mist, bullet-hole decals and ejected brass. Presentation
## only: the shooter (Player._fire / NPC._shoot_at) stays the authority for
## rays, damage and ammunition.
##
## Everything is pooled and batched. Each particle kind is one MultiMesh drawn
## as camera-facing (or velocity-stretched) quads by one shader, simulated
## here in GDScript, so a full firefight is six draw calls plus the decals and
## two flash lights. Pools are hard capped (COMBAT-05: no permanent piles).

const MAX_PARTICLES := {"puff": 260, "chip": 160, "spark": 220, "flash": 24, "flame": 24, "tracer": 32}
const MAX_DECALS := 56
const MAX_CASINGS := 40
const CASING_LIFE := 9.0

static var _instance: CombatFx = null
## Counters read by the regression suite and the combat review.
static var stats := {"muzzle": 0, "tracer": 0, "impact": 0, "decal": 0, "casing": 0, "flinch": 0, "npc_shots": 0}

var _layers := {}
var _decals: Array[Decal] = []
var _decal_next := 0
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []
var _light_peak: Array[float] = []
var _light_next := 0
var _impact_light: OmniLight3D
var _impact_light_t := 0.0
var _casings: MultiMeshInstance3D
var _cas: Array[Dictionary] = []
var _staggers: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _hole_tex: Texture2D
var _hole_normal: Texture2D
var _metal_hole_tex: Texture2D
var _headless := false

## The scene's single effects node, created on first use.
static func get_fx(tree: SceneTree) -> CombatFx:
	if _instance != null and is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	_instance = CombatFx.new()
	_instance.name = "CombatFx"
	# Deferred: the first caller is usually inside a _ready chain.
	tree.root.add_child.call_deferred(_instance)
	return _instance

## One-line hook from Player._ready: effects node, recoil/aim layer and the
## combat HUD overlay.
static func attach_player(player: Node3D) -> void:
	var fx := get_fx(player.get_tree())
	if player.get_node_or_null("PlayerCombat") == null:
		var pc: Node = load("res://src/actors/player_combat.gd").new()
		pc.name = "PlayerCombat"
		player.add_child(pc)
	if fx.get_node_or_null("CombatHud") == null:
		var hud: Node = load("res://src/ui/combat_hud.gd").new()
		hud.name = "CombatHud"
		hud.set("player", player)
		fx.add_child(hud)

func _ready() -> void:
	_rng.seed = 5150
	_headless = DisplayServer.get_name() == "headless"
	process_priority = 30
	top_level = true
	for kind in MAX_PARTICLES:
		_layers[kind] = _make_layer(kind, MAX_PARTICLES[kind])
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.omni_range = 6.0
		l.omni_attenuation = 1.4
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.light_specular = 0.6
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_t.append(0.0)
		_light_peak.append(0.0)
	_impact_light = OmniLight3D.new()
	_impact_light.light_color = Color(1.0, 0.68, 0.35)
	_impact_light.omni_range = 1.6
	_impact_light.shadow_enabled = false
	_impact_light.visible = false
	add_child(_impact_light)
	_build_decal_textures()
	_build_casings()
	CombatAudio.register()

# ------------------------------------------------------------------ public

## A player or NPC shot. `muzzle` is the visible barrel tip, `aim_dir` the
## barrel direction, `end` where the round stopped (hit or max range).
func shot(muzzle: Vector3, aim_dir: Vector3, end: Vector3, hit: bool, normal: Vector3, collider: Object, weapon: String, by_player: bool) -> void:
	if _layers.is_empty():
		return
	stats["muzzle"] += 1
	mark_combat()
	if not by_player:
		stats["npc_shots"] += 1
	var dir := aim_dir.normalized()
	var big := 1.0 if weapon == "pistol" or weapon == "npc_pistol" else 0.8
	# Flame cone: two crossed stretched sheets along the barrel, a star facing
	# the camera and a short side burst, for a 3-frame life with the light.
	var cone_len := _rng.randf_range(0.20, 0.30) * big  # integ-P: compact burst, never swallows the gun
	_emit("flame", muzzle + dir * cone_len * 0.5, Vector3.ZERO, 0.045, cone_len, 0.075 * big, 0.07 * big,
		Color(1.0, 0.85, 0.55, 1.0) * 1.6, 0.0, 0.0, dir, _rng.randf())
	_emit("flame", muzzle + dir * cone_len * 0.32, Vector3.ZERO, 0.04, cone_len * 0.55, 0.085 * big, 0.06 * big,
		Color(1.0, 0.62, 0.30, 1.0) * 1.3, 0.0, 0.0, dir, _rng.randf())
	_emit("flash", muzzle + dir * 0.06, Vector3.ZERO, 0.04, 0.0, 0.11 * big, 0.13 * big,
		Color(1.0, 0.82, 0.55, 1.0) * 1.3, _rng.randf() * TAU, 0.0, Vector3.ZERO, _rng.randf())
	var side := dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	for s in [-1.0, 1.0]:
		_emit("flame", muzzle + side * s * 0.04 + dir * 0.02, Vector3.ZERO, 0.035, 0.06 * big, 0.03, 0.025,
			Color(1.0, 0.7, 0.4, 1.0) * 1.4, 0.0, 0.0, (side * s + dir * 0.4).normalized(), _rng.randf())
	# Muzzle sparks and smoke.
	for i in 5:
		var v := (dir + Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.2, 0.25), _rng.randf_range(-0.25, 0.25))).normalized() * _rng.randf_range(6.0, 14.0)
		_emit("spark", muzzle, v, _rng.randf_range(0.05, 0.12), 0.0, 0.012, 0.006, Color(1.0, 0.7, 0.35, 1.0) * 3.5, 0.0, 4.0, Vector3.ZERO, 0.0, 0.011)
	# Thin grey smoke that curls off the muzzle after the flash.
	for i in 3:
		var sv := dir * _rng.randf_range(0.5, 1.3) + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.15, 0.4), _rng.randf_range(-0.15, 0.15))
		_emit("puff", muzzle + dir * (0.05 + 0.06 * i), sv, _rng.randf_range(0.8, 1.3), 0.0, 0.03 + 0.01 * i, 0.20 + 0.05 * i,
			Color(0.66, 0.66, 0.64, 0.24 - 0.04 * i), _rng.randf() * TAU, -0.35, Vector3.ZERO, _rng.randf(), 0.0, 2.6)
	# The flash light sits ahead of the barrel so it rakes the surroundings
	# instead of blowing out the shooter's own sleeve.
	_flash_light(muzzle + dir * 0.6 + Vector3.UP * 0.1, 1.1 * big if by_player else 1.4)
	# Tracer: a hot streak that travels from the muzzle to the end point.
	var to_end := end - muzzle
	var dist := to_end.length()
	if dist > 1.2:
		stats["tracer"] += 1
		var speed := 340.0
		var life := maxf(dist / speed, 0.034)
		var seg := minf(dist * 0.22, 1.1)
		_emit("tracer", muzzle + to_end.normalized() * seg * 0.5, to_end.normalized() * (dist - seg) / life, life, seg, 0.016, 0.012,
			Color(1.0, 0.80, 0.52, 1.0) * 2.4, 0.0, 0.0, to_end.normalized(), 0.0)
	if hit:
		impact(end, normal, collider, dir)
	_eject_casing(muzzle, dir, by_player)

## Wave Q: firefight clock for HUD suppression (interaction prompts stay
## hidden while shots were fired or someone was hit in the last few seconds).
const COMBAT_HOLD := 4.0
static var _last_combat := -100.0

static func mark_combat() -> void:
	_last_combat = NpcCombat.game_time()

static func in_combat() -> bool:
	return NpcCombat.game_time() - _last_combat < COMBAT_HOLD

## Impact at a resolved hit point.
func impact(point: Vector3, normal: Vector3, collider: Object, shot_dir: Vector3) -> void:
	if _layers.is_empty():
		return
	stats["impact"] += 1
	var n := normal.normalized() if normal.length() > 0.1 else -shot_dir.normalized()
	var is_vehicle := collider != null and (collider is RigidBody3D or collider is VehicleBody3D or (collider is Node and (collider as Node).is_in_group("vehicles")))
	var is_body := collider != null and not is_vehicle and collider is Node and ((collider as Node).is_in_group("npcs") or (collider as Node).is_in_group("player"))
	var reflect := shot_dir.normalized().bounce(n)
	if is_body:
		# Restrained hit mist (no gore): a quick dark-red puff and cloth fibres
		# carried along the round's direction.
		for i in 5:
			var v := (shot_dir.normalized() * 1.8 + n * 0.5 + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.2, 0.7), _rng.randf_range(-0.6, 0.6))) * _rng.randf_range(0.7, 1.5)
			_emit("puff", point, v * 0.7, _rng.randf_range(0.22, 0.34), 0.0, 0.05, _rng.randf_range(0.13, 0.19), Color(0.42, 0.04, 0.035, 0.75), _rng.randf() * TAU, 1.2, Vector3.ZERO, _rng.randf(), 0.0, 5.0)  # wave Q: compact
		for i in 5:
			var v2 := (shot_dir.normalized() * 2.0 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.0, 1.4), _rng.randf_range(-1, 1))) * _rng.randf_range(0.8, 2.0)
			_emit("chip", point, v2, _rng.randf_range(0.3, 0.6), 0.0, 0.012, 0.010, Color(0.22, 0.04, 0.03, 1.0), _rng.randf() * TAU, 9.0, Vector3.ZERO, 0.0)
		Sfx.play_at("impact_body", point, -6.0, _rng.randf_range(0.9, 1.1))
		return
	# Hard surface: a white-hot flash, sparks thrown off the reflection, a
	# dust/plaster puff along the normal, chips that fall, and a bullet hole.
	_emit("flash", point + n * 0.03, Vector3.ZERO, 0.04, 0.0, 0.08, 0.12, Color(1.0, 0.86, 0.6, 1.0) * 2.4, _rng.randf() * TAU, 0.0, Vector3.ZERO, _rng.randf())
	var spark_count := 18 if is_vehicle else 14
	for i in spark_count:
		var v := (reflect * 0.6 + n * 0.8 + Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.3, 0.8), _rng.randf_range(-0.7, 0.7))).normalized() * _rng.randf_range(3.0, 12.0)
		_emit("spark", point + n * 0.02, v, _rng.randf_range(0.10, 0.36), 0.0, 0.013, 0.007, Color(1.0, 0.66, 0.30, 1.0) * 3.5, 0.0, 9.5, Vector3.ZERO, 0.0, 0.007)
	var dust := Color(0.70, 0.66, 0.60, 0.8) if not is_vehicle else Color(0.45, 0.45, 0.46, 0.4)
	for i in (7 if not is_vehicle else 2):
		var v := (n * _rng.randf_range(1.2, 4.0) + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.1, 0.7), _rng.randf_range(-0.6, 0.6)))
		_emit("puff", point + n * 0.05, v, _rng.randf_range(0.8, 1.7), 0.0, 0.08, _rng.randf_range(0.45, 0.85), dust, _rng.randf() * TAU, 0.6, Vector3.ZERO, _rng.randf(), 0.0, 3.4)
	if not is_vehicle:
		for i in 7:
			var v := (n * 2.2 + reflect * 0.8 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0, 1.6), _rng.randf_range(-1, 1))) * _rng.randf_range(0.6, 1.6)
			_emit("chip", point + n * 0.02, v, _rng.randf_range(0.5, 0.9), 0.0, _rng.randf_range(0.012, 0.024), 0.012, Color(0.42, 0.40, 0.37, 1.0), _rng.randf() * TAU, 9.8, Vector3.ZERO, 0.0)
	_impact_light.global_position = point + n * 0.15
	_impact_light.light_energy = 2.2
	_impact_light.visible = true
	_impact_light_t = 0.06
	_place_decal(point, n, collider, is_vehicle)
	Sfx.play_at("impact_hard", point, -4.0, _rng.randf_range(0.85, 1.15))
	if _rng.randf() < 0.3:
		Sfx.play_at("ricochet", point, -9.0, _rng.randf_range(0.85, 1.2))

## Physical stagger: the struck actor is shoved along the round's direction
## and its skeleton flinches (CombatReaction). `lethal` adds a larger shove.
func stagger(actor: CharacterBody3D, from_position: Vector3, amount: float, lethal: bool) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	mark_combat()
	stats["flinch"] += 1
	var away := actor.global_position - from_position
	away.y = 0.0
	if away.length() < 0.05:
		away = -actor.global_transform.basis.z
	away = away.normalized()
	var push := (3.0 if lethal else 2.2) * clampf(amount / 30.0, 0.6, 1.5)
	_staggers.append({"actor": actor, "vel": away * push, "t": 0.36 if not lethal else 0.5})
	var visual: Node = actor.get("character_visual")
	if visual == null:
		visual = actor.get("_visual")
	if visual != null and visual.get("loaded") and visual.get("skeleton") != null:
		var sk: Skeleton3D = visual.get("skeleton")
		var reaction: Node = sk.get_node_or_null("CombatReaction")
		if reaction == null:
			reaction = load("res://src/actors/combat_reaction.gd").new()
			reaction.name = "CombatReaction"
			sk.add_child(reaction)
		reaction.call("kick", away, clampf(amount / 34.0, 0.5, 1.4), lethal, _rng.randf_range(-1.0, 1.0))
		if lethal:
			# Wave Q: a lethal hit hands the body to a physical ragdoll.
			Ragdoll.start(visual, away, clampf(amount / 30.0, 0.6, 1.5))

# ------------------------------------------------------------------ internals

func _emit(kind: String, pos: Vector3, vel: Vector3, life: float, stretch: float, s0: float, s1: float,
		col: Color, roll: float, grav: float, axis: Vector3, noise: float, stretch_k: float = 0.0, drag: float = 0.0) -> void:
	var L: Dictionary = _layers[kind]
	var arr: Array = L["p"]
	if arr.size() >= int(L["max"]):
		# Recycle the oldest particle instead of growing.
		_remove(L, 0)
	arr.append({"pos": pos, "vel": vel, "age": 0.0, "life": maxf(life, 0.001), "stretch": stretch, "s0": s0, "s1": s1,
		"col": col, "roll": roll, "grav": grav, "axis": axis, "noise": noise, "sk": stretch_k, "drag": drag})

func _remove(L: Dictionary, i: int) -> void:
	(L["p"] as Array).remove_at(i)

func _flash_light(at: Vector3, energy: float) -> void:
	var i := _light_next
	_light_next = (_light_next + 1) % _lights.size()
	_lights[i].global_position = at
	_lights[i].visible = true
	_light_peak[i] = energy
	_light_t[i] = 0.0
	_lights[i].light_energy = energy

func _process(delta: float) -> void:
	for i in _lights.size():
		if not _lights[i].visible:
			continue
		_light_t[i] += delta
		# Full for two frames, then a fast falloff (gone by ~70 ms).
		var k := 1.0 if _light_t[i] < 0.034 else maxf(0.0, 1.0 - (_light_t[i] - 0.034) / 0.035)
		_lights[i].light_energy = _light_peak[i] * k
		if k <= 0.0:
			_lights[i].visible = false
	if _impact_light.visible:
		_impact_light_t -= delta
		_impact_light.light_energy = maxf(0.0, _impact_light_t / 0.06) * 2.2
		if _impact_light_t <= 0.0:
			_impact_light.visible = false
	for kind in _layers:
		_step_layer(_layers[kind], delta)
	_step_casings(delta)

func _physics_process(delta: float) -> void:
	for i in range(_staggers.size() - 1, -1, -1):
		var s: Dictionary = _staggers[i]
		var actor = s["actor"]
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
			_staggers.remove_at(i)
			continue
		var v: Vector3 = s["vel"]
		(actor as CharacterBody3D).move_and_collide(v * delta)
		s["vel"] = v * exp(-delta * 7.0)
		s["t"] = float(s["t"]) - delta
		if float(s["t"]) <= 0.0:
			_staggers.remove_at(i)

func _step_layer(L: Dictionary, delta: float) -> void:
	var arr: Array = L["p"]
	var i := 0
	while i < arr.size():
		var p: Dictionary = arr[i]
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) >= float(p["life"]):
			arr.remove_at(i)
			continue
		var v: Vector3 = p["vel"]
		v.y -= float(p["grav"]) * delta
		var drag := float(p["drag"])
		if drag > 0.0:
			v *= exp(-drag * delta)
		p["vel"] = v
		p["pos"] = (p["pos"] as Vector3) + v * delta
		i += 1
	var mm: MultiMesh = L["mm"]
	var n := arr.size()
	if n == 0:
		mm.visible_instance_count = 0
		return
	var buf: PackedFloat32Array = L["buf"]
	var o := 0
	for p in arr:
		var t := float(p["age"]) / float(p["life"])
		var size := lerpf(float(p["s0"]), float(p["s1"]), sqrt(t))
		var pos: Vector3 = p["pos"]
		var c: Color = p["col"]
		var a := c.a
		match L["kind"]:
			"puff":
				a *= (1.0 - t) * (1.0 - t) * minf(1.0, t * 12.0 + 0.25)
			"chip":
				a = 1.0
			"flame", "flash":
				a *= 1.0 if t < 0.5 else (1.0 - t) * 2.0
			"spark":
				a *= 1.0 - t * t
			"tracer":
				a *= 1.0
		var axis: Vector3 = p["axis"]
		var stretch := float(p["stretch"])
		var sk := float(p["sk"])
		if sk > 0.0:
			var vv: Vector3 = p["vel"]
			axis = vv.normalized() if vv.length() > 0.01 else Vector3.UP
			stretch = 0.02 + vv.length() * sk
			pos -= axis * stretch * 0.5
		elif L["kind"] == "flame":
			# flames grow out of the muzzle as they flare
			stretch *= lerpf(0.75, 1.15, t)
		buf[o] = size; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = pos.x
		buf[o + 4] = 0.0; buf[o + 5] = size; buf[o + 6] = 0.0; buf[o + 7] = pos.y
		buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = size; buf[o + 11] = pos.z
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = a
		if stretch > 0.0:
			buf[o + 16] = axis.x; buf[o + 17] = axis.y; buf[o + 18] = axis.z; buf[o + 19] = stretch
		else:
			buf[o + 16] = float(p["roll"]) + t * 0.6; buf[o + 17] = float(p["noise"]); buf[o + 18] = t; buf[o + 19] = 0.0
		o += 20
	for k in range(o, mini(o + 20, buf.size())):
		buf[k] = 0.0
	mm.buffer = buf
	mm.visible_instance_count = n

func _make_layer(kind: String, count: int) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fx_" + kind
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 3000, 8000))
	var mat := ShaderMaterial.new()
	mat.shader = _shader_for(kind)
	mat.set_shader_parameter("noise_tex", _noise_texture())
	mmi.material_override = mat
	add_child(mmi)
	var buf := PackedFloat32Array()
	buf.resize(count * 20)
	return {"kind": kind, "mm": mm, "mmi": mmi, "p": [], "max": count, "buf": buf}

static var _shaders := {}
static var _noise: Texture2D

static func _noise_texture() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 4
		var t := NoiseTexture2D.new()
		t.width = 128
		t.height = 128
		t.seamless = true
		t.noise = n
		_noise = t
	return _noise

const VERTEX_CODE := """
varying vec4 v_col;
varying vec4 v_cu;
void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 cu = INSTANCE_CUSTOM;
	v_col = COLOR;
	v_cu = cu;
	vec3 world;
	if (cu.w > 0.0) {
		vec3 axis = normalize(cu.xyz + vec3(0.0, 0.00001, 0.0));
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 0.001 ? side / sl : vec3(1.0, 0.0, 0.0);
		world = center + axis * VERTEX.y * cu.w + side * VERTEX.x * size;
	} else {
		float r = cu.x;
		vec2 q = vec2(VERTEX.x * cos(r) - VERTEX.y * sin(r), VERTEX.x * sin(r) + VERTEX.y * cos(r));
		world = center + (INV_VIEW_MATRIX[0].xyz * q.x + INV_VIEW_MATRIX[1].xyz * q.y) * size;
	}
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
}
"""

static func _shader_for(kind: String) -> Shader:
	if _shaders.has(kind):
		return _shaders[kind]
	var mode := "unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled"
	var frag := ""
	match kind:
		"puff":
			mode = "blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_lambert_wrap, specular_disabled"
			frag = """
	vec2 p = UV * 2.0 - 1.0;
	float n = texture(noise_tex, UV * 0.55 + vec2(v_cu.y * 7.3, v_cu.y * 3.1 + v_cu.z * 0.2)).r;
	float n2 = texture(noise_tex, UV * 1.3 + vec2(v_cu.y * 2.1, -v_cu.z * 0.35)).r;
	float d = length(p) + (n - 0.5) * 0.75 + (n2 - 0.5) * 0.3;
	float a = smoothstep(1.0, 0.15, d);
	ALBEDO = v_col.rgb * (0.78 + 0.45 * n);
	ALPHA = clamp(a * v_col.a, 0.0, 1.0);
	NORMAL = normalize(vec3(p * 0.6, 1.0));
	ROUGHNESS = 1.0;
"""
		"chip":
			mode = "blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled, specular_disabled"
			frag = """
	vec2 p = abs(UV * 2.0 - 1.0);
	float n = texture(noise_tex, UV * 0.4 + vec2(v_cu.y)).r;
	if (max(p.x, p.y) > 0.75 + n * 0.25) discard;
	ALBEDO = v_col.rgb * (0.8 + 0.4 * n);
	ROUGHNESS = 0.9;
"""
		"spark":
			frag = """
	float u = abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float core = exp(-u * u * 9.0);
	float head = smoothstep(0.0, 0.85, 1.0 - along);
	ALBEDO = v_col.rgb * core * (0.35 + 0.65 * head) * v_col.a;
	ALPHA = 1.0;
"""
		"flash":
			frag = """
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float n = texture(noise_tex, vec2(ang * 0.16 + v_cu.y, d * 0.4 + v_cu.y * 3.0)).r;
	float petals = pow(0.5 + 0.5 * cos(ang * 5.0 + v_cu.y * 6.28), 3.0);
	float rays = exp(-d * (2.4 + 6.0 * (1.0 - petals))) * (0.5 + n);
	float core = exp(-d * d * 22.0) * 2.4;
	float m = clamp(core + rays * 1.1, 0.0, 4.0) * smoothstep(1.0, 0.6, d);
	vec3 hot = mix(vec3(1.0, 0.45, 0.12), vec3(1.0, 0.95, 0.85), clamp(core, 0.0, 1.0));
	ALBEDO = v_col.rgb * hot * m * v_col.a;
	ALPHA = 1.0;
"""
		"flame":
			frag = """
	float u = UV.x * 2.0 - 1.0;
	float v = 1.0 - UV.y; // 0 = muzzle end, 1 = tip
	float n = texture(noise_tex, vec2(UV.x * 0.5 + v_cu.x * 0.0, v * 0.7 - TIME * 0.0) + vec2(fract(dot(v_cu.xyz, vec3(3.1, 7.7, 1.3))))).r;
	float width = pow(sin(clamp(v, 0.0, 1.0) * 3.14159), 0.55) * (0.55 + 0.45 * (1.0 - v)) * (0.75 + 0.5 * n);
	float m = smoothstep(width, width * 0.25, abs(u));
	m *= smoothstep(1.0, 0.55, v + (n - 0.5) * 0.5);
	vec3 col = mix(vec3(1.0, 0.95, 0.82), vec3(1.0, 0.42, 0.10), smoothstep(0.1, 0.9, v + abs(u) * 0.5));
	ALBEDO = v_col.rgb * col * m * v_col.a;
	ALPHA = 1.0;
"""
		"tracer":
			frag = """
	float u = abs(UV.x * 2.0 - 1.0);
	float along = 1.0 - UV.y;
	float core = exp(-u * u * 14.0);
	float fade = pow(along, 1.3);
	ALBEDO = v_col.rgb * core * fade * v_col.a;
	ALPHA = 1.0;
"""
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode " + mode + ";\nuniform sampler2D noise_tex : repeat_enable, filter_linear;\n" + VERTEX_CODE + "\nvoid fragment() {" + frag + "}\n"
	_shaders[kind] = sh
	return sh

# ------------------------------------------------------------------ decals

func _build_decal_textures() -> void:
	_hole_tex = _hole_texture(false)
	_metal_hole_tex = _hole_texture(true)
	for i in MAX_DECALS:
		var d := Decal.new()
		d.size = Vector3(0.2, 0.22, 0.2)
		d.texture_albedo = _hole_tex
		d.albedo_mix = 1.0
		d.upper_fade = 0.15
		d.lower_fade = 0.35
		d.normal_fade = 0.35
		d.cull_mask = 1
		d.visible = false
		d.top_level = true
		add_child(d)
		_decals.append(d)

## Procedural bullet hole: a dark punched core, a crushed lighter ring of
## broken plaster, radiating cracks and a soft soot/dust halo.
func _hole_texture(metal: bool) -> Texture2D:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if not metal else 91
	var cracks := []
	for i in 9:
		cracks.append([rng.randf() * TAU, rng.randf_range(0.35, 0.95), rng.randf_range(0.6, 1.4)])
	var noise := FastNoiseLite.new()
	noise.seed = 12 if not metal else 13
	noise.frequency = 0.09
	for y in size:
		for x in size:
			var p := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5) / (size * 0.5)
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var rr := r + (n - 0.5) * 0.08
			var col := Color(0, 0, 0, 0)
			if metal:
				# Bright punched lip with a dark centre and a scorched ring.
				if rr < 0.13:
					col = Color(0.03, 0.03, 0.03, 1.0)
				elif rr < 0.2:
					col = Color(0.62, 0.62, 0.64, 1.0)
				elif rr < 0.42:
					col = Color(0.1, 0.09, 0.08, (1.0 - (rr - 0.2) / 0.22) * 0.7)
			else:
				var halo := clampf(1.0 - rr / 0.95, 0.0, 1.0)
				col = Color(0.12, 0.11, 0.10, halo * halo * 0.45)
				if rr < 0.52:
					var t := (rr - 0.16) / 0.36
					col = Color(0.36, 0.34, 0.31, 0.75).lerp(Color(0.24, 0.23, 0.21, 0.35), clampf(t, 0.0, 1.0))
					col = col * (0.8 + 0.4 * n)
					col.a = (0.75 - 0.45 * clampf(t, 0.0, 1.0)) * (0.6 + 0.6 * n)
				if rr < 0.2:
					col = Color(0.06, 0.055, 0.05, 1.0).lerp(Color(0.2, 0.19, 0.18, 1.0), clampf((rr - 0.1) / 0.1, 0.0, 1.0))
				for c in cracks:
					var da := absf(wrapf(ang - float(c[0]) - sin(r * 9.0 * float(c[2])) * 0.06, -PI, PI))
					var w := 0.035 * (1.0 - r / float(c[1]))
					if r > 0.15 and r < float(c[1]) and da * r < w * 0.5:
						col = Color(0.08, 0.075, 0.07, maxf(col.a, 0.85))
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _place_decal(point: Vector3, n: Vector3, collider: Object, metal: bool) -> void:
	stats["decal"] += 1
	var d := _decals[_decal_next]
	if d == null or not is_instance_valid(d):
		d = Decal.new()
		d.size = Vector3(0.2, 0.22, 0.2)
		d.albedo_mix = 1.0
		d.upper_fade = 0.15
		d.lower_fade = 0.35
		d.normal_fade = 0.35
		d.cull_mask = 1
		add_child(d)
		_decals[_decal_next] = d
	_decal_next = (_decal_next + 1) % _decals.size()
	if d.get_parent() != self:
		d.reparent(self)
	d.texture_albedo = _metal_hole_tex if metal else _hole_tex
	var up := n
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z).rotated(up, _rng.randf() * TAU)
	var s := _rng.randf_range(0.85, 1.25) * (0.7 if metal else 1.0)
	d.global_transform = Transform3D(b.scaled(Vector3(s, 1.0, s)), point)
	d.visible = true
	# A moving body carries its holes with it.
	if collider is Node3D and (collider is RigidBody3D or collider is VehicleBody3D or collider is CharacterBody3D or collider is AnimatableBody3D):
		d.top_level = false
		d.reparent(collider as Node3D, true)
	else:
		d.top_level = true

# ------------------------------------------------------------------ brass

func _build_casings() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0048
	mesh.bottom_radius = 0.0052
	mesh.height = 0.021
	mesh.radial_segments = 8
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.62, 0.26)
	mat.metallic = 1.0
	mat.roughness = 0.28
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = MAX_CASINGS
	mm.visible_instance_count = 0
	_casings = MultiMeshInstance3D.new()
	_casings.name = "Fx_casings"
	_casings.multimesh = mm
	_casings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_casings.custom_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 3000, 8000))
	add_child(_casings)

func _eject_casing(muzzle: Vector3, dir: Vector3, by_player: bool) -> void:
	stats["casing"] += 1
	if _cas.size() >= MAX_CASINGS:
		_cas.remove_at(0)
	var right := dir.cross(Vector3.UP).normalized()
	if right.length() < 0.1:
		right = Vector3.RIGHT
	var port := muzzle - dir * 0.12 + Vector3.UP * 0.02
	var v := right * _rng.randf_range(1.6, 2.6) + Vector3.UP * _rng.randf_range(1.8, 2.8) - dir * _rng.randf_range(0.2, 0.7)
	var ground := port.y - 1.5
	var q := PhysicsRayQueryParameters3D.create(port + Vector3.UP * 0.1, port + Vector3.DOWN * 4.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		ground = (hit["position"] as Vector3).y
	_cas.append({"pos": port, "vel": v, "basis": Basis(Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(), _rng.randf() * TAU),
		"spin": Vector3(_rng.randf_range(-30, 30), _rng.randf_range(-10, 10), _rng.randf_range(-30, 30)), "ground": ground, "age": 0.0,
		"rest": false, "bounces": 0, "loud": by_player})

func _step_casings(delta: float) -> void:
	var i := 0
	while i < _cas.size():
		var c: Dictionary = _cas[i]
		c["age"] = float(c["age"]) + delta
		if float(c["age"]) > CASING_LIFE:
			_cas.remove_at(i)
			continue
		if not c["rest"]:
			var v: Vector3 = c["vel"]
			v.y -= 13.0 * delta
			var p: Vector3 = (c["pos"] as Vector3) + v * delta
			var spin: Vector3 = c["spin"]
			if spin.length() > 0.01:
				c["basis"] = ((c["basis"] as Basis).rotated(spin.normalized(), spin.length() * delta)).orthonormalized()
			var g := float(c["ground"]) + 0.005
			if p.y < g:
				p.y = g
				if absf(v.y) > 1.0 and int(c["bounces"]) < 3:
					if bool(c["loud"]):
						Sfx.play_at("casing", p, -14.0 - 4.0 * int(c["bounces"]), _rng.randf_range(0.9, 1.15))
					c["bounces"] = int(c["bounces"]) + 1
				v.y = -v.y * 0.32
				v.x *= 0.55
				v.z *= 0.55
				c["spin"] = spin * 0.5
				if absf(v.y) < 0.4 and Vector2(v.x, v.z).length() < 0.25:
					c["rest"] = true
					# lie on its side
					var flat := Basis(Vector3.FORWARD, PI * 0.5).rotated(Vector3.UP, _rng.randf() * TAU)
					c["basis"] = flat
					v = Vector3.ZERO
			c["vel"] = v
			c["pos"] = p
		i += 1
	var mm := _casings.multimesh
	mm.visible_instance_count = _cas.size()
	for k in _cas.size():
		var c: Dictionary = _cas[k]
		mm.set_instance_transform(k, Transform3D(c["basis"], c["pos"]))

## Test helper: live particle count per layer.
func live_counts() -> Dictionary:
	var out := {}
	for kind in _layers:
		out[kind] = (_layers[kind]["p"] as Array).size()
	out["casings"] = _cas.size()
	var lit := 0
	for l in _lights:
		if l.visible: lit += 1
	out["lights"] = lit
	return out
