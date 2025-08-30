extends Node2D

const MeteorScene: PackedScene = preload("res://scenes/Meteor.tscn")

@onready var cam: Camera2D           = $Camera2D
@onready var ship: RigidBody2D       = $Ship
@onready var spawn_timer: Timer      = $MeteorTimer
@onready var alarm: AudioStreamPlayer2D = $HUD/HUDRoot/AlarmBeep


# HUD refs
@onready var hud_root: Control       = $HUD/HUDRoot
@onready var edge_t: ColorRect       = $HUD/HUDRoot/EdgeTop
@onready var edge_b: ColorRect       = $HUD/HUDRoot/EdgeBottom
@onready var edge_l: ColorRect       = $HUD/HUDRoot/EdgeLeft
@onready var edge_r: ColorRect       = $HUD/HUDRoot/EdgeRight
@onready var oob_label: Label        = $HUD/HUDRoot/OOBLabel
@onready var marker: Control         = $HUD/HUDRoot/EdgeMarker
@onready var health_bar: HealthBar = $HUD/HUDRoot/HealthBar




var rng := RandomNumberGenerator.new()

# --- OOB system ---
var oob_limit: float = 5.0
var oob_time_left: float = 0.0
var oob_last_tick: int = -1
var was_out: bool = false



func _ready() -> void:
	rng.randomize()
	spawn_timer.timeout.connect(_spawn_meteor)
	_set_oob_visible(false)

	# Marker setup (unchanged)
	marker.size = Vector2(24, 24)
	marker.custom_minimum_size = Vector2(24, 24)
	marker.z_index = 100
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	print("EdgeMarker path OK? ", is_instance_valid(marker), " size=", marker.size, " vis=", marker.visible)

	# 1) Apply selected ship config FIRST
	var path: String = Settings.get_selected_ship_path()
	if ResourceLoader.exists(path):
		var cfg := load(path) as ShipConfig
		if cfg and ship.has_method("set_config"):
			ship.set_config(cfg)

	# 2) Now initialize the health bar from the ship (capacity + current)
	if is_instance_valid(health_bar):
		health_bar.set_capacity(ship.max_health)
		health_bar.set_value(ship.health)

	# 3) Connect health signals (guard against double-connecting)
	if not ship.health_changed.is_connected(_on_ship_health_changed):
		ship.health_changed.connect(_on_ship_health_changed)
	if not ship.died.is_connected(_on_ship_died):
		ship.died.connect(_on_ship_died)





func _physics_process(delta: float) -> void:
	_update_oob(delta)

func _update_oob(delta: float) -> void:
	var rect := _get_camera_rect()  # visible world rect
	var in_bounds := rect.has_point(ship.global_position)

	if in_bounds:
		if was_out:
			# back in → clear warning
			was_out = false
			oob_time_left = 0.0
			_set_oob_visible(false)
		return

	# out of bounds
	if not was_out:
		was_out = true
		oob_time_left = oob_limit
		oob_last_tick = -1          # reset so the first second will beep
		_set_oob_visible(true)
		# Optional: beep immediately when going OOB:
		_beep()

	# countdown
	oob_time_left = max(0.0, oob_time_left - delta)
	_update_oob_hud(rect, delta)

	if oob_time_left <= 0.0:
		_on_oob_fail()

func _set_oob_visible(v: bool) -> void:
	edge_t.visible = v
	edge_b.visible = v
	edge_l.visible = v
	edge_r.visible = v
	oob_label.visible = v
	marker.visible = v

func _update_oob_hud(rect: Rect2, _delta: float) -> void:
	# 1) pulse edges (1 pulse per second)
	var frac: float = 1.0 - fposmod(oob_time_left, 1.0)   # 0..1 within the current second
	var pulse: float = sin(frac * PI)                     # 0..1
	var edge_alpha: float = lerp(0.10, 0.70, pulse)
	var c: Color = Color(1, 0.25, 0.30, edge_alpha)
	edge_t.color = c
	edge_b.color = c
	edge_l.color = c
	edge_r.color = c

	# label (big seconds)
	oob_label.text = str(int(ceil(oob_time_left)))
	var mod: Color = oob_label.modulate
	mod.a = lerp(0.4, 1.0, pulse)
	oob_label.modulate = mod
	
	# Beep on each new whole-second value (5,4,3,2,1)
	var tick: int = int(ceil(oob_time_left))
	if tick > 0 and tick != oob_last_tick:
		_beep()
		oob_last_tick = tick


	# 2) place marker on the edge pointing toward the ship
	var center: Vector2 = rect.get_center()
	var edge_world: Vector2 = _line_to_rect_edge(center, ship.global_position, rect)
	var aim: float = (ship.global_position - edge_world).angle()

	var screen_pt: Vector2 = _world_to_screen(edge_world)
	var back: Vector2 = Vector2.RIGHT.rotated(aim + PI) * 6.0
	marker.position = screen_pt - marker.size * 0.5 + back
	if marker.has_method("set_angle"):
		marker.call("set_angle", aim)


