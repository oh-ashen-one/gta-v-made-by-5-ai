extends Node3D
## Mission drop point: a real, visible handover location at the waterfront.

var mission: Node
var prompt_text := "[E] Deliver the package"
var _marker: Node3D

func _ready() -> void:
	add_to_group("interactables")
	var crate := AssetLibrary.instantiate("airfield_clutter_clean.glb", self)
	if crate!=null: crate.scale=Vector3.ONE*.7
	_marker=Node3D.new();add_child(_marker)
	var beam:=MeshInstance3D.new()
	var ring:=TorusMesh.new();ring.inner_radius=1.15;ring.outer_radius=1.23
	ring.rings=40;ring.ring_segments=6;beam.mesh=ring;beam.scale.y=.12
	beam.material_override=Palette.emissive(Color(.35,.85,.65),.4)
	beam.position=Vector3(0,.045,0);_marker.add_child(beam)
	_marker.visible=Game.mission_stage==Mission.Stage.DELIVER
	Events.mission_stage_changed.connect(func(stage: int):_marker.visible=stage==Mission.Stage.DELIVER)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.4, 1.0, 0.8)
	lamp.light_energy = 1.4
	lamp.omni_range = 9.0
	lamp.position = Vector3(0.0, 1.4, 0.0)
	add_child(lamp)

func interact(_player: Node) -> void:
	if mission and mission.has_method("delivery_completed"):
		mission.delivery_completed()

func can_interact() -> bool:
	return mission != null and mission.stage == Mission.Stage.DELIVER
