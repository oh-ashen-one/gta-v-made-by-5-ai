extends Node3D
## Fixture-based mechanical checks, NOT evidence of walking here from heritage.
## Explicit fixture placement isolates the production E lift and real physics.
const Access = preload("res://src/world/downtown/skypark_access.gd")
var main: Node
var access: Node
var player: Player
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print("[skypark-test] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)

func frames(n: int = 3) -> void:
	for i in n: await get_tree().physics_frame

func press_e() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	await frames(2)
	Input.action_release("interact")
	await frames(3)

func place(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player._speed = 0.0
	player._fall_speed = 0.0
	await frames(8)

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	access = get_tree().get_first_node_in_group("skypark_access")
	check("production main creates SkyPark access", access != null and access.get_parent() == main)
	if access == null:
		print("[skypark-test] RESULT failed: production main hook missing; no automatic bootstrap")
		get_tree().quit(1)
		return
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	await frames(10)
	if "--skypark-combat-probe" in OS.get_cmdline_user_args():
		# Explicit short diagnostic fixture, not a replacement for the full suite.
		await place(Access.ground_position())
		await _visitor_combat_checks()
		print("[skypark-test] COMBAT_PROBE_RESULT %d/%d failures=%s" % [checks - failures.size(), checks, failures])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	check("remote and invalid station denied", not access.can_use_station("ground") and not access.can_use_station("missing"))
	check("ground arrival has floor and capsule clearance", access.destination_clear(Access.ground_position()))
	check("painted rooftop marker hint includes center", DowntownPlan.is_marked_landing_hint(Access.pad_position()))
	check("painted marker hint excludes adjacent unmarked deck (not exit refusal)", not DowntownPlan.is_marked_landing_hint(Access.pad_position() + Vector3(0, 0, 3)))
	check("other roofs and off-map points are not marked hints", not DowntownPlan.is_marked_landing_hint(Vector3(-118, 200, -705)) and not DowntownPlan.is_marked_landing_hint(Vector3(5000, 200, 5000)))
	check("existing ground navigation hints retained", DowntownPlan.is_marked_landing_hint(DowntownPlan.HELIPADS.ns_square.pos + Vector3(18, 0, 0)))
	check("roof arrival has floor and capsule clearance", access.destination_clear(Access.roof_position()))
	await place(Vector3(-325.0, 0.15, -632.0))
	check("north promenade entry ramp crosses without jump", await walk_to(Vector3(-310.0, 0.4, -632.0)))
	await place(Access.ground_position() + Vector3(0, -1.1, 18))
	check("Event Plaza ramp reaches lift on foot", await walk_to(Access.ground_position()))
	check("ground lift reachable", access.can_use_station("ground"))
	await still("ground_lift_approach")
	var health := Game.health
	Game.simulation_paused = true
	check("pause guard", not access.can_use_station("ground"))
	Game.simulation_paused = false
	player.busy = true
	check("busy guard", not access.can_use_station("ground"))
	player.busy = false
	Game.health = 0.0
	check("dead guard", not access.can_use_station("ground"))
	Game.health = health
	for mode in [Game.MODE_CAR, Game.MODE_HELI]:
		Game.mode = mode
		check("vehicle mode guard %d" % mode, not access.can_use_station("ground"))
	Game.mode = Game.MODE_FOOT
	player.current_vehicle = main.get_node("Helicopter")
	check("occupied vehicle guard independent of mode", not access.can_use_station("ground"))
	player.current_vehicle = null
	var stranger := Node.new()
	check("foreign actor guard", not access.use_station("ground", stranger))
	stranger.free()
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 0.2)
	cs.shape = box
	wall.add_child(cs)
	main.add_child(wall)
	wall.global_position = Access.ground_position() + Vector3(0, 1.5, -1)
	await frames()
	check("LOS wall denies direct interaction", not access.use_station("ground", player))
	wall.queue_free()
	await frames()
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(2, 3, 2)
	obstruction_shape.shape = obstruction_box
	obstruction.add_child(obstruction_shape)
	main.add_child(obstruction)
	obstruction.global_position = Access.roof_position() + Vector3.UP
	await frames()
	check("blocked arrival refuses lift without moving player", not access.use_station("ground", player) and player.global_position.distance_to(Access.ground_position()) < 1.5)
	obstruction.queue_free()
	await frames()
	# Let only this deliberately generated warning expire normally before
	# positive-flow stills. Do not clear the HUD or unrelated message history.
	await get_tree().create_timer(HUD.NOTIFICATION_LIFETIME + 0.1).timeout
	var fixture_notice_remains := false
	for notice in main.hud._notifications.get_children():
		if notice is Label and notice.text.begins_with("Lift arrival is obstructed."):
			fixture_notice_remains = true
	check("negative-fixture toast expires before positive still", not fixture_notice_remains)
	var activity_state: Dictionary = main.downtown_activity.serialize_state()
	var story: int = Game.mission_stage
	var wanted: int = Game.wanted_level
	await press_e()
	check("real E lifts to public terrace", player.global_position.distance_to(Access.roof_position()) < 0.5, str(player.global_position))
	await still("public_terrace_arrival")
	check("health story wanted and courier preserved", Game.health == health and Game.mission_stage == story and Game.wanted_level == wanted and main.downtown_activity.serialize_state() == activity_state)
	check("safe checkpoint remains reachable ground", Game.last_safe_position.distance_to(Access.ground_position()) < 0.01)
	check("immediate double use denied", not access.can_use_station("roof"))
	await place(Access.roof_position() + Vector3(-3, 0, 2))
	var saved_roof_position := player.global_position
	check("native save rooftop position", Game.save_game())
	await place(Access.ground_position())
	check("native load preserves exact rooftop position", Game.load_game() and player.global_position.distance_to(saved_roof_position) < 0.01)
	check("loaded player walks back to lift", await walk_to(Access.roof_position()))
	await frames(65)
	await press_e()
	check("real E returns to ground", player.global_position.distance_to(Access.ground_position()) < 0.5)
	await _terrace_checks()
	await _visitor_checks()
	await _heli_checks()
	await _flight_checks()
	await _death_checks()
	await _fresh_scene_save_checks()
	await _visitor_combat_checks()
	print("[skypark-test] RESULT %d/%d failures=%s" % [checks - failures.size(), checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)

func _terrace_checks() -> void:
	var m := DowntownPlan.anchor("marina_bay_sands")
	var space := get_world_3d().direct_space_state
	var floors := true
	for x in range(32, 84, 4):
		for z in range(-2, 14, 3):
			var at := m + Vector3(x, 200, z + 2)
			var floor_ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at - Vector3.UP, 1)
			# Probe the supporting authored deck below the new benches/headhouse;
			# those props are not missing floor and have their own solid collision.
			floor_ray.exclude = [access.get_node("SkyParkPublicCollision").get_rid()]
			var hit := space.intersect_ray(floor_ray)
			if hit.is_empty() or absf(hit.position.y - 200.0) > 0.1: floors = false
	check("public terrace floor continuous", floors)
	for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var origin := m + Vector3(55, 201.2, 7)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + dir * 80, 1))
		check("visible boundary has collision %s" % dir, not hit.is_empty())
	# Real controller moves and repeatedly jumps toward every terrace boundary.
	for dir: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		await place(m + Vector3(55, 200.1, 7))
		player.yaw = atan2(-dir.x, -dir.z)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		for i in 240:
			if i % 35 == 0: Input.action_press("jump")
			if i % 35 == 3: Input.action_release("jump")
			await get_tree().physics_frame
		Input.action_release("move_forward")
		Input.action_release("sprint")
		Input.action_release("jump")
		await frames(8)
		check("controller cannot jump past terrace %s" % dir, Access.on_public_terrace(player.global_position, 0.1), str(player.global_position))

