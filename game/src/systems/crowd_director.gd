class_name CrowdDirector
extends Node
## Camera-centred pedestrian density (street-life, Opus wave A).
##
## Wave 5 spread ~80 general walkers over twenty 640 m kerb lanes (one person
## every ~150 m), so the streets a camera actually looks at were empty. The
## director keeps every "roamer" (general walkers, never diners, guards,
## officers or panicking people) within walking distance of the active camera:
## people who fall far behind are re-seeded on pavements and five-foot ways
## ahead of it, out of sight. Each roamer walks a personal line at its own
## distance from the kerb, some pairs stop to talk, and everyone uses the
## junction crosswalks.

const EXTRA_WALKERS := 96
## M2: conversation groups of two or three (ids 0..LOITER_GROUPS-1).
const LOITER_GROUPS := 10
const LOITER_SLOTS := 27
## M2: walking pairs (a couple, friends, a parent with a child) after the
## loiter slots: (leader, follower) indices.
const COMPANION_PAIRS := 12
const SPAWN_RADIUS := 115.0
const DESPAWN_RADIUS := 135.0
## Pavement lines: just behind the kerb, mid-pavement, and the five-foot way.
const OFFSETS: Array[float] = [10.15, 10.75, 11.35]
## Share of five-foot-way seeds that stand at a shopfront for a while.
const SHOPFRONT_SHARE := 0.4

var traffic: TrafficManager
var roamers: Array[NPC] = []
var _rng := RandomNumberGenerator.new()
var _focus := Vector3.INF
var _pp_vel := Vector3.ZERO
var _last_pp := Vector3.ZERO
var _last_pp_ms := 0
var _cam_pos := Vector3.ZERO
var _cam_fwd := Vector3.FORWARD
var _lines: Array[Dictionary] = []   # {axis, line, side}
## Open-sky block spines (the paved service cross through each block centre),
## so crowds also read from the air where avenue canopy hides the pavement.
var _spines: Array[Dictionary] = []  # {a, b}
var stats := {"relocated": 0, "cuts": 0}
## Wave M: downtown pedestrian polylines (world.downtown_ped_lanes, published
## by the downtown-map piece): promenades, bridges and new-road footways.
var _polys: Array = []

