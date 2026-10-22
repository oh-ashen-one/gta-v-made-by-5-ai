class_name AmbientVehicle
extends AnimatableBody3D
## Lightweight lane-following traffic car (street-life, Opus wave A).
##
## AmbientTraffic moves these kinematically along the left-hand lane graph, so
## a dense stream of traffic costs a transform write per car instead of a
## CharacterBody collision solve. They are solid (vehicle layer 8): the player,
## the player's car and civilian cars collide with them. A stopped or crawling
## one can be taken with [E]: it is swapped for a real drivable Car on the spot.

const KIND_DIMS := {
	"sedan": Vector3(1.85, 1.45, 4.5),
	"taxi": Vector3(1.85, 1.45, 4.5),
	"coupe": Vector3(1.95, 1.25, 4.2),
	"van": Vector3(2.05, 2.1, 5.2),
	"bus": Vector3(2.45, 3.2, 11.6),
}

var kind := "sedan"
var paint := Color.WHITE
var dims := Vector3(1.85, 1.45, 4.5)
var manager: Node = null
var prompt_text := "[E] Take Sedan"

# Lane state, owned and advanced by AmbientTraffic.
var edge := -1
var lane := 0
var s := 0.0
var speed := 0.0
var vmax := 12.0
var next_edge := -1
var j_p0 := Vector3.ZERO
var j_c := Vector3.ZERO
var j_p2 := Vector3.ZERO
var j_len := 0.0
var obstacle_gap := INF
var stuck_time := 0.0
## Seconds at (near) standstill anywhere; drives the out-of-sight gridlock reset.
var idle_time := 0.0
var scan_timer := 0.0
var active := true
var _brake_lamps: Array[MeshInstance3D] = []
var _braking := false
static var _brake_on: Material
static var _brake_off: Material
static var _taxi_sign: Material
static var _bus_mats: Array = []

func setup_vehicle(vehicle_kind: String, color: Color) -> void:
	kind = vehicle_kind
	paint = color
	dims = KIND_DIMS.get(kind, KIND_DIMS["sedan"])
	prompt_text = "[E] Take %s" % ("Taxi" if kind == "taxi" else kind.capitalize())
	sync_to_physics = false
	collision_layer = 8
	collision_mask = 0
	add_to_group("ambient_vehicles")
	add_to_group("actors")          # civilian Car.blocker_ahead() queues behind us
	if kind != "bus":
		add_to_group("interactables")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Slightly inside the visible body, so lane neighbours never scrape.
	box.size = Vector3(dims.x - 0.12, dims.y, dims.z - 0.1)
	shape.shape = box
	shape.position = Vector3(0.0, dims.y * 0.5, 0.0)
	add_child(shape)
	if kind == "bus":
		_build_bus()
	else:
		_build_car()
	for mi in _all_meshes(self):
		mi.visibility_range_end = 520.0

func _build_car() -> void:
	var file := "sedan_clean.glb"
	match kind:
		"coupe": file = "coupe_clean.glb"
		"van": file = "van_clean.glb"
	var root: Node3D = null
	if AssetLibrary.has_asset(file):
		root = AssetLibrary.instantiate(file, self)
	if root != null:
		# Same fit as Car._try_provider_asset, so a taken car does not jump.
		if kind == "coupe":
			root.rotation.y = PI * 0.5
			root.scale = Vector3(dims.z / 9.13, dims.y / 2.61, dims.x / 4.30)
		elif kind == "van":
			root.rotation.y = PI * 0.5
			root.scale = Vector3(dims.z / 9.73, dims.y / 5.42, dims.x / 5.20)
		if paint != Color.WHITE:
			AssetLibrary.tint(root, paint)
		# The provider wheel_* nodes are stray strips; hide them.
		for wheel_name in ["wheel_FL", "wheel_FR", "wheel_RL", "wheel_RR"]:
			var w := AssetLibrary.find_named(root, wheel_name)
			if w is Node3D:
				(w as Node3D).visible = false
	else:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(dims.x, dims.y * 0.6, dims.z)
		body.mesh = bm
		body.material_override = Palette.mat(paint, 0.35, 0.55)
		body.position.y = dims.y * 0.32
		add_child(body)
		var cabin := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(dims.x * 0.88, dims.y * 0.42, dims.z * 0.5)
		cabin.mesh = cm
		cabin.material_override = Palette.glass()
		cabin.position.y = dims.y * 0.8
		add_child(cabin)
	if kind == "taxi":
		if _taxi_sign == null:
			_taxi_sign = Palette.emissive(Color(1.0, 0.86, 0.35), 1.2)
		var sign_mesh := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.62, 0.2, 0.26)
		sign_mesh.mesh = sb
		sign_mesh.material_override = _taxi_sign
		sign_mesh.position = Vector3(0.0, dims.y + 0.02, 0.15)
		add_child(sign_mesh)
	if root != null:
		# Seat the lamps on the provider body's own rear face; the collider
		# dims do not match the art, which left lamps floating beside it.
		var bounds := _local_bounds(root)
		if bounds.size.z > 0.5:
			_add_brake_lamps(bounds.position.y + bounds.size.y * 0.5, bounds.end.z - 0.06, bounds.size.x * 0.3, bounds.get_center().x)
	else:
		_add_brake_lamps(dims.y * 0.55, dims.z * 0.5 + 0.02, dims.x * 0.36)
	_add_driver()

