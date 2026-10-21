extends Node
## Fixture-assisted UI appearance review, not an OS-input playtest.
var main: Node
var folder := "../docs/wave-02/ui-review"
func setup(value: Node) -> void:
	main=value
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): folder=arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	_run.call_deferred()
func _save(label: String) -> void:
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder+"/"+label+".png")
	print("[ui-review] ",label," paused=",Game.simulation_paused)
func _run() -> void:
	await _save("01_title")
	main._new_game()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await _save("02_start")
	main._toggle_pause()
	await _save("03_pause")
	main._toggle_settings()
	await _save("04_settings")
	main._toggle_settings()
	await _save("05_return_to_pause")
	main._quit_game()
