class_name PerfDirector
extends Node
## Wave S performance piece: runtime rendering budgets that sit beside the
## systems they budget (no behaviour of theirs changes).
##
## 1. Bay reflection pass: the planar-reflection camera re-rendered the whole
##    city (people, cars, street props) plus its own sun shadow cascades,
##    ~5,900 extra draw calls in aerial views. Street-life drawables and small
##    street props move to NO_REFLECT_LAYER, which the main cameras still see
##    and the reflection camera does not (at half resolution under the wave
##    normal they were never readable in the water).
## 2. Car shadows by distance: a car body costs 10-28 k triangles in up to four
##    shadow cascades. Within CAR_SHADOW_NEAR the real meshes cast; out to
##    CAR_SHADOW_FAR one shadows-only box (12 triangles) shaped to the body
##    casts instead; beyond that the shadow is sub-pixel and nothing casts.
## 3. Small static props (planters, bins, bollards, AC units, stalls, shrubs):
##    each 160 m batch draws to PROP_DRAW_M and casts sun shadows only within
##    PROP_SHADOW_M of the camera.
## `--perf-off` disables the director (A/B captures).

const NO_REFLECT_LAYER := 1 << 15   # street life + small props: not in the bay mirror or car probes
const INLAND_LAYER := 1 << 14       # tall inland static geometry: not in the bay mirror only
const CAR_SHADOW_NEAR := 60.0
const CAR_SHADOW_FAR := 220.0
const PROP_DRAW_M := 300.0
const PROP_SHADOW_M := 100.0
const SMALL_PROP_M := 3.5
const PROP_PREFIXES := ["StaticBatch", "StreetDressing", "NearfieldProps", "NearfieldShrub", "NearfieldAwning", "NearfieldKerb"]
const TICK := 0.2

var main: Node
var enabled := true
var stats := {"no_reflect": 0, "small_prop_batches": 0, "cars": 0, "car_proxies_on": 0, "car_real_on": 0}
var _traffic: Node
var _props: Array = []        # [GeometryInstance3D, original cast_shadow, AABB]
var _cars: Dictionary = {}    # instance id -> {node, casters: [[gi, setting]], proxy, mode}
var _acc := 0.0
var _box: BoxMesh
var _reflection_cam: Camera3D

## Wave T: the first ReflectionProbe render (the player car's moving probe)
## allocated the reflection atlas and compiled the probe-pass pipelines inside
## the car-entry frames (two ~105 ms frames in the rendered route). One probe
## with the car probe's settings renders its faces at the start position while
## the title / first gameplay seconds play, then is freed.
const WARM_PROBE_SECONDS := 2.5
func _warm_probe(m: Node) -> void:
	if DisplayServer.get_name() == "headless" or "--no-car-probe" in OS.get_cmdline_user_args():
		return
	var p := ReflectionProbe.new()
	p.name = "PerfWarmProbe"
	p.update_mode = ReflectionProbe.UPDATE_ONCE
	p.size = Vector3(90.0, 40.0, 90.0)
	p.origin_offset = Vector3(0.0, 1.2, 0.0)
	p.max_distance = 160.0
	p.box_projection = false
	p.enable_shadows = false
	p.mesh_lod_threshold = 12.0
	p.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	p.intensity = 0.0
	p.cull_mask = 0xFFFFF & ~(1 << 19) & ~NO_REFLECT_LAYER
	m.add_child(p)
	var start: Variant = m.world.locations.get("player_start", Vector3.ZERO) if m.world != null else Vector3.ZERO
	p.global_position = (start as Vector3) + Vector3(0.0, 1.4, 0.0)
	get_tree().create_timer(WARM_PROBE_SECONDS, true).timeout.connect(p.queue_free)

func _exit_tree() -> void:
	CarMotionBlur.release_shared()

static func off() -> bool:
	return "--perf-off" in OS.get_cmdline_user_args()

