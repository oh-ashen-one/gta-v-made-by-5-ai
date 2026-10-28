extends Node3D
## Actual production-world roof/support checks plus disclosed actor fixtures.
## Every aircraft relocation is an initial fixture while unoccupied. Descent,
## touchdown, E exit and subsequent walking use production physics/input.
## This is NOT a continuous flown route, every-background-roof certificate,
## human-input acceptance, geographic accuracy or performance acceptance.
const MBS = preload("res://src/world/downtown/landmarks/mbs.gd")
const Fullerton = preload("res://src/world/downtown/landmarks/fullerton.gd")
const LIMIT_SECONDS := 210.0
var main: Node
var world: WorldBuilder
var player: Player
var heli: Helicopter
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var metrics: Dictionary = {}
var captures: Array[Dictionary] = []
var output := ""
var qa_session := ""
var _started := 0
var _finished := false
var _watch := false
var _tracking_walk := false
var _last_foot := Vector3.ZERO
var _max_walk_step := 0.0
var _min_walk_y := INF
var _max_walk_y := -INF
var _initial_deaths := 0
var _actor_cases_done := 0
var _fixture_assignments := 0
var _player_collider: CollisionShape3D
var _heli_collider: CollisionShape3D
var _heli_bottom_y := 0.0
var _fixture_search := {"eligible_roofs": 0, "points": 0, "helicopter_blocked": 0, "foot_support_failed": 0, "capsule_blocked": 0, "sweep_blocked": 0, "sample_rejections": []}

func _ready() -> void:
	if not _paths():
		get_tree().quit(2)
		return
	_mouse_safe()
	_run.call_deferred()

func _canonical(path: String) -> String:
	return "/private/tmp/" + path.trim_prefix("/tmp/") if path.begins_with("/tmp/") else path

func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/", false):
		var dir := DirAccess.open(parent)
		if dir != null and dir.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _paths() -> bool:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size():
		push_error("Roof support review requires an explicit isolated --qa-session")
		return false
	qa_session = _canonical(args[at + 1])
	for arg in args:
		if arg.begins_with("--roof-support-output="): output = _canonical(arg.trim_prefix("--roof-support-output="))
	if output.is_empty(): output = qa_session.path_join("roof-support-review")
	if not _owned(qa_session) or not _owned(output) or output == qa_session or FileAccess.file_exists(output.path_join("report.json")):
		push_error("Roof review refuses unsafe paths or existing evidence")
		return false
	return DirAccess.make_dir_recursive_absolute(output) == OK

func _mouse_safe() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Runtime introspection avoids assuming a platform-specific window flag.
	if DisplayServer.get_name() != "headless":
		for property: Dictionary in get_window().get_property_list():
			if property.name == "unfocusable": get_window().set("unfocusable", true)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	if AudioServer.bus_count > 0: AudioServer.set_bus_mute(0, true)

func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _watch and not _finished and Time.get_ticks_msec() - _started > int(LIMIT_SECONDS * 1000):
		check("roof review completes inside its monotonic limit", false)
		_finish()

func _physics_process(_delta: float) -> void:
	if _tracking_walk and is_instance_valid(player):
		_max_walk_step = maxf(_max_walk_step, player.global_position.distance_to(_last_foot))
		_min_walk_y = minf(_min_walk_y, player.global_position.y)
		_max_walk_y = maxf(_max_walk_y, player.global_position.y)
		_last_foot = player.global_position

func check(label: String, passed: bool, detail: String = "") -> bool:
	if _finished: return passed
	checks += 1
	results.append({"name": label, "passed": passed, "detail": detail})
	print("[roof-support] %s %s %s" % ["PASS" if passed else "FAIL", label, detail])
	if not passed: failures.append(label)
	return passed

func _frames(count: int) -> void:
	for i in count:
		if _finished: return
		await get_tree().physics_frame

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "interact"]: Input.action_release(action)

func _press_e() -> void:
	Input.action_press("interact")
	await get_tree().process_frame
	await _frames(2)
	Input.action_release("interact")
	await get_tree().process_frame
	await get_tree().process_frame
	await _frames(3)

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(query)

