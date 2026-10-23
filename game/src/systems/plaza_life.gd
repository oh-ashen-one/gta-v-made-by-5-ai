class_name PlazaLife
extends Node3D
## downtown-life (wave S): people doing readable things in the downtown
## plazas and promenades, close to the lens.
##
## Critics (street-life M1/M2, integration M): "people within 3-12 m of the
## camera doing readable things" (GTA V reference: ~20 distinct people 3-15 m
## away). The crowd director supplies walkers and talking groups; this adds
## the activities a walk line cannot give:
## - sitting on granite-and-timber benches facing the bay or the plaza
##   (one on a phone, one with a drink, an older couple...),
## - queuing at an ice-cream cart under a striped parasol (the Singapore
##   "ice-cream uncle"), a vendor behind it and someone eating nearby,
## - a tourist photographing friends who pose with the landmark behind them.
##
## Stations (bench, cart, photo spot) are fixed places validated against the
## built world (floor ray, no colliders, never on a carriageway). Benches and
## carts are always there (two MultiMesh / mesh batches, colliders on the
## on-foot prop layer only). A small pool of people "units" (a bench pair, a
## cart queue, a photo group) is moved to the stations nearest the camera,
## only while the station is out of sight or on a camera cut, so nobody pops
## in view. Units stay IDLE (settled, no collision solve) until startled.

const ACTIVE_RADIUS := 75.0
const RELEASE_RADIUS := 110.0
const BENCH_TOP := 0.46

## [kind, x, z, face_x, face_z]: the face point is where sitters, the queue
## or the posers look (the bay, a landmark, the plaza).
const STATIONS := [
	# MBS Event Plaza (bay side, facing the CBD skyline across the water)
	["bench", -190.0, -628.5, -190.0, -500.0], ["bench", -152.0, -628.5, -152.0, -500.0],
	["bench", -84.0, -628.5, -84.0, -500.0], ["bench", -44.0, -628.5, -44.0, -500.0],
	["cart", -118.0, -649.0, -118.0, -600.0], ["photo", -136.0, -640.0, -136.0, -600.0],
	["photo", -64.0, -641.0, -64.0, -600.0],
	# Merlion Park / One Fullerton terrace (facing Marina Bay Sands)
	["bench", -500.0, -398.0, -118.0, -705.0], ["bench", -458.0, -404.0, -118.0, -705.0],
	["cart", -488.0, -380.0, -118.0, -705.0], ["photo", -470.0, -392.0, -118.0, -705.0],
	# Raffles Place plaza
	["bench", -404.0, -64.0, -377.0, -80.0], ["bench", -352.0, -122.0, -377.0, -80.0],
	["cart", -378.0, -36.0, -378.0, 20.0], ["bench", -402.0, -132.0, -377.0, -80.0],
	# Boat Quay river walk (facing the river)
	["bench", -528.0, 34.0, -600.0, 34.0], ["bench", -528.0, 112.0, -600.0, 112.0],
	["cart", -523.0, 72.0, -600.0, 72.0], ["photo", -526.0, -60.0, -600.0, -60.0],
	# Esplanade waterfront and NS Square (facing the bay)
	["bench", -651.0, -432.0, -400.0, -432.0], ["bench", -651.0, -520.0, -400.0, -520.0],
	["cart", -645.0, -476.0, -400.0, -476.0], ["photo", -600.0, -612.0, -500.0, -560.0],
	# District waterfront promenade (legacy, facing the bay / MBS)
	["bench", -60.0, -344.5, -60.0, -500.0], ["bench", 24.0, -344.5, 24.0, -500.0],
	["cart", -24.0, -334.0, -24.0, -500.0], ["photo", 48.0, -343.0, 64.0, -371.0],
	# Marina Bay Financial Centre waterfront
	["bench", 372.0, -560.0, 200.0, -560.0], ["cart", 366.0, -470.0, 200.0, -470.0],
]