func setup(t: TrafficManager) -> void:
	name = "CrowdDirector"
	traffic = t
	_rng.seed = Game.seed_value + 313
	for x in WorldBuilder.X_LINES:
		for side: float in [-1.0, 1.0]:
			_lines.append({"axis": 0, "line": x, "side": side})
	for z in WorldBuilder.Z_LINES:
		for side: float in [-1.0, 1.0]:
			_lines.append({"axis": 1, "line": z, "side": side})
	for col in 4:
		for row in 4:
			var c := Vector3(-240.0 + col * 160.0, 0.2, -240.0 + row * 160.0)
			if c.distance_to(Vector3(-80.0, 0.2, -80.0)) < 1.0:
				continue   # hawker hall: mission combat and package aisle
			var clear := true
			for pad in [t.world.locations["helipad_primary"], t.world.locations["helipad_secondary"]]:
				if Vector2(c.x - pad.x, c.z - pad.z).length() < 75.0:
					clear = false
			if not clear:
				continue
			for off: float in [-4.6, 4.6]:
				_spines.append({"a": c + Vector3(-56.0, 0.0, off), "b": c + Vector3(56.0, 0.0, off)})
				_spines.append({"a": c + Vector3(off, 0.0, -56.0), "b": c + Vector3(off, 0.0, 56.0)})
	adopt_downtown(t.world.downtown_ped_lanes)
	for ped in t.peds:
		if is_instance_valid(ped) and ped.has_meta("roamer"):
			roamers.append(ped)
	var leaders: Array[NPC] = []
	for i in EXTRA_WALKERS:
		var npc := NPC.new()
		npc.set_meta("roamer", true)
		if i < LOITER_SLOTS:
			# Groups of three, every third group a pair (slot 2 walks alone).
			var g := i / 3
			if g % 3 != 2 or i % 3 < 2:
				npc.set_meta("loiter_pair", g)
		elif i < LOITER_SLOTS + COMPANION_PAIRS * 2:
			var k := i - LOITER_SLOTS
			if k % 2 == 1:
				npc.set_meta("follower", true)
				# Every third pair is a parent walking with a child.
				if (k / 2) % 3 == 0:
					npc.set_meta("people_kind", CrowdPeople.Kind.CHILD)
		t.add_child(npc)
		npc.global_position = Vector3(0.0, -40.0 - i * 0.5, 0.0)
		t.peds.append(npc)
		roamers.append(npc)
		if i >= LOITER_SLOTS and i < LOITER_SLOTS + COMPANION_PAIRS * 2:
			if npc.has_meta("follower"):
				npc.companion = leaders[leaders.size() - 1]
				npc.companion_side = 0.62 if posmod(i, 4) == 1 else -0.62
				npc.companion.set_meta("leads", npc)
			else:
				leaders.append(npc)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam_pos = cam.global_position
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		flat = Vector3.FORWARD
	_cam_fwd = flat.normalized()
	var reach := clampf(_cam_pos.y * 1.6, 18.0, 160.0)
	var f := Vector3(_cam_pos.x, 0.0, _cam_pos.z) + _cam_fwd * reach
	# Lead the focus along the player's motion so a driving player meets
	# traffic and people that were seeded out of sight ahead of time.
	var now_ms := Time.get_ticks_msec()
	if _last_pp_ms > 0 and now_ms > _last_pp_ms:
		var inst := (Game.player_position - _last_pp) / (float(now_ms - _last_pp_ms) / 1000.0)
		inst.y = 0.0
		if inst.length() < 60.0:
			_pp_vel = _pp_vel.lerp(inst, 0.1)
	_last_pp = Game.player_position
	_last_pp_ms = now_ms
	f += _pp_vel.limit_length(25.0) * 4.5
	var cut := _focus == Vector3.INF or f.distance_to(_focus) > 45.0
	_focus = f
	if cut:
		stats["cuts"] += 1
	_recycle(cut)
	_dodge_player_vehicle()
	_separate()
	_contact_shadows()
	if cut and "--street-debug" in OS.get_cmdline_user_args():
		var cnt := 0
		var vis := 0
		for r in roamers:
			if r.global_position.distance_to(_focus) < SPAWN_RADIUS + 5.0:
				cnt += 1
				if r.global_position.distance_to(_cam_pos) < NPC.FAR_DRAW_RANGE:
					vis += 1
		print("[crowd-debug] cut focus=", _focus.round(), " cam=", _cam_pos.round(), " near=", cnt, " in_draw_range=", vis, " roamers=", roamers.size())

## Street-life M2: soft contact shadows under the feet of the people nearest
## the camera (the player already has his own), from a small Decal pool, so
## figures in shade read as standing on the paving, not floating.
const CONTACT_PEOPLE := 26
var _decals: Array[Decal] = []
var _foot_ids := {}
func _contact_shadows() -> void:
	if _decals.is_empty():
		for i in CONTACT_PEOPLE * 2:
			var d := Decal.new()
			d.texture_albedo = CharacterVisual._contact_texture()
			d.size = Vector3(0.3, 0.6, 0.4)
			d.modulate = Color(1, 1, 1, 0.7)
			d.upper_fade = 0.25
			d.lower_fade = 0.6
			d.visible = false
			add_child(d)
			_decals.append(d)
	var cands: Array = []
	for p in traffic.peds:
		if not is_instance_valid(p) or not p.visible or p.state == NPC.State.DEAD or p.character_visual == null or not p.character_visual.loaded:
			continue
		var d2 := p.global_position.distance_squared_to(_cam_pos)
		if d2 < 32.0 * 32.0 and d2 > 2.0:
			cands.append([d2, p])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var k := 0
	for c in cands:
		if k >= _decals.size():
			break
		var npc: NPC = c[1]
		var sk := npc.character_visual.skeleton
		var ids: PackedInt32Array = _foot_ids.get(sk.get_instance_id(), PackedInt32Array())
		if ids.is_empty():
			ids = PackedInt32Array([sk.find_bone("foot.l"), sk.find_bone("foot.r")])
			_foot_ids[sk.get_instance_id()] = ids
		var yaw := npc.global_rotation.y
		var feet: Array[Vector3] = []
		for id in ids:
			feet.append(sk.global_transform * sk.get_bone_global_pose(id).origin if id >= 0 else npc.global_position)
		var ground := minf(feet[0].y, feet[1].y) - 0.09 * npc.character_visual.scale.y
		for f in feet:
			var dc := _decals[k]
			k += 1
			var lift := maxf(f.y - ground - 0.12, 0.0)
			dc.modulate.a = 0.72 * (0.25 + 0.75 * clampf(1.0 - lift / 0.25, 0.0, 1.0))
			dc.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(f.x, ground + 0.05, f.z))
			dc.visible = true
	while k < _decals.size():
		_decals[k].visible = false
		k += 1

