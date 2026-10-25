extends "res://src/systems/downtown_activities/tests/courier_route.gd"
## Local geometry fixture only. Initial spawn is explicitly at the MBS north
## corridor; no position assignment occurs during either controls-driven leg.
## This cannot establish end-to-end courier completion: use courier_route.
func _run() -> void:
	_started = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	activity = main.downtown_activity
	var mbs := DowntownPlan.anchor("marina_bay_sands")
	var quay_z := DowntownPlan.anchor("mbs_event_plaza").z + 10.0
	var initial := Vector3(mbs.x - 206, 0.2, quay_z - 18)
	player.respawn_at(initial, PI)
	_last_position = player.global_position
	_initial_deaths = Game.death_count
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	print("[courier-test] LOCAL MBS APPROACH FIXTURE initial spawn=", initial)
	await get_tree().create_timer(0.5).timeout
	var path: Array[Vector3] = [Vector3(mbs.x - 206, 0, quay_z), Vector3(mbs.x - 196, 0, quay_z), activity.stations.bayfront.global_position]
	if not await _walk(path, "local MBS ramp ingress"):
		_finish()
		return
	_check("MBS ring physical arrival", player.global_position.distance_to(activity.stations.bayfront.global_position) < 3.0)
	path.reverse()
	path.append(initial)
	await _walk(path, "local MBS ramp egress")
	_check("local fixture has no deaths", Game.death_count == _initial_deaths)
	_check("local fixture has no teleport steps", _max_step < 2.0, str(_max_step))
	_finish()
