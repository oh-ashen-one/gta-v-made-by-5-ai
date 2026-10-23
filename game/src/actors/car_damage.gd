extends Node3D
## Vehicle body and damage layer (opus55 driving-p). One child of every Car with
## a provider body; created by CarFx.
##
## - Swaps the provider material for car_body.gdshader: clean clear-coat paint
##   (proxy-smoothed reflections), mirror glass, tail lamps that glow and flare
##   when braking, and an optional per-car paint colour for civilian sedans.
## - Dents: up to four per car, stored in car space and pushed into the shader
##   as model-space instance uniforms, so the body visibly crumples where it was
##   hit (with scraped paint, cracked glass and dead lamps near the dent).
## - Debris: small rigid fragments (body panel, black trim, lamp lens, glass)
##   from one shared pool that stay on the road afterwards.
## - Glass: a burst of glinting shards plus a persistent glittering scatter
##   decal on the asphalt.
## - Procedural crash crunch and glass tinkle sounds (registered in Sfx).
## Nothing here is loaded from disk: every mesh, texture and sound is generated.

const BodyShader := preload("res://assets/authored/shaders/car_body.gdshader")
const MAX_DENTS := 4
const MAX_DENT_DEPTH := 0.42
const DEBRIS_LAYER := 32
const DEBRIS_POOL := 64
const SCATTER_MAX := 18
## Civilian sedan paint (Singapore traffic is mostly white, silver, grey and black).
const SEDAN_PAINTS := [
	Color(0.86, 0.86, 0.84), Color(0.60, 0.61, 0.63), Color(0.035, 0.036, 0.04),
	Color(0.20, 0.21, 0.23), Color(0.06, 0.11, 0.25), Color(0.42, 0.035, 0.03),
	Color(0.60, 0.53, 0.40), Color(0.84, 0.85, 0.86), Color(0.12, 0.17, 0.15),
]

static var _mat_cache: Dictionary = {}
static var _debris_pool: Array[RigidBody3D] = []
static var _debris_next := 0
static var _debris_meshes: Array = []
static var _debris_shapes: Array = []
static var _debris_mats: Array = []
static var _scatter: Array[Decal] = []
static var _scatter_tex: Texture2D
static var _scatter_emit: Texture2D
static var _sounds_ready := false
static var total_debris := 0

var car: Car
var _root: Node3D
var _aabb := AABB()
var _meshes: Array[MeshInstance3D] = []
var _model_from_car: Array[Transform3D] = []
var _dents: Array[Dictionary] = []
var _dent_next := 0
var _glass_fx: GPUParticles3D
var _state := Vector4(0.0, 0.0, 0.0, 0.0)
var paint := Color(0.0, 0.0, 0.0, 0.0)
## QA readback
var dents_applied := 0
var debris_spawned := 0
var glass_bursts := 0

func setup(owner_car: Car, root: Node3D, aabb: AABB, base_xform: Transform3D) -> void:
	car = owner_car
	name = "CarDamage"
	_root = root
	_aabb = aabb
	if car.kind == "sedan":
		paint = SEDAN_PAINTS[absi(int(car.get_instance_id() / 7)) % SEDAN_PAINTS.size()]
		paint.a = 1.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null: continue
		# Wave-M integration: only meshes that now carry the body shader on every
		# surface take its instance uniforms. A promoted lane car's lamp/driver
		# parts (material_override, no surface material) logged 'Parameter
		# "material" is null' from material_get_instance_shader_parameters.
		if not _swap_material(m): continue
		# Model -> car (rest pose) transform of this mesh.
		var chain := Transform3D.IDENTITY
		var n: Node = m
		while n != null and n != root:
			if n is Node3D: chain = (n as Node3D).transform * chain
			n = n.get_parent()
		var t := base_xform * chain
		_meshes.append(m)
		_model_from_car.append(t.affine_inverse())
		var c := aabb.get_center()
		var hx := maxf(aabb.size.x * 0.5, 0.1)
		var hz := maxf(aabb.size.z * 0.5, 0.1)
		var h := maxf(aabb.size.y, 0.1)
		var b := t.basis
		m.set_instance_shader_parameter("car_row_x", Vector4(b.x.x / hx, b.y.x / hx, b.z.x / hx, (t.origin.x - c.x) / hx))
		m.set_instance_shader_parameter("car_row_y", Vector4(b.x.y / h, b.y.y / h, b.z.y / h, (t.origin.y - aabb.position.y) / h))
		m.set_instance_shader_parameter("car_row_z", Vector4(b.x.z / hz, b.y.z / hz, b.z.z / hz, (t.origin.z - c.z) / hz))
		m.set_instance_shader_parameter("paint_color", paint)
	_push_state()

