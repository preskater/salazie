# Audio

Technical reference for music, ambience and sound effects.

- Autoload: `Audio` (`scripts/systems/audio/audio.gd`)
- Files: `audio/music/*.wav`, `audio/sfx/*.wav` (22050 Hz, mono, 16-bit)
- Buses: `Master` → `Music`, `SFX` (`audio/default_bus_layout.tres`); volumes belong to
  `Settings` and the options screen
- Generator: `tools/audio/generate_audio.py`

## Status: placeholders

Every sound in the repository is **synthesised by `tools/audio/generate_audio.py`** with
the Python standard library: sine, triangle and plucked tones with envelopes, filtered noise
and a seeded random-walk melody over a chord loop. Nothing is sampled or downloaded, so the
files are original to the project and carry no third-party licence. Running the script again
rewrites them byte for byte.

They exist so the game is not silent and so every cue is wired and tested. They were
checked for level, clipping and loop continuity, **not by ear**: treat the music in
particular as a stand-in. To replace a sound, drop a WAV of the same name in the same
folder; nothing else changes. Record the source and licence of any replacement in this
file.

## Cues

| Cue | Played when | Triggered from |
|---|---|---|
| `step` | every stride while walking or running | `player.gd` |
| `pickup` | a forage spot is taken | `forage_spot.gd` |
| `drink` | the player drinks at a bank | `maroon_map.gd` |
| `alert` | a guard enters the alert state | `guard.gd` |
| `caught` | a setback is recorded (catch, collapse) | `Campaign.setback_recorded` |
| `plant` / `harvest` | a crop is planted / harvested | `GameState` signals |
| `coin` | produce is sold, an offer is bought | `GameState.produce_sold`, `Economy.offer_purchased` |
| `task_done` | a task becomes done | `Campaign.task_status_changed` |
| `ui_move` / `ui_accept` | a button takes focus / is pressed | every `BaseButton`, connected as it enters the tree |
| `ui_cancel` | reserved for back actions | not wired yet |

| Ambience | Where |
|---|---|
| `river` | Map 1, for the whole map |
| `wind` | Map 2, while the cyclone crosses the farm |

| Music | Scene |
|---|---|
| `menu` | main menu |
| `maroon` / `farm` / `heir` | the three maps |
| `ending` | epilogue |

Music and scene ambience follow `SceneRouter.scene_changed` through `Audio.SCENE_AUDIO`,
keyed by scene file name. A scene that is not listed is silent.

## API

```gdscript
Audio.play_sfx(&"pickup")                 # one-shot on the next of 8 voices
Audio.play_sfx(&"step", -14.0, 0.12)      # volume in dB, random pitch spread
Audio.play_music(&"farm")                 # crossfade, 1.2 s by default
Audio.stop_music()
Audio.play_ambience(&"wind")
Audio.stop_ambience()
```

Unknown names are refused with a warning and return `false`. Loops are flagged on the
loaded `AudioStreamWAV` at runtime rather than in the `.import` file, so a replaced file
loops without an import option to remember.

Most effects are connected inside `Audio` from the signals of the other autoloads; gameplay
scripts only call it where no signal exists (steps, pickup, drink, alert, wind).

## Headless runs

`Audio.enabled` is false under the headless display server: cues are tracked
(`current_music`, `current_ambience`) but no player starts. Nobody is listening in CI, and
a stream still playing when the engine quits is reported as a leaked resource. The audio
tests set `enabled = true`.

## Adding a sound

1. Add a recipe to `build_sfx()` or `build_music()` in the generator, or drop a WAV file.
2. Add the name to `SFX_CUES`, `AMBIENCE_CUES` or `MUSIC_TRACKS` in `audio.gd`.
3. Run `python3 tools/audio/generate_audio.py`, then `godot --headless --import`, and commit
   the WAV with its `.import` file.
4. `tests/unit/test_audio.gd` fails if a registered cue has no file.