## Street-life M2: walkers near the camera steer round each other and round
## kerb clutter (M1: pairs walking through each other, people walking
## through the bike racks, which TAA smeared). Sets NPC.avoid, which
## _move_towards blends into the heading.
const SEP_RADIUS := 0.95
const SEP_RANGE := 45.0
var _obs_grid := {}
var _obs_built := false
func _build_obstacles() -> void:
	_obs_built = true
	var pts: Array[Vector3] = AvenueDressing.ped_obstacles.duplicate()
	var body := get_tree().current_scene.find_child("StreetPropColliders", true, false) if get_tree().current_scene != null else null
	if body != null:
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null or not cs.shape is BoxShape3D:
				continue
			var size: Vector3 = (cs.shape as BoxShape3D).size
			var xf := cs.global_transform
			var long_ax := xf.basis.x.normalized() if size.x >= size.z else xf.basis.z.normalized()
			var length := maxf(size.x, size.z)
			var r := minf(size.x, size.z) * 0.5 + 0.08
			var n := maxi(1, int(ceil(length / 0.7)))
			for k in n:
				var q := xf.origin + long_ax * ((float(k) + 0.5) / n - 0.5) * length
				pts.append(Vector3(q.x, q.z, maxf(r, length / n * 0.6)))
	for q in pts:
		var key := Vector2i(floori(q.x / 2.0), floori(q.y / 2.0))
		if not _obs_grid.has(key):
			_obs_grid[key] = []
		_obs_grid[key].append(q)
	stats["ped_obstacles"] = pts.size()

func _separate() -> void:
	if not _obs_built and Engine.get_process_frames() > 30:
		_build_obstacles()
	var grid := {}
	var near: Array[NPC] = []
	for p in traffic.peds:
		if not is_instance_valid(p) or p.state == NPC.State.DEAD or not p.visible:
			continue
		var gp := p.global_position
		if absf(gp.x - _cam_pos.x) > SEP_RANGE or absf(gp.z - _cam_pos.z) > SEP_RANGE:
			if p.avoid != Vector3.ZERO:
				p.avoid = Vector3.ZERO
			continue
		near.append(p)
		var key := Vector2i(floori(gp.x / 1.5), floori(gp.z / 1.5))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)
	for p in near:
		if p.state != NPC.State.WALK:
			p.avoid = Vector3.ZERO
			continue
		var gp := p.global_position
		var push := Vector3.ZERO
		var cx := floori(gp.x / 1.5)
		var cz := floori(gp.z / 1.5)
		var heading := Vector3(p.velocity.x, 0.0, p.velocity.z)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for o in grid.get(Vector2i(cx + dx, cz + dz), []):
					if o == p or o == p.companion or (p.has_meta("leads") and p.get_meta("leads") == o):
						continue
					var d: Vector3 = gp - (o as NPC).global_position
					d.y = 0.0
					var dist := d.length()
					if dist < SEP_RADIUS and dist > 0.001:
						var w := (SEP_RADIUS - dist) / SEP_RADIUS
						# Pass beside someone ahead, not just bounce off them.
						var side := Vector3.UP.cross(heading.normalized()) if heading.length() > 0.2 else Vector3.ZERO
						if side != Vector3.ZERO and d.dot(side) < 0.0:
							side = -side
						push += (d / dist) * w * 1.6 + side * w * 0.8
		var ocx := floori(gp.x / 2.0)
		var ocz := floori(gp.z / 2.0)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for q in _obs_grid.get(Vector2i(ocx + dx, ocz + dz), []):
					var ob: Vector3 = q
					var d2 := Vector3(gp.x - ob.x, 0.0, gp.z - ob.y)
					var reach := ob.z + 0.55
					var dist2 := d2.length()
					if dist2 < reach and dist2 > 0.001:
						var w2 := (reach - dist2) / reach
						var side2 := Vector3.UP.cross(heading.normalized()) if heading.length() > 0.2 else Vector3.ZERO
						if side2 != Vector3.ZERO and d2.dot(side2) < 0.0:
							side2 = -side2
						push += (d2 / dist2) * w2 * 2.2 + side2 * w2 * 1.2
		p.avoid = push.limit_length(1.8)