func _heli_checks() -> void:
	# Each case deliberately repositions the unoccupied aircraft as a fixture.
	# Boarding is fixture setup; the real player E path must perform every exit.
	var heli: Helicopter = main.get_node("Helicopter")
	var cases: Array[Dictionary] = []
	for degrees in [0, 45, 90, 135, 180, 225, 270, 315]:
		cases.append({"heading": degrees, "offset": Vector3.ZERO, "allowed": true, "label": "center heading %d" % degrees})
	for degrees in [0, 45, 90, 135, 180, 225, 270, 315]:
		var direction := Vector3(cos(deg_to_rad(degrees)), 0, sin(deg_to_rad(degrees)))
		var radius := 2.5 if degrees % 90 == 0 else 2.49
		cases.append({"heading": degrees, "offset": direction * radius, "allowed": true, "label": "boundary %.2fm heading %d" % [radius, degrees]})
	for degrees in [0, 90, 180, 270]:
		var direction := Vector3(cos(deg_to_rad(degrees)), 0, sin(deg_to_rad(degrees)))
		cases.append({"heading": degrees, "offset": direction * 2.6, "allowed": true, "label": "adjacent unmarked deck %d" % degrees})
	for sample in cases:
		# Explicit cleanup after a refused-exit case. Never counted as traversal.
		if player.current_vehicle != null:
			player.respawn_at(Access.roof_position(), PI)
		await place(Access.roof_position())
		heli.global_position = Access.pad_position() + sample.offset + Vector3.UP * 0.5
		heli.rotation.y = deg_to_rad(sample.heading)
		heli.velocity = Vector3.ZERO
		await frames(35)
		check("supported aircraft " + sample.label, heli.is_on_floor() and absf(heli.global_position.y - 200) < 1, str(heli.global_position))
		heli.interact(player) # labelled fixture boarding, not a traversal claim
		await frames(5)
		await press_e()
		if sample.allowed:
			check("real E exit " + sample.label, player.current_vehicle == null and not heli.pilot_is_player and Access.on_public_terrace(player.global_position))
			await frames(12)
			check("supported visible pilot " + sample.label, player.is_on_floor() and player.visible and player.alive and player.collision_layer == 2 and player.collision_mask == Player.COLLIDE_MASK and Game.mode == Game.MODE_FOOT)
		else:
			check("real E refused " + sample.label, player.current_vehicle == heli and heli.pilot_is_player and Game.mode == Game.MODE_HELI)
	if player.current_vehicle != null:
		player.respawn_at(Access.roof_position(), PI) # cleanup refused-exit fixture
	# Independent conservative swept volume includes the permitted offset.
	var clear_rotor := true
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 6.0
	shape.height = 5.0
	q.shape = shape
	q.collision_mask = 1
	for offset: Vector3 in [Vector3.ZERO, Vector3.LEFT * 2.5, Vector3.RIGHT * 2.5, Vector3.FORWARD * 2.5, Vector3.BACK * 2.5]:
		q.transform = Transform3D(Basis.IDENTITY, Access.pad_position() + offset + Vector3.UP * 2.6)
		clear_rotor = clear_rotor and get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
	check("6m rotor and tail cylinder at allowed exit boundary", clear_rotor)

