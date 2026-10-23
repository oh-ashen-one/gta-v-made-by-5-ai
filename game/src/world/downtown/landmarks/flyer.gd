extends RefCounted
## Singapore Flyer and its terminal (wave M, downtown-landmarks).
##
## The authored wheel GLB moves to its plan anchor at Marina Centre (D2) and
## now stands on a full terminal: a 3-storey, 140 m curved-front glazed
## building with mullions, slab edges, a planted roof and a timber boarding
## deck under the lowest capsule, a drop-off canopy and an entrance plaza with
## trees, lamps and benches. Collision: terminal, boarding deck and a ring of
## boxes around the rim for the helicopter.

const Kit = preload("res://src/world/downtown/landmarks/kit.gd")
const Looks = preload("res://src/world/downtown/landmarks/looks.gd")
const Realm = preload("res://src/world/downtown/landmarks/realm.gd")

const TOP := 0.36
const WHEEL_SCALE := 1.4
const HUB_Y := 62.0 * 1.4
const RIM_R := 52.0 * 1.4

func build(world: WorldBuilder, root: Node3D) -> Dictionary:
	var a: Dictionary = DowntownPlan.ANCHORS["singapore_flyer"]
	var p: Vector3 = a["pos"]
	var yaw := deg_to_rad(float(a["yaw_deg"]))
	var holder := Node3D.new()
	holder.name = "SingaporeFlyer"
	root.add_child(holder)
	var wheel := world._authored("singapore_flyer.glb", p, yaw, Vector3.ONE * WHEEL_SCALE)
	var kit := Kit.new(holder, "FlyerCollision")
	var basis := Basis(Vector3.UP, yaw)
	var ax := basis * Vector3.RIGHT      # wheel plane direction
	var az := basis * Vector3.BACK       # across the wheel
	var site := DowntownPlan.block_rect("flyer_site")
	var sc := site.get_center()
	var paving := Looks.get_mat("granite_paving")
	kit.box(paving, Vector3(sc.x, TOP * 0.5 - 0.6, sc.y), Vector3(site.size.x, TOP + 1.2, site.size.y))
	kit.col_box(Vector3(site.size.x, 1.0, site.size.y), Vector3(sc.x, TOP - 0.5, sc.y))
	# Terminal: curved glazed front (bow toward +az), 3 storeys of 4 m.
	var length := 140.0
	var depth := 34.0
	var h := 11.0
	var n := 28
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for i in n + 1:
		var u := float(i) / n
		var s := lerpf(-length * 0.5, length * 0.5, u)
		var bow := 7.0 * sin(PI * u)
		front.append(p + ax * s + az * (depth * 0.5 + bow))
		back.append(p + ax * s - az * (depth * 0.5))
	var glass := Looks.get_mat("glass_green")
	var satin := Looks.get_mat("steel_satin")
	var white := Looks.get_mat("steel_white")
	var concrete := Looks.get_mat("concrete_fair")
	for i in n:
		var f0 := front[i] + Vector3(0, TOP, 0)
		var f1 := front[i + 1] + Vector3(0, TOP, 0)
		var b0 := back[i] + Vector3(0, TOP, 0)
		var b1 := back[i + 1] + Vector3(0, TOP, 0)
		var up := Vector3(0, h, 0)
		kit.quad(glass, f0, f1, f1 + up, f0 + up)
		kit.quad(concrete, b1, b0, b0 + up, b1 + up)
		kit.quad(Looks.get_mat("planting"), f0 + up, f1 + up, b1 + up, b0 + up)
		kit.beam(satin, f0, f0 + up, 0.18, 0.3)
		for fl: float in [4.0, 8.0]:
			kit.beam(white, f0 + Vector3(0, fl, 0), f1 + Vector3(0, fl, 0), 0.6, 0.45)
		kit.beam(white, f0 + up, f1 + up, 0.9, 0.7)
		# Warm interior read through the lowest glazing.
		var inset := (b0 - f0).normalized() * 3.0
		kit.quad(Looks.get_mat("interior_warm"), f0 + inset, f1 + inset, f1 + inset + Vector3(0, 3.6, 0), f0 + inset + Vector3(0, 3.6, 0))
	for e in [0, n]:
		var f := front[e] + Vector3(0, TOP, 0)
		var b := back[e] + Vector3(0, TOP, 0)
		if e == 0:
			kit.quad(concrete, b, f, f + Vector3(0, h, 0), b + Vector3(0, h, 0))
		else:
			kit.quad(concrete, f, b, b + Vector3(0, h, 0), f + Vector3(0, h, 0))
	kit.col_box(Vector3(length, h, depth + 7.0), p + Vector3(0, TOP + h * 0.5, 0) + az * 3.5, basis)
	# Boarding deck on the roof under the wheel, with glass balustrade.
	var deck_c := p + Vector3(0, TOP + h + 0.3, 0)
	kit.box(Looks.get_mat("timber"), deck_c, Vector3(46.0, 0.6, 18.0), basis)
	for side: float in [-9.0, 9.0]:
		Realm.glass_rail(kit, deck_c + az * side - ax * 23.0 + Vector3(0, 0.3, 0), deck_c + az * side + ax * 23.0 + Vector3(0, 0.3, 0), 1.2)
	kit.col_box(Vector3(46.0, 0.6, 18.0), deck_c, basis)
	# Drop-off canopy and entrance on the plaza (Raffles Avenue) side.
	var ent := p - az * (depth * 0.5 + 9.0) + Vector3(0, TOP, 0)
	for k in 6:
		kit.cyl(white, ent + ax * (-25.0 + k * 10.0) - az * 6.0, 0.3, 0.25, 6.0, 10, false)
	kit.box(white, ent + Vector3(0, 6.3, 0), Vector3(56.0, 0.6, 16.0), basis)
	kit.box(Looks.get_mat("light_strip"), ent + Vector3(0, 5.98, 0), Vector3(50.0, 0.04, 0.4), basis)
	var sign := Label3D.new()
	sign.text = "SINGAPORE FLYER"
	sign.font_size = 120
	sign.pixel_size = 0.016
	sign.modulate = Color(0.92, 0.9, 0.84)
	sign.position = ent + Vector3(0, 7.4, 0) - az * 8.1
	sign.rotation.y = yaw + PI
	holder.add_child(sign)
	kit.box(Looks.get_mat("signage"), ent + Vector3(0, 7.4, 0) - az * 7.9, Vector3(14.0, 1.6, 0.3), basis)
	# Plaza trees, lamps and benches in front of the entrance.
	var lamps := []
	var benches := []
	for k in 7:
		var tp := ent - az * 22.0 + ax * (-36.0 + k * 12.0)
		world._tree(tp, 0.95)
		lamps.append(Kit.xf(tp + ax * 6.0, yaw))
		benches.append(Kit.xf(tp - az * 3.0, yaw))
	Realm.lamps(holder, "FlyerLamps", lamps)
	Realm.benches(holder, "FlyerBenches", benches)
	# Rim collision ring (helicopter) and the two A-frame legs.
	for k in 14:
		var ang := TAU * k / 14.0
		var rp := p + Vector3(0, HUB_Y, 0) + ax * cos(ang) * RIM_R + Vector3.UP * sin(ang) * RIM_R
		var tangent := (ax * -sin(ang) + Vector3.UP * cos(ang)).normalized()
		var bz := az.normalized()
		var bx := tangent.cross(bz).normalized()
		kit.col_box(Vector3(6.0, 2.0 * RIM_R * sin(PI / 14.0) + 2.0, 12.0), rp, Basis(bx, tangent, bz))
	kit.commit(holder, "FlyerTerminal", true)
	return {"shapes": kit.shapes, "tris": kit.tris, "wheel": wheel != null}
