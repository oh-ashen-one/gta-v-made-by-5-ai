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
	"helipad_secondary": Vector3(0.0, 0.2, -337.0),
	"delivery": Vector3(96.0, 0.2, -337.0),
	"hawker": Vector3(-80.0, 0.2, -80.0),
}

var _rng := RandomNumberGenerator.new()
var _world_root: Node3D
var _collision_root: StaticBody3D
var _asset_collision_cache: Dictionary = {}
## Footprints already occupied by authored structures. Block infill consults
## this so new plots never intersect the heritage rows, HDB slabs, mission hall
## or aviation buildings they are meant to surround.
var _reserved: Array[Rect2] = []

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
	_block_plots()
	var interior_data: Dictionary = InteriorDetail.build(_world_root, locations["safe_room"] - Vector3(0,.2,0))
	locations["convenience_shop"] = interior_data["convenience_shop"]
	locations["workshop"] = interior_data["workshop"]
	_waterfront_edge()
	_background_city()
	_perimeter()
	_build_lane_graph()
	_scatter_props()
	_landscape()

# ---------------------------------------------------------------- environment
func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://assets/authored/shaders/tropical_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.54, 0.58, 0.70)
	env.ambient_light_energy = 0.44
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# The manager's review of the aerial found "washed-out whites/pinks". The
	# previous 1.02 exposure plus 0.58 ambient plus 0.42 glow stacked into the
	# highlight shoulder on pale HDB facades. Pull all three back.
	env.tonemap_exposure = 0.92
	# Warm tropical dusk haze. The approved concepts are late-afternoon: a low
	# sun, long shadows and gold bounce, not an overcast midday wash. The first
	# wave-3 pass used 0.0011 and smothered the district in peach dust; this is
	# light aerial perspective only.
	env.fog_enabled = true
	env.fog_light_color = Color(0.80, 0.78, 0.74)
	env.fog_density = 0.00024
	env.fog_sky_affect = 0.18
	env.fog_aerial_perspective = 0.10
	env.ssao_enabled = true
	env.ssao_radius = 2.1
	env.ssao_intensity = 2.0
	env.ssao_light_affect = 0.45
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.10
	env.glow_hdr_threshold = 1.12
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	# Low western sun, ~16 deg elevation, so the street gets long raking light
	# and readable shade under the five-foot ways (ART-07).
	sun.rotation_degrees = Vector3(-16.3, 62.0, 0.0)
	sun.light_energy = 2.35
	sun.light_color = Color(1.0, 0.80, 0.58)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_bias = 0.025
	sun.shadow_normal_bias = 1.4
	sun.shadow_blur = 1.15
	add_child(sun)

	var fill := DirectionalLight3D.new()
	# Sky fill from the opposite side keeps shadowed frontage readable instead
	# of crushing it to black.
	fill.rotation_degrees = Vector3(-24.0, -128.0, 0.0)
	fill.light_energy = 0.26
	fill.light_color = Color(0.62, 0.72, 0.92)
	fill.shadow_enabled = false
	add_child(fill)

	var bounce := DirectionalLight3D.new()
	# Warm ground bounce, aimed upward: shaded five-foot ways and arcades pick
	# up pavement light instead of reading as flat blue-grey walls.
	bounce.rotation_degrees = Vector3(58.0, 40.0, 0.0)
	bounce.light_energy = 0.20
	bounce.light_color = Color(1.0, 0.80, 0.60)
	bounce.shadow_enabled = false
	add_child(bounce)

# -------------------------------------------------------------- ground/roads
func _ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	_world_root.add_child(ground)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1500.0, 4.0, 1100.0)
	mesh.mesh = box
	mesh.material_override = Palette.mat_textured(Color(0.42, 0.41, 0.38), "concrete", Vector3(70.0, 1.0, 70.0), 0.95)
	mesh.position = Vector3(0.0, -2.0, 200.0)
	ground.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1500.0, 4.0, 1100.0)
	shape.shape = bs
	shape.position = Vector3(0.0, -2.0, 200.0)
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
			_solid_box(Vector3(BLOCK, 0.16, BLOCK), Vector3(cx, 0.08, cz), Palette.mat_textured(Palette.CONCRETE_LIGHT, "pavers", Vector3.ONE, 0.92))
	# Kerb stones define the carriageway edge; without them the road and the
	# pavement merged into one grey field at street level.
	var kerb := Palette.mat_textured(Color(0.72, 0.70, 0.65), "concrete", Vector3.ONE, 0.88)
	for x in X_LINES:
		for side: float in [-1.0, 1.0]:
			_box(Vector3(0.30, 0.20, 760.0), Vector3(x + side * (ROAD_HALF + 0.15), 0.10, 0.0), kerb)
	for z in Z_LINES:
		for side: float in [-1.0, 1.0]:
			_box(Vector3(760.0, 0.20, 0.30), Vector3(0.0, 0.10, z + side * (ROAD_HALF + 0.15)), kerb)
	_medians()

## Planted central medians. The manager's review of the street still called the
## carriageway "an almost-empty endless road": a 760 m unbroken ribbon of asphalt
## with nothing in the middle. Singapore arterial roads carry planted medians, and
## they also break the vanishing point. Segments stop short of every junction so
## turning traffic and the authored drive are unaffected.
func _medians() -> void:
	var median_kerb := Palette.mat_textured(Color(0.70, 0.68, 0.63), "concrete", Vector3.ONE, 0.88)
	var median_turf := Palette.mat_textured(Color(0.24, 0.33, 0.16), "soil", Vector3.ONE, 0.95)
	var span := 160.0 - 2.0 * (ROAD_HALF + 6.0)   # clear of both junction mouths
	for x in X_LINES:
		for k in range(0, 4):
			var cz := -240.0 + k * 160.0
			var centre := Vector3(x, 0.0, cz)
			_box(Vector3(1.6, 0.26, span), centre + Vector3(0.0, 0.13, 0.0), median_kerb)
			_box(Vector3(1.2, 0.30, span - 1.0), centre + Vector3(0.0, 0.30, 0.0), median_turf)
			# low clipped shrubs only: median trees sit on the road centreline and
			# would put a real trunk collider on the mission avenue centreline
			var count := int(span / 9.0)
			for i in count:
				var zz: float = cz - span * 0.5 + 4.5 + i * 9.0
				_sphere(Vector3(1.0, 0.75, 1.0), Vector3(x, 0.52, zz), Palette.mat(Palette.FOLIAGE_LIGHT, 0.95))
	for z in Z_LINES:
		for k in range(0, 4):
			var cx := -240.0 + k * 160.0
			var centre := Vector3(cx, 0.0, z)
			_box(Vector3(span, 0.26, 1.6), centre + Vector3(0.0, 0.13, 0.0), median_kerb)
			_box(Vector3(span - 1.0, 0.30, 1.2), centre + Vector3(0.0, 0.30, 0.0), median_turf)
			var count := int(span / 9.0)
			for i in count:
				var xx: float = cx - span * 0.5 + 4.5 + i * 9.0
				_sphere(Vector3(1.0, 0.75, 1.0), Vector3(xx, 0.52, z), Palette.mat(Palette.FOLIAGE_LIGHT, 0.95))

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
	_shophouse_row(centre+Vector3(60,0,-42.4),Vector3(0,0,1),8)
	_shophouse_row(centre+Vector3(-60,0,42.4),Vector3(0,0,-1),8)
	# The interior is planned by _block_plots(): rear service yards, back
	# extensions, courtyards and parking courts fill the former empty platform.
	if AssetLibrary.has_asset("service_clutter_clean.glb"):
		for i: int in 3:
			var clutter := AssetLibrary.instantiate("service_clutter_clean.glb", _world_root)
			if clutter != null:
				clutter.position = centre + Vector3(-44.0 + i * 9.0, 0.0, 30.0)
				clutter.rotation.y = randf_range(-0.6, 0.6)

