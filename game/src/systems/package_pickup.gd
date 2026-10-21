extends Node3D
## The mission package: a real 3D object the player picks up by interacting.

var mission: Node
var prompt_text := "[E] Take the package"
var _taken := false

func _ready() -> void:
	add_to_group("interactables")
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.35, 0.42)
	mesh.mesh = bm
	mesh.material_override = Palette.mat(Color(0.42, 0.30, 0.16), 0.9)
	mesh.position = Vector3(0.0, 0.2, 0.0)
	add_child(mesh)
	var strap := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.58, 0.06, 0.45)
	strap.mesh = sb
	strap.material_override = Palette.mat(Color(0.75, 0.62, 0.25), 0.7, 0.2)
	strap.position = Vector3(0.0, 0.2, 0.0)
	add_child(strap)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.55)
	glow.light_energy = 0.9
	glow.omni_range = 5.0
	glow.position = Vector3(0.0, 0.6, 0.0)
	add_child(glow)

func interact(_player: Node) -> void:
	if _taken:
		return
	_taken = true
	visible = false
	Events.toast("Package secured.", "good")
	Sfx.play("pickup", -4.0, 1.0)
	if mission and mission.has_method("package_collected"):
		mission.package_collected()
