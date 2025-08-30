extends Area2D
signal hit_ship

@export var use_palette: bool = true
@export var palette: Array[Color] = [
	Color8(180,186,199), # glacial stone (cool gray-blue)
	Color8(152,160,176), # slate
	Color8(139,147,161), # steel
	Color8(128,122,111), # warm basalt (a touch of brown)
	Color8(127,143,134)  # desaturated green-gray
]
@export var background_color: Color = Color8(11,16,32) # your #0b1020
@export var use_vertex_shading: bool = true           # fake 2-tone shading
@export var base_damage: float = 22.0
var _radius_current: float = 24.0  # store the chosen radius for damage scaling


@export_range(8.0, 160.0, 1.0) var radius_min: float = 18.0
@export_range(8.0, 220.0, 1.0) var radius_max: float = 64.0
@export_range(0.0, 0.9, 0.01) var jaggedness: float = 0.35
@export_range(5, 16, 1) var sides_min: int = 7
@export_range(5, 24, 1) var sides_max: int = 12
@export_range(80.0, 480.0, 1.0) var speed_min: float = 120.0
@export_range(80.0, 820.0, 1.0) var speed_max: float = 520.0
@export_range(-3.5, 3.5, 0.05) var angular_speed_min: float = -3.0
@export_range(-3.5, 3.5, 0.05) var angular_speed_max: float =  3.0
@export var base_color: Color = Color8(180, 186, 199) # soft gray-blue

var velocity: Vector2 = Vector2.ZERO
var angular_speed: float = 0.0

@onready var sprite: Polygon2D = $Sprite
@onready var coll: CollisionPolygon2D = $Collision
@onready var notifier: VisibleOnScreenNotifier2D = $OnScreen

func _ready() -> void:
	notifier.screen_exited.connect(_on_screen_exited)
	body_entered.connect(_on_body_entered)

func setup(from_pos: Vector2, to_pos: Vector2, rng: RandomNumberGenerator) -> void:
	global_position = from_pos

	# --- direction & velocity ---
	var travel_dir: Vector2 = (to_pos - from_pos).normalized()
	var spd: float = rng.randf_range(speed_min, speed_max)
	velocity = travel_dir * spd
	angular_speed = rng.randf_range(angular_speed_min, angular_speed_max)

	var sides: int = rng.randi_range(sides_min, sides_max)
	var radius: float = rng.randf_range(radius_min, radius_max)
	_radius_current = radius
	
	var pts: PackedVector2Array = _make_irregular_polygon(radius, sides, jaggedness, rng)
	sprite.polygon = pts
	coll.polygon = pts

	# pick a palette color and blend it slightly toward the background so it harmonizes
	var chosen: Color = base_color
	if use_palette and palette.size() > 0:
		chosen = palette[rng.randi() % palette.size()]
	# pull the color ~60% away from the bg (keeps it muted and cohesive)
	var base_tint: Color = background_color.lerp(chosen, 0.60)
	# tiny per-meteor variation
	base_tint = base_tint.darkened(rng.randf_range(0.0, 0.15))

	sprite.color = base_tint

	# OPTIONAL: cheap per-vertex “rim” shading (off the incoming direction)
	if use_vertex_shading:
		var vcols := PackedColorArray()
		var centroid := Vector2.ZERO
		for p in pts: centroid += p
		centroid /= float(pts.size())

		var light_dir: Vector2 = (-velocity).normalized()  # brighten the “front” rim
		for p in pts:
			var rim_dir: Vector2 = (p - centroid).normalized()
			var t: float = clamp(rim_dir.dot(light_dir) * 0.5 + 0.5, 0.0, 1.0) # 0..1
			var c_dark := base_tint.darkened(0.18)
			var c_lit  := base_tint.lightened(0.18)
			vcols.append(c_dark.lerp(c_lit, t))
		sprite.vertex_colors = vcols

	# OPTIONAL: if you created a Line2D child named "Outline", update it
	var outline := get_node_or_null("Outline") as Line2D
	if outline:
		outline.points = pts + PackedVector2Array([pts[0]]) # close the loop
		outline.width = clamp(radius * 0.08, 1.0, 3.0)
		outline.default_color = base_tint.darkened(0.35)
		outline.z_index = 1


func _process(delta: float) -> void:
	global_position += velocity * delta
	rotation += angular_speed * delta

func _make_irregular_polygon(r: float, sides: int, jag: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step: float = TAU / float(sides)
	for i in range(sides):
		var angle: float = step * float(i) + rng.randf_range(-step * 0.1, step * 0.1)
		var radius_variation: float = 1.0 - jag + rng.randf() * jag * 2.0
		var rr: float = max(6.0, r * radius_variation)
		pts.append(Vector2(rr, 0.0).rotated(angle))
	return pts

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		var dmg := _compute_damage()
		# prefer calling the ship API directly
		if body.has_method("apply_damage"):
			body.apply_damage(dmg)
		# keep your signal for other systems (logging, effects)
		hit_ship.emit()
		queue_free()

func _compute_damage() -> float:
	# Scale damage by meteor size (small → ~70%, big → ~180%)
	var t := 0.0
	if radius_max > radius_min:
		t = clamp((_radius_current - radius_min) / (radius_max - radius_min), 0.0, 1.0)
	return base_damage * lerp(0.7, 1.8, t)


func _on_screen_exited() -> void:
	queue_free()