func _shape_kind(hit: Dictionary) -> String:
	var body := hit.get("collider") as CollisionObject3D
	if body == null: return ""
	var owner := body.shape_find_owner(int(hit.get("shape", -1)))
	var node := body.shape_owner_get_owner(owner) as Node
	return String(node.get_meta("roof_support_kind", "")) if node != null else ""

func _hit_detail(hit: Dictionary) -> Dictionary:
	if hit.is_empty(): return {"empty": true}
	var body := hit.get("collider") as CollisionObject3D
	var node: Node = null
	if body != null:
		var owner := body.shape_find_owner(int(hit.get("shape", -1)))
		node = body.shape_owner_get_owner(owner) as Node
	return {"empty": false, "position": hit.get("position", Vector3.ZERO), "normal": hit.get("normal", Vector3.ZERO), "kind": _shape_kind(hit), "body": String(body.get_path()) if body != null else "", "shape": String(node.name) if node != null else "", "render_instance": node.get_meta("render_instance_index", -1) if node != null else -1}

func _sample_rejection(reason: String, point: Vector3, hits: Array = []) -> void:
	var examples: Array = _fixture_search.sample_rejections
	if examples.size() >= 16: return
	var names: Array[Dictionary] = []
	for hit: Dictionary in hits: names.append(_hit_detail(hit))
	examples.append({"reason": reason, "point": point, "hits": names})

func _xf_error(a: Transform3D, b: Transform3D) -> float:
	var error := 0.0
	for x: float in [-0.5, 0.5]:
		for y: float in [-0.5, 0.5]:
			for z: float in [-0.5, 0.5]:
				var point := Vector3(x, y, z)
				error = maxf(error, (a * point).distance_to(b * point))
	return error

func _roof_receipts(mesh: MultiMeshInstance3D) -> Array:
	return mesh.get_meta("roof_instance_transforms", [])

func _roof_instance_xform(mesh: MultiMeshInstance3D, index: int) -> Transform3D:
	var receipts := _roof_receipts(mesh)
	# The headless dummy rendering backend does not retain useful GPU buffer
	# readback. This is the exact CPU transform submitted to the real MMI,
	# checked separately against the actual native collision shape below.
	var local: Transform3D = receipts[index] if DisplayServer.get_name() == "headless" else mesh.multimesh.get_instance_transform(index)
	return mesh.global_transform * local

func _top_overlap_detail(top: Vector3) -> Array[Dictionary]:
	# A centre may lie inside an existing housing/tank rather than in exposed
	# air. Record the actual native shape owners instead of silently skipping
	# its failed membrane ray or inventing an acceptable lower surface.
	var sphere := SphereShape3D.new()
	sphere.radius = 0.005
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, top + Vector3.UP * 0.015)
	query.margin = 0.0
	query.collision_mask = 1
	var detail: Array[Dictionary] = []
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 12): detail.append(_hit_detail(hit))
	return detail

func _matching_box(mesh: MultiMeshInstance3D, index: int, collision: StaticBody3D, part: String) -> Dictionary:
	var receipts := _roof_receipts(mesh)
	if index >= receipts.size(): return {"matched": false, "reason": "missing authored render receipt"}
	var source: Transform3D = receipts[index]
	var expected := mesh.global_transform * source
	for child in collision.get_children():
		if not child is CollisionShape3D or String(child.get_meta("roof_support_kind", "")) != part or int(child.get_meta("render_instance_index", -1)) != index: continue
		var node := child as CollisionShape3D
		if not node.shape is BoxShape3D: return {"matched": false, "reason": "structural box changed shape type"}
		var size := (node.shape as BoxShape3D).size
		var actual := node.global_transform * Transform3D(Basis.from_scale(size), Vector3.ZERO)
		var error := _xf_error(expected, actual)
		return {"matched": not node.disabled and collision.collision_layer == 1 and error < 0.0001, "shape": String(node.name), "size": size, "collider_transform": node.global_transform, "authored_transform": source, "max_corner_error_m": error}
	return {"matched": false, "reason": "no indexed structural box"}