## Unit rosters: [kind, prop] per member (CrowdPeople.Kind).
const BENCH_UNITS := [
	[[1, "phone"], [0, "cup"]], [[3, "none"], [2, "none"]], [[0, "phone"], [1, "handbag"]], [[1, "cup"], [1, "phone"]],
]
const CART_UNITS := [
	[[2, "none"], [1, "handbag"], [4, "none"], [0, "backpack"], [1, "cup"]],
	[[0, "none"], [3, "shopping"], [1, "phone"], [0, "none"], [4, "cup"]],
]
const PHOTO_UNITS := [
	[[1, "phone"], [0, "none"], [1, "umbrella"]], [[0, "phone"], [1, "handbag"], [1, "cup"]],
]

## People this system adds to traffic.peds (the self-test budget).
static func pool_size() -> int:
	var n := 0
	for r in BENCH_UNITS + CART_UNITS + PHOTO_UNITS:
		n += (r as Array).size()
	return n

var traffic: TrafficManager
var stations: Array[Dictionary] = []      # {kind, pos, yaw, face, unit}
var units: Array[Dictionary] = []         # {kind, people: Array[NPC], station}
var stats := {"stations": 0, "rejected": 0, "placements": 0}
var _built := false
var _frames := 0
var _cam_pos := Vector3.INF
var _cam_fwd := Vector3.FORWARD
var _tick := 0.0
var _body: StaticBody3D

func setup(t: TrafficManager) -> void:
	name = "PlazaLife"
	traffic = t
	for roster in BENCH_UNITS:
		units.append(_make_unit("bench", roster, ["sitting", "sitting"]))
	for roster in CART_UNITS:
		units.append(_make_unit("cart", roster, ["vending", "queuing", "queuing", "queuing", "eating"]))
	for roster in PHOTO_UNITS:
		units.append(_make_unit("photo", roster, ["photo", "posing", "posing"]))

func _make_unit(kind: String, roster: Array, roles: Array) -> Dictionary:
	var people: Array[NPC] = []
	for i in roster.size():
		var n := NPC.new()
		n.set_meta("people_kind", int(roster[i][0]))
		n.set_meta("people_prop", String(roster[i][1]))
		n.set_meta("plaza_activity", String(roles[i]))
		if roles[i] == "sitting":
			n.set_meta("people_seated", true)
		traffic.add_child(n)
		n.global_position = Vector3(0.0, -50.0 - units.size() * 2.0 - i * 0.4, 30.0)
		_park(n)
		traffic.peds.append(n)
		people.append(n)
	return {"kind": kind, "people": people, "station": -1}

func _park(n: NPC) -> void:
	if n.character_visual != null:
		n.character_visual.set_lod_far(true)
		n.character_visual.set_process(false)
	n.visible = false
	n.collision_layer = 0
	n.collision_mask = 0
	n.set_physics_process(false)
	n.velocity = Vector3.ZERO
	n.state = NPC.State.IDLE
	n.idle_time = 1.0e9

func _physics_process(delta: float) -> void:
	_frames += 1
	if not _built:
		if _frames < 3:
			return
		_build_stations()
		_built = true
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	var cut := _cam_pos == Vector3.INF or cp.distance_to(_cam_pos) > 40.0
	_cam_pos = cp
	_cam_fwd = flat.normalized() if flat.length() > 0.05 else Vector3.FORWARD
	_tick -= delta
	if _tick > 0.0 and not cut:
		return
	_tick = 0.3
	_update_units(cut)

func _visible_from_lens(p: Vector3) -> bool:
	var rel := p - _cam_pos
	rel.y = 0.0
	return rel.length() < 70.0 and (rel.length() < 6.0 or rel.normalized().dot(_cam_fwd) > -0.1)

func _update_units(cut: bool) -> void:
	var cam2 := Vector2(_cam_pos.x, _cam_pos.z)
	# Release units far from the lens (or whose people were startled away).
	for u in units:
		var si := int(u["station"])
		if si < 0:
			continue
		var st: Dictionary = stations[si]
		var d := cam2.distance_to(Vector2((st["pos"] as Vector3).x, (st["pos"] as Vector3).z))
		if d > RELEASE_RADIUS or (cut and d > ACTIVE_RADIUS):
			_release(u)
		else:
			_restore_seat(u)
	# Fill the nearest empty stations.
	var order: Array = []
	for i in stations.size():
		var st2: Dictionary = stations[i]
		if int(st2["unit"]) >= 0:
			continue
		var d2 := cam2.distance_to(Vector2((st2["pos"] as Vector3).x, (st2["pos"] as Vector3).z))
		if d2 < ACTIVE_RADIUS:
			order.append([d2, i])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for o in order:
		var st3: Dictionary = stations[int(o[1])]
		if not cut and _visible_from_lens(st3["pos"]):
			continue
		var free: Dictionary = {}
		for u in units:
			if int(u["station"]) < 0 and String(u["kind"]) == String(st3["kind"]):
				free = u
				break
		if free.is_empty():
			continue
		_assign(free, int(o[1]))