func walk_to(target: Vector3) -> bool:
	Input.action_press("move_forward")
	for i in 600:
		var d := target - player.global_position
		d.y = 0
		if d.length() < 1.4:
			Input.action_release("move_forward")
			await frames(10)
			return true
		player.yaw = atan2(-d.x, -d.z)
		await get_tree().physics_frame
	Input.action_release("move_forward")
	return false

func _flight_checks() -> void:
	var heli: Helicopter = main.get_node("Helicopter")
	# The only flight fixture placement: airborne south of the deck, with
	# player already boarding. No positions/rotations/velocities are assigned
	# between this starting fixture and touchdown/exit/return by controls.
	heli.global_position = Access.pad_position() + Vector3(0, 12, 30)
	heli.rotation.y = 0.0
	heli.velocity = Vector3.ZERO
	heli.interact(player)
	var initial := heli.global_position
	Input.action_press("jump", 0.7)
	await frames(60)
	Input.action_release("jump")
	check("flight controls ascend", heli.global_position.y > initial.y + 2.0)
	var landed := false
	var max_step := 0.0
	var previous := heli.global_position
	for i in 1800:
		var dz := heli.global_position.z - Access.pad_position().z
		var command := clampf(dz * 0.035 + heli.velocity.z * 0.045, -0.35, 0.35)
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if command > 0: Input.action_press("move_forward", command)
		else: Input.action_press("move_back", -command)
		Input.action_release("sprint")
		if absf(dz) < 1.0 and absf(heli.velocity.z) < 0.8:
			Input.action_press("sprint", 0.7)
		await get_tree().physics_frame
		max_step = maxf(max_step, heli.global_position.distance_to(previous))
		previous = heli.global_position
		if heli.is_landed():
			landed = true
			break
	for action in ["move_forward", "move_back", "sprint", "jump"]: Input.action_release(action)
	await frames(20)
	check("input flight lands at selected painted target", landed and DowntownPlan.is_marked_landing_hint(heli.global_position), str(heli.global_position))
	check("flight leg has no teleport", max_step < 1.0, "max_step=%.3f" % max_step)
	check("flight aircraft undamaged", heli.health == 100.0)
	await still("flight_landed_pad")
	await press_e()
	check("E exits landed helicopter", player.current_vehicle == null and Access.on_public_terrace(player.global_position))
	if player.current_vehicle == null:
		await still("flight_pilot_on_terrace")
		check("flight pilot walks to public lift", await walk_to(Access.roof_position()) and access.can_use_station("roof"))
		await press_e()
		check("flight pilot returns to Event Plaza by E", player.global_position.distance_to(Access.ground_position()) < 0.6)

