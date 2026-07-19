extends Camera3D

@export var orbit_radius: float = 90.0
@export var min_radius: float = 15.0
@export var max_radius: float = 300.0
@export var zoom_step: float = 1.5
@export var zoom_lerp_speed: float = 6.0
@export var rotation_sensitivity: float = 0.0022
@export var rotation_inertia: float = 0.93
@export var pitch_limit: float = 1.55

var _is_dragging := false
var _yaw: float = 0.0
var _pitch: float = 0.35
var _rotation_velocity := Vector2.ZERO
var _target_radius: float

func _ready() -> void:
	_target_radius = orbit_radius
	_update_camera_position()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_radius = max(min_radius, _target_radius - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_radius = min(max_radius, _target_radius + zoom_step)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = event.pressed

	if event is InputEventMouseMotion and _is_dragging:
		_rotation_velocity.x -= event.relative.x * rotation_sensitivity
		_rotation_velocity.y += event.relative.y * rotation_sensitivity

func _process(delta: float) -> void:
	orbit_radius = lerp(orbit_radius, _target_radius, zoom_lerp_speed * delta)
	
	if _rotation_velocity.length() > 0.0001:
		_yaw += _rotation_velocity.x
		_pitch += _rotation_velocity.y
		_pitch = clamp(_pitch, -pitch_limit, pitch_limit)
		_rotation_velocity *= rotation_inertia
	else:
		_rotation_velocity = Vector2.ZERO

	_update_camera_position()

func _update_camera_position() -> void:
	var x = orbit_radius * cos(_pitch) * sin(_yaw)
	var y = orbit_radius * sin(_pitch)
	var z = orbit_radius * cos(_pitch) * cos(_yaw)
	position = Vector3(x, y, z)
	look_at(Vector3.ZERO, Vector3.UP)
