extends Node3D
## Actual rendered lighting A/B in one production world, with disclosed fixed
## camera poses. No native route/control, performance or visual acceptance.
## Parent alone launches this through the shared engine wrapper.
const CANDIDATE_PATH := "res://assets/authored/shaders/golden_hour_sky.gdshader"
const DEFAULT_BASELINE_SHA := "daf5b419a7026eed3bd5b0e62ce1b3006a5b35b0e4cf15cce7ddb40a2d282c84"
const DEFAULT_CANDIDATE_SHA := "75e46d5f8fe9f303930b685fba49c8fd9a1fb4610c3ded91198e5471c0ac8b78"
const REVIEW_LIMIT_SECONDS := 120.0
const MAX_SHADER_BYTES := 128 * 1024
const SKY_UNIFORMS := ["zenith_color", "mid_color", "horizon_cool", "horizon_warm", "ground_color", "sky_energy", "cloud_coverage", "cloud_scale", "sun_disc_energy", "fallback_sun"]
var output := ""
var qa_session := ""
var baseline_path := ""
var baseline_ref := "parent-provided baseline"
var baseline_sha := DEFAULT_BASELINE_SHA
var candidate_sha := DEFAULT_CANDIDATE_SHA
var baseline_code := ""
var candidate_code := ""
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var warmups: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var main: Node3D
var camera: Camera3D
var environment: Environment
var original_sky: Sky
var original_material: ShaderMaterial
var uniform_values: Dictionary = {}
var effective_uniform_values: Dictionary = {}
var uniform_resolution: Dictionary = {}
var phase_uniform_resolution: Dictionary = {}
var sky_settings: Dictionary = {}
var world_startup_ms := 0
var world_ready_ms := -1
var initial_game_seconds := 0.0
var _finished := false
var _configured := false
var _rendered := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _configure():
		get_tree().quit(2)
		return
	_configured = true
	source_hashes = _selected_source_hashes()
	if DisplayServer.get_name() == "headless":
		failures.append("Headless invocation cannot produce rendered sky evidence")
		_finish("headless_refused", 2)
		return
	Game.simulation_paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_run.call_deferred()

func _process(_delta: float) -> void:
	# Start AFTER synchronous world construction; a newly-created Timer can
	# otherwise consume the cold world's accumulated first-frame delta.
	if not _finished and world_ready_ms >= 0 and _elapsed() > REVIEW_LIMIT_SECONDS:
		failures.append("Post-world monotonic capture limit exceeded")
		_finish("capture_timeout", 1)

func _elapsed() -> float:
	return 0.0 if world_ready_ms < 0 else float(Time.get_ticks_msec() - world_ready_ms) / 1000.0

func _canonical(path: String) -> String:
	return "/private/tmp/" + path.trim_prefix("/tmp/") if path.begins_with("/tmp/") else path

func _owned(path: String) -> bool:
	var prefix := "/private/tmp/singapore-fidelity/"
	if path != path.simplify_path() or not path.begins_with(prefix): return false
	var parts := path.trim_prefix(prefix).split("/", false)
	if parts.is_empty() or not String(parts[0]).begins_with("sky-pole-review-"): return false
	var parent := "/private/tmp"
	for part in path.trim_prefix("/private/tmp/").split("/", false):
		var dir := DirAccess.open(parent)
		if dir != null and dir.is_link(part): return false
		parent = parent.path_join(part)
	return true