func _swap_material(m: MeshInstance3D) -> bool:
	# True when the mesh takes the body shader and no surface is material-less.
	var any_swapped := false
	var has_null := m.material_override != null
	for i in m.mesh.get_surface_count():
		var src: Material = m.get_surface_override_material(i)
		if src == null: src = m.mesh.surface_get_material(i)
		if src == null: has_null = true
		if not src is StandardMaterial3D: continue
		any_swapped = true
		var std := src as StandardMaterial3D
		var key := "%d|%s" % [std.get_instance_id(), car.kind]
		var sm: ShaderMaterial = _mat_cache.get(key)
		if sm == null:
			sm = ShaderMaterial.new()
			sm.shader = BodyShader
			sm.set_shader_parameter("albedo_tex", std.albedo_texture)
			var orm: Texture2D = std.roughness_texture if std.roughness_texture != null else std.metallic_texture
			if orm != null: sm.set_shader_parameter("orm_tex", orm)
			sm.set_shader_parameter("albedo_tint", std.albedo_color)
			sm.set_shader_parameter("paint_kind", 1.0 if car.kind == "coupe" else 0.0)
			sm.set_shader_parameter("lamp_glow", 0.0 if car.kind == "coupe" else 1.0)
			sm.set_shader_parameter("badge_mask", 1.0 if car.kind == "sedan" or car.kind == "police" else 0.0)
			_mat_cache[key] = sm
		m.set_surface_override_material(i, sm)
	return any_swapped and not has_null

## Brake (0..1) and running lamps (0..1) for the shader lamps.
func set_lamps(brake: float, lights: float) -> void:
	var s := Vector4(brake, lights, _state.z, paint.a)
	if s.is_equal_approx(_state): return
	_state = s
	_push_state()

func _push_state() -> void:
	_state.w = paint.a
	for m in _meshes:
		if is_instance_valid(m): m.set_instance_shader_parameter("car_state", Color(_state.x, _state.y, _state.z, _state.w))

## Crumple the body at a world contact. `push` points into the body (the
## contact normal seen from this car's side); energy 0..1.
func add_dent(world_point: Vector3, push: Vector3, energy: float) -> void:
	if _meshes.is_empty(): return
	var inv := car.global_transform.affine_inverse()
	var p := inv * world_point
	var d := (inv.basis * push)
	d.y = 0.0
	if d.length_squared() < 0.0001: return
	d = d.normalized()
	# Nose and tail hits buckle the bonnet/boot down as well as in.
	if absf(d.z) > 0.6: d = (d + Vector3.DOWN * 0.45).normalized()
	p.x = clampf(p.x, _aabb.position.x, _aabb.end.x)
	p.z = clampf(p.z, _aabb.position.z, _aabb.end.z)
	p.y = clampf(p.y, _aabb.position.y + _aabb.size.y * 0.28, _aabb.position.y + _aabb.size.y * 0.78)
	var radius := lerpf(0.5, 1.15, energy)
	var depth := lerpf(0.06, 0.32, energy)
	# Hitting the same corner again deepens that dent.
	var merged := false
	for dent in _dents:
		if (dent["p"] as Vector3).distance_to(p) < float(dent["r"]) * 0.6:
			dent["depth"] = minf(MAX_DENT_DEPTH, float(dent["depth"]) + depth * 0.7)
			dent["r"] = minf(1.3, maxf(float(dent["r"]), radius) + 0.08)
			dent["d"] = ((dent["d"] as Vector3) + d).normalized()
			merged = true
			break
	if not merged:
		var dent := {"p": p, "d": d, "r": radius, "depth": depth}
		if _dents.size() < MAX_DENTS:
			_dents.append(dent)
		else:
			_dents[_dent_next] = dent
			_dent_next = (_dent_next + 1) % MAX_DENTS
	dents_applied += 1
	_state.z = minf(1.0, _state.z + energy * 0.35)
	_push_dents()
	_push_state()

