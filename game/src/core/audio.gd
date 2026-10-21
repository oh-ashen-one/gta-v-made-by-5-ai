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

func _ready() -> void:
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
	_siren_player.volume_db = -12.0

func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p

# --------------------------------------------------------------------- public
func play(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _bank.has(sound_id):
		return
	var p := _one_shots[_one_shot_index]
	_one_shot_index = (_one_shot_index + 1) % _one_shots.size()
	p.stream = _bank[sound_id]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func start_engine() -> void:
	if not _engine_player.playing:
		_engine_player.play()

func stop_engine() -> void:
	_engine_player.stop()

func set_engine_pitch(ratio: float) -> void:
	_engine_player.pitch_scale = clampf(0.65 + ratio * 1.4, 0.5, 2.4)

func start_rotor() -> void:
	if not _rotor_player.playing:
		_rotor_player.play()

func stop_rotor() -> void:
	_rotor_player.stop()

func set_rotor_pitch(ratio: float) -> void:
	_rotor_player.pitch_scale = clampf(0.7 + ratio * 0.8, 0.5, 1.8)

func set_siren(on: bool, pitch: float = 1.0) -> void:
	if on and not _siren_player.playing:
		_siren_player.play()
	elif not on and _siren_player.playing:
		_siren_player.stop()
	_siren_player.pitch_scale = pitch

# ------------------------------------------------------------------ synthesis
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
		s[i] = clampf(body + crack + tail, -1.0, 1.0)
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
	var n := int(MIX_RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var saw := fmod(t * 62.0, 1.0) * 2.0 - 1.0
		low = low * 0.9 + _rng.randf_range(-1.0, 1.0) * 0.1
		s[i] = (saw * 0.22 + low * 0.35 + sin(TAU * 31.0 * t) * 0.18) * 0.7
	return _wav(s, true)

func _rotor_loop() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var chop := 0.6 + 0.4 * sin(TAU * 22.0 * t)
		low = low * 0.88 + _rng.randf_range(-1.0, 1.0) * 0.12
		s[i] = (low * 0.5 * chop + sin(TAU * 55.0 * t) * 0.12) * 0.8
	return _wav(s, true)

func _siren_loop() -> AudioStreamWAV:
	var n := int(MIX_RATE * 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 720.0 if fmod(t, 0.8) < 0.4 else 980.0
		var env: float = 0.4 + 0.6 * absf(sin(TAU * 1.25 * t))
		s[i] = sin(TAU * f * t) * env * 0.3
	return _wav(s, true)
