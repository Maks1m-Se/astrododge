extends RigidBody2D

# --- Tunables (export to tweak in editor) ---
@export_range(0.0, 5000.0, 10.0) var thrust_force: float = 900.0
@export_range(0.0, 5000.0, 10.0) var torque_strength: float = 450.0
@export_range(0.0, 5.0, 0.05) var linear_damp_playfeel: float = 0.1
@export_range(0.0, 5.0, 0.05) var angular_damp_playfeel: float = 0.1

# --- Debug overlay ---
var debug_enabled := true
var _debug_label: Label

func _ready() -> void:
	# Set soft damping for a pleasant feel (still keeps momentum).
	linear_damp = linear_damp_playfeel
	angular_damp = angular_damp_playfeel

	# Create a simple debug label (child) to show speed & ω.
	_debug_label = Label.new()
	_debug_label.theme_type_variation = "Mono"  # if you have a theme; otherwise ignored
	_debug_label.modulate = Color(1,1,1,0.75)
	_debug_label.position = Vector2( -60, -40 )
	add_child(_debug_label)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		debug_enabled = !debug_enabled
		if is_instance_valid(_debug_label):
			_debug_label.visible = debug_enabled

func _physics_process(delta: float) -> void:
	# 1) Forward thrust (applied at center)
	if Input.is_action_pressed("thrust"):
		# Facing direction is +X rotated by current rotation.
		var forward := Vector2.RIGHT.rotated(rotation)
		# Continuous force keeps adding momentum.
		apply_central_force(forward * thrust_force)

	# 2) Rotation via torque (simulate side thrusters)
	var turning := 0.0
	if Input.is_action_pressed("turn_left"):
		turning -= 1.0
	if Input.is_action_pressed("turn_right"):
		turning += 1.0

	if turning != 0.0:
		# Use impulse scaled by delta to approximate continuous torque.
		apply_torque_impulse(turning * torque_strength * delta)

	# 3) Debug info (speed & angular velocity)
	if debug_enabled and is_instance_valid(_debug_label):
		var speed := linear_velocity.length()
		_debug_label.text = "v = %.1f px/s\nω = %.2f rad/s" % [speed, angular_velocity]

	# 4) Simple soft clamping of max speed for comfort (optional)
	var max_speed := 900.0
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	# Notes:
	# - We intentionally DO NOT zero velocity when no input is pressed—momentum is conserved.
	# - Small linear/angular damping makes control a bit more forgiving without feeling "sticky".
