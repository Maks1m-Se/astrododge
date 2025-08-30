extends Control

@onready var play_btn: Button      = $Centerer/MenuBox/PlayBtn
@onready var settings_btn: Button  = $Centerer/MenuBox/SettingsBtn
@onready var quit_btn: Button      = $Centerer/MenuBox/QuitBtn
@onready var title_lbl: Label      = $Centerer/MenuBox/Title
@onready var subtitle_lbl: Label   = $Centerer/MenuBox/Subtitle
@onready var settings_popup: PopupPanel = $SettingsPopup
@onready var close_settings_btn: Button = $SettingsPopup/SettingsBox/CloseSettingsBtn
@onready var ui_click: AudioStreamPlayer = get_node_or_null("UIClick") as AudioStreamPlayer
@onready var ship_select: OptionButton = $SettingsPopup/SettingsBox/ShipRow/ShipSelect
@onready var ship_desc: Label         = $SettingsPopup/SettingsBox/ShipDesc




# Music rig
@onready var music_root: Node            = $Music
@onready var pl_intro: AudioStreamPlayer = $Music/Intro
@onready var pl_a: AudioStreamPlayer     = $Music/PadA
@onready var pl_b: AudioStreamPlayer     = $Music/PadB


@export var ship_configs: Array[String] = [
	"res://data/ships/ranger.tres",
	"res://data/ships/phantom.tres",
	"res://data/ships/needle.tres",
	"res://data/ships/bulwark.tres",
]



# point this at your gameplay scene
@export_file("*.tscn") var game_scene_path := "res://scenes/Main.tscn"

# --- MUSIC CONFIG ---
const INTRO_PATHS: Array[String] = [
	"res://audio/music/main_menu_music/main_menu_pads_intro_1.ogg",
	"res://audio/music/main_menu_music/main_menu_pads_intro_2.ogg"
]
const PAD_PATHS: Array[String] = [
	"res://audio/music/main_menu_music/main_menu_pads_1.ogg",
	"res://audio/music/main_menu_music/main_menu_pads_2.ogg"
]

@export_range(0.1, 10.0, 0.1) var intro_fade_in: float = 1.5
@export_range(0.1, 10.0, 0.1) var xfade_intro_to_pad: float = 2.0
@export_range(0.1, 10.0, 0.1) var pad_xfade: float = 2.0
@export var intro_target_db: float = -14.0
@export var pad_target_db: float = -18.0
@export var leave_menu_fade: float = 0.8

var _rng := RandomNumberGenerator.new()
var _music_running: bool = false
var _current_is_a: bool = true
var _pad_stream: AudioStream
var _pad_len: float = 0.0
var _xfading: bool = false
var _use_pos_swap: bool = true  # drive crossfades by playback position

@export var debug_music: bool = true                  # toggle in Inspector
@export var debug_audio_peaks: bool = false           # optional: poll bus level
@export_range(0.1, 2.0, 0.1) var debug_audio_poll: float = 0.5

var _t0_ms: int = 0

func _dbg_enabled() -> bool:
	return debug_music and OS.is_debug_build()

func dbg(tag: String, msg: String) -> void:
	if _dbg_enabled():
		var t_ms: int = Time.get_ticks_msec()
		print("[MUSIC:", tag, "] +", t_ms - _t0_ms, "ms  ", msg)



func _ready() -> void:
	print("_ready()")  ###DEBUGGING
	
	_t0_ms = Time.get_ticks_msec()
	if debug_audio_peaks:
		_start_debug_audio_poll()

	
	_rng.randomize()

	# UI bindings
	play_btn.grab_focus()
	play_btn.pressed.connect(_on_play)
	settings_btn.pressed.connect(_on_open_settings)
	quit_btn.pressed.connect(_on_quit)
	close_settings_btn.pressed.connect(_on_close_settings)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	# Ship selector
	_populate_ship_selector()
	ship_select.item_selected.connect(_on_ship_selected)


	# Start menu music
	_start_menu_music()

