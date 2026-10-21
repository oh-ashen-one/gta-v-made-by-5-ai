extends SceneTree
## Bounded render-only verification fixture. Launch only under the shared slot.
## godot --path game --script ../docs/wave-02/characters/character_pose_fixture.gd
## Saves actual Godot frames and exits; it does not alter gameplay or save data.

var world: Node3D
var camera: Camera3D
var visual
var output := "res://../docs/wave-02/characters/godot"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 960)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.57, 0.66, 0.78)
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTED_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -34, 0)
	sun.light_color = Color(1.0, 0.89, 0.74)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.2, -2.0)
	fill.light_energy = 1.8
	fill.omni_range = 6.0
	fill.light_color = Color(0.65, 0.79, 1.0)
	world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.17, 0.20, 0.22)
	material.roughness = 0.86
	floor_mesh.material_override = material
	floor_mesh.position.y = -0.006
	world.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.position = Vector3(2.6, 1.85, -3.4)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var script := load("res://src/actors/character_visual.gd")
	var report: Array = []
	for role in ["player", "officer", "civilian"]:
		visual = script.new()
		visual.ignore_simulation_pause = true
		world.add_child(visual)
		var ok: bool = visual.configure(role, 3)
		if not ok:
			report.append({"role": role, "error": "configure failed"})
			visual.queue_free()
			continue
		for pose in ["idle", "walk", "run", "aim", "hit", "fall"]:
			visual.set_motion(0.0, pose == "aim", true, false)
			if pose == "aim":
				var gun := load("res://assets/providers/pistol_held.glb") as PackedScene
				if gun != null:
					visual.attach_weapon(gun.instantiate(), "pistol")
			visual.animator.play(pose)
			visual.animator.seek(0.2 if pose != "fall" else 0.9, true)
			visual.animator.pause()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file := output.path_join(role + "_" + pose + ".png")
			var error := root.get_texture().get_image().save_png(file)
			report.append({"role": role, "pose": pose, "path": file, "error": error,
				"bones": visual.skeleton.get_bone_count(), "clips": visual.animator.get_animation_list()})
		visual.queue_free()
		await process_frame
	var file := FileAccess.open(output.path_join("fixture-log.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_FIXTURE_DONE ", JSON.stringify(report))
	quit(0)