## Merged mesh bounds of a subtree, in this vehicle's local space.
func _local_bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for mi in _all_meshes(node):
		if mi.mesh == null or not (mi.is_visible_in_tree() if is_inside_tree() else mi.visible):
			continue
		var xf: Transform3D
		if is_inside_tree():
			xf = inv * mi.global_transform
		else:
			xf = Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != self:
				if n is Node3D:
					xf = (n as Node3D).transform * xf
				n = n.get_parent()
		var box: AABB = xf * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out

## Singapore double-decker: procedural, two glazed decks with pillars, livery
## band, front and rear detailing, wheel arches and wheels.
func _build_bus() -> void:
	if _bus_mats.is_empty():
		_bus_mats = [
			Palette.mat(Color(0.86, 0.86, 0.82), 0.45, 0.25),            # body
			Palette.glass(),                                             # glazing
			Palette.mat(Color(0.36, 0.55, 0.22), 0.5, 0.2),              # livery band
			Palette.mat(Color(0.07, 0.07, 0.08), 0.9),                   # tyres / skirt
			Palette.emissive(Color(1.0, 0.62, 0.18), 1.6),               # destination sign
			Palette.mat(Color(0.18, 0.19, 0.2), 0.6, 0.4),               # pillars / grille
			Palette.emissive(Color(1.0, 0.95, 0.85), 1.4),               # head lamps
		]
	var body_mat: Material = _bus_mats[0]
	var glass_mat: Material = _bus_mats[1]
	var band_mat: Material = _bus_mats[2]
	var dark_mat: Material = _bus_mats[3]
	var pillar_mat: Material = _bus_mats[5]
	if paint != Color.WHITE:
		band_mat = Palette.mat(paint, 0.45, 0.25)
	var half_z := dims.z * 0.5
	_part(Vector3(dims.x - 0.1, 0.35, dims.z - 0.2), Vector3(0, 0.42, 0), dark_mat)
	_part(Vector3(dims.x, dims.y - 0.62, dims.z), Vector3(0, 0.62 + (dims.y - 0.62) * 0.5, 0), body_mat)
	# Two glazed decks broken by pillars, set just proud of the body.
	for deck_y in [1.6, 2.68]:
		_part(Vector3(dims.x + 0.03, 0.74, dims.z - 1.4), Vector3(0, deck_y, 0.1), glass_mat)
		var n := int((dims.z - 1.4) / 1.25)
		for k in n + 1:
			var z := -((dims.z - 1.4) * 0.5) + 0.1 + k * ((dims.z - 1.4) / n)
			_part(Vector3(dims.x + 0.06, 0.76, 0.12), Vector3(0, deck_y, z), pillar_mat)
	_part(Vector3(dims.x + 0.05, 0.22, dims.z + 0.02), Vector3(0, 2.13, 0), band_mat)
	_part(Vector3(dims.x + 0.05, 0.16, dims.z + 0.02), Vector3(0, 0.98, 0), band_mat)
	# Front (-Z): split windscreen, destination blind, lamps, bumper.
	_part(Vector3(dims.x - 0.25, 1.05, 0.06), Vector3(0, 1.62, -half_z - 0.02), glass_mat)
	_part(Vector3(dims.x - 0.25, 0.72, 0.06), Vector3(0, 2.68, -half_z - 0.02), glass_mat)
	_part(Vector3(0.08, 1.05, 0.08), Vector3(0, 1.62, -half_z - 0.04), pillar_mat)
	_part(Vector3(dims.x - 0.6, 0.24, 0.05), Vector3(0, 2.2, -half_z - 0.04), _bus_mats[4])
	for sx in [-1.0, 1.0]:
		_part(Vector3(0.32, 0.16, 0.05), Vector3(sx * (dims.x * 0.5 - 0.32), 0.78, -half_z - 0.03), _bus_mats[6])
	_part(Vector3(dims.x, 0.3, 0.12), Vector3(0, 0.45, -half_z - 0.05), pillar_mat)
	# Rear (+Z): upper rear window, engine grille, bumper.
	_part(Vector3(dims.x - 0.5, 0.6, 0.06), Vector3(0, 2.7, half_z + 0.02), glass_mat)
	_part(Vector3(dims.x - 0.5, 0.55, 0.05), Vector3(0, 0.95, half_z + 0.02), pillar_mat)
	_part(Vector3(dims.x, 0.3, 0.12), Vector3(0, 0.45, half_z + 0.05), pillar_mat)
	_part(Vector3(dims.x + 0.02, 0.08, dims.z + 0.02), Vector3(0, dims.y + 0.02, 0), body_mat)
	for z in [-dims.z * 0.33, dims.z * 0.3]:
		_part(Vector3(dims.x + 0.04, 0.5, 1.25), Vector3(0, 0.66, z), dark_mat)
		for sx in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.32
			cm.radial_segments = 14
			w.mesh = cm
			w.material_override = dark_mat
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * (dims.x * 0.5 - 0.12), 0.5, z)
			add_child(w)
	_add_brake_lamps(0.9, half_z + 0.03, dims.x * 0.4)

