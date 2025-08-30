extends RigidBody2D


# --- Config + Debug ---
@export var config: ShipConfig
@export var debug_ship: bool = true
func sdbg(tag: String, msg: String) -> void:
	if debug_ship and OS.is_debug_build():
		print("[SHIP:", tag, "] ", msg)



@onready var vfx_main:  GPUParticles2D  = $GFX/VFX/MainThruster
@onready var vfx_left:  GPUParticles2D  = $GFX/VFX/LeftThruster
@onready var vfx_right: GPUParticles2D  = $GFX/VFX/RightThruster
@onready var light_main:  PointLight2D  = $GFX/VFX/MainLight
@onready var light_left:  PointLight2D  = $GFX/VFX/LeftLight
@onready var light_right: PointLight2D  = $GFX/VFX/RightLight
@onready var s_main:  AudioStreamPlayer2D = $Audio/ThrusterMain
@onready var s_left:  AudioStreamPlayer2D = $Audio/ThrusterLeft
@onready var s_right: AudioStreamPlayer2D = $Audio/ThrusterRight

@onready var gfx_root: Node2D = get_node_or_null("GFX") as Node2D
@onready var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var col_poly: CollisionPolygon2D = get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D

var _base_poly: PackedVector2Array
var _base_rect: Vector2 = Vector2.ZERO
var _base_radius: float = 0.0
var _base_capsule_radius: float = 0.0
var _base_capsule_height: float = 0.0


var thrust_level := 0.0 # smoothed 0..1

# --- VFX scaling ---
var _vfx_base_main_scale := Vector2.ONE
var _vfx_base_left_scale := Vector2.ONE
var _vfx_base_right_scale := Vector2.ONE
var _vfx_variant_scale := 1.0

# Smooth side thruster intensity (0..1)
var _side_left_level := 0.0
var _side_right_level := 0.0


# --- Tunables (export to tweak in editor) ---
@export_range(0.0, 5000.0, 10.0) var thrust_force: float = 900.0
@export_range(0.0, 5000.0, 10.0) var torque_strength: float = 450.0
@export_range(0.0, 5.0, 0.05) var linear_damp_playfeel: float = 0.1
@export_range(0.0, 5.0, 0.05) var angular_damp_playfeel: float = 0.1

# --- VFX scaling knobs (Inspector) ---
@export var vfx_ref_thrust: float = 900.0                      # baseline thrust to compare variants
@export_range(0.2, 3.0, 0.05) var vfx_variant_min: float = 0.6 # clamp variant factor
@export_range(0.2, 3.0, 0.05) var vfx_variant_max: float = 1.8

@export var vfx_main_dyn_range: Vector2 = Vector2(0.70, 1.35)  # live size range (idle → full) for main
@export var vfx_side_dyn_range: Vector2 = Vector2(0.70, 1.15)  # live size range for side jets

@export var vfx_speed_main_range: Vector2 = Vector2(0.85, 1.30) # optional “longer jet” feel
@export var vfx_speed_side_range: Vector2 = Vector2(0.85, 1.15)


# --- Light base so Heavy can brighten a bit ---
@export var base_light_energy: float = 1.4
var _light_base := 1.4

# health
signal health_changed(current: float, max: float)
signal died

@export_range(1.0, 500.0, 1.0) var max_health: float = 60.0
var health: float = max_health



# --- Debug overlay ---
var debug_enabled := false
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
	
	if col_poly and col_poly.polygon.size() > 0:
		_base_poly = col_poly.polygon.duplicate()

	if col_shape and col_shape.shape:
		var sh := col_shape.shape
		if sh is CircleShape2D:
			_base_radius = (sh as CircleShape2D).radius
		elif sh is RectangleShape2D:
			_base_rect = (sh as RectangleShape2D).size
		elif sh is CapsuleShape2D:
			var c := sh as CapsuleShape2D
			_base_capsule_radius = c.radius
			_base_capsule_height = c.height
	
	if vfx_main:  vfx_main.emitting = false
	if vfx_left:  vfx_left.emitting = false
	if vfx_right: vfx_right.emitting = false
	
	# Cache original particle scales so we scale relative to your authored size
	if vfx_main:  _vfx_base_main_scale  = vfx_main.scale
	if vfx_left:  _vfx_base_left_scale  = vfx_left.scale
	if vfx_right: _vfx_base_right_scale = vfx_right.scale

	# Ensure particles start off (okay if you already had this)
	if vfx_main:  vfx_main.emitting = false
	if vfx_left:  vfx_left.emitting = false
	if vfx_right: vfx_right.emitting = false




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
	
	# --- VFX: emitters and light follow inputs ---
	var thrusting := Input.is_action_pressed("thrust")
	var turning_left := Input.is_action_pressed("turn_left")
	var turning_right := Input.is_action_pressed("turn_right")

	# Particles still controlled the same way:
	if is_instance_valid(vfx_main):
		vfx_main.emitting = thrusting
	if is_instance_valid(vfx_left):
		vfx_left.emitting = turning_left
	if is_instance_valid(vfx_right):
		vfx_right.emitting = turning_right
		
	# Light fade (Python-style ternary + lerp)
	if is_instance_valid(light_main):
		var target_energy_main := _light_base if thrusting else 0.0
		light_main.energy = lerp(light_main.energy, target_energy_main, 0.18)
	if is_instance_valid(light_left):
		var target_energy_left := _light_base if turning_left else 0.0
		light_left.energy = lerp(light_left.energy, target_energy_left, 0.18)
	if is_instance_valid(light_right):
		var target_energy_right := _light_base if turning_right else 0.0
		light_right.energy = lerp(light_right.energy, target_energy_right, 0.18)
		
	_update_thruster_audio(delta, thrusting, turning_left, turning_right)
	
	
	
