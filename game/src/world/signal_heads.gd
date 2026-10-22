class_name SignalHeads
## Junction signal heads (opus55 driving-q rQ3). The old single head faced +Z
## on every corner, so a driver approaching along X saw a blank black slab
## (driving-Q2 critic). Every corner pole now carries two three-aspect heads,
## one facing each approach that meets at that corner, each with a backing
## board, hooded lenses and a short bracket. Lenses join the existing
## "traffic_lamps" group (signal_axis 0 = traffic travelling along X, 1 = along
## Z; lamp_index 0 red, 1 amber, 2 green), so TrafficManager keeps driving
## them from the shared signal clock. Housings, boards and hoods are plain
## primitives with shared materials, so the world's static batching merges them.

static var _housing_mat: StandardMaterial3D
static var _board_mat: StandardMaterial3D
static var _lens_off: StandardMaterial3D
static var _housing_mesh: BoxMesh
static var _board_mesh: BoxMesh
static var _hood_mesh: BoxMesh
static var _bracket_mesh: BoxMesh
static var _lens_mesh: CylinderMesh

static func _ensure() -> void:
	if _housing_mat != null: return
	_housing_mat = StandardMaterial3D.new()
	_housing_mat.albedo_color = Color(0.055, 0.058, 0.06)
	_housing_mat.roughness = 0.45
	_housing_mat.metallic = 0.35
	_board_mat = StandardMaterial3D.new()
	_board_mat.albedo_color = Color(0.03, 0.032, 0.034)
	_board_mat.roughness = 0.6
	_lens_off = StandardMaterial3D.new()
	_lens_off.albedo_color = Color(0.06, 0.06, 0.055)
	_lens_off.roughness = 0.15
	_housing_mesh = BoxMesh.new()
	_housing_mesh.size = Vector3(0.36, 1.0, 0.24)
	_board_mesh = BoxMesh.new()
	_board_mesh.size = Vector3(0.62, 1.22, 0.025)
	_hood_mesh = BoxMesh.new()
	_hood_mesh.size = Vector3(0.27, 0.025, 0.2)
	_bracket_mesh = BoxMesh.new()
	_bracket_mesh.size = Vector3(0.08, 0.08, 0.34)
	_lens_mesh = CylinderMesh.new()
	_lens_mesh.top_radius = 0.105
	_lens_mesh.bottom_radius = 0.105
	_lens_mesh.height = 0.03
	_lens_mesh.radial_segments = 16
	_lens_mesh.rings = 1

## Two heads on the pole standing at `pos`; `corner` is the pole's offset sign
## from the junction centre (x, z each +-1).
static func build(root: Node3D, pos: Vector3, corner: Vector2) -> void:
	_ensure()
	var sx := 1.0 if corner.x >= 0.0 else -1.0
	var sz := 1.0 if corner.y >= 0.0 else -1.0
	# Faces the drivers arriving along X from this corner's side, and along Z.
	_head(root, pos, Vector3(sx, 0.0, 0.0), 0, 3.05)
	_head(root, pos, Vector3(0.0, 0.0, sz), 1, 3.05)

static func _part(root: Node3D, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	root.add_child(mi)
	return mi

static func _head(root: Node3D, pole: Vector3, facing: Vector3, axis: int, height: float) -> void:
	# Basis whose -Z... we want local +Z to point along `facing`.
	var z := facing.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var b := Basis(x, Vector3.UP, z)
	var centre := pole + Vector3(0.0, height, 0.0) + z * 0.3
	_part(root, _bracket_mesh, _housing_mat, Transform3D(b, pole + Vector3(0.0, height + 0.3, 0.0) + z * 0.13))
	_part(root, _board_mesh, _board_mat, Transform3D(b, centre - z * 0.13))
	_part(root, _housing_mesh, _housing_mat, Transform3D(b, centre))
	var lens_basis := b * Basis(Vector3.RIGHT, PI * 0.5)   # cylinder axis -> facing
	for i in 3:
		var y := 0.31 - i * 0.31
		_part(root, _hood_mesh, _housing_mat, Transform3D(b * Basis(Vector3.RIGHT, -0.18), centre + Vector3(0.0, y + 0.13, 0.0) + z * 0.2))
		var lens := MeshInstance3D.new()
		lens.mesh = _lens_mesh
		lens.material_override = _lens_off
		lens.transform = Transform3D(lens_basis, centre + Vector3(0.0, y, 0.0) + z * 0.125)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lens.add_to_group("traffic_lamps")
		lens.set_meta("signal_axis", axis)
		lens.set_meta("lamp_index", i)
		root.add_child(lens)
