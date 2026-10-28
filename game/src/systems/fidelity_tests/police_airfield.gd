extends Node3D
## Production-world fixture for the two former decorative airfield officers.
## Positioning the player/camera below is explicit test setup, not a traversal.
var main: Node
var checks := 0
var failures: Array[String] = []

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("Airfield police verification requires an isolated --qa-session")
		get_tree().quit(2)
		return
	_run.call_deferred()

func check(label: String, ok: bool, detail: String = "") -> bool:
	checks += 1
	print("[police-airfield] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)
	return ok

func frames(n: int = 3) -> void:
	for i in n: await get_tree().physics_frame

func floor_below(actor: NPC) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP * 0.1, actor.global_position - Vector3.UP * 0.5, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)

func ray_at(actor: NPC) -> Dictionary:
	var chest := actor.global_position + Vector3.UP * 1.05
	var q := PhysicsRayQueryParameters3D.create(chest + Vector3(0, 0, -3), chest + Vector3(0, 0, 0.5), 1 | 4 | 8)
	return get_world_3d().direct_space_state.intersect_ray(q)

func still(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--police-stills-dir="): dir = arg.trim_prefix("--police-stills-dir=")
	if dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var file := dir.path_join(label + ".png")
	check("actual rendered still " + label, get_viewport().get_texture().get_image().save_png(file) == OK, file)

func _run() -> void:
	main = load("res://main.tscn").instantiate()
	add_child(main)
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	Game.set_wanted(0)
	Game.wanted_heat = 0.0
	await frames(35)
	var traffic: TrafficManager = main.traffic
	var staff := get_tree().get_nodes_in_group("airfield_officers")
	check("exactly two real airfield officer actors", staff.size() == 2 and traffic.airfield_officers.size() == 2)
	if staff.size() != 2:
		finish()
		return
	var static_decoys := 0
	for n in main.world.find_children("*", "Node", true, false):
		if n.scene_file_path.ends_with("/officer_clean.glb"): static_decoys += 1
	check("raw decorative officer decoys removed", static_decoys == 0)
	for i in staff.size():
		var officer: NPC = staff[i]
		var ground := floor_below(officer)
		var surface_y: float = (ground.get("position", Vector3(0,-100,0)) as Vector3).y
		# NPC root is 0.02m below the capsule sole by design; compare the
		# sole/visual root rather than incorrectly requiring root >= floor.
		var sole_y := officer.global_position.y + officer.body_root.position.y
		check("officer %d stands on a supported floor" % i, officer.is_on_floor() and not ground.is_empty() and absf(sole_y - surface_y) < 0.08, "root=%s sole_y=%.3f floor=%.3f" % [officer.global_position, sole_y, surface_y])
		check("officer %d is visible, alive, loaded and damageable" % i, officer.is_visible_in_tree() and officer.is_police and officer.health == 100.0 and officer.state != NPC.State.DEAD and officer.collision_layer == 4 and officer.character_visual != null and officer.character_visual.loaded)
		if officer.character_visual != null and officer.character_visual.loaded:
			var sk: Skeleton3D = officer.character_visual.skeleton
			var foot_sole := INF
			for name in ["foot.l", "foot.r"]:
				var bone := sk.find_bone(name)
				if bone >= 0: foot_sole = minf(foot_sole, (sk.global_transform * sk.get_bone_global_pose(bone).origin).y - 0.09)
			check("officer %d rig feet are not buried or floating" % i, foot_sole >= surface_y - 0.12 and foot_sole <= surface_y + 0.2, "rig_sole=%.3f floor=%.3f" % [foot_sole, surface_y])
		var ray := ray_at(officer)
		check("real bullet-layer ray identifies officer %d" % i, ray.get("collider") == officer and officer.has_method("take_damage"))
	var player: Player = main.player
	var middle: Vector3 = ((staff[0] as NPC).global_position + (staff[1] as NPC).global_position) * 0.5
	player.respawn_at(middle + Vector3(0, 0.1, -9), PI)
	await frames(10)
	await still("airfield_officers_grounded")
	# A full player firing-path fixture, not a direct health assignment.
	var target: NPC = staff[0]
	print("[police-airfield] FIXTURE player/camera placed beside aviation post for actual Player._fire")
	player.respawn_at(target.global_position + Vector3(0, 0.1, -5), PI)
	await frames(10)
	player.camera.current = true
	player.camera.global_position = target.global_position + Vector3(0, 1.05, -4)
	player.camera.look_at(target.global_position + Vector3.UP * 1.05, Vector3.UP)
	Game.switch_weapon("pistol")
	Game.ammo["pistol"] = {"mag": 12, "reserve": 96}
	player._fire_cooldown = 0.0
	var health_before := target.health
	player._fire()
	check("actual player bullet damages former decorative officer", is_equal_approx(target.health, health_before - 34.0), "health=%.2f" % target.health)
	check("hit officer reacts as a live cop", target.state == NPC.State.PURSUE and target.character_visual != null and target.character_visual._one_shot)
	check("other officer is not damaged by the same bullet", (staff[1] as NPC).health == 100.0)
	await still("airfield_officer_after_player_hit")
	# Dispatch a second actual ray to the other officer and use the same
	# collision-identified take_damage path as player/NPC bullets.
	var other: NPC = staff[1]
	var hit := ray_at(other)
	if check("second officer remains ray-targetable", hit.get("collider") == other):
		(hit["collider"] as NPC).take_damage(34.0, hit["position"] - Vector3.FORWARD * 3.0, false)
		check("second officer takes damage and reacts", other.health == 66.0 and other.state == NPC.State.PURSUE)
	# Ordinary wanted-level cleanup must not hide these permanent posts.
	Game.set_wanted(0)
	Game.wanted_heat = 0.0
	traffic._update_police(0.0)
	check("airfield officers persist when no pursuit is active", target.is_visible_in_tree() and other.is_visible_in_tree() and traffic.airfield_officers.size() == 2 and not traffic._officer_pool.has(target) and not traffic._officer_pool.has(other))
	# Pool initialization used to set defaults before _ready overwrote them.
	var inactive := true
	for officer in traffic._officer_pool:
		inactive = inactive and officer.pooled_inactive and not officer.is_visible_in_tree() and officer.collision_layer == 0 and officer.collision_mask == 0 and not officer.is_physics_processing() and officer.process_mode == Node.PROCESS_MODE_DISABLED
	check("reserve pool stays invisible, non-colliding and inert after ready", inactive and traffic._officer_pool.size() == TrafficManager.OFFICER_POOL_SIZE)
	var reserve := traffic._officer_pool[0]
	var reserve_health := reserve.health
	reserve.take_damage(999.0, reserve.global_position, false)
	Events.shot_fired.emit(reserve.global_position, Vector3.FORWARD, "pistol")
	check("inactive reserve ignores direct damage/shot events", reserve.health == reserve_health and reserve.state == NPC.State.IDLE)
	var hidden_ray := ray_at(reserve)
	check("inactive reserve cannot be hit by bullet layers", hidden_ray.is_empty())
	# A held/elevated spot must be projected to support and stale fall/pose
	# data must not follow a responder out of the pool.
	var spawn: Vector3 = main.world.locations["aviation_officer_0"] + Vector3(-3, 2, -4)
	var actor := traffic._take_officer(spawn)
	if check("reserve activates on supported clear airfield surface", actor != null):
		check("active reserve has collision, life and no carried falling velocity", actor.health == 100.0 and actor.collision_layer == 4 and actor.collision_mask == (1 | 4) and actor.velocity == Vector3.ZERO and not actor.pooled_inactive and actor.is_physics_processing())
		actor.velocity = Vector3(2, -45, 3)
		actor.health = 5.0
		actor.body_root.position.y = -0.7
		actor.body_root.rotation.x = 1.0
		traffic._recycle_officer(actor)
		check("recycle disables body and clears velocity", actor.pooled_inactive and actor.collision_layer == 0 and actor.velocity == Vector3.ZERO)
		var reused := traffic._take_officer(spawn)
		check("same reserve reactivates with restored capsule/visual origin", reused == actor and reused.health == 100.0 and reused.velocity == Vector3.ZERO and reused.body_root.position.is_equal_approx(Vector3(0, 0.02, 0)) and reused.body_root.rotation.is_equal_approx(Vector3.ZERO))
		traffic._recycle_officer(actor)
	var pool_count := traffic._officer_pool.size()
	check("unsupported spawn is rejected without consuming reserve", traffic._take_officer(Vector3(10000, 300, 10000)) == null and traffic._officer_pool.size() == pool_count)
	target.take_damage(200.0, player.global_position, false)
	check("airfield officer can die normally", target.state == NPC.State.DEAD and target.health <= 0.0 and target.collision_layer == 0)
	finish()

func finish() -> void:
	print("[police-airfield] RESULT %d/%d failures=%s" % [checks - failures.size(), checks, failures])
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
