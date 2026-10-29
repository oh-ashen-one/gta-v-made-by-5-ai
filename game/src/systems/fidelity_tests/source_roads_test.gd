extends Node3D
## SYNTHETIC topology/ribbon physics fixture; never actual Singapore gameplay.
const Roads = preload("res://src/world/geography/source_roads.gd")
const Frame = preload("res://src/world/geography/source_frame.gd")
const SNAPSHOT := "res://data/geography/osm-2026-10-27/manifest.json"
const FIXTURE := "res://data/geography/source-roads/qa-fixture-v4"
const FIXTURE_SHA := "217d7bde5a019d110648ac3fd1f877763d58135eefde78fc23f4ceabf358d7a0"
const REPORT_NAME := "source-roads-report.json"
var checks := 0
var failures: Array[String] = []
var metrics: Dictionary = {}
var qa_session := ""
var output := ""
var finished := false
var walker: CharacterBody3D
var walking := false
var prior := Vector3.ZERO
var max_step := 0.0
var maximum_y := -INF
var supported_frames := 0
var walking_frames := 0

class Walker extends CharacterBody3D:
	var moving := false
	func _physics_process(delta: float) -> void:
		velocity.x = 5.0 if moving else 0.0
		velocity.y -= 9.8 * delta
		move_and_slide()

func check(label: String, condition: bool, detail: String = "") -> bool:
	checks += 1
	print("[source-roads] %s %s %s" % ["PASS" if condition else "FAIL", label, detail])
	if not condition: failures.append(label)
	return condition

