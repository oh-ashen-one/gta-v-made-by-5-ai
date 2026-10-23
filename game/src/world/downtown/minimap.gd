extends RefCounted
## downtown-map: minimap layer for the Marina Bay downtown (HUD._draw_minimap).
## Draws land, the bay / river / channel water, plots, downtown roads and
## bridges and promenades from DowntownPlan, under the legacy district layer.

const Shoreline := preload("res://src/world/downtown/shoreline.gd")
const LAND := Color(0.15, 0.16, 0.17, 0.9)
const WATER := Color(0.16, 0.31, 0.36, 0.9)
const PLOT := Color(0.21, 0.22, 0.24, 0.9)
const PARK := Color(0.18, 0.27, 0.18, 0.9)
const ROAD := Color(0.36, 0.38, 0.41, 0.95)
const ARTERIAL := Color(0.50, 0.50, 0.46, 0.95)
const WALK := Color(0.40, 0.39, 0.35, 0.85)

static func _rect(canvas: Control, to_map: Callable, r: Rect2, scale: float, color: Color) -> void:
	canvas.draw_rect(Rect2(to_map.call(Vector3(r.position.x, 0, r.position.y)), r.size * scale), color, true)

static func draw(canvas: Control, to_map: Callable, scale: float) -> void:
	_rect(canvas, to_map, Shoreline.OUTER, scale, LAND)
	for wr: Rect2 in Shoreline.water_rects():
		_rect(canvas, to_map, wr, scale, WATER)
	for key: String in DowntownPlan.ISLANDS:
		_rect(canvas, to_map, DowntownPlan.ISLANDS[key], scale, LAND)
	for key2: String in DowntownPlan.BLOCKS:
		var blk: Dictionary = DowntownPlan.BLOCKS[key2]
		var park := String(blk["kind"]) == "park" or key2 in ["gardens_site", "civic_padang"]
		_rect(canvas, to_map, blk["rect"], scale, PARK if park else PLOT)
	for key3: String in DowntownPlan.PROMENADES:
		var w: Dictionary = DowntownPlan.PROMENADES[key3]
		var pts: Array = w["pts"]
		for i in pts.size() - 1:
			canvas.draw_line(to_map.call(pts[i]), to_map.call(pts[i + 1]), WALK, maxf(2.0, float(w["width"]) * scale * 0.6))
	for key4: String in DowntownPlan.ROADS:
		var road: Dictionary = DowntownPlan.ROADS[key4]
		var pts2: Array = road["pts"]
		var col := ARTERIAL if String(road["kind"]) == "arterial" else ROAD
		for j in pts2.size() - 1:
			canvas.draw_line(to_map.call(pts2[j]), to_map.call(pts2[j + 1]), col, maxf(2.0, float(road["width"]) * scale * 0.8))
	for key5: String in DowntownPlan.BRIDGES:
		var b: Dictionary = DowntownPlan.BRIDGES[key5]
		var col2 := ARTERIAL if String(b["kind"]) == "vehicle" else WALK
		canvas.draw_line(to_map.call(b["from"]), to_map.call(b["to"]), col2, maxf(2.0, float(b["width"]) * scale * 0.8))
