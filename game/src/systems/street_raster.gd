class_name StreetRaster
extends RefCounted
## downtown-life (wave S): where the live carriageways are, as a 2 m raster
## over the whole playable ground (legacy district + downtown Marina Bay).
##
## 0 = not a carriageway (pavement, plaza, park, building, water)
## 1 = carriageway between junctions (a pedestrian must never stand here)
## 2 = junction box or crossing mouth (pedestrians cross here on the walk phase)
##
## The legacy NPC rules (_pavement_return, _crossing_hold) only knew the 5 x 5
## district grid, so downtown walkers stood in live lanes and stepped off the
## kerb at any phase. Built lazily once (~40k cells written), queried in O(1).

const CELL := 1.0
const ORIGIN := Vector2(-920.0, -1080.0)
const W := 1720
const H := 1480
## Cells are carriageway when their centre is this far inside the kerb line
## (a walker at the kerb edge is on the pavement, not in the lane).
const KERB_TOLERANCE := 0.8
static var _grid := PackedByteArray()
static var _built := false

static func _ensure() -> void:
	if _built:
		return
	_built = true
	_grid.resize(W * H)
	_grid.fill(0)
	# Legacy district carriageways (16 m) and their junction boxes.
	for x: float in DowntownPlan.LEGACY["x_lines"]:
		_stamp_seg(Vector2(x, -380.0), Vector2(x, 380.0), WorldBuilder.ROAD_HALF, 1)
	for z: float in DowntownPlan.LEGACY["z_lines"]:
		_stamp_seg(Vector2(-380.0, z), Vector2(380.0, z), WorldBuilder.ROAD_HALF, 1)
	# Downtown roads (carriageway = plan width) and vehicle bridges.
	for key: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key]
		var pts: Array = road["pts"]
		var hw := float(road["width"]) * 0.5
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			_stamp_seg(Vector2(a.x, a.z), Vector2(b.x, b.z), hw, 1)
	for key2: String in DowntownPlan.BRIDGES:
		var br: Dictionary = DowntownPlan.BRIDGES[key2]
		if String(br.get("kind", "")) != "vehicle":
			continue
		var f: Vector3 = br["from"]
		var t: Vector3 = br["to"]
		_stamp_seg(Vector2(f.x, f.z), Vector2(t.x, t.z), int(br.get("lanes", 1)) * 3.5 + 0.6, 1)
	# Junction boxes: legacy crossings and every downtown crossing / T.
	for x: float in DowntownPlan.LEGACY["x_lines"]:
		for z: float in DowntownPlan.LEGACY["z_lines"]:
			_stamp_box(Vector2(x, z), WorldBuilder.ROAD_HALF + 4.5)
	var Roads := load("res://src/world/downtown/roads.gd")
	for j: Dictionary in Roads.junctions():
		var p: Vector3 = j["pos"]
		_stamp_box(Vector2(p.x, p.z), float(j["r"]) + 4.0)

static func _idx(x: float, z: float) -> int:
	var cx := int(floor((x - ORIGIN.x) / CELL))
	var cz := int(floor((z - ORIGIN.y) / CELL))
	if cx < 0 or cz < 0 or cx >= W or cz >= H:
		return -1
	return cz * W + cx

static func _stamp_seg(a: Vector2, b: Vector2, hw: float, v: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(hw, hw)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(hw, hw)
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	var x := lo.x + CELL * 0.5
	while x < hi.x:
		var z := lo.y + CELL * 0.5
		while z < hi.y:
			var p := Vector2(x, z)
			var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			if p.distance_to(a + ab * t) < hw - KERB_TOLERANCE:
				var i := _idx(x, z)
				if i >= 0 and _grid[i] < v:
					_grid[i] = v
			z += CELL
		x += CELL

## Junction mouths become crossing cells (only where a road already is).
static func _stamp_box(c: Vector2, r: float) -> void:
	var x := c.x - r + CELL * 0.5
	while x < c.x + r:
		var z := c.y - r + CELL * 0.5
		while z < c.y + r:
			var i := _idx(x, z)
			if i >= 0 and _grid[i] == 1:
				_grid[i] = 2
			z += CELL
		x += CELL

## 0 off-road, 1 carriageway, 2 junction box / crossing mouth.
static func at(x: float, z: float) -> int:
	_ensure()
	var i := _idx(x, z)
	return 0 if i < 0 else _grid[i]

static func on_carriageway(x: float, z: float) -> bool:
	return at(x, z) != 0

## Nearest point off the carriageway (searching the four axes, then the
## diagonals, out to `reach` m), pushed `margin` m onto the pavement; INF if
## none is found.
static func kerb_point(p: Vector3, reach: float = 16.0, margin: float = 1.2) -> Vector3:
	_ensure()
	var best := Vector3.INF
	var best_d := INF
	for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
			Vector3(0.7071, 0, 0.7071), Vector3(-0.7071, 0, 0.7071), Vector3(0.7071, 0, -0.7071), Vector3(-0.7071, 0, -0.7071)]:
		var s := 1.0
		while s <= reach and s < best_d:
			var q := p + d * s
			if at(q.x, q.z) == 0:
				if s < best_d:
					best_d = s
					best = p + d * (s + margin)
				break
			s += 1.0
	return best
