class_name SkylineCity
extends RefCounted
## Layered procedural background city (wave A, Opus 5.5).
##
## The wave-5 far shore was four repeated skyline GLBs on a grid with white
## crowns, and the sides were 48 individual nodes. From the helicopter it read
## as a sparse prototype rather than a city. This builds six tower archetypes
## (setback office, octagonal tower, round tower, residential slab, chamfered
## tower with fin, low podium block) as procedural meshes and places a few
## hundred instances in depth layers: a low waterfront edge, mid-rise bands,
## a tall CBD cluster on either side of Marina Bay Sands, residential estates
## on the flanks and a distant horizon band. All instances share one facade
## shader (floor bands, mullions, punched windows, weathered roofs) driven by
## per-instance custom data, so the whole background costs six draw calls and
## casts no shadows. Clear zones keep sky behind the Marina Bay Sands SkyPark
## and behind the Singapore Flyer wheel.

const SHADER := "res://assets/authored/shaders/skyline_facade.gdshader"

var _rng := RandomNumberGenerator.new()
var _groups: Array = []          # per archetype: Array of [Transform3D, Color]
var _clear: Array[Dictionary] = []  # {rect: Rect2, max_h: float}
var placed := 0
## material id -> tower count (self-test reads it)
var materials_used := {}
## towers whose footprint overlaps bay water (must stay 0)
var over_water := 0
var _last_kind := -1
var _last_material := -1
## Facade systems each archetype may wear (ids from skyline_facade.gdshader):
## 0 dark blue-green glass, 1 limestone, 2 silver-blue glass, 3 bronze glass,
## 4 white aluminium ribbon, 5 painted residential, 6 finned grey-green glass.
const MATERIALS_BY_KIND := [[0, 1, 2, 3, 6], [0, 2, 6, 1], [0, 2, 3], [5, 5, 1, 4], [0, 6, 4, 2], [1, 4, 3]]

func _init(seed_value: int = 7310) -> void:
	_rng.seed = seed_value
	for i in 6:
		_groups.append([])

## Keep anything taller than max_h out of rect (x, z plane).
func clear_zone(rect: Rect2, max_h: float) -> void:
	_clear.append({"rect": rect, "max_h": max_h})

func _allowed_height(x: float, z: float, footprint: float) -> float:
	var h := INF
	var probe := Rect2(x - footprint * 0.5, z - footprint * 0.5, footprint, footprint)
	for c in _clear:
		if (c["rect"] as Rect2).intersects(probe):
			h = minf(h, float(c["max_h"]))
	return h

## Place one tower. kind: 0 setback, 1 octagon, 2 round, 3 slab, 4 fin, 5 podium.
## material: facade system id in skyline_facade.gdshader (0..6), -1 = pick.
func add(kind: int, pos: Vector3, width: float, height: float, depth_ratio: float = 1.0, yaw: float = 0.0, material: int = -1) -> bool:
	var cap := _allowed_height(pos.x, pos.z, width * maxf(1.0, depth_ratio))
	if cap < 12.0:
		return false
	# Round 2: nothing stands in the bay. The critic found flank towers
	# floating over open water at the left bank.
	if _over_water(pos, width * maxf(1.0, depth_ratio)):
		return false
	height = minf(height, cap)
	if material < 0:
		material = _pick_material(kind)

	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(width, height, width * depth_ratio))
	var custom := Color((float(material) + 0.5) / 8.0, _rng.randf(), _rng.randf_range(0.35, 0.75), _rng.randf())
	_groups[kind].append([Transform3D(basis, pos), custom])
	materials_used[material] = int(materials_used.get(material, 0)) + 1
	placed += 1
	return true

## Bay water (see WorldBuilder._waterfront_edge): x -800..800, z -1028..-328,
## minus the far-shore land that starts at z = -628.
static func _over_water(pos: Vector3, footprint: float) -> bool:
	var r := footprint * 0.5 + 6.0
	return absf(pos.x) - r < 800.0 and pos.z - r < -328.0 and pos.z + r > -628.0