func _world_to_screen(world: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport_rect().size
	# Correct mapping: pixels = (world - camera_center) * zoom + viewport_half
	return (world - cam.global_position) * cam.zoom + vp * 0.5



func _get_camera_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var size := Vector2(vp.x / cam.zoom.x, vp.y / cam.zoom.y)
	var half := size * 0.5
	var center := cam.global_position
	return Rect2(center - half, size)

func _line_to_rect_edge(from: Vector2, to: Vector2, r: Rect2) -> Vector2:
	var dir: Vector2 = to - from
	var candidates: Array[Vector2] = []

	if absf(dir.x) > 0.0001:
		var t: float = (r.position.x - from.x) / dir.x
		if t > 0.0 and t <= 1.0:
			var y: float = from.y + dir.y * t
			if y >= r.position.y and y <= r.position.y + r.size.y:
				candidates.append(Vector2(r.position.x, y))

		t = (r.position.x + r.size.x - from.x) / dir.x
		if t > 0.0 and t <= 1.0:
			var y2: float = from.y + dir.y * t
			if y2 >= r.position.y and y2 <= r.position.y + r.size.y:
				candidates.append(Vector2(r.position.x + r.size.x, y2))

	if absf(dir.y) > 0.0001:
		var t2: float = (r.position.y - from.y) / dir.y
		if t2 > 0.0 and t2 <= 1.0:
			var x: float = from.x + dir.x * t2
			if x >= r.position.x and x <= r.position.x + r.size.x:
				candidates.append(Vector2(x, r.position.y))

		t2 = (r.position.y + r.size.y - from.y) / dir.y
		if t2 > 0.0 and t2 <= 1.0:
			var x2: float = from.x + dir.x * t2
			if x2 >= r.position.x and x2 <= r.position.x + r.size.x:
				candidates.append(Vector2(x2, r.position.y + r.size.y))

	if candidates.size() == 0:
		return Vector2(
			clampf(to.x, r.position.x, r.position.x + r.size.x),
			clampf(to.y, r.position.y, r.position.y + r.size.y)
		)

	var best: Vector2 = candidates[0]
	var best_d: float = (best - from).length_squared()
	for i in range(1, candidates.size()):
		var d: float = (candidates[i] - from).length_squared()
		if d < best_d:
			best_d = d
			best = candidates[i]
	return best

# --- existing meteor spawner (keep yours) ---
func _spawn_meteor(
	
) -> void:
	var view_size: Vector2 = get_viewport_rect().size
	var half: Vector2 = view_size * 0.5
	var center: Vector2 = cam.global_position
	var rect: Rect2 = Rect2(center - half, view_size)

	var margin: float = 140.0
	var spawn_pos: Vector2 = _random_point_on_rect_edge(rect.grow(margin))
	var target_pos: Vector2 = Vector2(
		rng.randf_range(rect.position.x, rect.position.x + rect.size.x),
		rng.randf_range(rect.position.y, rect.position.y + rect.size.y)
	)

	var m: Area2D = MeteorScene.instantiate()
	add_child(m)
	(m as Node).call("setup", spawn_pos, target_pos, rng)
	m.connect("hit_ship", Callable(self, "_on_meteor_hit_ship"))

func _random_point_on_rect_edge(r: Rect2) -> Vector2:
	var side: int = rng.randi_range(0, 3)
	match side:
		0:  return Vector2(r.position.x + rng.randf() * r.size.x, r.position.y)
		1:  return Vector2(r.position.x + r.size.x, r.position.y + rng.randf() * r.size.y)
		2:  return Vector2(r.position.x + rng.randf() * r.size.x, r.position.y + r.size.y)
		_:  return Vector2(r.position.x, r.position.y + rng.randf() * r.size.y)

func _on_meteor_hit_ship() -> void:
	print("HIT! Meteor collided with the ship.")

func _on_oob_fail() -> void:
	print("OOB fail — player stayed off-screen too long.")
	# TODO: die/reset/lose life. For now, just clear UI:
	was_out = false
	_set_oob_visible(false)
	
func _beep() -> void:
		# restart the sound cleanly (use stop+play to retrigger even if still playing)
		alarm.stop()
		alarm.play()

func _on_ship_health_changed(cur: float, maxv: float) -> void:
	if not is_instance_valid(health_bar):
		return

	# Keep capacity in sync and update the value
	health_bar.set_capacity(maxv)
	health_bar.set_value(cur)

	# Optional: keep your pleasant color ramp
	var t: float = (cur / maxv) if maxv > 0.0 else 0.0
	t = clampf(t, 0.0, 1.0)
	var healthy := Color(0.65, 0.87, 1.0)
	var danger  := Color(1.00, 0.36, 0.40)
	var mid     := Color(0.96, 0.74, 0.38)
	var col     := healthy.lerp(mid, 1.0 - pow(t, 1.2)).lerp(danger, 1.0 - t)

	# Write to the bar's Fill node
	var fill := health_bar.get_node_or_null("Fill") as ColorRect
	if fill:
		fill.color = col


func _on_ship_died() -> void:
	# For now, just print; in the next step we’ll show Game Over overlay.
	print("Ship destroyed.")
	# Optional: stop spawning immediately
	spawn_timer.stop()