func setup(m: Node) -> void:
	main = m
	name = "PerfDirector"
	# Wave T: compile the car-camera motion blur while loading, not on entry.
	CarMotionBlur.prewarm()
	_warm_probe(m)
	if HitchMonitor.path_arg() != "":
		var hm := HitchMonitor.new()
		m.add_child(hm)
		hm.setup(HitchMonitor.path_arg())
	if off():
		enabled = false
		print("[perf] director disabled (--perf-off)")
		return
	_traffic = m.traffic
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_tag_no_reflect(_traffic)
	get_tree().node_added.connect(_on_node_added)
	_tree_lod(m)
	var district: Node = m.world.get_node_or_null("District")
	if district != null:
		_small_props(district)
		_far_from_water(district)
	_reflection_cam = m.world.find_child("BayReflectionCamera", true, false) as Camera3D
	if _reflection_cam != null:
		_reflection_cam.cull_mask &= ~(NO_REFLECT_LAYER | INLAND_LAYER)
	# After BayWater._process, which re-copies the main camera's near plane.
	process_priority = 1000
	print("[perf] director: ", JSON.stringify(stats))

# ---------------------------------------------------------------- reflection
static func _reflectable(gi: GeometryInstance3D) -> bool:
	# Avenue trees stay in the water's mirror image.
	return "Tree" in String(gi.name)

func _tag(gi: GeometryInstance3D) -> void:
	if _reflectable(gi) or (gi.layers & 1) == 0:
		return
	gi.layers = (gi.layers & ~1) | NO_REFLECT_LAYER
	stats["no_reflect"] += 1

func _tag_no_reflect(root: Node) -> void:
	if root == null:
		return
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		_tag(n as GeometryInstance3D)

func _on_node_added(n: Node) -> void:
	if n is ReflectionProbe:
		# The player car's moving probe mirrors buildings, trees and sky; the
		# crowd and street props were sub-pixel in the paint.
		(n as ReflectionProbe).cull_mask &= ~NO_REFLECT_LAYER
		return
	if n is GeometryInstance3D and _traffic != null and is_instance_valid(_traffic) and _traffic.is_ancestor_of(n):
		_tag(n as GeometryInstance3D)

## Legacy-district geometry far from the bay that is too low ever to show in
## it (top below REFLECT_SLOPE x its distance from the bay rectangle) leaves
## the reflection pass. Downtown, bay, skyline and landmark nodes are kept:
## they line the water.
const REFLECT_SLOPE := 0.3
const REFLECT_KEEP := ["Downtown", "Bay", "Skyline", "Horizon", "Background", "Landmark", "marina", "supertree", "singapore_flyer", "merlion", "artscience"]

static func _bay_distance(bb: AABB) -> float:
	var dx := maxf(0.0, maxf(-900.0 - bb.end.x, bb.position.x - 900.0))
	var dz := maxf(0.0, maxf(BayWater.FAR_SHORE_Z - bb.end.z, bb.position.z - BayWater.NEAR_SHORE_Z))
	return sqrt(dx * dx + dz * dz)

func _far_from_water(district: Node) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var n := 0
	for c in district.get_children():
		var cn := String(c.name)
		var keep := false
		for k: String in REFLECT_KEEP:
			if cn.findn(k) >= 0:
				keep = true
				break
		if keep:
			continue
		var nodes: Array = [c] if c is GeometryInstance3D else c.find_children("*", "GeometryInstance3D", true, false)
		for g in nodes:
			var gi := g as GeometryInstance3D
			if (gi.layers & 1) == 0:
				continue
			var bb: AABB = gi.global_transform * gi.get_aabb()
			var d := _bay_distance(bb)
			# Flat ground (roads, pavements, kerbs) keeps layer 1: tyre-mark and
			# contact-shadow decals project onto layer 1 only.
			if d > 60.0 and bb.end.y < REFLECT_SLOPE * d and bb.size.y >= 2.5:
				gi.layers = (gi.layers & ~1) | INLAND_LAYER
				n += 1
	stats["far_from_water"] = n

## The mirrored camera only needs what lies beyond the nearest visible WATER
## point: a reflection seen at water point W is the mirror image of something
## deeper along the same ray, so geometry nearer than the nearest visible
## water can never appear in it. Rays are sampled across the screen (plus rows
## hugging the horizon, where distant water is a thin band) and only plane hits
## that are water (downtown Shoreline map, else the legacy bay) count. With no
## water sampled the mirror pass draws nothing but sky.
var _shore: Script = null
var _shore_checked := false
var _near_cache := -1.0
var _near_frame := -1

func _is_water(x: float, z: float) -> bool:
	if not _shore_checked:
		_shore_checked = true
		var sp := "res://src/world/downtown/shoreline.gd"
		if ResourceLoader.exists(sp):
			_shore = load(sp)
	if _shore != null:
		return _shore.is_water_ext(x, z)
	return x > -900.0 and x < 900.0 and z > BayWater.FAR_SHORE_Z and z < BayWater.NEAR_SHORE_Z