func _process(_delta: float) -> void:
	if not _music_running or not _use_pos_swap or _pad_len <= 0.1:
		return

	var cur: AudioStreamPlayer = (pl_a if _current_is_a else pl_b)
	if not cur.playing:
		return

	var pos: float = cur.get_playback_position()
	# Start next pad BEFORE current reaches the end; extra 0.15s safety to avoid gaps.
	var trigger: float = maxf(0.0, _pad_len - pad_xfade - 0.15)

	if not _xfading and pos >= trigger:
		var next: AudioStreamPlayer = (pl_b if _current_is_a else pl_a)
		next.stream = _pad_stream
		next.volume_db = -60.0
		dbg("PAD", "trigger crossfade: pos=%.3fs  trigger=%.3fs  xfade=%.2fs  from=%s → to=%s" % [
			pos,
			maxf(0.0, _pad_len - pad_xfade - 0.15),
			pad_xfade,
			("A" if _current_is_a else "B"),
			("B" if _current_is_a else "A")
		])

		next.play()  # time 0.0
		_crossfade(cur, next, pad_xfade, pad_target_db)
		_current_is_a = not _current_is_a
		_xfading = true
		# allow the next cycle after the crossfade completes
		_delay_call(pad_xfade * 0.95, func():
			_xfading = false
		)


func _unhandled_input(event: InputEvent) -> void:
	print("_unhandled_input()")  ###DEBUGGING
	if event.is_action_pressed("ui_cancel"):
		if settings_popup.visible:
			_on_close_settings()
		else:
			_on_quit()

# ------------------------
# MUSIC: intro -> pad loop
# ------------------------
func _start_menu_music() -> void:
	print("_start_menu_music()")  ###DEBUGGING
	_music_running = true
	# pick intro & pad
	var intro_path := INTRO_PATHS[_rng.randi() % INTRO_PATHS.size()]
	var pad_path := PAD_PATHS[_rng.randi() % PAD_PATHS.size()]
	dbg("START", "intro=%s  pad=%s" % [intro_path, pad_path])  ###DEBUGGING
	
	
	var intro_stream := load(intro_path) as AudioStream
	print("intro_stream: ", intro_stream) ###DEBUGGING
	
	_pad_stream = load(pad_path) as AudioStream
	if _pad_stream and _pad_stream.has_method("get_length"):
		_pad_len = _pad_stream.get_length()
	else:
		_pad_len = 20.0  # safe fallback
	dbg("PAD_LEN", "reported pad length = %.3fs" % _pad_len)  ###DEBUGGING
	
	# fade-in intro
	pl_intro.stream = intro_stream
	pl_intro.volume_db = -60.0
	pl_intro.play()
	dbg("INTRO", "fade in to %.1f dB over %.2fs" % [intro_target_db, intro_fade_in]) ###DEBUGGING
	var tw := get_tree().create_tween()
	tw.tween_property(pl_intro, "volume_db", intro_target_db, intro_fade_in)

	# schedule crossfade into pad a bit before intro ends
	var intro_len: float = 0.0
	if intro_stream and intro_stream.has_method("get_length"):
		intro_len = intro_stream.get_length()
	# if we can't query length, just wait for finished and then start pad (no overlap)
	if intro_len <= 0.1:
		dbg("INTRO", "length unknown → will start pad on finished() (no overlap)") ###DEBUGGING
		pl_intro.finished.connect(func(): _start_pad_cycle())
	else:
		var lead: float = maxf(0.0, intro_len - xfade_intro_to_pad)
		dbg("INTRO→PAD", "intro_len=%.3fs  lead=%.3fs  xfade=%.2fs" % [intro_len, lead, xfade_intro_to_pad]) ###DEBUGGING
		
		_delay_call(lead, func():
			dbg("INTRO→PAD", "crossfade start") ###DEBUGGING
			
			_crossfade(pl_intro, _ensure_pad_player(true), xfade_intro_to_pad, pad_target_db)
			_current_is_a = true
			_xfading = false
		)

		
func _ensure_pad_player(use_a: bool) -> AudioStreamPlayer:
	print("_ensure_pad_player()") ###DEBUGGING
	var p := pl_a if use_a else pl_b
	print("p: ", p) ###DEBUGGING
	p.stream = _pad_stream
	p.volume_db = -60.0
	p.play()  # starts at 0.0
	return p

func _start_pad_cycle() -> void:
	print("_start_pad_cycle()")  ###DEBUGGING
	dbg("PAD", "start pad cycle on A; target_db=%.1f" % pad_target_db)  ###DEBUGGING

	# Start PadA and let _process() handle ongoing crossfades by position.
	var cur := _ensure_pad_player(true)
	print("cur: ", cur) ###DEBUGGING
	_tween_db(cur, pad_target_db, 0.8)
	pl_intro.stop()
	_current_is_a = true
	_xfading = false


func _crossfade(from_p: AudioStreamPlayer, to_p: AudioStreamPlayer, dur: float, to_target_db: float) -> void:
	print("_crossfade()") ###DEBUGGING
	dbg("XFADE", "dur=%.2fs  to_target_db=%.1f" % [dur, to_target_db]) ###DEBUGGING

	_tween_db(to_p, to_target_db, dur)
	var tw := get_tree().create_tween()
	print("tw: ", tw) ###DEBUGGING
	tw.tween_property(from_p, "volume_db", -60.0, dur)
	tw.finished.connect(func():
		if is_instance_valid(from_p):
			from_p.stop()
		dbg("XFADE", "completed")
		)

