extends Node
## Private licensed media stays outside public Git; manifest travels with code.
const MANIFEST := "res://assets/audio/radio/tracks.json"
var tracks: Array = []
var remaining: Array[int] = []
var current := -1
var speaker: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	speaker=AudioStreamPlayer.new(); speaker.volume_db=-14.0
	add_child(speaker); speaker.finished.connect(_next_track)
	if FileAccess.file_exists(MANIFEST):
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if parsed is Array:
			for row in parsed:
				if row is Dictionary and row.has("path") and ResourceLoader.exists(row.path): tracks.append(row)

func next_index() -> int:
	if tracks.is_empty(): return -1
	if remaining.is_empty():
		for i in tracks.size(): remaining.append(i)
		for i in range(remaining.size()-1,0,-1):
			var j:=_rng.randi_range(0,i)
			var swap:=remaining[i]; remaining[i]=remaining[j]; remaining[j]=swap
		# First track in the next shuffle must differ from the one just played.
		if remaining.size()>1 and remaining.back()==current:
			var swap:=remaining[0]; remaining[0]=remaining[-1]; remaining[-1]=swap
	return remaining.pop_back()

func _next_track() -> void:
	if Game.mode!=Game.MODE_CAR or not bool(Game.settings.get("radio_enabled",true)): return
	current=next_index()
	if current<0: return
	speaker.stream=load(tracks[current].path) as AudioStream
	speaker.play()

func title() -> String:
	return String(tracks[current].title) if current>=0 and speaker.playing else "OFF"

func _process(delta: float) -> void:
	if DisplayServer.get_name()=="headless": return
	var audible:=Game.mode==Game.MODE_CAR and bool(Game.settings.get("radio_enabled",true))
	speaker.stream_paused=Game.simulation_paused
	if audible and not speaker.playing and not Game.simulation_paused: _next_track()
	var target: float=0.20 if audible else 0.0
	speaker.volume_linear=move_toward(speaker.volume_linear,target,delta*0.5)
	if not audible and speaker.volume_linear<=0.001: speaker.stop()