func _clip_reflection_near(cam: Camera3D) -> void:
	if _reflection_cam == null or not is_instance_valid(_reflection_cam):
		return
	var frame := Engine.get_process_frames()
	if _near_frame >= 0 and frame - _near_frame < 2 and _near_cache > 0.0:
		_reflection_cam.near = maxf(_reflection_cam.near, _near_cache)
		return
	_near_frame = frame
	var level := BayWater.LEVEL
	var o := cam.global_position
	if o.y <= level + 0.5:
		_near_cache = -1.0
		return
	var fwd := -cam.global_basis.z
	var size := get_viewport().get_visible_rect().size
	var rows: Array[float] = [0.55, 0.65, 0.75, 0.85, 0.95, 1.0]
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() > 0.01 and not cam.is_position_behind(o + flat.normalized() * 5000.0):
		var hv := cam.unproject_position(Vector3(o.x, level, o.z) + flat.normalized() * 5000.0).y / size.y
		for dpx in [2.0, 5.0, 10.0, 20.0, 40.0, 80.0, 160.0]:
			rows.append(hv + dpx / size.y)
	var best := INF
	var far_lim := cam.far
	for v in rows:
		if v < 0.0 or v > 1.0:
			continue
		for i in 13:
			var dir := cam.project_ray_normal(Vector2(size.x * i / 12.0, size.y * v))
			if dir.y >= -0.00001:
				continue
			var t := (level - o.y) / dir.y
			if t > far_lim:
				continue
			var hit := o + dir * t
			if not _is_water(hit.x, hit.z):
				continue
			best = minf(best, t * dir.dot(fwd))
	_near_cache = (best * 0.97 - 2.0) if best < INF else far_lim * 0.98
	_reflection_cam.near = maxf(cam.near, _near_cache)

func _tree_lod(m: Node) -> void:
	var n := 0
	for g in m.find_children("*", "GeometryInstance3D", true, false):
		var mesh: Mesh = null
		if g is MultiMeshInstance3D and g.multimesh != null:
			mesh = g.multimesh.mesh
		elif g is MeshInstance3D:
			mesh = g.mesh
		if mesh != null and "rain_tree" in mesh.resource_path:
			(g as GeometryInstance3D).lod_bias = PerfBudget.TREE_LOD_BIAS
			n += 1
	stats["tree_lod_biased"] = n

# ---------------------------------------------------------------- props
static func _is_tree(mmi: MultiMeshInstance3D) -> bool:
	var mesh := mmi.multimesh.mesh if mmi.multimesh != null else null
	var p := mesh.resource_path if mesh != null else ""
	var nm := String(mmi.name)
	return "rain_tree" in p or "palm" in p or "fern" in p or "rain_tree" in nm or "palm" in nm or "fern" in nm

## Largest world extent of one instance of the batch (0 when unknown).
static func _max_instance_extent(mmi: MultiMeshInstance3D) -> float:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or mm.instance_count == 0:
		return 0.0
	var size := mm.mesh.get_aabb().size
	var best := 0.0
	for i in mm.instance_count:
		var s := mm.get_instance_transform(i).basis.get_scale()
		best = maxf(best, maxf(size.x * s.x, maxf(size.y * s.y, size.z * s.z)))
	return best

func _small_props(district: Node) -> void:
	# The dummy (headless) renderer keeps no MultiMesh transforms, so sizes are
	# only known in rendered runs; headless runs skip (nothing is drawn there).
	var headless := DisplayServer.get_name() == "headless"
	for c in district.get_children():
		if not c is MultiMeshInstance3D:
			continue
		var mmi := c as MultiMeshInstance3D
		var nm := String(mmi.name)
		var match_prefix := false
		for pre: String in PROP_PREFIXES:
			if nm.begins_with(pre):
				match_prefix = true
				break
		if not match_prefix or _is_tree(mmi) or mmi.visibility_range_end > 0.0 and mmi.visibility_range_end < PROP_DRAW_M:
			if match_prefix and not _is_tree(mmi):
				_register_prop(mmi)
			continue
		if headless:
			continue
		var ext := _max_instance_extent(mmi)
		if ext <= 0.0 or ext > SMALL_PROP_M:
			continue
		mmi.visibility_range_end = PROP_DRAW_M
		mmi.visibility_range_end_margin = 30.0
		_register_prop(mmi)