func _surface(label: String, point: Vector3, expected_y: float, kind: String = "", span: float = 0.6) -> bool:
	var hit := _ray(Vector3(point.x, expected_y + span, point.z), Vector3(point.x, expected_y - span, point.z))
	var y := float((hit.get("position", Vector3(0, -1000, 0)) as Vector3).y)
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var actual_kind := _shape_kind(hit)
	return check(label, not hit.is_empty() and absf(y - expected_y) < 0.035 and normal.y > 0.65 and (kind.is_empty() or actual_kind == kind), "expected_y=%.4f actual_y=%.4f normal=%s shape=%s" % [expected_y, y, normal, actual_kind])

func _run() -> void:
	_release()
	main = load("res://main.tscn").instantiate()
	add_child(main) # synchronous production construction, never a QA replacement roof
	world = main.get_node_or_null("World") as WorldBuilder
	player = main.get_node_or_null("Player") as Player
	heli = main.get_node_or_null("Helicopter") as Helicopter
	_started = Time.get_ticks_msec()
	_watch = true
	if not check("production world player and helicopter exist", world != null and player != null and heli != null):
		_finish()
		return
	main._new_game()
	_mouse_safe()
	_player_collider = _body_collider(player)
	_heli_collider = _body_collider(heli)
	if not check("fixture probes use actual production collision resources", _player_collider != null and _player_collider.shape is CapsuleShape3D and _heli_collider != null and _heli_collider.shape is BoxShape3D):
		_finish()
		return
	_heli_bottom_y = _heli_collider.position.y - (_heli_collider.shape as BoxShape3D).size.y * 0.5
	metrics["production_collision"] = {"player_capsule_radius": (_player_collider.shape as CapsuleShape3D).radius, "player_capsule_height": (_player_collider.shape as CapsuleShape3D).height, "player_local_transform": _player_collider.transform, "helicopter_box_size": (_heli_collider.shape as BoxShape3D).size, "helicopter_bottom_y": _heli_bottom_y}
	_initial_deaths = Game.death_count
	await _frames(10)
	_roof_rays()
	var membrane_case := _roofkit_checks()
	var cases := _actor_cases(membrane_case)
	for entry: Dictionary in cases:
		if _finished: return
		await _land_exit_walk(entry)
	check("every representative actor case was exercised", _actor_cases_done == cases.size(), "%d/%d" % [_actor_cases_done, cases.size()])
	check("roof fixtures cause no player death", Game.death_count == _initial_deaths and Game.health > 0.0)
	_finish()

func _body_collider(actor: Node3D) -> CollisionShape3D:
	for node in actor.get_children():
		if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
			return node as CollisionShape3D
	return null

func _roof_rays() -> void:
	var m := DowntownPlan.anchor("marina_bay_sands")
	for dx: float in MBS.TOWER_DX:
		_surface("pavilion roof supports its visible top %.0f" % dx, Vector3(m.x + dx, 204.4, m.z), 204.4, "SkyParkPavilionRoof_%.0f" % dx)
	_surface("clear visible SkyPark bow is supported", Vector3(m.x - 172.0, 200, m.z + 2), 200, "SkyParkStructuralHull")
	_surface("clear landward SkyPark edge is supported", Vector3(m.x - 60.0, 200, m.z - 15), 200, "SkyParkStructuralHull")
	_surface("visible stern surface is supported", Vector3(m.x + 123.0, 200, m.z + 2), 200, "SkyParkStructuralHull")
	var outside := Vector3(m.x - 164.0, 200.0, m.z + 16.0)
	check("no phantom deck support outside the tapered hull", _ray(outside + Vector3.UP, outside - Vector3.UP).is_empty())
	var tip := Vector3(m.x - 185.2, 200.0, m.z + 2.0)
	check("no phantom support beyond the visible bow tip", _ray(tip + Vector3.UP, tip - Vector3.UP).is_empty())
	# The pool's underlying stone is structural; liquid itself is not solid.
	var water := Vector3(m.x - 100.0, 200.29, m.z + 15.0)
	check("pool liquid is not turned into solid roof", _ray(water + Vector3.UP * 0.01, water - Vector3.UP * 0.03).is_empty())
	var crest := 17.4 + 7.5 * sin(4.0 * PI / 9.0)
	_surface("Shoppes visible curved crest has matching support", Vector3(m.x - 165.0, crest, m.z + 32), crest, "ShoppesStructuralWaveRoof")
	var aviation: Vector3 = world.locations["helipad_primary"] - Vector3(30.0, 0.3, 24.0)
	_surface("hangar visible ridge has matching prism support", aviation + Vector3(-30, 15, -20), aviation.y + 15.0, "HangarPrismRoof")
	var one := Vector3(-516.0, Fullerton.TOP + 8.25, -396.0)
	_surface("One Fullerton eave supports the visible roof", one, one.y, "OneFullertonRoof_-507")
	var full := DowntownPlan.anchor("fullerton_hotel")
	_surface("Fullerton upper roof has actual upper-mass support", Vector3(full.x + 20, Fullerton.TOP + 33, full.z + 10), Fullerton.TOP + 33, "FullertonMainUpperMass")
	var terrace := Vector3(full.x + 38.7, Fullerton.TOP + 27, full.z + 30)
	_surface("Fullerton lower terrace has lower-mass support", terrace, terrace.y, "FullertonMainLowerMass")
	check("air above Fullerton lower terrace is not an upper box", _ray(Vector3(terrace.x, Fullerton.TOP + 34, terrace.z), Vector3(terrace.x, Fullerton.TOP + 28, terrace.z)).is_empty())
	metrics["known_positive_and_negative_roof_probes"] = 15

