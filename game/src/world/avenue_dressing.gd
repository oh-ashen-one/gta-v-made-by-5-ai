class_name AvenueDressing
extends Node3D
## Avenue trees and kerbside clutter (street-life, Opus wave A).
##
## Critic 5: "Rain trees line the avenues, but there is no overhanging canopy
## and nothing shades the street the way the concepts do." Wave 5 planted the
## north-south avenues only, 14 m from the centreline. This adds a rain-tree
## row on every avenue, trunks 9 m from the centreline on the pavement edge,
## so the crowns reach over the kerb lane, batched as one MultiMesh per tree
## mesh with trunk-only collision. Spots that would put a trunk in a building,
## a junction mouth, the opening five-foot way or the kerbside furniture are
## skipped by an explicit rule or a physics overlap test.

const TRUNK_OFFSET := 8.85
const SPACING := 21.0
const JUNCTION_CLEAR := 17.0
## Wave-5 _landscape tree spots (road x in [-160, 0, 160], 14 m off-centre).
const LEGACY_ROADS: Array[float] = [-160.0, 0.0, 160.0]

var trees: Array[Transform3D] = []
var clutter_count := 0
var _rng := RandomNumberGenerator.new()
var _world: WorldBuilder

func build(world: WorldBuilder) -> void:
	ped_obstacles.clear()
	name = "AvenueDressing"
	_world = world
	_rng.seed = Game.seed_value + 911
	# Physics queries need the static world registered with the space first.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var candidates := _tree_candidates()
	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	probe.shape = sphere
	probe.collision_mask = 1
	for c in candidates:
		var pos: Vector3 = c["pos"]
		var away: Vector3 = c["away"]
		# Trunk volume must be clear.
		sphere.radius = 1.2
		probe.transform = Transform3D(Basis(), pos + Vector3(0, 2.6, 0))
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		# Crown must not bury itself in a facade or arcade roof.
		sphere.radius = 2.2
		probe.transform = Transform3D(Basis(), pos + away * 2.2 + Vector3(0, 7.2, 0))
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		var s := _rng.randf_range(0.78, 0.94)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * s), pos)
		trees.append(xf)
	_batch_trees()
	_trunk_colliders()
	_kerb_clutter(space)
	print("[street] avenue trees=", trees.size(), " candidates=", candidates.size(), " clutter=", clutter_count)

func _tree_candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for axis in 2:
		var lines: Array[float] = WorldBuilder.X_LINES if axis == 0 else WorldBuilder.Z_LINES
		for line in lines:
			for side: float in [-1.0, 1.0]:
				var phase := 7.0 if side > 0.0 else 17.5
				var u := -330.0 + phase
				while u < 330.0:
					var along := u
					u += SPACING
					var near_junction := false
					for j in WorldBuilder.Z_LINES:
						if absf(along - j) < JUNCTION_CLEAR:
							near_junction = true
						# Kerbside furniture (bin/bench/planter) and bus shelters
						# sit at z+28..z+46 on the north-south avenues.
						if axis == 0 and along - j > 25.0 and along - j < 47.0:
							near_junction = true
					if near_junction:
						continue
					var lateral := line + side * TRUNK_OFFSET
					var pos := Vector3(lateral, 0.16, along) if axis == 0 else Vector3(along, 0.16, lateral)
					# Opening heritage five-foot way (see WorldBuilder._landscape).
					if axis == 0 and line == -160.0 and side < 0.0 and along > -160.0 and along < -24.0:
						continue
					# The bay promenade edge and the world rim.
					if pos.z < -326.0 or absf(pos.x) > 334.0 or pos.z > 334.0:
						continue
					if _near_legacy_tree(pos):
						continue
					# Wave-M integration: keep the Supertree grove sightline
					# from the gameplay grove-vista spot open (an avenue crown at
					# (-18.5, -168.9) hid the grove crowns; critic street-life-M2).
					if _blocks_grove_vista(pos):
						continue
					var away := Vector3(side, 0, 0) if axis == 0 else Vector3(0, 0, side)
					out.append({"pos": pos, "away": away, "axis": axis, "along": along})
	return out

