extends RefCounted
## Public-realm furniture shared by the landmark districts: railings, lamp
## standards, benches, bollards and planters. Repeated items are MultiMeshes;
## railings and planters merge into the caller's kit mesh.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")

static var _lamp_mesh: ArrayMesh
static var _bollard_mesh: ArrayMesh
static var _bench_mesh: ArrayMesh

## Waterfront railing between two points: posts every ~2 m, top rail, two
## intermediate rails. y of p0/p1 is the walk surface.
static func railing(kit: Kit, p0: Vector3, p1: Vector3, h: float = 1.15) -> void:
	var steel := Looks.get_mat("steel_dark")
	var d := p1 - p0
	var length := d.length()
	if length < 0.5:
		return
	var n := maxi(1, int(ceil(length / 2.0)))
	for i in n + 1:
		var p := p0 + d * (float(i) / n)
		kit.box(steel, p + Vector3(0, h * 0.5, 0), Vector3(0.07, h, 0.07))
	kit.beam(Looks.get_mat("steel_satin"), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), 0.09, 0.06)
	kit.beam(steel, p0 + Vector3(0, h * 0.62, 0), p1 + Vector3(0, h * 0.62, 0), 0.03, 0.03)
	kit.beam(steel, p0 + Vector3(0, h * 0.25, 0), p1 + Vector3(0, h * 0.25, 0), 0.03, 0.03)

## Glass balustrade (bridges, terraces): steel cap rail over a glass panel.
static func glass_rail(kit: Kit, p0: Vector3, p1: Vector3, h: float = 1.2) -> void:
	var d := p1 - p0
	if d.length() < 0.2:
		return
	var side := Vector3.UP.cross(d.normalized()).normalized() * 0.02
	kit.quad(Looks.get_mat("glass_clear"), p0 + Vector3(0, 0.08, 0), p1 + Vector3(0, 0.08, 0), p1 + Vector3(0, h - 0.06, 0), p0 + Vector3(0, h - 0.06, 0))
	kit.beam(Looks.get_mat("steel_satin"), p0 + Vector3(0, h, 0) + side, p1 + Vector3(0, h, 0) + side, 0.08, 0.06)
	kit.beam(Looks.get_mat("steel_dark"), p0 + Vector3(0, 0.05, 0), p1 + Vector3(0, 0.05, 0), 0.08, 0.1)

static func lamp_mesh() -> ArrayMesh:
	if _lamp_mesh != null:
		return _lamp_mesh
	var k := Kit.new()
	var steel := Looks.get_mat("steel_dark")
	k.box(Looks.get_mat("granite_dark"), Vector3(0, 0.2, 0), Vector3(0.5, 0.4, 0.5))
	k.cyl(steel, Vector3(0, 0.4, 0), 0.11, 0.07, 6.4, 8)
	k.beam(steel, Vector3(0, 6.6, 0), Vector3(0, 6.75, 1.1), 0.08, 0.08)
	k.box(steel, Vector3(0, 6.75, 1.25), Vector3(0.36, 0.16, 0.7))
	k.box(Looks.get_mat("light_strip"), Vector3(0, 6.66, 1.25), Vector3(0.3, 0.03, 0.6))
	_lamp_mesh = k.to_mesh()
	return _lamp_mesh

static func bollard_mesh() -> ArrayMesh:
	if _bollard_mesh != null:
		return _bollard_mesh
	var k := Kit.new()
	k.cyl(Looks.get_mat("bollard"), Vector3.ZERO, 0.11, 0.1, 0.9, 8)
	k.cyl(Looks.get_mat("steel_satin"), Vector3(0, 0.9, 0), 0.1, 0.06, 0.06, 8)
	_bollard_mesh = k.to_mesh()
	return _bollard_mesh

static func bench_mesh() -> ArrayMesh:
	if _bench_mesh != null:
		return _bench_mesh
	var k := Kit.new()
	var stone := Looks.get_mat("granite_light")
	var wood := Looks.get_mat("timber")
	k.box(stone, Vector3(-0.85, 0.22, 0), Vector3(0.18, 0.44, 0.5))
	k.box(stone, Vector3(0.85, 0.22, 0), Vector3(0.18, 0.44, 0.5))
	for i in 4:
		k.box(wood, Vector3(0, 0.47, -0.18 + i * 0.12), Vector3(2.0, 0.05, 0.09))
	_bench_mesh = k.to_mesh()
	return _bench_mesh

static func lamps(parent: Node3D, node_name: String, xforms: Array) -> void:
	Kit.multimesh(parent, node_name, lamp_mesh(), xforms, false, 320.0)

static func bollards(parent: Node3D, node_name: String, pts: Array) -> void:
	var xs := []
	for p in pts:
		xs.append(Kit.xf(p))
	Kit.multimesh(parent, node_name, bollard_mesh(), xs, false, 200.0)

