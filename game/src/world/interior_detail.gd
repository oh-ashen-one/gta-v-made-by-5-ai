class_name InteriorDetail
extends RefCounted
## Original authored interior kits. Existing safe-room envelope remains owned
## by WorldBuilder; this file adds its furniture and two complete small shops.
## safe_room is the existing envelope BASE, .2 m below its finished floor.

const ASSET_DIR := "res://assets/authored/"
const SHOP := Vector3(-38.0, 0.20, -22.0)
const WORKSHOP := Vector3(207.0, 0.20, 111.0)

static func build(parent: Node3D, safe_room: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "FurnishedInteriors"
	parent.add_child(root)
	var safe_floor := safe_room + Vector3(0.0, 0.2, 0.0)
	var safe := _asset(root, "interior_safe_furnishings.glb", safe_floor)
	if safe != null:
		safe.name = "SafeRoomFurnishings"
		_safe_collision(safe)
		_light(safe, Vector3(-3.6, 2.68, -3.4), Color(1.0, 0.80, 0.57), 1.25, 5.0)
	var shop := _asset(root, "interior_convenience_shop.glb", SHOP)
	if shop != null:
		shop.name = "OrchardDailyConvenience"
		_envelope_collision(shop, 14.0, 10.0, 3.65, 3.2)
		_shop_collision(shop)
		for x: float in [-4.0, 0.0, 4.0]:
			_light(shop, Vector3(x, 3.30, 0.0), Color(1.0, 0.92, 0.80), 1.6, 7.0)
	var workshop := _asset(root, "interior_workshop.glb", WORKSHOP)
	if workshop != null:
		workshop.name = "HarbourMotorWorks"
		_envelope_collision(workshop, 20.0, 12.0, 4.3, 4.8)
		_workshop_collision(workshop)
		for x: float in [-6.0, 0.0, 6.0]:
			_light(workshop, Vector3(x, 3.93, 0.0), Color(0.93, 0.95, 1.0), 1.65, 8.0)
	return {
		"root": root,
		"convenience_shop": SHOP + Vector3(0.0, 0.4, 0.0),
		"convenience_entrance": SHOP + Vector3(0.0, 0.4, 5.5),
		"workshop": WORKSHOP + Vector3(0.0, 0.4, 0.0),
		"workshop_entrance": WORKSHOP + Vector3(0.0, 0.4, 6.5),
		"safe_floor": safe_floor,
		"inspection_views": inspection_views(safe_room),
		"walking_routes": walking_routes(safe_room),
	}

static func _asset(parent: Node3D, filename: String, position: Vector3) -> Node3D:
	var packed := load(ASSET_DIR + filename) as PackedScene
	if packed == null:
		push_error("Missing authored interior asset: " + filename)
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		push_error("Authored interior root is not Node3D: " + filename)
		return null
	parent.add_child(node)
	node.position = position
	_surface_materials(node)
	return node

static func _solid(parent: Node3D, name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)

static func _light(parent: Node3D, position: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "FixtureLight"
	lamp.position = position
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.1
	lamp.shadow_enabled = false
	parent.add_child(lamp)

static func _envelope_collision(parent: Node3D, width: float, depth: float, height: float, door: float) -> void:
	_solid(parent, "FloorCollision", Vector3(0.0, -0.05, 0.0), Vector3(width, 0.1, depth))
	_solid(parent, "BackWallCollision", Vector3(0.0, height * 0.5, -depth * 0.5), Vector3(width, height, 0.23))
	_solid(parent, "RoofCollision", Vector3(0.0, height + 0.1, 0.0), Vector3(width + 0.4, 0.2, depth + 0.4))
	var pier_width := (width - door) * 0.5
	for sign: float in [-1.0, 1.0]:
		_solid(parent, "SideWallCollision", Vector3(sign * width * 0.5, height * 0.5, 0.0), Vector3(0.23, height, depth))
		_solid(parent, "EntrancePierCollision", Vector3(sign * (door * 0.5 + pier_width * 0.5), height * 0.5, depth * 0.5), Vector3(pier_width, height, 0.23))
	_solid(parent, "EntranceLintelCollision", Vector3(0.0, (height + 2.75) * 0.5, depth * 0.5), Vector3(door, height - 2.75, 0.23))

static func _safe_collision(parent: Node3D) -> void:
	_solid(parent, "DeskCollision", Vector3(-3.6, 0.4, -3.5), Vector3(2.8, 0.8, 1.1))
	_solid(parent, "DeskChairCollision", Vector3(-3.6, 0.58, -2.3), Vector3(0.60, 1.16, 0.62))
	_solid(parent, "StorageCollision", Vector3(4.3, 1.1, -4.15), Vector3(2.6, 2.2, 0.8))
	_solid(parent, "SofaCollision", Vector3(2.2, 0.60, 3.0), Vector3(3.5, 1.2, 1.3))
	_solid(parent, "CoffeeTableCollision", Vector3(1.5, 0.22, 0.7), Vector3(1.8, 0.44, 0.85))

static func _shop_collision(parent: Node3D) -> void:
	for x: float in [-3.1, 3.1]:
		_solid(parent, "StockedIslandCollision", Vector3(x, 0.95, -0.5), Vector3(2.5, 1.9, 0.9))
	_solid(parent, "DryGoodsCollision", Vector3(1.7, 0.95, -4.35), Vector3(4.6, 1.9, 0.8))
	_solid(parent, "CoolerCollision", Vector3(-4.6, 1.20, -4.25), Vector3(3.2, 2.4, 0.95))
	_solid(parent, "CheckoutCollision", Vector3(4.65, 0.52, 2.5), Vector3(3.25, 1.04, 1.13))

static func _workshop_collision(parent: Node3D) -> void:
	_solid(parent, "WorkbenchCollision", Vector3(0.0, 0.48, -4.9), Vector3(7.0, 0.96, 1.25))
	_solid(parent, "PartsRackCollision", Vector3(-7.7, 0.95, -3.8), Vector3(3.1, 1.9, 0.9))
	_solid(parent, "LockersCollision", Vector3(7.5, 1.13, -5.2), Vector3(3.0, 2.26, 0.8))
	_solid(parent, "ToolChestCollision", Vector3(5.1, 0.65, -3.2), Vector3(1.5, 1.3, 0.8))
	_solid(parent, "TyreStackCollision", Vector3(-8.0, 0.43, 3.0), Vector3(1.05, 0.86, 1.05))

static func inspection_views(safe_room: Vector3) -> Array[Dictionary]:
	return [
		{"name": "safe_room_furnished", "pos": safe_room + Vector3(-5.8, 1.9, 0.0), "look": safe_room + Vector3(1.2, 1.1, -0.3), "fov": 72.0},
		{"name": "convenience_exterior", "pos": SHOP + Vector3(-7.0, 2.3, 12.0), "look": SHOP + Vector3(0.0, 1.5, 3.7), "fov": 66.0},
		{"name": "convenience_interior", "pos": SHOP + Vector3(0.0, 1.8, 3.8), "look": SHOP + Vector3(-0.5, 1.1, -3.4), "fov": 76.0},
		{"name": "workshop_exterior", "pos": WORKSHOP + Vector3(9.0, 2.6, 14.0), "look": WORKSHOP + Vector3(0.0, 1.7, 4.0), "fov": 68.0},
		{"name": "workshop_interior", "pos": WORKSHOP + Vector3(0.0, 1.9, 4.9), "look": WORKSHOP + Vector3(0.0, 1.3, -4.5), "fov": 76.0},
	]

static func walking_routes(safe_room: Vector3) -> Dictionary:
	return {
		"safe_room": [safe_room + Vector3(-9.0, 0.6, 0.0), safe_room + Vector3(-5.0, 0.6, 0.0), safe_room + Vector3(0.0, 0.6, 0.0)],
		"convenience": [SHOP + Vector3(0.0, 0.4, 8.0), SHOP + Vector3(0.0, 0.4, 3.5), SHOP + Vector3(0.0, 0.4, -2.4)],
		"workshop": [WORKSHOP + Vector3(0.0, 0.4, 9.0), WORKSHOP + Vector3(0.0, 0.4, 4.0), WORKSHOP + Vector3(0.0, 0.4, -2.0)],
	}

static func _surface_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(index)
			if not source is StandardMaterial3D: continue
			var name := String(source.resource_name).to_lower()
			var kind := ""
			if name.contains("plaster"): kind="plaster"
			elif name.ends_with("tile"): kind="concrete"
			elif name.contains("steel"): kind="metal"
			if kind != "":
				var material := Palette.mat_textured(source.albedo_color,kind,Vector3.ONE,source.roughness,source.metallic,false)
				node.set_surface_override_material(index,material)
	for child in node.get_children(): _surface_materials(child)
