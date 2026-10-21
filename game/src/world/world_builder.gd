class_name WorldBuilder
extends Node3D
## Procedural but authored-feeling Singapore-inspired district ("Orchard Reach").
##
## Layout is a deliberate grid of distinct precincts (END_GOAL WORLD-02):
## heritage shophouse streets, a public-housing void-deck neighbourhood, a
## roofed hawker hub, a modern waterfront edge and a fictional aviation
## compound. Everything is built from world-space 3D meshes with collision
## (ART-02); nothing here is a billboard or a flat backdrop.

const X_LINES: Array[float] = [-320.0, -160.0, 0.0, 160.0, 320.0]
const Z_LINES: Array[float] = [-320.0, -160.0, 0.0, 160.0, 320.0]
const ROAD_HALF := 8.0          # carriageway half-width (16 m carriageway)
const SIDEWALK := 10.0          # distance from road centre to walkable kerb band
const BLOCK := 144.0            # block platform edge-to-edge
const PROMENADE_Z := -338.0
const WORLD_MIN := Vector3(-330.0, 0.0, -350.0)
const WORLD_MAX := Vector3(330.0, 0.0, 330.0)

# --- layout data consumed by other systems -----------------------------------
var traffic_nodes: Array[Vector3] = []
var ped_lanes: Array = []          # Array of Array[Vector3] polylines
var parked_spots: Array = []       # Array of Dictionary {pos, heading, kind}
var locations := {
	"safe_room": Vector3(-268.0, 0.2, -80.0),
	"package": Vector3(-80.0, 1.0, -80.0),
	"marked_car": Vector3(-40.0, 0.2, -150.0),
	"helipad_primary": Vector3(240.0, 0.2, 240.0),
	"helipad_secondary": Vector3(0.0, 0.2, -330.0),
	"delivery": Vector3(96.0, 0.2, -322.0),
	"hawker": Vector3(-80.0, 0.2, -80.0),
}

var _rng := RandomNumberGenerator.new()
var _world_root: Node3D
var _collision_root: StaticBody3D

func build(seed_value: int = 20261021) -> void:
	_rng.seed = seed_value
	_world_root = Node3D.new()
	_world_root.name = "District"
	add_child(_world_root)
	_collision_root = StaticBody3D.new()
	_collision_root.name = "StaticWorld"
	_collision_root.collision_layer = 1
	_collision_root.collision_mask = 0
	_world_root.add_child(_collision_root)

	_environment()
	_ground()
	_roads()
	_junctions()
	_street_furniture()
	_build_grid()
	_waterfront_edge()
	_background_city()
	_build_lane_graph()
	_scatter_props()

# ---------------------------------------------------------------- environment
func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.42, 0.68)
	sky_mat.sky_horizon_color = Color(0.83, 0.78, 0.68)
	sky_mat.sky_curve = 0.15
	sky_mat.ground_bottom_color = Color(0.28, 0.27, 0.24)
	sky_mat.ground_horizon_color = Color(0.72, 0.66, 0.55)
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.76, 0.70)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.2
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, 38.0, 0.0)
	sun.light_energy = 2.6
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, -140.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.72, 0.80, 0.95)
	fill.shadow_enabled = false
	add_child(fill)

# -------------------------------------------------------------- ground/roads
func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	_world_root.add_child(ground)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1500.0, 4.0, 1500.0)
	mesh.mesh = box
	mesh.material_override = Palette.mat_textured(Palette.CONCRETE_LIGHT, "concrete", Vector3(70.0, 1.0, 70.0), 0.95)
	mesh.position = Vector3(0.0, -2.0, 0.0)
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1500.0, 4.0, 1500.0)
	shape.shape = bs
	shape.position = Vector3(0.0, -2.0, 0.0)
	ground.add_child(shape)

func _roads() -> void:
	var asphalt := Palette.mat_textured(Palette.ASPHALT, "asphalt", Vector3(8.0, 1.0, 120.0), 0.9)
	var paint := Palette.mat(Palette.PAINT_LINE, 0.75)
	for x in X_LINES:
		var strip := _solid_box(Vector3(ROAD_HALF * 2.0, 0.06, 760.0), Vector3(x, 0.03, 0.0), asphalt)
		strip.name = "RoadX"
		for z in range(-360, 361, 12):
			if absf(z) < 9.0:
				continue
			_box(Vector3(0.16, 0.02, 5.0), Vector3(x, 0.08, z), paint).name = "LaneDash"
	for z in Z_LINES:
		_solid_box(Vector3(760.0, 0.06, ROAD_HALF * 2.0), Vector3(0.0, 0.03, z), asphalt).name = "RoadZ"
		for x in range(-360, 361, 12):
			if absf(x) < 9.0:
				continue
			_box(Vector3(5.0, 0.02, 0.16), Vector3(x, 0.08, z), paint).name = "LaneDash"
	# kerbs + sidewalk bands around each block
	for cx in [-240.0, -80.0, 80.0, 240.0]:
		for cz in [-240.0, -80.0, 80.0, 240.0]:
			_solid_box(Vector3(BLOCK, 0.16, BLOCK), Vector3(cx, 0.08, cz), Palette.mat_textured(Palette.CONCRETE, "concrete", Vector3(24.0, 1.0, 24.0), 0.92))

