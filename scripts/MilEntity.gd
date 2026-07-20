extends Node3D
class_name MilEntity

enum Type { LAND, AIR, NAVAL, BALLISTIC }

@export var entity_type: Type = Type.LAND
@export var move_speed: float = 6.0
@export var size: float = 13.0
@export var color: Color = Color(1.0, 0.9, 0.2)
@export var unit_name: String = ""
@export var nation: String = ""

@export var move_points_max: int = 4
var move_points: int = 4
@export var combat_points_max: int = 2
var combat_points: int = 2

var committed_move: int = 0
var committed_combat: int = 0

var target_pos: Vector3
var selected := false
var mesh_instance: MeshInstance3D

var path: Array[Vector3] = []
var path_index: int = 0
var moving := false

var pending_path: Array[Vector3] = []
var pending_combat_target: MilEntity = null

signal arrived_at_hex(unit: MilEntity)
signal order_finished(unit: MilEntity)

var ap_move_boxes: Array[MeshInstance3D] = []
var ap_combat_boxes: Array[MeshInstance3D] = []

func _ready() -> void:
	target_pos = position
	move_points = move_points_max
	combat_points = combat_points_max
	_build_mesh()
	_build_ap_bars()
	_update_ap_bars()

func _process(delta: float) -> void:
	if not moving or path.is_empty():
		position = position.lerp(target_pos, 1.0 - exp(-move_speed * delta))
		return

	var waypoint = path[path_index]
	var dest = Vector3(waypoint.x, _height_for_type(), waypoint.z)
	position = position.lerp(dest, 1.0 - exp(-move_speed * delta))

	if position.distance_to(dest) < 0.8:
		position = dest
		target_pos = dest
		arrived_at_hex.emit(self)

		path_index += 1
		if path_index >= path.size():
			moving = false
			path.clear()
			order_finished.emit(self)
		else:
			var next = path[path_index]
			target_pos = Vector3(next.x, _height_for_type(), next.z)

func _height_for_type() -> float:
	match entity_type:
		Type.LAND, Type.NAVAL:
			return 0.2
		Type.AIR:
			return size * 0.9
		Type.BALLISTIC:
			return size * 1.7
	return 0.2

func set_hex_position(pos: Vector3) -> void:
	var p = Vector3(pos.x, _height_for_type(), pos.z)
	target_pos = p
	position = p
	path.clear()
	moving = false

func set_order(new_path: Array[Vector3]) -> void:
	if new_path.is_empty() or new_path.size() < 2:
		pending_path.clear()
		committed_move = 0
		_update_ap_bars()
		return
	pending_path = new_path.duplicate()
	var steps = pending_path.size() - 1
	committed_move = mini(steps, move_points)
	_update_ap_bars()

func clear_order() -> void:
	pending_path.clear()
	committed_move = 0
	_update_ap_bars()

func has_order() -> bool:
	return pending_path.size() >= 2

func set_combat_order(target: MilEntity) -> void:
	if combat_points - committed_combat <= 0:
		return
	pending_combat_target = target
	committed_combat = 1
	_update_ap_bars()

func clear_combat_order() -> void:
	pending_combat_target = null
	committed_combat = 0
	_update_ap_bars()

func has_combat_order() -> bool:
	return pending_combat_target != null and is_instance_valid(pending_combat_target)

func execute_turn_movement() -> void:
	if pending_path.size() < 2:
		committed_move = 0
		_update_ap_bars()
		return
	var steps = mini(move_points, pending_path.size() - 1)
	if steps <= 0:
		return
	var segment: Array[Vector3] = pending_path.slice(0, steps + 1)
	if steps + 1 < pending_path.size():
		pending_path = pending_path.slice(steps)
	else:
		pending_path.clear()
	move_points -= steps
	committed_move = 0
	_update_ap_bars()
	follow_path(segment)

func execute_combat_order() -> void:
	if not has_combat_order():
		return
	combat_points = maxi(0, combat_points - 1)
	pending_combat_target = null
	committed_combat = 0
	_update_ap_bars()

func reset_points() -> void:
	move_points = move_points_max
	combat_points = combat_points_max
	if pending_path.size() >= 2:
		var steps = pending_path.size() - 1
		committed_move = mini(steps, move_points)
	else:
		committed_move = 0
	committed_combat = 0
	pending_combat_target = null
	_update_ap_bars()

func follow_path(new_path: Array[Vector3]) -> void:
	if new_path.is_empty():
		return
	if new_path.size() == 1:
		set_hex_position(new_path[0])
		arrived_at_hex.emit(self)
		order_finished.emit(self)
		return
	path = new_path.duplicate()
	path_index = 1
	moving = true
	var next = path[path_index]
	target_pos = Vector3(next.x, _height_for_type(), next.z)

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

func _build_ap_bars() -> void:
	## Horizontal row to the LEFT of the unit (visible from top-down)
	var box_size := 1.8
	var gap := 0.35
	var y := 0.35
	var z := 0.0
	var start_x := -size * 0.55 - 2.0

	# Move AP: green, left to right away from unit
	for i in move_points_max:
		var mi = _make_ap_box(Color(0.2, 0.85, 0.25), box_size)
		mi.position = Vector3(start_x - i * (box_size + gap), y, z)
		add_child(mi)
		ap_move_boxes.append(mi)

	# Combat AP: red, further left with a small gap
	var combat_start = start_x - move_points_max * (box_size + gap) - gap * 2.0
	for i in combat_points_max:
		var mi = _make_ap_box(Color(0.9, 0.15, 0.12), box_size)
		mi.position = Vector3(combat_start - i * (box_size + gap), y, z)
		add_child(mi)
		ap_combat_boxes.append(mi)

func _make_ap_box(col: Color, s: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs = s * 0.5
	var y = 0.05
	var verts = [
		Vector3(-hs, y, -hs), Vector3(hs, y, -hs),
		Vector3(hs, y, hs), Vector3(-hs, y, hs)
	]
	st.set_color(col)
	st.add_vertex(verts[0]); st.add_vertex(verts[1]); st.add_vertex(verts[2])
	st.set_color(col)
	st.add_vertex(verts[0]); st.add_vertex(verts[2]); st.add_vertex(verts[3])
	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	mi.mesh = mesh
	mi.material_override = mat
	return mi

func _update_ap_bars() -> void:
	var available_move = maxi(0, move_points - committed_move)
	for i in ap_move_boxes.size():
		var lit = i < available_move
		_set_box_state(ap_move_boxes[i], lit, Color(0.2, 0.85, 0.25))

	var available_combat = maxi(0, combat_points - committed_combat)
	for i in ap_combat_boxes.size():
		var lit = i < available_combat
		_set_box_state(ap_combat_boxes[i], lit, Color(0.9, 0.15, 0.12))

func _set_box_state(mi: MeshInstance3D, lit: bool, active_col: Color) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var mat = mi.material_override as StandardMaterial3D
	if mat == null:
		return
	if lit:
		mat.albedo_color = Color(1, 1, 1, 1)
		mat.emission = active_col
		mat.emission_energy_multiplier = 1.6
		mi.visible = true
	else:
		mat.albedo_color = Color(0.35, 0.35, 0.35, 0.45)
		mat.emission = Color(0.25, 0.25, 0.25)
		mat.emission_energy_multiplier = 0.3
		mi.visible = true

func _build_rectangle(st: SurfaceTool) -> void:
	var s = size * 0.45
	var y = 0.15
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