func _tween_db(p: AudioStreamPlayer, target_db: float, dur: float) -> void:
	print("_tween_db()") ###DEBUGGING
	var tw := get_tree().create_tween()
	print("tw: ", tw) ###DEBUGGING
	tw.tween_property(p, "volume_db", target_db, dur)

func _delay_call(seconds: float, cb: Callable) -> void:
	print("_delay_call()") ###DEBUGGING
	dbg("TIMER", "set %.3fs" % seconds) ###DEBUGGING

	# small helper for readable timers
	var t := get_tree().create_timer(seconds)
	print("t: ", t) ###DEBUGGING
	await t.timeout
	dbg("TIMER", "timeout %.3fs" % seconds) ###DEBUGGING

	if is_instance_valid(self):
		cb.call()

func _stop_menu_music() -> void:
	print("_stop_menu_music()") ###DEBUGGING
	dbg("STOP", "fading out over %.2fs" % leave_menu_fade) ###DEBUGGING

	if not _music_running: return
	_music_running = false
	# fade everything out quickly
	var tw := get_tree().create_tween()
	print("tw: ", tw) ###DEBUGGING
	if pl_intro.playing: tw.tween_property(pl_intro, "volume_db", -60.0, leave_menu_fade)
	if pl_a.playing:     tw.tween_property(pl_a, "volume_db", -60.0, leave_menu_fade)
	if pl_b.playing:     tw.tween_property(pl_b, "volume_db", -60.0, leave_menu_fade)
	await tw.finished
	pl_intro.stop(); pl_a.stop(); pl_b.stop()

# ---------------
# UI button logic
# ---------------
func _on_open_settings() -> void:
	print("_on_open_settings()") ###DEBUGGING
	_click()
	settings_popup.popup_centered(settings_popup.size)

func _on_close_settings() -> void:
	print("_on_close_settings()") ###DEBUGGING
	_click()
	settings_popup.hide()
	play_btn.grab_focus()

func _on_play() -> void:
	print("_on_play()") ###DEBUGGING
	_click()
	await _stop_menu_music()
	if ResourceLoader.exists(game_scene_path):
		get_tree().change_scene_to_file(game_scene_path)
	else:
		push_warning("Game scene path invalid: %s" % game_scene_path)

func _on_quit() -> void:
	print("_on_quit()") ###DEBUGGING
	_click()
	await _stop_menu_music()
	get_tree().quit()

func _click() -> void:
	print("_click()") ###DEBUGGING
	if ui_click != null:
		ui_click.stop()
		ui_click.play()

func _start_debug_audio_poll() -> void:
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		return
	_debug_audio_poll_tick(bus_idx)

func _debug_audio_poll_tick(bus_idx: int) -> void:
	if not debug_audio_peaks:
		return
	var l_db: float = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
	var r_db: float = AudioServer.get_bus_peak_volume_right_db(bus_idx, 1)
	dbg("PEAK", "Music bus L/R = %.1f / %.1f dB" % [l_db, r_db])
	_delay_call(debug_audio_poll, func():
		_debug_audio_poll_tick(bus_idx)
	)
	
func _populate_ship_selector() -> void:
	ship_select.clear()
	for path in ship_configs:
		if ResourceLoader.exists(path):
			var cfg := load(path) as ShipConfig
			if cfg:
				var idx := ship_select.item_count
				ship_select.add_item(cfg.display_name)
				ship_select.set_item_metadata(idx, path)

	# select saved choice
	var saved := Settings.get_selected_ship_path()
	var picked := 0
	for i in range(ship_select.item_count):
		if String(ship_select.get_item_metadata(i)) == saved:
			picked = i; break
	ship_select.select(picked)
	_update_ship_desc_from_path(String(ship_select.get_item_metadata(picked)))

func _update_ship_desc_from_path(path: String) -> void:
	var cfg := load(path) as ShipConfig
	if cfg:
		ship_desc.text = "%s\nHP %.0f\nMass %.2f\nThrust %.0f\nTorque %.0f" % [
			cfg.description, cfg.max_health, cfg.mass, cfg.thrust_force, cfg.torque_strength
		]

func _on_ship_selected(index: int) -> void:
	var path := String(ship_select.get_item_metadata(index))
	Settings.set_selected_ship_path(path)
	_update_ship_desc_from_path(path)