# ------------------------------------------------------------------- blocks
func _build_grid() -> void:
	for col in 4:
		for row in 4:
			var cx: float = [-240.0, -80.0, 80.0, 240.0][col]
			var cz: float = [-240.0, -80.0, 80.0, 240.0][row]
			var kit := _kit_for(col, row)
			match kit:
				"shophouse":
					_shophouse_block(Vector3(cx, 0.16, cz))
				"hdb":
					_hdb_block(Vector3(cx, 0.16, cz))
				"hawker":
					_hawker_block(Vector3(cx, 0.16, cz))
				"waterfront":
					_waterfront_block(Vector3(cx, 0.16, cz))
				"aviation":
					_aviation_block(Vector3(cx, 0.16, cz))
				_:
					_mixed_block(Vector3(cx, 0.16, cz))

func _kit_for(col: int, row: int) -> String:
	# row 0 = northern waterfront edge, row 3 = southern edge.
	var table := {
		Vector2i(0, 0): "shophouse", Vector2i(1, 0): "waterfront", Vector2i(2, 0): "shophouse",
		Vector2i(3, 0): "waterfront",
		Vector2i(0, 1): "hdb", Vector2i(1, 1): "hawker", Vector2i(2, 1): "shophouse",
		Vector2i(3, 1): "shophouse",
		Vector2i(0, 2): "hdb", Vector2i(1, 2): "shophouse", Vector2i(2, 2): "hdb",
		Vector2i(3, 2): "aviation",
		Vector2i(0, 3): "shophouse", Vector2i(3, 3): "hdb",
	}
	return String(table.get(Vector2i(col, row), "mixed"))

## Heritage shophouses: narrow frontages, five-foot-way arcades, pitched roofs.
func _shophouse_block(centre: Vector3) -> void:
	# two street-facing rows plus a rear service lane
	_shophouse_row(centre + Vector3(-BLOCK / 2.0 + 8.0, 0.0, -BLOCK / 2.0 + 8.0), Vector3(1, 0, 0), 13)
	_shophouse_row(centre + Vector3(BLOCK / 2.0 - 8.0, 0.0, BLOCK / 2.0 - 8.0), Vector3(-1, 0, 0), 13)
	# low rear service buildings + a service lane
	for i: int in 3:
		var p := centre + Vector3(-40.0 + i * 40.0, 0.0, 30.0)
		_solid_box(Vector3(18.0, 6.0, 10.0), p + Vector3(0.0, 3.0, 0.0), Palette.mat(Palette.PLASTER_2, 0.9))
		_box(Vector3(19.0, 0.4, 11.0), p + Vector3(0.0, 6.2, 0.0), Palette.mat(Palette.METAL, 0.6, 0.6))
	for i: int in 6:
		var t := centre + Vector3(-50.0 + i * 20.0, 0.0, 46.0)
		_tree(t + Vector3(0.0, 0.0, 0.0), 1.0)

func _shophouse_row(origin: Vector3, dir: Vector3, count: int) -> void:
	var unit_w := 10.6
	for i in count:
		var pos: Vector3 = origin + dir * (unit_w * 0.5 + i * unit_w)
		var frontage: Color = Palette.FRONTAGES[i % Palette.FRONTAGES.size()]
		var height := 9.5 + float(i % 3) * 1.6
		var depth := 13.0
		# body
		_solid_box(Vector3(unit_w - 0.35, height, depth), pos + Vector3(0.0, height * 0.5, 0.0),
			Palette.mat_textured(frontage, "plaster", Vector3(3.0, 2.0, 3.0), 0.88))
		# five-foot-way arcade: columns + covered walkway (recessed threshold)
		var arcade_dir := Vector3(0.0, 0.0, 1.0) if dir.x != 0.0 else Vector3(1.0, 0.0, 0.0)
		var along := Vector3(0.0, 0.0, 1.0) if dir.x != 0.0 else Vector3(1.0, 0.0, 0.0)
		for c in 2:
			var cpos := pos + dir * (-unit_w * 0.25 + c * unit_w * 0.5) - arcade_dir * (depth * 0.5 + 1.6)
			_solid_box(Vector3(0.55, 3.6, 0.55), cpos + Vector3(0.0, 1.8, 0.0), Palette.mat(Palette.CONCRETE, 0.9))
		_solid_box(Vector3(unit_w - 0.35, 0.35, 3.2), pos + Vector3(0.0, 3.7, 0.0) - arcade_dir * (depth * 0.5 + 1.4),
			Palette.mat(Palette.PLASTER_2, 0.9))
		# shopfront: dark recess + warm interior glow + shutter panels
		var front := pos - arcade_dir * (depth * 0.5 + 0.1)
		_box(Vector3(unit_w - 2.0, 2.6, 0.12), front + Vector3(0.0, 1.3, 0.0), Palette.mat(Color(0.08, 0.07, 0.06), 0.6))
		_box(Vector3(unit_w - 3.4, 1.7, 0.06), front + Vector3(0.0, 1.5, 0.05), Palette.emissive(Palette.SHOP_WARM, 1.1))
		_box(Vector3(unit_w - 1.2, 0.5, 0.1), front + Vector3(0.0, 3.3, 0.0), Palette.mat(Palette.METAL, 0.5, 0.5))
		# upper windows
		for w: int in 3:
			var wx := along * (-unit_w * 0.3 + w * unit_w * 0.3)
			_box(Vector3(1.5, 1.4, 0.1), pos + wx + Vector3(0.0, 6.6, 0.0) - arcade_dir * (depth * 0.5 + 0.06),
				Palette.mat(Palette.GLASS, 0.25, 0.2))
			_box(Vector3(1.8, 0.14, 0.22), pos + wx + Vector3(0.0, 5.7, 0.0) - arcade_dir * (depth * 0.5 + 0.08),
				Palette.mat(Palette.PLASTER, 0.9))
		# pitched tile roof
		var roof := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(unit_w - 0.2, 2.6, depth + 0.6)
		roof.mesh = prism
		roof.material_override = Palette.mat_textured(Palette.ROOF_TILE if i % 2 == 0 else Palette.ROOF_TILE_2, "tile", Vector3(2.0, 2.0, 3.0), 0.8)
		roof.position = pos + Vector3(0.0, height + 1.3, 0.0)
		if dir.z != 0.0:
			roof.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		_world_root.add_child(roof)
		# awning + signage
		var awning := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(unit_w - 1.0, 0.12, 1.6)
		awning.mesh = am
		awning.material_override = Palette.mat(Palette.FRONTAGES[(i + 3) % Palette.FRONTAGES.size()], 0.9)
		awning.position = front + Vector3(0.0, 2.95, 0.0) + arcade_dir * 0.9
		awning.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		if dir.x != 0.0:
			awning.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
			awning.scale = Vector3(1.0, 1.0, 1.0)
		else:
			awning.rotation_degrees = Vector3(0.0, 0.0, 14.0)
		_world_root.add_child(awning)
		var sign := _label3d(Palette.SIGN_TEXT[(i * 3 + int(absf(pos.x + pos.z))) % Palette.SIGN_TEXT.size()], front + Vector3(0.0, 3.9, 0.0) + arcade_dir * 0.12)
		sign.font_size = 44
		sign.pixel_size = 0.011
		sign.modulate = Color(0.96, 0.93, 0.86)
		# kerb parking bay
		if i % 3 == 1:
			parked_spots.append({"pos": pos + arcade_dir * (depth * 0.5 + 3.4) + Vector3(0.0, 0.2, 0.0), "heading": 0.0, "kind": "sedan"})

