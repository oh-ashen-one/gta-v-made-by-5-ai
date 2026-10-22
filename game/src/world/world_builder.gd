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
## Kerbside parking sits wholly on the carriageway. Wave 4 used SIDEWALK - 2.0
## (8.0 m), which put each parked car astride the 16 cm block-platform edge.
const KERB_PARK_OFFSET := ROAD_HALF - 1.35
## Opening composition (WORLD-03 opening-view acceptance, wave 5).
const OPENING_ROW_X := -180.0
const PLAYER_START := Vector3(-171.0, 0.45, -22.0)
const PLAYER_START_YAW_DEG := -8.0
## Slightly raised opening look so the SkyPark clears the objective card.
const PLAYER_START_PITCH := -0.02
## Wave A (skyline): the grove moved west and its layout tightened so it stands
## clear of the Marina Bay Sands silhouette from the street vista and promenade.
const GROVE_POS := Vector3(-80.0, 0.16, -262.0)
const MBS_POS := Vector3(-118.0, 0.0, -705.0)
## Wave A: the MBS GLB is authored at true scale (curved legs, 300 m SkyPark).
const MBS_SCALE := Vector3.ONE
## Wave A: moved east of the MBS podium, under the SkyPark cantilever side,
## so the lotus no longer sits behind the Supertree crowns in photo_06 or
## against the west tower in photo_16.
const ASM_POS := Vector3(80.0, 0.0, -640.0)
## Wave A: moved west so the wheel sits inside photo_06_aerial_district and
## photo_16 without touching the SkyPark cantilever or the background towers.
const FLYER_POS := Vector3(210.0, 0.0, -700.0)
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

## Bay water, seawalls, boats and the Merlion jet (water piece).
var bay: BayWater
var _rng := RandomNumberGenerator.new()
var _world_root: Node3D
var _collision_root: StaticBody3D
var _asset_collision_cache: Dictionary = {}
## Footprints already occupied by authored structures. Block infill consults
## this so new plots never intersect the heritage rows, HDB slabs, mission hall
## or aviation buildings they are meant to surround.
var _reserved: Array[Rect2] = []
## Rooftop dressing for infill and HDB roofs, flushed in _background_city().
var _roof_kit := RoofKit.new()
## Skyline round 2 stats for the self-test (materials used, towers over water).
var skyline_stats := {}
## Practical lights and fixtures (street lamps, arcades, void decks, hawker).
var _lighting := Lighting.new()

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
	_lighting.root = _world_root

	_environment()
	_ground()
	_roads()
	_junctions()
	_street_furniture()
	_build_grid()
	_opening_signage()
	var interior_data: Dictionary = InteriorDetail.build(_world_root, locations["safe_room"] - Vector3(0,.2,0))
	locations["convenience_shop"] = interior_data["convenience_shop"]
	locations["workshop"] = interior_data["workshop"]
	_reserve(Vector3(28.0, 8.0, 32.0), InteriorDetail.SHOP + Vector3(0.0, 0.0, 6.0))
	_reserve(Vector3(34.0, 8.0, 32.0), InteriorDetail.WORKSHOP + Vector3(0.0, 0.0, 5.0))
	_reserve(Vector3(38.0, 8.0, 22.0), locations["safe_room"] + Vector3(-6.0, 0.0, 0.0))
	_block_plots()
	_waterfront_edge()
	_background_city()
	_perimeter()
	_far_shore_landmarks()
	locations["player_start"] = PLAYER_START
	_build_lane_graph()
	_kerb_markings()
	_scatter_props()
	_landscape()
	_lighting.finish()
	_batch_static_primitives()

# ---------------------------------------------------------------- environment
## Sky, sun, fog, tonemap and grade live in Lighting (src/world/lighting.gd).
func _environment() -> void:
	Lighting.build_environment(self)

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
			# driving C2: the planted bed is solid (critic: cars drove through it)
			_collision_box(Vector3(1.6, 0.9, span), centre + Vector3(0.0, 0.45, 0.0))
			# planting is StreetDressing's median bed (lighting r4: the smooth
			# green spheres read as placeholder domes, critic A3)
	for z in Z_LINES:
		for k in range(0, 4):
			var cx := -240.0 + k * 160.0
			var centre := Vector3(cx, 0.0, z)
			_box(Vector3(span, 0.26, 1.6), centre + Vector3(0.0, 0.13, 0.0), median_kerb)
			_box(Vector3(span - 1.0, 0.30, 1.2), centre + Vector3(0.0, 0.30, 0.0), median_turf)
			_collision_box(Vector3(span, 0.9, 1.6), centre + Vector3(0.0, 0.45, 0.0))

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
	# Northern blocks (row 0) keep their heritage frontage on the -160 street;
	# _block_plots() fills the bayside interior. Wave 4 put a Supertree Grove in
	# each of these blocks; wave 5 consolidates one grove beside the opening
	# sightline (see _waterfront_block) instead of two procedural clones.
	if centre.z < -200.0:
		_shophouse_row(centre + Vector3(BLOCK / 2.0 - 8.0, 0.0, BLOCK / 2.0 - 8.0), Vector3(-1, 0, 0), 13)
		return
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
		_lighting.arcade_bay(pos, yaw, front_dir)
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
		var ceiling_strip := _box(Vector3(5.6, 0.16, 0.5), pos + front_dir * 3.3 + Vector3(0, 2.52, 0), Palette.emissive(Color(1.0, 0.74, 0.44), 2.4))
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
				_lighting.void_deck(slab)
				_reserve(size + Vector3(16.0, 0.0, 16.0), pos)
				_roof_kit.add_hdb_roof(pos, h, rot == 90.0)
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
	_reserve(Vector3(106.0, 10.0, 44.0), centre + Vector3(-16.0, 0.0, -30.0))
	_reserve(Vector3(52.0, 6.0, 44.0), centre + Vector3(0.0, 0.0, 4.0))
	_reserve(Vector3(34.0, 14.0, 28.0), centre + Vector3(34.0, 0.0, 50.0))
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
		# Wave 5 opening street: a heritage shophouse row with its five-foot way
		# faces the hawker hall across the x=-160 road, with the HDB slabs rising
		# behind it -- the CONCEPT-01 arrangement, looking north to the bay.
		_shophouse_row(Vector3(OPENING_ROW_X, 0.16, -151.3), Vector3(0, 0, 1), 11)
		_reserve(Vector3(17.0, 12.0, 118.0), Vector3(OPENING_ROW_X - 1.0, 0.0, -93.0))

