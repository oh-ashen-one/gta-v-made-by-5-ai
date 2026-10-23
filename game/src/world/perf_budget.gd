class_name PerfBudget
extends RefCounted
## Wave S performance piece: project-wide rendering budgets and helpers.
## Systems that spawn many drawables (street-life people and lane cars, avenue
## dressing, downtown blocks, trees) read their draw distances and batching
## cells from here instead of hard-coding them, so one file sets the cost.
## Behaviour stays in the owning systems; this only says how far and how
## batched things are drawn, and builds the occlusion culling volumes.

## Tree MultiMesh batching cell (m): small enough to frustum-cull and pick a
## distance LOD per cell, big enough to keep the draw count low.
const TREE_CELL_M := 200.0

## Rain-tree canopies (32 k triangles at LOD 0) pick their generated LODs at
## this bias (< 1 = coarser sooner); near trees stay at full detail.
const TREE_LOD_BIAS := 0.6

## Pedestrians: drawn to this distance (m); sun shadows only inside the near
## distance. Lane cars: whole car to CAR_DRAW_M, small parts to CAR_PARTS_M.
const PEOPLE_DRAW_M := 160.0
const PEOPLE_SHADOW_M := 45.0
const CAR_DRAW_M := 380.0
const CAR_PARTS_M := 120.0
## Parked cars: whole car to this distance, shadows only near.
const PARKED_CAR_DRAW_M := 320.0
const PARKED_CAR_SHADOW_M := 90.0

## Crowd animation strides (frames between pose updates, summed delta):
## every frame within PEOPLE_ANIM_NEAR_M, MID beyond, FAR past
## PEOPLE_ANIM_FAR_M, OFFSCREEN when outside the camera frustum (the pose still
## advances, so a figure turning into view is mid-stride, not frozen).
const PEOPLE_ANIM_NEAR_M := 35.0
const PEOPLE_ANIM_FAR_M := 80.0
const PEOPLE_STRIDE_MID := 3
const PEOPLE_STRIDE_FAR := 6
const PEOPLE_STRIDE_OFFSCREEN := 15

static func people_anim_stride(dist_sq: float, on_screen: bool) -> int:
	if not on_screen:
		return PEOPLE_STRIDE_OFFSCREEN
	if dist_sq < PEOPLE_ANIM_NEAR_M * PEOPLE_ANIM_NEAR_M:
		return 1
	if dist_sq < PEOPLE_ANIM_FAR_M * PEOPLE_ANIM_FAR_M:
		return PEOPLE_STRIDE_MID
	return PEOPLE_STRIDE_FAR

## Occluder volumes are inset from the visible shell and start above the
## street band so arcades, lobbies and void decks stay see-through.
const OCCLUDER_INSET_M := 0.6
const OCCLUDER_MIN_SIZE_M := 6.0

## Groups Array[Transform3D] (or any Transform3D Array) into per-cell lists.
static func cell_groups(transforms: Array, cell: float) -> Array:
	var by_cell := {}
	var order: Array = []
	for xf in transforms:
		var o: Vector3 = (xf as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not by_cell.has(key):
			by_cell[key] = []
			order.append(key)
		by_cell[key].append(xf)
	var out: Array = []
	for key in order:
		out.append(by_cell[key])
	return out

# ------------------------------------------------------------- load laps
static var _laps: Array = []
static var _lap_t := -1

## Load-time attribution: `lap(name)` records the ms since the previous lap.
static func lap(name: String) -> void:
	var now := Time.get_ticks_msec()
	if _lap_t >= 0:
		_laps.append([name, now - _lap_t])
	_lap_t = now

## Prints and clears the laps (largest first), e.g. at world_ui_ready.
static func report_laps(tag: String) -> void:
	var sorted := _laps.duplicate()
	sorted.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var parts: Array[String] = []
	for l in sorted:
		parts.append("%s=%d" % [l[0], l[1]])
	print("[perf] load laps (", tag, "): ", " ".join(parts))
	_laps.clear()

static func occlusion_enabled() -> bool:
	return bool(ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false)) \
		and not ("--no-occluders" in OS.get_cmdline_user_args())

