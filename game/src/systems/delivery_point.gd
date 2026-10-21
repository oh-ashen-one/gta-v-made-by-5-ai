extends Node3D
## Mission drop point: a real, visible handover location at the waterfront.

var mission: Node
var prompt_text := "[E] Deliver the package"

func _ready() -> void:
	add_to_group("interactables")
	var crate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.9, 1.0)
	crate.mesh = bm
	crate.material_override = Palette.mat(Color(0.30, 0.33, 0.28), 0.9)
	crate.position = Vector3(0.0, 0.45, 0.0)
	add_child(crate)
	var band := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(1.7, 0.12, 1.1)
	band.mesh = sb
	band.material_override = Palette.emissive(Color(0.35, 0.9, 0.7), 1.4)
	band.position = Vector3(0.0, 0.85, 0.0)
	add_child(band)
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.10
	beam_mesh.bottom_radius = 0.22
	beam_mesh.height = 3.4
	beam_mesh.radial_segments = 10
	beam.mesh = beam_mesh
	beam.material_override = Palette.emissive(Color(0.35, 0.95, 0.75), 1.4)
	beam.position = Vector3(0.0, 1.7, 0.0)
	add_child(beam)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.4, 1.0, 0.8)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.position = Vector3(0.0, 1.4, 0.0)
	add_child(lamp)

func interact(_player: Node) -> void:
	if mission and mission.has_method("delivery_completed"):
		mission.delivery_completed()
