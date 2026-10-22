extends Node
## Procedural sound bank (END_GOAL AUDIO-01 / AUDIO-02).
## Every sound is synthesised in code: original material, no sampled or
## licensed audio, no music. One-shots are pooled; the engine and rotor are
## looping players whose pitch tracks the vehicle state.

const MIX_RATE := 22050

var _bank := {}
var _one_shots: Array[AudioStreamPlayer] = []
var _one_shot_index := 0
var _engine_player: AudioStreamPlayer
var _rotor_player: AudioStreamPlayer
var _siren_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _spatial_shots: Array[AudioStreamPlayer3D] = []
var _spatial_index := 0
var _actor_loops: Dictionary = {}
var _spatial_timer := 0.0
var _bird_timer := 6.0
var _ambient_started := false
var _ambience_players: Array[AudioStreamPlayer3D] = []
var _audio_shutdown := false
var _headless_audio := false


func _ready() -> void:
	_headless_audio = DisplayServer.get_name() == "headless"
	_rng.seed = 90210
	_bank["gunshot"] = _gunshot()
	_bank["footstep"] = _footstep()
	_bank["impact"] = _impact()
	_bank["pickup"] = _pickup()
	_bank["ui"] = _ui_click()
	_bank["engine"] = _engine_loop()
	_bank["rotor"] = _rotor_loop()
	_bank["siren"] = _siren_loop()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_one_shots.append(p)
	_engine_player = _loop_player(_bank["engine"])
	_rotor_player = _loop_player(_bank["rotor"])
	_siren_player = _loop_player(_bank["siren"])
	# Legacy control methods remain compatible; actual vehicle sounds now live
	# on their actors, so passing traffic and a distant aircraft attenuate.
	_engine_player.volume_db = -80.0
	_rotor_player.volume_db = -80.0
	_siren_player.volume_db = -80.0
	_bank["city"] = _ambience_loop(0)
	_bank["market"] = _ambience_loop(1)
	_bank["water"] = _ambience_loop(2)
	_bank["bird"] = _bird()
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 130.0
		p.unit_size = 7.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_spatial_shots.append(p)
	Events.shot_fired.connect(func(origin: Vector3, _direction: Vector3, id: String):
		if id == "npc_pistol": play_at("gunshot", origin, -7.0, .9))

func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p