func _push_dents() -> void:
	for k in _meshes.size():
		var m := _meshes[k]
		if not is_instance_valid(m): continue
		var to_model := _model_from_car[k]
		var scale := (to_model.basis.get_scale().x + to_model.basis.get_scale().y + to_model.basis.get_scale().z) / 3.0
		for i in MAX_DENTS:
			var c := Vector4.ZERO
			var dd := Vector4.ZERO
			if i < _dents.size():
				var dent: Dictionary = _dents[i]
				var pm: Vector3 = to_model * (dent["p"] as Vector3)
				var dm: Vector3 = to_model.basis * ((dent["d"] as Vector3) * float(dent["depth"]))
				c = Vector4(pm.x, pm.y, pm.z, float(dent["r"]) * scale)
				var dl := dm.length()
				if dl > 0.0:
					dm /= dl
				dd = Vector4(dm.x, dm.y, dm.z, dl)
			m.set_instance_shader_parameter("dent%d" % i, c)
			m.set_instance_shader_parameter("dent_dir%d" % i, dd)

func dent_count() -> int:
	return _dents.size()

# ---------------------------------------------------------------- debris
static func _build_debris_kit() -> void:
	if not _debris_meshes.is_empty(): return
	var sizes: Array[Vector3] = [Vector3(0.17, 0.01, 0.11), Vector3(0.30, 0.035, 0.06), Vector3(0.08, 0.025, 0.06), Vector3(0.045, 0.01, 0.035), Vector3(0.12, 0.02, 0.08)]
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.05, 0.05, 0.055)
	plastic.roughness = 0.6
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.55, 0.03, 0.02)
	lens.roughness = 0.12
	lens.emission_enabled = true
	lens.emission = Color(0.6, 0.02, 0.01)
	lens.emission_energy_multiplier = 0.4
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.30, 0.36, 0.38)
	glass.roughness = 0.04
	glass.metallic_specular = 1.0
	var panel := StandardMaterial3D.new()
	panel.albedo_color = Color(0.7, 0.7, 0.7)
	panel.roughness = 0.3
	panel.clearcoat_enabled = true
	panel.clearcoat = 1.0
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.45, 0.46, 0.47)
	metal.metallic = 0.9
	metal.roughness = 0.4
	_debris_mats = [panel, plastic, lens, glass, metal]
	for s in sizes:
		var bm := BoxMesh.new()
		bm.size = s
		_debris_meshes.append(bm)
		var sh := BoxShape3D.new()
		sh.size = Vector3(maxf(s.x, 0.04), maxf(s.y, 0.03), maxf(s.z, 0.04))
		_debris_shapes.append(sh)

func _take_debris() -> RigidBody3D:
	_build_debris_kit()
	var tree_root := car.get_tree().current_scene
	if _debris_pool.size() < DEBRIS_POOL:
		var rb := RigidBody3D.new()
		rb.collision_layer = DEBRIS_LAYER
		rb.collision_mask = 1
		rb.mass = 0.6
		rb.continuous_cd = false
		rb.can_sleep = true
		var pmat := PhysicsMaterial.new()
		pmat.bounce = 0.22
		pmat.friction = 0.85
		rb.physics_material_override = pmat
		rb.linear_damp = 0.15
		rb.angular_damp = 0.6
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.visibility_range_end = 90.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		rb.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		rb.add_child(cs)
		tree_root.add_child(rb)
		rb.top_level = true
		_debris_pool.append(rb)
		return rb
	var reuse := _debris_pool[_debris_next % _debris_pool.size()]
	_debris_next += 1
	if not is_instance_valid(reuse):
		_debris_pool.clear()
		return _take_debris()
	return reuse