func still(label: String) -> void:
	# Optional parent-owned rendered review; no renderer is launched by this test.
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skypark-stills-dir="):
			output = arg.trim_prefix("--skypark-stills-dir=")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await frames(15)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))

func _death_checks() -> void:
	# Arrive via the actual lift after the previous flight returned to ground.
	await frames(65)
	await press_e()
	check("death test reaches roof through E", Access.on_public_terrace(player.global_position))
	var deaths := Game.death_count
	Game.damage_player(Game.MAX_HEALTH) # normal production lethal-damage path
	await frames(12)
	check("rooftop death recovers once at ground", Game.death_count == deaths + 1 and player.global_position.distance_to(Access.ground_position()) < 0.6)
	check("death recovery restores live visible foot controller", Game.health == Game.MAX_HEALTH and player.alive and player.visible and player.current_vehicle == null and not player.busy and Game.mode == Game.MODE_FOOT and player.collision_layer == 2 and player.collision_mask == Player.COLLIDE_MASK and player.is_on_floor())
	check("recovered controller walks normally", await walk_to(Access.ground_position() + Vector3(4, 0, 0)))
	check("recovered controller returns to lift", await walk_to(Access.ground_position()))
	await press_e()
	check("lift reusable after death", Access.on_public_terrace(player.global_position))

func _fresh_scene_save_checks() -> void:
	# Save a legitimate roof position, destroy the entire game scene, rebuild
	# normal main (including its production access hook), then native-load it.
	check("fresh-scene fixture starts on public terrace", Access.on_public_terrace(player.global_position))
	check("walk to distinct rooftop save position", await walk_to(Access.roof_position() + Vector3(-3, 0, 2)))
	await frames(3)
	var saved_position := player.global_position
	check("save before scene teardown", Game.save_game())
	main.queue_free()
	player = null
	access = null
	await frames(5)
	check("old scene fully removed", get_tree().get_nodes_in_group("player").is_empty() and get_tree().get_nodes_in_group("skypark_access").is_empty())
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	access = get_tree().get_first_node_in_group("skypark_access")
	check("fresh production main creates one access controller", access != null and get_tree().get_nodes_in_group("skypark_access").size() == 1)
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	await frames(10)
	check("fresh-scene native load keeps exact rooftop position", Game.load_game() and player.global_position.distance_to(saved_position) < 0.01)
	await frames(12)
	check("fresh-scene loaded player has floor and live controls", player.is_on_floor() and player.alive and player.visible and player.collision_layer == 2 and player.collision_mask == Player.COLLIDE_MASK and Game.mode == Game.MODE_FOOT)
	check("fresh-scene loaded player walks to return lift", await walk_to(Access.roof_position()))
	await press_e()
	check("fresh-scene return lift works through E", player.global_position.distance_to(Access.ground_position()) < 0.6)

