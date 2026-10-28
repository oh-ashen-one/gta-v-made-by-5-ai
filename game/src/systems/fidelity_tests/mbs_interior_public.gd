extends Node3D
## Mechanical/public-stage test, not full MBS or city acceptance.
## Source placement is measured first. Then the whole module is translated
## as one unit into a labeled controller fixture, preserving metres/rotation.
const PublicL1 = preload("res://src/world/mbs_interior/public_l1.gd")
const Reference = preload("res://src/world/mbs_interior/site_reference.gd")
var interior: Node3D
var player: Player
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var _started := 0
var _track := false
var _last := Vector3.ZERO
var _travel := 0.0
var _max_step := 0.0
var _minimum_y := INF
var _maximum_y := -INF
var _finished := false
var _probe_shape: Shape3D
var _probe_local_transform := Transform3D.IDENTITY
var _probe_mask := 0
var _player_layer := 0
var _probe_margin := 0.01

func _ready() -> void:
	if not "--qa-session" in OS.get_cmdline_user_args():
		push_error("MBS public interior test requires isolated --qa-session")
		get_tree().quit(2)
		return
	get_tree().create_timer(240.0, true, true).timeout.connect(func():
		if not _finished:
			check("bounded public-stage completion", false, "240s watchdog")
			finish())
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not _track or not is_instance_valid(player): return
	var distance := player.global_position.distance_to(_last)
	_travel += distance
	_max_step = maxf(_max_step, distance)
	_minimum_y = minf(_minimum_y, player.global_position.y)
	_maximum_y = maxf(_maximum_y, player.global_position.y)
	_last = player.global_position

func check(label: String, ok: bool, detail: String = "") -> bool:
	checks += 1
	print("[mbs-public-stage] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)
	return ok

func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func ray(a: Vector3, b: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

func _prepare_production_player_probe() -> bool:
	# _ready creates the actual production body. Disable processing before tree
	# insertion so its controller cannot move during source-plan/physics setup.
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	_player_layer = player.collision_layer
	_probe_mask = player.collision_mask
	_probe_margin = maxf(0.01, player.safe_margin)
	player.collision_layer = 0
	player.collision_mask = 0
	player.hide()
	var collision: CollisionShape3D
	for child: Node in player.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			collision = child as CollisionShape3D
			break
	if not check("production Player capsule exists before physical queries", collision != null): return false
	_probe_shape = collision.shape
	_probe_local_transform = collision.transform
	var capsule := _probe_shape as CapsuleShape3D
	return check("probe reuses exact production capsule transform/mask without weaker margin", is_equal_approx(capsule.radius, 0.36) and is_equal_approx(capsule.height, 1.75) and _probe_local_transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.90, 0.0))) and _probe_mask == Player.COLLIDE_MASK and _probe_margin >= player.safe_margin and not player.can_process())

func _capsule_query(at: Vector3) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.transform = Transform3D(Basis.IDENTITY, at) * _probe_local_transform
	query.margin = _probe_margin
	query.collision_mask = _probe_mask
	return query

func _capsule_has_space(at: Vector3) -> bool:
	return get_world_3d().direct_space_state.intersect_shape(_capsule_query(at), 1).is_empty()

func _capsule_motion_clear(a: Vector3, b: Vector3) -> bool:
	var query := _capsule_query(a)
	if not _capsule_has_space(a): return false
	query.motion = b - a
	var fraction: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	return fraction.size() == 2 and fraction[0] > 0.999

func _transaction_and_transform_tests() -> void:
	var parent := Node3D.new()
	add_child(parent)
	parent.position = Vector3(37.5, 8.0, -61.0)
	parent.rotation.y = 0.73
	var module := PublicL1.new()
	parent.add_child(module)
	var original_local: Transform3D = module.transform
	var rejected: Dictionary = module.build({"corridor_width_m": 100.0})
	check("failed plan returns failure before state/children/transform mutation", not rejected.get("built", true) and module.zones.is_empty() and module.corridors.is_empty() and module.sections.is_empty() and module.furniture.is_empty() and module.get_child_count() == 0 and module.transform.is_equal_approx(original_local))
	for field: String in ["length_m", "width_m", "roof_height_m"]:
		var huge := {"atrium_dimensions": {"T1": {field: 1.0e12}}}
		var oversized: Dictionary = module.build(huge)
		check("finite oversized " + field + " rejected before mutation", not oversized.get("built", true) and module.zones.is_empty() and module.corridors.is_empty() and module.sections.is_empty() and module.furniture.is_empty() and module.get_child_count() == 0 and module.transform.is_equal_approx(original_local))
	var retry: Dictionary = module.build()
	check("valid retry is inside explicit preconstruction member budget", retry.get("built", false) and retry.construction_budget.validated_before_integer_conversion_or_construction and retry.construction_budget.estimated_member_upper_bound <= retry.construction_budget.maximum_members)
	check("failed build can retry with exactly three anchors", retry.get("built", false) and module.zones.size() == 3 and module.corridors.size() == 2 and module.sections.size() == 5)
	check("absolute source placement survives translated rotated unit parent", retry.get("source_placement_preserved", false) and retry.get("metres_per_unit_preserved", false))
	for i in module.zones.size():
		var at: Vector3 = module.to_global(module.zones[i].center)
		var c: Array = Reference.DATA.towers[i].centroid_world_xz
		check("transformed-parent centroid " + String(module.zones[i].tower), Vector2(at.x, at.z).distance_to(Vector2(c[0], c[1])) < 0.002 and absf(at.y) < 0.001)
	var child_count: int = module.get_child_count()
	check("already-built refusal cannot duplicate children", not module.build().get("built", true) and module.get_child_count() == child_count and module.zones.size() == 3)
	parent.queue_free()
	await frames(3)

