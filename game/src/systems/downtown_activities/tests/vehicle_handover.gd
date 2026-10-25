extends Node3D
## Explicit local vehicle fixture, NOT continuous driving or a city traversal.
## Uses production main/courier/Car, real E entry/exit/pickup/delivery and Game
## save/load. Only initial foot placement and occupied-car destination placement
## are fixture moves; every such move is logged. No mode/occupancy flags are forged.
const Courier = preload("res://src/systems/downtown_activities/courier.gd")
var main: Node
var player: Player
var activity: Node
var car: Car
var _qa := ""
var _checks := 0
var _failures: Array[String] = []
var _started := 0
var _deaths := 0
var _local_car_motion_m := 0.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--qa-session")
	if index < 0 or index + 1 >= args.size() or not String(args[index + 1]).is_absolute_path():
		push_error("Vehicle courier fixture requires --qa-session <isolated absolute directory>")
		get_tree().quit(2)
		return
	_qa = args[index + 1]
	_run.call_deferred()

func _check(label: String, ok: bool, detail := "") -> bool:
	_checks += 1
	print("[courier-car] ", "PASS " if ok else "FAIL ", label, " ", detail)
	if not ok: _failures.append(label + " " + detail)
	return ok

func _run() -> void:
	_started = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	activity = main.downtown_activity
	if not _check("production courier bootstrap", activity != null and activity.is_in_group("downtown_activity")):
		_finish(); return
	_deaths = Game.death_count
	var dispatch: Vector3 = activity.stations.heritage.global_position
	var initial := dispatch + Vector3(0, 0.2, 2.5)
	print("[courier-car] FIXTURE initial foot placement ", initial)
	player.respawn_at(initial, 0.0)
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	await get_tree().create_timer(0.6).timeout
	Game.mark_safe_position(player.global_position, player.yaw)
	await _tap_e()
	if not _check("real E collects courier parcel", activity.stage == Courier.Stage.OUTBOUND):
		_finish(); return
	car = Car.new()
	car.name = "CourierFixtureCar"
	main.add_child(car)
	car.global_position = dispatch + Vector3(8, 0.5, -3)
	print("[courier-car] FIXTURE production Car placement ", car.global_position)
	await get_tree().create_timer(0.6).timeout
	if not await _board_car():
		_finish(); return
	var motion_start := car.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.45).timeout
	Input.action_release("move_forward")
	Input.action_press("jump") # Native car handbrake, not a foot jump.
	await get_tree().create_timer(0.8).timeout
	Input.action_release("jump")
	_local_car_motion_m = car.global_position.distance_to(motion_start)
	_check("native throttle carries the parcel locally", _local_car_motion_m > 0.5 and activity.stage == Courier.Stage.OUTBOUND and player.current_vehicle == car, "distance_m=%.3f" % _local_car_motion_m)
	var outbound: Dictionary = activity.serialize_state()
	var occupied_file := _qa.path_join("courier-occupied-car.json")
	if not _check("save real occupied-car courier", Game.save_game(occupied_file)):
		_finish(); return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(occupied_file))
	_check("occupied save contains car mode and parcel", saved is Dictionary and int(saved.mode) == Game.MODE_CAR and Courier.valid_state(saved.get("downtown_activity")) and int(saved.downtown_activity.stage) == Courier.Stage.OUTBOUND and int(saved.downtown_activity.completed_runs) == 0)
	# Deliberately perturb only the activity snapshot to prove Game.load_game
	# restores persisted data. Load's normal foot-checkpoint fallback is real.
	print("[courier-car] FIXTURE reset activity before testing saved-state restoration")
	activity.reset_state()
	if not _check("load occupied-car save", Game.load_game(occupied_file)):
		_finish(); return
	await get_tree().create_timer(0.4).timeout
	_check("parcel restored through Game.load_game", activity.serialize_state() == outbound)
	_check("occupied save restores honest foot checkpoint", Game.mode == Game.MODE_FOOT and player.current_vehicle == null and not car.driver_is_player)
	if not await _board_car():
		_finish(); return
	var destination: Vector3 = activity.stations.bayfront.global_position
	print("[courier-car] FIXTURE occupied car relocation from ", car.global_position, " to MBS handover; NOT continuous driving")
	car.global_position = destination + Vector3(-2.5, 0.5, 0)
	car.rotation = Vector3.ZERO
	car.velocity = Vector3.ZERO
	await get_tree().create_timer(0.8).timeout
	_check("real occupied car at destination", Game.mode == Game.MODE_CAR and player.current_vehicle == car and car.driver_is_player and player.controlled_actor() == car)
	_check("seated player proxy within handover range", player.global_position.distance_to(destination) < Courier.INTERACTION_RADIUS, str(player.global_position))
	_check("seated destination prompt unavailable", not activity.stations.bayfront.can_interact())
	_check("seated handover rejected without stage mutation", not activity.use_station("bayfront", player) and activity.serialize_state() == outbound)
	activity.stations.bayfront.interact(player)
	_check("station API also rejects seated handover", activity.serialize_state() == outbound)
	await _tap_e()
	if not _check("real E exits safely at destination", Game.mode == Game.MODE_FOOT and player.current_vehicle == null and not car.driver_is_player and player.visible):
		_finish(); return
	_check("exit remains on supported MBS ground", player.is_on_floor() and absf(player.global_position.y - destination.y) < 0.3, str(player.global_position))
	_check("on-foot courier interaction available after exit", activity.stations.bayfront.can_interact())
	if not _check("courier is real nearest E target", player._interaction_target() == activity.stations.bayfront):
		_finish(); return
	await _tap_e()
	if not _check("real E delivers after car exit", activity.stage == Courier.Stage.RECEIPT and activity.completed_runs == 0):
		_finish(); return
	var receipt: Dictionary = activity.serialize_state()
	var receipt_file := _qa.path_join("courier-car-receipt.json")
	_check("save delivered receipt", Game.save_game(receipt_file))
	print("[courier-car] FIXTURE reset activity before receipt restore")
	activity.reset_state()
	_check("load delivered receipt", Game.load_game(receipt_file))
	await get_tree().create_timer(0.3).timeout
	_check("receipt persists through actual save/load", activity.serialize_state() == receipt and activity.stage == Courier.Stage.RECEIPT)
	_check("receipt targets heritage dispatch", activity.objective_position().distance_to(dispatch) < 0.01)
	if "--courier-helicopter-check" in OS.get_cmdline_user_args():
		await _helicopter_receipt_fixture(dispatch, destination, receipt)
	_check("vehicle fixture has no deaths", Game.death_count == _deaths)
	_finish()

