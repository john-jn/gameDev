# Audio Update

Changes to the audio setup described in [AUDIO_SETUP.md](AUDIO_SETUP.md). Where the two disagree, this file wins.

## Summary

1. **Music by screen:** calm music plays only on the main menu. Tense music plays during gameplay, starting when the player presses **START DISPATCH** or **TUTORIAL**.
2. **Quieter sound effects:** all sound effects play at 80% of their current volume (20% lower).
3. **Fewer sound effects:** the 8 unused sound effects are removed from the audio manager for now.

Files to change: `scripts/audio_manager.gd` and `scripts/game.gd`.

## 1. Music by screen

### Target behaviour

| Screen / moment | Music | Already true? |
| --- | --- | --- |
| Game boots to the main menu | `calm` | Yes (`audio_manager.gd` `_start_default_music()` and `game.gd` `_show_main_menu()`) |
| Main menu, settings panel, tutorial offer pop-up | `calm` | Yes |
| **START DISPATCH** pressed → round starts | `tense` | **No, currently `calm`** |
| **TUTORIAL** pressed → practice round starts | `tense` | **No, currently `calm`** |
| Tutorial finished → **START GAME** | `tense` (keeps playing, no restart) | Follows from the change |
| Round ends, including settings → **End game** | `win` or `fail` stinger | Yes (`_end_round()`) |
| **Next round** / **Try again** from the results screen | `tense` | **No, currently `calm`** |
| Back to the main menu (results screen **Main menu**, leaving the tutorial) | `calm` | Yes (both go through `_show_main_menu()`) |

### Why one change covers it

All three gameplay entry points call `_start_round()` in `scripts/game.gd`:

- `_on_start_game_pressed()`: the **START DISPATCH** button
- `_start_tutorial()`: the **TUTORIAL** button
- `_on_next_pressed()`: Next round / Try again, including `_on_no_route_next_pressed()`

`_start_round()` currently calls `Audio.play_music("calm")`. Change that one call:

```gdscript
# scripts/game.gd, in _start_round()
Audio.play_music("tense")
```

Leave the `Audio.play_music("calm")` in `_show_main_menu()` as it is.

`Audio.play_music()` returns early when the same track is already playing. So when the tutorial hands off to a real game, the tense music carries on without restarting. After a win/fail stinger, the next round starts tense from the beginning again.

`music_tense.wav` is already set to loop (Loop Mode **Forward**), so no import change is needed.

## 2. Sound effects at 80% volume

### Why not the bus or the slider

Use a gain inside the audio manager. Neither of the obvious alternatives works:

- **The SFX bus volume in the Audio tab:** `game.gd` `_load_volume()` overwrites every bus volume at startup from the saved settings (slider default 100% → 0 dB). Values set in `default_bus_layout.tres` never reach the player.
- **Lowering the SFX slider's default:** players who already have saved settings would not get the change.

### Change

In `scripts/audio_manager.gd`, add a level constant next to the other constants:

```gdscript
const SFX_LEVEL := 0.8  # all sound effects play at 80% of their file volume (about -1.9 dB)
```

Apply it in both places that start a sound effect:

```gdscript
# play_sfx(): replace `player.volume_db = volume_db`
player.volume_db = linear_to_db(SFX_LEVEL) + volume_db

# play_loop(): set this before player.play()
player.volume_db = linear_to_db(SFX_LEVEL)
```

This covers every sound effect:

- one-shots called from `game.gd`
- the automatic button-hover sound (it goes through `play_sfx`)
- the fire and footsteps loops

The SFX slider still works on top of this: at 100% the player hears 80% of the original level, and at 50% they hear 40%.

Music is not affected.

To fine-tune later, change only `SFX_LEVEL` (for example `0.7` for quieter, `0.9` for louder).

## 3. Remove the 8 unused sound effects for now

Delete these entries from the `SFX` dictionary in `scripts/audio_manager.gd`:

| Key | File |
| --- | --- |
| `alert_blocked` | `sfx_alert_blocked.ogg` |
| `help_toggle` | `sfx_help_toggle.ogg` |
| `next_round` | `sfx_next_round.ogg` |
| `plan_warning` | `sfx_plan_warning.ogg` |
| `radio_static` | `sfx_radio_static.wav` |
| `route_tick` | `sfx_route_tick.ogg` |
| `score_tick` | `sfx_score_tick.ogg` |
| `star_on` | `sfx_star_on.ogg` |

- Keep the audio files in `assets/audio/` so they can be added back later.
- Nothing in `game.gd` or `tutorial.gd` calls these keys today, so removing them breaks nothing.
- Add a short comment above `SFX` listing the removed keys, so whoever adds them back knows they exist.

The remaining 15 sound effects stay as they are:

`button_hover`, `casualty`, `clear`, `detour_dispatch`, `dispatch`, `fire_loop`, `fire_start`, `footsteps_loop`, `invalid`, `round_complete`, `round_failed`, `select_team`, `tablet_on`, `team_safe`, `undo`.

## Out of scope

- Do not edit `default_bus_layout.tres`. It has uncommitted local edits from the user, and its bus volumes are overwritten at startup anyway.
- Do not change the volume sliders, the settings file format, or the win/fail stingers.
- Do not touch the unused audio data embedded in `scenes/main.tscn`. That is a separate cleanup.
- Known separate bug, not part of this change: the tutorial's final **START GAME** button may not start a real round. `tutorial._on_play()` calls `_on_start_game_pressed()`, which returns early because `game_started` is still `true` from the practice round. The music is correct either way (tense keeps playing). Report it, but don't fix it here.

## How to check it

1. Launch the game. The main menu plays calm music.
2. Press **START DISPATCH**. The music fades over 0.5 s from calm to tense.
3. Finish or fail the round. The win/fail stinger plays.
4. Press **Next round** or **Try again**. Tense music starts again.
5. Return to the main menu. The music fades back to calm.
6. Press **TUTORIAL**. Tense music plays. Finish the tutorial and press **START GAME**. Tense music keeps playing without restarting.
7. Sound effects (button hover, dispatch, undo, fire loop) are slightly quieter than before. The SFX slider in settings still raises and lowers them.
8. The Output panel shows no `Unknown SFX key` or `Unknown music key` errors.
9. Run the existing tests in `tests/` and confirm they still pass.