func _visitor_checks() -> void:
	var visitors: Array = get_tree().get_nodes_in_group("skypark_visitors")
	check("three actual roof NPC visitors", visitors.size() == 3)
	for visitor in visitors:
		check("visitor has live NPC floor and character", visitor is NPC and visitor.is_on_floor() and visitor.character_visual != null and visitor.character_visual.loaded and visitor.collision_layer == 4)
	var m := DowntownPlan.anchor("marina_bay_sands")
	check("walk to furnished viewing area", await walk_to(m + Vector3(43, 200.1, 5)))
	player.yaw = atan2(6.0, -9.0)
	await still("terrace_viewing_area")
	# Dispatch the actual production signal consumed by NPC._on_shot_fired.
	# This is an explicitly labelled shot-event fixture, not a bullet hit.
	Events.shot_fired.emit(m + Vector3(41, 201, 9), Vector3.LEFT, "pistol")
	await frames(2)
	var reacted := true
	for visitor in visitors:
		reacted = reacted and visitor.state == NPC.State.FLEE
	check("real shot event dispatch panics all visitors", reacted)
	for i in 780:
		await get_tree().physics_frame
		for visitor in visitors:
			if Vector2(visitor.global_position.x - Access.pad_position().x, visitor.global_position.z - Access.pad_position().z).length() <= 9.0:
				check("panicking visitors stay outside aircraft clearance", false)
				return
	check("panicking visitors stay outside aircraft clearance", true)
	for visitor in visitors:
		check("visitor settles back to roof-local idle", Access.on_public_terrace(visitor.global_position, 0.3) and visitor.is_on_floor() and visitor.state == NPC.State.IDLE)