## People in the path of the player's moving car jump clear (GTA-style),
## instead of standing in a crossing as an immovable wall.
func _dodge_player_vehicle() -> void:
	if Game.mode == Game.MODE_FOOT:
		# People step aside for the player on foot instead of standing as a
		# wall in a five-foot way (a talking pair blocked a route walk).
		var pp := Game.player_position
		for p in traffic.peds:
			if is_instance_valid(p) and not p.is_hostile and not p.is_police and p.state != NPC.State.DEAD and not p.has_meta("ambient_role") \
					and absf(p.global_position.x - pp.x) < 1.3 and absf(p.global_position.z - pp.z) < 1.3:
				p.scramble_from(pp)
		return
	if Game.mode != Game.MODE_CAR:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or player.get("current_vehicle") == null:
		return
	var car := player.current_vehicle as Node3D
	if car == null:
		return
	var vel: Vector3 = car.get("velocity") if car.get("velocity") != null else Vector3.ZERO
	vel.y = 0.0
	if vel.length() < 2.0:
		return
	var fwd := vel.normalized()
	var left := Vector3.UP.cross(fwd)
	var reach := 6.0 + vel.length() * 0.9
	for p in traffic.peds:
		if not is_instance_valid(p) or p.state == NPC.State.DEAD or p.is_hostile or p.is_police:
			continue
		var d: Vector3 = p.global_position - car.global_position
		var ahead := d.dot(fwd)
		if ahead > -1.0 and ahead < reach and absf(d.dot(left)) < 2.6:
			p.dodge_vehicle(car.global_position, fwd)

func _eligible(p: NPC) -> bool:
	if not is_instance_valid(p) or p.is_police or p.is_hostile:
		return false
	return p.state == NPC.State.WALK or p.state == NPC.State.IDLE

func _recycle(cut: bool) -> void:
	var budget := 400 if cut else 2
	var pending_pairs := {}
	for p in roamers:
		if budget <= 0:
			break
		if not _eligible(p):
			continue
		if p.has_meta("follower"):
			# Placed beside its leader when the leader is seeded; a follower
			# that has lost its leader is re-seeded with it next time.
			if p.companion == null:
				var lead: NPC = _leader_of(p)
				if lead != null and lead.global_position.distance_to(p.global_position) < 9.0:
					p.companion = lead
			continue
		var d := Vector2(p.global_position.x - _focus.x, p.global_position.z - _focus.z).length()
		if p.global_position.y > -10.0 and d < (SPAWN_RADIUS if cut else DESPAWN_RADIUS):
			continue
		if p.has_meta("loiter_pair"):
			var pair := int(p.get_meta("loiter_pair"))
			if pending_pairs.has(pair):
				var members: Array = pending_pairs[pair]
				_place_partner(p, members[0], members.size())
				members.append(p)
				budget -= 1
				continue
			if _seed(p, not cut, true):
				pending_pairs[pair] = [p]
				budget -= 1
			continue
		if _seed(p, not cut, false):
			budget -= 1
			if p.has_meta("leads"):
				_place_follower(p, p.get_meta("leads"))

## Keep every downtown polyline with at least two points; returns the count.
func adopt_downtown(lanes: Array) -> int:
	_polys.clear()
	for poly in lanes:
		if poly is Array and (poly as Array).size() >= 2:
			var pts: Array[Vector3] = []
			for q in poly:
				pts.append(Vector3((q as Vector3).x, (q as Vector3).y + 0.2, (q as Vector3).z))
			_polys.append(pts)
	return _polys.size()

