class_name CombatAudio
extends RefCounted
## Synthesised firearm sounds (combat piece). Original procedural material:
## a sharp supersonic crack, a chest-thump body, a mid "bark" and an urban
## slap-back tail off the shophouse walls; brass tinkle, hard-surface and body
## impacts, ricochet, dry fire and magazine handling. Registered into the
## shared Sfx bank so existing play/play_at calls pick them up ("gunshot" is
## replaced by the new pistol report for NPC and player shots alike).

const RATE := 22050
static var _done := false

static func register() -> void:
	if _done:
		return
	_done = true
	if DisplayServer.get_name() == "headless":
		return
	var bank = Sfx.get("_bank")
	if typeof(bank) != TYPE_DICTIONARY:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4401
	bank["gunshot"] = _report(rng, 1.0)
	bank["gun_pistol"] = bank["gunshot"]
	bank["gun_smg"] = _report(rng, 0.72)
	bank["casing"] = _casing(rng)
	bank["impact_hard"] = _impact_hard(rng)
	bank["impact_body"] = _impact_body(rng)
	bank["ricochet"] = _ricochet(rng)
	bank["dry_fire"] = _click(rng, 0.05, 2400.0)
	bank["reload_mag"] = _mag(rng)

static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

static func _report(rng: RandomNumberGenerator, length_scale: float) -> AudioStreamWAV:
	var n := int(RATE * 1.15 * length_scale)
	var dry := PackedFloat32Array()
	dry.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var bp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp = lp * 0.55 + w * 0.45
		lp2 = lp2 * 0.92 + w * 0.08
		bp = (w - lp) # high band
		var crack := bp * exp(-t * 380.0) * 1.6 + w * exp(-t * 120.0) * 0.6
		var f := 140.0 * exp(-t * 18.0) + 48.0
		var thump := sin(TAU * f * t) * exp(-t * 22.0) * 1.0
		var bark := lp * exp(-t * 30.0) * 0.8
		var rumble := lp2 * exp(-t * 4.2 / length_scale) * 1.4
		dry[i] = crack + thump + bark + rumble
	# Urban slap-back: two delayed, darker reflections plus a diffuse tail.
	var out := PackedFloat32Array()
	out.resize(n)
	var echo_lp := 0.0
	for i in n:
		var e := 0.0
		var d1 := i - int(RATE * 0.085)
		var d2 := i - int(RATE * 0.19)
		var d3 := i - int(RATE * 0.33)
		if d1 >= 0: e += dry[d1] * 0.42
		if d2 >= 0: e += dry[d2] * 0.26
		if d3 >= 0: e += dry[d3] * 0.14
		echo_lp = echo_lp * 0.8 + e * 0.2
		out[i] = tanh((dry[i] + echo_lp * 1.4) * 1.25) * 0.9
	return _wav(out)

static func _casing(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var s := PackedFloat32Array()
	s.resize(n)
	var partials := [3150.0, 5230.0, 7180.0, 8920.0]
	for i in n:
		var t := float(i) / RATE
		var v := rng.randf_range(-1, 1) * exp(-t * 400.0) * 0.4
		for k in partials.size():
			v += sin(TAU * partials[k] * t + k) * exp(-t * (16.0 + k * 9.0)) * (0.35 / (k + 1))
		s[i] = v * 0.7
	return _wav(s)

static func _impact_hard(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1, 1)
		lp = lp * 0.7 + w * 0.3
		s[i] = tanh((w * exp(-t * 160.0) * 1.1 + lp * exp(-t * 28.0) * 0.8 + sin(TAU * 210.0 * t) * exp(-t * 45.0) * 0.4) * 1.2) * 0.8
	return _wav(s)

static func _impact_body(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lp * 0.88 + rng.randf_range(-1, 1) * 0.12
		s[i] = (lp * 2.2 + sin(TAU * 85.0 * t) * 0.6) * exp(-t * 32.0)
	return _wav(s)

static func _ricochet(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 2900.0 * exp(-t * 2.2) + 700.0
		ph += TAU * f / RATE
		s[i] = sin(ph) * exp(-t * 6.0) * 0.32 * minf(1.0, t * 80.0) + rng.randf_range(-1, 1) * exp(-t * 90.0) * 0.3
	return _wav(s)

static func _click(rng: RandomNumberGenerator, length: float, freq: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (rng.randf_range(-1, 1) * 0.5 + sin(TAU * freq * t) * 0.5) * exp(-t * 140.0)
	return _wav(s)

static func _mag(rng: RandomNumberGenerator) -> AudioStreamWAV:
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for at in [0.0, 0.42, 0.66]:
			var u: float = t - float(at)
			if u >= 0.0:
				v += (rng.randf_range(-1, 1) * 0.6 + sin(TAU * 1800.0 * u) * 0.4) * exp(-u * 90.0)
		s[i] = v * 0.6
	return _wav(s)