func _shophouse_row(origin: Vector3, dir: Vector3, count: int) -> void:
	# A block perimeter is a continuous row with outward-facing five-foot ways.
	# The provider module's actual facade faces +X, not -Z as wave one assumed.
	var unit_w := 10.6
	var yaw := atan2(-dir.z, dir.x)
	var front_dir := Vector3(0,0,-1).rotated(Vector3.UP,yaw)
	var plaster := Palette.mat_textured(Palette.PLASTER,"plaster",Vector3.ONE,.9)
	var sign_mat := Palette.mat(Color(.055,.11,.1),.75)
	for i in count:
		var pos: Vector3 = origin + dir * (unit_w * .5+i*unit_w)
		var frontage: Color = Palette.FRONTAGES[(i+int(absf(origin.x)/25))%Palette.FRONTAGES.size()]
		var module := AssetLibrary.instantiate("shophouse_clean.glb",_world_root)
		if module != null:
			module.position=pos
			module.rotation.y=yaw+PI*.5
			module.scale.y=.94+float((i/3)%3)*.04
			AssetLibrary.tint(module,frontage)
		# Building envelope and rear wall are solid; arcade remains walkable.
		_collision_box(Vector3(10.1,7.3,9.5),pos+Vector3(0,7.6,0),yaw)
		_collision_box(Vector3(10.1,3.7,6.5),pos+Vector3(0,1.85,0)+Vector3(0,0,1.4).rotated(Vector3.UP,yaw),yaw)
		# A sheltered tiled footway physically joins the modules.
		var path := _box(Vector3(unit_w,.08,3.3),pos+front_dir*6.2+Vector3(0,.10,0),Palette.mat_textured(Color(.65,.68,.62),"pavers",Vector3.ONE,.86))
		path.rotation.y=yaw
		var board := _box(Vector3(7.2,.65,.16),pos+front_dir*5.27+Vector3(0,3.45,0),sign_mat)
		board.rotation.y=yaw
		var sign := _label3d(Palette.SIGN_TEXT[(i+int(absf(origin.z)/12))%Palette.SIGN_TEXT.size()],pos+front_dir*5.39+Vector3(0,3.46,0))
		sign.rotation.y=yaw+PI
		sign.font_size=48
		sign.pixel_size=.009
		sign.outline_size=2
		# A recessed shop interior. The manager's review called the previous
		# full-width emissive panel a "solid glowing storefront"; a lightbox is
		# not a shop. This builds a dark room with a lit ceiling strip, so the
		# arcade reads as depth with a warm source rather than a flat white card.
		var back_wall := _box(Vector3(6.6, 2.4, 0.12), pos + front_dir * 2.55 + Vector3(0, 1.35, 0), Palette.mat(Color(0.15, 0.12, 0.10), 0.92))
		back_wall.rotation.y = yaw
		var ceiling_strip := _box(Vector3(5.6, 0.16, 0.5), pos + front_dir * 3.3 + Vector3(0, 2.52, 0), Palette.emissive(Color(1.0, 0.74, 0.44), 1.15))
		ceiling_strip.rotation.y = yaw
		# Vertical mullions break the opening into bays instead of one blank panel.
		for m in 3:
			var mullion := _box(Vector3(0.10, 2.4, 0.14), pos + front_dir * 4.0 + Vector3(0, 1.35, 0) + dir * (-2.2 + m * 2.2), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
			mullion.rotation.y = yaw
		# Counter line at the shop mouth, so the opening has a readable scale.
		if i % 2 == 0:
			var counter := _box(Vector3(5.4, 0.95, 0.55), pos + front_dir * 3.55 + Vector3(0, 0.48, 0), Palette.mat(Color(0.34, 0.24, 0.16), 0.85))
			counter.rotation.y = yaw
		# Canvas awning over every other shopfront, in the heritage palette.
		if i % 2 == 0:
			var awning := _box(Vector3(7.4, 0.12, 1.9), pos + front_dir * 6.1 + Vector3(0, 3.15, 0), Palette.mat(Palette.FRONTAGES[(i + 3) % Palette.FRONTAGES.size()].darkened(0.18), 0.85))
			awning.rotation.y = yaw
			awning.rotation.x = deg_to_rad(-12.0)
		# Street-level clutter. The manager's review called the pavements sparse;
		# bare five-foot ways read as a model, not a working street. Kept sparse
		# per shop so the node and draw-call cost stays bounded.
		if i % 4 == 0:
			var crate := _box(Vector3(0.95, 0.52, 0.72), pos + front_dir * 5.9 + dir * 3.1 + Vector3(0, 0.26, 0), Palette.mat(Color(0.54, 0.37, 0.21), 0.9))
			crate.rotation.y = yaw
			var crate2 := _box(Vector3(0.82, 0.44, 0.62), pos + front_dir * 5.9 + dir * 3.1 + Vector3(0, 0.73, 0), Palette.mat(Color(0.45, 0.30, 0.17), 0.9))
			crate2.rotation.y = yaw
		if i % 6 == 2:
			var aboard := _box(Vector3(0.95, 1.25, 0.09), pos + front_dir * 5.5 + dir * -2.7 + Vector3(0, 0.62, 0), Palette.mat(Color(0.13, 0.12, 0.11), 0.9))
			aboard.rotation.y = yaw
			aboard.rotation.x = deg_to_rad(-9.0)
		# Warm lanterns have modeled holders and small visible emitters.
		for side in [-1.0,1.0]:
			var lp: Vector3 = pos+front_dir*5.65+dir*side*4.2+Vector3(0,2.7,0)
			_box(Vector3(.22,.42,.22),lp,Palette.mat(Palette.METAL_DARK,.5,.45))
			_box(Vector3(.16,.27,.16),lp,Palette.emissive(Palette.SHOP_WARM,1.6))
		if i%2==0:
			var pot:=AssetLibrary.instantiate("planter_clean.glb",_world_root)
			if pot!=null: pot.position=pos+front_dir*7.2+dir*3.7; pot.scale=Vector3.ONE*1.2
			_authored("fern.glb",pos+front_dir*7.2+dir*3.7+Vector3(0,.65,0),yaw,Vector3.ONE*.6)
		if i%3==1:
			var ac:=AssetLibrary.instantiate("ac_unit_clean.glb",_world_root)
			if ac!=null: ac.position=pos-front_dir*5.2+Vector3(0,4.3,0); ac.rotation.y=yaw

func _collision_box(size: Vector3, pos: Vector3, yaw: float=0) -> void:
	var body:=StaticBody3D.new()
	body.position=pos; body.rotation.y=yaw
	body.collision_layer=1; body.collision_mask=0
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new(); box.size=size; shape.shape=box
	body.add_child(shape); _world_root.add_child(body)
	if size.y > 2.5:
		_reserve(size, pos)

## Public housing: tall slab blocks, void-deck ground floor, courtyard, carpark.
func _hdb_block(centre: Vector3) -> void:
	var slabs := [
		{"pos": Vector3(-38.0, 0.0, -34.0), "rot": 0.0, "h": 58.0},
		{"pos": Vector3(38.0, 0.0, -34.0), "rot": 0.0, "h": 52.0},
		{"pos": Vector3(-30.0, 0.0, 40.0), "rot": 90.0, "h": 46.0},
	]
	# Per-block variation. The manager's review called the housing "clone HDB
	# grids": every slab was the same provider mesh at the same albedo. Each
	# block now gets its own height offset, footprint scale and paint tint.
	var block_key := int(absf(centre.x) * 0.25 + absf(centre.z) * 0.5) % 6
	for s in slabs:
		var pos: Vector3 = centre + s["pos"]
		var h: float = s["h"] + float(block_key - 2) * 4.0
		var rot: float = s["rot"]
		var size := Vector3(22.0, h, 13.0)
		if rot == 90.0:
			size = Vector3(13.0, h, 22.0)
		var used_provider := false
		if AssetLibrary.has_asset("hdb_slab_clean.glb"):
			var slab := AssetLibrary.instantiate("hdb_slab_clean.glb", _world_root)
			if slab != null:
				# the cleaned module is 42 m tall; scale it to this slab
				var unit_h := 42.0
				slab.position = pos + Vector3(0.0, 0.0, 0.0)
				slab.scale = Vector3.ONE * (h / unit_h)
				if rot == 90.0:
					slab.rotation.y = PI * 0.5
				AssetLibrary.tint(slab, Palette.HDB_TINTS[block_key])
				_asset_collision(slab)
				used_provider = true
		if not used_provider:
			_solid_box(size, pos + Vector3(0.0, 3.6 + h * 0.5, 0.0), Palette.mat_textured(Palette.CONCRETE, "concrete", Vector3(5.0, 7.0, 3.0), 0.85))
		# void-deck: open ground floor with columns (skipped for the generated slab)
		if not used_provider:
			for cx: int in 3:
				for cz: int in 3:
					_solid_box(Vector3(0.7, 3.6, 0.7), pos + Vector3(-size.x * 0.4 + cx * size.x * 0.4, 1.8, -size.z * 0.4 + cz * size.z * 0.4),
						Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
			# lift lobby + sheltered link
			_solid_box(Vector3(4.2, 3.0, 5.0), pos + Vector3(0.0, 1.5, size.z * 0.5 + 2.0), Palette.mat(Palette.PLASTER_2, 0.9))
			_box(Vector3(4.4, 0.25, 3.0), pos + Vector3(0.0, 3.2, size.z * 0.5 + 2.6), Palette.mat(Palette.METAL, 0.6, 0.4))
		# window bands (the generated slab carries its own facade)
		var floors := int(h / 3.4) if not used_provider else 0
		for f in floors:
			var wy := 6.4 + f * 3.4
			for w: int in 5:
				var off := -size.x * 0.36 + w * size.x * 0.18
				var win_pos := pos + Vector3(off, wy, size.z * 0.5 + 0.06)
				if rot == 90.0:
					win_pos = pos + Vector3(size.x * 0.5 + 0.06, wy, off)
				_box(Vector3(1.5, 1.3, 0.12), win_pos, Palette.mat(Palette.GLASS, 0.25, 0.25))
		# roof parapet + tank
		if not used_provider:
			_box(size + Vector3(0.0, 0.6, 0.0), pos + Vector3(0.0, 3.6 + h + 0.3, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
			_cyl(Vector3(2.0, 2.4, 2.0), pos + Vector3(size.x * 0.25, 3.6 + h + 1.8, 0.0), Palette.mat(Palette.METAL, 0.7, 0.3))
	# planted courtyard with a community table
	_solid_box(Vector3(40.0, 0.3, 34.0), centre + Vector3(0.0, 0.15, 2.0), Palette.mat(Color(0.32, 0.40, 0.26), 0.95))
	for i: int in 8:
		if centre.x < -200 and centre.z > -100 and centre.z < 0 and i == 2:
			continue # the safe-room roof occupies this courtyard edge
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
		_safe_room(centre + Vector3(0.0, 0.30, 10.0))

func _safe_room(pos: Vector3) -> void:
	_solid_box(Vector3(14.0, 0.2, 10.0), pos + Vector3(0.0, 0.1, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(14.0, 3.4, 0.4), pos + Vector3(0.0, 1.7, side * 5.0), Palette.mat(Palette.PLASTER, 0.9))
	# doorway on the -X side, facing the street, so the room can be entered and left
	_solid_box(Vector3(0.4, 3.4, 2.5), pos + Vector3(-7.0, 1.7, -3.75), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(0.4, 3.4, 2.5), pos + Vector3(-7.0, 1.7, 3.75), Palette.mat(Palette.PLASTER, 0.9))
	_box(Vector3(0.5, 0.4, 3.4), pos + Vector3(-7.0, 3.5, 0.0), Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 1.0, 2.0), 0.5, 0.5))
	_solid_box(Vector3(14.0, 0.3, 10.0), pos + Vector3(0.0, 3.5, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	_solid_box(Vector3(0.4, 3.4, 10.0), pos + Vector3(7.0, 1.7, 0.0), Palette.mat(Palette.PLASTER, 0.9))
	var lamp := OmniLight3D.new()
	lamp.position = pos + Vector3(0.0, 3.1, 0.0)
	lamp.light_energy = 1.6
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.omni_range = 12.0
	_world_root.add_child(lamp)
	# visible ceiling fixture so the light has a source
	_box(Vector3(1.2, 0.16, 0.5), pos + Vector3(0.0, 3.38, 0.0), Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 1.0, 1.0), 0.5, 0.5))
	_box(Vector3(1.0, 0.06, 0.34), pos + Vector3(0.0, 3.28, 0.0), Palette.emissive(Color(1.0, 0.92, 0.78), 2.6))
	# daylight spilling in through the doorway
	var door_light := SpotLight3D.new()
	door_light.position = pos + Vector3(-6.4, 2.6, 0.0)
	door_light.rotation_degrees = Vector3(-14.0, 90.0, 0.0)
	door_light.light_energy = 4.0
	door_light.light_color = Color(1.0, 0.92, 0.80)
	door_light.spot_range = 16.0
	door_light.spot_angle = 55.0
	door_light.spot_attenuation = 1.2
	door_light.shadow_enabled = true
	_world_root.add_child(door_light)
	locations["safe_room"] = pos + Vector3(0.0, 0.2, 0.0)
	locations["safe_room_exit"] = pos + Vector3(-12.0, 0.2, 0.0)

## Hawker hub: roofed open-sided shared dining with stalls, tables, fans, lights.
func _hawker_block(centre: Vector3) -> void:
	_shophouse_row(centre+Vector3(-63.6,0,-60),Vector3(1,0,0),12)
	# Bring the public hall to the street edge: a sheltered civic frontage,
	# with its garden/service court behind it rather than a forty-metre void.
	centre += Vector3(-30,0,0)
	locations["hawker"] = centre
	# pavilion slab
	_solid_box(Vector3(70.0, 0.25, 54.0), centre + Vector3(0.0, 0.12, 0.0), Palette.mat_textured(Palette.CONCRETE_LIGHT, "pavers", Vector3.ONE, 0.92))
	# Original DCC-authored pitched terracotta pavilion with exposed trusses.
	_authored("hawker_pavilion.glb", centre)
	# stalls: counters, canopies, signboards
	for i: int in 6:
		var sp := centre + Vector3(-27.0 + i * 11.0, 0.25, -20.0)
		var used_counter := false
		if AssetLibrary.has_asset("hawker_counter_refined.glb"):
			var counter := AssetLibrary.instantiate("hawker_counter_refined.glb", _world_root)
			if counter != null:
				counter.position = sp + Vector3(0.0, 0.0, 0.6)
				counter.scale = Vector3(2.0, 1.1, 1.2)
				counter.rotation.y = PI
				used_counter = true
		if not used_counter:
			_solid_box(Vector3(8.0, 1.05, 3.2), sp + Vector3(0.0, 0.52, 0.0), Palette.mat(Palette.PLASTER, 0.85))
		if AssetLibrary.has_asset("player_clean.glb"):
			var vendor := AssetLibrary.instantiate("player_clean.glb", _world_root)
			if vendor != null:
				vendor.position = sp + Vector3(0.6, 0.0, -1.5)
				vendor.rotation.y = PI
				AssetLibrary.tint(vendor, Palette.FRONTAGES[(i + 1) % Palette.FRONTAGES.size()])
		var sign := _label3d(["RICE & CURRY","SOUP NOODLES","KAYA TOAST","TEA & COFFEE","FRESH JUICE","GRILLED SATAY"][i], sp + Vector3(0.0, 3.1, 1.3))
		sign.font_size = 40
		sign.pixel_size = 0.012
	# shared dining: tables, stools, bins, tray return
	for i: int in 12:
		for j: int in 8:
			var tp := centre + Vector3(-27.5 + i * 5.0, 0.25, -11.0 + j * 4.5)
			if i%4==1 and j in [3,5,7]:
				for meal in 3:
					var angle: float=meal*TAU/3.0
					_authored("hawker_meal.glb",tp+Vector3(cos(angle)*.32,.755,sin(angle)*.32),-angle)
			var provider_table := false
			if AssetLibrary.has_asset("hawker_table_refined.glb"):
				var table := AssetLibrary.instantiate("hawker_table_refined.glb", _world_root)
				if table != null:
					table.position = tp
					table.scale = Vector3.ONE
					provider_table = true
			if not provider_table:
				_cyl(Vector3(2.0, 0.12, 2.0), tp + Vector3(0.0, 0.85, 0.0), Palette.mat(Palette.PLASTER_2, 0.8))
				_cyl(Vector3(0.3, 0.85, 0.3), tp + Vector3(0.0, 0.42, 0.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
			for s in (0 if provider_table else 4):
				var ang := TAU * s / 4.0 + 0.6
				_cyl(Vector3(0.55, 0.5, 0.55), tp + Vector3(cos(ang) * 1.5, 0.25, sin(ang) * 1.5), Palette.mat(Palette.PLASTER, 0.85))
		# tray return + bins
		_solid_box(Vector3(3.0, 1.0, 1.0), centre + Vector3(-28.0 + i * 8.0, 0.5, -25.0), Palette.mat(Palette.METAL, 0.5, 0.5))
		_cyl(Vector3(1.0, 1.2, 1.0), centre + Vector3(-29.0 + i * 8.0, 0.6, -24.0), Palette.mat(Palette.METAL_DARK, 0.7, 0.3))
	# warm practical lighting under the hawker roof
	for i: int in 6:
		var practical := OmniLight3D.new()
		practical.position = centre + Vector3(-30.0 + i * 12.0, 4.4, 6.0)
		practical.light_energy = 1.5
		practical.light_color = Color(1.0, 0.84, 0.62)
		practical.omni_range = 16.0
		_world_root.add_child(practical)
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
	# mission package in the open aisle in front of the stalls, so it can be
	# walked to and picked up without climbing over the counter
	locations["package"] = centre + Vector3(-5.0, 0.25, -8.0)

## Modern waterfront edge: towers, promenade, skyline.
func _waterfront_block(centre: Vector3) -> void:
	for i: int in 2:
		var pos := centre + Vector3(-34.0 + i * 68.0, 0.0, -30.0)
		var h := 70.0 + i * 18.0
		# Curtain-wall grid instead of a bare glass box: the skyline is the
		# backdrop for every street view and was reading as flat blue slabs.
		_solid_box(Vector3(26.0, h, 26.0), pos + Vector3(0.0, h * 0.5, 0.0), Palette.facade("office"))
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
	# ground staff (static figures from the generated officer set)
	if AssetLibrary.has_asset("officer_clean.glb"):
		for i: int in 2:
			var guard := AssetLibrary.instantiate("officer_clean.glb", _world_root)
			if guard != null:
				guard.position = centre + Vector3(18.0 + i * 6.0, 0.0, 10.0 + i * 3.0)
				guard.rotation.y = -1.1
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
	if AssetLibrary.has_asset("airfield_clutter_clean.glb"):
		for i: int in 3:
			var crate := AssetLibrary.instantiate("airfield_clutter_clean.glb", _world_root)
			if crate != null:
				crate.position = centre + Vector3(-10.0 + i * 5.0, 0.0, -34.0 + i * 4.0)
				crate.rotation.y = randf_range(-0.5, 0.5)
	# fence line + windsock
	for i: int in 10:
		_cyl(Vector3(0.18, 2.6, 0.18), centre + Vector3(-60.0 + i * 13.0, 1.3, 56.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	_box(Vector3(130.0, 0.1, 0.1), centre + Vector3(0.0, 2.4, 56.0), Palette.mat(Palette.METAL, 0.6, 0.4))
	_cyl(Vector3(0.16, 6.0, 0.16), centre + Vector3(-56.0, 3.0, 44.0), Palette.mat(Palette.METAL, 0.5, 0.5))
	_box(Vector3(0.3, 0.3, 2.2), centre + Vector3(-56.0, 5.9, 45.0), Palette.mat(Color(0.9, 0.4, 0.15), 0.8))
	for i: int in 4:
		_tree(centre + Vector3(-56.0 + i * 18.0, 0.0, 48.0), 0.9)

func _helipad(pos: Vector3, radius: float) -> void:
	var body:=StaticBody3D.new();body.position=pos+Vector3(0,.15,0)
	var shape:=CollisionShape3D.new();var cylinder:=CylinderShape3D.new()
	cylinder.radius=radius;cylinder.height=.3;shape.shape=cylinder
	body.add_child(shape);_world_root.add_child(body)
	_cyl(Vector3(radius * 2.0, 0.3, radius * 2.0), pos + Vector3(0.0, 0.15, 0.0), Palette.mat(Palette.CONCRETE, 0.9))
	_cyl(Vector3(radius * 1.5, 0.06, radius * 1.5), pos + Vector3(0.0, 0.33, 0.0), Palette.mat(Color(0.16, 0.16, 0.17), 0.9))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.62
	tm.outer_radius = radius * 0.74
	tm.rings = 24
	tm.ring_segments = 8
	ring.mesh = tm
	ring.material_override = Palette.mat(Color(0.92, 0.90, 0.74), 0.85)
	ring.position = pos + Vector3(0.0, 0.38, 0.0)
	ring.scale.y = 0.015
	_world_root.add_child(ring)
	var h := "H"
	var label := _label3d(h, pos + Vector3(0.0, 0.4, 0.0))
	label.font_size = 120
	label.pixel_size = 0.05
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.modulate = Color(0.95, 0.95, 0.92)

func _mixed_block(centre: Vector3) -> void:
	_shophouse_row(centre + Vector3(-BLOCK / 2.0 + 8.0, 0.0, -BLOCK / 2.0 + 8.0), Vector3(1, 0, 0), 13)
	_shophouse_row(centre + Vector3(-BLOCK / 2.0 + 8.0, 0.0, BLOCK / 2.0 - 8.0), Vector3(1, 0, 0), 13)

# ------------------------------------------------------- block interior grain
## Wave 2 left each 144 m block as one flat paver platform with buildings only
## on its edge, which is what read as "giant empty paved lots". Each block is
## now subdivided by a cross of service lanes into four 46 m plots, and every
## plot gets a real use: courtyard, garden, workshop yard, parking court or a
## mid-block building. Authored structures register footprints in `_reserved`,
## so infill only lands where nothing else already stands.
func _reserve(size: Vector3, pos: Vector3) -> void:
	_reserved.append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))

func _is_free(rect: Rect2) -> bool:
	for other in _reserved:
		if rect.intersects(other, true):
			return false
	return true

func _block_plots() -> void:
	var apron := Palette.mat_textured(Color(0.36, 0.35, 0.33), "concrete", Vector3.ONE, 0.94)
	for col in 4:
		for row in 4:
			var centre := Vector3(-240.0 + col * 160.0, 0.16, -240.0 + row * 160.0)
			var kit := _kit_for(col, row)
			# Cross service lanes are painted everywhere; they are the block's
			# back-of-house spine and stop the interior reading as one field.
			var tarmac := Palette.mat_textured(Palette.ASPHALT_EDGE, "asphalt", Vector3.ONE, 0.95)
			_box(Vector3(120.0, 0.07, 6.0), centre + Vector3(0.0, 0.035, 0.0), tarmac)
			_box(Vector3(6.0, 0.07, 120.0), centre + Vector3(0.0, 0.035, 0.0), tarmac)
			_box(Vector3(120.0, 0.05, 0.16), centre + Vector3(0.0, 0.075, -3.1), Palette.mat(Palette.PAINT_LINE, 0.8))
			_box(Vector3(0.16, 0.05, 120.0), centre + Vector3(-3.1, 0.075, 0.0), Palette.mat(Palette.PAINT_LINE, 0.8))
			# A service apron rings the plots between them and the frontage.
			_box(Vector3(118.0, 0.05, 118.0), centre + Vector3(0.0, 0.025, 0.0), apron)
			if kit in ["hawker", "aviation"]:
				if kit == "hawker":
					# The pavilion occupies the west two-thirds; the east strip is
					# planned explicitly so the busiest precinct is not left as a
					# paved field. Offsets stay clear of the pedestrian lanes at
					# x=-10 and z=-10/-150 and of the mission package aisle.
					for spec in [[Vector3(40, 0, -45), 1], [Vector3(40, 0, 0), 0], [Vector3(40, 0, 45), 3]]:
						var offset: Vector3 = spec[0]
						var hp: Vector3 = centre + offset
						match int(spec[1]):
							0: _plot_courtyard(hp, Rect2())
							1: _plot_garden(hp, Rect2())
							3: _plot_parking(hp, Rect2())
				continue
			for i in 2:
				for j in 2:
					var p := centre + Vector3(-26.0 + i * 52.0, 0.0, -26.0 + j * 52.0)
					var rect := Rect2(p.x - 23.0, p.z - 23.0, 46.0, 46.0)
					var pick := (col * 5 + row * 11 + i * 3 + j * 7) % 5
					if kit == "hdb":
						pick = [1, 3, 0, 4][pick % 4]
					elif kit == "shophouse":
						pick = [0, 2, 4, 2][pick % 4]
					elif kit == "waterfront":
						pick = [0, 4, 1, 3][pick % 4]
					match pick:
						0: _plot_courtyard(p, rect)
						1: _plot_garden(p, rect)
						2: _plot_workshop(p, rect)
						3: _plot_parking(p, rect)
						_: _plot_backblock(p, rect)

## Low rear extensions along plot edges. Real blocks are built up to their
## boundaries; a 46 m open court surrounded by nothing is what still read as a
## paved lot after the first pass.
func _plot_edge_buildings(p: Vector3, skip: Array = []) -> void:
	# Three segments per edge with varied heights and small gaps, so a plot
	# boundary reads as a row of back extensions rather than one blank wall.
	var edges := [
		{"edge": 0, "axis": "x", "off": -20.0, "depth": 5.4},
		{"edge": 1, "axis": "x", "off": 20.0, "depth": 5.4},
		{"edge": 2, "axis": "z", "off": -20.0, "depth": 5.4},
		{"edge": 3, "axis": "z", "off": 20.0, "depth": 5.4},
	]
	var heights := [[4.6, 6.1, 3.8], [5.4, 4.2, 6.4], [3.9, 5.8, 4.9], [6.2, 4.4, 5.2]]
	for e in edges:
		if int(e["edge"]) in skip:
			continue
		var axis := String(e["axis"])
		var off: float = e["off"]
		var depth: float = e["depth"]
		for seg in 3:
			var h: float = heights[int(e["edge"])][seg]
			var along := -15.0 + seg * 15.0
			var size: Vector3
			var pos: Vector3
			if axis == "x":
				size = Vector3(14.0, h, depth)
				pos = p + Vector3(along, 0.0, off)
			else:
				size = Vector3(depth, h, 14.0)
				pos = p + Vector3(off, 0.0, along)
			if not _is_free(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)):
				continue
			_infill_building(size, pos, "shopback")
			_reserve(size, pos + Vector3(0.0, size.y * 0.5, 0.0))

func _plot_courtyard(p: Vector3, rect: Rect2) -> void:
	_box(Vector3(46.0, 0.06, 46.0), p + Vector3(0.0, 0.03, 0.0), Palette.mat_textured(Color(0.47, 0.45, 0.41), "pavers", Vector3.ONE, 0.9))
	_plot_edge_buildings(p)
	# low planted beds at the corners, a communal table and string-light poles
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var bed := p + Vector3(sx * 11.0, 0.0, sz * 11.0)
			_box(Vector3(8.0, 0.45, 8.0), bed + Vector3(0.0, 0.22, 0.0), Palette.mat_textured(Palette.CONCRETE_LIGHT, "concrete", Vector3.ONE, 0.9))
			_sphere(Vector3(6.8, 1.4, 6.8), bed + Vector3(0.0, 0.9, 0.0), Palette.mat(Palette.FOLIAGE, 0.95))
	if not _is_free(Rect2(p.x - 4.0, p.z - 4.0, 8.0, 8.0)):
		return
	_cyl(Vector3(2.6, 0.14, 2.6), p + Vector3(0.0, 0.85, 0.0), Palette.mat(Palette.PLASTER_2, 0.8))
	_cyl(Vector3(0.35, 0.85, 0.35), p + Vector3(0.0, 0.42, 0.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
	for s in 5:
		var ang := TAU * s / 5.0
		_cyl(Vector3(0.55, 0.5, 0.55), p + Vector3(cos(ang) * 2.0, 0.25, sin(ang) * 2.0), Palette.mat(Palette.PLASTER, 0.85))
	for s in 4:
		var ang2 := TAU * s / 4.0 + 0.4
		_cyl(Vector3(0.14, 5.2, 0.14), p + Vector3(cos(ang2) * 9.0, 2.6, sin(ang2) * 9.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
	for s in 10:
		var t := float(s) / 9.0
		_sphere(Vector3(0.26, 0.26, 0.26), p + Vector3(-9.0 + t * 18.0, 5.05 - sin(t * PI) * 0.5, 9.0), Palette.emissive(Palette.SHOP_WARM, 2.2))

func _plot_garden(p: Vector3, rect: Rect2) -> void:
	_box(Vector3(46.0, 0.06, 46.0), p + Vector3(0.0, 0.03, 0.0), Palette.mat_textured(Color(0.26, 0.34, 0.17), "soil", Vector3.ONE, 0.95))
	_box(Vector3(46.0, 0.05, 3.4), p + Vector3(0.0, 0.06, 0.0), Palette.mat_textured(Color(0.52, 0.50, 0.46), "pavers", Vector3.ONE, 0.9))
	_box(Vector3(3.4, 0.05, 46.0), p + Vector3(0.0, 0.06, 0.0), Palette.mat_textured(Color(0.52, 0.50, 0.46), "pavers", Vector3.ONE, 0.9))
	_plot_edge_buildings(p, [0, 1])
	for k in 4:
		var off := Vector3(-14.0 + (k % 2) * 28.0, 0.0, -14.0 + (k / 2) * 28.0)
		if _is_free(Rect2(p.x + off.x - 3.0, p.z + off.z - 3.0, 6.0, 6.0)):
			_tree(p + off, 0.95 + _rng.randf() * 0.3)
	for k in 6:
		var a := TAU * k / 6.0
		_authored("fern.glb", p + Vector3(cos(a) * 9.0, 0.09, sin(a) * 9.0), a, Vector3.ONE * 0.8)
	_box(Vector3(1.8, 0.12, 0.5), p + Vector3(6.0, 0.55, -6.0), Palette.mat_textured(Palette.PLASTER, "plaster", Vector3.ONE, 0.85))

func _plot_workshop(p: Vector3, rect: Rect2) -> void:
	_box(Vector3(46.0, 0.06, 46.0), p + Vector3(0.0, 0.03, 0.0), Palette.mat_textured(Color(0.24, 0.24, 0.25), "asphalt", Vector3.ONE, 0.95))
	var sheds := [
		{"size": Vector3(30.0, 7.2, 15.0), "off": Vector3(-4.0, 0.0, -12.0), "kind": "workshop"},
		{"size": Vector3(14.0, 5.4, 12.0), "off": Vector3(13.0, 0.0, 6.0), "kind": "shopback"},
	]
	for shed in sheds:
		var size: Vector3 = shed["size"]
		var pos: Vector3 = p + shed["off"]
		var rect2 := Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)
		if not _is_free(rect2):
			continue
		_infill_building(size, pos, String(shed["kind"]))
		_reserve(size, pos + Vector3(0.0, size.y * 0.5, 0.0))
	# service yard clutter: pallets, drums, a parked van bay
	if AssetLibrary.has_asset("service_clutter_clean.glb"):
		for k in 2:
			var clutter := AssetLibrary.instantiate("service_clutter_clean.glb", _world_root)
			if clutter != null:
				clutter.position = p + Vector3(-14.0 + k * 6.0, 0.0, 10.0)
				clutter.rotation.y = _rng.randf_range(-0.6, 0.6)
	for k in 3:
		_cyl(Vector3(0.7, 0.9, 0.7), p + Vector3(8.0 + k * 1.1, 0.45, 8.0), Palette.mat(Color(0.30, 0.42, 0.34), 0.7, 0.3))
	_box(Vector3(5.0, 0.12, 5.0), p + Vector3(-14.0, 0.4, 9.0), Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3.ONE, 0.6, 0.4))

func _plot_parking(p: Vector3, rect: Rect2) -> void:
	_box(Vector3(46.0, 0.06, 46.0), p + Vector3(0.0, 0.03, 0.0), Palette.mat_textured(Color(0.18, 0.18, 0.19), "asphalt", Vector3.ONE, 0.96))
	_plot_edge_buildings(p, [0])
	var paint := Palette.mat(Palette.PAINT_LINE, 0.8)
	# two rows of perpendicular bays with a drive aisle between them
	for side: float in [-1.0, 1.0]:
		var row_z := side * 14.0
		for bay in 6:
			var bx := -15.0 + bay * 6.0
			_box(Vector3(0.14, 0.03, 5.0), p + Vector3(bx, 0.075, row_z), paint)
		_box(Vector3(36.0, 0.03, 0.14), p + Vector3(0.0, 0.075, row_z - 2.5), paint)
		if _is_free(Rect2(p.x - 14.0, p.z + row_z - 2.4, 30.0, 5.0)):
			for bay2 in 2:
				var spot := p + Vector3(-9.0 + bay2 * 15.0 + _rng.randf_range(-0.6, 0.6), 0.14, row_z)
				parked_spots.append({"pos": spot, "heading": 0.0 if side > 0 else PI, "kind": ["sedan", "coupe", "van"][(int(absf(p.x)) + bay2) % 3]})
	_box(Vector3(0.5, 2.6, 0.5), p + Vector3(19.0, 1.3, -19.0), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))
	_box(Vector3(1.4, 0.7, 0.5), p + Vector3(19.0, 2.9, -19.0), Palette.mat(Color(0.14, 0.20, 0.36), 0.7))

func _plot_backblock(p: Vector3, rect: Rect2) -> void:
	_box(Vector3(46.0, 0.06, 46.0), p + Vector3(0.0, 0.03, 0.0), Palette.mat_textured(Color(0.44, 0.42, 0.38), "pavers", Vector3.ONE, 0.92))
	_plot_edge_buildings(p, [1])
	var size := Vector3(34.0, 11.0 + float(int(absf(p.x) + absf(p.z)) % 4) * 3.0, 22.0)
	var pos := p + Vector3(0.0, 0.0, -4.0)
	if not _is_free(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)):
		return
	_infill_building(size, pos, "shopback" if size.y < 17.0 else "hdb")
	_reserve(size, pos + Vector3(0.0, size.y * 0.5, 0.0))
	# ground-floor awning and a service door, so the block has a frontage
	_box(Vector3(35.0, 0.16, 2.6), pos + Vector3(0.0, 3.3, size.z * 0.5 + 1.3), Palette.mat_textured(Palette.METAL, "metal", Vector3(2.0, 1.0, 1.0), 0.55, 0.4))
	_box(Vector3(2.2, 2.6, 0.14), pos + Vector3(-6.0, 1.3, size.z * 0.5 + 0.05), Palette.mat(Palette.METAL_DARK, 0.5, 0.5))
	for k in 3:
		_cyl(Vector3(0.12, 3.3, 0.12), pos + Vector3(-11.0 + k * 11.0, 1.65, size.z * 0.5 + 2.5), Palette.mat(Palette.METAL_DARK, 0.6, 0.4))

## One textured mid-block building: real collision, parapet, roof clutter.
func _infill_building(size: Vector3, pos: Vector3, kind: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0.0, size.y * 0.5, 0.0)
	body.collision_layer = 1
	body.collision_mask = 0
	_world_root.add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = Palette.facade(kind)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	# A darker roof deck than the walls: from above, a district of bright parapets
	# read as flat pale parcels. Real roofs are weathered grey with equipment.
	_box(size + Vector3(0.7, 0.55, 0.7), pos + Vector3(0.0, size.y + 0.2, 0.0), Palette.mat(Color(0.40, 0.39, 0.37), 0.95))
	if size.y > 9.0:
		_cyl(Vector3(1.8, 2.0, 1.8), pos + Vector3(size.x * 0.22, size.y + 1.4, -size.z * 0.2), Palette.mat(Palette.METAL, 0.7, 0.3))
		_box(Vector3(3.0, 0.9, 2.4), pos + Vector3(-size.x * 0.25, size.y + 0.7, size.z * 0.22), Palette.mat(Color(0.52, 0.52, 0.50), 0.9))

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
	_solid_box(Vector3(700.0, 0.3, 22.0), Vector3(0.0, 0.15, PROMENADE_Z), Palette.mat_textured(Palette.CONCRETE_LIGHT,"pavers",Vector3.ONE,0.9))
	for i: int in 46:
		_cyl(Vector3(0.12, 1.1, 0.12), Vector3(-340.0 + i * 15.0, 0.85, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_box(Vector3(700.0, 0.08, 0.08), Vector3(0.0, 1.35, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_helipad(Vector3(locations["helipad_secondary"].x, 0.0, locations["helipad_secondary"].z), 11.0)
	for i: int in 8:
		_tree(Vector3(-300.0 + i * 85.0, 0.0, PROMENADE_Z + 6.0), 1.0)
	for i: int in 6:
		_street_lamp(Vector3(-320.0 + i * 128.0, 0.0, PROMENADE_Z + 8.0))

func _background_city() -> void:
	# Existing side/back context remains dimensional, with its existing shadows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 64:
		var side := i % 4
		if side == 0: continue
		var p := Vector3.ZERO
		match side:
			1: p=Vector3(-440-rng.randf_range(0,90),0,-410+(i/4)*54)
			2: p=Vector3(440+rng.randf_range(0,90),0,-410+(i/4)*54)
			_: p=Vector3(-620+(i/4)*82,0,435+rng.randf_range(0,90))
		_authored("skyline_%d.glb"%posmod(i,4),p,rng.randf_range(-.08,.08),Vector3(1,rng.randf_range(.55,1.20),1))
	# Three staggered clusters on the existing far shore. Lower near-water
	# blocks and taller rear blocks overlap in depth instead of isolated plinths.
	# This is inaccessible context, not additional playable city area.
	var groups: Array = [[],[],[],[]]
	for row in 3:
		for cluster in 3:
			for col in 8:
				var variant: int = 2 if row == 0 and col % 3 != 0 else (row+cluster+col)%4
				var x: float = -720+cluster*490+col*54+rng.randf_range(-7,7)+row*13
				var z: float = -711-row*130+rng.randf_range(-18,18)
				var height_scale: float = rng.randf_range(.48,.73) if row == 0 else rng.randf_range(.70,1.22)+row*.08
				var width_scale: float = rng.randf_range(.90,1.18)
				var basis := Basis(Vector3.UP,rng.randf_range(-.07,.07)).scaled(Vector3(width_scale,height_scale,width_scale))
				groups[variant].append(Transform3D(basis,Vector3(x,0,z)))
	for variant in 4:
		var tints := [Color(0.86, 0.84, 0.80), Color(0.60, 0.68, 0.76), Color(0.94, 0.88, 0.78), Color(0.72, 0.76, 0.80)]
		_batch_background("res://assets/authored/skyline_%d.glb"%variant,groups[variant],tints[variant])

func _batch_background(path: String, transforms: Array, tint: Color = Color.WHITE) -> void:
	var packed: PackedScene = load(path)
	var source: Node = packed.instantiate()
	var parts: Array[Dictionary] = []
	_background_mesh_parts(source,Transform3D.IDENTITY,parts)
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=part["mesh"]
		mm.instance_count=transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i,transforms[i]*part["transform"])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh=mm
		# One duplicated material per skyline variant: the far shore needs
		# variety, and four extra materials cost nothing next to 2000 instances.
		var override: Material = part["override"]
		if override is StandardMaterial3D:
			var dup := (override as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.albedo_color = dup.albedo_color.lerp(tint, 0.55)
			override = dup
		instance.material_override=override
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world_root.add_child(instance)
	source.free()

func _background_mesh_parts(node: Node, parent_transform: Transform3D, result: Array[Dictionary]) -> void:
	var local := parent_transform
	if node is Node3D: local=parent_transform*node.transform
	if node is MeshInstance3D and node.mesh != null:
		result.append({"mesh":node.mesh,"transform":local,"override":node.material_override})
	for child in node.get_children():
		_background_mesh_parts(child,local,result)


func _perimeter() -> void:
	# One continuous far shoreline anchors the background skyline across a bay.
	var ground_mat:=Palette.mat_textured(Color(.33,.38,.28),"soil",Vector3.ONE,.95)
	_box(Vector3(1700,8,700),Vector3(0,-4,-970),ground_mat)
	_box(Vector3(1700,2,18),Vector3(0,-.7,-624),Palette.mat_textured(Palette.CONCRETE,"concrete",Vector3.ONE,.92))
	_box(Vector3(1680,.08,16),Vector3(0,.05,-657),Palette.mat_textured(Palette.ASPHALT,"asphalt",Vector3.ONE,.85))
	for i in 34:
		_tree(Vector3(-790+i*48,.1,-640),.8)
	# A treed far shoreline. The manager's aerial review called the horizon
	# "abrupt"; the bay previously ended where open water met a flat plane.
	# This band gives the far shore a real edge with canopy and low roofs.
	for i in 44:
		_tree(Vector3(-800.0 + i * 37.0, 0.15, -652.0), 0.95 + float(i % 4) * 0.12)
	for i in 16:
		_box(Vector3(26.0, 7.0 + float(i % 3) * 3.0, 14.0), Vector3(-760.0 + i * 100.0, 3.5, -712.0),
			Palette.mat_textured(Color(0.52, 0.50, 0.47), "concrete", Vector3.ONE, 0.92))
	# The authored district has visible physical edges. Aircraft can fly over
	# the same geometry; ordinary walking/driving meets real railings.
	for i in 50:
		var t: float=-367.5+i*15
		for side in [-1.0,1.0]:
			var p:=Vector3(side*375,.1,t)
			_authored("boundary_railing.glb",p,PI*.5)
			_collision_box(Vector3(.25,2.4,15),p+Vector3(0,1.2,0))
		var south:=Vector3(t,.1,375)
		_authored("boundary_railing.glb",south)
		_collision_box(Vector3(15,2.4,.25),south+Vector3(0,1.2,0))
	# Waterfront rails have deliberate pad-side pedestrian access, but stop a
	# normal sprint from falling into the bay.
	for i in 46:
		var p:=Vector3(-337.5+i*15,.3,-348.5)
		_authored("boundary_railing.glb",p,0,Vector3(1,.55,1))
		_collision_box(Vector3(15,1.35,.25),p+Vector3(0,.68,0))

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
	# Parked cars along both kerb families. Wave 2 only lined the north-south
	# streets, so the east-west frontages read as permanently empty.
	var i := 0
	for x in X_LINES:
		for side: float in [-1.0, 1.0]:
			for j: int in 5:
				var px: float = x + side * (SIDEWALK - 2.0)
				var pz := -240.0 + j * 120.0 + 40.0
				if absf(pz) > 300.0:
					continue
				parked_spots.append({"pos": Vector3(px, 0.3, pz), "heading": 0.0, "kind": ["sedan", "coupe", "van"][i % 3]})
				i += 1
	for z in Z_LINES:
		for side: float in [-1.0, 1.0]:
			for j: int in 5:
				var pz2: float = z + side * (SIDEWALK - 2.0)
				var px2 := -240.0 + j * 120.0 + 60.0
				if absf(px2) > 300.0:
					continue
				parked_spots.append({"pos": Vector3(px2, 0.3, pz2), "heading": PI * 0.5, "kind": ["sedan", "coupe", "van"][i % 3]})
				i += 1

# ------------------------------------------------------------------- props
func _scatter_props() -> void:
	for x in X_LINES:
		for z in Z_LINES:
			# Wave 2 offset the second lamp only in Z, which left it on the
			# centreline of the north-south carriageway (FV-07: "lamp on the
			# marked carriageway"). Both lamps now sit on opposite junction
			# corners, clear of both roads.
			for k: int in 2:
				var sx: float = -1.0 if k == 0 else 1.0
				_street_lamp(Vector3(x, 0.0, z) + Vector3(sx * 10.5, 0.0, -10.5))
	# Tree locations are authored in _landscape. The inherited random scatter
	# put trees in live lanes; real trunk collision made that defect observable.

## True when a point falls on a raised block platform (buildings live there).
func _inside_block(pos: Vector3) -> bool:
	for cx in [-240.0, -80.0, 80.0, 240.0]:
		for cz in [-240.0, -80.0, 80.0, 240.0]:
			if absf(pos.x - cx) < BLOCK * 0.5 - 6.0 and absf(pos.z - cz) < BLOCK * 0.5 - 6.0:
				return true
	return false

func _street_lamp(pos: Vector3) -> void:
	var used_provider := false
	if AssetLibrary.has_asset("street_lamp_clean.glb"):
		var lamp_model := AssetLibrary.instantiate("street_lamp_clean.glb", _world_root)
		if lamp_model != null:
			lamp_model.position = pos
			used_provider = true
	if not used_provider:
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
	var tree := _authored("rain_tree.glb", pos, _rng.randf_range(-PI, PI), Vector3.ONE * scale)
	if tree == null:
		return
	# Trunk collision only: leaf envelopes never become invisible walls.
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, 2.4 * scale, 0)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.45 * scale
	cylinder.height = 4.8 * scale
	shape.shape = cylinder
	body.add_child(shape)
	_world_root.add_child(body)

func _authored(file: String, pos: Vector3, yaw: float = 0.0, asset_scale: Vector3 = Vector3.ONE) -> Node3D:
	var path := "res://assets/authored/" + file
	if not ResourceLoader.exists(path):
		return null
	var node: Node3D = (load(path) as PackedScene).instantiate()
	_world_root.add_child(node)
	node.position = pos
	node.rotation.y = yaw
	node.scale = asset_scale
	return node

func _landscape() -> void:
	var turf := Palette.mat_textured(Color(0.24, 0.32, 0.16), "soil", Vector3.ONE, 0.95)
	# Block interiors are now planned by _block_plots(); painting another turf
	# slab over them would z-fight and re-create the flat field this wave
	# removed. Only street verges and the promenade planting live here.
	for road in [-160.0,0.0,160.0]:
		for block in [-240.0,-80.0,80.0,240.0]:
			for side in [-1.0,1.0]:
				for j in 3:
					var p := Vector3(road+side*14, .23, block-47+j*47)
					_tree(p,.8+_rng.randf()*.2)
					_box(Vector3(4.0,.12,5.4),p+Vector3(0,.04,0),turf)
					for k in 2:
						_authored("fern.glb",p+Vector3(side*.9,.12,-1.4+k*2.8),j+k,Vector3.ONE*.65)
	for j in 10:
		_authored("palm.glb",Vector3(-290+j*62,.2,PROMENADE_Z+6),j*.7,Vector3.ONE)

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
					_traffic_light(Vector3(x + sx * (ROAD_HALF + 1.4), 0.0, z + sz * (ROAD_HALF + 1.4)), 0 if sx*sz>0 else 1)

func _traffic_light(pos: Vector3, axis: int = 0) -> void:
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
		lamp.add_to_group("traffic_lamps")
		lamp.set_meta("signal_axis",axis)
		lamp.set_meta("lamp_index",i)
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
				var planter_pos := kerb + Vector3(1.6, 0.0, 3.2)
				var used_planter := false
				if AssetLibrary.has_asset("planter_clean.glb"):
					var planter := AssetLibrary.instantiate("planter_clean.glb", _world_root)
					if planter != null:
						planter.position = planter_pos
						used_planter = true
				if not used_planter:
					var planter_box := MeshInstance3D.new()
					var pb := BoxMesh.new()
					pb.size = Vector3(1.2, 0.6, 1.2)
					planter_box.mesh = pb
					planter_box.material_override = Palette.mat_textured(Palette.CONCRETE, "concrete", Vector3(1.0, 1.0, 1.0), 0.9)
					planter_box.position = planter_pos + Vector3(0.0, 0.3, 0.0)
					_world_root.add_child(planter_box)
				_sphere(Vector3(1.1, 0.9, 1.1), planter_pos + Vector3(0.0, 0.8, 0.0), Palette.mat(Palette.FOLIAGE, 0.95))
				# wall-mounted air-con condensers on the flanking facades
				for k: int in 2:
					if AssetLibrary.has_asset("ac_unit_clean.glb"):
						var ac_model := AssetLibrary.instantiate("ac_unit_clean.glb", _world_root)
						if ac_model != null:
							ac_model.position = kerb + Vector3(-2.0 + k * 2.6, 4.2, -0.8)
							continue
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
	if size.y > 2.5:
		_reserve(size, pos)
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

func _asset_collision(node: Node) -> void:
	# Imported housing includes real raised plinths, steps and void-deck
	# columns. Collision must follow that geometry instead of an invisible
	# flat ground below it; cache the immutable shape across instances.
	if node is MeshInstance3D and node.mesh != null:
		var id: int = node.mesh.get_instance_id()
		if not _asset_collision_cache.has(id):
			_asset_collision_cache[id]=node.mesh.create_trimesh_shape()
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		var shape:=CollisionShape3D.new();shape.shape=_asset_collision_cache[id]
		body.add_child(shape);node.add_child(body)
	for child in node.get_children():
		if not child is StaticBody3D: _asset_collision(child)