func _roofkit_checks() -> Dictionary:
	var deck := world.find_child("RoofKit_deck", true, false) as MultiMeshInstance3D
	var collision := world.find_child("RoofKitStructuralCollision", true, false) as StaticBody3D
	if not check("production membrane mesh and structural body exist", deck != null and collision != null and deck.multimesh != null): return {}
	var count := deck.multimesh.instance_count
	var receipts := _roof_receipts(deck)
	if not check("membrane CPU render receipts cover every submitted instance", receipts.size() == count, "%d/%d" % [receipts.size(), count]): return {}
	var deck_shapes := 0
	var excluded_shapes := 0
	for node in collision.get_children():
		var kind := String(node.get_meta("roof_support_kind", ""))
		if kind == "deck": deck_shapes += 1
		if kind in ["solar", "shrub", "mast", "vent", "fan", "door"]: excluded_shapes += 1
	check("every membrane has one matching structural shape", count > 0 and deck_shapes == count, "%d visual/%d physical" % [count, deck_shapes])
	check("small nonstructural dressing was not solidified", excluded_shapes == 0)
	var supported := 0
	var unsupported: Array[int] = []
	var candidate: Dictionary = {}
	var deck_details: Array[Dictionary] = []
	var shapes_matched := 0
	var gpu_buffer_max_error := 0.0
	for i in count:
		var xf := _roof_instance_xform(deck, i)
		var matching := _matching_box(deck, i, collision, "deck")
		if matching.matched: shapes_matched += 1
		var gpu_local := deck.multimesh.get_instance_transform(i)
		gpu_buffer_max_error = maxf(gpu_buffer_max_error, _xf_error(receipts[i], gpu_local))
		var top := xf * Vector3(0, 0.5, 0)
		var hit := _ray(top + Vector3.UP * 0.015, top - Vector3.UP * 0.12)
		var ok := not hit.is_empty() and absf((hit.position as Vector3).y - top.y) < 0.025 and _shape_kind(hit) == "deck"
		if ok: supported += 1
		else: unsupported.append(i)
		deck_details.append({"index": i, "expected_top": top, "native_ray": _hit_detail(hit), "supported": ok, "matching_shape": matching, "renderer_readback": gpu_local, "native_top_overlaps_if_failed": _top_overlap_detail(top) if not ok else []})
		if candidate.is_empty() and xf.basis.get_scale().x > 24.0 and xf.basis.get_scale().z > 20.0:
			_fixture_search.eligible_roofs += 1
			candidate = _clear_membrane_fixture(deck, xf, i)
	check("every membrane structural box matches its submitted render transform", shapes_matched == count, "%d/%d" % [shapes_matched, count])
	if DisplayServer.get_name() != "headless":
		check("rendered membrane buffer matches the CPU submission receipt", gpu_buffer_max_error < 0.0001, "max_corner_error_m=%.6f" % gpu_buffer_max_error)
	check("all actual membrane centres support their rendered slab height", supported == count, "supported=%d/%d failures=%s" % [supported, count, unsupported])
	check("an ordinary production membrane has a clear fixture landing and walk", not candidate.is_empty())
	var housing := world.find_child("RoofKit_housing_roof", true, false) as MultiMeshInstance3D
	var housing_ok := 0
	var housing_count := 0
	var housing_matches := 0
	var housing_details: Array[Dictionary] = []
	var housing_gpu_error := 0.0
	if housing != null and housing.multimesh != null:
		housing_count = housing.multimesh.instance_count
		var housing_receipts := _roof_receipts(housing)
		if check("housing CPU render receipts cover every submitted instance", housing_receipts.size() == housing_count, "%d/%d" % [housing_receipts.size(), housing_count]):
			for i in housing_count:
				var xf := _roof_instance_xform(housing, i)
				var top := xf * Vector3(0, 0.5, 0)
				var matching := _matching_box(housing, i, collision, "housing_roof")
				if matching.matched: housing_matches += 1
				var gpu_local := housing.multimesh.get_instance_transform(i)
				housing_gpu_error = maxf(housing_gpu_error, _xf_error(housing_receipts[i], gpu_local))
				var hit := _ray(top + Vector3.UP * 0.02, top - Vector3.UP * 0.12)
				var ok := not hit.is_empty() and absf((hit.position as Vector3).y - top.y) < 0.03 and _shape_kind(hit) == "housing_roof"
				if ok: housing_ok += 1
				housing_details.append({"index": i, "expected_top": top, "native_ray": _hit_detail(hit), "supported": ok, "matching_shape": matching, "renderer_readback": gpu_local, "native_top_overlaps_if_failed": _top_overlap_detail(top) if not ok else []})
	check("every large housing structural box matches its submitted render transform", housing_count > 0 and housing_matches == housing_count, "%d/%d" % [housing_matches, housing_count])
	if DisplayServer.get_name() != "headless":
		check("rendered housing buffer matches the CPU submission receipt", housing_gpu_error < 0.0001, "max_corner_error_m=%.6f" % housing_gpu_error)
	check("actual large housing roofs have matching support", housing_count > 0 and housing_ok == housing_count, "%d/%d" % [housing_ok, housing_count])
	metrics["roofkit"] = {"visual_membranes": count, "physical_membranes": deck_shapes, "supported_centres": supported, "housing_roofs": housing_count, "supported_housing_roofs": housing_ok, "fixture_selection": candidate, "fixture_search": _fixture_search, "transform_source": "CPU values submitted to production MMI; rendered runs also require GPU-buffer agreement" if DisplayServer.get_name() == "headless" else "actual renderer buffer plus independent CPU submission agreement", "headless_gpu_readback_acceptance": false, "deck_gpu_readback_max_corner_error_m": gpu_buffer_max_error, "housing_gpu_readback_max_corner_error_m": housing_gpu_error, "deck_details": deck_details, "housing_details": housing_details}
	return candidate

