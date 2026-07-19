extends Node3D

@export var hex_map_path: NodePath = NodePath("../HexMap")
@export var oob_path: String = "res://data/oob.json"

var hex_map: Node3D
var selected: MilEntity = null
var units: Array[MilEntity] = []

func _ready() -> void:
	hex_map = get_node_or_null(hex_map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_oob()

func _load_oob() -> void:
	if not FileAccess.file_exists(oob_path):
		push_error("oob.json nicht gefunden")
		return
	var file = FileAccess.open(oob_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	
	for entry in json.data:
		var typ_str = str(entry.get("type", "land")).to_lower()
		var typ = MilEntity.Type.LAND
		match typ_str:
			"air": typ = MilEntity.Type.AIR
			"naval": typ = MilEntity.Type.NAVAL
			"ballistic": typ = MilEntity.Type.BALLISTIC
		
		var lon = float(entry.get("lon", 10.0))
		var lat = float(entry.get("lat", 51.0))
		var unit_name = str(entry.get("name", "Unit"))
		
		var world_pos = hex_map.lonlat_to_world(lon, lat)
		world_pos = hex_map.get_closest_hex_center(world_pos)
		
		var unit = spawn_unit(typ, world_pos)
		unit.unit_name = unit_name
		unit.name = unit_name
	
	print("OOB geladen – Einheiten: ", units.size())

func spawn_unit(type: MilEntity.Type, hex_pos: Vector3) -> MilEntity:
	var unit = MilEntity.new()
	unit.entity_type = type
	add_child(unit)
	unit.set_hex_position(hex_pos)
	units.append(unit)
	return unit

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var world_pos = _screen_to_ground(event.position)
	if event.button_index == MOUSE_BUTTON_LEFT:
		_try_select(world_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_try_move(world_pos)

func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null: return Vector3.ZERO
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.00001: return Vector3.ZERO
	return from + dir * (-from.y / dir.y)

func _try_select(world_pos: Vector3) -> void:
	var closest: MilEntity = null
	var best_dist := 1.6
	for u in units:
		var d = u.position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			closest = u
	if selected: selected.deselect()
	selected = closest
	if selected:
		selected.select()
		print("Ausgewählt: ", selected.unit_name)
	else:
		print("Nichts ausgewählt")

func _try_move(world_pos: Vector3) -> void:
	if selected == null or hex_map == null:
		return
	
	var unit_type = selected.get_type_string()
	print("Suche Pfad für ", unit_type, "...")
	
	var path = hex_map.find_path(selected.position, world_pos, unit_type)
	
	if path.is_empty():
		print("Kein gültiger Pfad")
		return
	
	print("Pfad mit ", path.size(), " Hexes gefunden")
	selected.follow_path(path)