## Polylines with a vertex inside the spawn radius of the focus.
func _near_polys() -> Array:
	var out: Array = []
	for poly in _polys:
		for q in poly:
			if Vector2((q as Vector3).x - _focus.x, (q as Vector3).z - _focus.z).length() < SPAWN_RADIUS:
				out.append(poly)
				break
	return out

func _seed_poly(p: NPC, hidden_only: bool, near: Array) -> bool:
	for attempt in 8:
		var pts: Array[Vector3] = near[_rng.randi_range(0, near.size() - 1)]
		var k := _rng.randi_range(0, pts.size() - 2)
		var pos: Vector3 = pts[k].lerp(pts[k + 1], _rng.randf_range(0.05, 0.95))
		var seg := pts[k + 1] - pts[k]
		seg.y = 0.0
		# Spread across the walk, not on one painted line.
		if seg.length() > 0.1:
			pos += Vector3.UP.cross(seg.normalized()) * _rng.randf_range(-1.4, 1.4)
		if Vector2(pos.x - _focus.x, pos.z - _focus.z).length() > SPAWN_RADIUS:
			continue
		if hidden_only:
			var rel := pos - _cam_pos
			rel.y = 0.0
			if rel.length() < 95.0 and rel.normalized().dot(_cam_fwd) > -0.25:
				continue
		if Vector2(pos.x - _cam_pos.x, pos.z - _cam_pos.z).length() < 7.0:
			continue
		p.lane = pts
		p.lane_dir = 1 if _rng.randf() < 0.5 else -1
		p.lane_index = k + 1 if p.lane_dir > 0 else k
		p.velocity = Vector3.ZERO
		p.global_position = pos
		p.visible = true
		var face: Vector3 = pts[p.lane_index] - pos
		face.y = 0.0
		if face.length() > 0.1:
			p.rotation.y = atan2(-face.x, -face.z)
		p.state = NPC.State.WALK
		p.idle_time = 0.0
		stats["relocated"] += 1
		stats["downtown"] = int(stats.get("downtown", 0)) + 1
		return true
	return false