func _clear_membrane_fixture(deck: MultiMeshInstance3D, xf: Transform3D, index: int) -> Dictionary:
	for x: float in [-0.25, 0.0, 0.25]:
		for z: float in [-0.25, 0.0, 0.25]:
			_fixture_search.points += 1
			var top := xf * Vector3(x, 0.5, z)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _heli_collider.shape
			query.transform = Transform3D(Basis.IDENTITY, top + Vector3.UP * (0.05 - _heli_bottom_y)) * _heli_collider.transform
			query.margin = maxf(heli.safe_margin, 0.01)
			query.collision_mask = 1 | 4 | 8
			query.exclude = [heli.get_rid(), player.get_rid()]
			var helicopter_hits := get_world_3d().direct_space_state.intersect_shape(query, 4)
			if not helicopter_hits.is_empty():
				_fixture_search.helicopter_blocked += 1
				_sample_rejection("helicopter body obstruction", top, helicopter_hits)
				continue
			var clear := true
			for u: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var foot := top + Vector3(2.8, 0, -3.4 * u)
				var hit := _ray(foot + Vector3.UP * 0.02, foot - Vector3.UP * 0.12)
				if hit.is_empty() or absf((hit.position as Vector3).y - top.y) > 0.025 or _shape_kind(hit) != "deck":
					clear = false
					_fixture_search.foot_support_failed += 1
					_sample_rejection("walk path lacks matching membrane support", foot, [hit] if not hit.is_empty() else [])
				query.shape = _player_collider.shape
				query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.08) * _player_collider.transform
				query.margin = maxf(player.safe_margin, 0.01)
				var capsule_hits := get_world_3d().direct_space_state.intersect_shape(query, 4)
				if not capsule_hits.is_empty():
					clear = false
					_fixture_search.capsule_blocked += 1
					_sample_rejection("walk capsule obstruction", foot, capsule_hits)
			query.transform = Transform3D(Basis.IDENTITY, top + Vector3(2.8, 0.08, 0)) * _player_collider.transform
			query.motion = Vector3(0, 0, -3.4)
			var fraction: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
			if fraction.size() != 2 or fraction[0] < 0.999:
				clear = false
				_fixture_search.sweep_blocked += 1
				_sample_rejection("walk capsule sweep obstruction", top)
			if clear:
				return {"name": "ordinary_membrane_%d" % index, "point": top, "yaw": 0.0, "render_node": String(deck.name), "render_instance": index, "selection": "production body/capsule clearance and full walk-path sweep; other occupied spots are not claimed clear"}
	return {}

