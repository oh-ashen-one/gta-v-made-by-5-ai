class_name JunctionSignals
extends Node3D
## Overhead junction signals (street-life, Opus wave D).
##
## The wave-5 junctions carry one 3.4 m post per corner with a fist-sized
## head, which reads as nothing beyond ~40 m (driving-C2 critic: "junction
## views show 0-1 vehicles and 0 pedestrians", no readable signals). Every
## signalled approach now gets a kerbside cantilever mast at the stop line:
## a tapered pole, an arm reaching over both traffic lanes, two backplated
## three-aspect heads facing the approaching drivers, and a pedestrian head on
## the pole facing the crossing. Everything is batched as one MultiMesh per
## part; the six lens sets (2 signal axes x 3 aspects) join the
## "traffic_lamps" group, so TrafficManager lights them with the phase.
## Visual only: no colliders, so routes and AI are unaffected.

const STOP_BACK := 12.6        # mast this far before the junction centre
const KERB_SIDE := 9.05        # pole this far left of the road centreline
const ARM_HEIGHT := 5.7
const ARM_REACH := 8.6         # from the pole toward the median
const HEAD_LATS: Array[float] = [4.6, 2.3]   # heads over each lane centre

var masts := 0
var _xf := {}                  # part -> Array[Transform3D]

func build(world: WorldBuilder) -> void:
	name = "JunctionSignals"
	for node: Vector3 in world.traffic_nodes:
		for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			if not _has_node(world, node - d * 160.0):
				continue
			_mast(Vector3(node.x, 0.0, node.z), d)
	_commit()

func _has_node(world: WorldBuilder, p: Vector3) -> bool:
	for n: Vector3 in world.traffic_nodes:
		if absf(n.x - p.x) < 0.5 and absf(n.z - p.z) < 0.5:
			return true
	return false

func _add(part: String, xf: Transform3D) -> void:
	if not _xf.has(part):
		_xf[part] = []
	(_xf[part] as Array).append(xf)

## One approach: traffic travels along `d` into the junction at `centre`.
func _mast(centre: Vector3, d: Vector3) -> void:
	masts += 1
	var left := Vector3.UP.cross(d).normalized()        # kerb side (left-hand traffic)
	var face := Basis.looking_at(-d, Vector3.UP)        # -Z of a head points at the drivers
	var base := centre - d * STOP_BACK + left * KERB_SIDE
	var axis := 0 if absf(d.x) > absf(d.z) else 1
	# Pole and footing.
	_add("pole", Transform3D(Basis(), base + Vector3(0, ARM_HEIGHT * 0.5 + 0.1, 0)))
	_add("footing", Transform3D(Basis(), base + Vector3(0, 0.12, 0)))
	# Arm: a box along -left (toward the median), slightly raked up.
	var arm_mid := base - left * (ARM_REACH * 0.5) + Vector3(0, ARM_HEIGHT, 0)
	var arm_basis := Basis(-left, Vector3.UP, (-left).cross(Vector3.UP))
	_add("arm", Transform3D(arm_basis, arm_mid))
	# Diagonal brace under the arm root.
	var brace_mid := base - left * 1.1 + Vector3(0, ARM_HEIGHT - 0.7, 0)
	_add("brace", Transform3D(Basis(d, 0.9) * face, brace_mid))
	# Overhead heads, one per lane, hanging below the arm.
	for lat: float in HEAD_LATS:
		var hp := centre - d * STOP_BACK + left * lat + Vector3(0, ARM_HEIGHT - 0.62, 0)
		_head(hp, face, d, axis, 1.0)
	# Kerbside repeater on the pole at driver height, and a pedestrian head
	# on the far side of the pole facing across the crossing.
	_head(base + Vector3(0, 3.1, 0) - left * 0.28, face, d, axis, 0.8)
	var ped_face := Basis.looking_at(-left, Vector3.UP)
	var pp := base + Vector3(0, 2.55, 0) + d * 0.25
	_add("ped_box", Transform3D(ped_face, pp))
	# Pedestrians cross this approach's road, so they walk when it is red:
	# lens on the axis with the *other* phase (green man = that axis' green).
	_add("lens_%d_2" % (1 - axis), Transform3D(ped_face, pp - left * 0.13 + Vector3(0, -0.14, 0)))   # green man
	_add("lens_%d_0" % (1 - axis), Transform3D(ped_face, pp - left * 0.13 + Vector3(0, 0.14, 0)))    # red man

func _head(pos: Vector3, face: Basis, d: Vector3, axis: int, s: float) -> void:
	var b := face.scaled(Vector3(s, s, s))
	_add("backplate", Transform3D(b, pos + d * 0.06 * s))
	_add("housing", Transform3D(b, pos))
	for i in 3:
		var lp := pos + Vector3(0, (0.3 - i * 0.3) * s, 0) - d * 0.15 * s
		_add("visor", Transform3D(b, lp - d * 0.09 * s + Vector3(0, 0.1 * s, 0)))
		_add("lens_%d_%d" % [axis, i], Transform3D(b, lp))

func _commit() -> void:
	var metal := Palette.mat(Color(0.16, 0.17, 0.17), 0.45, 0.65)
	var head_mat := Palette.mat(Color(0.05, 0.05, 0.05), 0.5, 0.3)
	var plate := Palette.mat(Color(0.03, 0.03, 0.03), 0.7, 0.1)
	var footing := Palette.mat(Color(0.58, 0.57, 0.54), 0.9)
	var meshes := {
		"pole": _cyl(0.11, 0.14, ARM_HEIGHT + 0.2), "footing": _cyl(0.32, 0.36, 0.24),
		"arm": _box(Vector3(ARM_REACH, 0.16, 0.16)), "brace": _box(Vector3(0.07, 1.6, 0.07)),
		"backplate": _box(Vector3(0.62, 1.12, 0.04)), "housing": _box(Vector3(0.36, 0.98, 0.26)),
		"visor": _box(Vector3(0.3, 0.03, 0.2)), "ped_box": _box(Vector3(0.34, 0.6, 0.24)),
	}
	var mats := {"pole": metal, "footing": footing, "arm": metal, "brace": metal, "backplate": plate,
		"housing": head_mat, "visor": head_mat, "ped_box": head_mat}
	for part in _xf:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var lens := String(part).begins_with("lens_")
		mm.mesh = _lens() if lens else meshes[part]
		var list: Array = _xf[part]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Signals_" + String(part)
		mmi.multimesh = mm
		mmi.visibility_range_end = 420.0
		if lens:
			var bits := String(part).split("_")
			mmi.add_to_group("traffic_lamps")
			mmi.set_meta("signal_axis", int(bits[1]))
			mmi.set_meta("lamp_index", int(bits[2]))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.material_override = mats[part]
		add_child(mmi)

func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 10
	return m

func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

## A domed lens facing -Z.
func _lens() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.125
	m.height = 0.05
	m.radial_segments = 14
	# Rotate the cylinder axis onto Z by baking through a SurfaceTool.
	var st := SurfaceTool.new()
	st.append_from(m, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	return st.commit()
