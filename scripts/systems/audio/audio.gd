extends Node
## Music, ambience and sound effects.
##
## Game code asks for a cue by name (`Audio.play_sfx(&"pickup")`); nothing else
## knows a file path. Music follows the scene, and most effects are wired here
## from the signals of the other autoloads, so gameplay scripts stay silent
## about sound. Volumes belong to `Settings`, which drives the three buses.

signal music_changed(track: StringName)

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const MUSIC_DIR := "res://audio/music/"
const SFX_DIR := "res://audio/sfx/"

const MUSIC_TRACKS: Array[StringName] = [&"menu", &"maroon", &"farm", &"heir", &"ending"]
const SFX_CUES: Array[StringName] = [
	&"step", &"pickup", &"drink", &"alert", &"caught", &"plant", &"harvest", &"coin",
	&"task_done", &"ui_move", &"ui_accept", &"ui_cancel",
]
const AMBIENCE_CUES: Array[StringName] = [&"river", &"wind"]
## Scene file name → what plays there. A scene that is not listed is silent.
const SCENE_AUDIO := {
	"main_menu.tscn": {"music": &"menu"},
	"maroon.tscn": {"music": &"maroon", "ambience": &"river"},
	"farm.tscn": {"music": &"farm"},
	"heir.tscn": {"music": &"heir"},
	"ending_screen.tscn": {"music": &"ending"},
}
const SFX_VOICES := 8
const DEFAULT_FADE := 1.2
const SILENT_DB := -60.0
const AMBIENCE_DB := -10.0

## False keeps every player silent while the cues are still tracked. A
## headless run (CI, the smoke test) has nobody to listen, and a stream that is
## playing when the engine quits is reported as a leaked resource.
var enabled := true
var current_music: StringName = &""
var current_ambience: StringName = &""

var _streams: Dictionary = {}
var _music_players: Array[AudioStreamPlayer] = []
var _active_music := 0
var _ambience_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music_tween: Tween
var _ambience_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.get_name() != "headless"
	for index: int in 2:
		_music_players.append(_add_player("Music%d" % index, MUSIC_BUS))
	_ambience_player = _add_player("Ambience", SFX_BUS)
	for index: int in SFX_VOICES:
		_sfx_players.append(_add_player("Sfx%d" % index, SFX_BUS))
	SceneRouter.scene_changed.connect(_on_scene_changed)
	get_tree().node_added.connect(_on_node_added)
	# Autoloads created before this one (the pause menu) already have buttons.
	for node: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(node)
	GameState.crop_planted.connect(play_sfx.bind(&"plant").unbind(1))
	GameState.crop_harvested.connect(play_sfx.bind(&"harvest").unbind(2))
	GameState.produce_sold.connect(play_sfx.bind(&"coin").unbind(3))
	Economy.offer_purchased.connect(play_sfx.bind(&"coin").unbind(2))
	Campaign.task_status_changed.connect(_on_task_status_changed)
	Campaign.setback_recorded.connect(play_sfx.bind(&"caught").unbind(2))
	# The boot scene is loaded by the engine, not by the router.
	_apply_scene_audio.call_deferred()


## Streams are cached for the session; letting go of them before the engine
## shuts down keeps the exit log free of "resources still in use".
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _music_players + _sfx_players + [_ambience_player]:
		player.stop()
		player.stream = null
	_streams.clear()


func has_cue(cue: StringName) -> bool:
	return SFX_CUES.has(cue) or AMBIENCE_CUES.has(cue) or MUSIC_TRACKS.has(cue)