# --------------------------------------------------------------------- public
func play(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _headless_audio:
		return
	if not _bank.has(sound_id):
		return
	var p := _one_shots[_one_shot_index]
	_one_shot_index = (_one_shot_index + 1) % _one_shots.size()
	p.stream = _bank[sound_id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func start_engine() -> void:
	if _headless_audio:
		return
	if not _engine_player.playing:
		_engine_player.play()

func stop_engine() -> void:
	_engine_player.stop()

func set_engine_pitch(ratio: float) -> void:
	_engine_player.pitch_scale = clampf(0.65 + ratio * 1.4, 0.5, 2.4)

func start_rotor() -> void:
	if _headless_audio:
		return
	if not _rotor_player.playing:
		_rotor_player.play()

func stop_rotor() -> void:
	_rotor_player.stop()

func set_rotor_pitch(ratio: float) -> void:
	_rotor_player.pitch_scale = clampf(0.7 + ratio * 0.8, 0.5, 1.8)

func set_siren(on: bool, pitch: float = 1.0) -> void:
	if _headless_audio:
		return
	if on and not _siren_player.playing:
		_siren_player.play()
	elif not on and _siren_player.playing:
		_siren_player.stop()
	_siren_player.pitch_scale = pitch

# -------------------------------------------------------- spatial soundscape
func play_at(sound_id: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _headless_audio:
		return
	if _audio_shutdown or not _bank.has(sound_id) or _spatial_shots.is_empty():
		return
	var p := _spatial_shots[_spatial_index]
	_spatial_index = (_spatial_index + 1) % _spatial_shots.size()
	p.global_position = position
	p.stream = _bank[sound_id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _spatial_loop(owner_node: Node3D, stream_id: String, volume: float, distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _bank[stream_id]
	p.volume_db = volume
	p.max_distance = distance
	p.unit_size = 10.0
	owner_node.add_child(p)
	p.play()
	return p

func _process(delta: float) -> void:
	if _headless_audio:
		return
	if _audio_shutdown:
		return
	for p in _spatial_shots:
		p.stream_paused = Game.simulation_paused
	for p in _ambience_players:
		if is_instance_valid(p): p.stream_paused = Game.simulation_paused
	for record in _actor_loops.values():
		if is_instance_valid(record["engine"]): record["engine"].stream_paused = Game.simulation_paused
		if record.has("siren") and is_instance_valid(record["siren"]): record["siren"].stream_paused = Game.simulation_paused
	if Game.simulation_paused:
		return
	_spatial_timer -= delta
	if _spatial_timer > 0.0:
		return
	_spatial_timer = .25
	var listener := Game.player_position
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(v): continue
		var id: int = v.get_instance_id()
		var helicopter := v is Helicopter
		var active: bool = v.pilot_is_player if helicopter else (v.has_ai or v.driver_is_player)
		active = active and not v.disabled and listener.distance_to(v.global_position)<(240.0 if helicopter else 105.0)
		if not active:
			if _actor_loops.has(id):
				var old: Dictionary = _actor_loops[id]
				for sound in old.values():
					if is_instance_valid(sound): sound.queue_free()
				_actor_loops.erase(id)
			continue
		if not _actor_loops.has(id):
			var engine := _spatial_loop(v,"rotor" if helicopter else "engine",-7.0 if helicopter else -17.0,240.0 if helicopter else 110.0)
			_actor_loops[id] = {"engine":engine}
			if not helicopter and v.kind=="police":
				_actor_loops[id]["siren"] = _spatial_loop(v,"siren",-12.0,160.0)
		var record: Dictionary = _actor_loops[id]
		record["engine"].pitch_scale = .75+clampf(v.velocity.length()/30.0,0,1)*1.0
		if record.has("siren"):
			record["siren"].volume_db = -13.0 if Game.wanted_level>0 else -80.0
	# Prune references after streamed/destroyed vehicles; audio is actor-owned.
	for id in _actor_loops.keys():
		if not is_instance_valid(_actor_loops[id]["engine"]): _actor_loops.erase(id)
	if not _ambient_started and get_tree().current_scene.get("world") != null:
		_ambient_started=true
		for spec in [[Vector3(-80,3,-80),"market",-24.0,80.0],[Vector3(0,2,-350),"water",-21.0,180.0],[Vector3(-160,4,-160),"city",-28.0,260.0],[Vector3(160,4,160),"city",-28.0,260.0]]:
			var anchor:=Node3D.new();add_child(anchor);anchor.global_position=spec[0]
			_ambience_players.append(_spatial_loop(anchor,spec[1],spec[2],spec[3]))
	_bird_timer-=.25
	if _bird_timer<=0:
		_bird_timer=_rng.randf_range(7,13)
		play_at("bird",listener+Vector3(_rng.randf_range(-18,18),10,_rng.randf_range(-18,18)),-24.0,_rng.randf_range(.85,1.15))

func shutdown_audio() -> void:
	_audio_shutdown=true
	_stop_audio_recursive(self)
	for record in _actor_loops.values():
		for p in record.values():
			if is_instance_valid(p): p.stop(); p.stream=null
	_actor_loops.clear()

func _stop_audio_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop(); child.stream=null
		_stop_audio_recursive(child)

func _ambience_loop(kind: int) -> AudioStreamWAV:
	var n:=MIX_RATE*6
	var s:=PackedFloat32Array();s.resize(n)
	var low:=0.0
	for i in n:
		var t:=float(i)/MIX_RATE
		low=low*.985+_rng.randf_range(-1,1)*.015
		var wave:=.6+.4*sin(TAU*t/6.0)
		match kind:
			0: s[i]=low*.65+sin(TAU*43.0*t)*.018
			1: s[i]=low*.5+sin(TAU*90.0*t)*.012+sin(TAU*180.0*t)*.008
			_: s[i]=low*wave*.85
	# Crossfade the tail to the head so the loop seam is continuous.
	var fade:=int(MIX_RATE*.2)
	for i in fade:
		var weight:=float(i)/fade
		s[n-fade+i]=lerpf(s[n-fade+i],s[i],weight)
	return _wav(s,true)

func _bird() -> AudioStreamWAV:
	var n:=int(MIX_RATE*.38)
	var s:=PackedFloat32Array();s.resize(n)
	for i in n:
		var t:=float(i)/MIX_RATE
		var envelope:=pow(sin(PI*float(i)/n),2.0)
		s[i]=sin(TAU*(1900*t+1100*t*t+sin(t*30)*8))*envelope*.18
	return _wav(s)

# ------------------------------------------------------------------ synthesis
## Loop seam (wave 5): the engine/rotor loops restarted with a different noise
## state and a half-cycle tone, a click every 0.5 s. Use whole tone cycles and
## crossfade the tail into the head so sample n-1 flows into sample 0.
## `s` holds LOOP_PAD extra samples past the loop end; that continuation is
## blended into the head, so sample n-1 flows into sample 0, then trimmed.
const LOOP_PAD := 1323   # 60 ms at 22.05 kHz
func _loop_seam(s: PackedFloat32Array) -> PackedFloat32Array:
	var n := s.size() - LOOP_PAD
	for i in LOOP_PAD:
		var weight := float(i + 1) / float(LOOP_PAD + 1)
		s[i] = lerpf(s[n + i], s[i], weight)
	s.resize(n)
	return s

## Objective loop/clip metrics for the regression suite (not a listening test).
func loop_metrics() -> Dictionary:
	var out := {}
	for key in _bank:
		var stream: AudioStreamWAV = _bank[key]
		var data := stream.data
		var count := data.size() / 2
		if count < 2: continue
		var peak := 0
		var interior := 0
		var previous := data.decode_s16(0)
		for i in count:
			var v := data.decode_s16(i * 2)
			peak = maxi(peak, absi(v))
			interior = maxi(interior, absi(v - previous))
			previous = v
		var seam := absi(data.decode_s16(0) - data.decode_s16((count - 1) * 2))
		# A seam is a click only if it jumps further than the waveform ever does
		# between neighbouring samples (a sawtooth's own reset is not a click).
		out[key] = {"looped": stream.loop_mode != AudioStreamWAV.LOOP_DISABLED, "peak": peak / 32000.0, "seam_step": seam / 32000.0, "max_interior_step": interior / 32000.0}
	return out
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		var s: int = int(v * 32000.0)
		bytes.encode_s16(i * 2, s)
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream

func _gunshot() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		low = low * 0.72 + noise * 0.28
		var body := sin(TAU * 95.0 * t) * exp(-t * 16.0) * 0.55
		var crack := noise * exp(-t * 42.0) * 0.8
		var tail := low * exp(-t * 9.0) * 0.5
		# Soft saturation instead of a hard clamp: the hard-clipped crack hit
		# full scale (objective peak check, wave 5).
		s[i] = tanh((body + crack + tail) * 1.1) * 0.86
	return _wav(s)

func _footstep() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.14)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		low = low * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.4
		s[i] = low * exp(-t * 30.0) * 0.5 + sin(TAU * 150.0 * t) * exp(-t * 40.0) * 0.18
	return _wav(s)

func _impact() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = _rng.randf_range(-1.0, 1.0) * exp(-t * 55.0) * 0.4 + sin(TAU * 320.0 * t) * exp(-t * 40.0) * 0.25
	return _wav(s)

func _pickup() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 660.0 if t < 0.14 else 990.0
		s[i] = sin(TAU * f * t) * exp(-t * 5.0) * 0.35
	return _wav(s)

func _ui_click() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.07)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		s[i] = sin(TAU * 1200.0 * t) * exp(-t * 60.0) * 0.3
	return _wav(s)

func _engine_loop() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.5) + LOOP_PAD
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var saw := fmod(t * 62.0, 1.0) * 2.0 - 1.0
		low = low * 0.9 + _rng.randf_range(-1.0, 1.0) * 0.1
		s[i] = (saw * 0.22 + low * 0.35 + sin(TAU * 32.0 * t) * 0.18) * 0.7
	return _wav(_loop_seam(s), true)

func _rotor_loop() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.5) + LOOP_PAD
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var chop := 0.6 + 0.4 * sin(TAU * 22.0 * t)
		low = low * 0.88 + _rng.randf_range(-1.0, 1.0) * 0.12
		s[i] = (low * 0.5 * chop + sin(TAU * 56.0 * t) * 0.12) * 0.8
	return _wav(_loop_seam(s), true)

func _siren_loop() -> AudioStreamWAV:
	# Two whole 0.8 s wail cycles: a 1.0 s loop restarted the pattern mid-phrase.
	var n := int(MIX_RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 720.0 if fmod(t, 0.8) < 0.4 else 980.0
		var env: float = 0.4 + 0.6 * absf(sin(TAU * 1.25 * t))
		s[i] = sin(TAU * f * t) * env * 0.3
	return _wav(s, true)
