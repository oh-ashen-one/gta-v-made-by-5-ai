extends RefCounted
## downtown-landmarks piece entry (wave M, loop/DOWNTOWN_PLAN.md sections 9 and 13).
##
## Builds the full-scale, reachable Marina Bay landmarks at their plan anchors
## and takes over the legacy far-shore landmark section. Every module lives in
## res://src/world/downtown/landmarks/ and reads its numbers from DowntownPlan.
## Modules are loaded guarded, so one failing module never takes the city down.

const MODULES := [
	"res://src/world/downtown/landmarks/interim_ground.gd",
	"res://src/world/downtown/landmarks/mbs.gd",
	"res://src/world/downtown/landmarks/helix.gd",
	"res://src/world/downtown/landmarks/artscience.gd",
	"res://src/world/downtown/landmarks/esplanade.gd",
	"res://src/world/downtown/landmarks/flyer.gd",
	"res://src/world/downtown/landmarks/gardens.gd",
	"res://src/world/downtown/landmarks/fullerton.gd",
]

## Footprints this piece builds on; procedural background towers are kept out.
const SITES := ["fullerton_site", "esplanade_site", "flyer_site", "mbs_site", "gardens_site"]

var report := {}

## A/B debug switch: `--landmarks-off` builds the legacy far shore instead
## (before/after sightline probes and perf comparisons).
static func disabled() -> bool:
	return "--landmarks-off" in OS.get_cmdline_user_args()

func replaces() -> PackedStringArray:
	if disabled():
		return PackedStringArray()
	# While downtown-map is absent the legacy far-shore slab (which fills the
	# east channel under the Helix) is swapped for interim_ground.gd.
	if not ResourceLoader.exists("res://src/world/downtown/map.gd"):
		return PackedStringArray(["far_shore_landmarks", "far_shore_ground"])
	return PackedStringArray(["far_shore_landmarks"])

func skyline_clear(world: WorldBuilder, city: SkylineCity) -> void:
	if disabled():
		return
	var rects: Array[Rect2] = []
	for key: String in SITES:
		rects.append(DowntownPlan.block_rect(key).grow(6.0))
	for key: String in ["artscience_promontory", "fullerton_peninsula", "ns_square_float"]:
		rects.append((DowntownPlan.ISLANDS[key] as Rect2).grow(6.0))
	# Nothing stands in the water, and the Helix corridor stays open.
	for key: String in DowntownPlan.WATER:
		rects.append(DowntownPlan.WATER[key] as Rect2)
	rects.append(Rect2(-560.0, -800.0, 310.0, 110.0))
	# Bayfront Avenue strip between the MBS towers and the Gardens.
	rects.append(Rect2(-330.0, -800.0, 730.0, 40.0))
	for r in rects:
		city.clear_zone(r, 0.0)
	# Towers placed before this hook ran (near flank rows) are dropped too, so
	# no procedural tower stands inside a landmark.
	var dropped := 0
	var groups = city.get("_groups")
	if groups is Array:
		for g in groups:
			if not g is Array:
				continue
			for i in range((g as Array).size() - 1, -1, -1):
				var entry = g[i]
				if not entry is Array or (entry as Array).is_empty() or not entry[0] is Transform3D:
					continue
				var o: Vector3 = (entry[0] as Transform3D).origin
				for r in rects:
					if r.has_point(Vector2(o.x, o.z)):
						g.remove_at(i)
						dropped += 1
						break
	report["skyline_dropped"] = dropped
	city.placed = maxi(0, city.placed - dropped)

## Integration (wave M): the landmark site decks stand at 0.34-0.36 m, built
## for the plan's 0.3 m quay ground, but downtown-map lays the land at 0 with
## 0.06 m roads and 0.10 m footways and walks. The player capsule has no
## step-up, so every land edge of a raised deck was a lip that stopped a walk
## onto the Marina Bay side. Each land side gets a 1.6 m granite edge ramp
## with walkable collision (water sides keep their seawall).
const RAISED_DECKS := {"esplanade_site": 0.36, "flyer_site": 0.36, "fullerton_site": 0.36, "gardens_site": 0.34}
const EDGE_RAMP := 1.6

func _edge_ramps(holder: Node3D) -> int:
	const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
	const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
	var kit := Kit.new(holder, "LandmarkEdgeRampCollision")
	var mat := Looks.get_mat("granite_paving")
	var rects := {}
	for key: String in RAISED_DECKS:
		rects[key] = [DowntownPlan.block_rect(key), float(RAISED_DECKS[key])]
	rects["fullerton_peninsula"] = [DowntownPlan.ISLANDS["fullerton_peninsula"] as Rect2, 0.36]
	for key: String in rects:
		var r: Rect2 = rects[key][0]
		var top: float = rects[key][1]
		var c := r.get_center()
		var sides := [[Vector2(-1, 0), r.size.y], [Vector2(1, 0), r.size.y], [Vector2(0, -1), r.size.x], [Vector2(0, 1), r.size.x]]
		for sd: Array in sides:
			var n: Vector2 = sd[0]
			var length: float = sd[1]
			var edge := c + Vector2(n.x * r.size.x * 0.5, n.y * r.size.y * 0.5)
			var probe := edge + n * 3.0
			if DowntownPlan.is_water(Vector3(probe.x, 0.0, probe.y)):
				continue
			var p1 := Vector3(edge.x, top, edge.y)
			var p0 := Vector3(edge.x + n.x * EDGE_RAMP, -0.02, edge.y + n.y * EDGE_RAMP)
			kit.col_beam(p0, p1, length, 0.4)
			var d := p1 - p0
			var z := d.normalized()
			var x := Vector3.UP.cross(z).normalized()
			var y := z.cross(x).normalized()
			kit.box(mat, (p0 + p1) * 0.5 - y * 0.05, Vector3(length, 0.1, d.length()), Basis(x, y, z))
	kit.commit(holder, "LandmarkEdgeRamps", false)
	return kit.shapes

func build(world: WorldBuilder, root: Node3D) -> void:
	if disabled():
		return
	var holder := Node3D.new()
	holder.name = "DowntownLandmarks"
	root.add_child(holder)
	var t0 := Time.get_ticks_msec()
	var shapes := 0
	var tris := 0
	for path: String in MODULES:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			push_warning("[landmarks] module failed to load: " + path)
			continue
		var module: Object = script.new()
		var st: Variant = module.call("build", world, holder)
		var key := path.get_file().get_basename()
		report[key] = st
		if st is Dictionary:
			shapes += int(st.get("shapes", 0))
			tris += int(st.get("tris", 0))
	shapes += _edge_ramps(holder)
	report["shapes"] = shapes
	report["tris"] = tris
	report["build_ms"] = Time.get_ticks_msec() - t0
	for key: String in ["marina_bay_sands", "artscience_museum", "singapore_flyer", "helix_bridge", "esplanade_theatre", "esplanade_concert_hall", "gardens_supertree_grove", "fullerton_hotel", "one_fullerton"]:
		world.locations[key] = DowntownPlan.anchor(key)
	world.locations["merlion_park_true"] = DowntownPlan.anchor("merlion_park_true")
	world.set_meta("downtown_landmarks", report)
	print("[landmarks] built ", report)