func _register_prop(gi: GeometryInstance3D) -> void:
	stats["small_prop_batches"] += 1
	_tag(gi)
	if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_props.append([gi, gi.cast_shadow, gi.global_transform * gi.get_aabb()])

# ---------------------------------------------------------------- cars
func _car_nodes() -> Array:
	var out: Array = []
	for c in _traffic.get_children():
		if c is Car:
			out.append(c)
	var amb = _traffic.get("ambient")
	if amb != null and is_instance_valid(amb):
		for v in amb.vehicles:
			if is_instance_valid(v):
				out.append(v)
	return out

func _register_car(car: Node3D) -> Dictionary:
	var casters: Array = []
	var box := AABB()
	var first := true
	var inv := car.global_transform.affine_inverse()
	for n in car.find_children("*", "MeshInstance3D", true, false):
		var gi := n as MeshInstance3D
		if gi.mesh == null or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			continue
		casters.append([gi, gi.cast_shadow])
		if not gi.is_visible_in_tree():
			continue
		var local: AABB = (inv * gi.global_transform) * gi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	var entry := {"node": car, "casters": casters, "proxy": null, "mode": -1}
	if not first and box.size.y > 0.5:
		var proxy := MeshInstance3D.new()
		proxy.name = "PerfShadowProxy"
		proxy.mesh = _box
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var y0 := box.position.y + box.size.y * 0.22
		var y1 := box.end.y - box.size.y * 0.06
		proxy.transform = Transform3D(Basis.from_scale(Vector3(box.size.x * 0.9, y1 - y0, box.size.z * 0.92)),
			Vector3(box.get_center().x, (y0 + y1) * 0.5, box.get_center().z))
		proxy.visible = false
		car.add_child(proxy)
		entry["proxy"] = proxy
	stats["cars"] += 1
	return entry

## 0 = real shadows, 1 = proxy box, 2 = none.
func _set_car_mode(e: Dictionary, mode: int) -> void:
	if int(e["mode"]) == mode:
		return
	e["mode"] = mode
	for pair in e["casters"]:
		var gi: GeometryInstance3D = pair[0]
		if is_instance_valid(gi):
			gi.cast_shadow = pair[1] if mode == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proxy: MeshInstance3D = e["proxy"]
	if proxy != null and is_instance_valid(proxy):
		proxy.visible = mode == 1

## A/B switch for --render-budget: off restores every original setting.
func set_active(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if not on:
		for e in _cars.values():
			_set_car_mode(e, 0)
		for p in _props:
			if is_instance_valid(p[0]):
				(p[0] as GeometryInstance3D).cast_shadow = p[1]
	var rc := main.world.find_child("BayReflectionCamera", true, false) as Camera3D
	if rc != null:
		rc.cull_mask = (rc.cull_mask & ~(NO_REFLECT_LAYER | INLAND_LAYER)) if on else (rc.cull_mask | NO_REFLECT_LAYER | INLAND_LAYER)

func _process(delta: float) -> void:
	if not enabled:
		return
	var view_cam := get_viewport().get_camera_3d()
	if view_cam != null and view_cam != _reflection_cam:
		_clip_reflection_near(view_cam)
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	# props
	for p in _props:
		var gi: GeometryInstance3D = p[0]
		if not is_instance_valid(gi):
			continue
		var bb: AABB = p[2]
		var closest := cp.clamp(bb.position, bb.end)
		var want: int = p[1] if closest.distance_to(cp) < PROP_SHADOW_M else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if gi.cast_shadow != want:
			gi.cast_shadow = want
	# cars
	var seen := {}
	var real := 0
	var prox := 0
	for car in _car_nodes():
		var id: int = car.get_instance_id()
		seen[id] = true
		if not _cars.has(id):
			_cars[id] = _register_car(car)
		var e: Dictionary = _cars[id]
		var d: float = (car as Node3D).global_position.distance_to(cp)
		var mode := 0 if d < CAR_SHADOW_NEAR else (1 if d < CAR_SHADOW_FAR else 2)
		_set_car_mode(e, mode)
		if mode == 0: real += 1
		elif mode == 1: prox += 1
	for id in _cars.keys():
		if not seen.has(id):
			_cars.erase(id)
	stats["car_real_on"] = real
	stats["car_proxies_on"] = prox