func _join_boundary_tests() -> void:
	var report: Dictionary = interior.report()
	check("all original lounge furniture retained with full colliders", interior.furniture.size() == 25 and report.furniture_items == 25)
	check("explicit central public aisle reserved", is_equal_approx(report.reserved_public_aisle_width_m, 4.0))
	var furniture_body: StaticBody3D = interior.get_node("MBSPublicL1Collision") as StaticBody3D
	for item: Dictionary in interior.furniture:
		var collision: CollisionShape3D = furniture_body.get_node_or_null(NodePath(String(item.id))) as CollisionShape3D
		var solid_matches: bool = collision != null and not collision.disabled and collision.shape is BoxShape3D
		if solid_matches:
			solid_matches = (collision.shape as BoxShape3D).size.is_equal_approx(item.size) and collision.position.is_equal_approx(item.position + Vector3.UP * float((item.size as Vector3).y) * 0.5) and furniture_body.collision_layer == 1
		check("full matching solid furniture collision retained " + String(item.id), solid_matches)
		check("furniture footprint preserves clear aisle " + String(item.id), float(item.minimum_centerline_to_inner_edge_m) >= 2.5 - 0.0001 and float(item.minimum_wall_clearance_m) >= 0.25 - 0.0001)
		if item.kind == "planter":
			var stem: CollisionShape3D = furniture_body.get_node_or_null(NodePath(String(item.id) + "_TreeStem")) as CollisionShape3D
			check("tall vessel and overhead tree retain solid collision " + String(item.id), is_equal_approx((item.size as Vector3).y, 3.0) and stem != null and not stem.disabled and stem.shape is BoxShape3D and (stem.shape as BoxShape3D).size.y > 1.0 and stem.position.y - (stem.shape as BoxShape3D).size.y * 0.5 >= 3.0 - 0.0001 and is_equal_approx(stem.position.x, (item.position as Vector3).x) and is_equal_approx(stem.position.z, (item.position as Vector3).z) and (stem.shape as BoxShape3D).size.x <= (item.size as Vector3).x and (stem.shape as BoxShape3D).size.z <= (item.size as Vector3).z)
	var probes: Array[Dictionary] = interior.join_probes_local()
	check("both side edges covered at all three profile joins", probes.size() == 6)
	for probe: Dictionary in probes:
		var label := String(probe.join) + (" west" if float(probe.side) > 0.0 else " east")
		var a: Vector3 = interior.to_global(probe.walk_a)
		var b: Vector3 = interior.to_global(probe.walk_b)
		check("clear capsule traverses join edge " + label, _capsule_motion_clear(a, b), str([a, b]))
		for u: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var at := a.lerp(b, u)
			var hit := ray(at + Vector3.UP, at - Vector3.UP)
			check("join edge floor support " + label + " " + str(u), not hit.is_empty() and absf((hit.get("position", Vector3(0,-100,0)) as Vector3).y - at.y) < 0.02)
		for escape: Dictionary in probe.escape_pairs:
			var inside: Vector3 = interior.to_global(escape.inside)
			var outside: Vector3 = interior.to_global(escape.outside)
			check("escape capsule begins clear inside " + label + " " + str(escape.x_offset), _capsule_has_space(inside))
			check("capsule cannot escape beside join " + label + " " + str(escape.x_offset), not _capsule_motion_clear(inside, outside))
			check("no ray slit beside join " + label + " " + str(escape.x_offset), not ray(inside + Vector3.UP * 1.1, outside + Vector3.UP * 1.1).is_empty())
	var door: Dictionary = interior.doorway_world()
	check("whole capsule fits intentional hotel doorway", _capsule_motion_clear(door.outside, door.inside))
	for side: float in [-1.0, 1.0]:
		var offset := interior.global_basis.x * side * 1.60
		check("parked glass leaves preserve full-width capsule approach " + str(side), _capsule_motion_clear((door.outside as Vector3) + offset, (door.inside as Vector3) + offset))
	for link: Dictionary in interior.corridors:
		check("production capsule full public spine clear " + String(link.from), _capsule_motion_clear(interior.to_global(link.a), interior.to_global(link.b)))
		check("production capsule full public spine return clear " + String(link.to), _capsule_motion_clear(interior.to_global(link.b), interior.to_global(link.a)))
		var center: Vector3 = (link.a + link.b) * 0.5
		var at := interior.to_global(center)
		var roof := ray(at + Vector3.UP * 2.0, at + Vector3.UP * 100.0)
		check("intertower volume retains high continuous roof " + String(link.from), not roof.is_empty() and float((roof.get("position", Vector3.ZERO) as Vector3).y - at.y) > 25.0)

