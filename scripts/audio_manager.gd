extends Node
## Global audio manager. Registered as the "Audio" autoload.

const MUSIC := {
	"calm": preload("res://assets/audio/music_calm.mp3"),
	"tense": preload("res://assets/audio/music_tense.wav"),
	"win": preload("res://assets/audio/music_result_win.wav"),
	"fail": preload("res://assets/audio/music_result_fail.ogg"),
}

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

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const SFX_VOICES := 8
const SILENT_DB := -40.0

var _music: AudioStreamPlayer
var _music_tween: Tween
var _sfx_pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _make_player(MUSIC_BUS)
	for i in SFX_VOICES:
		_sfx_pool.append(_make_player(SFX_BUS))
	call_deferred("_start_default_music")


func _start_default_music() -> void:
	play_music("calm")


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	if AudioServer.get_bus_index(bus) < 0:
		push_error("Audio bus '%s' is missing from default_bus_layout.tres" % bus)
		player.bus = &"Master"
	else:
		player.bus = bus
	add_child(player)
	return player


func play_music(key: String, fade := 0.5) -> void:
	if not MUSIC.has(key):
		push_error("Unknown music key: %s" % key)
		return
	if _music == null:
		return
	var stream: AudioStream = MUSIC[key]
	if _music.stream == stream and _music.playing:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", SILENT_DB, fade)
	_music_tween.tween_callback(func() -> void:
		_music.stream = stream
		_music.volume_db = SILENT_DB
		_music.play())
	_music_tween.tween_property(_music, "volume_db", 0.0, fade)


func stop_music(fade := 0.5) -> void:
	if _music == null or not _music.playing:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", SILENT_DB, fade)
	_music_tween.tween_callback(_music.stop)


func play_sfx(key: String, pitch_jitter := 0.05, volume_db := 0.0) -> void:
	if not SFX.has(key):
		push_error("Unknown SFX key: %s" % key)
		return
	var stream: AudioStream = SFX[key]
	for player in _sfx_pool:
		if not player.playing:
			player.stream = stream
			player.volume_db = volume_db
			player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
			player.play()
			return


func play_loop(key: String) -> void:
	if not SFX.has(key):
		push_error("Unknown looping SFX key: %s" % key)
		return
	if _loops.has(key):
		var existing: AudioStreamPlayer = _loops[key]
		if is_instance_valid(existing) and not existing.playing:
			existing.play()
		return
	var player := _make_player(SFX_BUS)
	var stream: AudioStream = SFX[key]
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	player.stream = stream
	player.finished.connect(_on_loop_finished.bind(key, player))
	player.play()
	_loops[key] = player


func _on_loop_finished(key: String, player: AudioStreamPlayer) -> void:
	if _loops.has(key) and _loops[key] == player and is_instance_valid(player):
		player.play()


func stop_loop(key: String) -> void:
	if not _loops.has(key):
		return
	var player: AudioStreamPlayer = _loops[key]
	_loops.erase(key)
	if is_instance_valid(player):
		player.queue_free()


func set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	var value := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, -80.0 if value <= 0.0 else linear_to_db(value))
	AudioServer.set_bus_mute(index, value <= 0.0)


func get_bus_volume(bus: String) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index < 0 or AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.mouse_entered.connect(play_sfx.bind("button_hover", 0.0))
