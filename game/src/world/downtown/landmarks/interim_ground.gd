extends RefCounted
## Interim far-shore ground, built ONLY while the downtown-map piece is absent
## (landmarks.gd takes over the legacy "far_shore_ground" key in that case).
## The legacy far shore was one continuous slab that filled the east channel
## under the Helix Bridge and stopped short of the Esplanade and Marina Centre.
## This stand-in follows DowntownPlan.WATER exactly (land = not water), so the
## landmarks stand on plausible quays until downtown-map lands; once map.gd is
## present this module does nothing and the map's shorelines take over.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOP := 0.3

static func active() -> bool:
	return not ResourceLoader.exists("res://src/world/downtown/map.gd")

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	if not active():
		return {"active": false}
	var holder := Node3D.new()
	holder.name = "InterimFarShore"
	root.add_child(holder)
	var kit := Kit.new(holder, "InterimFarShoreCollision")
	var made := Looks.get_mat("concrete_fair")
	var paving := Looks.get_mat("granite_paving")
	var lands := [
		[Rect2(-900.0, -1320.0, 430.0, 660.0), made],      # Marina Centre and beyond
		[Rect2(-900.0, -660.0, 260.0, 311.0), paving],     # Esplanade lobe
		[Rect2(-330.0, -1320.0, 1180.0, 696.0), made],     # Bayfront, Gardens, Marina South
		[Rect2(-470.0, -1320.0, 140.0, 220.0), made],      # beyond the channel
		[DowntownPlan.ISLANDS["ns_square_float"], paving],
	]
	for l in lands:
		var r: Rect2 = l[0]
		var c := r.get_center()
		kit.box(l[1], Vector3(c.x, TOP - 2.0, c.y), Vector3(r.size.x, 4.0, r.size.y))
		kit.col_box(Vector3(r.size.x, 4.0, r.size.y), Vector3(c.x, TOP - 2.0, c.y))
	# Granite seawall coping with a dark wet band on every water edge.
	var coping := Looks.get_mat("granite_light")
	var wet := Looks.get_mat("granite_dark")
	var edges := [
		[Vector3(-330.0, 0, -624.0), Vector3(850.0, 0, -624.0)],
		[Vector3(-330.0, 0, -1100.0), Vector3(-330.0, 0, -624.0)],
		[Vector3(-470.0, 0, -1100.0), Vector3(-470.0, 0, -660.0)],
		[Vector3(-640.0, 0, -660.0), Vector3(-470.0, 0, -660.0)],
		[Vector3(-640.0, 0, -660.0), Vector3(-640.0, 0, -349.0)],
	]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		kit.beam(coping, a + Vector3(0, TOP - 0.1, 0), b + Vector3(0, TOP - 0.1, 0), 1.4, 0.22)
		kit.beam(wet, a + Vector3(0, -0.45, 0), b + Vector3(0, -0.45, 0), 1.2, 0.9)
	# Waterfront railings (gaps at the Helix landings).
	var rails := [
		[Vector3(-641.0, TOP, -372.0), Vector3(-641.0, TOP, -659.0)],
		[Vector3(-639.0, TOP, -661.0), Vector3(-472.0, TOP, -661.0)],
		[Vector3(-471.0, TOP, -662.0), Vector3(-471.0, TOP, -735.0)],
		[Vector3(-471.0, TOP, -756.0), Vector3(-471.0, TOP, -1060.0)],
		[Vector3(-329.0, TOP, -1060.0), Vector3(-329.0, TOP, -756.0)],
		[Vector3(-329.0, TOP, -735.0), Vector3(-329.0, TOP, -626.0)],
	]
	for r in rails:
		Realm.railing(kit, r[0], r[1], 1.15)
		var a2: Vector3 = r[0]
		var b2: Vector3 = r[1]
		var mid := (a2 + b2) * 0.5
		var span := (b2 - a2).abs()
		kit.col_box(Vector3(maxf(span.x, 0.2), 1.3, maxf(span.z, 0.2)), mid + Vector3(0, 0.65, 0))
	kit.commit(holder, "InterimFarShoreMesh", false)
	# Keep the legacy promise: the far shore is landable ground.
	return {"active": true, "shapes": kit.shapes, "tris": kit.tris}
