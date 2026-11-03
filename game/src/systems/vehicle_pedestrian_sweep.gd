extends RefCounted
## Pedestrians receive swept contact damage without acting as vehicle walls.
const NPC_LAYER := 4
const MAX_CONTACTS := 16

static func apply(car: Car, start: Transform3D, incoming: Vector3) -> int:
	if not car.driver_is_player or car._collision_shape == null: return 0
	var travel := car.global_position - start.origin
	var speed := Vector2(incoming.x,incoming.z).length()
	if travel.length_squared()<0.000001 or speed<0.5: return 0
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car._collision_shape.shape
	query.transform = start * car._collision_shape.transform
	query.collision_mask = NPC_LAYER
	query.margin = 0.015
	query.exclude = [car.get_rid()]
	var start_shape := query.transform
	var count := 0
	# cast_motion ignores starting overlaps, so handle those explicitly first.
	count += _contacts(space.intersect_shape(query,MAX_CONTACTS),car,speed,query)
	for attempt in MAX_CONTACTS:
		query.transform = start_shape
		query.motion = travel
		var fraction := space.cast_motion(query)
		if fraction.size()<2 or fraction[0]>=1.0: break
		query.transform.origin = start_shape.origin + travel * minf(1.0,fraction[1]+0.01/maxf(travel.length(),0.01))
		query.motion = Vector3.ZERO
		var contacts := space.intersect_shape(query,MAX_CONTACTS)
		if contacts.is_empty(): break
		count += _contacts(contacts,car,speed,query)
	query.transform = car._collision_shape.global_transform
	query.motion = Vector3.ZERO
	count += _contacts(space.intersect_shape(query,MAX_CONTACTS),car,speed,query)
	return count

static func _contacts(rows: Array, car: Car, speed: float, query: PhysicsShapeQueryParameters3D) -> int:
	var count := 0
	var excluded := query.exclude
	for row in rows:
		if row.rid in excluded: continue
		excluded.append(row.rid)
		var person := row.collider as NPC
		if person == null or person.state == NPC.State.DEAD or person.pooled_inactive: continue
		var now := Time.get_ticks_msec()
		if now-int(person.get_meta("car_hit_ms",-100000))<=600: continue
		person.set_meta("car_hit_ms",now)
		if speed>2.5:
			person.take_damage(clampf((speed-2.0)*16.0,18.0,220.0),car.global_position,true)
		else:
			person.scramble_from(car.global_position)
		count+=1
	query.exclude=excluded
	return count