func _update_thruster_audio(delta: float, thrusting: bool, left: bool, right: bool) -> void:
	# Smooth main thruster intensity 0..1 (prevents clicks)
	thrust_level = move_toward(thrust_level, 1.0 if thrusting else 0.0, delta * 6.0)

	# Start/stop main loop neatly
	if thrust_level > 0.02 and not s_main.playing:
		s_main.play()
	elif thrust_level <= 0.0 and s_main.playing:
		s_main.stop()

	# Fade loudness and add a little pitch rise with thrust
	var quiet_db := -18.0
	var loud_db  :=  -6.0
	s_main.volume_db  = lerp(quiet_db, loud_db, thrust_level)
	s_main.pitch_scale = lerp(0.90, 1.15, thrust_level)

	# Side thrusters: play while held
	_set_looping_player(s_left, left)
	_set_looping_player(s_right, right)

func _set_looping_player(p: AudioStreamPlayer2D, active: bool) -> void:
	if active:
		if not p.playing:
			p.pitch_scale = 1.1 + randf() * 0.05 # tiny variation so L/R aren’t identical
			p.play()
	else:
		if p.playing:
			p.stop()


func apply_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


func set_config(new_cfg: ShipConfig) -> void:
	config = new_cfg
	if is_node_ready():
		_apply_config(config)
	else:
		call_deferred("_apply_config", config)


func _apply_config(cfg: ShipConfig) -> void:
	# If someone called us before _ready(), ensure refs/base are cached now
	if col_poly and _base_poly.is_empty() and col_poly.polygon.size() > 0:
		_base_poly = col_poly.polygon.duplicate()
		
	if cfg == null:
		sdbg("CFG", "No ShipConfig assigned; using current Inspector values.")
		# still ensure health fields are aligned
		health = clamp(health, 0.0, max_health)
		_light_base = base_light_energy
		return

	# Stats
	max_health = cfg.max_health
	# If you want a “keep current ratio” behavior when swapping in-game, do:
	# var ratio := (health / max_health) if max_health > 0.0 else 1.0
	# max_health = cfg.max_health
	# health = clamp(ratio * max_health, 0.0, max_health)
	health = max_health
	health_changed.emit(health, max_health)

	mass = cfg.mass
	thrust_force = cfg.thrust_force
	torque_strength = cfg.torque_strength
	linear_damp_playfeel = cfg.linear_damp
	angular_damp_playfeel = cfg.angular_damp
	linear_damp = linear_damp_playfeel
	angular_damp = angular_damp_playfeel

	# Visual scale (prefer scaling the GFX wrapper; otherwise scale the Ship)
	var sc := Vector2.ONE * cfg.scale
	if is_instance_valid(gfx_root):
		gfx_root.scale = sc
	else:
		scale = sc  # fallback

	# Collision scale from cached base values
	_apply_collider_scale(cfg.scale)
	
	if is_instance_valid(col_poly):
		sdbg("COL", "poly points=%d  first=%s  scale=%.2f"
			% [col_poly.polygon.size(),
			   (str(col_poly.polygon[0]) if col_poly.polygon.size() > 0 else "—"),
			   (gfx_root.scale.x if is_instance_valid(gfx_root) else scale.x)])



	# A/V flavor
	if is_instance_valid(s_main):
		s_main.pitch_scale = cfg.sfx_pitch
	if is_instance_valid(s_left):
		s_left.pitch_scale = cfg.sfx_pitch
	if is_instance_valid(s_right):
		s_right.pitch_scale = cfg.sfx_pitch

	_light_base = base_light_energy * cfg.vfx_brightness

	var pitch_debug: float = s_main.pitch_scale if is_instance_valid(s_main) else 1.0
	var vis_scale: float = (gfx_root.scale.x if is_instance_valid(gfx_root) else scale.x)
	sdbg("CFG", "Applied %s (HP=%.0f, mass=%.2f, thrust=%.0f, torque=%.0f, damp=(%.2f/%.2f), scale=%.2f, pitch=%.2f, vfx=%.2f)"
		% [cfg.display_name, max_health, mass, thrust_force, torque_strength,
		   linear_damp_playfeel, angular_damp_playfeel, vis_scale, pitch_debug, cfg.vfx_brightness])


func _apply_collider_scale(f: float) -> void:
	if col_poly and _base_poly.size() > 0:
		var pts := PackedVector2Array()
		for p in _base_poly:
			pts.append(p * f)
		col_poly.polygon = pts
	elif col_shape and col_shape.shape:
		var sh := col_shape.shape
		if sh is CircleShape2D:
			(sh as CircleShape2D).radius = _base_radius * f
		elif sh is RectangleShape2D:
			(sh as RectangleShape2D).size = _base_rect * f
		elif sh is CapsuleShape2D:
			var c := sh as CapsuleShape2D
			c.radius = _base_capsule_radius * f
			c.height = _base_capsule_height * f
			