func _release(u: Dictionary) -> void:
	var si := int(u["station"])
	if si >= 0:
		stations[si]["unit"] = -1
	u["station"] = -1
	for n: NPC in u["people"]:
		if is_instance_valid(n) and n.state != NPC.State.DEAD:
			if n.character_visual != null and n.character_visual.loaded:
				n.character_visual.set_seated(false)
				n.character_visual.position = Vector3.ZERO
			_park(n)

## A sitter who was startled (shot nearby, the player's car) stood up and ran
## off; once out of sight, the unit goes back to its seats.
func _restore_seat(u: Dictionary) -> void:
	for n: NPC in u["people"]:
		if is_instance_valid(n) and n.state != NPC.State.IDLE and n.state != NPC.State.DEAD and not _visible_from_lens(n.global_position):
			var si := int(u["station"])
			_release(u)
			_assign(u, si)
			return

func _assign(u: Dictionary, si: int) -> void:
	var st: Dictionary = stations[si]
	u["station"] = si
	st["unit"] = units.find(u)
	var base: Vector3 = st["pos"]
	var yaw := float(st["yaw"])
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))     # facing direction
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var people: Array = u["people"]
	var spots: Array = []   # [pos, yaw]
	match String(st["kind"]):
		"bench":
			spots = [[base - right * 0.42, yaw + 0.12], [base + right * 0.38, yaw - 0.1]]
		"cart":
			# Vendor behind the cart; queue in front of it; someone eating to one side.
			spots = [[base - fwd * 0.95, yaw],
				[base + fwd * 1.05, yaw + PI], [base + fwd * 1.95 + right * 0.15, yaw + PI + 0.1], [base + fwd * 2.85 - right * 0.1, yaw + PI - 0.15],
				[base + fwd * 1.6 + right * 2.2, yaw + PI * 0.75]]
		"photo":
			# The photographer faces the posers, who stand with the view behind them.
			spots = [[base + fwd * 1.7, yaw + PI], [base - right * 0.35, yaw], [base + right * 0.35, yaw]]
	for i in people.size():
		var n: NPC = people[i]
		if not is_instance_valid(n) or n.state == NPC.State.DEAD:
			continue
		var p: Vector3 = spots[i][0]
		n.global_position = Vector3(p.x, base.y + 0.05, p.z)
		n.rotation = Vector3(0.0, float(spots[i][1]), 0.0)
		n.velocity = Vector3.ZERO
		n.visible = true
		n.collision_layer = 4
		n.collision_mask = 1 | 4
		n.set_physics_process(true)
		n.state = NPC.State.IDLE
		n.idle_time = 1.0e9
		n.lane = []
		if n.character_visual != null:
			n.character_visual.set_lod_far(false)
			n.character_visual.set_process(true)
		if n.character_visual != null and n.character_visual.loaded:
			if String(n.get_meta("plaza_activity", "")) == "sitting":
				n.character_visual.position = Vector3(0.0, BENCH_TOP - 0.445, 0.0)
				n.character_visual.set_seated(true)
			else:
				n.character_visual.position = Vector3.ZERO
				n.character_visual.set_seated(false)
	stats["placements"] = int(stats["placements"]) + 1