## Public housing: tall slab blocks, void-deck ground floor, courtyard, carpark.
func _hdb_block(centre: Vector3) -> void:
	var slabs := [
		{"pos": Vector3(-38.0, 0.0, -34.0), "rot": 0.0, "h": 58.0},
		{"pos": Vector3(38.0, 0.0, -34.0), "rot": 0.0, "h": 52.0},
		{"pos": Vector3(-30.0, 0.0, 40.0), "rot": 90.0, "h": 46.0},
	]
	for s in slabs:
		var pos: Vector3 = centre + s["pos"]
		var h: float = s["h"]
		var rot: float = s["rot"]
		var size := Vector3(22.0, h, 13.0)
		if rot == 90.0:
			size = Vector3(13.0, h, 22.0)
		_solid_box(size, pos + Vector3(0.0, 3.6 + h * 0.5, 0.0), Palette.mat_textured(Palette.CONCRETE, "concrete", Vector3(5.0, 7.0, 3.0), 0.85))
		# void-deck: open ground floor with columns
		for cx: int in 3:
			for cz: int in 3:
				_solid_box(Vector3(0.7, 3.6, 0.7), pos + Vector3(-size.x * 0.4 + cx * size.x * 0.4, 1.8, -size.z * 0.4 + cz * size.z * 0.4),
					Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
		# lift lobby + sheltered link
		_solid_box(Vector3(4.2, 3.0, 5.0), pos + Vector3(0.0, 1.5, size.z * 0.5 + 2.0), Palette.mat(Palette.PLASTER_2, 0.9))
		_box(Vector3(4.4, 0.25, 3.0), pos + Vector3(0.0, 3.2, size.z * 0.5 + 2.6), Palette.mat(Palette.METAL, 0.6, 0.4))
		# window bands
		var floors := int(h / 3.4)
		for f in floors:
			var wy := 6.4 + f * 3.4
			for w: int in 5:
				var off := -size.x * 0.36 + w * size.x * 0.18
				var win_pos := pos + Vector3(off, wy, size.z * 0.5 + 0.06)
				if rot == 90.0:
					win_pos = pos + Vector3(size.x * 0.5 + 0.06, wy, off)
				_box(Vector3(1.5, 1.3, 0.12), win_pos, Palette.mat(Palette.GLASS, 0.25, 0.25))
		# roof parapet + tank
		_box(size + Vector3(0.0, 0.6, 0.0), pos + Vector3(0.0, 3.6 + h + 0.3, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
		_cyl(Vector3(2.0, 2.4, 2.0), pos + Vector3(size.x * 0.25, 3.6 + h + 1.8, 0.0), Palette.mat(Palette.METAL, 0.7, 0.3))
	# planted courtyard with a community table
	_solid_box(Vector3(40.0, 0.3, 34.0), centre + Vector3(0.0, 0.15, 2.0), Palette.mat(Color(0.32, 0.40, 0.26), 0.95))
	for i: int in 8:
		var ang := TAU * i / 8.0
		_tree(centre + Vector3(cos(ang) * 15.0, 0.0, 2.0 + sin(ang) * 12.0), 1.1)
	_box(Vector3(5.0, 0.16, 2.0), centre + Vector3(0.0, 0.9, 2.0), Palette.mat(Palette.PLASTER, 0.85))
	for i: int in 3:
		_box(Vector3(0.2, 0.85, 0.2), centre + Vector3(-1.8 + i * 1.8, 0.45, 2.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
	# driveable multi-level carpark ramp
	_solid_box(Vector3(26.0, 0.4, 12.0), centre + Vector3(34.0, 0.2, 52.0), Palette.mat(Palette.CONCRETE, 0.9))
	for i: int in 4:
		_solid_box(Vector3(26.0, 0.4, 3.0), centre + Vector3(34.0, 3.2 + i * 3.0, 44.0 + i * 4.0), Palette.mat(Palette.CONCRETE, 0.9))
		_solid_box(Vector3(0.6, 3.2, 3.0), centre + Vector3(21.5, 1.6 + i * 3.0, 44.0 + i * 4.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	# safe room interior (wave-1 mission origin)
	if centre.x < -200.0 and centre.z > -100.0 and centre.z < 0.0:
		_safe_room(centre + Vector3(-52.0, 0.0, 34.0))

func _safe_room(pos: Vector3) -> void:
	_solid_box(Vector3(14.0, 0.2, 10.0), pos + Vector3(0.0, 0.1, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(14.0, 3.4, 0.4), pos + Vector3(0.0, 1.7, side * 5.0), Palette.mat(Palette.PLASTER, 0.9))
	# doorway on the -X side, facing the street, so the room can be entered and left
	_solid_box(Vector3(0.4, 3.4, 3.5), pos + Vector3(-7.0, 1.7, -3.25), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(0.4, 3.4, 3.5), pos + Vector3(-7.0, 1.7, 3.25), Palette.mat(Palette.PLASTER, 0.9))
	_box(Vector3(0.5, 0.4, 3.4), pos + Vector3(-7.0, 3.5, 0.0), Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 1.0, 2.0), 0.5, 0.5))
	_solid_box(Vector3(14.0, 0.3, 10.0), pos + Vector3(0.0, 3.5, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	_solid_box(Vector3(0.4, 3.4, 10.0), pos + Vector3(7.0, 1.7, 0.0), Palette.mat(Palette.PLASTER, 0.9))
	_box(Vector3(2.6, 0.9, 1.2), pos + Vector3(-3.0, 0.6, -3.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	_box(Vector3(2.2, 1.2, 0.8), pos + Vector3(3.5, 0.7, -3.4), Palette.mat(Palette.PLASTER_2, 0.9))
	var lamp := OmniLight3D.new()
	lamp.position = pos + Vector3(0.0, 3.1, 0.0)
	lamp.light_energy = 1.6
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.omni_range = 12.0
	_world_root.add_child(lamp)
	locations["safe_room"] = pos + Vector3(0.0, 0.2, 0.0)

## Hawker hub: roofed open-sided shared dining with stalls, tables, fans, lights.
func _hawker_block(centre: Vector3) -> void:
	# pavilion slab
	_solid_box(Vector3(70.0, 0.25, 54.0), centre + Vector3(0.0, 0.12, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.92))
	# roof on columns
	for i: int in 7:
		for j: int in 5:
			var cp := centre + Vector3(-30.0 + i * 10.0, 0.0, -22.0 + j * 11.0)
			_cyl(Vector3(0.5, 5.2, 0.5), cp + Vector3(0.0, 2.6, 0.0), Palette.mat(Palette.METAL, 0.5, 0.5))
	_solid_box(Vector3(72.0, 0.5, 56.0), centre + Vector3(0.0, 5.4, 0.0), Palette.mat(Palette.METAL_DARK, 0.7, 0.3))
	_box(Vector3(74.0, 0.2, 12.0), centre + Vector3(0.0, 5.9, -18.0), Palette.mat(Palette.ROOF_TILE, 0.8))
	# stalls: counters, canopies, signboards
	for i: int in 6:
		var sp := centre + Vector3(-27.0 + i * 11.0, 0.0, -20.0)
		_solid_box(Vector3(8.0, 1.05, 3.2), sp + Vector3(0.0, 0.52, 0.0), Palette.mat(Palette.PLASTER, 0.85))
		_box(Vector3(8.4, 0.18, 3.6), sp + Vector3(0.0, 1.12, 0.0), Palette.mat(Palette.METAL, 0.4, 0.6))
		_box(Vector3(8.0, 2.1, 0.12), sp + Vector3(0.0, 2.1, 1.5), Palette.mat(Palette.FRONTAGES[i % Palette.FRONTAGES.size()], 0.85))
		var canopy := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(8.6, 0.1, 2.2)
		canopy.mesh = cm
		canopy.material_override = Palette.mat(Palette.FRONTAGES[(i + 2) % Palette.FRONTAGES.size()], 0.9)
		canopy.position = sp + Vector3(0.0, 3.1, 2.1)
		canopy.rotation_degrees = Vector3(18.0, 0.0, 0.0)
		_world_root.add_child(canopy)
		var sign := _label3d(Palette.SIGN_TEXT[(i + 2) % Palette.SIGN_TEXT.size()], sp + Vector3(0.0, 3.6, 1.3))
		sign.font_size = 40
		sign.pixel_size = 0.012
	# shared dining: tables, stools, bins, tray return
	for i: int in 4:
		for j: int in 3:
			var tp := centre + Vector3(-24.0 + i * 16.0, 0.0, 6.0 + j * 12.0)
			_cyl(Vector3(2.0, 0.12, 2.0), tp + Vector3(0.0, 0.85, 0.0), Palette.mat(Palette.PLASTER_2, 0.8))
			_cyl(Vector3(0.3, 0.85, 0.3), tp + Vector3(0.0, 0.42, 0.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
			for s in 4:
				var ang := TAU * s / 4.0 + 0.6
				_cyl(Vector3(0.55, 0.5, 0.55), tp + Vector3(cos(ang) * 1.5, 0.25, sin(ang) * 1.5), Palette.mat(Palette.PLASTER, 0.85))
		# tray return + bins
		_solid_box(Vector3(3.0, 1.0, 1.0), centre + Vector3(-24.0 + i * 16.0, 0.5, 0.0), Palette.mat(Palette.METAL, 0.5, 0.5))
		_cyl(Vector3(1.0, 1.2, 1.0), centre + Vector3(-30.0 + i * 16.0, 0.6, -2.0), Palette.mat(Palette.METAL_DARK, 0.7, 0.3))
	# ceiling fans
	for i: int in 4:
		var fp := centre + Vector3(-24.0 + i * 16.0, 0.0, 12.0)
		_cyl(Vector3(0.3, 0.6, 0.3), fp + Vector3(0.0, 4.9, 0.0), Palette.mat(Palette.METAL, 0.5, 0.5))
		_box(Vector3(2.6, 0.06, 0.3), fp + Vector3(0.0, 4.55, 0.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
	# string lights
	for i: int in 10:
		var lp := centre + Vector3(-30.0 + i * 7.0, 0.0, -26.0)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		bulb.mesh = sm
		bulb.material_override = Palette.emissive(Palette.SHOP_WARM, 2.0)
		bulb.position = lp + Vector3(0.0, 4.6, 0.0)
		_world_root.add_child(bulb)
	# mission package on a stall counter
	locations["package"] = centre + Vector3(-27.0 + 2 * 11.0, 1.4, -20.0)

## Modern waterfront edge: towers, promenade, skyline.
func _waterfront_block(centre: Vector3) -> void:
	for i: int in 2:
		var pos := centre + Vector3(-34.0 + i * 68.0, 0.0, -30.0)
		var h := 70.0 + i * 18.0
		_solid_box(Vector3(26.0, h, 26.0), pos + Vector3(0.0, h * 0.5, 0.0), Palette.mat(Palette.GLASS, 0.12, 0.6))
		for f in int(h / 4.0):
			_box(Vector3(26.6, 0.35, 26.6), pos + Vector3(0.0, 4.0 + f * 4.0, 0.0), Palette.mat(Palette.METAL, 0.4, 0.7))
		_box(Vector3(28.0, 0.7, 28.0), pos + Vector3(0.0, h + 0.35, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.8))
	# low podium with a skywalk
	_solid_box(Vector3(60.0, 5.0, 16.0), centre + Vector3(0.0, 2.5, 24.0), Palette.mat(Palette.CONCRETE, 0.8))
	_box(Vector3(24.0, 0.4, 3.0), centre + Vector3(0.0, 5.3, 14.0), Palette.mat(Palette.METAL, 0.4, 0.6))
	for i: int in 6:
		_tree(centre + Vector3(-40.0 + i * 16.0, 0.0, 40.0), 1.0)

## Aviation compound: hangar, helipads, perimeter fence.
func _aviation_block(centre: Vector3) -> void:
	# hangar
	_solid_box(Vector3(38.0, 12.0, 24.0), centre + Vector3(-30.0, 6.0, -20.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	var hangar_roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(38.0, 3.0, 24.0)
	hangar_roof.mesh = prism
	hangar_roof.material_override = Palette.mat(Palette.METAL_DARK, 0.6, 0.4)
	hangar_roof.position = centre + Vector3(-30.0, 13.5, -20.0)
	_world_root.add_child(hangar_roof)
	_box(Vector3(14.0, 9.0, 0.2), centre + Vector3(-30.0, 4.5, -8.1), Palette.mat(Palette.METAL_DARK, 0.5, 0.5))
	var hsign := _label3d("AIR SERVICE", centre + Vector3(-30.0, 11.0, -7.9))
	hsign.font_size = 48
	hsign.pixel_size = 0.016
	# helipad (primary)
	_helipad(centre + Vector3(30.0, 0.0, 24.0), 16.0)
	locations["helipad_primary"] = centre + Vector3(30.0, 0.3, 24.0)
	# fence line + windsock
	for i: int in 10:
		_cyl(Vector3(0.18, 2.6, 0.18), centre + Vector3(-60.0 + i * 13.0, 1.3, 56.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	_box(Vector3(130.0, 0.1, 0.1), centre + Vector3(0.0, 2.4, 56.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	_cyl(Vector3(0.16, 6.0, 0.16), centre + Vector3(-56.0, 3.0, 44.0), Palette.mat(Palette.METAL, 0.5, 0.5))
	_box(Vector3(0.3, 0.3, 2.2), centre + Vector3(-56.0, 5.9, 45.0), Palette.mat(Color(0.9, 0.4, 0.15), 0.8))
	for i: int in 4:
		_tree(centre + Vector3(-56.0 + i * 18.0, 0.0, 48.0), 0.9)

func _helipad(pos: Vector3, radius: float) -> void:
	_cyl(Vector3(radius * 2.0, 0.3, radius * 2.0), pos + Vector3(0.0, 0.15, 0.0), Palette.mat(Palette.CONCRETE, 0.9))
	_cyl(Vector3(radius * 1.5, 0.06, radius * 1.5), pos + Vector3(0.0, 0.33, 0.0), Palette.mat(Color(0.16, 0.16, 0.17), 0.9))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.62
	tm.outer_radius = radius * 0.74
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = Palette.emissive(Color(0.95, 0.95, 0.9), 0.9)
	ring.position = pos + Vector3(0.0, 0.34, 0.0)
	_world_root.add_child(ring)
	var h := "H"
	var label := _label3d(h, pos + Vector3(0.0, 0.4, 0.0))
	label.font_size = 120
	label.pixel_size = 0.012
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.modulate = Color(0.95, 0.95, 0.92)

func _mixed_block(centre: Vector3) -> void:
	_shophouse_row(centre + Vector3(-BLOCK / 2.0 + 8.0, 0.0, -BLOCK / 2.0 + 8.0), Vector3(1, 0, 0), 13)
	_shophouse_row(centre + Vector3(-BLOCK / 2.0 + 8.0, 0.0, BLOCK / 2.0 - 8.0), Vector3(1, 0, 0), 13)
	for i in 5:
		_tree(centre + Vector3(-40.0 + i * 20.0, 0.0, 0.0), 1.0)
	_solid_box(Vector3(20.0, 4.0, 14.0), centre + Vector3(20.0, 2.0, 30.0), Palette.mat(Palette.PLASTER_2, 0.9))
	_box(Vector3(21.0, 0.35, 15.0), centre + Vector3(20.0, 4.2, 30.0), Palette.mat(Palette.METAL, 0.6, 0.4))

# ------------------------------------------------------------- water + skyline
func _waterfront_edge() -> void:
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1600.0, 700.0)
	water.mesh = pm
	var wm := Palette.mat(Palette.WATER, 0.08, 0.4)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.albedo_color = Color(0.16, 0.31, 0.36, 0.92)
	water.mesh.material = wm
	water.position = Vector3(0.0, -0.4, PROMENADE_Z - 340.0)
	_world_root.add_child(water)
	# promenade deck + railing
	_solid_box(Vector3(700.0, 0.3, 22.0), Vector3(0.0, 0.15, PROMENADE_Z), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	for i: int in 46:
		_cyl(Vector3(0.12, 1.1, 0.12), Vector3(-340.0 + i * 15.0, 0.85, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_box(Vector3(700.0, 0.08, 0.08), Vector3(0.0, 1.35, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_helipad(Vector3(locations["helipad_secondary"].x, 0.0, locations["helipad_secondary"].z), 11.0)
	for i: int in 8:
		_tree(Vector3(-300.0 + i * 85.0, 0.0, PROMENADE_Z + 6.0), 1.0)
	for i: int in 6:
		_street_lamp(Vector3(-320.0 + i * 128.0, 0.0, PROMENADE_Z + 8.0))

func _background_city() -> void:
	# distant, non-reachable silhouettes — dimensional, not a flat backdrop
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i: int in 70:
		var side := i % 4
		var pos := Vector3.ZERO
		match side:
			0: pos = Vector3(rng.randf_range(-700.0, 700.0), 0.0, -420.0 - rng.randf_range(0.0, 160.0))
			1: pos = Vector3(-430.0 - rng.randf_range(0.0, 140.0), 0.0, rng.randf_range(-400.0, 400.0))
			2: pos = Vector3(430.0 + rng.randf_range(0.0, 140.0), 0.0, rng.randf_range(-400.0, 400.0))
			_: pos = Vector3(rng.randf_range(-700.0, 700.0), 0.0, 400.0 + rng.randf_range(0.0, 160.0))
		var h := rng.randf_range(18.0, 95.0)
		var shade := Color(0.42, 0.44, 0.48).lerp(Color(0.30, 0.33, 0.38), rng.randf())
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(14.0, 34.0), h, rng.randf_range(14.0, 34.0))
		mesh.mesh = bm
		mesh.material_override = Palette.mat(shade, 0.9)
		mesh.position = pos + Vector3(0.0, h * 0.5, 0.0)
		_world_root.add_child(mesh)

# ------------------------------------------------------------------ traffic
func _build_lane_graph() -> void:
	# junction nodes
	for x in X_LINES:
		for z in Z_LINES:
			traffic_nodes.append(Vector3(x, 0.1, z))
	# pedestrian lanes along every kerb band, both sides of every road
	for x in X_LINES:
		for side: float in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for z in Z_LINES:
				pts.append(Vector3(x + side * SIDEWALK, 0.25, z))
			ped_lanes.append(pts)
	for z in Z_LINES:
		for side: float in [-1.0, 1.0]:
			var pts2: Array[Vector3] = []
			for x in X_LINES:
				pts2.append(Vector3(x, 0.25, z + side * SIDEWALK))
			ped_lanes.append(pts2)
	# parked cars along the kerbs of the shophouse streets
	var i := 0
	for x in X_LINES:
		for side: float in [-1.0, 1.0]:
			for j: int in 4:
				var px: float = x + side * (SIDEWALK - 2.0)
				var pz := -240.0 + j * 160.0 + 40.0
				if absf(pz) > 300.0:
					continue
				parked_spots.append({"pos": Vector3(px, 0.3, pz), "heading": 0.0, "kind": ["sedan", "coupe", "van"][i % 3]})
				i += 1

# ------------------------------------------------------------------- props
func _scatter_props() -> void:
	for x in X_LINES:
		for z in Z_LINES:
			for k: int in 2:
				var off := Vector3(-6.0 + k * 12.0, 0.0, 0.0)
				if k == 1:
					off = Vector3(0.0, 0.0, -6.0 + 12.0)
				_street_lamp(Vector3(x, 0.0, z) + off)
	for i: int in 40:
		var pos := Vector3(_rng.randf_range(-310.0, 310.0), 0.0, _rng.randf_range(-310.0, 310.0))
		if _inside_block(pos):
			continue
		_tree(pos, _rng.randf_range(0.8, 1.25))

## True when a point falls on a raised block platform (buildings live there).
func _inside_block(pos: Vector3) -> bool:
	for cx in [-240.0, -80.0, 80.0, 240.0]:
		for cz in [-240.0, -80.0, 80.0, 240.0]:
			if absf(pos.x - cx) < BLOCK * 0.5 - 6.0 and absf(pos.z - cz) < BLOCK * 0.5 - 6.0:
				return true
	return false

func _street_lamp(pos: Vector3) -> void:
	_cyl(Vector3(0.16, 6.0, 0.16), pos + Vector3(0.0, 3.0, 0.0), Palette.mat(Palette.METAL_DARK, 0.5, 0.5))
	_box(Vector3(1.2, 0.14, 0.3), pos + Vector3(0.0, 6.0, 0.0), Palette.mat(Palette.METAL_DARK, 0.5, 0.5))
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.4
	bulb.mesh = sm
	bulb.material_override = Palette.emissive(Palette.SHOP_WARM, 1.8)
	bulb.position = pos + Vector3(0.0, 5.85, 0.0)
	_world_root.add_child(bulb)

func _tree(pos: Vector3, scale: float) -> void:
	var trunk_h := 3.2 * scale
	_cyl(Vector3(0.42 * scale, trunk_h, 0.42 * scale), pos + Vector3(0.0, trunk_h * 0.5, 0.0), Palette.mat(Palette.TRUNK, 0.95))
	# dimensional canopy: several overlapping spheres, not a billboard
	for i: int in 4:
		var ang := TAU * i / 4.0
		var r := 1.5 * scale
		_sphere(Vector3(r * 2.0, r * 1.7, r * 2.0), pos + Vector3(cos(ang) * 0.9 * scale, trunk_h + 0.9 * scale + (0.2 if i % 2 == 0 else 0.0), sin(ang) * 0.9 * scale),
			Palette.mat(Palette.FOLIAGE.lerp(Palette.FOLIAGE_LIGHT, float(i % 2)), 0.95))
	_sphere(Vector3(2.6 * scale, 2.2 * scale, 2.6 * scale), pos + Vector3(0.0, trunk_h + 1.9 * scale, 0.0),
		Palette.mat(Palette.FOLIAGE, 0.95))


# ------------------------------------------------------- junctions & fittings
## Crosswalks, stop lines and signal heads at every intersection (TRAFFIC-01).
func _junctions() -> void:
	var paint := Palette.mat_textured(Palette.PAINT_LINE, "concrete", Vector3(4.0, 1.0, 4.0), 0.8)
	for x in X_LINES:
		for z in Z_LINES:
			for axis in 2:
				for side: float in [-1.0, 1.0]:
					var dir := Vector3(1, 0, 0) if axis == 0 else Vector3(0, 0, 1)
					var centre := Vector3(x, 0.07, z) + dir * (ROAD_HALF + 1.6) * side
					for i: int in 7:
						var offset := (i - 3) * 1.7
						var stripe_pos: Vector3 = centre + Vector3(-dir.z, 0.0, dir.x) * offset
						var size := Vector3(0.55, 0.02, 3.0) if axis == 0 else Vector3(3.0, 0.02, 0.55)
						_box(size, stripe_pos, paint)
					# stop line
					var stop_pos: Vector3 = Vector3(x, 0.07, z) + dir * (ROAD_HALF - 0.4) * side
					var stop_size := Vector3(0.4, 0.02, 6.0) if axis == 0 else Vector3(6.0, 0.02, 0.4)
					_box(stop_size, stop_pos, paint)
			# signal heads on the corners
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_traffic_light(Vector3(x + sx * (ROAD_HALF + 1.4), 0.0, z + sz * (ROAD_HALF + 1.4)))

func _traffic_light(pos: Vector3) -> void:
	_cyl(Vector3(0.16, 3.4, 0.16), pos + Vector3(0.0, 1.7, 0.0), Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3(1.0, 2.0, 1.0), 0.5, 0.6))
	var head := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.95, 0.3)
	head.mesh = bm
	head.material_override = Palette.mat(Palette.METAL_DARK, 0.5, 0.5)
	head.position = pos + Vector3(0.0, 3.4, 0.0)
	_world_root.add_child(head)
	var lamps := [Color(0.95, 0.2, 0.15), Color(0.95, 0.75, 0.2), Color(0.25, 0.9, 0.35)]
	for i: int in 3:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		lamp.mesh = sm
		lamp.material_override = Palette.emissive(lamps[i], 0.6 if i != 2 else 2.4)
		lamp.position = pos + Vector3(0.0, 3.7 - i * 0.3, 0.16)
		_world_root.add_child(lamp)

## Everyday street fittings: bins, benches, planters, bollards, cables, AC units.
func _street_furniture() -> void:
	var metal := Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 2.0, 1.0), 0.55, 0.5)
	var dark := Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3(1.0, 1.0, 1.0), 0.6, 0.4)
	for x in X_LINES:
		for z in Z_LINES:
			# overhead utility cables across the carriageway
			for k: int in 3:
				var cable_z := z - 30.0 + k * 22.0
				var cable := MeshInstance3D.new()
				var cb := BoxMesh.new()
				cb.size = Vector3(22.0, 0.05, 0.05)
				cable.mesh = cb
				cable.material_override = dark
				cable.position = Vector3(x, 7.4, cable_z)
				cable.rotation_degrees = Vector3(0.0, 0.0, 1.5)
				_world_root.add_child(cable)
			# kerbside fittings
			for side: float in [-1.0, 1.0]:
				var kerb := Vector3(x + side * (SIDEWALK - 1.0), 0.0, z + 34.0)
				_cyl(Vector3(0.55, 0.9, 0.55), kerb + Vector3(0.0, 0.45, 0.0), dark)          # bin
				_cyl(Vector3(0.1, 0.9, 0.1), kerb + Vector3(2.2, 0.45, 0.0), metal)            # bollard
				var bench := MeshInstance3D.new()
				var bb := BoxMesh.new()
				bb.size = Vector3(1.8, 0.12, 0.5)
				bench.mesh = bb
				bench.material_override = Palette.mat_textured(Palette.PLASTER, "plaster", Vector3(1.0, 1.0, 1.0), 0.85)
				bench.position = kerb + Vector3(-2.6, 0.55, 1.8)
				_world_root.add_child(bench)
				for lx in [-0.7, 0.7]:
					var leg := MeshInstance3D.new()
					var lb := BoxMesh.new()
					lb.size = Vector3(0.1, 0.55, 0.45)
					leg.mesh = lb
					leg.material_override = dark
					leg.position = bench.position + Vector3(lx, -0.3, 0.0)
					_world_root.add_child(leg)
				var planter := MeshInstance3D.new()
				var pb := BoxMesh.new()
				pb.size = Vector3(1.2, 0.6, 1.2)
				planter.mesh = pb
				planter.material_override = Palette.mat_textured(Palette.CONCRETE, "concrete", Vector3(1.0, 1.0, 1.0), 0.9)
				planter.position = kerb + Vector3(1.6, 0.3, 3.2)
				_world_root.add_child(planter)
				_sphere(Vector3(1.1, 0.9, 1.1), planter.position + Vector3(0.0, 0.7, 0.0), Palette.mat(Palette.FOLIAGE, 0.95))
				# wall-mounted air-con condensers on the flanking facades
				for k: int in 2:
					var ac := MeshInstance3D.new()
					var ab := BoxMesh.new()
					ab.size = Vector3(0.85, 0.6, 0.4)
					ac.mesh = ab
					ac.material_override = Palette.mat_textured(Color(0.62, 0.63, 0.60), "metal", Vector3(1.0, 1.0, 1.0), 0.65, 0.35)
					ac.position = kerb + Vector3(-2.0 + k * 2.6, 4.2, -0.8)
					_world_root.add_child(ac)
				# bus shelter at a few stops
				if int(absf(z)) % 160 == 0:
					_bus_shelter(kerb + Vector3(-1.0, 0.0, 6.0))

func _bus_shelter(pos: Vector3) -> void:
	var metal := Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 1.0, 1.0), 0.5, 0.5)
	for sx in [-1.6, 1.6]:
		_cyl(Vector3(0.12, 2.6, 0.12), pos + Vector3(sx, 1.3, 0.0), metal)
	_box(Vector3(4.0, 0.12, 1.6), pos + Vector3(0.0, 2.7, 0.0), Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3(2.0, 1.0, 1.0), 0.5, 0.5))
	_box(Vector3(3.6, 1.9, 0.08), pos + Vector3(0.0, 1.4, -0.7), Palette.glass())
	_box(Vector3(3.4, 0.1, 0.5), pos + Vector3(0.0, 0.6, 0.2), Palette.mat_textured(Palette.PLASTER_2, "plaster", Vector3(1.0, 1.0, 1.0), 0.85))

# ------------------------------------------------------------------ helpers
func _solid_box(size: Vector3, pos: Vector3, material: Material, yaw: float = 0.0) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = yaw
	_world_root.add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	return mesh

func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = material
	mesh.position = pos
	_world_root.add_child(mesh)
	return mesh

func _cyl(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size.x * 0.5
	cm.bottom_radius = size.z * 0.5
	cm.height = size.y
	cm.radial_segments = 12
	mesh.mesh = cm
	mesh.material_override = material
	mesh.position = pos
	_world_root.add_child(mesh)
	return mesh

func _sphere(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size.x * 0.5
	sm.height = size.y
	sm.radial_segments = 12
	sm.rings = 6
	mesh.mesh = sm
	mesh.material_override = material
	mesh.position = pos
	_world_root.add_child(mesh)
	return mesh

func _label3d(text: String, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	l.double_sided = false
	l.modulate = Color(0.95, 0.93, 0.87)
	l.outline_size = 8
	l.outline_modulate = Color(0.08, 0.07, 0.06, 0.9)
	_world_root.add_child(l)
	return l
