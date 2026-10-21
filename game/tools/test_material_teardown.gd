extends Node3D
## Focused diagnostic for Godot dummy-renderer material teardown; not gameplay acceptance.
func _ready() -> void:
	for variant in ["sedan", "police"]:
		print("MATERIAL_PROBE spawning ", variant)
		var car := Car.new()
		car.kind = variant
		add_child(car)
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("MATERIAL_PROBE freeing ", variant)
		car.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("MATERIAL_PROBE finished ", variant)
	for role in ["civilian", "police", "hostile"]:
		print("MATERIAL_PROBE spawning NPC ", role)
		var npc := NPC.new()
		npc.is_police = role == "police"
		npc.is_hostile = role == "hostile"
		add_child(npc)
		await get_tree().physics_frame
		await get_tree().physics_frame
		npc.take_damage(200.0, Vector3.ZERO, false)
		await get_tree().physics_frame
		npc.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		print("MATERIAL_PROBE finished NPC ", role)
	var player := Player.new()
	print("MATERIAL_PROBE spawning player")
	add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("MATERIAL_PROBE reset player action state")
	player.reset_action_state()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for weapon in ["smg", "pistol"]:
		print("MATERIAL_PROBE swap weapon ", weapon)
		Game.switch_weapon(weapon)
		player._update_weapon_mesh()
		await get_tree().physics_frame
		await get_tree().physics_frame
	print("MATERIAL_PROBE freeing player")
	player.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Sfx.shutdown_audio()
	get_tree().quit()