# ------------------------------------------------------------------ build
func _build_stations() -> void:
	var space := get_world_3d().direct_space_state
	_body = StaticBody3D.new()
	_body.name = "PlazaLifeColliders"
	_body.collision_layer = StreetPropColliders.PROP_LAYER
	_body.collision_mask = 0
	add_child(_body)
	var bench_xf: Array[Transform3D] = []
	var obstacles: Array[Vector3] = []
	for s in STATIONS:
		var kind: String = s[0]
		var want := Vector3(float(s[1]), 0.0, float(s[2]))
		var pos := _find_floor(space, want, kind)
		if pos == Vector3.INF:
			stats["rejected"] = int(stats["rejected"]) + 1
			if OS.is_debug_build() and "--street-debug" in OS.get_cmdline_user_args():
				print("[plaza-life] rejected %s at %s: %s" % [kind, str(want), _why])
			continue
		var face := Vector3(float(s[3]), pos.y, float(s[4])) - pos
		face.y = 0.0
		var yaw := atan2(-face.x, -face.z) if face.length() > 0.1 else 0.0
		var st := {"kind": kind, "pos": pos, "yaw": yaw, "unit": -1}
		stations.append(st)
		var basis := Basis(Vector3.UP, yaw)
		match kind:
			"bench":
				bench_xf.append(Transform3D(basis, pos))
				_add_box(Transform3D(basis, pos + Vector3(0.0, 0.23, 0.0)), Vector3(1.8, 0.46, 0.5))
				obstacles.append(Vector3(pos.x, pos.z, 0.95))
			"cart":
				var cart := MeshInstance3D.new()
				cart.mesh = _cart_mesh()
				cart.transform = Transform3D(basis, pos)
				cart.visibility_range_end = 220.0
				add_child(cart)
				_add_box(Transform3D(basis, pos + Vector3(0.0, 0.5, 0.0)), Vector3(1.25, 1.0, 0.75))
				obstacles.append(Vector3(pos.x, pos.z, 0.8))
	if not bench_xf.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _bench_mesh()
		mm.instance_count = bench_xf.size()
		for i in bench_xf.size():
			mm.set_instance_transform(i, bench_xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "PlazaBenches"
		mmi.multimesh = mm
		mmi.visibility_range_end = 220.0
		add_child(mmi)
	if traffic.crowd != null:
		traffic.crowd.add_obstacles(obstacles)
	stats["stations"] = stations.size()
	print("[plaza-life] %d stations (%d rejected), %d units" % [stations.size(), int(stats["rejected"]), units.size()])

## A level, open, walkable spot at or near `want` (tries a few nudges).
var _why := ""
func _find_floor(space: PhysicsDirectSpaceState3D, want: Vector3, kind: String) -> Vector3:
	var probe := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.3 if kind != "cart" else 1.6
	probe.shape = sph
	probe.collision_mask = 1
	for off: Vector3 in [Vector3.ZERO, Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3(4, 0, 4), Vector3(-4, 0, -4)]:
		var p := want + off
		if StreetRaster.at(p.x, p.z) != 0:
			_why = "road"
			continue
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 12.0, p.z), Vector3(p.x, -3.0, p.z), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.9:
			_why = "no floor" if hit.is_empty() else "slope %s y=%.2f %s" % [str(hit["normal"]), (hit["position"] as Vector3).y, str(hit["collider"])]
			continue
		var g := (hit["position"] as Vector3).y
		if g > 6.0 or g < -0.5:
			_why = "height %.2f %s" % [g, str(hit["collider"])]
			continue
		probe.transform = Transform3D(Basis(), Vector3(p.x, g + sph.radius + 0.3, p.z))
		var blk := space.intersect_shape(probe, 1)
		if not blk.is_empty():
			_why = "blocked by %s" % str(blk[0]["collider"])
			continue
		# Level enough for a bench and a queue (no steps under it).
		var level := true
		for d: Vector3 in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4)]:
			var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x + d.x, g + 2.0, p.z + d.z), Vector3(p.x + d.x, g - 1.0, p.z + d.z), 1))
			if h2.is_empty() or absf((h2["position"] as Vector3).y - g) > 0.12:
				_why = "not level"
				level = false
				break
		if not level:
			continue
		return Vector3(p.x, g, p.z)
	return Vector3.INF

