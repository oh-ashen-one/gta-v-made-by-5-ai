extends RefCounted
## Boat Quay shophouse row (original work). A run of narrow 2-3 storey
## shophouses facing the Singapore River (-x): varied widths and heights,
## pastel plaster, louvred windows, timber shutters, pitched clay-tile
## roofs or parapet fronts, a five-foot way under the upper floors, canvas
## awnings and umbrellas over the river-walk dining, lanterns and bilingual
## signboards (the generated sign set when present). No more than two
## neighbours share a tint, a height class or a roof type.

const MeshKit := preload("res://src/world/downtown/block_kits/mesh_kit.gd")
const Batch := preload("res://src/world/downtown/block_kits/batch.gd")
const FrontageKit := preload("res://src/world/downtown/block_kits/frontage_kit.gd")

const SIGN_NAMES := ["RIVERSIDE SEAFOOD", "HARBOUR TAVERN", "QUAYSIDE CHILLI CRAB", "MADRAS CURRY HOUSE", "TONGKANG BAR",
	"LAU PA SAT KOPI", "JADE DRAGON", "SAMPAN NOODLE BAR", "IRISH ROVER PUB", "SATAY ALLEY", "THE OLD GODOWN", "BIRYANI CORNER"]

## Builds one row along z inside rect (x0..x1 = back..front reversed: the
## river frontage is the rect's -x edge). Returns the number of units.
static func build(k: MeshKit, det: Batch, labels: Node3D, looks, rng: RandomNumberGenerator, r: Rect2, gy: float, stats: Dictionary) -> int:
	var x_front := r.position.x          # river side (-x)
	var x_back := r.end.x
	var z := r.position.y + 0.3
	var units := 0
	var prev_tint := -1
	var prev2_tint := -1
	var prev_roof := -1
	var roof_run := 0
	var sign_i := rng.randi() % 8
	var name_i := rng.randi() % SIGN_NAMES.size()
	var awn_keys := ["awning_red", "awning_cream", "awning_green", "awning_navy"]
	var max_h := 0.0
	while z < r.end.y - 4.5:
		# frontages are whole window bays (2.2 m), 2-4 bays wide
		var nb: int = [2, 3, 3, 2, 4][rng.randi() % 5]
		var w := 2.2 * float(nb) + 0.04
		if z + w > r.end.y - 0.3:
			nb = int((r.end.y - 0.3 - z) / 2.2)
			w = 2.2 * float(nb) + 0.04
		if nb < 2:
			break
		var storeys := 2 if rng.randf() < 0.45 else 3
		var h := (3.9 + 3.4 * float(storeys - 1)) + rng.randf_range(0.6, 1.4)
		var tint_i := rng.randi() % 6
		var guard := 0
		while (tint_i == prev_tint or tint_i == prev2_tint) and guard < 10:
			tint_i = rng.randi() % 6
			guard += 1
		prev2_tint = prev_tint
		prev_tint = tint_i
		var roof := 0 if rng.randf() < 0.6 else 1   # 0 pitched, 1 parapet front
		if roof == prev_roof:
			roof_run += 1
			if roof_run >= 2:
				roof = 1 - roof
				roof_run = 0
		else:
			roof_run = 0
		prev_roof = roof
		var inf := {"cid": 9, "tint": (float(tint_i) + 0.5) / 6.0, "fl": 0.5, "seed": rng.randf(), "H": h, "lobby": 3.6, "ground_y": gy, "u_shift": 1.1 if nb % 2 == 1 else 0.0}
		var depth := x_back - x_front
		var arcade := 2.6
		# ground floor shop recessed behind the five-foot way
		k.prism(MeshKit.rect((x_front + arcade + x_back) * 0.5, z + w * 0.5, depth - arcade, w - 0.04), gy - 1.0, gy + 3.6, inf, Vector2.ZERO, false, false, false)
		# upper floors over the arcade (soffit = five-foot-way ceiling)
		k.prism(MeshKit.rect((x_front + x_back) * 0.5, z + w * 0.5, depth, w - 0.04), gy + 3.6, gy + h, inf, Vector2.ZERO, roof == 1, true, false)
		max_h = maxf(max_h, h + 3.0)
		if roof == 0:
			# pitched clay roof, ridge along the row, eaves front and back
			k.gable_z(x_front, x_back, z, z + w, gy + h, rng.randf_range(2.2, 3.0), inf, 0.6)
		else:
			# raised parapet with a pediment and cornice, roof behind
			det.box_at("plaster_white", Vector3(0.5, 1.6, w), Vector3(x_front + 0.25, gy + h + 0.8, z + w * 0.5))
			det.box_at("plaster_white", Vector3(0.7, 0.35, w + 0.1), Vector3(x_front + 0.1, gy + h + 1.7, z + w * 0.5))
			det.box_at("roof_tile", Vector3(depth - 1.5, 0.3, w - 0.4), Vector3((x_front + x_back) * 0.5 + 0.5, gy + h + 0.15, z + w * 0.5))
		# pilasters at the party walls (front), carrying the upper facade
		for zz in [z + 0.25, z + w - 0.25]:
			det.box_at("plaster_cream", Vector3(0.55, 3.6, 0.5), Vector3(x_front + 0.27, gy + 1.8, zz))
		# cornice band between floors
		det.box_at("plaster_white", Vector3(0.35, 0.28, w), Vector3(x_front - 0.1, gy + 3.75, z + w * 0.5))
		det.box_at("plaster_white", Vector3(0.45, 0.32, w), Vector3(x_front - 0.12, gy + h - 0.2, z + w * 0.5))
		# timber shutters beside each upper window (window pattern: 2.2 m bays)
		for fl in storeys - 1:
			var wy := gy + 3.6 + 3.4 * float(fl) + 1.9
			for b in nb:
				var bz := z + w * 0.5 + (float(b) - float(nb - 1) * 0.5) * 2.2
				for s in [-1.0, 1.0]:
					det.box_at("shutter_green" if tint_i % 2 == 0 else "shutter_blue", Vector3(0.06, 1.75, 0.5), Vector3(x_front - 0.08, wy, bz + s * 0.85))
		# signboard over the five-foot way (generated sign art when present)
		var sy := gy + 3.1
		var sc := Vector3(x_front - 0.05, sy, z + w * 0.5)
		if looks.sign_keys.size() > 0:
			var key: String = looks.sign_keys[sign_i % looks.sign_keys.size()]
			sign_i += 1 + (1 if rng.randf() < 0.3 else 0)
			det.box_at("timber", Vector3(0.1, 1.05, minf(w - 0.8, 4.4) + 0.2), sc + Vector3(0.06, 0, 0))
			det.plane(key, sc + Vector3(-0.02, 0, 0), Vector3(0, 0, 1), Vector3.UP, Vector2(minf(w - 0.8, 4.4), 0.95))
		else:
			det.box_at("sign_dark", Vector3(0.1, 0.9, w - 1.0), sc)
		# restaurant name in lights on the arcade fascia above the awning
		FrontageKit._label(labels, SIGN_NAMES[name_i % SIGN_NAMES.size()], Vector3(x_front - 0.13, gy + 4.25, z + w * 0.5), Vector2(-1, 0), 44, 0.0075,
			[Color(1.0, 0.85, 0.55), Color(0.9, 0.95, 1.0), Color(1.0, 0.5, 0.4)][name_i % 3], true)
		name_i += 1
		# red lanterns under the arcade
		for s in [-1.0, 1.0]:
			var lp := Vector3(x_front + 1.2, gy + 3.0, z + w * 0.5 + s * w * 0.3)
			det.box_at("lantern", Vector3(0.38, 0.5, 0.38), lp)
			det.box_at("metal_dark", Vector3(0.05, 0.25, 0.05), lp + Vector3(0, 0.37, 0))
		# canvas awning sloping out over the river-walk dining
		var awn: String = awn_keys[(units + tint_i) % awn_keys.size()]
		var ab := Basis(Vector3(0, 0, 1), deg_to_rad(14.0))
		det.box(awn, Vector3(3.2, 0.06, w - 0.3), Transform3D(ab, Vector3(x_front - 1.5, gy + 3.15, z + w * 0.5)))
		det.box(awn, Vector3(0.04, 0.35, w - 0.3), Transform3D.IDENTITY.translated(Vector3(x_front - 3.05, gy + 2.6, z + w * 0.5)))
		# dining set on the river walk: tables, chairs, umbrella every other unit
		if units % 2 == 0:
			for tz in [z + w * 0.3, z + w * 0.75]:
				var tp := Vector3(x_front - 2.0, gy, tz)
				det.column("table", 0.45, 0.04, tp + Vector3(0, 0.74, 0), 10)
				det.column("table", 0.05, 0.74, tp, 6)
				for s in [-1.0, 1.0]:
					det.box_at("chair", Vector3(0.45, 0.45, 0.45), tp + Vector3(0, 0.22, s * 0.75))
					det.box_at("chair", Vector3(0.45, 0.5, 0.06), tp + Vector3(0, 0.7, s * 0.97))
		elif units % 4 == 1:
			var up := Vector3(x_front - 4.6, gy, z + w * 0.5)
			det.column("metal_dark", 0.05, 2.5, up, 6)
			det.column("umbrella_white", 1.4, 0.18, up + Vector3(0, 2.4, 0), 10)
			det.column("table", 0.5, 0.04, up + Vector3(0, 0.74, 0), 10)
		# rear service side: doors, pipes, AC condensers
		det.box_at("metal_dark", Vector3(0.1, 2.2, 1.2), Vector3(x_back + 0.06, gy + 1.1, z + w * 0.5))
		if units % 3 == 0:
			det.box_at("metal_light", Vector3(0.7, 0.6, 0.9), Vector3(x_back + 0.4, gy + 4.6, z + w * 0.3))
		units += 1
		z += w
	# Row collision: the shop bodies behind the five-foot way and the upper
	# floors over it (the arcade itself stays walkable).
	var zc := (r.position.y + z) * 0.5
	var zl := z - r.position.y
	k.boxes.append([Vector3(x_back - x_front - 2.6, 3.6, zl), Vector3((x_front + 2.6 + x_back) * 0.5, gy + 1.8, zc)])
	k.boxes.append([Vector3(x_back - x_front, max_h - 3.6, zl), Vector3((x_front + x_back) * 0.5, gy + 3.6 + (max_h - 3.6) * 0.5, zc)])
	stats["boat_quay_units"] = int(stats.get("boat_quay_units", 0)) + units
	return units
