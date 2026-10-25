extends RefCounted
## Wave S performance piece: regression checks (called from SelfTest).
## Each check is [name, passed, detail].

static func run(main: Node) -> Array:
	var out: Array = []
	var world := main.get_node_or_null("World") as WorldBuilder
	var district: Node = world.get_node_or_null("District") if world != null else null
	# Occlusion culling: enabled, and solid building volumes became occluders.
	var occ := district.get_node_or_null("PerfOccluders") if district != null else null
	var occ_n := occ.get_child_count() if occ != null else 0
	out.append(["perf-S: occlusion culling on with >= 150 building occluders (downtown shells, shophouse rows, HDB slabs)",
		bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)) and occ_n >= 150, "occluders=%d" % occ_n])
	# Every occluder sits above the street band (arcades, lobbies, void decks stay see-through).
	var low := 0
	if occ != null:
		for o in occ.get_children():
			var oi := o as OccluderInstance3D
			var bo := oi.occluder as BoxOccluder3D
			if bo == null or oi.global_position.y - bo.size.y * 0.5 < 3.5:
				low += 1
	out.append(["perf-S: occluders start above the street band (>= 3.5 m)", occ_n > 0 and low == 0, "below=%d" % low])
	# Background tree batches are chunked: no rain-tree MultiMesh holds more than one cell's worth.
	var big := 0
	var tree_mm := 0
	if district != null:
		for c in district.get_children():
			if c is MultiMeshInstance3D and c.multimesh != null and c.multimesh.mesh != null and "rain_tree" in c.multimesh.mesh.resource_path:
				tree_mm += 1
				if c.multimesh.instance_count > 120:
					big += 1
	out.append(["perf-S: rain-tree batches are per-cell (culled, distance LOD), none map-wide", tree_mm > 0 and big == 0, "batches=%d oversized=%d" % [tree_mm, big]])
	var groups: Array = PerfBudget.cell_groups([Transform3D(Basis(), Vector3(10, 0, 10)), Transform3D(Basis(), Vector3(15, 0, 20)), Transform3D(Basis(), Vector3(900, 0, 10))], 200.0)
	out.append(["perf-S: cell grouping splits far instances", groups.size() == 2, "groups=%d" % groups.size()])
	# Crowd animation strides.
	var s_near := PerfBudget.people_anim_stride(10.0 * 10.0, true)
	var s_mid := PerfBudget.people_anim_stride(50.0 * 50.0, true)
	var s_far := PerfBudget.people_anim_stride(120.0 * 120.0, true)
	var s_off := PerfBudget.people_anim_stride(10.0 * 10.0, false)
	out.append(["perf-S: crowd animates every frame near, strided far and off screen", s_near == 1 and s_mid > 1 and s_far >= s_mid and s_off > 1,
		"near=%d mid=%d far=%d off=%d" % [s_near, s_mid, s_far, s_off]])
	# Packaged builds: the look-mesh bake is accepted when the source .glb is not shipped.
	out.append(["perf-S: look bake valid in packaged builds (source .glb absent) and still rejected for a different source",
		CharacterLook._source_matches({"source": "res://assets/providers/__absent__.glb", "source_bytes": 123}, "res://assets/providers/__absent__.glb")
		and not CharacterLook._source_matches({"source": "res://assets/providers/other.glb", "source_bytes": 123}, "res://assets/providers/__absent__.glb"), ""])
	# Director: street-life drawables are kept out of the bay reflection pass.
	var pd := main.get_node_or_null("PerfDirector")
	var tagged := 0
	var untagged := 0
	var traffic := main.get_node_or_null("Traffic")
	if traffic != null:
		for g in traffic.find_children("*", "MeshInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if "Tree" in String(gi.name):
				continue
			if gi.layers & PerfDirector.NO_REFLECT_LAYER:
				tagged += 1
			elif gi.layers & 1:
				untagged += 1
	var rc := world.find_child("BayReflectionCamera", true, false) as Camera3D if world != null else null
	out.append(["perf-S: street-life meshes leave the bay reflection pass (main cameras still see them)",
		pd != null and tagged > 100 and untagged * 20 < tagged and (rc == null or (rc.cull_mask & PerfDirector.NO_REFLECT_LAYER) == 0)
		and (main.get_viewport().get_camera_3d() == null or (main.get_viewport().get_camera_3d().cull_mask & PerfDirector.NO_REFLECT_LAYER) != 0),
		"tagged=%d untagged=%d" % [tagged, untagged]])
	out.append_array(_wave_t(main))
	return out

## Wave T performance piece (CPU side, hitches).
static func _wave_t(main: Node) -> Array:
	var out: Array = []
	# Far walkers: deferred body motion is committed exactly, visual glide reset.
	var npc: NPC = null
	for n in main.get_tree().get_nodes_in_group("npcs"):
		if n is NPC and (n as NPC).body_root != null and (n as NPC).state != NPC.State.DEAD:
			npc = n
			break
	var ok_flush := false
	var detail := "no npc"
	if npc != null:
		var p0 := npc.global_position
		var base := npc.body_root.position
		npc._root_base = base
		npc._far_off = Vector3(0.3, 0.0, -0.2)
		npc.body_root.position = base + Vector3(0.3, 0.0, -0.2)
		npc._flush_far()
		var moved := npc.global_position - p0
		ok_flush = moved.distance_to(Vector3(0.3, 0.0, -0.2)) < 0.001 and npc.body_root.position.distance_to(base) < 0.0001 and npc._far_off == Vector3.ZERO
		detail = "moved=%s root=%s" % [str(moved.snapped(Vector3.ONE * 0.001)), str(npc.body_root.position)]
		npc.global_position = p0
	out.append(["perf-T: far walker deferred motion commits exactly and resets the visual glide", ok_flush, detail])
	var g_near := PerfBudget.far_glide_stride(20.0 * 20.0, true)
	var g_far := PerfBudget.far_glide_stride(100.0 * 100.0, true)
	var g_off := PerfBudget.far_glide_stride(20.0 * 20.0, false)
	out.append(["perf-T: far walkers glide every tick near the lens, strided far / off screen; idlers strided; near walkers full rate",
		g_near == 1 and g_far == 2 and g_off == NPC.SIM_FAR_TICKS and PerfBudget.IDLE_TICKS >= 2 and PerfBudget.IDLE_TICKS <= 6
		and PerfBudget.WALK_FULL_RATE_M >= 6.0, "glide %d/%d/%d idle=%d full=%.0f m" % [g_near, g_far, g_off, PerfBudget.IDLE_TICKS, PerfBudget.WALK_FULL_RATE_M]])
	# Compiled/exported GDScript has no source text. Exercise the actual
	# update/recycle paths, rather than treating a source substring as proof.
	out.append_array(_runtime_budget_checks(main))
	return out

class BareNPC extends NPC:
	func _ready() -> void:
		pass

class BareCar extends Car:
	func _ready() -> void:
		pass

class ProbeFx extends "res://src/actors/car_fx.gd":
	# Isolate probe scheduling from unrelated camera motion and input.
	func _update_camera(_delta: float) -> void:
		pass

class FailedCrowdSeeds extends CrowdDirector:
	var attempts := 0
	func _seed(_p: NPC, _hidden_only: bool, _loiter: bool) -> bool:
		attempts += 1
		return false

class FailedTrafficSeeds extends AmbientTraffic:
	var attempts := 0
	func _seed_vehicle(_v: AmbientVehicle, _hidden_only: bool) -> bool:
		attempts += 1
		return false

static func _runtime_budget_checks(main: Node) -> Array:
	var out: Array = []
	var holder := Node3D.new()
	main.add_child(holder)
	# The CPU phase cache must cover every moving boat and survive updates.
	# Dummy/headless RenderingServer returns zeroed MultiMesh custom data, so
	# GPU output checks are additional rendered coverage, never headless proof.
	var boats: Array[Dictionary] = [
		{"type": "launch", "half": Vector2(3.0, 1.0)},
		{"type": "launch", "half": Vector2(4.0, 1.2)},
		{"type": "launch", "half": Vector2(3.0, 1.0), "moored": true},
	]
	var wash := BoatWash.build(holder, boats)
	var drops: MultiMesh = wash._droplets["launch"]["mm"]
	var cached := wash._entries.size() == 2 and wash.sheets.instance_count == 2 and wash.churns.instance_count == 2 and drops.instance_count == 2 and not boats[2].has("wash")
	for i in 2:
		var entry: Dictionary = wash._entries[i]
		cached = cached and int(entry["slot"]) == i and int(entry["dslot"]) == i and int(boats[i].get("wash", -1)) == i
		cached = cached and entry.get("cd") == Color(0, i * 0.137, 0, 0) and entry.get("cc") == Color(0, i * 0.211, 0, 0) and entry.get("dc") == Color(0, i * 0.173, 0, 0)
		var before: Array = [entry.get("cd"), entry.get("cc"), entry.get("dc")]
		# Deliberately disagree with CPU seeds: an implementation that starts
		# reading its phase from the renderer will fail the rendered check.
		wash.sheets.set_instance_custom_data(i, Color(0, 0.91, 0, 0))
		wash.churns.set_instance_custom_data(i, Color(0, 0.91, 0, 0))
		drops.set_instance_custom_data(i, Color(0, 0.91, 0, 0))
		wash.update_boat(boats[i], Transform3D.IDENTITY, 3.5)
		wash.update_boat(boats[i], Transform3D.IDENTITY, 7.0)
		cached = cached and before == [entry.get("cd"), entry.get("cc"), entry.get("dc")]
		if DisplayServer.get_name() != "headless":
			var sheet := wash.sheets.get_instance_custom_data(i)
			var churn := wash.churns.get_instance_custom_data(i)
			var drop := drops.get_instance_custom_data(i)
			cached = cached and absf(sheet.g - i * 0.137) < 0.005 and absf(churn.g - i * 0.211) < 0.005 and absf(drop.g - i * 0.173) < 0.005 				and absf(sheet.r - 1.0) < 0.005 and absf(churn.r - 1.0) < 0.005 and absf(drop.b - 7.0) < 0.005
	# Run the inherited _process with a fixture car. The probe must remain
	# fixed before its deadline, relocate at it, then hold its new position.
	var car := BareCar.new()
	holder.add_child(car)
	car.set_physics_process(false)
	car.driver_is_player = true
	var fx := ProbeFx.new()
	holder.add_child(fx)
	fx.set_process(false)
	fx.car = car
	fx.camera = Camera3D.new()
	fx.add_child(fx.camera)
	fx._probe = ReflectionProbe.new()
	fx.add_child(fx._probe)
	fx._probe.position = Vector3(100, 100, 100)
	fx._probe_timer = 0.25
	var paused := Game.simulation_paused
	Game.simulation_paused = false
	fx._process(0.1)
	var held_before := fx._probe.position == Vector3(100, 100, 100)
	fx._process(0.16)
	var reset := fx._probe_timer
	var moved_to := fx._probe.global_position
	car.position = Vector3(20, 0, 0)
	fx._process(0.1)
	var held_after := fx._probe.global_position.is_equal_approx(moved_to)
	fx._process(reset)
	var moved_again := fx._probe.global_position.distance_to(moved_to) > 19.9
	Game.simulation_paused = paused
	var cadence := held_before and held_after and moved_again and reset >= 0.9 and is_equal_approx(reset, PerfBudget.CAR_PROBE_STEP)
	# Headless prewarm has an explicit no-GPU-allocation contract. On a
	# renderer, load-time prewarm must have produced usable shared RIDs.
	var shader_before := CarMotionBlur._s_shader
	var pipeline_before := CarMotionBlur._s_pipeline
	var state_before := CarMotionBlur._s_state
	CarMotionBlur.prewarm()
	var no_compute := DisplayServer.get_name() == "headless" or "--no-motion-blur" in OS.get_cmdline_user_args()
	var blur_ok := CarMotionBlur._s_state == state_before and CarMotionBlur._s_shader == shader_before and CarMotionBlur._s_pipeline == pipeline_before
	if no_compute:
		blur_ok = blur_ok and state_before in [0, -1] and not pipeline_before.is_valid() and not shader_before.is_valid()
	else:
		blur_ok = blur_ok and state_before == 1 and pipeline_before.is_valid() and shader_before.is_valid() and CarMotionBlur._s_sampler.is_valid()
	var shared_instances := 0
	if not no_compute:
		for vehicle in main.get_tree().get_nodes_in_group("vehicles"):
			var effects := vehicle.get_node_or_null("CarFx")
			var effect: CarMotionBlur = effects.get("motion_blur") if effects != null else null
			if effect != null:
				shared_instances += 1
				blur_ok = blur_ok and effect._shader == shader_before and effect._pipeline == pipeline_before
		blur_ok = blur_ok and shared_instances > 0
	var coverage := "GPU output/sharing NOT EXERCISED (headless or disabled); CPU cache/timer/prewarm no-allocation contract checked" if no_compute else "GPU output and shared shader/pipeline identities checked"
	out.append(["perf-T: wake CPU cache, probe cadence and renderer-aware prewarm contract",
		cached and cadence and blur_ok, "cache=%s probe=%s reset=%.2f prewarm=%s state=%d shared_instances=%d; %s" % [cached, cadence, reset, blur_ok, state_before, shared_instances, coverage]])
	var crowd := FailedCrowdSeeds.new()
	main.add_child(crowd)
	crowd.set_process(false)
	crowd._focus = Vector3(10000, 0, 10000)
	var traffic := FailedTrafficSeeds.new()
	holder.add_child(traffic)
	traffic.set_process(false)
	traffic.set_physics_process(false)
	for i in 10:
		var ped := BareNPC.new()
		holder.add_child(ped)
		ped.set_physics_process(false)
		crowd.roamers.append(ped)
		var vehicle := AmbientVehicle.new()
		vehicle.active = false
		traffic.vehicles.append(vehicle)
		holder.add_child(vehicle)
	crowd._recycle_pass(false)
	traffic._recycle(false)
	var first_crowd := crowd.attempts
	var first_traffic := traffic.attempts
	crowd._recycle_pass(false)
	traffic._recycle(false)
	out.append(["perf-T: failed seed attempts stop at each per-frame budget and retry next frame",
		first_crowd == PerfBudget.CROWD_SEED_FAILS and first_crowd >= 1 and first_crowd <= 3 		and first_traffic == PerfBudget.TRAFFIC_SEED_FAILS and first_traffic >= 1 and first_traffic <= 3 		and crowd.attempts == first_crowd * 2 and traffic.attempts == first_traffic * 2,
		"first crowd=%d traffic=%d; two frames crowd=%d traffic=%d" % [first_crowd, first_traffic, crowd.attempts, traffic.attempts]])
	crowd.free()
	holder.free()
	return out
