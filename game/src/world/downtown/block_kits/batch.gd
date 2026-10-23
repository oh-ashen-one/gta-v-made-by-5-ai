extends RefCounted
## Static detail batcher for the downtown blocks piece (original work).
## Boxes and simple cylinders are merged into one ArrayMesh per region with
## one surface per material, so a whole block's street frontage (canopies,
## columns, signs, planters, railings) costs a handful of draw calls.

## Visually close materials share one surface (fewer draw calls per block).
const ALIAS := {"metal_white": "metal_light", "umbrella_white": "metal_light", "sign_dark": "metal_dark", "table": "metal_dark",
	"chair": "timber", "soil": "timber", "shrub_light": "shrub", "light_cool": "light_strip", "ad_panel": "light_strip",
	"bus_sign": "shutter_green", "mrt_red": "awning_red", "shelter_glass": "canopy_glass", "granite_light": "planter"}

var _tools := {}      # material key -> SurfaceTool
var _counts := {}     # material key -> vertex count
var parts := 0

func _tool(key: String) -> SurfaceTool:
	key = ALIAS.get(key, key)
	if not _tools.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = s
		_counts[key] = 0
	return _tools[key]

func _quad(s: SurfaceTool, key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv_scale: Vector2) -> void:
	# a b c d counter-clockwise seen from outside -> emit clockwise for Godot.
	var w := a.distance_to(b) * uv_scale.x
	var h := a.distance_to(d) * uv_scale.y
	var uvs := [Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0)]
	var p := [a, b, c, d]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for k in tri:
			s.set_normal(n)
			s.set_uv(uvs[k])
			s.add_vertex(p[k])
	_counts[ALIAS.get(key, key)] += 6

## Axis-aligned (in its own frame) box; xf places its centre.
func box(key: String, size: Vector3, xf: Transform3D, uv_scale := Vector2.ONE) -> void:
	var s := _tool(key)
	var h := size * 0.5
	var b := xf.basis
	var o := xf.origin
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var w := []
	for v in c:
		w.append(o + b * v)
	var faces := [
		[4, 5, 6, 7, Vector3(0, 0, 1)], [1, 0, 3, 2, Vector3(0, 0, -1)],
		[5, 1, 2, 6, Vector3(1, 0, 0)], [0, 4, 7, 3, Vector3(-1, 0, 0)],
		[7, 6, 2, 3, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)]]
	for f in faces:
		var n: Vector3 = (b * (f[4] as Vector3)).normalized()
		_quad(s, key, w[f[0]], w[f[1]], w[f[2]], w[f[3]], n, uv_scale)
	parts += 1

func box_at(key: String, size: Vector3, pos: Vector3, yaw: float = 0.0) -> void:
	box(key, size, Transform3D(Basis(Vector3.UP, yaw), pos))

## Vertical n-gon column centred at pos (base at pos.y).
func column(key: String, radius: float, height: float, pos: Vector3, sides: int = 8) -> void:
	var s := _tool(key)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := pos + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := pos + Vector3(cos(a1), 0, sin(a1)) * radius
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_quad(s, key, p1, p0, p0 + Vector3.UP * height, p1 + Vector3.UP * height, n, Vector2.ONE)
	parts += 1

## Flat quad facing +n (for sign faces); centre, right axis, up axis, size.
func plane(key: String, centre: Vector3, right: Vector3, up: Vector3, size: Vector2) -> void:
	var s := _tool(key)
	var r := right.normalized() * size.x * 0.5
	var u := up.normalized() * size.y * 0.5
	var n := right.cross(up).normalized()
	var a := centre - r - u
	var b := centre + r - u
	var c := centre + r + u
	var d := centre - r + u
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var p := [a, b, c, d]
	for tri in [[0, 2, 1], [0, 3, 2]]:
		for k in tri:
			s.set_normal(n)
			s.set_uv(uvs[k])
			s.add_vertex(p[k])
	_counts[ALIAS.get(key, key)] += 6
	parts += 1

## Builds one MeshInstance3D holding a surface per material key.
func commit(parent: Node3D, node_name: String, materials: Dictionary, vis_end: float = 0.0, shadows: bool = true) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in _tools:
		if int(_counts[key]) == 0:
			continue
		var s: SurfaceTool = _tools[key]
		s.generate_tangents()
		var arrays := s.commit_to_arrays()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials.get(key, null))
	if mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.set_meta("downtown_blocks", true)
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
