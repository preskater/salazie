extends GdUnitTestSuite
## Music, ambience and sound effects (#28).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MENU_SCENES: Array[String] = [
	"res://scenes/ui/menus/main_menu.tscn",
	"res://scenes/maps/maroon.tscn",
	"res://scenes/maps/farm.tscn",
	"res://scenes/maps/heir.tscn",
	"res://scenes/ui/ending/ending_screen.tscn",
]


func before_test() -> void:
	# The runner is headless, where Audio stays silent unless asked.
	Audio.enabled = true
	Audio.play_music(&"", 0.0)
	Audio.play_ambience(&"", 0.0)


func after_test() -> void:
	Audio.play_music(&"", 0.0)
	Audio.play_ambience(&"", 0.0)
	for index: int in Audio.SFX_VOICES:
		(Audio.get_node("Sfx%d" % index) as AudioStreamPlayer).stop()
	Audio.enabled = false
	Campaign.reset()
	GameState.reset()


func _music_players() -> Array:
	return [Audio.get_node("Music0"), Audio.get_node("Music1")]


func _playing_voices() -> int:
	var count := 0
	for index: int in Audio.SFX_VOICES:
		if (Audio.get_node("Sfx%d" % index) as AudioStreamPlayer).playing:
			count += 1
	return count


# --- Registry ----------------------------------------------------------------

func test_every_cue_has_a_file() -> void:
	for cue: StringName in Audio.SFX_CUES + Audio.AMBIENCE_CUES:
		assert_bool(ResourceLoader.exists(Audio.SFX_DIR + cue + ".wav")).override_failure_message(
			"No file for sound '%s'" % cue).is_true()
		assert_bool(Audio.has_cue(cue)).is_true()
	for track: StringName in Audio.MUSIC_TRACKS:
		assert_bool(ResourceLoader.exists(Audio.MUSIC_DIR + track + ".wav")).override_failure_message(
			"No file for track '%s'" % track).is_true()
	assert_bool(Audio.has_cue(&"kazoo")).is_false()


func test_players_sit_on_the_buses_the_settings_drive() -> void:
	for bus: StringName in [Audio.MUSIC_BUS, Audio.SFX_BUS]:
		assert_int(AudioServer.get_bus_index(bus)).override_failure_message(
			"Bus %s is missing from the layout" % bus).is_greater_equal(0)
	for player: AudioStreamPlayer in _music_players():
		assert_str(String(player.bus)).is_equal(String(Audio.MUSIC_BUS))
	assert_str(String((Audio.get_node("Ambience") as AudioStreamPlayer).bus)) \
		.is_equal(String(Audio.SFX_BUS))
	assert_str(String((Audio.get_node("Sfx0") as AudioStreamPlayer).bus)) \
		.is_equal(String(Audio.SFX_BUS))
	assert_int(Audio.process_mode).is_equal(Node.PROCESS_MODE_ALWAYS)


func test_every_playable_scene_has_its_own_music() -> void:
	var seen := {}
	for scene_path: String in MENU_SCENES:
		var plan := Audio.audio_for_scene(scene_path)
		assert_bool(Audio.MUSIC_TRACKS.has(plan["music"])).override_failure_message(
			"%s has no music" % scene_path).is_true()
		seen[plan["music"]] = true
	assert_int(seen.size()).is_equal(MENU_SCENES.size())
	assert_str(String(Audio.audio_for_scene("res://scenes/maps/maroon.tscn")["ambience"])) \
		.is_equal("river")
	var silent := Audio.audio_for_scene("res://scenes/samples/main.tscn")
	assert_str(String(silent["music"])).is_empty()
	assert_str(String(silent["ambience"])).is_empty()


# --- Sound effects -------------------------------------------------------------

func test_a_sound_effect_plays_on_a_free_voice() -> void:
	assert_bool(Audio.play_sfx(&"pickup", -3.0)).is_true()

	var player: AudioStreamPlayer = null
	for index: int in Audio.SFX_VOICES:
		var candidate := Audio.get_node("Sfx%d" % index) as AudioStreamPlayer
		if candidate.playing and candidate.volume_db == -3.0:
			player = candidate
	assert_object(player).is_not_null()
	assert_object(player.stream).is_not_null()
	assert_float(player.pitch_scale).is_equal(1.0)


