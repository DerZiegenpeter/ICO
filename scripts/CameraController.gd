extends Camera3D

@export var orbit_radius: float = 35.0
@export var zoom_step: float = 0.5
@export var zoom_lerp_speed: float = 9.0
@export var rotation_sensitivity: float = 0.0016
@export var rotation_inertia: float = 0.935
@export var min_radius: float = 5.0
@export var max_radius: float = 100.0

var _is_dragging := false
var _rotation_velocity := Vector2.ZERO
var _target_radius: float

func _ready() -> void:
	_target_radius = orbit_radius
	position = Vector3(0, 0, orbit_radius)
	look_at(Vector3.ZERO, Vector3.UP)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_radius = max(min_radius, _target_radius - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_radius = min(max_radius, _target_radius + zoom_step)

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging = event.pressed

	if event is InputEventMouseMotion and _is_dragging:
		# West/Ost invertiert + langsames, smootheres Draggen
		_rotation_velocity.x -= event.relative.x * rotation_sensitivity
		_rotation_velocity.y += event.relative.y * rotation_sensitivity

func _process(delta: float) -> void:
	# Smooth Zoom mit Nachgleiten
	orbit_radius = lerp(orbit_radius, _target_radius, zoom_lerp_speed * delta)

	# Orbit um den Mittelpunkt der Sphäre (träg + smooth)
	if _rotation_velocity.length() > 0.0005:
		var pos := position

		# Yaw (links/rechts)
		pos = pos.rotated(Vector3.UP, _rotation_velocity.x)

		# Pitch (hoch/runter)
		var right := pos.cross(Vector3.UP).normalized()
		pos = pos.rotated(right, _rotation_velocity.y)

		position = pos
		look_at(Vector3.ZERO, Vector3.UP)

		_rotation_velocity *= rotation_inertia
	else:
		_rotation_velocity = Vector2.ZERO

	# Abstand zum Zentrum halten
	position = position.normalized() * orbit_radius
	look_at(Vector3.ZERO, Vector3.UP)
