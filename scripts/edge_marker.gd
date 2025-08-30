@tool
extends Control

@export var color: Color = Color(1, 0.35, 0.40, 0.95)
@export var base_size: Vector2 = Vector2(24, 24)  # ensures a draw area even in editor

var angle: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100                          # draw above the red edge bars
	top_level = false                      # keep it in HUDRoot coords
	if size == Vector2.ZERO:
		size = base_size
	custom_minimum_size = base_size
	visible = true                         # force visible for debugging
	queue_redraw()

func _draw() -> void:
	# Debug: faint box so we SEE the control’s rect even if the triangle fails
	draw_rect(Rect2(Vector2.ZERO, size), Color(1,1,1,0.08), true)

	# Tiny triangle pointing along +X, rotated by 'angle'
	var pts := PackedVector2Array([Vector2(18,0), Vector2(-9,4), Vector2(-9,-4)])
	for i in range(pts.size()):
		pts[i] = pts[i].rotated(angle) + size * 0.5
	draw_polygon(pts, PackedColorArray([color, color, color]))

func set_angle(a: float) -> void:
	angle = a
	queue_redraw()