func _part(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

func _add_brake_lamps(height: float, back: float, half: float, centre_x := 0.0) -> void:
	if _brake_on == null:
		_brake_on = Palette.emissive(Color(1.0, 0.08, 0.05), 3.2)
		_brake_off = Palette.emissive(Color(0.55, 0.05, 0.04), 0.5)
	for sx in [-1.0, 1.0]:
		var lamp := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.3, 0.12, 0.05)
		lamp.mesh = lb
		lamp.material_override = _brake_off
		lamp.position = Vector3(centre_x + sx * half, height, back)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lamp)
		_brake_lamps.append(lamp)

static var _driver_mats: Array = []
func _add_driver() -> void:
	if _driver_mats.is_empty():
		var torso := CapsuleMesh.new()
		torso.radius = 0.2
		torso.height = 0.62
		var head := SphereMesh.new()
		head.radius = 0.105
		head.height = 0.23
		_driver_mats = [torso, head, Palette.mat(Color(0.2, 0.22, 0.26), 0.9), Palette.mat(Color(0.52, 0.38, 0.29), 0.7)]
	var seat: Vector3 = Car.DRIVER_SEAT.get(kind if kind != "taxi" else "sedan", Car.DRIVER_SEAT["sedan"])
	for part in [[0, 2, Vector3(0.0, 0.86, 0.0)], [1, 3, Vector3(0.0, 1.16, -0.02)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _driver_mats[part[0]]
		mi.material_override = _driver_mats[part[1]]
		mi.position = seat + part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

func set_braking(on: bool) -> void:
	if on == _braking:
		return
	_braking = on
	for lamp in _brake_lamps:
		lamp.material_override = _brake_on if on else _brake_off

func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			out.append(child)
		out.append_array(_all_meshes(child))
	return out

## Slow or stopped traffic can be taken by a nearby player on foot.
func can_interact() -> bool:
	if not visible or not active or speed > 4.0:
		return false
	return global_position.distance_to(Game.player_position) < 4.6

func interact(player: Node) -> void:
	if manager != null and manager.has_method("promote"):
		manager.promote(self, player)