## Fragments thrown from a contact; energy 0..1.
func spawn_debris(at: Vector3, normal: Vector3, energy: float, car_velocity: Vector3) -> void:
	if car == null or not car.is_inside_tree(): return
	var count := int(round(lerpf(2.0, 12.0, energy)))
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var tangent := Vector3.UP.cross(normal).normalized()
	for i in count:
		var rb := _take_debris()
		var kind := rng.randi_range(0, _debris_meshes.size() - 1)
		if i < 2: kind = 2 if energy > 0.4 and i == 0 else 1
		var mi := rb.get_node("Mesh") as MeshInstance3D
		mi.mesh = _debris_meshes[kind]
		var mat: StandardMaterial3D = _debris_mats[kind]
		if kind == 0:
			# Panel shards carry this car's paint.
			var pc := paint if paint.a > 0.0 else (Color(0.55, 0.06, 0.06) if car.kind == "coupe" else Color(0.82, 0.83, 0.84))
			var key := "panel_%s" % pc.to_html()
			var pm: StandardMaterial3D = _mat_cache.get(key)
			if pm == null:
				pm = mat.duplicate()
				pm.albedo_color = Color(pc.r, pc.g, pc.b)
				_mat_cache[key] = pm
			mat = pm
		mi.material_override = mat
		(rb.get_node("Shape") as CollisionShape3D).shape = _debris_shapes[kind]
		rb.freeze = false
		rb.sleeping = false
		rb.visible = true
		var spread := tangent * rng.randf_range(-1.0, 1.0) * 0.6
		rb.global_transform = Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)), at + normal * 0.25 + spread + Vector3.UP * rng.randf_range(0.2, 0.7))
		var throw := normal * rng.randf_range(1.0, 4.5) * (0.5 + energy) + tangent * rng.randf_range(-3.0, 3.0) * energy + Vector3.UP * rng.randf_range(1.0, 4.0) * (0.4 + energy)
		rb.linear_velocity = car_velocity * rng.randf_range(0.35, 0.75) + throw
		rb.angular_velocity = Vector3(rng.randf_range(-14, 14), rng.randf_range(-14, 14), rng.randf_range(-14, 14))
		debris_spawned += 1
		total_debris += 1

# ---------------------------------------------------------------- glass
func glass_burst(at: Vector3, normal: Vector3, energy: float, car_velocity: Vector3) -> void:
	if car == null or not car.is_inside_tree(): return
	glass_bursts += 1
	if _glass_fx == null:
		_glass_fx = GPUParticles3D.new()
		_glass_fx.amount = 140
		_glass_fx.lifetime = 1.0
		_glass_fx.one_shot = true
		_glass_fx.explosiveness = 0.92
		_glass_fx.local_coords = false
		_glass_fx.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 10, 24))
		_glass_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 1.0, 0.0)
		pm.spread = 75.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 5.5
		pm.gravity = Vector3(0.0, -16.0, 0.0)
		pm.angular_velocity_min = -600.0
		pm.angular_velocity_max = 600.0
		pm.scale_min = 0.4
		pm.scale_max = 1.2
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.35
		_glass_fx.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.016, 0.012)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_color = Color(0.85, 0.92, 1.0, 0.8)
		quad.material = m
		_glass_fx.draw_pass_1 = quad
		car.get_tree().current_scene.add_child(_glass_fx)
		_glass_fx.top_level = true
	_glass_fx.global_position = at + Vector3.UP * 0.5
	var ppm := _glass_fx.process_material as ParticleProcessMaterial
	ppm.direction = (normal * 0.7 + Vector3.UP).normalized()
	ppm.initial_velocity_max = 3.0 + energy * 4.0
	_glass_fx.amount_ratio = clampf(0.35 + energy * 0.65, 0.0, 1.0)
	_glass_fx.restart()
	_glass_fx.emitting = true
	_scatter_at(at + car_velocity.normalized() * 0.8 * energy, energy)