func _run() -> void:
	_started = Time.get_ticks_msec()
	Game.simulation_paused = false
	Game.health = Game.MAX_HEALTH
	Game.mode = Game.MODE_FOOT
	Game.death_count = 0
	_light_fixture()
	if not _prepare_production_player_probe():
		finish()
		return
	await _transaction_and_transform_tests()
	interior = PublicL1.new()
	add_child(interior)
	var result: Dictionary = interior.build()
	if not check("public module constructs a hollow L1 stage", bool(result.get("built", false))):
		finish()
		return
	check("actual uncompressed source placement retained", result.source_placement_preserved and result.metres_per_unit_preserved)
	check("continuous taper replaces separate low tunnel volumes", result.continuous_atrium and result.isolated_low_tunnels_built == 0 and not result.roof_heights_metric_verified)
	check("historical approximate widths retained", Reference.ATRIUM_ENGINEERING.approx_width_m == {"T1":40.0,"T2":20.0,"T3":10.0})
	check("public tower order remains T3 T2 T1", result.public_nodes_built == ["hotel_T3_L1", "hotel_T2_L1", "hotel_T1_L1"])
	for i in interior.zones.size():
		var source: Dictionary = Reference.DATA["towers"][i]
		var point: Vector3 = interior.to_global(interior.zones[i]["center"])
		var c: Array = source["centroid_world_xz"]
		check("source centroid exactly positions " + String(source.tower), Vector2(point.x, point.z).distance_to(Vector2(float(c[0]), float(c[1]))) < 0.002)
	check("stage cannot certify whole interior", not result.full_requested_interior_verified and not result.entire_floor_space_inventory_complete and result.room_inventory_created == 0)
	check("metric entrances floor elevations and fit-out remain unverified", not result.entrance_metric_verified and not result.floor_elevations_verified and not result.architectural_identity_and_fitout_verified)
	check("all missing programs stay explicit", result.unbuilt_areas.has("all_guestrooms_and_suites") and result.unbuilt_areas.has("hotel_service_and_back_of_house") and result.unbuilt_areas.has("shoppes_B2") and not result.retail_connection_built)
	check("collision is continuous hollow shell/floors rather than tower mass", result.collision_shapes > 15 and result.triangle_count > 500)
	await frames(4)
	_join_boundary_tests()
	for zone: Dictionary in interior.zones:
		var at: Vector3 = interior.to_global(zone.center)
		var floor := ray(at + Vector3.UP * 2, at - Vector3.UP)
		check("supported visible floor beneath " + String(zone.tower), not floor.is_empty() and absf((floor.get("position", Vector3(0,-100,0)) as Vector3).y - at.y) < 0.02)
		var ceiling := ray(at + Vector3.UP * 2, at + Vector3.UP * (float(zone.wall_height_m) + 7.0))
		check("continuous sloping roof has actual ceiling collision " + String(zone.tower), not ceiling.is_empty())
	var door: Dictionary = interior.doorway_world()
	var center: Vector3 = door.center
	var normal: Vector3 = door.normal
	var along: Vector3 = interior.global_basis.x
	check("door opening is physically clear", ray(center + normal * 2 + Vector3.UP * 1.1, center - normal * 2 + Vector3.UP * 1.1).is_empty())
	check("adjacent facade remains solid", not ray(center + along * 3.0 + normal * 2 + Vector3.UP * 1.1, center + along * 3.0 - normal * 2 + Vector3.UP * 1.1).is_empty())
	var unsupported := PublicL1.new()
	add_child(unsupported)
	check("oversize opening rejects invalid shell", not unsupported.build({"corridor_width_m": 100.0}).get("built", true))
	unsupported.queue_free()
	var scaled := Node3D.new()
	add_child(scaled)
	scaled.scale = Vector3(0.45, 1, 0.65)
	var compressed := PublicL1.new()
	scaled.add_child(compressed)
	check("compressed parent is refused", not compressed.build().get("built", true))
	scaled.queue_free()
	await frames(2)
	# The present Player still enforces legacy district bounds. Moving the
	# COMPLETE stage (not the actor during travel) isolates controller/collision.
	print("[mbs-public-stage] FIXTURE translating complete source stage to origin for existing Player bounds; no global-site traversal claim.")
	interior.global_position = Vector3.ZERO
	await frames(3)
	var moved_report: Dictionary = interior.report()
	check("fixture translation is reported honestly", not moved_report.source_placement_preserved and moved_report.metres_per_unit_preserved)
	player.collision_layer = _player_layer
	player.collision_mask = _probe_mask
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.show()
	var route: Array[Vector3] = interior.walking_route_world(true)
	Game.last_safe_position = route[0] + Vector3.UP * 0.1
	Game.last_safe_rotation = 0.0
	player.respawn_at(Game.last_safe_position, 0.0)
	await frames(20)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_last = player.global_position
	_track = true
	await still("01_exterior_door_approach")
	for i in route.size():
		if not await walk_to(route[i], 1.15):
			check("continuous doorway atrium circulation", false, "waypoint%d at%s target%s" % [i, player.global_position, route[i]])
			finish()
			return
		if i == 2: await still("02_tower1_atrium")
		if i == (route.size() - 1) / 2: await still("03_north_atrium")
	check("continuous outside inside three-atria return route", true, "travel=%.2fm" % _travel)
	check("walking never teleports or jumps floor", _max_step < 0.5 and _minimum_y > -0.2 and _maximum_y < 0.2 and Game.death_count == 0, "step=%.4fm min_y=%.4f max_y=%.4f" % [_max_step, _minimum_y, _maximum_y])
	check("player remains live supported and independently controlled", player.alive and player.current_vehicle == null and player.is_on_floor() and Game.mode == Game.MODE_FOOT and Game.health > 0.0)
	var final_report: Dictionary = interior.report()
	check("a passing walk does not certify as-built whole building", not final_report.full_requested_interior_verified and not final_report.entire_floor_space_inventory_complete)
	metrics = {"travel_m": _travel, "max_step_m": _max_step, "minimum_fixture_y": _minimum_y, "maximum_fixture_y": _maximum_y, "report": final_report}
	await still("04_returned_outside")
	finish()