func _sha(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _hash_file(path: String) -> String:
	return _sha(FileAccess.get_file_as_bytes(path))

func _valid_hash(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}$")
	return pattern.search(value) != null

func _configure() -> bool:
	var args := OS.get_cmdline_user_args()
	var seen: Dictionary = {}
	var i := 0
	while i < args.size():
		var arg: String = args[i]
		if arg == "--qa-session":
			if seen.has("qa") or i + 1 >= args.size(): return _configuration_error("Require one explicit --qa-session path")
			seen["qa"] = true
			i += 1
			qa_session = _canonical(args[i])
		elif arg.begins_with("--qa-render-size="):
			pass # main.gd applies this existing backing-resolution option.
		elif arg.begins_with("--sky-pole-output="):
			if seen.has("output"): return _configuration_error("Duplicate output option")
			seen["output"] = true
			output = _canonical(arg.trim_prefix("--sky-pole-output="))
		elif arg.begins_with("--sky-pole-baseline="):
			if seen.has("baseline"): return _configuration_error("Duplicate baseline option")
			seen["baseline"] = true
			baseline_path = _canonical(arg.trim_prefix("--sky-pole-baseline="))
		elif arg.begins_with("--sky-pole-baseline-sha256="):
			baseline_sha = arg.trim_prefix("--sky-pole-baseline-sha256=")
		elif arg.begins_with("--sky-pole-candidate-sha256="):
			candidate_sha = arg.trim_prefix("--sky-pole-candidate-sha256=")
		elif arg.begins_with("--sky-pole-baseline-ref="):
			baseline_ref = arg.trim_prefix("--sky-pole-baseline-ref=")
		else:
			return _configuration_error("Unsupported option; do not combine another QA controller or save override")
		i += 1
	if not seen.has("qa") or not seen.has("output") or not seen.has("baseline") or not _owned(output) or not _owned(qa_session) or not _owned(baseline_path):
		return _configuration_error("Use explicit normalized nonsymlink sky-pole-review-* output, QA and baseline paths")
	if output == qa_session or output.begins_with(qa_session + "/") or qa_session.begins_with(output + "/"):
		return _configuration_error("Capture and isolated save directories must be separate")
	if FileAccess.file_exists(output.path_join("review.json")):
		return _configuration_error("Refusing to overwrite existing capture evidence")
	if not _valid_hash(baseline_sha) or not _valid_hash(candidate_sha) or baseline_sha == candidate_sha:
		return _configuration_error("Require distinct valid baseline and candidate source identities")
	for path: String in [baseline_path, CANDIDATE_PATH]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() < 1 or file.get_length() > MAX_SHADER_BYTES:
			return _configuration_error("Cannot read a bounded shader source")
		var bytes := file.get_buffer(file.get_length())
		if path == baseline_path:
			if _sha(bytes) != baseline_sha: return _configuration_error("Baseline shader hash mismatch")
			baseline_code = bytes.get_string_from_utf8()
		else:
			if _sha(bytes) != candidate_sha: return _configuration_error("Candidate shader hash mismatch")
			candidate_code = bytes.get_string_from_utf8()
	if not baseline_code.begins_with("shader_type sky;") or not candidate_code.begins_with("shader_type sky;"):
		return _configuration_error("Expected actual sky shader sources")
	if _canonical(String(Game.get("_save_path"))) != qa_session.path_join("orchard_reach_save.json"):
		return _configuration_error("Game save path is not confined to the explicit QA session")
	if FileAccess.file_exists(qa_session.path_join("orchard_reach_save.json")):
		return _configuration_error("Use a fresh QA session; existing saves are preserved")
	return DirAccess.make_dir_recursive_absolute(output) == OK and DirAccess.make_dir_recursive_absolute(qa_session) == OK

func _configuration_error(message: String) -> bool:
	push_error("[sky-pole-review] " + message)
	return false

func _selected_source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["res://main.tscn", "res://src/main.gd", "res://src/world/world_builder.gd", "res://src/world/lighting.gd", CANDIDATE_PATH, "res://src/systems/fidelity_tests/sky_pole_review.gd"]:
		result[path] = _hash_file(path)
	result["baseline_shader"] = _hash_file(baseline_path)
	return result

func _check(label: String, ok: bool, detail: String = "") -> bool:
	if _finished: return false
	checks += 1
	print("[sky-pole-review] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok: failures.append(label)
	return ok

func _freeze_callbacks(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children(): _freeze_callbacks(child)

func _environment_nodes(node: Node, result: Array[WorldEnvironment]) -> void:
	if node is WorldEnvironment: result.append(node as WorldEnvironment)
	for child in node.get_children(): _environment_nodes(child, result)

func _run() -> void:
	initial_game_seconds = Game.elapsed_seconds
	get_tree().paused = true
	var started := Time.get_ticks_msec()
	main = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	add_child(main) # Production district, lights, actors, materials and atmosphere.
	world_startup_ms = Time.get_ticks_msec() - started
	world_ready_ms = Time.get_ticks_msec()
	_freeze_callbacks(main)
	Game.simulation_paused = true
	if not _check("production world, player and HUD constructed", main.get("world") != null and main.get("player") != null and main.get("hud") != null):
		_finish("setup_failed", 1); return
	main.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action in InputMap.get_actions():
		Input.action_release(action)
		InputMap.action_erase_events(action) # Only this isolated QA process.
	Sfx.shutdown_audio()
	var nodes: Array[WorldEnvironment] = []
	_environment_nodes(main, nodes)
	if not _check("exactly one production WorldEnvironment", nodes.size() == 1):
		_finish("setup_failed", 1); return
	environment = nodes[0].environment
	if not _check("production sky and shader material exist", environment != null and environment.sky != null and environment.sky.sky_material is ShaderMaterial):
		_finish("setup_failed", 1); return
	original_sky = environment.sky
	original_material = original_sky.sky_material as ShaderMaterial
	if not _check("loaded production candidate matches frozen source", original_material.shader != null and _sha(original_material.shader.code.to_utf8_buffer()) == candidate_sha):
		_finish("setup_failed", 1); return
	var production_uniforms := _uniform_snapshot(original_material)
	uniform_resolution = _resolution_record(production_uniforms)
	uniform_values = production_uniforms.get("values", {})
	if not _check("all effective production sky uniforms resolved", production_uniforms.get("ok", false), JSON.stringify(uniform_resolution)):
		_finish("setup_failed", 1); return
	effective_uniform_values = production_uniforms["raw"]
	sky_settings = {"radiance_size": original_sky.get("radiance_size"), "process_mode": original_sky.get("process_mode"),
		"tonemap_exposure": environment.tonemap_exposure, "ambient_light_source": environment.ambient_light_source,
		"ambient_light_sky_contribution": environment.ambient_light_sky_contribution, "reflected_light_source": environment.reflected_light_source}
	camera = Camera3D.new()
	camera.name = "DisclosedSkyLightingFixtureCamera"
	camera.cull_mask = main.player.camera.cull_mask
	add_child(camera)
	camera.current = true
	var opening: Vector3 = main.world.locations["player_start"]
	var elevated: Vector3 = main.world.locations["helipad_primary"] + Vector3(0.0, 245.0, 0.0)
	var poses: Array[Dictionary] = [
		# A disclosed eye-height sidewalk camera just ahead of the frozen actor,
		# not a claim about the native player camera or animation/control.
		{"label": "01_ground", "position": opening + Vector3(0.0, 1.65, -1.0), "pitch_deg": -8.0, "yaw_deg": -8.0, "fov": 58.0},
		{"label": "02_horizon", "position": elevated, "pitch_deg": 0.0, "yaw_deg": 35.0, "fov": 62.0},
		{"label": "03_cap_below", "position": elevated, "pitch_deg": 62.0, "yaw_deg": 35.0, "fov": 62.0},
		{"label": "04_cap_above", "position": elevated, "pitch_deg": 72.0, "yaw_deg": 35.0, "fov": 62.0},
		{"label": "05_near_vertical", "position": elevated, "pitch_deg": 88.5, "yaw_deg": 35.0, "fov": 62.0}
	]
	for phase: String in ["baseline", "candidate"]:
		if _finished: return
		var shader := Shader.new()
		shader.code = baseline_code if phase == "baseline" else candidate_code
		var material := original_material.duplicate(true) as ShaderMaterial
		material.shader = shader
		# Validate EVERY declared material uniform, including source defaults.
		# ShaderMaterial.get_shader_parameter() alone returned null for seven
		# unset overrides in R1; null does not mean their GPU defaults are absent.
		var before_apply := _uniform_snapshot(material)
		phase_uniform_resolution[phase + "_before_apply"] = _resolution_record(before_apply)
		if not _check("complete uniform interface matches for " + phase, before_apply.get("ok", false) and before_apply.get("interface") == production_uniforms.get("interface"), JSON.stringify(phase_uniform_resolution[phase + "_before_apply"])):
			_finish("setup_failed", 1); return
		if not _check("declared defaults and effective starting values match for " + phase, before_apply.get("defaults") == production_uniforms.get("defaults") and before_apply.get("values") == uniform_values):
			_finish("setup_failed", 1); return
		for name: String in effective_uniform_values:
			material.set_shader_parameter(name, effective_uniform_values[name])
		var applied := _uniform_snapshot(material)
		phase_uniform_resolution[phase + "_applied"] = _resolution_record(applied)
		if not _check("all effective scene uniform values preserved for " + phase, applied.get("ok", false) and applied.get("values") == uniform_values, JSON.stringify(phase_uniform_resolution[phase + "_applied"])):
			_finish("setup_failed", 1); return
		var sky := original_sky.duplicate(true) as Sky
		sky.sky_material = material
		environment.sky = sky
		_set_pose(poses[0])
		await _warm(phase + ": sky/radiance", 4.0, 48)
		for pose: Dictionary in poses:
			if _finished: return
			_set_pose(pose)
			await _warm(phase + ": " + String(pose.label), 1.0, 16)
			await _capture(phase, pose, _sha(shader.code.to_utf8_buffer()))
	_check("all ten real images recorded", captures.size() == 10 and captures.all(func(c: Dictionary) -> bool: return c.saved))
	_check("selected source identities unchanged during capture", _selected_source_hashes() == source_hashes)
	_check("simulation remained paused without game-time advancement", Game.simulation_paused and is_equal_approx(Game.elapsed_seconds, initial_game_seconds))
	_check("no save was written by this lighting fixture", not FileAccess.file_exists(qa_session.path_join("orchard_reach_save.json")))
	for i in 5:
		if captures.size() == 10:
			_check("matching camera, pixels and node count across pair " + str(i + 1), captures[i].camera == captures[i + 5].camera and captures[i].pixels == captures[i + 5].pixels and captures[i].world_node_count == captures[i + 5].world_node_count)
	_finish("capture_pipeline_completed" if failures.is_empty() else "capture_pipeline_failed", 0 if failures.is_empty() else 1)

func _set_pose(pose: Dictionary) -> void:
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pose.pitch_deg), deg_to_rad(pose.yaw_deg), 0.0)), pose.position)
	camera.fov = pose.fov
	camera.current = true

