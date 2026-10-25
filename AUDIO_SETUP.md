# Audio Setup Guide

How to connect the music and sound effects in `assets/audio/` to the game in Godot 4.6.

The approach has three parts:

1. **Audio buses** — separate volume channels for Music and SFX.
2. **An `Audio` autoload** — one global script that owns every player, so any script can call `Audio.play_sfx("dispatch")`.
3. **Import settings** — loop flags on the music and looping SFX.

## Current state of the project

- `default_bus_layout.tres` already has **Music** and **SFX** buses that send to **Master**.
- Bus volumes are low and stack on top of each other: Master is about -25 dB, Music about -20 dB, SFX about -7 dB. Anything on the Music bus plays at roughly -45 dB before the player's own volume is applied.
- `scenes/main.tscn` has three test players:
  - `AudioStreamPlayer`: `music_calm.mp3` on the **Master** bus, `pitch_scale = 0.51`.
  - `AudioStreamPlayer2`: `music_tense.wav` on **Music**, `volume_db = -46.7`, `pitch_scale = 2.74`. Combined with the bus volumes, this is effectively silent.
  - `AudioStreamPlayer3`: on **SFX**, no stream.
- No audio files are set to loop yet.

`pitch_scale` on an `AudioStreamPlayer` changes speed and pitch together. 0.51 plays the track at half speed, an octave lower. Keep it at `1.0` unless that effect is intended.

Once the `Audio` autoload below is in place, delete those three test nodes from `main.tscn` so music does not play twice.

## 1. Set up the buses

Open the **Audio** tab at the bottom of the editor.

1. Set **Master**, **Music** and **SFX** to `0 dB` to start. Balance individual sounds later.
2. Keep both **Music** and **SFX** sending to **Master**.
3. Optional: add effects to one bus only, such as a **LowPassFilter** on Music for a muffled pause menu.

Godot saves this to `default_bus_layout.tres` automatically.

## 2. Set loop flags on import

Music and continuous sounds must loop. Sound effects and the result stingers must not.

1. Select the file in the **FileSystem** dock.
2. Open the **Import** tab, next to the Scene tab.
3. Set the loop option:
   - `.ogg` / `.mp3`: check **Loop**.
   - `.wav`: set **Edit → Loop Mode** to **Forward**.
4. Click **Reimport**.

| File | Loop? |
| --- | --- |
| `music_calm.mp3` | Yes |
| `music_tense.wav` | Yes (Forward) |
| `music_result_win.wav` | No (stinger) |
| `music_result_fail.ogg` | No (stinger) |
| `sfx_fire_loop.wav` | Yes (Forward) |
| `sfx_footsteps_loop.wav` | Yes (Forward) |
| `sfx_radio_static.wav` | Only if you want it continuous |
| All other `sfx_*` | No |

## 3. Create the audio manager

Create `scripts/audio_manager.gd`:

