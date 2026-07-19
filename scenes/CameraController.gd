extends Camera3D

@export var move_speed: float = 40.0
@export var zoom_speed: float = 8.0
@export var min_height: float = 10.0
@export var max_height: float = 300.0
@export var pan_sensitivity: float = 0.03

var _is_panning := false
var _last_mouse_pos := Vector2.ZERO

func _ready() -> void:
	# Von oben schauen
	rotation_degrees = Vector3(-90, 0, 0)
	position.y = 80.0

func _input(event: InputEvent) -> void:
	# Zoom mit Mausrad
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			position.y = max(min_height, position.y - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			position.y = min(max_height, position.y + zoom_speed)
		
		# Mittlere Maustaste = Pan starten/stoppen
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = event.pressed
			_last_mouse_pos = event.position

	# Pan mit gedrückter mittlerer Maustaste
	if event is InputEventMouseMotion and _is_panning:
		var delta = event.position - _last_mouse_pos
		_last_mouse_pos = event.position
		
		# Bewegung relativ zur Kamera-Ausrichtung (flach)
		var right = global_transform.basis.x
		var forward = -global_transform.basis.z
		# Da wir von oben schauen, nutzen wir X und Z
		right.y = 0
		forward.y = 0
		right = right.normalized()
		forward = forward.normalized()
		
		position += (-right * delta.x + forward * delta.y) * pan_sensitivity * (position.y * 0.02)

func _process(delta: float) -> void:
	# Optional: WASD / Pfeiltasten Bewegung
	var input_dir = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1
	
	if input_dir != Vector3.ZERO:
		input_dir = input_dir.normalized()
		# Geschwindigkeit abhängig von der Höhe (weiter weg = schneller)
		var speed = move_speed * (position.y * 0.015)
		position += input_dir * speed * delta
