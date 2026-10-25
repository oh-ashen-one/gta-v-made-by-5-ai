extends "res://src/systems/downtown_activities/tests/courier_route.gd"
## Local reverse-route fixture. Starts explicitly on Jubilee's east approach
## and walks to Heritage Waterfront. It does not prove a full courier run.
func _run() -> void:
	_started = Time.get_ticks_msec()
	main = load("res://main.tscn").instantiate()
	add_child(main)
	player = main.player
	activity = main.downtown_activity
	var initial := Vector3(-540, 1.0, -400)
	player.respawn_at(initial, -PI * 0.5)
	_last_position = player.global_position
	_initial_deaths = Game.death_count
	main.started = true
	main.hud.show_title(false)
	Game.simulation_paused = false
	print("[courier-test] LOCAL JUBILEE RETURN FIXTURE initial spawn=", initial)
	await get_tree().create_timer(0.5).timeout
	var space := player.get_world_3d().direct_space_state
	for x: float in [-537.0, -534.0, -532.0, -530.5, -529.5, -528.0, -526.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 5, -400), Vector3(x, -2, -400), 1)
		var hit := space.intersect_ray(q)
		print("[courier-test] Jubilee ground x=", x, " y=", hit.get("position", Vector3.INF))
	var path: Array[Vector3] = [Vector3(-521, 0, -400), Vector3(-521, 0, -384), Vector3(-488, 0, -380), Vector3(-460, 0, -372), Vector3(-458, 0, -344), Vector3(-440, 0, -338), Vector3(-330, 0, -337), activity.stations.heritage.global_position]
	await _walk(path, "local Jubilee to heritage return")
	_check("local fixture has no deaths", Game.death_count == _initial_deaths)
	_check("local fixture has no teleport steps", _max_step < 2.0, str(_max_step))
	_finish()
