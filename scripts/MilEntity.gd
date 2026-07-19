extends Node3D
class_name MilEntity

enum Type { LAND, AIR, NAVAL, BALLISTIC }

@export var entity_type: Type = Type.LAND
@export var move_speed: float = 6.0
@export var size: float = 8.5
@export var color: Color = Color(1.0, 0.9, 0.2)
@export var unit_name: String = ""
@export var nation_id: String = ""

var target_pos: Vector3
var selected := false
var mesh_instance: MeshInstance3D

var path: Array[Vector3] = []
var path_index: int = 0
var moving := false

## Called when unit arrives at a hex (path finished or teleported)
signal arrived(unit: MilEntity)

func _ready() -> void:
	target_pos = position
	_build_mesh()

func _process(delta: float) -> void:
	if not moving or path.is_empty():
		position = position.lerp(target_pos, 1.0 - exp(-move_speed * delta))
		return

	var waypoint = path[path_index]
	var goal = Vector3(waypoint.x, _height(), waypoint.z)
	position = position.lerp(goal, 1.0 - exp(-move_speed * delta))

	if position.distance_to(goal) < 0.8:
		path_index += 1
		if path_index >= path.size():
			moving = false
			position = goal
			target_pos = goal
			path.clear()
			arrived.emit(self)
		else:
			var next = path[path_index]
			target_pos = Vector3(next.x, _height(), next.z)

func _height() -> float:
	match entity_type:
		Type.LAND, Type.NAVAL:
			return 0.2
		Type.AIR:
			return size * 0.9		# clearly above land/naval
		Type.BALLISTIC:
			return size * 1.7		# above air
	return 0.2

func set_hex_position(pos: Vector3) -> void:
	var p = Vector3(pos.x, _height(), pos.z)
	target_pos = p
	position = p
	path.clear()
	moving = false

func follow_path(new_path: Array[Vector3]) -> void:
	if new_path.is_empty():
		return
	if new_path.size() == 1:
		set_hex_position(new_path[0])
		arrived.emit(self)
		return
	path = new_path
	path_index = 1
	moving = true
	var next = path[path_index]
	target_pos = Vector3(next.x, _height(), next.z)

func get_type_string() -> String:
	match entity_type:
		Type.LAND: return "land"
		Type.AIR: return "air"
		Type.NAVAL: return "naval"
		Type.BALLISTIC: return "ballistic"
	return "land"

func get_ground_pos() -> Vector3:
	return Vector3(position.x, 0.0, position.z)

func select() -> void:
	selected = true
	_update_color()

func deselect() -> void:
	selected = false
	_update_color()

func _update_color() -> void:
	if mesh_instance and mesh_instance.material_override:
		var mat = mesh_instance.material_override as StandardMaterial3D
		mat.albedo_color = Color(1.0, 0.45, 0.1) if selected else color

func _build_mesh() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	match entity_type:
		Type.LAND:
			_build_rectangle(st)
		Type.AIR:
			_build_pyramid(st, false)
		Type.NAVAL:
			_build_pyramid(st, true)
		Type.BALLISTIC:
			_build_sphere(st)

	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat

func _build_rectangle(st: SurfaceTool) -> void:
	var s = size * 0.45
	var y = 0.0
	var pts = [
		Vector3(-s, y, -s), Vector3(s, y, -s),
		Vector3(s, y, s), Vector3(-s, y, s)
	]
	for i in 4:
		st.add_vertex(pts[i])
		st.add_vertex(pts[(i + 1) % 4])

func _build_pyramid(st: SurfaceTool, inverted: bool) -> void:
	var s = size * 0.4
	var h = size * 0.65
	var top = Vector3(0.0, h if not inverted else -h, 0.0)
	var base = [
		Vector3(-s, 0.0, -s), Vector3(s, 0.0, -s),
		Vector3(s, 0.0, s), Vector3(-s, 0.0, s)
	]
	for i in 4:
		st.add_vertex(base[i])
		st.add_vertex(base[(i + 1) % 4])
	for p in base:
		st.add_vertex(p)
		st.add_vertex(top)

func _build_sphere(st: SurfaceTool) -> void:
	var r = size * 0.35
	var seg = 10
	for i in seg:
		var lat0 = PI * (-0.5 + float(i) / seg)
		var lat1 = PI * (-0.5 + float(i + 1) / seg)
		for j in seg:
			var lon0 = TAU * float(j) / seg
			var lon1 = TAU * float(j + 1) / seg
			var p1 = _sph(r, lat0, lon0)
			var p2 = _sph(r, lat0, lon1)
			var p3 = _sph(r, lat1, lon0)
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p1)
			st.add_vertex(p3)

func _sph(r: float, lat: float, lon: float) -> Vector3:
	return Vector3(
		r * cos(lat) * cos(lon),
		r * sin(lat),
		r * cos(lat) * sin(lon)
	)
