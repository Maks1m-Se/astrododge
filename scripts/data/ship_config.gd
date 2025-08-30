extends Resource
class_name ShipConfig

@export var id: String = "scout"
@export var display_name: String = "Scout"
@export_multiline var description: String = "Small, agile, low health."

# Core stats
@export_range(1.0, 500.0, 1.0) var max_health: float = 60.0
@export_range(0.01, 20.0, 0.1)  var mass: float = 1.0
@export_range(0.25, 2.0, 0.01) var scale: float = 1.0

# Handling
@export_range(0.0, 5000.0, 10.0) var thrust_force: float = 900.0
@export_range(0.0, 5000.0, 10.0) var torque_strength: float = 450.0
@export_range(0.0, 5.0, 0.05)    var linear_damp: float = 0.10
@export_range(0.0, 5.0, 0.05)    var angular_damp: float = 0.10

# A/V flavor
@export_range(0.25, 2.0, 0.01)   var sfx_pitch: float = 1.00
@export_range(0.25, 2.0, 0.01)   var vfx_brightness: float = 1.00

@export var vfx_plume_mult: float = 1.0  # visual plume size multiplier (independent of thrust)