func _sha(raw: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(raw); return h.finish().hex_encode()

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func _ready() -> void:
	var args := OS.get_cmdline_user_args(); var at := args.find("--qa-session")
	if at < 0 or at + 1 >= args.size(): get_tree().quit(2); return
	qa_session = args[at + 1]
	if qa_session.begins_with("/tmp/"): qa_session = "/private/tmp/" + qa_session.trim_prefix("/tmp/")
	if not _report_path_error(qa_session, true).is_empty() or DirAccess.make_dir_absolute(qa_session) != OK or not _report_path_error(qa_session, false).is_empty(): get_tree().quit(2); return
	output = qa_session.path_join(REPORT_NAME)
	get_tree().create_timer(90.0, true, true).timeout.connect(func():
		if not finished:
			check("bounded native road fixture", false, "90s")
			finish())
	run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not walking or not is_instance_valid(walker): return
	walking_frames += 1
	if walker.is_on_floor(): supported_frames += 1
	max_step = maxf(max_step, walker.position.distance_to(prior)); prior = walker.position
	maximum_y = maxf(maximum_y, walker.position.y)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func _resign(plan: Dictionary) -> void:
	plan.content_sha256 = _sha(JSON.stringify(plan.data, "", true, true).to_utf8_buffer())

func run() -> void:
	var bytes := FileAccess.get_file_as_bytes(SNAPSHOT)
	var manifest: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not check("actual canonical frame reference exists", typeof(manifest) == TYPE_DICTIONARY): finish(); return
	var frame := Frame.new()
	if not check("source frame configures without compression", frame.configure(manifest.georeference, [0, 0, 0], _sha(bytes))): finish(); return
	var roads := Roads.new()
	if not check("pinned explicitly synthetic road artifact configures", roads.configure(FIXTURE, FIXTURE_SHA, frame), roads.last_error): finish(); return
	check("wrong pinned artifact refuses", not Roads.new().configure(FIXTURE, "0".repeat(64), frame))
	var graph: Dictionary = roads.prepare_graph("fixture")
	if not check("bound original-node graph prepares and commits", graph.ok and roads.commit_graph(graph.plan).ok): finish(); return
	var bridge_key := 'node/4|grade/["bridge",1,""]'
	var lower_key := 'node/9|grade/["surface",0,""]'
	var car: Dictionary = roads.successors(bridge_key, "car")
	var foot: Dictionary = roads.successors(bridge_key, "foot")
	check("oneway car has only source-forward arc", car.ok and car.edges.size() == 1 and car.edges[0].to_vertex_id == "6")
	check("foot mode retains its explicit reverse allowance", foot.ok and foot.edges.size() == 2)
	var lower: Dictionary = roads.successors(lower_key, "car")
	check("sameXY overpass never gains original-node adjacency", lower.ok and lower.edges.size() == 2 and lower.edges.all(func(e: Dictionary): return not e.to_vertex_id in ["4", "5", "6"]))
	check("unknown graph vertex requests data rather than outside recovery", roads.successors("not-loaded", "car").get("requires_chunk", false))
	var tampered: Dictionary = graph.plan.duplicate(true)
	tampered.data.edges[0].directions.car = 3
	check("accidental changed graph plan rejects", not roads.commit_graph(tampered).ok)
	check("graph release explicitly drops resident cache", roads.release_graph("fixture") and roads.successors(bridge_key, "car").get("requires_chunk", false))
	check("canonical graph reload succeeds", roads.commit_graph(graph.plan).ok)
	var physical: Dictionary = roads.prepare_physical("fixture")
	if not check("physical source ribbon plan prepares", physical.ok): finish(); return
	var baseline_children := get_child_count()
	tampered = physical.plan.duplicate(true)
	tampered.data.features[0].mesh.indices[0] = 999999
	_resign(tampered)
	check("invalid index rejects before scene mutation", not roads.build_physical(tampered, self).ok and get_child_count() == baseline_children)
	tampered = physical.plan.duplicate(true)
	var temp: Variant = tampered.data.features[0].mesh.indices[0]
	tampered.data.features[0].mesh.indices[0] = tampered.data.features[0].mesh.indices[1]
	tampered.data.features[0].mesh.indices[1] = temp
	_resign(tampered)
	check("reversed native collision winding rejects without culling bypass", not roads.build_physical(tampered, self).ok and get_child_count() == baseline_children)
	tampered = physical.plan.duplicate(true)
	tampered.data.features[0].mesh.vertices_local_xyz[0][1] += 50.0
	_resign(tampered)
	check("shader normals cannot hide actual excessive physical slope", not roads.build_physical(tampered, self).ok and get_child_count() == baseline_children)
	var built: Dictionary = roads.build_physical(physical.plan, self)
	if not check("identical render/collision topology commits", built.ok and built.features == 5, str(built)): finish(); return
	await frames(5)
	var above: Dictionary = ray(Vector3(25, 20, 0), Vector3(25, -2, 0))
	var below: Dictionary = ray(Vector3(25, 5, 0), Vector3(25, -2, 0))
	check("native above ray hits separate raised bridge deck", not above.is_empty() and absf(above.position.y - 6.0) < .005 and above.normal.y > .99, str(above))
	check("native underbridge ray hits ground crossing separately", not below.is_empty() and absf(below.position.y) < .005 and below.normal.y > .99, str(below))
	check("native bridge-ground clearance remains6m", not above.is_empty() and not below.is_empty() and absf(above.position.y - below.position.y - 6.0) < .005)
	check("native road loop leaves actual collision hole", ray(Vector3(220, 15, 220), Vector3(220, -5, 220)).is_empty())
	check("native road loop edge supports from above", not ray(Vector3(200, 15, 220), Vector3(200, -5, 220)).is_empty())
	var body := Walker.new()
	body.collision_layer = 2; body.collision_mask = 1; body.floor_snap_length = .35; body.floor_max_angle = deg_to_rad(52)
	var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius = .36; capsule.height = 1.75
	shape.shape = capsule; shape.position = Vector3(0, .9, 0); body.add_child(shape)
	body.position = Vector3(-90, .12, 0) # One declared isolated-standin initial pose.
	add_child(body); walker = body
	await frames(30)
	check("native capsule settles on west road", body.is_on_floor() and absf(body.position.y) < .12)
	prior = body.position; walking = true; body.moving = true
	var end := Time.get_ticks_msec() + 60000
	while body.position.x < 140.0 and Time.get_ticks_msec() < end: await get_tree().physics_frame
	body.moving = false; walking = false
	await frames(5)
	check("native capsule crosses both actual ribbon seams and ramps", body.position.x >= 140.0 and absf(body.position.y) < .12 and maximum_y > 5.90, str({"position": body.position, "peak_y": maximum_y}))
	check("incremental physical traversal preserves floor support", walking_frames > 100 and float(supported_frames) / walking_frames > .95 and max_step < .20, str({"samples": walking_frames, "supported": supported_frames, "max_step": max_step}))
	metrics["synthetic_native_traversal"] = {"samples": walking_frames, "supported_samples": supported_frames, "max_step_m": max_step, "peak_y_m": maximum_y, "end_xyz": [body.position.x, body.position.y, body.position.z], "production_Player_or_Car": false, "actual_country_route": false}
	finish()

func finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(walker): walker.set("moving", false)
	var report := {"checks": checks, "failures": failures, "metrics": metrics,
		"scope": "SYNTHETIC original-node/direction/cache/ribbon/collision/ramp fixture. No actual source Singapore route, production car/actor/traffic integration, terrain cut/fill, rendered/performance or whole-goal acceptance."}
	var written := _write_guarded_report(qa_session, output, JSON.stringify(report, "\t", true, true))
	if not written.ok: push_error(written.error); get_tree().quit(2); return
	print("[source-roads] RESULT ", JSON.stringify(report)); get_tree().quit(0 if failures.is_empty() else 1)

func _owned(path: String) -> bool:
	if path != path.simplify_path() or not path.begins_with("/private/tmp/singapore-fidelity/"): return false
	var parent := "/private/tmp"
	var parts := path.trim_prefix("/private/tmp/").split("/", false)
	for i in parts.size():
		var part: String = parts[i]
		var folder := DirAccess.open(parent)
		if folder == null or folder.is_link(part): return false
		var next := parent.path_join(part)
		if not folder.dir_exists(part):
			# Only a missing final session component is allowed; its verified
			# parent must already exist. Regular files/dangling links refuse.
			return i == parts.size() - 1 and not _entry_present(next)
		parent = next
	return true

## Directory enumeration notices existing entries without opening/following
## the report leaf. FileAccess.file_exists alone misses dangling symlinks.
func _entry_present(path: String) -> bool:
	var folder := DirAccess.open(path.get_base_dir())
	if folder == null: return true # Failure to prove absence is a refusal.
	var leaf := path.get_file()
	if folder.is_link(leaf): return true
	folder.include_hidden = true
	if folder.list_dir_begin() != OK: return true
	for i in 4096:
		var entry := folder.get_next()
		if entry.is_empty():
			folder.list_dir_end()
			return false
		if entry == leaf:
			folder.list_dir_end()
			return true
	folder.list_dir_end()
	return true # Oversized/unreadable evidence directory fails closed.

func _report_path_error(session: String, require_fresh_session: bool) -> String:
	if not _owned(session): return "QA session has an unsafe path, ancestor or entry"
	if require_fresh_session:
		if _entry_present(session): return "QA session must be fresh; existing entries are refused"
		return ""
	if not DirAccess.dir_exists_absolute(session): return "QA session directory disappeared"
	if _entry_present(session.path_join(REPORT_NAME)): return "Report leaf already exists or is a link"
	return ""

func _write_guarded_report(session: String, destination: String, content: String) -> Dictionary:
	if destination != session.path_join(REPORT_NAME): return {"ok": false, "error": "Output no longer matches its checked report path"}
	var path_error := _report_path_error(session, false)
	if not path_error.is_empty(): return {"ok": false, "error": path_error}
	# Immediate recheck above is an ownership guard, not an O_EXCL primitive.
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null: return {"ok": false, "error": "Cannot create source-roads report"}
	file.store_string(content)
	file.flush()
	var complete := file.get_error() == OK and file.get_length() == content.to_utf8_buffer().size()
	file.close()
	return {"ok": true} if complete else {"ok": false, "error": "Incomplete source-roads report write"}