func _seed(p: NPC, hidden_only: bool, loiter: bool) -> bool:
	if not _polys.is_empty() and not loiter:
		var near := _near_polys()
		# Outside the legacy district, people go on the downtown walks only;
		# inside it, the downtown walks take a share in proportion.
		var outside := absf(_focus.x) > 330.0 or absf(_focus.z) > 330.0
		if not near.is_empty() and (outside or _rng.randf() < 0.3) and _seed_poly(p, hidden_only, near):
			return true
	var spine_share := 0.5 if _cam_pos.y > 30.0 else 0.15
	if not loiter and _rng.randf() < spine_share and _seed_spine(p, hidden_only):
		return true
	# Street-level cameras: half the people go on the street being looked down.
	var view_lines: Array[Dictionary] = []
	if _cam_pos.y < 30.0 and (loiter or _rng.randf() < 0.7):
		var along_z := absf(_cam_fwd.z) > absf(_cam_fwd.x)
		for ln2 in _lines:
			var lat: float = _cam_pos.x if along_z else _cam_pos.z
			if int(ln2["axis"]) == (0 if along_z else 1) and absf(float(ln2["line"]) - lat) < 30.0:
				view_lines.append(ln2)
	for attempt in 12:
		var ln: Dictionary = _lines[_rng.randi_range(0, _lines.size() - 1)]
		if not view_lines.is_empty():
			ln = view_lines[_rng.randi_range(0, view_lines.size() - 1)]
		# M1: a personal distance from the kerb (not three painted lines), so
		# walkers seeded on one pavement do not form single-file columns.
		var off_idx := _rng.randi_range(0, OFFSETS.size() - 1)
		var off: float = OFFSETS[off_idx] + (_rng.randf_range(-0.35, 0.35) if off_idx < OFFSETS.size() - 1 else _rng.randf_range(-0.3, 0.15))
		var lateral: float = float(ln["line"]) + float(ln["side"]) * off
		var focus_lat := _focus.x if int(ln["axis"]) == 0 else _focus.z
		var focus_along := _focus.z if int(ln["axis"]) == 0 else _focus.x
		if absf(lateral - focus_lat) > SPAWN_RADIUS:
			continue
		var along := clampf(focus_along + _rng.randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), -326.0, 326.0)
		# Street-life D: on the street the camera looks down, most people go in
		# the 6-90 m in front of the lens, where they are actually seen.
		if not view_lines.is_empty() and not hidden_only and (loiter or _rng.randf() < 0.65):
			var cam_along := _cam_pos.z if int(ln["axis"]) == 0 else _cam_pos.x
			var fwd_along := _cam_fwd.z if int(ln["axis"]) == 0 else _cam_fwd.x
			# M2: half of those in the first ~35 m, where the eye reads people.
			var reach_far := 35.0 if _rng.randf() < 0.5 else 90.0
			along = clampf(cam_along + signf(fwd_along) * _rng.randf_range(6.0, reach_far), -326.0, 326.0)
		# Not on a crossing: people are seeded on the pavement, not mid-road.
		var on_crossing := false
		for j in WorldBuilder.Z_LINES:
			if absf(along - j) < 11.0:
				on_crossing = true
		if on_crossing:
			continue
		var pos := Vector3(lateral, 0.2, along) if int(ln["axis"]) == 0 else Vector3(along, 0.2, lateral)
		if Vector2(pos.x - _focus.x, pos.z - _focus.z).length() > SPAWN_RADIUS:
			continue
		if hidden_only:
			var rel := pos - _cam_pos
			rel.y = 0.0
			if rel.length() < 95.0 and rel.normalized().dot(_cam_fwd) > -0.25:
				continue
		if Vector2(pos.x - Game.player_position.x, pos.z - Game.player_position.z).length() < 4.0:
			continue
		# Never inside or against the lens (a hand filled a frame edge).
		if Vector2(pos.x - _cam_pos.x, pos.z - _cam_pos.z).length() < 7.0:
			continue
		_assign(p, ln, off, pos, loiter)
		return true
	return false

func _assign(p: NPC, ln: Dictionary, off: float, pos: Vector3, loiter: bool) -> void:
	var pts: Array[Vector3] = []
	var lateral: float = float(ln["line"]) + float(ln["side"]) * off
	for j in WorldBuilder.Z_LINES:
		pts.append(Vector3(lateral, 0.25, j) if int(ln["axis"]) == 0 else Vector3(j, 0.25, lateral))
	p.lane = pts
	p.lane_dir = 1 if _rng.randf() < 0.5 else -1
	var along := pos.z if int(ln["axis"]) == 0 else pos.x
	var idx := 0
	while idx < WorldBuilder.Z_LINES.size() - 1 and WorldBuilder.Z_LINES[idx] < along:
		idx += 1
	p.lane_index = idx if p.lane_dir > 0 else maxi(0, idx - 1)
	p.velocity = Vector3.ZERO
	p.global_position = pos
	p.visible = true
	var face: Vector3 = pts[p.lane_index] - pos
	face.y = 0.0
	if face.length() > 0.1:
		p.rotation.y = atan2(-face.x, -face.z)
	if loiter:
		p.state = NPC.State.IDLE
		p.idle_time = _rng.randf_range(25.0, 70.0)
	elif off > 11.0 and _rng.randf() < SHOPFRONT_SHARE:   # five-foot way
		# M1: window-shoppers and people waiting at a shopfront in the
		# five-foot way, facing the shop, before walking on.
		var shop := Vector3(float(ln["side"]), 0.0, 0.0) if int(ln["axis"]) == 0 else Vector3(0.0, 0.0, float(ln["side"]))
		p.rotation.y = atan2(-shop.x, -shop.z) + _rng.randf_range(-0.5, 0.5)
		p.state = NPC.State.IDLE
		p.idle_time = _rng.randf_range(8.0, 35.0)
		stats["shopfront"] = int(stats.get("shopfront", 0)) + 1
	else:
		p.state = NPC.State.WALK
		p.idle_time = 0.0
	stats["relocated"] += 1