func _warm(label: String, seconds: float, minimum_frames: int) -> void:
	var start := Time.get_ticks_msec()
	var count := 0
	while not _finished and (Time.get_ticks_msec() - start < int(seconds * 1000.0) or count < minimum_frames):
		await RenderingServer.frame_post_draw
		count += 1
	if not _finished: warmups.append({"label": label, "actual_ms": Time.get_ticks_msec() - start, "rendered_frames": count, "guarantees_radiance_convergence": false})

func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _uniform_snapshot(material: ShaderMaterial) -> Dictionary:
	var result := {"ok": false, "error": "", "interface": [], "defaults": {}, "values": {}, "origins": {}, "raw": {}}
	if material == null or material.shader == null:
		result.error = "Missing shader material/resource"
		return result
	var names: Array[String] = []
	for entry: Dictionary in material.shader.get_shader_uniform_list(false):
		var name := String(entry.get("name", ""))
		if name.is_empty() or names.has(name):
			result.error = "Empty or duplicate reflected uniform name"
			return result
		names.append(name)
		result.interface.append({"name": name, "type": entry.get("type"), "hint": entry.get("hint"), "hint_string": entry.get("hint_string", "")})
		# Record every declared default, including uniforms overridden by the
		# production material, so the two shader interfaces/defaults are proven
		# identical before explicit effective values are applied.
		var shader_default: Variant = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), name)
		if not _finite_uniform(shader_default):
			result.error = "Unresolved, nonfinite or unsupported declared default: " + name + " type=" + type_string(typeof(shader_default))
			return result
		result.defaults[name] = _encode_uniform(shader_default)
		var value: Variant = material.get_shader_parameter(name)
		var origin := "material_override"
		if value == null:
			# Official RenderingServer API: query the default value associated
			# with this actual Shader RID, rather than inventing/skipping it.
			value = shader_default
			origin = "rendering_server_shader_default"
		result.origins[name] = origin
		if not _finite_uniform(value):
			result.error = "Unresolved, nonfinite or unsupported effective uniform: " + name + " type=" + type_string(typeof(value))
			return result
		result.raw[name] = value
		result.values[name] = _encode_uniform(value)
	names.sort()
	var expected: Array = SKY_UNIFORMS.duplicate()
	expected.sort()
	if names != expected:
		result.error = "Reflected uniform interface differs from the complete frozen ten-uniform contract"
		return result
	result.interface.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name) < String(b.name))
	result.ok = true
	return result

