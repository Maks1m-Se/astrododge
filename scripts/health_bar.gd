# res://scripts/ui/health_bar.gd
extends Control
class_name HealthBar

@onready var track: ColorRect = $Track
@onready var fill: ColorRect = $Fill

# How wide should a full bar be for a given max HP?
@export var px_per_hp: float = 2.0          # 2 px per HP → edit to taste
@export var min_full_width: float = 120.0   # clamp so tiny ships still readable
@export var max_full_width: float = 280.0   # clamp so huge ships don't dominate

# Internal state
var _max_hp: float = 1.0
var _cur_hp: float = 1.0
var _full_w: float = 160.0

func set_capacity(max_hp: float) -> void:
	# Called when a ship type is (re)applied
	_max_hp = max(1.0, max_hp)
	_full_w = clampf(_max_hp * px_per_hp, min_full_width, max_full_width)

	# Grow the bar to the right: fix left, expand width
	custom_minimum_size.x = _full_w
	size.x = _full_w
	if is_instance_valid(track):
		track.size.x = _full_w
	# Reapply current fill
	_apply_fill()

func set_value(cur_hp: float) -> void:
	_cur_hp = clampf(cur_hp, 0.0, _max_hp)
	_apply_fill()

func _apply_fill() -> void:
	var t: float = _cur_hp / _max_hp
	if is_instance_valid(fill):
		fill.size.x = floor(_full_w * t)