func _visitor_combat_checks() -> void:
	# Run damaging fixtures AFTER all positive-flow screenshots and the fresh
	# scene test. Never conceal a corpse or pretend fixture damage is normal
	# arrival presentation. Initial placements below are explicit fixtures.
	var visitors := get_tree().get_nodes_in_group("skypark_visitors")
	if visitors.size() != 3:
		check("combat fixtures have fresh roof visitors", false)
		return
	var actor: NPC = visitors[0]
	var m := DowntownPlan.anchor("marina_bay_sands")
	await frames(65)
	await press_e()
	check("combat observer reaches roof by E", Access.on_public_terrace(player.global_position))
	check("combat observer walks near viewing area", await walk_to(m + Vector3(46, 200.1, 7)))
	await frames(12) # native NPC render/animation LOD catches up to nearby player
	var viewing: Rect2 = actor.get("viewing_bounds")
	var east_boundary := viewing.end.x - m.x
	var cases := [
		{"at": Vector3(east_boundary, 200.1, 7), "push": Vector3.RIGHT, "name": "east toward pad"},
		{"at": Vector3(32.1, 200.1, 7), "push": Vector3.LEFT, "name": "west toward rail"},
		{"at": Vector3(38, 200.1, 15), "push": Vector3.BACK, "name": "bay edge"},
		{"at": Vector3(39, 200.1, 2.5), "push": Vector3.FORWARD, "name": "landward edge"},
	]
	for sample in cases:
		actor.global_position = m + sample.at
		actor.health = 100.0 # explicit fresh-health nonlethal fixture
		actor.velocity = Vector3.ZERO
		actor.state = NPC.State.IDLE
		actor.idle_time = 1.0e9
		await frames(12)
		var health_before := actor.health
		var start_position := actor.global_position
		var fx := CombatFx.get_fx(get_tree())
		var flinches_before := int(fx.stats.get("flinch", 0))
		actor.take_damage(45.0, actor.global_position - sample.push * 2.0, false)
		check("native nonlethal damage and stagger " + sample.name, actor.health == health_before - 45.0 and actor.state == NPC.State.FLEE and int(fx.stats.get("flinch", 0)) == flinches_before + 1)
		var nearest := INF
		var max_motion := 0.0
		var stayed_on_terrace := true
		for i in 60:
			await get_tree().physics_frame
			await get_tree().process_frame # CombatFx stagger moves in _process
			nearest = minf(nearest, Vector2(actor.global_position.x - Access.pad_position().x, actor.global_position.z - Access.pad_position().z).length())
			max_motion = maxf(max_motion, actor.global_position.distance_to(start_position))
			stayed_on_terrace = stayed_on_terrace and Access.on_public_terrace(actor.global_position, 0.1)
		check("live damage fixture clears aircraft " + sample.name, nearest > 9.0 and stayed_on_terrace and actor.health > 0.0 and max_motion > 0.02, "nearest_pad=%.3f moved=%.3f" % [nearest, max_motion])
	# One lethal hit from the closest viewing boundary, directed toward the
	# pad. Measure the actual physical bones, not the now-noncolliding NPC root.
	var victim: NPC = visitors[1]
	victim.global_position = m + Vector3(east_boundary, 200.1, 7)
	victim.velocity = Vector3.ZERO
	victim.state = NPC.State.IDLE
	victim.idle_time = 1.0e9
	await frames(12)
	var started_before := Ragdoll.started
	var blowups_before := Ragdoll.blowups
	victim.take_damage(150.0, victim.global_position - Vector3.RIGHT * 2.0, false)
	await frames(2) # capture the active phase before a possible guard fallback
	var simulator := victim.character_visual.skeleton.get_node_or_null("Ragdoll")
	check("native lethal damage creates independent ragdoll", victim.state == NPC.State.DEAD and victim.health <= 0.0 and victim.collision_layer == 0 and simulator != null and Ragdoll.started == started_before + 1)
	if simulator == null: return
	var bones: Array[PhysicalBone3D] = []
	var initial: Dictionary = {}
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			bones.append(child)
			initial[child.get_instance_id()] = child.global_position
	var nearest_bone := INF
	var min_y := INF
	var min_sample: Dictionary = {}
	var active_min_node_y := INF
	var active_min_body_y := INF
	var active_samples := 0
	var fallback_min_node_y := INF
	var fallback_min_body_y := INF
	var max_motion := 0.0
	var stayed_over_deck := true
	for i in 183:
		await get_tree().physics_frame
		await get_tree().process_frame
		for bone in bones:
			var p: Vector3 = bone.global_position
			var physics_xf: Transform3D = PhysicsServer3D.body_get_state(bone.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			var simulating: bool = simulator.is_simulating_physics()
			var guard_tripped := false
			for guard in simulator.get_children():
				if guard is Ragdoll.RagdollGuard: guard_tripped = guard.tripped
			if simulating and simulator.influence > 0.5 and not guard_tripped:
				active_samples += 1
				active_min_node_y = minf(active_min_node_y, p.y)
				active_min_body_y = minf(active_min_body_y, physics_xf.origin.y)
			else:
				fallback_min_node_y = minf(fallback_min_node_y, p.y)
				fallback_min_body_y = minf(fallback_min_body_y, physics_xf.origin.y)
			nearest_bone = minf(nearest_bone, Vector2(p.x - Access.pad_position().x, p.z - Access.pad_position().z).length())
			if p.y < min_y:
				min_y = p.y
				var skeleton: Skeleton3D = victim.character_visual.skeleton
				var bone_index := skeleton.find_bone(bone.bone_name)
				var pose_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin if bone_index >= 0 else Vector3.INF
				min_sample = {"frame": i, "bone": String(bone.name), "bone_node_world": str(p), "physics_body_world": str(physics_xf.origin), "actor_root_world": str(victim.global_position), "visual_root_world": str(victim.character_visual.global_position), "skeleton_root_world": str(skeleton.global_position), "skeletal_pose_world": str(pose_world), "simulating": simulating, "influence": simulator.influence, "guard_tripped": guard_tripped}
			max_motion = maxf(max_motion, p.distance_to(initial[bone.get_instance_id()]))
			stayed_over_deck = stayed_over_deck and Access.TERRACE.has_point(Vector2(p.x - m.x, p.z - m.z - 2.0))
	check("lethal fixture simulates native physical bones", bones.size() == Ragdoll.BODIES.size() and bones.size() >= 10 and max_motion > 0.1, "bones=%d motion=%.3f" % [bones.size(), max_motion])
	check("native ragdoll solver remains stable", Ragdoll.blowups == blowups_before, "blowups=%d" % (Ragdoll.blowups - blowups_before))
	check("observed lethal fixture remains clear of aircraft", nearest_bone > 9.0, "nearest_bone_pad=%.3f" % nearest_bone)
	check("ragdoll bone-node floor gate includes fallback state", min_y > 199.7 and stayed_over_deck, "min_y=%.3f over_deck=%s" % [min_y, stayed_over_deck])
	print("[skypark-test] RAGDOLL_PHASES " + JSON.stringify({"active_samples": active_samples, "active_min_node_y": active_min_node_y, "active_min_body_y": active_min_body_y, "fallback_min_node_y": fallback_min_node_y, "fallback_min_body_y": fallback_min_body_y}))
	print("[skypark-test] RAGDOLL_MIN_SAMPLE " + JSON.stringify(min_sample))
	print("[skypark-test] RAGDOLL_NATIVE_GUARD " + Ragdoll.last_blowup)
	print("[skypark-test] RAGDOLL_SCOPE one native lethal fixture; post-fallback node floor failure is not rendered mesh-floor proof; stability failure remains")
	player.yaw = PI * 0.5
	player.pitch = -0.25
	await still("combat_ragdoll_after_fallback")
