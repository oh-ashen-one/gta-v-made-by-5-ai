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
const PERSONAL := 0.66            # capsule radii 0.36 + 0.32 minus a hair
const STEER := 1.15               # m/s of side-step at the closest approach
var _cache: Array = []
var _cache_t := 0.0
var brush := 0.0

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
	for npc in _cache:
		if not is_instance_valid(npc):
			continue
		var n := npc as Node3D
		var off := n.global_position - pos
		off.y = 0.0
		var d := off.length()
		if d > LOOK_AHEAD + 0.5 or d < 0.001:
			continue
		var ahead := off.dot(fwd)
		var lat := off.dot(right)
		# Path clearance: someone within ~0.85 m of the line we are walking.
		if speed > 0.3 and ahead > -0.1 and ahead < LOOK_AHEAD and absf(lat) < 0.85:
			var k := (1.0 - clampf(ahead / LOOK_AHEAD, 0.0, 1.0)) * (1.0 - absf(lat) / 0.85)
			var away := -signf(lat) if absf(lat) > 0.04 else 1.0
			side += away * k * STEER
			if ahead < 1.0 and absf(lat) < 0.45:
				slow = minf(slow, lerpf(0.55, 1.0, clampf(ahead, 0.0, 1.0)))
		if d < 1.0:
			brush_now += signf(-lat) * (1.0 - d)
		# Never overlap: shoulder the pedestrian out of the player's space.
		if d < PERSONAL:
			var push := off / d * (PERSONAL - d)
			n.global_position += push * 0.7
	brush = lerpf(brush, clampf(brush_now, -1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	if speed < 0.2:
		return vel
	side += _prop_steer(player, pos, fwd, right, speed)
	var out := Vector3(vel.x, 0.0, vel.z) * slow + right * clampf(side, -STEER * 1.6, STEER * 1.6) * minf(1.0, speed / 1.5)
	# Keep the player's own speed: side-stepping redirects, it does not add pace.
	out = out.normalized() * speed * slow
	return Vector3(out.x, vel.y, out.z)

## Knee-height probes ahead on the street-prop layer: when the path is
## blocked, side-step toward whichever side is open (the capsule then slides
## past the prop rather than butting into it head-on).
var _prop_side := 0.0
func _prop_steer(player: Node3D, pos: Vector3, fwd: Vector3, right: Vector3, speed: float) -> float:
	var space := player.get_world_3d().direct_space_state
	var reach := 0.9 + speed * 0.32
	var base := pos + Vector3.UP * 0.45
	var hit_near := INF
	for lat: float in [-0.3, 0.0, 0.3]:
		var d := _probe(space, base + right * lat, fwd, reach)
		hit_near = minf(hit_near, d)
	if hit_near == INF:
		_prop_side = lerpf(_prop_side, 0.0, 0.2)
		return _prop_side * STEER
	if absf(_prop_side) < 0.3:
		# Pick the open side once and keep it until clear (no dithering).
		var open_r := _probe(space, base + right * 0.75, fwd, reach + 0.4)
		var open_l := _probe(space, base - right * 0.75, fwd, reach + 0.4)
		_prop_side = 1.0 if open_r >= open_l else -1.0
	var k := clampf(1.3 - hit_near / reach, 0.35, 1.0)
	return _prop_side * STEER * 1.5 * k

func _probe(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, length: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, StreetPropColliders.PROP_LAYER)
	var hit := space.intersect_ray(q)
	return INF if hit.is_empty() else from.distance_to(hit["position"])