## Plays a one-shot effect on the next free voice. `pitch_spread` detunes each
## play a little so a repeated sound (footsteps) does not drill into the ear.
func play_sfx(cue: StringName, volume_db := 0.0, pitch_spread := 0.0) -> bool:
	if not SFX_CUES.has(cue):
		push_warning("Audio: unknown sound effect '%s'." % cue)
		return false
	var stream := _stream(SFX_DIR, cue)
	if stream == null:
		return false
	var player := _sfx_players[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	if enabled:
		player.play()
	return true


## Crossfades to `track`. An empty name fades the music out.
func play_music(track: StringName, fade := DEFAULT_FADE) -> bool:
	if track == current_music:
		return true
	if track != &"" and not MUSIC_TRACKS.has(track):
		push_warning("Audio: unknown music track '%s'." % track)
		return false
	var stream: AudioStream = null
	if track != &"":
		stream = _stream(MUSIC_DIR, track, true)
		if stream == null:
			return false
	var previous := _music_players[_active_music]
	_active_music = 1 - _active_music
	var next := _music_players[_active_music]
	current_music = track
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	if stream != null:
		next.stream = stream
		next.volume_db = SILENT_DB
		if enabled:
			next.play()
	if fade <= 0.0:
		# A cut, not a fade: nothing is left for a later frame.
		previous.stop()
		next.volume_db = 0.0
	else:
		_music_tween = create_tween().set_parallel(true)
		_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_music_tween.tween_property(previous, "volume_db", SILENT_DB, fade)
		if stream != null:
			_music_tween.tween_property(next, "volume_db", 0.0, fade)
		_music_tween.chain().tween_callback(previous.stop)
	music_changed.emit(track)
	return true


func stop_music(fade := DEFAULT_FADE) -> void:
	play_music(&"", fade)


## Starts a looping background sound. An empty name fades it out.
func play_ambience(cue: StringName, fade := DEFAULT_FADE) -> bool:
	if cue == current_ambience:
		return true
	if cue != &"" and not AMBIENCE_CUES.has(cue):
		push_warning("Audio: unknown ambience '%s'." % cue)
		return false
	var stream: AudioStream = null
	if cue != &"":
		stream = _stream(SFX_DIR, cue, true)
		if stream == null:
			return false
	current_ambience = cue
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if stream != null:
		_ambience_player.stream = stream
		_ambience_player.volume_db = SILENT_DB
		if enabled:
			_ambience_player.play()
	if fade <= 0.0:
		if stream == null:
			_ambience_player.stop()
		else:
			_ambience_player.volume_db = AMBIENCE_DB
		return true
	_ambience_tween = create_tween()
	_ambience_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if stream == null:
		_ambience_tween.tween_property(_ambience_player, "volume_db", SILENT_DB, fade)
		_ambience_tween.tween_callback(_ambience_player.stop)
	else:
		_ambience_tween.tween_property(_ambience_player, "volume_db", AMBIENCE_DB, fade)
	return true


func stop_ambience(fade := DEFAULT_FADE) -> void:
	play_ambience(&"", fade)


## What a scene file plays: `{"music": …, "ambience": …}`, both possibly empty.
func audio_for_scene(scene_path: String) -> Dictionary:
	var entry: Dictionary = SCENE_AUDIO.get(scene_path.get_file(), {})
	return {
		"music": entry.get("music", &""),
		"ambience": entry.get("ambience", &""),
	}


func _apply_scene_audio() -> void:
	var scene := get_tree().current_scene
	var plan := audio_for_scene(scene.scene_file_path if scene != null else "")
	play_music(plan["music"])
	play_ambience(plan["ambience"])


func _on_scene_changed(_scene: Node) -> void:
	_apply_scene_audio()


func _on_task_status_changed(_map_id: int, _task_id: String, status: int) -> void:
	if status == Campaign.TaskStatus.DONE:
		play_sfx(&"task_done")


## Every button of the game clicks, wherever it is created.
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.focus_entered.connect(play_sfx.bind(&"ui_move", -8.0))
	button.pressed.connect(play_sfx.bind(&"ui_accept", -4.0))


func _add_player(player_name: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus
	add_child(player)
	return player


func _stream(directory: String, cue: StringName, loop := false) -> AudioStream:
	var path := "%s%s.wav" % [directory, cue]
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		push_warning("Audio: missing file %s." % path)
		return null
	var stream := load(path) as AudioStream
	var wav := stream as AudioStreamWAV
	if loop and wav != null:
		# Set here rather than in the .import file, so a regenerated or replaced
		# WAV loops without anyone remembering an import option.
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_streams[path] = stream
	return stream
