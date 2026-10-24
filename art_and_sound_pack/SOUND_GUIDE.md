# Evac Grid: Sound Guide

For whoever makes or finds the music and sound effects. **The audio assets have been collected, but the game has no audio playback yet.** Everything below describes the plan and current asset status.

---

# Part 1: The vibe (read this first)

## One-line feel
> **A calm, focused rescue operator in a control room, with the clock ticking.**

You are not a soldier. You sit at a tablet and guide people to safety. The sound should make the player feel **professional, under pressure, but in control**, until a fire breaks that calm.

## References
- **Keep Talking and Nobody Explodes:** tactile clicks, beeps, a ticking clock, and sound that tells you instantly if you did something right or wrong.
- **Dispatch / emergency radio:** short radio blips, squelch, quiet static.
- **Control-room tablets:** soft, clean UI sounds, not toy-like or cartoonish.

## Mood by moment
| Moment | Feel | Music / sound idea |
|---|---|---|
| Planning (no fire) | Calm, focused, a little tense | Low, slow synth pad, soft pulse. Barely noticeable |
| Fire appears | Sudden alarm, adrenaline | Short sharp alarm, music gets faster or louder |
| Rerouting under pressure | Urgent but not panicked | Faster pulse, ticking clock stands out |
| Team reaches safety | Relief, small victory | Warm, rising chime |
| People lost | Heavy, sad, quiet | Low dull thud, music dips for a second |
| Round complete | Satisfying, rewarding | Short bright jingle, no long fanfare |
| Round failed | Disappointed, not punishing | Short low sting, "try again" feel |

## Style words
- **Use:** clean, digital, electronic, tactile, crisp, tense, low synth, soft radio, mechanical clicks.
- **Avoid:** cartoon, funny, orchestral epic, heavy metal, 8-bit chiptune, loud explosions, screaming, gore.

## Rules of thumb
1. **Short and clear.** Most effects under 1 second. The player hears one every few seconds, so they must not annoy.
2. **Meaning by pitch.** Going up = good (select, saved, success). Going down = bad (blocked, lost, fail).
3. **Alarms are the loudest thing in the game.** Everything else is quieter, so a fire always stands out.
4. **Quiet in the background.** Music is under the effects. Players should be able to talk while playing.
5. **No harsh sounds.** Nothing piercing. Players may play for a long time.
6. **Consistent.** All sounds should sound like they come from the same tablet and the same radio system.

---

# Part 2: Sound effects list (SFX)

Format: `.wav`, 44.1 kHz, 16-bit, mono for short effects. Name files in lowercase with underscores, e.g. `sfx_dispatch.wav`.
Priority: **P1** = must have, **P2** = should have, **P3** = nice to have.

## Controls and interface
| File name | P | When it plays | Length | Feel |
|---|---|---|---|---|
| `sfx_select_team` | P1 | Player picks a team | 0.15 s | Soft rising "blip", like a radio ping |
| `sfx_route_tick` | P1 | Each tile added to the route | 0.08 s | Tiny tactile tick. Pitch can rise a little with route length |
| `sfx_invalid` | P1 | Tapping a fire, building or closed road | 0.25 s | Low, dull buzz (like a wrong answer in KTANE) |
| `sfx_dispatch` | P1 | Pressing DISPATCH | 0.6 s | Radio "roger": click, short beep-beep, squelch end |
| `sfx_undo` | P2 | Undo | 0.12 s | Soft backward click |
| `sfx_clear` | P2 | Clear | 0.2 s | Quick sweep or wipe |
| `sfx_detour_dispatch` | P2 | Dispatching a detour after a fire | 0.6 s | Like the dispatch sound but faster and sharper |
| `sfx_button_hover` | P3 | Mouse over a button | 0.05 s | Very faint tick |
| `sfx_help_toggle` | P3 | Opening or closing the help box | 0.15 s | Soft slide |
| `sfx_tablet_on` | P3 | Game start | 1 s | Power-on beep and a soft rising hum |

## Hazards and alerts
| File name | P | When it plays | Length | Feel |
|---|---|---|---|---|
| `sfx_fire_start` | P1 | A new fire starts | 1 s | Whoosh plus a short alarm beep |
| `sfx_alert_blocked` | P1 | A moving team is stopped by fire | 1.5 s | Urgent two-tone siren, repeats once. The loudest sound in the game |
| `sfx_fire_loop` | P2 | While any fire is on the map | loop | Very quiet crackle, a background texture |
| `sfx_casualty` | P2 | A person is lost in smoke | 0.6 s | Low dull thud and a short sad tone |
| `sfx_plan_warning` | P2 | Plan clock bonus nearly gone | 0.3 s | Single clock tick, one per second |
| `sfx_radio_static` | P3 | Alert arrives | 0.5 s | Short radio squelch before the alarm |

## Movement and results
| File name | P | When it plays | Length | Feel |
|---|---|---|---|---|
| `sfx_footsteps_loop` | P2 | A team is moving | loop | Soft, fast footsteps. Only one loop at a time, even with several teams |
| `sfx_team_safe` | P1 | A team reaches the safe zone | 1 s | Warm rising chime, 3 notes going up |
| `sfx_round_complete` | P1 | Results card, success | 2 s | Bright short jingle |
| `sfx_round_failed` | P1 | Results card, failure | 1.5 s | Low, short sting that fades out |
| `sfx_score_tick` | P2 | Score numbers counting up | 0.05 s | Tiny tick, repeated quickly |
| `sfx_star_on` | P2 | Each rating light turns on | 0.4 s | Sparkle with rising pitch, higher for each star |
| `sfx_next_round` | P2 | Pressing NEXT ROUND or TRY AGAIN | 0.3 s | Confirm click, like dispatch but shorter |

## SFX asset status