```gdscript
extends Node
## Global audio player. Registered as the "Audio" autoload.

const MUSIC := {
	"calm": preload("res://assets/audio/music_calm.mp3"),
	"tense": preload("res://assets/audio/music_tense.wav"),
	"win": preload("res://assets/audio/music_result_win.wav"),
	"fail": preload("res://assets/audio/music_result_fail.ogg"),
}

# Key = file name without the "sfx_" prefix and extension.
const SFX := {
	"alert_blocked": preload("res://assets/audio/sfx_alert_blocked.ogg"),
	"button_hover": preload("res://assets/audio/sfx_button_hover.ogg"),
	"casualty": preload("res://assets/audio/sfx_casualty.ogg"),
	"clear": preload("res://assets/audio/sfx_clear.ogg"),
	"detour_dispatch": preload("res://assets/audio/sfx_detour_dispatch.ogg"),
	"dispatch": preload("res://assets/audio/sfx_dispatch.ogg"),
	"fire_loop": preload("res://assets/audio/sfx_fire_loop.wav"),
	"fire_start": preload("res://assets/audio/sfx_fire_start.ogg"),
	"footsteps_loop": preload("res://assets/audio/sfx_footsteps_loop.wav"),
	"help_toggle": preload("res://assets/audio/sfx_help_toggle.ogg"),
	"invalid": preload("res://assets/audio/sfx_invalid.ogg"),
	"next_round": preload("res://assets/audio/sfx_next_round.ogg"),
	"plan_warning": preload("res://assets/audio/sfx_plan_warning.ogg"),
	"radio_static": preload("res://assets/audio/sfx_radio_static.wav"),
	"round_complete": preload("res://assets/audio/sfx_round_complete.ogg"),
	"round_failed": preload("res://assets/audio/sfx_round_failed.ogg"),
	"route_tick": preload("res://assets/audio/sfx_route_tick.ogg"),
	"score_tick": preload("res://assets/audio/sfx_score_tick.ogg"),
	"select_team": preload("res://assets/audio/sfx_select_team.ogg"),
	"star_on": preload("res://assets/audio/sfx_star_on.ogg"),
	"tablet_on": preload("res://assets/audio/sfx_tablet_on.ogg"),
	"team_safe": preload("res://assets/audio/sfx_team_safe.ogg"),
	"undo": preload("res://assets/audio/sfx_undo.ogg"),
}

const SFX_VOICES := 8  # how many one-shot SFX can overlap
const SILENT_DB := -40.0

var _music: AudioStreamPlayer
var _music_tween: Tween
var _sfx_pool: Array[AudioStreamPlayer] = []
var _loops := {}  # key -> AudioStreamPlayer


func _ready() -> void:
	# Keep audio running while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _make_player(&"Music")
	for i in SFX_VOICES:
		_sfx_pool.append(_make_player(&"SFX"))


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


# --- Music ---

## Cross-fades to another track. Does nothing if it is already playing.
func play_music(key: String, fade := 0.5) -> void:
	var stream: AudioStream = MUSIC[key]
	if _music.stream == stream and _music.playing:
		return
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", SILENT_DB, fade)
	_music_tween.tween_callback(func():
		_music.stream = stream
		_music.volume_db = SILENT_DB
		_music.play())
	_music_tween.tween_property(_music, "volume_db", 0.0, fade)


func stop_music(fade := 0.5) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", SILENT_DB, fade)
	_music_tween.tween_callback(_music.stop)


# --- One-shot SFX ---

## Plays a sound once. A small random pitch shift keeps repeats from sounding identical.
## volume_db lets one sound be quieter or louder than the rest of the SFX bus.
func play_sfx(key: String, pitch_jitter := 0.05, volume_db := 0.0) -> void:
	for player in _sfx_pool:
		if not player.playing:
			player.stream = SFX[key]
			player.volume_db = volume_db
			player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			player.play()
			return
	# All voices busy: drop the sound rather than cut one off.


# --- Looping SFX ---

## Starts a looping sound such as "fire_loop". Calling it again while it plays does nothing.
func play_loop(key: String) -> void:
	if _loops.has(key):
		return
	var player := _make_player(&"SFX")
	player.stream = SFX[key]
	player.play()
	_loops[key] = player


func stop_loop(key: String) -> void:
	if _loops.has(key):
		_loops[key].queue_free()
		_loops.erase(key)


# --- Volume ---

## linear is 0.0–1.0, for example from an HSlider.
func set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(linear))
	AudioServer.set_bus_mute(index, linear <= 0.0)


func get_bus_volume(bus: String) -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)))
```

## 4. Register the autoload

1. Open **Project → Project Settings → Globals → Autoload**.
2. **Path:** `res://scripts/audio_manager.gd`
3. **Node Name:** `Audio`
4. Click **Add**. It appears next to the existing `UiPalette` autoload.

`project.godot` will then contain:

```ini
[autoload]

UiPalette="*res://scripts/ui_palette.gd"
Audio="*res://scripts/audio_manager.gd"
```

## 5. Call it from game code

Any script can now play audio without adding nodes:

```gdscript
Audio.play_music("calm")
Audio.play_music("tense")   # cross-fades from calm
Audio.play_sfx("dispatch")
Audio.play_loop("fire_loop")
Audio.stop_loop("fire_loop")
```

