extends Node

# ---- Files ----
const GAME_TRACKS: Array[String] = [
	"res://audio/music/game_music/game_music_1.ogg",
	"res://audio/music/game_music/game_music_2.ogg",
	"res://audio/music/game_music/game_music_3.ogg",
	"res://audio/music/game_music/game_music_4.ogg",
	"res://audio/music/game_music/game_music_5.ogg",
	"res://audio/music/game_music/game_music_6.ogg",
]

# ---- Musical config ----
@export_range(40.0, 220.0, 0.1) var bpm: float = 120.0
@export var beats_per_bar: int = 4
@export_range(0.5, 32.0, 0.5) var fade_beats: float = 4.0        # crossfade length (beats)
@export var target_db: float = -16.0
@export var bars_min: int = 8                                     # bars between changes (min/max)
@export var bars_max: int = 12
@export_range(0.5, 32.0, 0.5) var fade_out_beats: float = 4.0


# ---- Debug (like your menu) ----
@export var debug_music: bool = true
var _t0_ms: int = 0
func _dbg_enabled() -> bool: return debug_music and OS.is_debug_build()
func dbg(tag: String, msg: String) -> void:
	if _dbg_enabled():
		var t_ms: int = Time.get_ticks_msec()
		print("[GMUSIC:", tag, "] +", t_ms - _t0_ms, "ms  ", msg)

# ---- Nodes ----
@onready var a: AudioStreamPlayer = $TrackA
@onready var b: AudioStreamPlayer = $TrackB

# ---- State ----
var _rng := RandomNumberGenerator.new()
var _cur_is_a := true
var _playing := false
var _spb := 0.0                  # seconds per beat
var _bar_sec := 0.0              # seconds per bar
var _fade_sec := 0.0             # seconds for crossfade (from fade_beats)
var _next_trigger_pos := INF     # next bar boundary (in seconds of the *current* player)
var _current_path := ""          # path of current track
var _xfading := false
var _fade_out_sec := 0.0


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	_rng.randomize()
	_recalc_timing()
	_start_random_track()
	dbg("START", "bpm=%.1f  beats/bar=%d  fade_beats=%.1f (%.2fs)  next in %d..%d bars"
		% [bpm, beats_per_bar, fade_beats, _fade_sec, bars_min, bars_max])

func _process(_dt: float) -> void:
	if not _playing or _xfading:
		return
	var p := _cur_player()
	if not p.playing:
		return
	var pos := _exact_pos(p)
	if pos >= _next_trigger_pos - 0.02:           # small safety
		_crossfade_to_random_on_bar()

# ---- Public API (optional) ----
func stop_music(fade_out_sec: float = 0.8) -> void:
	if not _playing: return
	_playing = false
	var p := _cur_player()
	var tw := get_tree().create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade_out_sec)
	await tw.finished
	if is_instance_valid(p): p.stop()

# ---- Internals ----
func _recalc_timing() -> void:
	_spb = 60.0 / maxf(1.0, bpm)
	_bar_sec = _spb * float(max(1, beats_per_bar))
	_fade_sec = _spb * fade_beats
	_fade_out_sec = _spb * fade_out_beats

func _cur_player() -> AudioStreamPlayer:
	return a if _cur_is_a else b

func _other_player() -> AudioStreamPlayer:
	return b if _cur_is_a else a

func _pick_random_path(exclude: String) -> String:
	var choices := GAME_TRACKS.filter(func(p): return p != exclude)
	if choices.is_empty(): choices = GAME_TRACKS.duplicate()
	var rand_choice = choices[_rng.randi() % choices.size()]
	print("Random new track: ", rand_choice)
	return rand_choice

func _start_random_track() -> void:
	_current_path = _pick_random_path("")  # no exclude on first start
	var st := load(_current_path) as AudioStream
	var p := _cur_player()
	p.stream = st
	p.volume_db = -60.0
	p.play(0.0)
	var tw := get_tree().create_tween()
	tw.tween_property(p, "volume_db", target_db, 1.0)
	_playing = true
	_schedule_next_change_from_pos(0.0)    # from bar 0 of this track
	dbg("PLAY", "now playing %s" % _current_path)

func _schedule_next_change_from_pos(cur_pos: float) -> void:
	# choose bars ahead this time
	var bars_ahead := _rng.randi_range(max(1, bars_min), max(bars_min, bars_max))
	var rem_to_bar := _bar_sec - fposmod(cur_pos, _bar_sec)
	if rem_to_bar >= _bar_sec - 0.001: rem_to_bar = 0.0 # already on bar
	_next_trigger_pos = cur_pos + rem_to_bar + float(bars_ahead - 1) * _bar_sec
	dbg("SCHED", "next change in %d bars → %.3fs from now (trigger_pos=%.3fs)"
		% [bars_ahead, rem_to_bar + float(bars_ahead - 1) * _bar_sec, _next_trigger_pos])

func _crossfade_to_random_on_bar() -> void:
	if _xfading: return
	_xfading = true

	var from_p := _cur_player()
	var to_p := _other_player()
	var next_path := _pick_random_path(_current_path)

	if not ResourceLoader.exists(next_path):
		dbg("ERR", "Next file missing: %s" % next_path)
		_xfading = false
		_schedule_next_change_from_pos(_exact_pos(from_p))
		return

	to_p.stream = load(next_path) as AudioStream
	to_p.volume_db = -60.0
	to_p.play(0.0)

	dbg("XFADE", "bar-aligned → %s  (fade-in %.2fs, then fade-out %.2fs)" % [next_path, _fade_sec, _fade_out_sec])

	# 1) Fade the NEW track up to target_db
	var tw_up: Tween = get_tree().create_tween()
	tw_up.tween_property(to_p, "volume_db", target_db, _fade_sec)
	await tw_up.finished
	dbg("XFADE", "fade-in complete → start fade-out of previous")

	# 2) Only now fade the OLD track down to -60 dB
	var tw_dn: Tween = get_tree().create_tween()
	tw_dn.tween_property(from_p, "volume_db", -60.0, _fade_out_sec)
	await tw_dn.finished
	if is_instance_valid(from_p): from_p.stop()

	# Swap pointers and schedule next change from bar 0 of the new track
	_cur_is_a = not _cur_is_a
	_current_path = next_path
	_xfading = false
	_schedule_next_change_from_pos(0.0)
	dbg("DONE", "staggered crossfade complete; current = %s" % _current_path)


# Accurate audio position (compensate mixer timing/latency)
func _exact_pos(p: AudioStreamPlayer) -> float:
	var pos := p.get_playback_position()
	pos += AudioServer.get_time_since_last_mix()
	pos -= AudioServer.get_output_latency()
	return max(pos, 0.0)