func _finite_uniform(value: Variant) -> bool:
	if typeof(value) == TYPE_INT: return true
	if typeof(value) == TYPE_FLOAT: return is_finite(float(value))
	if value is Vector3: return value.is_finite()
	if value is Color: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	return false

func _encode_uniform(value: Variant) -> Variant:
	if value is Vector3: return _v3(value)
	if value is Color: return [value.r, value.g, value.b, value.a]
	return value

func _resolution_record(snapshot: Dictionary) -> Dictionary:
	var record := snapshot.duplicate(true)
	record.erase("raw") # Typed values remain internal for exact application.
	return record

func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += _count_nodes(child)
	return count

func _camera_record() -> Dictionary:
	var camera_transform := camera.global_transform
	return {"position": _v3(camera_transform.origin), "basis_x": _v3(camera_transform.basis.x), "basis_y": _v3(camera_transform.basis.y), "basis_z": _v3(camera_transform.basis.z), "forward": _v3(-camera_transform.basis.z), "fov": camera.fov, "near": camera.near, "far": camera.far, "cull_mask": camera.cull_mask, "environment_override": camera.environment != null}

func _capture(phase: String, pose: Dictionary, actual_shader_sha: String) -> void:
	if _finished: return
	_freeze_callbacks(main) # Include any late deferred construction nodes.
	if not _check("fixture camera is active for " + phase + "/" + String(pose.label), get_viewport().get_camera_3d() == camera): return
	await RenderingServer.frame_post_draw
	if _finished: return
	var directory := output.path_join(phase)
	var file := directory.path_join(String(pose.label) + ".png")
	if not _owned(directory) or not _owned(file) or FileAccess.file_exists(file) or DirAccess.make_dir_recursive_absolute(directory) != OK:
		_check("capture path is new and owned", false, phase + "/" + String(pose.label)); return
	var image := get_viewport().get_texture().get_image()
	var saved := image != null and not image.is_empty() and image.save_png(file) == OK
	_rendered = _rendered or saved
	_check("actual rendered image saved " + phase + "/" + String(pose.label), saved)
	var record := {"phase": phase, "pose": pose.label, "file": file, "saved": saved, "pixels": [], "png_sha256": "", "camera_fixture": true,
		"camera": _camera_record(), "shader_code_sha256": actual_shader_sha, "world_instance_id": main.get_instance_id(), "world_node_count": _count_nodes(main),
		"utc": Time.get_datetime_string_from_system(true) + "Z", "unix_seconds": Time.get_unix_time_from_system(),
		"post_world_elapsed_s": _elapsed(), "viewport_visible_size": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]}
	if image != null: record["pixels"] = [image.get_width(), image.get_height()]
	if saved: record["png_sha256"] = _hash_file(file)
	captures.append(record)