func walk_to(target: Vector3, radius: float) -> bool:
	var initial := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	var deadline := Time.get_ticks_msec() + int((initial / 5.5 + 12.0) * 1000)
	while Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() > radius and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var d := target - player.global_position
		player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), 0.20)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() > radius:
		_log_blocking_contacts(target)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await frames(2)
	return Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() <= radius + 0.2

func _log_blocking_contacts(target: Vector3) -> void:
	var contacts: Array[Dictionary] = []
	for index in player.get_slide_collision_count():
		var contact := player.get_slide_collision(index)
		var body: CollisionObject3D = contact.get_collider() as CollisionObject3D
		var owner: Node3D
		if body != null:
			owner = body.shape_owner_get_owner(body.shape_find_owner(contact.get_collider_shape_index())) as Node3D
		contacts.append({"body": String(body.name) if body != null else "UNKNOWN", "shape": String(owner.name) if owner != null else "UNKNOWN", "furnishing_id": owner.get_meta("furnishing_id", "") if owner != null else "", "normal": contact.get_normal(), "position": contact.get_position()})
	print("[mbs-public-stage] BLOCKING_CONTACT_DIAGNOSTIC ", JSON.stringify({"player_world": player.global_position, "player_module_local": interior.to_local(player.global_position), "target_world": target, "target_module_local": interior.to_local(target), "contacts": contacts}))

func still(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var folder := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mbs-interior-stills-dir="): folder = arg.trim_prefix("--mbs-interior-stills-dir=")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var file := folder.path_join(label + ".png")
	check("actual staged-player-camera image " + label, get_viewport().get_texture().get_image().save_png(file) == OK, file)

func _light_fixture() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.61, 0.67)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.86, 0.82)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -25, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

func finish() -> void:
	if _finished: return
	_finished = true
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]: Input.action_release(action)
	print("[mbs-public-stage] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "metrics": metrics, "elapsed_s": float(Time.get_ticks_msec() - _started) / 1000.0, "fixture_translation": true, "full_interior_verified": false, "whole_city_verified": false, "rendered_fidelity_accepted": false}))
	Sfx.shutdown_audio()
	get_tree().quit(0 if failures.is_empty() else 1)
