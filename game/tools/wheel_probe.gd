extends Node
## Measure where each provider car's baked wheels sit, in Car-local space, so
## articulated overlay wheels can be aligned (wave 5, ART-06). Prints JSON.
func _ready() -> void:
	var result := {}
	for kind in ["sedan", "coupe", "van"]:
		var car := Car.new()
		car.kind = kind
		add_child(car)
		var body: MeshInstance3D = null
		for mi in car.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).begins_with("body"):
				body = mi
		if body == null:
			result[kind] = "no provider body"
			continue
		var to_car: Transform3D = car.global_transform.affine_inverse() * body.global_transform
		var pts: PackedVector3Array = PackedVector3Array()
		for surface in body.mesh.get_surface_count():
			var arrays := body.mesh.surface_get_arrays(surface)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				pts.append(to_car * v)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		var wheels := {}
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				# Contact patch: the lowest 6 cm of the outer half of each corner.
				var contact: Array[Vector3] = []
				for p in pts:
					if p.y < lo.y + 0.06 and signf(p.x) == sx and signf(p.z) == sz and absf(p.x) > hi.x * 0.35:
						contact.append(p)
				if contact.is_empty(): continue
				var c := Vector3.ZERO
				for p in contact: c += p
				c /= contact.size()
				# Tyre profile: outer-face vertices near the contact column.
				var zmin := INF
				var zmax := -INF
				var ytop := -INF
				var xout := 0.0
				for p in pts:
					if signf(p.x) != sx or absf(p.z - c.z) > 0.55 or p.y > lo.y + 0.9: continue
					xout = maxf(xout, absf(p.x))
					if absf(p.y - (lo.y + 0.33)) < 0.05:
						zmin = minf(zmin, p.z)
						zmax = maxf(zmax, p.z)
				wheels["%s%s" % ["F" if sz < 0 else "R", "L" if sx < 0 else "R"]] = {"contact_centre": [snappedf(c.x, 0.01), snappedf(lo.y, 0.01), snappedf(c.z, 0.01)], "contact_points": contact.size(), "outer_x": snappedf(xout, 0.01), "profile_z": [snappedf(zmin, 0.01), snappedf(zmax, 0.01)]}
		result[kind] = {"bounds_min": [snappedf(lo.x, 0.01), snappedf(lo.y, 0.01), snappedf(lo.z, 0.01)], "bounds_max": [snappedf(hi.x, 0.01), snappedf(hi.y, 0.01), snappedf(hi.z, 0.01)], "vertices": pts.size(), "wheels": wheels}
		car.queue_free()
	print("WHEEL_PROBE ", JSON.stringify(result))
	Sfx.shutdown_audio()
	get_tree().quit(0)