func _actor_cases(membrane: Dictionary) -> Array[Dictionary]:
	var m := DowntownPlan.anchor("marina_bay_sands")
	var full := DowntownPlan.anchor("fullerton_hotel")
	var aviation: Vector3 = world.locations["helipad_primary"] - Vector3(30.0, 0.3, 24.0)
	var cases: Array[Dictionary] = [
		{"name": "mbs_pavilion_north", "point": Vector3(m.x - 98, 204.4, m.z), "yaw": 0.0},
		{"name": "mbs_visible_bow", "point": Vector3(m.x - 172, 200, m.z + 2), "yaw": 0.0},
		{"name": "mbs_landward_edge", "point": Vector3(m.x - 60, 200, m.z - 15), "yaw": PI * 0.5},
		{"name": "shoppes_wave_crest", "point": Vector3(m.x - 165, 17.4 + 7.5 * sin(4.0 * PI / 9.0), m.z + 32), "yaw": 0.0, "walk_roof_drop_m": 1.5},
		{"name": "hangar_prism_ridge", "point": aviation + Vector3(-30, 15, -20), "yaw": 0.0, "walk_roof_drop_m": 1.5},
		{"name": "one_fullerton_eave", "point": Vector3(-516, Fullerton.TOP + 8.25, -396), "yaw": 0.0},
		{"name": "fullerton_upper_roof", "point": Vector3(full.x + 20, Fullerton.TOP + 33, full.z + 10), "yaw": 0.0},
	]
	if not membrane.is_empty(): cases.append(membrane)
	return cases