const GROVE_VISTA_SPOT := Vector2(-6.0, -150.0)
func _blocks_grove_vista(pos: Vector3) -> bool:
	var a := GROVE_VISTA_SPOT
	var b := Vector2(WorldBuilder.GROVE_POS.x, WorldBuilder.GROVE_POS.z)
	var q := Vector2(pos.x, pos.z)
	var t := clampf((q - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return t < 0.6 and q.distance_to(a.lerp(b, t)) < 9.0

func _near_legacy_tree(pos: Vector3) -> bool:
	for road in LEGACY_ROADS:
		for side: float in [-1.0, 1.0]:
			if absf(pos.x - (road + side * 14.0)) > 8.0:
				continue
			for block in [-240.0, -80.0, 80.0, 240.0]:
				for j in 3:
					if absf(pos.z - (block - 47.0 + j * 47.0)) < 8.0:
						return true
	return false

## One MultiMesh per (160 m cell, tree mesh): whole-map batches are never
## frustum culled and always pick the closest mesh LOD, so the canopy is
## chunked to let distant cells cull and drop to their generated LODs.
func _batch_trees() -> void:
	var path := "res://assets/authored/rain_tree.glb"
	if trees.is_empty() or not ResourceLoader.exists(path):
		return
	var src: Node3D = (load(path) as PackedScene).instantiate()
	var parts: Array[Dictionary] = []
	_collect_meshes(src, Transform3D.IDENTITY, parts)
	var cells := {}
	for xf in trees:
		var key := Vector2i(floori((xf.origin.x + 400.0) / 160.0), floori((xf.origin.z + 400.0) / 160.0))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	for key in cells:
		var list: Array = cells[key]
		for part in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part["mesh"]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, (list[i] as Transform3D) * (part["xf"] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "AvenueTrees_%d_%d_%s" % [key.x, key.y, String(part["name"])]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mmi)
	src.free()

func _collect_meshes(node: Node, parent_xf: Transform3D, out: Array[Dictionary]) -> void:
	for child in node.get_children():
		var xf := parent_xf
		if child is Node3D:
			xf = parent_xf * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append({"mesh": (child as MeshInstance3D).mesh, "xf": xf, "name": child.name})
		_collect_meshes(child, xf, out)

func _trunk_colliders() -> void:
	var body := StaticBody3D.new()
	body.name = "AvenueTreeTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for xf in trees:
		var s := xf.basis.get_scale().x
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.45 * s
		cyl.height = 4.8 * s
		shape.shape = cyl
		shape.position = xf.origin + Vector3(0, 2.4 * s, 0)
		ped_obstacles.append(Vector3(xf.origin.x, xf.origin.z, 0.5 * s))
		body.add_child(shape)

# ------------------------------------------------------------ kerb clutter
## Lived-in kerbside: litter bins, share-bike racks, hydrants, utility
## cabinets, bollards and parking signs between the avenue trees. Every part
## is a primitive batched into one MultiMesh per (mesh, material).
var _batches: Dictionary = {}
## Street-life M2: footprints walkers steer round (x, z, radius), read by
## CrowdDirector (people walked through bike racks and bins in M1).
static var ped_obstacles: Array[Vector3] = []

func _kerb_clutter(space: PhysicsDirectSpaceState3D) -> void:
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.55
	probe.shape = sphere
	probe.collision_mask = 1
	var spots := _tree_candidates()
	var i := 0
	for c in spots:
		i += 1
		var away: Vector3 = c["away"]
		var along_dir := Vector3(0, 0, 1) if int(c["axis"]) == 0 else Vector3(1, 0, 0)
		# Midway between this tree spot and the next one along the avenue.
		var base: Vector3 = (c["pos"] as Vector3) + along_dir * (SPACING * 0.5) - away * 0.15
		base.y = 0.16
		var near_junction := false
		var along: float = float(c["along"]) + SPACING * 0.5
		for j in WorldBuilder.Z_LINES:
			if absf(along - j) < 14.0:
				near_junction = true
		if near_junction or absf(along) > 326.0:
			continue
		probe.transform = Transform3D(Basis(), base + Vector3(0, 1.0, 0))
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		var yaw := atan2(away.x, away.z)
		var kind := (i * 7 + int(absf(base.x + base.z))) % 6
		match kind:
			0, 3: _bike_rack(base, yaw, along_dir)
			1: _bin(base); _bollards(base + along_dir * 2.2, along_dir)
			2: _cabinet(base + away * 0.3, yaw)
			4: _hydrant(base); _sign(base + along_dir * 1.6)
			5: _bin(base + along_dir * -0.8); _bollards(base + along_dir * 1.2, along_dir)
		clutter_count += 1
	for key in _batches:
		var b: Dictionary = _batches[key]
		var xfs: Array = b["xfs"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = b["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 260.0
		add_child(mmi)

static var _meshes: Dictionary = {}
static var _mats: Dictionary = {}

func _mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var m: Mesh
	match id:
		"bin":
			var c := CylinderMesh.new(); c.top_radius = 0.28; c.bottom_radius = 0.25; c.height = 0.95; c.radial_segments = 12; m = c
		"lid":
			var c2 := CylinderMesh.new(); c2.top_radius = 0.2; c2.bottom_radius = 0.31; c2.height = 0.12; c2.radial_segments = 12; m = c2
		"wheel":
			var t := TorusMesh.new(); t.inner_radius = 0.29; t.outer_radius = 0.335; t.rings = 14; t.ring_segments = 5; m = t
		"tube":
			var b := BoxMesh.new(); b.size = Vector3(0.045, 0.045, 1.0); m = b
		"post":
			var c3 := CylinderMesh.new(); c3.top_radius = 0.06; c3.bottom_radius = 0.06; c3.height = 1.0; c3.radial_segments = 8; m = c3
		"box":
			var b2 := BoxMesh.new(); b2.size = Vector3.ONE; m = b2
		"hydrant":
			var c4 := CylinderMesh.new(); c4.top_radius = 0.13; c4.bottom_radius = 0.16; c4.height = 0.75; c4.radial_segments = 10; m = c4
		"cap":
			var sp := SphereMesh.new(); sp.radius = 0.15; sp.height = 0.22; sp.radial_segments = 10; sp.rings = 5; m = sp
		"bollard":
			var c5 := CylinderMesh.new(); c5.top_radius = 0.1; c5.bottom_radius = 0.12; c5.height = 0.9; c5.radial_segments = 8; m = c5
	_meshes[id] = m
	return m

func _mat(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var m: Material
	match id:
		"bin_green": m = Palette.mat(Color(0.16, 0.36, 0.24), 0.6, 0.15)
		"bin_lid": m = Palette.mat(Color(0.86, 0.45, 0.12), 0.55, 0.1)
		"tyre": m = Palette.mat(Color(0.05, 0.05, 0.055), 0.85)
		"bike_yellow": m = Palette.mat(Color(0.95, 0.74, 0.12), 0.4, 0.3)
		"bike_orange": m = Palette.mat(Color(0.93, 0.42, 0.12), 0.4, 0.3)
		"bike_teal": m = Palette.mat(Color(0.12, 0.6, 0.55), 0.4, 0.3)
		"steel": m = Palette.mat(Color(0.6, 0.62, 0.64), 0.35, 0.8)
		"cabinet": m = Palette.mat(Color(0.47, 0.52, 0.47), 0.7, 0.2)
		"hydrant_red": m = Palette.mat(Color(0.7, 0.1, 0.07), 0.45, 0.2)
		"hydrant_cap": m = Palette.mat(Color(0.95, 0.78, 0.15), 0.45, 0.2)
		"sign_blue": m = Palette.mat(Color(0.1, 0.27, 0.6), 0.5, 0.1)
		"sign_white": m = Palette.mat(Color(0.88, 0.88, 0.86), 0.5, 0.0)
		"bollard": m = Palette.mat(Color(0.62, 0.6, 0.56), 0.85, 0.05)
	_mats[id] = m
	return m

func _put(mesh_id: String, mat_id: String, xf: Transform3D, shadow: bool = true) -> void:
	var key := mesh_id + "|" + mat_id
	if not _batches.has(key):
		_batches[key] = {"mesh": _mesh(mesh_id), "mat": _mat(mat_id), "xfs": [], "shadow": shadow}
	_batches[key]["xfs"].append(xf)

func _bin(p: Vector3) -> void:
	ped_obstacles.append(Vector3(p.x, p.z, 0.4))
	_put("bin", "bin_green", Transform3D(Basis(), p + Vector3(0, 0.475, 0)))
	_put("lid", "bin_lid", Transform3D(Basis(), p + Vector3(0, 1.0, 0)))

func _bollards(p: Vector3, along_dir: Vector3) -> void:
	for k in 3:
		var bp := p + along_dir * (k * 1.3)
		ped_obstacles.append(Vector3(bp.x, bp.z, 0.22))
		_put("bollard", "bollard", Transform3D(Basis(), p + along_dir * (k * 1.3) + Vector3(0, 0.45, 0)), false)

func _hydrant(p: Vector3) -> void:
	ped_obstacles.append(Vector3(p.x, p.z, 0.3))
	_put("hydrant", "hydrant_red", Transform3D(Basis(), p + Vector3(0, 0.375, 0)), false)
	_put("cap", "hydrant_cap", Transform3D(Basis(), p + Vector3(0, 0.78, 0)), false)

func _sign(p: Vector3) -> void:
	ped_obstacles.append(Vector3(p.x, p.z, 0.18))
	_put("post", "steel", Transform3D(Basis().scaled(Vector3(0.7, 2.6, 0.7)), p + Vector3(0, 1.3, 0)), false)
	_put("box", "sign_blue", Transform3D(Basis().scaled(Vector3(0.62, 0.62, 0.05)), p + Vector3(0, 2.55, 0)), false)
	_put("box", "sign_white", Transform3D(Basis().scaled(Vector3(0.3, 0.38, 0.052)), p + Vector3(0, 2.55, 0)), false)

func _cabinet(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for k: float in [0.0, 0.6, 1.2]:
		var cp := p + b * Vector3(k, 0, 0)
		ped_obstacles.append(Vector3(cp.x, cp.z, 0.55))
	_put("box", "cabinet", Transform3D(b * Basis.from_scale(Vector3(1.1, 1.25, 0.5)), p + Vector3(0, 0.625, 0)))
	_put("box", "cabinet", Transform3D(b * Basis.from_scale(Vector3(0.7, 0.9, 0.35)), p + b * Vector3(1.2, 0, 0) + Vector3(0, 0.45, 0)))

## Three dock-less share bikes nose-in to the kerb, plus a steel hoop.
func _bike_rack(p: Vector3, yaw: float, along_dir: Vector3) -> void:
	var colors := ["bike_yellow", "bike_orange", "bike_teal"]
	var count := 2 + (int(absf(p.x * 3.0 + p.z)) % 3)
	for k in count:
		var c: String = colors[(int(absf(p.x + p.z)) + k) % colors.size()]
		var origin := p + along_dir * (k * 0.75 - count * 0.35)
		ped_obstacles.append(Vector3(origin.x, origin.z, 0.62))
		# Bike axis points across the pavement (away from the kerb).
		var axis_b := Basis(Vector3.UP, yaw + PI * 0.5 + (k % 2) * 0.12)
		var fwd := axis_b * Vector3(1, 0, 0)
		for w in [-0.52, 0.52]:
			var wheel_basis := axis_b * Basis(Vector3(1, 0, 0), PI * 0.5)
			_put("wheel", "tyre", Transform3D(wheel_basis, origin + fwd * w + Vector3(0, 0.335, 0)), false)
		# top tube, down tube, seat post, handlebar, basket
		_put("tube", c, Transform3D(axis_b * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(1, 1, 0.9)), origin + Vector3(0, 0.78, 0)), false)
		_put("tube", c, Transform3D(axis_b * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3(1, 0, 0), 0.75) * Basis.from_scale(Vector3(1, 1, 0.75)), origin + fwd * 0.12 + Vector3(0, 0.55, 0)), false)
		_put("tube", c, Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5) * Basis.from_scale(Vector3(1, 1, 0.55)), origin - fwd * 0.3 + Vector3(0, 0.75, 0)), false)
		_put("tube", "steel", Transform3D(axis_b * Basis.from_scale(Vector3(1, 1, 0.5)), origin + fwd * 0.5 + Vector3(0, 1.02, 0)), false)
		_put("box", c, Transform3D(axis_b * Basis.from_scale(Vector3(0.28, 0.2, 0.34)), origin + fwd * 0.62 + Vector3(0, 0.88, 0)), false)