func _seed_spine(p: NPC, hidden_only: bool) -> bool:
	for attempt in 8:
		var sp: Dictionary = _spines[_rng.randi_range(0, _spines.size() - 1)]
		var t := _rng.randf_range(0.05, 0.95)
		var pos: Vector3 = (sp["a"] as Vector3).lerp(sp["b"], t)
		if Vector2(pos.x - _focus.x, pos.z - _focus.z).length() > SPAWN_RADIUS:
			continue
		if hidden_only:
			var rel := pos - _cam_pos
			rel.y = 0.0
			if rel.length() < 95.0 and rel.normalized().dot(_cam_fwd) > -0.25:
				continue
		var pts: Array[Vector3] = [sp["a"], sp["b"]]
		p.lane = pts
		p.lane_dir = 1 if _rng.randf() < 0.5 else -1
		p.lane_index = 1 if p.lane_dir > 0 else 0
		p.velocity = Vector3.ZERO
		p.global_position = pos
		p.visible = true
		var face: Vector3 = pts[p.lane_index] - pos
		p.rotation.y = atan2(-face.x, -face.z)
		p.state = NPC.State.WALK
		stats["relocated"] += 1
		return true
	return false

func _leader_of(f: NPC) -> NPC:
	for r in roamers:
		if is_instance_valid(r) and r.has_meta("leads") and r.get_meta("leads") == f:
			return r
	return null

## M2: a follower walks beside its leader from the moment it is seeded.
func _place_follower(lead: NPC, f: NPC) -> void:
	if not is_instance_valid(f) or not _eligible(f):
		return
	var b := lead.global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	f.lane = lead.lane
	f.lane_dir = lead.lane_dir
	f.lane_index = lead.lane_index
	f.velocity = Vector3.ZERO
	f.global_position = lead.global_position + right * f.companion_side
	f.rotation.y = lead.rotation.y
	f.visible = true
	f.state = NPC.State.WALK
	f.companion = lead
	# A walking pair does not stand at a shopfront.
	if lead.state == NPC.State.IDLE:
		lead.state = NPC.State.WALK
		lead.idle_time = 0.0

## Second (and third) member of a talking group: the second stands facing
## the first a step away; the third closes a loose triangle.
func _place_partner(p: NPC, partner: NPC, index: int = 1) -> void:
	var side := Vector3(partner.global_transform.basis.x.x, 0.0, partner.global_transform.basis.x.z).normalized()
	var fwd := -Vector3(partner.global_transform.basis.z.x, 0.0, partner.global_transform.basis.z.z).normalized()
	if index >= 2:
		var c := partner.global_position + fwd * 0.6
		var pos3 := c + side * (0.95 if posmod(partner.get_instance_id(), 2) == 0 else -0.95) + fwd * 0.05
		p.lane = partner.lane
		p.lane_dir = partner.lane_dir
		p.lane_index = partner.lane_index
		p.velocity = Vector3.ZERO
		p.global_position = pos3
		p.visible = true
		p.rotation.y = atan2(-(c.x - pos3.x), -(c.z - pos3.z))
		p.state = NPC.State.IDLE
		p.idle_time = partner.idle_time + _rng.randf_range(-4.0, 4.0)
		stats["relocated"] += 1
		return
	var pos := partner.global_position + fwd * 1.15 + side * 0.25
	p.lane = partner.lane
	p.lane_dir = -partner.lane_dir
	p.lane_index = clampi(partner.lane_index - partner.lane_dir, 0, partner.lane.size() - 1)
	p.velocity = Vector3.ZERO
	p.global_position = pos
	p.visible = true
	p.rotation.y = partner.rotation.y + PI
	partner.rotation.y = atan2(-(pos.x - partner.global_position.x), -(pos.z - partner.global_position.z))
	p.state = NPC.State.IDLE
	p.idle_time = partner.idle_time + _rng.randf_range(-3.0, 3.0)
	stats["relocated"] += 1

## Living roamers within `radius` of `p`.
func count_near(p: Vector3, radius: float) -> int:
	var n := 0
	for r in roamers:
		if is_instance_valid(r) and r.state != NPC.State.DEAD and r.global_position.distance_to(p) < radius:
			n += 1
	return n