All 23 planned SFX are present in `res://assets/audio/`. The extensions are preserved from the source files, and Godot can import all of these formats.

| Status | Sound guide name | Project file |
|---|---|---|
| [x] | `sfx_select_team` | `sfx_select_team.ogg` |
| [x] | `sfx_route_tick` | `sfx_route_tick.ogg` |
| [x] | `sfx_invalid` | `sfx_invalid.ogg` |
| [x] | `sfx_dispatch` | `sfx_dispatch.ogg` |
| [x] | `sfx_undo` | `sfx_undo.ogg` |
| [x] | `sfx_clear` | `sfx_clear.ogg` |
| [x] | `sfx_detour_dispatch` | `sfx_detour_dispatch.ogg` |
| [x] | `sfx_button_hover` | `sfx_button_hover.ogg` |
| [x] | `sfx_help_toggle` | `sfx_help_toggle.ogg` |
| [x] | `sfx_tablet_on` | `sfx_tablet_on.ogg` |
| [x] | `sfx_fire_start` | `sfx_fire_start.ogg` |
| [x] | `sfx_alert_blocked` | `sfx_alert_blocked.ogg` |
| [x] | `sfx_fire_loop` | `sfx_fire_loop.wav` |
| [x] | `sfx_casualty` | `sfx_casualty.ogg` |
| [x] | `sfx_plan_warning` | `sfx_plan_warning.ogg` |
| [x] | `sfx_radio_static` | `sfx_radio_static.wav` |
| [x] | `sfx_footsteps_loop` | `sfx_footsteps_loop.wav` |
| [x] | `sfx_team_safe` | `sfx_team_safe.ogg` |
| [x] | `sfx_round_complete` | `sfx_round_complete.ogg` |
| [x] | `sfx_round_failed` | `sfx_round_failed.ogg` |
| [x] | `sfx_score_tick` | `sfx_score_tick.ogg` |
| [x] | `sfx_star_on` | `sfx_star_on.ogg` |
| [x] | `sfx_next_round` | `sfx_next_round.ogg` |

## Voice lines (optional, P3)
Short, calm, radio-filtered voice. Text-to-speech is fine if it is run through a radio filter.
- "Fire reported."
- "Route blocked. Draw a detour."
- "Team A is safe."
- "All teams accounted for."

---

# Part 3: Music

Format: `.ogg`, 44.1 kHz stereo, seamless loop. Name: `music_calm.ogg`, `music_tense.ogg`, etc.

| Track | P | Used when | Tempo | Length | Description |
|---|---|---|---|---|---|
| `music_calm` | P2 | Menu, planning, early rounds | 70 to 85 BPM | 1.5 to 2 min loop | Low synth pad, soft pulse, sparse notes. Calm control-room feeling |
| `music_tense` | P2 | When fires are active, later rounds | 110 to 130 BPM | 1.5 to 2 min loop | Same sounds as calm but faster, with a ticking clock element and a deeper bass |
| `music_result_win` | P3 | Results card | n/a | 6 to 8 s | Short warm resolve of the calm theme |
| `music_result_fail` | P3 | Results card | n/a | 6 to 8 s | Short, low and unresolved |

## Music asset status

All four planned music assets are present in `res://assets/audio/`. The calm, tense, and win tracks retain their source formats; convert them to `.ogg` if strict guide-format compliance is required.

| Status | Sound guide name | Project file |
|---|---|---|
| [x] | `music_calm` | `music_calm.mp3` |
| [x] | `music_tense` | `music_tense.wav` |
| [x] | `music_result_win` | `music_result_win.wav` |
| [x] | `music_result_fail` | `music_result_fail.ogg` |

Switching: fade from calm to tense over about 2 seconds when the first fire starts. Go back to calm when no group is blocked.

---

# Part 4: Mix levels (so nothing is too loud)

Peak targets, roughly, relative to the loudest sound:

| Group | Level |
|---|---|
| Alarms (`sfx_alert_blocked`, `sfx_fire_start`) | 0 dB (the loudest) |
| Result jingles, team safe | -3 dB |
| Dispatch, casualty | -6 dB |
| Interface clicks (select, tick, undo) | -10 dB |
| Loops (fire, footsteps) | -18 dB |
| Music | -15 to -20 dB |

Also normalise every file so none is accidentally much louder, and trim silence at the start so the sound plays instantly.

---

# Part 5: Technical notes (for whoever hooks the audio in)

- Create 3 audio buses in Godot: `Master`, `Music`, `SFX`. Add volume sliders and a mute button.
- Limit overlapping sounds. Footsteps and fire crackle should each be one loop at a time.
- Good hook points in `scripts/game.gd`:
  - `_select_group`: select team
  - `_try_extend`: route tick and invalid
  - `_dispatch`: dispatch and detour
  - `_undo` / `_clear_route`: undo and clear
  - `_on_hazard`: fire start
  - `_on_group_event`: "halted" (blocked alert), "casualty", "delivered" (team safe)
  - `_show_results`: complete or failed jingle, score ticks, stars
- A small autoload `Audio.play("sfx_dispatch")` keeps this tidy.

## Where to find sounds (check each licence and credit it)
- freesound.org (check CC0 or CC-BY)
- kenney.nl (CC0 UI and interface sound packs)
- opengameart.org
- pixabay.com (music and effects)

Keep a `CREDITS.md` listing every file, its author, its source link and its licence.

---

# Checklist

- [x] All P1 sound effects (9)
- [x] All P2 sound effects
- [x] All P3 sound effects
- [x] `music_calm`, `music_tense`, `music_result_win`, and `music_result_fail`
- [ ] Levels normalised as in Part 4
- [ ] `CREDITS.md`
- [ ] Hook-up in `game.gd`, with volume settings
- [ ] Optional voice lines