static func _make_scatter_textures() -> void:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var emit := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	emit.fill(Color(0, 0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	for i in 900:
		var a := rng.randf() * TAU
		var r := pow(rng.randf(), 0.7) * size * 0.47
		var x := int(size * 0.5 + cos(a) * r)
		var y := int(size * 0.5 + sin(a) * r * 0.8)
		if x < 1 or y < 1 or x >= size - 1 or y >= size - 1: continue
		var bright := rng.randf_range(0.55, 1.0)
		img.set_pixel(x, y, Color(0.80, 0.86, 0.88, bright))
		if rng.randf() < 0.4: img.set_pixel(x + 1, y, Color(0.75, 0.80, 0.82, bright * 0.7))
		if rng.randf() < 0.22: emit.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0) * bright)
	_scatter_tex = ImageTexture.create_from_image(img)
	_scatter_emit = ImageTexture.create_from_image(emit)

func _scatter_at(at: Vector3, energy: float) -> void:
	if _scatter_tex == null: _make_scatter_textures()
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at - Vector3.UP * 3.0)
	q.collision_mask = 1
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	var ground := (hit["position"] as Vector3) if not hit.is_empty() else Vector3(at.x, car.global_position.y, at.z)
	var decal: Decal
	if _scatter.size() < SCATTER_MAX:
		decal = Decal.new()
		decal.texture_albedo = _scatter_tex
		decal.texture_emission = _scatter_emit
		decal.emission_energy = 0.35
		decal.upper_fade = 0.3
		decal.lower_fade = 0.3
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 60.0
		decal.distance_fade_length = 15.0
		decal.cull_mask = 1
		car.get_tree().current_scene.add_child(decal)
		decal.top_level = true
		_scatter.append(decal)
	else:
		decal = _scatter.pop_front()
		if not is_instance_valid(decal):
			_scatter.clear()
			return
		_scatter.append(decal)
	var s := lerpf(1.4, 3.2, energy)
	decal.size = Vector3(s, 0.6, s)
	decal.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU), ground + Vector3.UP * 0.05)

# ---------------------------------------------------------------- audio
static func ensure_sounds() -> void:
	if _sounds_ready: return
	_sounds_ready = true
	var sfx: Node = Engine.get_main_loop().root.get_node_or_null("Sfx") if Engine.get_main_loop() is SceneTree else null
	if sfx == null or not sfx.has_method("_wav"): return
	var rate := 22050
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	# Crunch: a low thump, buckling-metal partials and a gritty noise tail.
	var n := int(rate * 0.75)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = low * 0.82 + noise * 0.18
		var grit := noise * (0.5 + 0.5 * sin(TAU * 31.0 * t + sin(TAU * 7.0 * t) * 3.0))
		var thump := sin(TAU * (62.0 - t * 30.0) * t) * exp(-t * 9.0) * 0.9
		var metal := (sin(TAU * 187.0 * t) * 0.5 + sin(TAU * 412.0 * t + 1.3) * 0.35 + sin(TAU * 733.0 * t + 0.4) * 0.25) * exp(-t * 7.5)
		s[i] = tanh((thump + metal * 0.55 + low * 1.4 * exp(-t * 6.0) + grit * 0.35 * exp(-t * 14.0)) * 1.3) * 0.9
	sfx._bank["car_crash"] = sfx._wav(s)
	# Glass: a short shatter burst and a scatter of high tinkles.
	n = int(rate * 0.9)
	var g := PackedFloat32Array()
	g.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + noise - prev)
		prev = noise
		g[i] = hp * exp(-t * 22.0) * 0.55
	for k in 22:
		var onset := rng.randf_range(0.0, 0.55)
		var f := rng.randf_range(2600.0, 7200.0)
		var amp := rng.randf_range(0.08, 0.22)
		var start := int(onset * rate)
		for i in range(start, mini(n, start + int(rate * 0.18))):
			var t := float(i - start) / rate
			g[i] += sin(TAU * f * t) * exp(-t * 38.0) * amp
	for i in n: g[i] = tanh(g[i] * 1.2) * 0.85
	sfx._bank["glass_break"] = sfx._wav(g)