func _land_exit_walk(entry: Dictionary) -> void:
	_release()
	_tracking_walk = false
	var point: Vector3 = entry.point
	var yaw: float = entry.yaw
	# Per-case INITIAL placement is explicit. Neither actor is relocated during
	# the subsequent native descent, exit or walking phase.
	player.respawn_at(point + Vector3(0, 0.15, 4), yaw)
	heli.global_position = point + Vector3.UP * 5.0
	heli.rotation = Vector3(0, yaw, 0)
	heli.velocity = Vector3.ZERO
	_fixture_assignments += 2
	heli.interact(player) # fixture boarding; normal production ownership path
	await _frames(3)
	check("initial roof fixture is airborne " + String(entry.name), player.current_vehicle == heli and not heli.is_on_floor())
	var landing_deadline := Time.get_ticks_msec() + 8000
	while not heli.is_landed() and Time.get_ticks_msec() < landing_deadline:
		Input.action_press("sprint")
		await _frames(1)
	Input.action_release("sprint")
	await _frames(5)
	# Read the production collision box bottom. Being landed on a
	# lower body/ground is not success for the selected visible roof surface.
	var landed := heli.is_on_floor() and heli.is_landed() and not heli.disabled and heli.health > 99.9 and absf(heli.global_position.y + _heli_bottom_y - point.y) < 0.12
	check("native descent lands on actual roof " + String(entry.name), landed, "position=%s target=%s speed=%s health=%.2f" % [heli.global_position, point, heli.velocity, heli.health])
	if not landed: return
	check("touchdown remains gentle " + String(entry.name), heli.last_touchdown_speed < 1.6, str(heli.last_touchdown_speed))
	var exit_point := heli.landing_exit_position()
	check("actual roof has a supported capsule exit " + String(entry.name), exit_point != Vector3.ZERO, str(exit_point))
	await _shot("landed_" + String(entry.name))
	await _press_e()
	var on_foot := player.current_vehicle == null and Game.mode == Game.MODE_FOOT and player.visible and player.collision_layer == 2 and player.collision_mask == Player.COLLIDE_MASK
	check("native E returns foot ownership " + String(entry.name), on_foot)
	if not on_foot: return
	await _frames(8)
	check("actual Player remains supported after exit " + String(entry.name), player.is_on_floor() and player.alive and _feet_supported())
	var start := player.global_position
	_max_walk_step = 0.0
	_min_walk_y = start.y
	_max_walk_y = start.y
	_last_foot = start
	_tracking_walk = true
	for i in 60:
		Input.action_press("move_forward")
		await _frames(1)
	Input.action_release("move_forward")
	_tracking_walk = false
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	var stayed_on_roof := _min_walk_y > point.y - float(entry.get("walk_roof_drop_m", 0.3)) and _max_walk_y < point.y + 0.3
	check("on-foot movement stays usable on roof " + String(entry.name), moved > 2.0 and player.is_on_floor() and player.alive and _max_walk_step < 0.5 and _feet_supported() and stayed_on_roof, "walk=%.3fm max_step=%.4fm height=[%.3f,%.3f] position=%s contacts=%s" % [moved, _max_walk_step, _min_walk_y, _max_walk_y, player.global_position, _contacts()])
	metrics[String(entry.name)] = {"fixture_point": point, "fixture_yaw": yaw, "landing_position": heli.global_position, "exit_point": exit_point, "walk_m": moved, "max_foot_step_m": _max_walk_step, "walk_min_y": _min_walk_y, "walk_max_y": _max_walk_y, "player_position": player.global_position, "native_descent_and_exit": true}
	_actor_cases_done += 1
	await _shot("walking_" + String(entry.name))

func _feet_supported() -> bool:
	var hit := _ray(player.global_position + Vector3.UP * 0.7, player.global_position - Vector3.UP * 0.4)
	return not hit.is_empty() and (hit.get("normal", Vector3.ZERO) as Vector3).y > 0.65 and absf(player.global_position.y - float((hit.position as Vector3).y)) < 0.25

func _contacts() -> Array[String]:
	var names: Array[String] = []
	for i in player.get_slide_collision_count():
		var collision := player.get_slide_collision(i)
		var body := collision.get_collider() as Node
		if body != null: names.append(str(body.get_path()))
	return names

func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var file := output.path_join(label + ".png")
	var image := get_viewport().get_texture().get_image()
	var ok := image != null and not image.is_empty() and image.save_png(file) == OK
	check("actual physics-fixture frame " + label, ok)
	captures.append({"label": label, "file": file, "saved": ok, "pixels": [image.get_width(), image.get_height()] if image != null else [], "scope": "actual production world/actors, explicitly fixture-assisted roof check"})

func _finish() -> void:
	if _finished: return
	_finished = true
	_release()
	_tracking_walk = false
	Sfx.shutdown_audio()
	var report := {"checks": checks, "failures": failures, "results": results, "metrics": metrics, "captures": captures, "elapsed_s": float(Time.get_ticks_msec() - _started) / 1000.0, "rendered": DisplayServer.get_name() != "headless", "scope": "Actual structural roofs and production actors in the legacy compressed district; explicit per-case fixture positions. Not a continuous flight route, all-background-roof, geographic, human-input, appearance or performance acceptance.", "fixture_actor_position_assignments": _fixture_assignments, "in_flight_position_assignments": false, "native_human_input": false, "all_visible_roofs_verified": false, "whole_city_verified": false}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		failures.append("write private roof review report")
	print("[roof-support] RESULT ", JSON.stringify({"checks": checks, "failures": failures, "report": output.path_join("report.json"), "rendered": report.rendered, "scope": report.scope}))
	get_tree().quit(0 if failures.is_empty() else 1)