## Material per archetype, never the same archetype + material as the
## previous tower (neighbours along a row are placed consecutively).
func _pick_material(kind: int) -> int:
	var options: Array = MATERIALS_BY_KIND[kind]
	var m: int = options[_rng.randi() % options.size()]
	var tries := 0
	while kind == _last_kind and m == _last_material and tries < 8:
		m = options[_rng.randi() % options.size()]
		tries += 1
	if kind != 5:
		_last_kind = kind
		_last_material = m
	return m

func _pick_from(kind: int, options: Array) -> int:
	var m: int = options[_rng.randi() % options.size()]
	var tries := 0
	while m == _last_material and tries < 8:
		m = options[_rng.randi() % options.size()]
		tries += 1
	_last_kind = kind
	_last_material = m
	return m

## A random tower whose archetype and proportions suit its height band.
func add_random(pos: Vector3, height: float, residential: bool = false) -> void:
	var kind: int = 3 if residential else [0, 1, 2, 4, 0, 3][_rng.randi() % 6]
	if kind == _last_kind and not residential:
		kind = [0, 1, 2, 4][(_rng.randi() % 3 + [0, 1, 2, 4].find(kind) + 1) % 4]
	var width := _rng.randf_range(22.0, 34.0)
	var depth := 1.0
	if kind == 3:
		width = _rng.randf_range(34.0, 52.0)
		depth = _rng.randf_range(0.30, 0.42)
	elif kind == 2:
		width = _rng.randf_range(24.0, 32.0)
	var yaw := _rng.randf_range(-0.25, 0.25) + (PI * 0.5 if _rng.randf() < 0.3 else 0.0)
	# Tall CBD towers alternate dark glass and light stone first, so the
	# cluster has real value contrast (SG-03), then the other systems.
	var mat := -1
	if height > 140.0 and kind != 3:
		mat = _pick_from(kind, [0, 1, 0, 3, 1, 2, 6])
	if add(kind, pos, width, height, depth, yaw, mat):
		# Every tower over 55 m stands on a podium; it fills the street wall
		# between towers and gives each a readable base.
		if height > 55.0:
			add(5, pos + Vector3(_rng.randf_range(-4, 4), 0.0, _rng.randf_range(-4, 4)), width * 1.4, _rng.randf_range(9.0, 16.0), _rng.randf_range(0.7, 1.0), yaw, [1, 4, 3][_rng.randi() % 3])

func build(parent: Node3D) -> void:
	var shader: Shader = load(SHADER)
	var meshes := [_setback_mesh(), _prism_mesh(8, 0.5, 0.94, true), _prism_mesh(18, 0.5, 0.96, false), _slab_mesh(), _fin_mesh(), _box_mesh(0.0, 1.0, 0.5, 0.5)]
	for kind in 6:
		var list: Array = _groups[kind]
		if list.is_empty():
			continue
		for item in list:
			var xf: Transform3D = item[0]
			if _over_water(xf.origin, xf.basis.x.length()):
				over_water += 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_custom_data(i, list[i][1])
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("use_instance_custom", true)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "SkylineCity_%d" % kind
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if "--sightline-probe" in OS.get_cmdline_user_args():
			var xforms: Array = []
			for item in list:
				xforms.append(item[0])
			mmi.set_meta("probe_xforms", xforms)
		parent.add_child(mmi)

# ------------------------------------------------------------- mesh archetypes
# Unit footprint (about 1 x 1), unit height; instance scale sets real size.

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	# Godot front faces are clockwise: emit a-c-b / a-d-c.
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)