Hook sounds to signals where possible:

```gdscript
undo_button.pressed.connect(Audio.play_sfx.bind("undo"))
help_button.pressed.connect(Audio.play_sfx.bind("help_toggle"))
```

### Suggested triggers

These are based on the file names. Adjust them to match the game's actual events.

| Sound | When to play it |
| --- | --- |
| `music: calm` | Menu, tutorial, planning phase |
| `music: tense` | Fires spreading, evacuation running |
| `music: win` / `fail` | Result screen. Call `stop_music()` first or switch directly. |
| `tablet_on` | Game or round screen opens |
| `select_team` | Player selects a survivor group |
| `route_tick` | Each cell added while drawing a route |
| `invalid` | Route goes somewhere it can't |
| `alert_blocked` | Route is blocked by fire |
| `plan_warning` | Plan is risky or incomplete |
| `undo` / `clear` | Undo step / clear route |
| `dispatch` / `detour_dispatch` | Group sent out / sent on a rerouted path |
| `footsteps_loop` | While any group is moving (`play_loop` / `stop_loop`) |
| `fire_start` | A new fire ignites |
| `fire_loop` | While any fire is burning |
| `radio_static` | Operator messages or alerts |
| `team_safe` | Group reaches the safe zone |
| `casualty` | Group is lost |
| `round_complete` / `round_failed` | Round ends |
| `score_tick` / `star_on` | Score counting up / each star awarded on the results screen |
| `next_round` | Next round button |
| `help_toggle` | Help panel opened or closed |
| `button_hover` | Mouse over any button (see below) |

### Hover sound on every button

Instead of connecting each button by hand, add this to `audio_manager.gd`. Every button created afterwards gets the hover sound automatically:

```gdscript
func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.mouse_entered.connect(play_sfx.bind("button_hover", 0.0))
```

## 6. Positional sounds (optional)

`Audio.play_loop()` plays at the same volume everywhere. For a sound that should come from a place on the map, such as one burning building or one moving group, put an **AudioStreamPlayer2D** in that object's scene instead:

1. Add an `AudioStreamPlayer2D` child to the scene.
2. Set **Stream** (for example `sfx_fire_loop.wav`), **Bus** = `SFX`, and **Autoplay** = on.
3. Adjust **Max Distance** and **Attenuation** for how far it carries.

Volume and stereo pan then follow the node's position relative to the camera, and the sound stops when the node is freed.

Only `Node2D`-based scenes can use `AudioStreamPlayer2D`. In a pure `Control`/UI scene, use the autoload.

## 7. Volume sliders

In a settings or pause menu with two `HSlider` nodes:

```gdscript
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider


func _ready() -> void:
	for slider in [music_slider, sfx_slider]:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
	music_slider.value = Audio.get_bus_volume("Music")
	sfx_slider.value = Audio.get_bus_volume("SFX")
	music_slider.value_changed.connect(func(v): Audio.set_bus_volume("Music", v))
	sfx_slider.value_changed.connect(func(v): Audio.set_bus_volume("SFX", v))
```

## Troubleshooting

| Problem | Check |
| --- | --- |
| No sound at all | Bus volumes in the Audio tab, and that no bus is muted or soloed. Remember that bus volumes stack. |
| Music stops after one play | Loop flag not set on import (step 2). Click **Reimport** after changing it. |
| Sound plays too fast or slow, or too high or low | `pitch_scale` on the player should be `1.0`. |
| Error `Invalid access to key` | The key passed to `play_sfx` / `play_music` doesn't match a key in `SFX` / `MUSIC`. |
| Audio cuts out when paused | The node's `process_mode` must be **Always**. The autoload already sets this. |
| Music plays twice | Delete the old `AudioStreamPlayer` test nodes from `main.tscn`. |
| One sound is too loud or too quiet | Pass a volume to that call, for example `Audio.play_sfx("score_tick", 0.05, -8.0)`. Prefer this over changing the whole bus. |
