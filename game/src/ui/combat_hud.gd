extends CanvasLayer
## Combat feedback overlay (combat piece), drawn above the main HUD:
## - hit marker: four short diagonal ticks that pop around the reticle on
##   every confirmed hit, red and larger on a kill;
## - target reticle: while aiming at a live person the centre dot turns red;
## - incoming fire: a red arc on a ring around the reticle points toward the
##   shooter, with a faint red screen-edge pulse.
## Listens to Events only; no hooks into hud.gd.

var player: Node3D
var _canvas: Control
var _hit_t := 0.0
var _kill := false
var _dmg: Array[Dictionary] = []
var _last_enemy_origin := Vector3.INF
var _on_target := false
var _vignette := 0.0
var hits_shown := 0

func _ready() -> void:
	layer = 11
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)
	Events.hit_landed.connect(_on_hit)
	Events.actor_died.connect(_on_died)
	Events.shot_fired.connect(func(origin: Vector3, _d: Vector3, id: String):
		if id == "npc_pistol": _last_enemy_origin = origin)

func _on_hit(target: Node, _damage: float, _point: Vector3, by_player: bool) -> void:
	if by_player and target != null and (target.is_in_group("npcs") or target.is_in_group("vehicles")):
		# hit_landed follows take_damage, so a lethal hit has already died.
		var lethal: bool = target is NPC and (target as NPC).state == NPC.State.DEAD
		_hit_t = 0.38 if lethal else 0.22
		_kill = lethal
		hits_shown += 1
	elif not by_player and target != null and target.is_in_group("player") and player != null:
		var from := _last_enemy_origin if _last_enemy_origin != Vector3.INF else player.global_position - player.global_basis.z
		_dmg.append({"pos": from, "t": 0.9})
		if _dmg.size() > 4:
			_dmg.remove_at(0)
		_vignette = 1.0

func _on_died(actor: Node, by_player: bool) -> void:
	if by_player and actor != null and actor.is_in_group("npcs"):
		_hit_t = 0.38
		_kill = true

func _process(delta: float) -> void:
	_hit_t = maxf(0.0, _hit_t - delta)
	_vignette = maxf(0.0, _vignette - delta * 1.6)
	for i in range(_dmg.size() - 1, -1, -1):
		_dmg[i]["t"] = float(_dmg[i]["t"]) - delta
		if float(_dmg[i]["t"]) <= 0.0:
			_dmg.remove_at(i)
	_on_target = false
	if player != null and bool(player.get("aiming")) and Game.mode == Game.MODE_FOOT:
		var cam: Camera3D = player.get("camera")
		if cam != null:
			var from := cam.global_position
			var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 90.0)
			q.collision_mask = 1 | 4 | 8
			q.exclude = [(player as CollisionObject3D).get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and hit["collider"] is NPC and (hit["collider"] as NPC).state != NPC.State.DEAD:
				_on_target = true
	visible = Game.mode == Game.MODE_FOOT
	_canvas.queue_redraw()

func _draw_overlay() -> void:
	var size := _canvas.size
	var c := size * 0.5
	var aiming := player != null and bool(player.get("aiming"))
	if aiming and _on_target:
		_canvas.draw_circle(c, 2.6, Color(0.95, 0.18, 0.14, 0.95))
	if _hit_t > 0.0:
		var life := 0.38 if _kill else 0.22
		var t := 1.0 - _hit_t / life
		var col := Color(0.95, 0.16, 0.12, 1.0) if _kill else Color(1.0, 1.0, 1.0, 1.0)
		col.a = clampf(_hit_t / life * 1.6, 0.0, 1.0)
		var r0 := (11.0 if not _kill else 12.0) + t * 3.0
		var r1 := r0 + (6.0 if not _kill else 9.0)
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			_canvas.draw_line(c + d * r0 + Vector2(1, 1), c + d * r1 + Vector2(1, 1), Color(0, 0, 0, col.a * 0.6), 3.4, true)
			_canvas.draw_line(c + d * r0, c + d * r1, col, 2.0 if not _kill else 2.6, true)
	if player != null and not _dmg.is_empty():
		var cam: Camera3D = player.get("camera")
		for e in _dmg:
			var to: Vector3 = (e["pos"] as Vector3) - player.global_position
			var fwd := -cam.global_basis.z if cam != null else -player.global_basis.z
			var right := cam.global_basis.x if cam != null else player.global_basis.x
			var ang := atan2(to.dot(right), to.dot(Vector3(fwd.x, 0, fwd.z).normalized()))
			var a := clampf(float(e["t"]) / 0.9, 0.0, 1.0)
			var mid := ang - PI * 0.5
			_canvas.draw_arc(c, 118.0, mid - 0.32, mid + 0.32, 18, Color(0.9, 0.08, 0.06, 0.75 * a), 7.0, true)
	if _vignette > 0.0:
		var a2 := _vignette * 0.22
		var w := 90.0
		for i in 6:
			var f := float(i) / 6.0
			var col2 := Color(0.6, 0.0, 0.0, a2 * (1.0 - f) * 0.5)
			var inset := w * f
			_canvas.draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0), col2, false, w / 6.0)
