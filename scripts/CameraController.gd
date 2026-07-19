extends Camera3D

@export var move_speed: float = 35.0
@export var zoom_speed: float = 7.0
@export var min_height: float = 4.0
@export var max_height: float = 1500.0
@export var pan_sensitivity: float = 0.035
@export var move_smooth: float = 9.0
@export var zoom_smooth: float = 7.0

var _target: Vector3
var _panning := false
var _last_mouse := Vector2.ZERO

func _ready() -> void:
	rotation_degrees = Vector3(-90, 0, 0)
	_target = position

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			var step = zoom_speed * (_target.y * 0.028)
			_target.y = max(min_height, _target.y - step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var step = zoom_speed * (_target.y * 0.028)
			_target.y = min(max_height, _target.y + step)
		
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_last_mouse = event.position

	if event is InputEventMouseMotion and _panning:
		var delta = event.position - _last_mouse
		_last_mouse = event.position
		# Deutlich schneller wenn man weit oben ist
		var sens = pan_sensitivity * (_target.y * 0.035)
		_target.x -= delta.x * sens
		_target.z -= delta.y * sens

func _process(delta: float) -> void:
	var dir = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	
	if dir != Vector3.ZERO:
		dir = dir.normalized()
		# Starke Höhenabhängigkeit: weit oben = deutlich schneller
		var height_factor = clamp(_target.y * 0.022, 0.4, 8.0)
		var speed = move_speed * height_factor
		_target += dir * speed * delta
	
	var t = 1.0 - exp(-move_smooth * delta)
	position.x = lerp(position.x, _target.x, t)
	position.z = lerp(position.z, _target.z, t)
	
	var zt = 1.0 - exp(-zoom_smooth * delta)
	position.y = lerp(position.y, _target.y, zt)
	
	rotation_degrees = Vector3(-90, 0, 0)