func _finish(terminal: String, code: int) -> void:
	if _finished: return
	_finished = true
	if environment != null and original_sky != null: environment.sky = original_sky
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var same_world_verified := captures.size() == 10 and is_instance_valid(main)
	if is_instance_valid(main):
		for capture: Dictionary in captures:
			if not capture.saved or capture.world_instance_id != main.get_instance_id(): same_world_verified = false
	var report := {"schema": "singapore_sky_pole_rendered_ab_v1", "terminal": terminal, "checks": checks, "failures": failures,
		"rendered": _rendered, "display_server": DisplayServer.get_name(), "engine_version": Engine.get_version_info(),
		"requested_rendering_method": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"world_startup_ms": world_startup_ms, "post_world_elapsed_s": _elapsed(), "capture_limit_after_world_s": REVIEW_LIMIT_SECONDS,
		"baseline_ref_label": baseline_ref, "baseline_sha256": baseline_sha, "candidate_sha256": candidate_sha,
		"selected_source_hashes": source_hashes, "sky_uniform_values": uniform_values, "production_uniform_resolution": uniform_resolution,
		"phase_uniform_resolution": phase_uniform_resolution, "production_sky_settings": sky_settings, "captures": captures, "warmups": warmups,
		"camera_fixtures": true, "same_world_for_both_phases": same_world_verified, "native_human_input_verified": false,
		"performance_accepted": false, "visual_accepted": false, "whole_ground_image_invariance_verified": false,
		"shader_compile_accepted": false, "full_singapore_or_mbs_verified": false,
		"scope": "Actual image acquisition only. Compare matched frames and engine logs; successful PNG writes do not establish shader correctness, radiance convergence, visual quality, frame rate or native gameplay. The actual production world is frozen and camera positions are disclosed fixtures. Ambient/reflections use each phase's sky and can affect ground views. Render-time shader animation/TAA may vary despite frozen gameplay."}
	if _configured and _owned(output) and not FileAccess.file_exists(output.path_join("review.json")):
		var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
		else:
			push_error("[sky-pole-review] Failed to write owned capture report")
			report["terminal"] = "report_write_failed"
			failures.append("Could not write capture report")
			code = 1
	print("[sky-pole-review] RESULT ", JSON.stringify(report))
	Sfx.shutdown_audio()
	get_tree().quit(code)