static func benches(parent: Node3D, node_name: String, xforms: Array) -> void:
	Kit.multimesh(parent, node_name, bench_mesh(), xforms, false, 220.0)

## Granite planter: soil, low planted ground cover and authored ferns
## (queued as MultiMesh transforms; call flush_ferns() once per module).
static var _ferns: Array = []
static func planter(kit: Kit, c: Vector3, size: Vector2, h: float = 0.55, ferns: bool = true) -> void:
	kit.box(Looks.get_mat("granite_light"), c + Vector3(0, h * 0.5, 0), Vector3(size.x, h, size.y))
	kit.box(Looks.get_mat("soil_bed"), c + Vector3(0, h + 0.01, 0), Vector3(size.x - 0.3, 0.04, size.y - 0.3))
	kit.box(Looks.get_mat("planting"), c + Vector3(0, h + 0.06, 0), Vector3(size.x - 0.5, 0.1, size.y - 0.5))
	if not ferns:
		return
	var n := clampi(int(size.x * size.y / 2.2), 3, 20)
	var h1 := hash(c)
	for i in n:
		var u := fposmod(sin(float(h1 % 997) + i * 12.9898) * 43758.5453, 1.0)
		var v := fposmod(sin(float(h1 % 991) + i * 78.233) * 12543.531, 1.0)
		var p := c + Vector3((u - 0.5) * (size.x - 1.0), h + 0.1, (v - 0.5) * (size.y - 1.0))
		_ferns.append(Kit.xf(p, u * TAU, Vector3.ONE * (0.55 + 0.35 * v)))

static func flush_ferns(parent: Node3D, node_name: String) -> void:
	glb_multimesh(parent, node_name, "fern.glb", _ferns, false, 260.0)
	_ferns = []

## MultiMesh copies of an authored GLB (every mesh part keeps its own node
## transform and materials, with LandmarkLooks upgrades applied).
static var _glb_parts := {}
static func glb_multimesh(parent: Node3D, node_name: String, file: String, xforms: Array, shadows: bool = false, vis_end: float = 0.0) -> void:
	if xforms.is_empty():
		return
	if not _glb_parts.has(file):
		var parts := []
		var path := "res://assets/authored/" + file
		if ResourceLoader.exists(path):
			var inst: Node = (load(path) as PackedScene).instantiate()
			LandmarkLooks.apply(inst)
			var stack: Array = [[inst, Transform3D.IDENTITY]]
			while not stack.is_empty():
				var item: Array = stack.pop_back()
				var node: Node = item[0]
				var xf: Transform3D = item[1]
				if node is Node3D:
					xf = xf * (node as Node3D).transform
				if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
					var mi := node as MeshInstance3D
					var mesh := mi.mesh.duplicate() as Mesh
					for si in mesh.get_surface_count():
						var ov := mi.get_surface_override_material(si)
						if ov != null:
							mesh.surface_set_material(si, ov)
					parts.append([mesh, xf])
				for ch in node.get_children():
					stack.append([ch, xf])
			inst.free()
		_glb_parts[file] = parts
	var k := 0
	for part: Array in _glb_parts[file]:
		var list := []
		for x: Transform3D in xforms:
			list.append(x * (part[1] as Transform3D))
		Kit.multimesh(parent, "%s_%d" % [node_name, k], part[0], list, shadows, vis_end)
		k += 1

## Low-poly palm (trunk + frond fan) for decks and promenades.
static var _palm_mesh: ArrayMesh
static func palm_mesh() -> ArrayMesh:
	if _palm_mesh != null:
		return _palm_mesh
	var k := Kit.new()
	var bark := Looks.get_mat("steel_bronze")
	var leaf := Looks.get_mat("hedge")
	var pts := PackedVector3Array()
	for i in 7:
		var t := i / 6.0
		pts.append(Vector3(0.35 * t * t, 7.0 * t, 0.0))
	k.tube(bark, pts, 0.22, 6)
	var top := pts[pts.size() - 1]
	for f in 9:
		var a := TAU * f / 9.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var mid := top + dir * 1.9 + Vector3(0, 0.45, 0)
		var tip := top + dir * 3.6 - Vector3(0, 0.9, 0)
		k.quad(leaf, top - side * 0.15, top + side * 0.15, mid + side * 0.55, mid - side * 0.55)
		k.quad(leaf, mid - side * 0.55, mid + side * 0.55, tip + side * 0.08, tip - side * 0.08)
	_palm_mesh = k.to_mesh()
	for i in _palm_mesh.get_surface_count():
		var m := _palm_mesh.surface_get_material(i)
		if m == leaf:
			var dbl := (leaf as StandardMaterial3D).duplicate() as StandardMaterial3D
			dbl.cull_mode = BaseMaterial3D.CULL_DISABLED
			_palm_mesh.surface_set_material(i, dbl)
	return _palm_mesh
