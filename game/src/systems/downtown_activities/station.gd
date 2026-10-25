extends Node3D
## A parcel handover point on existing accessible paving. Uses the already
## shipped crate asset; no added road or invisible collision volume.
var activity: Node
var station_id := ""
var title := ""
var prompt_text := ""
var _ring: MeshInstance3D
var _label: Label3D

func _ready() -> void:
	add_to_group("interactables")
	var crates := AssetLibrary.instantiate("airfield_clutter_clean.glb", self)
	if crates:
		crates.scale = Vector3.ONE * 0.55
		crates.position = Vector3(1.4, 0.0, 0.0)
	_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 0.94
	ring.rings = 32
	ring.ring_segments = 6
	_ring.mesh = ring
	_ring.scale.y = 0.10
	_ring.position.y = 0.045
	_ring.material_override = Palette.emissive(Color(0.35, 0.85, 0.65), 0.4)
	add_child(_ring)
	_label = Label3D.new()
	_label.text = "BAYFRONT COURIER\n" + title
	_label.position = Vector3(1.4, 1.35, 0.0)
	_label.font_size = 32
	_label.pixel_size = 0.0025
	_label.modulate = Color(0.78, 0.95, 0.88)
	_label.outline_modulate = Color(0.02, 0.05, 0.05)
	_label.outline_size = 4
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visibility_range_end = 45.0
	add_child(_label)
	refresh()

func refresh() -> void:
	prompt_text = activity.station_prompt(station_id)
	if _ring:
		_ring.visible = station_id == activity.target_id()

func can_interact() -> bool:
	return activity != null and activity.can_use_station(station_id)

func interact(actor: Node) -> void:
	if activity: activity.use_station(station_id, actor)