# ------------------------------------------------------------- occluders
## Collected building volumes: [size: Vector3, centre: Vector3, yaw: float].
static var _occluder_boxes: Array = []

## Registers a solid building volume (axis-aligned in its own yaw frame) as an
## occluder candidate. `street_band` is the height above `ground_y` kept open
## (arcades, lobbies, void decks). Callers pass the building's real envelope;
## the inset keeps the occluder strictly inside the visible geometry.
static func add_building_volume(size: Vector3, centre: Vector3, yaw: float = 0.0, ground_y: float = 0.0, street_band: float = 4.0) -> void:
	var bottom := maxf(centre.y - size.y * 0.5, ground_y + street_band)
	var top := centre.y + size.y * 0.5 - OCCLUDER_INSET_M
	var w := size.x - OCCLUDER_INSET_M * 2.0
	var d := size.z - OCCLUDER_INSET_M * 2.0
	if top - bottom < OCCLUDER_MIN_SIZE_M * 0.5 or w < OCCLUDER_MIN_SIZE_M or d < OCCLUDER_MIN_SIZE_M:
		return
	_occluder_boxes.append([Vector3(w, top - bottom, d), Vector3(centre.x, (top + bottom) * 0.5, centre.z), yaw])

## Largest axis-aligned rectangle (shrunk about the bounds centre) whose
## corners and edge midpoints all lie inside `poly`; Rect2() when none.
static func inscribed_rect(poly: PackedVector2Array) -> Rect2:
	if poly.size() < 3:
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var c := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	var s := 1.0
	while s > 0.3:
		var h := half * s
		var ok := true
		for t in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
			# 0.999: points exactly on an edge count as inside.
			if not Geometry2D.is_point_in_polygon(c + h * t * 0.999, poly):
				ok = false
				break
		if ok:
			return Rect2(c - h, h * 2.0)
		s -= 0.05
	return Rect2()

## Registers an extruded footprint (downtown MeshKit prisms) as a candidate.
static func add_prism(poly: PackedVector2Array, y0: float, y_top_min: float, ground_y: float, street_band: float) -> void:
	var r := inscribed_rect(poly)
	if r.size.x <= 0.0:
		return
	add_building_volume(Vector3(r.size.x, y_top_min - y0, r.size.y), Vector3(r.get_center().x, (y0 + y_top_min) * 0.5, r.get_center().y), 0.0, ground_y, street_band)

## Registers the merged world AABB of a building node's meshes (e.g. the HDB
## slab module), shrunk by `shrink` of its width/depth so balconies and
## recesses stay outside the occluder.
static func add_node_aabb(node: Node3D, shrink: float = 0.12, street_band: float = 6.0) -> void:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var size := Vector3(box.size.x * (1.0 - shrink), box.size.y, box.size.z * (1.0 - shrink))
	add_building_volume(size, box.get_center(), 0.0, box.position.y, street_band)

static func occluder_count() -> int:
	return _occluder_boxes.size()

## Builds OccluderInstance3D nodes (BoxOccluder3D) under `parent` for every
## registered volume and clears the list. Returns how many were built.
static func build_occluders(parent: Node3D) -> int:
	var n := 0
	if not occlusion_enabled():
		_occluder_boxes.clear()
		return 0
	var holder := Node3D.new()
	holder.name = "PerfOccluders"
	parent.add_child(holder)
	for b in _occluder_boxes:
		var occ := BoxOccluder3D.new()
		occ.size = b[0]
		var oi := OccluderInstance3D.new()
		oi.occluder = occ
		oi.position = b[1]
		oi.rotation.y = float(b[2])
		holder.add_child(oi)
		n += 1
	_occluder_boxes.clear()
	print("[perf] occluders built: ", n)
	return n