func _helicopter_receipt_fixture(dispatch: Vector3, destination: Vector3, receipt: Dictionary) -> void:
	var heli := main.get_node("Helicopter") as Helicopter
	if not _check("production helicopter exists", heli != null): return
	print("[courier-car] FIXTURE existing helicopter placed at MBS for landed receipt boarding; NOT flight")
	heli.global_position = destination + Vector3(-14, 0.7, 0)
	heli.rotation = Vector3(0, PI * 0.5, 0)
	heli.velocity = Vector3.ZERO
	var boarding := heli.global_position + heli.global_transform.basis.x * 3.6 + Vector3.UP * 0.3
	print("[courier-car] FIXTURE initial helicopter-side foot placement ", boarding)
	player.respawn_at(boarding, PI * 0.5)
	await get_tree().create_timer(1.2).timeout
	if not _check("native helicopter settles on MBS ground", heli.is_landed() and heli.is_on_floor()): return
	if not _check("helicopter is real nearest E target", player._interaction_target() == heli): return
	await _tap_e()
	if not _check("real E boards helicopter carrying receipt", Game.mode == Game.MODE_HELI and player.current_vehicle == heli and heli.pilot_is_player and activity.serialize_state() == receipt): return
	print("[courier-car] FIXTURE occupied helicopter relocation to heritage dispatch; NOT continuous flight")
	heli.global_position = dispatch + Vector3(0, 0.7, 2.8)
	heli.velocity = Vector3.ZERO
	# An occupied helicopter correctly hovers instead of falling. Use its
	# native descend control for this short local set-down, never forge the
	# landed flag or force the pilot out of an airborne vehicle.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var landing_deadline := Time.get_ticks_msec() + 6000
	Input.action_press("sprint")
	while not heli.is_on_floor() and Time.get_ticks_msec() < landing_deadline:
		await get_tree().physics_frame
	Input.action_release("sprint")
	await get_tree().create_timer(0.3).timeout
	_check("native helicopter descent lands at dispatch", heli.is_landed() and heli.is_on_floor() and player.current_vehicle == heli and Game.mode == Game.MODE_HELI, "position=%s velocity=%s" % [heli.global_position, heli.velocity])
	_check("helicopter passenger proxy within handover range", player.global_position.distance_to(dispatch) < Courier.INTERACTION_RADIUS, str(player.global_position))
	_check("helicopter seated receipt handover rejected", not activity.use_station("heritage", player) and activity.serialize_state() == receipt)
	activity.stations.heritage.interact(player)
	_check("station API rejects helicopter seated receipt", activity.serialize_state() == receipt)
	await _tap_e()
	if not _check("real E exits landed helicopter", Game.mode == Game.MODE_FOOT and player.current_vehicle == null and not heli.pilot_is_player and player.is_on_floor()): return
	if not _check("courier receipt is real nearest E target", player._interaction_target() == activity.stations.heritage): return
	await _tap_e()
	_check("real E completes receipt after helicopter exit", activity.stage == Courier.Stage.IDLE and activity.completed_runs == 1)

func _board_car() -> bool:
	# Walk round the rear of the real collision body to the driver side;
	# no foot placement shortcut is used for either boarding interaction.
	if not await _walk_to(car.global_position + Vector3(2.3, 0, 4.0)): return false
	if not await _walk_to(car.global_position + Vector3(2.3, 0, 0)): return false
	if not _check("car is real nearest E target", player._interaction_target() == car): return false
	await _tap_e()
	return _check("real E enters production car", Game.mode == Game.MODE_CAR and player.current_vehicle == car and car.driver_is_player and car.driver_player == player)

func _walk_to(target: Vector3) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var offset := target - player.global_position
		offset.y = 0
		if offset.length() < 0.65:
			_release()
			await get_tree().create_timer(0.2).timeout
			return true
		player.yaw = lerp_angle(player.yaw, atan2(-offset.x, -offset.z), 0.3)
		Input.action_press("move_forward")
	_release()
	return _check("walk to car door", false, str(player.global_position))

func _tap_e() -> void:
	_release()
	await get_tree().create_timer(0.2).timeout
	Input.action_press("interact")
	await get_tree().create_timer(0.08).timeout
	Input.action_release("interact")
	await get_tree().create_timer(0.4).timeout

func _release() -> void:
	for key in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact"]: Input.action_release(key)

func _finish() -> void:
	_release()
	print("[courier-car] RESULT ", JSON.stringify({"checks": _checks, "failures": _failures, "elapsed_s": (Time.get_ticks_msec() - _started) / 1000.0, "continuous_driving": false, "continuous_flight": false, "fixture_relocation": true, "native_local_car_motion_m": _local_car_motion_m}))
	Sfx.shutdown_audio()
	get_tree().quit(0 if _failures.is_empty() else 1)
