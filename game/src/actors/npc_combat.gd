class_name NpcCombat
extends RefCounted
## Close-range firefight behaviour for armed NPCs (combat piece). Replaces
## "stand still and fire every N seconds" with readable combatants: they keep
## facing the threat, sidestep between bursts, fire short 2-4 round bursts
## with human spread (near misses crack into the walls behind the player),
## and a hit makes them flinch and stop firing for a moment (NPC-03).
## Damage per round and range gates stay as authored in NPC._shoot_at.

const STRAFE_SPEED := 1.35
const BURST_GAP := 0.19
const FLINCH_HOLD := 0.45
const POLICE_RANGE := 15.0
const HOSTILE_RANGE := 18.0
const SPREAD := 0.06

## Clear sightline from the NPC's eyes to the target's chest (no shooting
## through walls, NPC-03). Re-checked at most every 0.3 s per NPC.
static func has_line(npc: NPC, target_position: Vector3) -> bool:
	var now := game_time()
	if float(npc.get_meta("_los_at", -10.0)) + 0.3 > now:
		return bool(npc.get_meta("_los", true))
	var q := PhysicsRayQueryParameters3D.create(npc.global_position + Vector3.UP * 1.5, target_position + Vector3.UP * 1.2)
	q.collision_mask = 1
	var clear := npc.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	npc.set_meta("_los_at", now)
	npc.set_meta("_los", clear)
	return clear

static func engage(npc: NPC, player: Node, target_position: Vector3, delta: float) -> void:
	var s: Dictionary = npc.get_meta("_combat_state", {})
	if s.is_empty():
		s = {"burst": 0, "strafe": 0.0, "strafe_t": randf_range(0.2, 0.7)}
		npc.fire_timer = randf_range(0.6, 1.1)
		npc.set_meta("_combat_state", s)
	var to := target_position - npc.global_position
	to.y = 0.0
	if to.length() > 0.05:
		npc.rotation.y = lerp_angle(npc.rotation.y, atan2(-to.x, -to.z), clampf(delta * 9.0, 0.0, 1.0))
	var now := game_time()
	if float(npc.get_meta("_flinch_until", 0.0)) > now:
		npc.velocity.x = move_toward(npc.velocity.x, 0.0, 14.0 * delta)
		npc.velocity.z = move_toward(npc.velocity.z, 0.0, 14.0 * delta)
		return
	# Sidestep left/right or hold, re-chosen every ~0.5-1.3 s.
	s["strafe_t"] = float(s["strafe_t"]) - delta
	if float(s["strafe_t"]) <= 0.0:
		var choices := [-1.0, 0.0, 1.0]
		s["strafe"] = choices[randi() % 3]
		s["strafe_t"] = randf_range(0.5, 1.3)
	var right := Vector3(to.z, 0.0, -to.x).normalized() if to.length() > 0.05 else Vector3.ZERO
	var lateral := right * float(s["strafe"]) * STRAFE_SPEED
	npc.velocity.x = move_toward(npc.velocity.x, lateral.x, 8.0 * delta)
	npc.velocity.z = move_toward(npc.velocity.z, lateral.z, 8.0 * delta)
	npc.fire_timer -= delta
	if npc.fire_timer > 0.0:
		return
	if int(s["burst"]) <= 0:
		s["burst"] = randi_range(2, 3) if npc.is_police else randi_range(2, 4)
	s["burst"] = int(s["burst"]) - 1
	npc._shoot_at(player, SPREAD)
	if int(s["burst"]) > 0:
		npc.fire_timer = BURST_GAP + randf_range(-0.03, 0.05)
	else:
		npc.fire_timer = randf_range(1.6, 2.4) if npc.is_police else randf_range(1.1, 1.7)

static func flinch(npc: Node) -> void:
	npc.set_meta("_flinch_until", game_time() + FLINCH_HOLD)

## Simulation clock (physics ticks), so fixed-fps captures keep timings.
static func game_time() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)
