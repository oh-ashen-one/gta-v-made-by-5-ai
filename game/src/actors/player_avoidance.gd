class_name PlayerAvoidance
extends RefCounted
## Locomotion-Q: the on-foot player and pedestrians share the pavement.
## Run-2 critic: "the player passes through pedestrians". Pedestrians do not
## collide with the player's layer, so they walked into and through him. Each
## physics tick this:
## - steers the player's path around anyone just ahead (a lateral side-step
##   that grows as they close, slowing a little when head-on and very near);
## - shoulders apart any pedestrian already inside personal space, so no
##   body ever overlaps the player's;
## - walks around parked scooters, bikes, planters and bins (the street
##   prop collision layer) instead of stopping dead against them;
## - reports a shoulder-brush amount (signed, + = brushed on the left) that
##   the player turns into a small torso turn/roll away from the contact.

const LOOK_AHEAD := 2.4
const PERSONAL := 0.78            # capsule radii 0.36 + 0.32 plus a shoulder's width
const STEER := 1.15               # m/s of side-step at the closest approach
var _cache: Array = []
var _cache_t := 0.0
var brush := 0.0
var _npc_side := 0.0              # +1 = detour to our right of the group, -1 = left
var _npc_clear_t := 0.0

func steer(player: Node3D, vel: Vector3, delta: float) -> Vector3:
	_cache_t -= delta
	if _cache_t <= 0.0:
		_cache_t = 0.25
		_cache.clear()
		for npc in player.get_tree().get_nodes_in_group("npcs"):
			if npc is Node3D and (npc as Node3D).visible and npc.get("collision_layer") != 0 \
					and (npc as Node3D).global_position.distance_squared_to(player.global_position) < 144.0:
				_cache.append(npc)
	var pos := player.global_position
	var speed := Vector2(vel.x, vel.z).length()
	var fwd := Vector3(vel.x, 0.0, vel.z) / speed if speed > 0.2 else -player.global_transform.basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var side := 0.0
	var slow := 1.0
	var brush_now := 0.0
	var look := LOOK_AHEAD + speed * 0.3
	var close_block := false
	var lat_min := INF
	var lat_max := -INF
	var k_max := 0.0
	for npc in _cache:
		if not is_instance_valid(npc):
			continue
		var n := npc as Node3D
		var off := n.global_position - pos
		off.y = 0.0
		var d := off.length()
		if d > look + 0.5 or d < 0.001:
			continue
		var ahead := off.dot(fwd)
		var lat := off.dot(right)
		# Path clearance: someone within ~0.85 m of the line we are walking.
		if speed > 0.05 and ahead > -0.1 and ahead < look and absf(lat) < 0.85:
			var k := (1.0 - clampf(ahead / look, 0.0, 1.0) * 0.8) * (1.0 - absf(lat) / 0.85)
			close_block = close_block or (ahead < 1.0 and absf(lat) < 0.6)
			lat_min = minf(lat_min, lat)
			lat_max = maxf(lat_max, lat)
			k_max = maxf(k_max, k)
			if ahead < 1.0 and absf(lat) < 0.45:
				slow = minf(slow, lerpf(0.55, 1.0, clampf(ahead, 0.0, 1.0)))
		if d < 1.0:
			brush_now += signf(-lat) * (1.0 - d)
		# Never overlap: shoulder the pedestrian out of the player's space.
		if d < PERSONAL:
			# Mostly sideways out of the player's line, so a brushed
			# pedestrian makes way instead of being bulldozed ahead of him.
			var side_dir := right * (signf(lat) if absf(lat) > 0.02 else -_npc_side if _npc_side != 0.0 else 1.0)
			var push := (side_dir * 0.8 + off / d * 0.4).normalized() * (PERSONAL - d)
			n.global_position += push * 0.8
	# Pass the whole knot of people on ONE side (two people chatting side by
	# side must not cancel each other's push into a head-on bump): the side
	# with the shorter detour, held until the path is clear.
	if k_max > 0.0:
		_npc_clear_t = 0.0
		var need_r := lat_max + 0.75
		var need_l := -lat_min + 0.75
		# Choose once; switch only when the other way became clearly shorter
		# (a second person stepped into the chosen gap).
		if _npc_side == 0.0 or (_npc_side > 0.0 and need_r > need_l + 0.35) or (_npc_side < 0.0 and need_l > need_r + 0.35):
			_npc_side = 1.0 if need_r <= need_l else -1.0
		var need := need_r if _npc_side > 0.0 else need_l
		side += _npc_side * k_max * STEER * clampf(need / 0.75, 0.6, 1.6)
	else:
		_npc_clear_t += delta
		if _npc_clear_t > 0.4:
			_npc_side = 0.0
	brush = lerpf(brush, clampf(brush_now, -1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	if speed < 0.05:
		return vel
	var prop := _prop_steer(player, pos, fwd, right, speed)
	side += prop
	# Near a prop the side-step keeps a walking pace even if the body was
	# slowed by a bump, so it slides off instead of pressing into it.
	var blocked := absf(prop) > 0.01 or close_block
	var lat_speed := maxf(speed, 1.3) if blocked else speed
	# Faster gaits swerve wider (the detour must open up within the look-ahead).
	var out := Vector3(vel.x, 0.0, vel.z) * slow + right * clampf(side, -STEER * 1.6, STEER * 1.6) * clampf(lat_speed / 1.5, 0.0, 1.0) * maxf(1.0, speed / 2.5)
	# Keep the player's own speed: side-stepping redirects, it does not add pace.
	out = out.normalized() * maxf(speed * slow, 1.0 if blocked else 0.0)
	return Vector3(out.x, vel.y, out.z)

## Knee-height probes ahead on the street-prop layer: when the path is
## blocked, side-step toward whichever side is open (the capsule then slides
## past the prop rather than butting into it head-on).
var _prop_side := 0.0
func _prop_steer(player: Node3D, pos: Vector3, fwd: Vector3, right: Vector3, speed: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var reach := 0.9 + speed * 0.5
	var base := pos + Vector3.UP * 0.35
	var hit_near := INF
	for lat: float in [-0.4, 0.0, 0.4]:
		var d := _probe(space, base + right * lat, fwd, reach)
		hit_near = minf(hit_near, d)
	if hit_near == INF:
		_prop_side = lerpf(_prop_side, 0.0, 0.2)
		return _prop_side * STEER
	if absf(_prop_side) < 0.3:
		# Pick the side with the nearest open lane (a row of parked scooters
		# is walked around at its end) once, and keep it until clear.
		var gap_r := _open_lane(space, base, right, fwd, reach + 0.6)
		var gap_l := _open_lane(space, base, -right, fwd, reach + 0.6)
		_prop_side = 1.0 if gap_r <= gap_l else -1.0
	var k := clampf(1.3 - hit_near / reach, 0.35, 1.0)
	# Very close and still blocked: mostly sideways until the lane opens.
	if hit_near < 0.7:
		k = 1.6
	return _prop_side * STEER * 1.5 * k

func _open_lane(space: PhysicsDirectSpaceState3D, base: Vector3, side: Vector3, fwd: Vector3, length: float) -> float:
	for off: float in [0.55, 0.9, 1.3, 1.8, 2.4, 3.1]:
		var from := base + side * off
		# The sideways path itself must be clear too.
		if _probe(space, base, side, off) < INF:
			return INF
		if _probe(space, from - side * 0.35, fwd, length) == INF and _probe(space, from + side * 0.35, fwd, length) == INF:
			return off
	return INF

func _probe(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, StreetPropColliders.PROP_LAYER)
	var hit := space.intersect_ray(q)
	return INF if hit.is_empty() else from.distance_to(hit["position"])

## Pedestrians that pass between the over-the-shoulder camera and the lens
## (or brush the lens) fade out instead of filling the frame with the inside
## of a head (run-1/2 critics: camera clipping into a pedestrian).
var _hidden: Array = []
func hide_near_camera(cam: Camera3D, target: Vector3 = Vector3.INF) -> void:
	if cam == null:
		return
	var cp := cam.global_position
	var still: Array = []
	for npc in _hidden:
		if not is_instance_valid(npc):
			continue
		var n := npc as Node3D
		if _cam_dist(n, cp) < 1.1 or _occludes(n, cp, target, 0.6):
			still.append(npc)
		else:
			_set_body_visible(n, true)
	_hidden = still
	for npc in _cache:
		if not is_instance_valid(npc) or npc in _hidden:
			continue
		if _cam_dist(npc as Node3D, cp) < 0.75 or _occludes(npc as Node3D, cp, target, 0.4):
			_set_body_visible(npc as Node3D, false)
			_hidden.append(npc)

## A pedestrian standing in the lens-to-player sightline within ~2.4 m of the
## lens (they would cover the player with a giant torso).
static func _occludes(n: Node3D, cp: Vector3, target: Vector3, radius: float) -> bool:
	if target == Vector3.INF:
		return false
	var a := Vector2(cp.x, cp.z)
	var b := Vector2(target.x, target.z)
	var q := Vector2(n.global_position.x, n.global_position.z)
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return t * ab.length() < 2.4 and q.distance_to(a + ab * t) < radius and (q - b).length() > 0.5

static func _cam_dist(n: Node3D, cp: Vector3) -> float:
	# Distance from the lens to the pedestrian's body column (0.2-1.8 m).
	var base := n.global_position
	var y := clampf(cp.y, base.y + 0.2, base.y + 1.8)
	return cp.distance_to(Vector3(base.x, y, base.z)) - 0.25

static func _set_body_visible(n: Node3D, on: bool) -> void:
	var body = n.get("character_visual")
	if body == null or not (body is Node3D):
		body = n.get("body_root")
	if body is Node3D:
		(body as Node3D).visible = on