func test_voices_are_reused_in_turn() -> void:
	for index: int in Audio.SFX_VOICES + 3:
		assert_bool(Audio.play_sfx(&"ui_move")).is_true()

	assert_int(_playing_voices()).is_less_equal(Audio.SFX_VOICES)


func test_pitch_spread_stays_within_its_bounds() -> void:
	for index: int in 20:
		Audio.play_sfx(&"step", 0.0, 0.1)
		for voice: int in Audio.SFX_VOICES:
			var pitch := (Audio.get_node("Sfx%d" % voice) as AudioStreamPlayer).pitch_scale
			assert_float(pitch).is_between(0.9, 1.1)


func test_an_unknown_effect_is_refused_without_crashing() -> void:
	assert_bool(Audio.play_sfx(&"kazoo")).is_false()
	# A looping ambience is not a one-shot effect.
	assert_bool(Audio.play_sfx(&"river")).is_false()


# --- Music -------------------------------------------------------------------

func test_music_changes_track_and_loops() -> void:
	var changes: Array[StringName] = []
	var listener := func(track: StringName) -> void: changes.append(track)
	Audio.music_changed.connect(listener)

	assert_bool(Audio.play_music(&"farm", 0.0)).is_true()
	assert_bool(Audio.play_music(&"farm", 0.0)).is_true()
	assert_bool(Audio.play_music(&"heir", 0.0)).is_true()

	Audio.music_changed.disconnect(listener)
	assert_array(changes).is_equal([&"farm", &"heir"])
	assert_str(String(Audio.current_music)).is_equal("heir")
	var playing: Array = _music_players().filter(
		func(player: AudioStreamPlayer) -> bool: return player.stream != null and player.playing)
	assert_int(playing.size()).is_greater_equal(1)
	var stream := (playing[-1] as AudioStreamPlayer).stream as AudioStreamWAV
	assert_int(stream.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(stream.loop_end).is_greater(0)


func test_stopping_the_music_silences_both_players() -> void:
	Audio.play_music(&"menu", 0.0)

	Audio.stop_music(0.0)

	assert_str(String(Audio.current_music)).is_empty()
	for player: AudioStreamPlayer in _music_players():
		assert_bool(player.playing).is_false()


func test_a_crossfade_ends_on_the_new_track_alone() -> void:
	Audio.play_music(&"menu", 0.0)

	Audio.play_music(&"farm", 0.05)
	assert_int(_music_players().filter(
		func(player: AudioStreamPlayer) -> bool: return player.playing).size()).is_equal(2)
	await get_tree().create_timer(0.2).timeout

	var playing: Array = _music_players().filter(
		func(player: AudioStreamPlayer) -> bool: return player.playing)
	assert_int(playing.size()).is_equal(1)
	assert_float((playing[0] as AudioStreamPlayer).volume_db).is_equal_approx(0.0, 0.01)

	Audio.stop_music(0.05)
	Audio.play_ambience(&"river", 0.05)
	await get_tree().create_timer(0.2).timeout
	assert_int(_music_players().filter(
		func(player: AudioStreamPlayer) -> bool: return player.playing).size()).is_equal(0)
	assert_float((Audio.get_node("Ambience") as AudioStreamPlayer).volume_db) \
		.is_equal_approx(Audio.AMBIENCE_DB, 0.01)
	Audio.stop_ambience(0.05)
	await get_tree().create_timer(0.2).timeout
	assert_bool((Audio.get_node("Ambience") as AudioStreamPlayer).playing).is_false()


func test_an_unknown_track_keeps_the_current_one() -> void:
	Audio.play_music(&"menu", 0.0)

	assert_bool(Audio.play_music(&"polka", 0.0)).is_false()

	assert_str(String(Audio.current_music)).is_equal("menu")


func test_ambience_starts_loops_and_stops() -> void:
	var ambience := Audio.get_node("Ambience") as AudioStreamPlayer

	assert_bool(Audio.play_ambience(&"wind", 0.0)).is_true()
	assert_bool(Audio.play_ambience(&"wind", 0.0)).is_true()
	assert_str(String(Audio.current_ambience)).is_equal("wind")
	assert_bool(ambience.playing).is_true()
	assert_int((ambience.stream as AudioStreamWAV).loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)

	assert_bool(Audio.play_ambience(&"storm", 0.0)).is_false()
	assert_str(String(Audio.current_ambience)).is_equal("wind")

	Audio.stop_ambience(0.0)
	assert_str(String(Audio.current_ambience)).is_empty()
	assert_bool(ambience.playing).is_false()


func test_a_scene_change_switches_music_and_ambience() -> void:
	# The runner's own scene is not a game scene, so it must go silent.
	Audio.play_music(&"farm", 0.0)
	Audio.play_ambience(&"river", 0.0)

	SceneRouter.scene_changed.emit(get_tree().current_scene)

	assert_str(String(Audio.current_music)).is_empty()
	assert_str(String(Audio.current_ambience)).is_empty()


# --- Wiring ------------------------------------------------------------------

func test_buttons_click_wherever_they_are_created() -> void:
	var button: Button = auto_free(Button.new())
	add_child(button)

	assert_bool(button.pressed.get_connections().any(
		func(entry: Dictionary) -> bool: return entry["callable"].get_object() == Audio)).is_true()
	assert_bool(button.focus_entered.get_connections().any(
		func(entry: Dictionary) -> bool: return entry["callable"].get_object() == Audio)).is_true()

	var label: Label = auto_free(Label.new())
	add_child(label)
	button.pressed.emit()
	assert_int(_playing_voices()).is_greater_equal(1)


func test_farm_and_campaign_events_are_heard() -> void:
	for emit: Callable in [
		func() -> void: GameState.crop_planted.emit("corn"),
		func() -> void: GameState.crop_harvested.emit("corn", 1),
		func() -> void: GameState.produce_sold.emit("corn", 1, 10),
		func() -> void: Campaign.record_setback("Repéré", 1),
		func() -> void: Campaign.complete_task("follow_river", 1),
	]:
		for index: int in Audio.SFX_VOICES:
			(Audio.get_node("Sfx%d" % index) as AudioStreamPlayer).stop()
		emit.call()
		assert_int(_playing_voices()).is_equal(1)

	# A failed task has no fanfare.
	for index: int in Audio.SFX_VOICES:
		(Audio.get_node("Sfx%d" % index) as AudioStreamPlayer).stop()
	Campaign.fail_task("earn_100", "trop tard", 2)
	assert_int(_playing_voices()).is_equal(0)


func test_footsteps_follow_the_stride() -> void:
	var player: CharacterBody2D = auto_free(PLAYER_SCENE.instantiate())
	add_child(player)
	player.set_physics_process(false)
	for index: int in Audio.SFX_VOICES:
		(Audio.get_node("Sfx%d" % index) as AudioStreamPlayer).stop()

	player._tick_steps(0.1, false)
	assert_int(_playing_voices()).is_equal(0)

	player._tick_steps(0.01, true)
	assert_int(_playing_voices()).is_equal(1)
	player._tick_steps(player.STEP_INTERVAL * 0.5, true)
	assert_int(_playing_voices()).is_equal(1)
	player._tick_steps(player.STEP_INTERVAL * 0.6, true)
	assert_int(_playing_voices()).is_equal(2)

	# Standing still resets the stride: the next step is immediate.
	player._tick_steps(0.01, false)
	player.is_running = true
	player._tick_steps(0.01, true)
	assert_int(_playing_voices()).is_equal(3)


func test_a_silent_run_still_tracks_what_should_play() -> void:
	Audio.enabled = false

	assert_bool(Audio.play_music(&"heir", 0.0)).is_true()
	assert_bool(Audio.play_ambience(&"river", 0.0)).is_true()
	assert_bool(Audio.play_sfx(&"coin")).is_true()

	assert_str(String(Audio.current_music)).is_equal("heir")
	assert_str(String(Audio.current_ambience)).is_equal("river")
	assert_int(_playing_voices()).is_equal(0)
	for player: AudioStreamPlayer in _music_players():
		assert_bool(player.playing).is_false()
	assert_bool((Audio.get_node("Ambience") as AudioStreamPlayer).playing).is_false()
