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

const EXTRA_WALKERS := 64
const LOITER_PAIRS := 9
const SPAWN_RADIUS := 115.0
const DESPAWN_RADIUS := 135.0
## Pavement lines: just behind the kerb, mid-pavement, and the five-foot way.
const OFFSETS: Array[float] = [9.75, 10.5, 11.35]

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
	for ped in t.peds:
		if is_instance_valid(ped) and ped.has_meta("roamer"):
			roamers.append(ped)
	for i in EXTRA_WALKERS:
		var npc := NPC.new()
		npc.set_meta("roamer", true)
		if i < LOITER_PAIRS * 2:
			npc.set_meta("loiter_pair", i / 2)
		t.add_child(npc)
		npc.global_position = Vector3(0.0, -40.0 - i * 0.5, 0.0)
		t.peds.append(npc)
		roamers.append(npc)

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
	if cut and "--street-debug" in OS.get_cmdline_user_args():
		var cnt := 0
		var vis := 0
		for r in roamers:
			if r.global_position.distance_to(_focus) < SPAWN_RADIUS + 5.0:
				cnt += 1
				if r.global_position.distance_to(_cam_pos) < NPC.FAR_DRAW_RANGE:
					vis += 1
		print("[crowd-debug] cut focus=", _focus.round(), " cam=", _cam_pos.round(), " near=", cnt, " in_draw_range=", vis, " roamers=", roamers.size())

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
		var d := Vector2(p.global_position.x - _focus.x, p.global_position.z - _focus.z).length()
		if p.global_position.y > -10.0 and d < (SPAWN_RADIUS if cut else DESPAWN_RADIUS):
			continue
		if p.has_meta("loiter_pair"):
			var pair := int(p.get_meta("loiter_pair"))
			if pending_pairs.has(pair):
				var partner: NPC = pending_pairs[pair]
				_place_partner(p, partner)
				budget -= 1
				continue
			if _seed(p, not cut, true):
				pending_pairs[pair] = p
				budget -= 1
			continue
		if _seed(p, not cut, false):
			budget -= 1

func _seed(p: NPC, hidden_only: bool, loiter: bool) -> bool:
	var spine_share := 0.5 if _cam_pos.y > 30.0 else 0.15
	if not loiter and _rng.randf() < spine_share and _seed_spine(p, hidden_only):
		return true
	# Street-level cameras: half the people go on the street being looked down.
	var view_lines: Array[Dictionary] = []
	if _cam_pos.y < 30.0 and _rng.randf() < 0.7:
		var along_z := absf(_cam_fwd.z) > absf(_cam_fwd.x)
		for ln2 in _lines:
			var lat: float = _cam_pos.x if along_z else _cam_pos.z
			if int(ln2["axis"]) == (0 if along_z else 1) and absf(float(ln2["line"]) - lat) < 30.0:
				view_lines.append(ln2)
	for attempt in 12:
		var ln: Dictionary = _lines[_rng.randi_range(0, _lines.size() - 1)]
		if not view_lines.is_empty():
			ln = view_lines[_rng.randi_range(0, view_lines.size() - 1)]
		var off: float = OFFSETS[_rng.randi_range(0, OFFSETS.size() - 1)]
		var lateral: float = float(ln["line"]) + float(ln["side"]) * off
		var focus_lat := _focus.x if int(ln["axis"]) == 0 else _focus.z
		var focus_along := _focus.z if int(ln["axis"]) == 0 else _focus.x
		if absf(lateral - focus_lat) > SPAWN_RADIUS:
			continue
		var along := clampf(focus_along + _rng.randf_range(-SPAWN_RADIUS, SPAWN_RADIUS), -326.0, 326.0)
		# Street-life D: on the street the camera looks down, most people go in
		# the 6-90 m in front of the lens, where they are actually seen.
		if not view_lines.is_empty() and not hidden_only and _rng.randf() < 0.65:
			var cam_along := _cam_pos.z if int(ln["axis"]) == 0 else _cam_pos.x
			var fwd_along := _cam_fwd.z if int(ln["axis"]) == 0 else _cam_fwd.x
			along = clampf(cam_along + signf(fwd_along) * _rng.randf_range(6.0, 90.0), -326.0, 326.0)
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

## Second member of a talking pair: stands facing the first, a step away.
func _place_partner(p: NPC, partner: NPC) -> void:
	var side := Vector3(partner.global_transform.basis.x.x, 0.0, partner.global_transform.basis.x.z).normalized()
	var fwd := -Vector3(partner.global_transform.basis.z.x, 0.0, partner.global_transform.basis.z.z).normalized()
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