func _safe_room(pos: Vector3) -> void:
	_solid_box(Vector3(14.0, 0.2, 10.0), pos + Vector3(0.0, 0.1, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	# South wall (+Z) is full height; North wall (-Z) and East wall (+X) have a
	# panoramic verandah window on the north-east corner so the starting camera
	# immediately looks out onto the HDB void deck, tropical canopy, Supertree
	# Grove and Marina Bay Sands while preserving the notice board on the west half.
	_solid_box(Vector3(14.0, 3.4, 0.4), pos + Vector3(0.0, 1.7, 5.0), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(8.8, 3.4, 0.4), pos + Vector3(-2.6, 1.7, -5.0), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(5.2, 0.95, 0.4), pos + Vector3(4.4, 0.48, -5.0), Palette.mat(Palette.PLASTER, 0.9))
	# doorway on the -X side, facing the street, so the room can be entered and left
	_solid_box(Vector3(0.4, 3.4, 2.5), pos + Vector3(-7.0, 1.7, -3.75), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(0.4, 3.4, 2.5), pos + Vector3(-7.0, 1.7, 3.75), Palette.mat(Palette.PLASTER, 0.9))
	_box(Vector3(0.5, 0.4, 3.4), pos + Vector3(-7.0, 3.5, 0.0), Palette.mat_textured(Palette.METAL, "metal", Vector3(1.0, 1.0, 2.0), 0.5, 0.5))
	_solid_box(Vector3(14.0, 0.3, 10.0), pos + Vector3(0.0, 3.5, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.9))
	_solid_box(Vector3(0.4, 3.4, 5.2), pos + Vector3(7.0, 1.7, 2.4), Palette.mat(Palette.PLASTER, 0.9))
	_solid_box(Vector3(0.4, 0.95, 4.8), pos + Vector3(7.0, 0.48, -2.6), Palette.mat(Palette.PLASTER, 0.9))
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
	_lighting.hawker_hall(centre)
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

## Modern waterfront edge (WORLD-02 #4, WORLD-03). The west block is a bayside
## garden around the Supertree Grove; the east block keeps contemporary towers.
## Marina Bay Sands, the ArtScience Museum and the Singapore Flyer stand across
## the bay on the far shore (_far_shore_landmarks), as in CONCEPT-03.
func _waterfront_block(centre: Vector3) -> void:
	if centre.x < 0.0:
		var grove_pos := GROVE_POS
		_reserve(Vector3(128.0, 50.0, 124.0), centre)
		var lawn := Palette.mat_textured(Color(0.25, 0.36, 0.17), "soil", Vector3.ONE, 0.95)
		_box(Vector3(126.0, 0.10, 118.0), centre + Vector3(0.0, 0.06, 0.0), lawn)
		var pavers := Palette.mat_textured(Palette.CONCRETE_LIGHT, "pavers", Vector3.ONE, 0.9)
		_box(Vector3(5.0, 0.12, 118.0), centre + Vector3(0.0, 0.08, 0.0), pavers)
		_box(Vector3(126.0, 0.12, 5.0), centre + Vector3(0.0, 0.08, 34.0), pavers)
		_authored("supertree_grove.glb", grove_pos, 0.0, Vector3.ONE)
		# Planted trunk colliders only: the crowns stay open sky for flight.
		for tree_off in [Vector3(0, 0, 0), Vector3(-15.4, 0, -4.9), Vector3(15.4, 0, -3.5), Vector3(-9.8, 0, 11.9), Vector3(10.5, 0, 12.6), Vector3(-21.7, 0, 7.7), Vector3(21.0, 0, 9.1)]:
			_collision_box(Vector3(7.0, 12.0, 7.0), grove_pos + tree_off + Vector3(0.0, 6.0, 0.0))
		locations["supertree_grove"] = grove_pos
		for i: int in 6:
			_tree(centre + Vector3(-48.0 + i * 18.0, 0.0, 50.0), 1.05)
		# East edge only: west-edge canopies would sit on the opening view's
		# line to the Marina Bay Sands towers (sightline probe, wave 5).
		for i: int in 4:
			_tree(centre + Vector3(60.0, 0.0, -40.0 + i * 24.0), 0.95)
	else:
		# Curtain-wall office towers: the near-shore commercial edge.
		for i: int in 2:
			var pos := centre + Vector3(-34.0 + i * 68.0, 0.0, -30.0)
			var h := 70.0 + i * 18.0
			# Wave A (skyline): shared curtain-wall shader instead of the dotted sheet.
			var tower_mat := LandmarkLooks.material_for("near_shore_tower_%d" % i) as ShaderMaterial
			# Round 2: lobby base and plant-screen crown on these near towers too.
			tower_mat.set_shader_parameter("legacy_base", pos.y)
			tower_mat.set_shader_parameter("legacy_height", h)
			_solid_box(Vector3(26.0, h, 26.0), pos + Vector3(0.0, h * 0.5, 0.0), tower_mat)
			for f in int(h / 4.0):
				_box(Vector3(26.6, 0.35, 26.6), pos + Vector3(0.0, 4.0 + f * 4.0, 0.0), Palette.mat(Palette.METAL, 0.4, 0.7))
			_box(Vector3(28.0, 0.7, 28.0), pos + Vector3(0.0, h + 0.35, 0.0), Palette.mat(Palette.CONCRETE_LIGHT, 0.8))
		_solid_box(Vector3(60.0, 5.0, 16.0), centre + Vector3(0.0, 2.5, 24.0), Palette.mat(Palette.CONCRETE, 0.8))
		_box(Vector3(24.0, 0.4, 3.0), centre + Vector3(0.0, 5.3, 14.0), Palette.mat(Palette.METAL, 0.4, 0.6))
		for i: int in 6:
			_tree(centre + Vector3(-40.0 + i * 16.0, 0.0, 40.0), 1.0)

## Far shore of the bay (distant scenery reachable only by air; collision so the
## helicopter cannot pass through). Marina Bay Sands sits just east of the x=-160
## avenue axis so the opening street (whose heritage row hides everything west of
## the axis) and the promenade both frame all three towers and the SkyPark; the ArtScience lotus sits at the water's edge to its west and the
## Singapore Flyer to the east. Scale follows real proportions (towers ~180 m,
## SkyPark ~260 m long, Flyer ~160 m).
func _far_shore_landmarks() -> void:
	# Round 4: grey granite pavers; the warm CONCRETE_LIGHT read as a brown
	# dirt strip under the far-shore trees from the aerial views (critic A3).
	var plaza := Palette.mat_textured(Color(0.56, 0.57, 0.56), "pavers", Vector3.ONE, 0.9)
	var turf := Palette.mat_textured(Color(0.24, 0.33, 0.17), "soil", Vector3.ONE, 0.95)
	_box(Vector3(920.0, 0.30, 70.0), Vector3(-20.0, 0.15, -668.0), plaza)
	_box(Vector3(920.0, 0.20, 160.0), Vector3(-20.0, 0.10, -783.0), turf)
	# The far shore is landable ground for the helicopter (WORLD-06).
	_collision_box(Vector3(1700.0, 2.0, 700.0), Vector3(0.0, -1.0, -970.0))
	var mbs := MBS_POS
	_authored("marina_bay_sands.glb", mbs, 0.0, MBS_SCALE)
	# Towers, SkyPark (cantilever east) and podium of the true-scale model.
	_collision_box(Vector3(232.0, 194.0, 30.0), mbs + Vector3(-6.5, 97.0, 0.0))
	_collision_box(Vector3(305.0, 12.0, 40.0), mbs + Vector3(32.5, 197.0, 0.0))
	_collision_box(Vector3(300.0, 14.0, 20.0), mbs + Vector3(20.0, 7.0, 27.0))
	locations["marina_bay_sands"] = mbs
	var asm := ASM_POS
	_authored("artscience_museum.glb", asm, deg_to_rad(12.0), Vector3.ONE * 1.6)
	_collision_box(Vector3(46.0, 50.0, 46.0), asm + Vector3(0.0, 25.0, 0.0))
	locations["artscience_museum"] = asm
	var flyer := FLYER_POS
	var flyer_yaw := deg_to_rad(-20.0)
	_authored("singapore_flyer.glb", flyer, flyer_yaw, Vector3.ONE * 1.4)
	_collision_box(Vector3(66.0, 12.0, 42.0), flyer + Vector3(0.0, 6.0, 0.0), flyer_yaw)
	_collision_box(Vector3(150.0, 150.0, 22.0), flyer + Vector3(0.0, 87.0, 0.0), flyer_yaw)
	locations["singapore_flyer"] = flyer

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
				parked_spots.append({"pos": spot, "heading": 0.0 if side > 0 else PI, "kind": ["sedan", "coupe", "van"][(int(absf(p.x)) + bay2) % 3], "courtyard_only": true})
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
	mesh.material_override = RoofKit.facade_variant(kind, pos)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	# Weathered membrane deck, parapet and seeded roof plant (RoofKit, wave A):
	# the critic found the aerials "dominated by untextured beige box roofs".
	_roof_kit.add_flat_roof(size, pos, kind)

# ------------------------------------------------------------- water + skyline
func _waterfront_edge() -> void:
	# The bay surface, seawalls, boats and Merlion jet live in bay.gd (BayWater).
	# promenade deck + railing
	_solid_box(Vector3(700.0, 0.3, 22.0), Vector3(0.0, 0.15, PROMENADE_Z), Palette.mat_textured(Palette.CONCRETE_LIGHT,"pavers",Vector3.ONE,0.9))
	for i: int in 46:
		_cyl(Vector3(0.12, 1.1, 0.12), Vector3(-340.0 + i * 15.0, 0.85, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_box(Vector3(700.0, 0.08, 0.08), Vector3(0.0, 1.35, PROMENADE_Z - 10.6), Palette.mat(Palette.METAL, 0.5, 0.5))
	_helipad(Vector3(locations["helipad_secondary"].x, 0.0, locations["helipad_secondary"].z), 11.0)
	# The Merlion pier jutting into the bay between the waterfront helipad and delivery zone
	# Wave A (skyline): the statue stands at the end of a pier past the railing,
	# turned toward the promenade, so walkers see the lion face three-quarter on
	# with the jet arcing into the bay instead of the back of the figure.
	# Wave A integration: the water piece's stone pier base, wet band and jet
	# follow this pier and the statue's rotation (see BayWater.build).
	var merlion_pos := Vector3(64.0, 0.30, -371.0)
	var merlion_pier := Rect2(57.0, -375.5, 14.0, 27.0)
	_solid_box(Vector3(14.0, 0.32, 27.0), Vector3(64.0, 0.15, -362.0), Palette.mat_textured(Palette.CONCRETE_LIGHT, "pavers", Vector3.ONE, 0.9))
	var merlion := _authored("merlion_landmark.glb", merlion_pos, deg_to_rad(-135.0), Vector3.ONE)
	_collision_box(Vector3(8.5, 3.5, 8.5), merlion_pos + Vector3(0.0, 1.75, 0.0))
	locations["merlion"] = merlion_pos
	bay = BayWater.build(self, _world_root, merlion, merlion_pos, merlion_pier)
	for i: int in 8:
		_tree(Vector3(-300.0 + i * 85.0, 0.0, PROMENADE_Z + 6.0), 1.0)
	for i: int in 6:
		_street_lamp(Vector3(-320.0 + i * 128.0, 0.0, PROMENADE_Z + 8.0))

func _background_city() -> void:
	# Wave A (skyline): one layered procedural city replaces the repeated
	# skyline GLB grid (see SkylineCity). Roof dressing collected by the infill
	# and HDB builders is flushed here too, before static batching.
	_roof_kit.build(_world_root)
	var city := SkylineCity.new(991)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4421
	# Clear sky behind the SkyPark and around the Flyer wheel; nothing tall on
	# the near far-shore plaza in front of the landmarks.
	# The SkyPark bow cantilevers west, and the aerial cameras look across it
	# from the east, so the low zone widens westward with depth (a wedge).
	for band in [[-800.0, -300.0], [-900.0, -360.0], [-1050.0, -440.0], [-1300.0, -520.0]]:
		var z_far: float = band[0]
		var x_west: float = band[1]
		city.clear_zone(Rect2(x_west, z_far, 115.0 - x_west, MBS_POS.z - z_far), 70.0)
	city.clear_zone(Rect2(MBS_POS.x - 200.0, MBS_POS.z - 40.0, 400.0, 75.0), 0.0)
	city.clear_zone(Rect2(FLYER_POS.x - 95.0, FLYER_POS.z - 480.0, 190.0, 520.0), 30.0)
	city.clear_zone(Rect2(ASM_POS.x - 45.0, ASM_POS.z - 40.0, 90.0, 80.0), 0.0)
	city.clear_zone(Rect2(-900.0, -700.0, 1800.0, 60.0), 0.0)
	# Far shore, five depth layers: low waterfront edge -> mid-rise -> tall CBD
	# clusters flanking MBS -> distant horizon band.
	for layer in 5:
		var z0: float = [-725.0, -790.0, -870.0, -980.0, -1180.0][layer]
		var step: float = [46.0, 42.0, 38.0, 44.0, 52.0][layer]
		var x := -900.0 + rng.randf_range(0.0, step)
		while x < 900.0:
			var z := z0 + rng.randf_range(-22.0, 22.0)
			var h: float
			var cbd_west := x > -620.0 and x < -330.0
			var cbd_east := x > 330.0 and x < 640.0
			match layer:
				0: h = rng.randf_range(22.0, 48.0)
				1: h = rng.randf_range(40.0, 95.0)
				2: h = rng.randf_range(70.0, 150.0) * (1.6 if cbd_west or cbd_east else 1.0)
				3: h = rng.randf_range(90.0, 180.0) * (1.45 if cbd_west or cbd_east else 1.0)
				_: h = rng.randf_range(40.0, 110.0)
			city.add_random(Vector3(x, 0.0, z), minf(h, 265.0), layer == 4 and rng.randf() < 0.5)
			x += step * rng.randf_range(0.75, 1.3)
	# Round 2: the inner east flank row (behind the aviation compound) is the
	# authored mullioned-glass towers again (podium, crown, spire). The critic
	# found the procedural slabs that replaced them read as flat boxes from
	# the airfield and the drive. West and south stay procedural (the aerial
	# views judged those better), and nothing stands in the bay any more.
	var near_rng := RandomNumberGenerator.new()
	near_rng.seed = 991
	for i in 64:
		var side := i % 4
		if side == 0:
			continue
		var p := Vector3.ZERO
		match side:
			1: p = Vector3(-440.0 - near_rng.randf_range(0.0, 90.0), 0.0, -410.0 + (i / 4) * 54.0)
			2: p = Vector3(440.0 + near_rng.randf_range(0.0, 90.0), 0.0, -410.0 + (i / 4) * 54.0)
			_: p = Vector3(-620.0 + (i / 4) * 82.0, 0.0, 435.0 + near_rng.randf_range(0.0, 90.0))
		var yaw := near_rng.randf_range(-0.08, 0.08)
		var hs := near_rng.randf_range(0.55, 1.20)
		if side != 2 or SkylineCity._over_water(p, 40.0):
			continue
		_authored("skyline_%d.glb" % ((i / 4) % 4), p, yaw, Vector3(1.0, hs, 1.0))
	# Procedural estates and mixed blocks: west flank and south edge from the
	# district edge outward, east flank behind the authored row.
	for side in [-1.0, 1.0]:
		var x0: float = 455.0 if side < 0.0 else 600.0
		for row in (3 if side < 0.0 else 2):
			var zz := -330.0 + rng.randf_range(0.0, 30.0)
			while zz < 600.0:
				var xx: float = side * (x0 + row * 72.0 + rng.randf_range(-10.0, 10.0))
				var res := rng.randf() < 0.4
				city.add_random(Vector3(xx, 0.0, zz), rng.randf_range(38.0, 75.0) + row * 24.0 + (40.0 if not res and rng.randf() < 0.45 else 0.0), res)
				zz += rng.randf_range(48.0, 72.0)
	for row in 3:
		var xs := -620.0 + rng.randf_range(0.0, 30.0)
		while xs < 560.0:
			var res2 := rng.randf() < 0.4
			city.add_random(Vector3(xs, 0.0, 455.0 + row * 72.0 + rng.randf_range(-10.0, 10.0)), rng.randf_range(32.0, 72.0) + row * 25.0, res2)
			xs += rng.randf_range(50.0, 76.0)
	# Round 4: third tower layer, wing estates, city carpet, low-rise blocks,
	# far ridges and the shared sun/haze sync (see SkylineHorizon).
	# `--skyline-off=horizon` builds without it (perf / look A/B only).
	var horizon := SkylineHorizon.new()
	var horizon_on := not ("--skyline-off=horizon" in OS.get_cmdline_user_args())
	if horizon_on:
		horizon.populate(city)
	city.build(_world_root)
	if horizon_on:
		horizon.build(_world_root, city)
		_batch_background("res://assets/authored/rain_tree.glb", horizon.promenade_tree_transforms(_far_shore_tree_clear))
	SkylineHorizon.sync(self)
	skyline_stats = {"materials": city.materials_used.size(), "over_water": city.over_water, "placed": city.placed, "ground_shadows": city.ground_shadows,
		"lowrise": horizon.lowrise, "far_towers": horizon.far_towers, "carpet_km2": horizon.carpet_area / 1.0e6, "promenade_trees": horizon.promenade_trees, "atmosphere": SkylineHorizon.params().size()}
	print("[world] skyline city: ", city.placed, " towers; roof kit: ", _roof_kit.roofs, " roofs")

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
	# Round 4: neutral made ground under the city carpet (the soil texture
	# showed through as brown dirt at the far shore's edges).
	var ground_mat:=Palette.mat(Color(.36,.37,.35),.95)
	_box(Vector3(1700,8,700),Vector3(0,-4,-970),ground_mat)
	# Round 4: grey granite seawall coping (the warm concrete read as a brown
	# dirt band along the far shore from the aerial views, critic A3).
	_box(Vector3(1700,2,18),Vector3(0,-.7,-624),Palette.mat(Color(0.47,0.48,0.48),.88))
	_box(Vector3(1680,.08,16),Vector3(0,.05,-657),Palette.mat_textured(Palette.ASPHALT,"asphalt",Vector3.ONE,.85))
	# Round 4: the far-shore rows are batched full-size rain trees now
	# (SkylineHorizon.promenade_tree_transforms); the world RNG still advances
	# once per old tree so every later random placement stays where it was.
	for i in 34:
		if _far_shore_clear(Vector3(-790+i*48,.1,-640)):
			_rng.randf_range(-PI, PI)
	# A treed far shoreline. The manager's aerial review called the horizon
	# "abrupt"; the bay previously ended where open water met a flat plane.
	# This band gives the far shore a real edge with canopy and low roofs.
	for i in 44:
		if _far_shore_clear(Vector3(-800.0 + i * 37.0, 0.15, -652.0)):
			_rng.randf_range(-PI, PI)
	# (Wave A: the 16 plain low-roof boxes at z=-712 are now SkylineCity's
	# waterfront layer, with facades and roofs.)
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
		if i in [25, 26]:
			continue
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
	# The two kerbs are staggered by 30 m: lots directly opposite each other
	# left ~11 m between parked bodies, less than a car's ~13 m U-turn (wave 5
	# soak: a free-roam car wedged mid-turn for 95 s).
	var i := 0
	for x in X_LINES:
		for side: float in [-1.0, 1.0]:
			var heading := 0.0 if side < 0.0 else PI
			for pz: float in [-218.0, -118.0, -64.0, 56.0, 182.0]:
				var stagger_z := pz + (30.0 if side > 0.0 else 0.0)
				parked_spots.append({"pos": Vector3(x + side * KERB_PARK_OFFSET, 0.3, stagger_z), "heading": heading, "kind": ["sedan", "coupe", "van"][i % 3]})
				i += 1
	for z in Z_LINES:
		for side: float in [-1.0, 1.0]:
			var heading2 := -PI * 0.5 if side < 0.0 else PI * 0.5
			var lots: Array[float] = [-220.0, -104.0, 56.0, 216.0]
			if z == -160.0:
				# heritage avenue (photo/gameplay hero street, lighting r4): a
				# fuller kerb so the toward-sun views read as a lived street
				lots.append_array([-128.0, -100.0, -50.0, -22.0] if side > 0.0 else [-140.0, -82.0, -36.0])
			for px2: float in lots:
				var stagger_x := px2 + (30.0 if side > 0.0 and px2 in [-220.0, -104.0, 56.0, 216.0] else 0.0)
				parked_spots.append({"pos": Vector3(stagger_x, 0.3, z + side * KERB_PARK_OFFSET), "heading": heading2, "kind": ["sedan", "coupe", "van"][i % 3]})
				i += 1

## Singapore kerb markings (wave 5): double yellow no-parking lines that stop at
## junction mouths and break for white-outlined kerbside parking lots. Two
## MultiMesh draws replace the twenty continuous 740 m strips, which ran
## straight through every junction and under every parked car.
func _kerb_markings() -> void:
	var yellow: Array[Transform3D] = []
	var white: Array[Transform3D] = []
	for axis in 2:
		var lines: Array[float] = X_LINES if axis == 0 else Z_LINES
		for line in lines:
			for side: float in [-1.0, 1.0]:
				var gaps: Array[Vector2] = []
				for cross in (Z_LINES if axis == 0 else X_LINES):
					gaps.append(Vector2(cross - ROAD_HALF - 1.0, cross + ROAD_HALF + 1.0))
				for spot in parked_spots:
					if bool(spot.get("courtyard_only", false)): continue
					var p: Vector3 = spot["pos"]
					var lateral := p.x if axis == 0 else p.z
					var along := p.z if axis == 0 else p.x
					if absf(lateral - (line + side * KERB_PARK_OFFSET)) > 0.2: continue
					gaps.append(Vector2(along - 3.4, along + 3.4))
					# Lot outline: two transverse ends and the traffic-side edge.
					for end_offset: float in [-3.3, 3.3]:
						white.append(_marking(axis, line + side * KERB_PARK_OFFSET, along + end_offset, Vector3(2.3, 1.0, 0.12)))
					white.append(_marking(axis, line + side * (KERB_PARK_OFFSET - 1.15), along, Vector3(0.12, 1.0, 6.7)))
				gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
				var cursor := -370.0
				gaps.append(Vector2(370.0, 371.0))
				for gap: Vector2 in gaps:
					if gap.x > cursor + 0.5:
						var mid: float = (cursor + gap.x) * 0.5
						var length: float = gap.x - cursor
						for offset: float in [ROAD_HALF - 0.35, ROAD_HALF - 0.58]:
							yellow.append(_marking(axis, line + side * offset, mid, Vector3(0.12, 1.0, length)))
					cursor = maxf(cursor, gap.y)
	_marking_batch(yellow, Palette.mat(Color(0.92, 0.72, 0.16), 0.72))
	_marking_batch(white, Palette.mat(Color(0.90, 0.90, 0.86), 0.75))

## Far-shore planting keeps clear of the ArtScience lotus and the Flyer terminal
## (release critic: shoreline tree rows grew through both).
## Far-shore promenade trees also keep off the Marina Bay Sands podium.
func _far_shore_tree_clear(p: Vector3) -> bool:
	if p.x > MBS_POS.x - 165.0 and p.x < MBS_POS.x + 200.0 and p.z > MBS_POS.z - 32.0 and p.z < MBS_POS.z + 40.0:
		return false
	return _far_shore_clear(p)

func _far_shore_clear(p: Vector3) -> bool:
	var to_asm := Vector2(p.x - ASM_POS.x, p.z - ASM_POS.z).length()
	var to_flyer := Vector2(p.x - FLYER_POS.x, p.z - FLYER_POS.z).length()
	return to_asm > 34.0 and to_flyer > 42.0

## Everyday wayfinding on the opening avenue (wave 5): a freestanding food-centre
## signboard at the hall's street corner and blade street-name signs at the first
## junction. Fictional English names; supporting cues, not the identity itself.
func _opening_signage() -> void:
	var board_mat := Palette.mat(Color(0.06, 0.24, 0.17), 0.7)
	var post_mat := Palette.mat_textured(Palette.METAL_DARK, "metal", Vector3.ONE, 0.6, 0.4)
	var board := Vector3(-147.5, 4.6, -58.0)
	for dz: float in [-4.2, 4.2]:
		_cyl(Vector3(0.18, 4.6, 0.18), Vector3(board.x, 2.3, board.z + dz), post_mat)
	_box(Vector3(0.28, 1.5, 9.4), board, board_mat)
	var name_label := _label3d("TEMBUSU FOOD CENTRE", board + Vector3(-0.16, 0.0, 0.0))
	name_label.rotation.y = -PI * 0.5
	name_label.font_size = 96
	name_label.pixel_size = 0.0115
	name_label.modulate = Color(0.97, 0.93, 0.80)
	# Blade street-name signs, white on deep blue, at the first junction corner;
	# each blade runs parallel to the street it names and reads from both sides.
	var pole := Vector3(-169.2, 0.0, -14.2)
	_cyl(Vector3(0.1, 3.1, 0.1), pole + Vector3(0.0, 1.55, 0.0), post_mat)
	_street_blade(pole + Vector3(0.0, 2.95, 0.0), true, "Kampong Sirih Road")
	_street_blade(pole + Vector3(0.0, 2.6, 0.0), false, "Tembusu Avenue")

func _street_blade(pos: Vector3, along_x: bool, text: String) -> void:
	var blue := Palette.mat(Color(0.05, 0.12, 0.38), 0.6)
	_box(Vector3(1.9, 0.32, 0.05) if along_x else Vector3(0.05, 0.32, 1.9), pos, blue)
	for side: float in [1.0, -1.0]:
		var offset := Vector3(0.0, 0.0, 0.035 * side) if along_x else Vector3(0.035 * side, 0.0, 0.0)
		var label := _label3d(text, pos + offset)
		# Label3D reads toward +Z; turn each copy to face away from its blade face.
		label.rotation.y = (0.0 if side > 0.0 else PI) if along_x else (PI * 0.5 if side > 0.0 else -PI * 0.5)
		label.font_size = 40
		label.pixel_size = 0.0085
		label.outline_size = 0
		label.modulate = Color(0.97, 0.97, 0.97)

## Static primitive batching (wave 5, PERF). The builder emits ~7,900 plain
## box/cylinder/sphere MeshInstance3D nodes with ~5,000 one-off materials; each is
## its own draw (and shadow/depth draw). After the district is complete, identical
## primitives with equivalent opaque materials are merged per 160 m cell into
## MultiMeshes. World-triplanar and per-face facade mapping are position/face
## based, so the merged geometry samples the same textures. Grouped, scripted,
## metadata-bearing (signal lamps), transparent or range-limited meshes stay as
## they are; collision bodies are untouched.
func _batch_static_primitives() -> void:
	if "--no-static-batching" in OS.get_cmdline_user_args():
		print("[world] static primitive batching disabled for A/B capture")
		return
	var groups := {}
	var originals: Array[MeshInstance3D] = []
	var stack: Array[Node] = [_world_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D: continue
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.get_child_count() > 0 or not mi.get_groups().is_empty() or not mi.get_meta_list().is_empty() or mi.get_script() != null: continue
		if not mi.is_visible_in_tree() or mi.visibility_range_end > 0.0 or mi.skin != null: continue
		var mat := mi.material_override as StandardMaterial3D
		var mesh_key := ""
		var mat_key := ""
		var unit_scale := Vector3.ONE
		var batch_mesh: Mesh = mi.mesh
		var source := ""
		if mi.mesh is ArrayMesh:
			# Repeated imported props (trees, ferns, planters, condensers, lamps,
			# railings, side skyline) keep their own surface materials; tinted
			# single-surface modules (shophouses) merge per shared tint.
			if mat != null: continue
			mesh_key = "mesh#%d" % mi.mesh.get_instance_id()
			mat_key = "surfaces"
			if mi.mesh.get_surface_count() == 1 and mi.get_surface_override_material(0) is StandardMaterial3D:
				mat = mi.get_surface_override_material(0) as StandardMaterial3D
				if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
				mat_key = "tint#%d" % mat.get_instance_id()
			elif not _imported_batchable(mi):
				continue
			source = _scene_source(mi)
		elif mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		elif mi.mesh is BoxMesh:
			var bm := mi.mesh as BoxMesh
			if bm.subdivide_width != 0 or bm.subdivide_height != 0 or bm.subdivide_depth != 0: continue
			mesh_key = "box"
			unit_scale = bm.size
			batch_mesh = null
		elif mi.mesh is CylinderMesh:
			var cm := mi.mesh as CylinderMesh
			mesh_key = "cyl|%.3f|%.3f|%.3f|%d|%d|%s|%s" % [cm.top_radius, cm.bottom_radius, cm.height, cm.radial_segments, cm.rings, cm.cap_top, cm.cap_bottom]
		elif mi.mesh is SphereMesh:
			var sm := mi.mesh as SphereMesh
			mesh_key = "sph|%.3f|%.3f|%d|%d|%s" % [sm.radius, sm.height, sm.radial_segments, sm.rings, sm.is_hemisphere]
		else:
			continue
		if mat_key == "":
			mat_key = ("obj#%d" % mat.get_instance_id()) if (mat.albedo_texture != null or mat.normal_texture != null or mat.roughness_texture != null) else \
				"c|%s|%.3f|%.3f|%.3f|%s|%s|%.3f|%d|%d" % [mat.albedo_color, mat.roughness, mat.metallic, mat.metallic_specular, mat.emission_enabled, mat.emission, mat.emission_energy_multiplier, mat.cull_mode, mat.shading_mode]
		var xform := mi.transform
		var parent := mi.get_parent()
		while parent != _world_root and parent is Node3D:
			xform = (parent as Node3D).transform * xform
			parent = parent.get_parent()
		if parent != _world_root: continue
		# MultiMesh normals use the instance basis without an inverse-transpose,
		# so strongly non-uniform scale on curved/slanted meshes stays unbatched
		# (unit boxes are exact: their faces stay axis-aligned; critic, wave 5).
		if mesh_key != "box":
			var sc := xform.basis.get_scale()
			if maxf(sc.x, maxf(sc.y, sc.z)) > minf(sc.x, minf(sc.y, sc.z)) * 1.10: continue
		var cell := Vector2i(floori(xform.origin.x / 160.0), floori(xform.origin.z / 160.0))
		var key := "%s#%s#%d" % [mesh_key, mat_key, mi.cast_shadow]
		if not groups.has(key):
			groups[key] = {"mesh": batch_mesh, "material": mat, "shadow": mi.cast_shadow, "xforms": [], "nodes": [], "cells": [], "source": source}
		groups[key]["xforms"].append(Transform3D(xform.basis * Basis.from_scale(unit_scale), xform.origin) if mesh_key == "box" else xform)
		groups[key]["nodes"].append(mi)
		groups[key]["cells"].append(cell)
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	# Large families split per 160 m cell so culling still works; small ones
	# (one-off facade colours etc.) become a single district-wide draw.
	var batch_list: Array[Dictionary] = []
	for key in groups:
		var g: Dictionary = groups[key]
		var count: int = (g["xforms"] as Array).size()
		# Imported props only merge when repeated; one-off landmarks stay nodes.
		if String(key).begins_with("mesh#") and count < 4:
			continue
		originals.append_array(g["nodes"])
		if count <= 24:
			batch_list.append(g)
			continue
		var by_cell := {}
		for i in count:
			var cell: Vector2i = g["cells"][i]
			if not by_cell.has(cell):
				by_cell[cell] = {"mesh": g["mesh"], "material": g["material"], "shadow": g["shadow"], "xforms": [], "source": g["source"]}
			by_cell[cell]["xforms"].append(g["xforms"][i])
		for cell in by_cell:
			batch_list.append(by_cell[cell])
	var batches := 0
	for g in batch_list:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"] if g["mesh"] != null else unit_box
		var xforms: Array = g["xforms"]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "StaticBatch_%s_%d" % [g["source"], batches]
		mmi.multimesh = mm
		mmi.material_override = g["material"]
		mmi.cast_shadow = g["shadow"]
		_probe_copy(mmi, xforms)
		_world_root.add_child(mmi)
		batches += 1
	for mi in originals:
		mi.get_parent().remove_child(mi)
		mi.free()
	print("[world] static primitive batching: ", originals.size(), " meshes -> ", batches, " multimesh draws")

## A flat paint stripe: size.x across the road, size.z along it.
func _marking(axis: int, lateral: float, along: float, size: Vector3) -> Transform3D:
	var basis := Basis.from_scale(Vector3(size.x, 0.02, size.z)) if axis == 0 else Basis.from_scale(Vector3(size.z, 0.02, size.x))
	var origin := Vector3(lateral, 0.075, along) if axis == 0 else Vector3(along, 0.075, lateral)
	return Transform3D(basis, origin)

func _marking_batch(transforms: Array[Transform3D], material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	mm.mesh = unit
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "StaticBatchMarkings"
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_probe_copy(instance, transforms)
	_world_root.add_child(instance)

## Opaque or alpha-tested imported surfaces only; blended surfaces need per-node
## sorting and stay as they are.
func _imported_batchable(mi: MeshInstance3D) -> bool:
	for i in mi.get_surface_override_material_count():
		if mi.get_surface_override_material(i) != null: return false
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
			return false
		if m != null and not m is BaseMaterial3D: return false
	return true

func _scene_source(node: Node) -> String:
	var n := node
	while n != null and n != _world_root:
		if String(n.scene_file_path) != "": return String(n.scene_file_path).get_file().get_basename()
		n = n.get_parent()
	return "prop"

## Headless (dummy renderer) MultiMeshes do not retain instance transforms, so
## the sightline probe gets its own copy to verify batched geometry.
func _probe_copy(instance: MultiMeshInstance3D, transforms: Array) -> void:
	if "--sightline-probe" in OS.get_cmdline_user_args():
		instance.set_meta("probe_xforms", transforms.duplicate())

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
	# Lamp head glow + downward light pool (Lighting owns the practicals).
	_lighting.street_lamp(pos)

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
	LandmarkLooks.apply(node)
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
					var tree_scale := .8+_rng.randf()*.2
					# The opening heritage row's five-foot way occupies this verge.
					if road == -160.0 and side < 0.0 and p.z > -156.0 and p.z < -28.0:
						continue
					_tree(p,tree_scale)
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