func _add_box(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.transform = xf
	_body.add_child(cs)

# ------------------------------------------------------------------ meshes
static var _bench: ArrayMesh
static var _cart: ArrayMesh

static func _mat(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

static func _box_into(st: SurfaceTool, size: Vector3, xf: Transform3D) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, xf)

static func _cyl_into(st: SurfaceTool, r_top: float, r_bot: float, h: float, xf: Transform3D, segs: int = 10) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	st.append_from(c, 0, xf)

static func _commit(mesh: ArrayMesh, st: SurfaceTool, mat: Material) -> void:
	st.generate_normals()
	st.set_material(mat)
	st.commit(mesh)

## Granite end blocks with a slatted timber seat, 1.8 m long, seat 0.46 m.
static func _bench_mesh() -> ArrayMesh:
	if _bench != null:
		return _bench
	var mesh := ArrayMesh.new()
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-0.68, 0.68]:
		_box_into(stone, Vector3(0.34, 0.4, 0.46), Transform3D(Basis(), Vector3(x, 0.2, 0.0)))
	_commit(mesh, stone, _mat(Color(0.58, 0.57, 0.55), 0.8))
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		_box_into(wood, Vector3(1.8, 0.05, 0.085), Transform3D(Basis(), Vector3(0.0, 0.435, -0.2 + k * 0.1)))
	_commit(mesh, wood, _mat(Color(0.46, 0.3, 0.18), 0.62))
	_bench = mesh
	return mesh

## Ice-cream cart: white enamel box on four wheels with a teal trim band and
## lid, a pole and an eight-panel striped parasol. No text or logos.
static func _cart_mesh() -> ArrayMesh:
	if _cart != null:
		return _cart
	var mesh := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(body, Vector3(1.15, 0.72, 0.66), Transform3D(Basis(), Vector3(0.0, 0.62, 0.0)))
	_box_into(body, Vector3(1.2, 0.05, 0.7), Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)))
	_commit(mesh, body, _mat(Color(0.93, 0.93, 0.9), 0.35))
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(trim, Vector3(1.17, 0.12, 0.68), Transform3D(Basis(), Vector3(0.0, 0.34, 0.0)))
	_box_into(trim, Vector3(1.17, 0.06, 0.68), Transform3D(Basis(), Vector3(0.0, 0.94, 0.0)))
	_box_into(trim, Vector3(0.5, 0.3, 0.02), Transform3D(Basis(), Vector3(0.0, 0.64, 0.34)))
	_commit(mesh, trim, _mat(Color(0.1, 0.55, 0.6), 0.45))
	var dark := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-0.45, 0.45]:
		for z: float in [-0.3, 0.3]:
			_cyl_into(dark, 0.13, 0.13, 0.06, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 0.13, z)), 12)
	_cyl_into(dark, 0.02, 0.02, 1.35, Transform3D(Basis(), Vector3(0.0, 1.68, 0.0)), 6)
	_box_into(dark, Vector3(0.04, 0.04, 0.5), Transform3D(Basis(), Vector3(-0.62, 0.95, 0.0)))
	_commit(mesh, dark, _mat(Color(0.08, 0.08, 0.09), 0.5, 0.4))
	# Parasol: alternating panels (two surfaces), slightly drooped.
	var cols := [Color(0.86, 0.14, 0.16), Color(0.97, 0.93, 0.82)]
	for c in 2:
		var pa := SurfaceTool.new()
		pa.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := Vector3(0.0, 2.48, 0.0)
		for k in 8:
			if k % 2 != c:
				continue
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			var p0 := Vector3(cos(a0) * 1.15, 2.12, sin(a0) * 1.15)
			var p1 := Vector3(cos(a1) * 1.15, 2.12, sin(a1) * 1.15)
			var mid := (p0 + p1) * 0.5 * Vector3(1.0, 0.0, 1.0) + Vector3(0.0, 2.17, 0.0)
			for tri in [[top, p1, mid], [top, mid, p0]]:
				for v in tri:
					pa.add_vertex(v)
		var pm := _mat(cols[c], 0.7)
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		_commit(mesh, pa, pm)
	_cart = mesh
	return mesh

## QA: (activity -> count) of placed, living people within `radius` of `p`.
func census_near(p: Vector3, radius: float) -> Dictionary:
	var out := {}
	for u in units:
		if int(u["station"]) < 0:
			continue
		for n: NPC in u["people"]:
			if is_instance_valid(n) and n.visible and n.state != NPC.State.DEAD and n.global_position.distance_to(p) < radius:
				var a := String(n.get_meta("plaza_activity", ""))
				out[a] = int(out.get(a, 0)) + 1
	return out