static func _add_prism(st: SurfaceTool, sides: int, r0: float, r1: float, y0: float, y1: float, phase: float, sx: float = 1.0, sz: float = 1.0, off: Vector3 = Vector3.ZERO) -> void:
	for i in sides:
		var a0 := TAU * i / sides + phase
		var a1 := TAU * (i + 1) / sides + phase
		var p00 := off + Vector3(cos(a0) * r0 * sx, y0, sin(a0) * r0 * sz)
		var p10 := off + Vector3(cos(a1) * r0 * sx, y0, sin(a1) * r0 * sz)
		var p01 := off + Vector3(cos(a0) * r1 * sx, y1, sin(a0) * r1 * sz)
		var p11 := off + Vector3(cos(a1) * r1 * sx, y1, sin(a1) * r1 * sz)
		_quad(st, p00, p01, p11, p10)
	# top cap (fan)
	var c := off + Vector3(0.0, y1, 0.0)
	for i in sides:
		var a0 := TAU * i / sides + phase
		var a1 := TAU * (i + 1) / sides + phase
		st.set_normal(Vector3.UP)
		st.add_vertex(c)
		st.add_vertex(off + Vector3(cos(a0) * r1 * sx, y1, sin(a0) * r1 * sz))
		st.add_vertex(off + Vector3(cos(a1) * r1 * sx, y1, sin(a1) * r1 * sz))

static func _box_mesh(y0: float, y1: float, hx: float, hz: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(st, 4, sqrt(2.0), sqrt(2.0), y0, y1, PI * 0.25, hx, hz)
	return st.commit()

static func _setback_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := sqrt(2.0)
	_add_prism(st, 4, k, k, 0.0, 0.62, PI * 0.25, 0.5, 0.5)
	_add_prism(st, 4, k, k, 0.62, 0.86, PI * 0.25, 0.41, 0.43)
	_add_prism(st, 4, k, k, 0.86, 0.97, PI * 0.25, 0.30, 0.33)
	_add_prism(st, 4, k, k, 0.97, 1.0, PI * 0.25, 0.16, 0.20, Vector3(0.04, 0, 0))
	return st.commit()

static func _prism_mesh(sides: int, r: float, body: float, crown: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_prism(st, sides, r, r * 0.97, 0.0, body, PI / sides)
	if crown:
		_add_prism(st, sides, r * 0.97, r * 0.55, body, 1.0, PI / sides)
	else:
		_add_prism(st, sides, r * 0.86, r * 0.86, body, 1.0, PI / sides)
	return st.commit()

static func _slab_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := sqrt(2.0)
	_add_prism(st, 4, k, k, 0.0, 0.96, PI * 0.25, 0.5, 0.5)
	# lift-core / water-tank housings on the roof
	_add_prism(st, 4, k, k, 0.96, 1.0, PI * 0.25, 0.07, 0.3, Vector3(-0.25, 0, 0))
	_add_prism(st, 4, k, k, 0.96, 1.0, PI * 0.25, 0.07, 0.3, Vector3(0.22, 0, 0))
	return st.commit()

static func _fin_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# chamfered octagon body (long and short sides)
	var pts: Array[Vector2] = [Vector2(-0.5, -0.32), Vector2(-0.32, -0.5), Vector2(0.32, -0.5), Vector2(0.5, -0.32),
		Vector2(0.5, 0.32), Vector2(0.32, 0.5), Vector2(-0.32, 0.5), Vector2(-0.5, 0.32)]
	var top := 0.9
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		_quad(st, Vector3(a.x, 0, a.y), Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, 0, b.y))
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, top, 0)); st.add_vertex(Vector3(a.x, top, a.y)); st.add_vertex(Vector3(b.x, top, b.y))
	# raked crown and a blade fin rising past the roof
	var k := sqrt(2.0)
	_add_prism(st, 4, k, k * 0.6, top, 0.97, PI * 0.25, 0.36, 0.36)
	_add_prism(st, 4, k, k, 0.0, 1.0, PI * 0.25, 0.03, 0.22, Vector3(0.47, 0, 0))
	return st.commit()
