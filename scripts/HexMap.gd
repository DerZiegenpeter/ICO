@tool
extends Node3D

@export var json_path: String = "res://data/hex_minimal.json"
@export var nations_path: String = "res://data/nations.json"
@export var scale_factor: float = 100.0
@export var hex_size: float = 0.104
@export var edge_inset: float = 0.97
@export var flat_top: bool = true
## Center-to-center distance for neighbors (auto-derived if <= 0)
@export var neighbor_dist: float = 0.0

@export var land_color: Color = Color(0.2, 0.72, 0.28)
@export var ocean_color: Color = Color(0.15, 0.42, 0.92)
@export var lake_color: Color = Color(0.4, 0.75, 0.98)

var mesh_instance: MeshInstance3D
var occupation_mesh_instance: MeshInstance3D
var hex_centers: Array[Vector3] = []
var hex_types: Array[String] = []
var hex_owners: Array[String] = []
var hex_controllers: Array[String] = []
var spatial_hash: Dictionary = {}
var _cell_size: float = 20.0
var _neighbor_range: float = 22.0

## nation_id -> Color
var nation_colors: Dictionary = {}

func _ready() -> void:
	print("=== HexMap startet ===")
	_load_nations()
	load_and_draw()

func _load_nations() -> void:
	nation_colors.clear()
	if not FileAccess.file_exists(nations_path):
		print("nations.json nicht gefunden – verwende Fallback-Farben")
		nation_colors["GER"] = Color("#555555")
		nation_colors["POL"] = Color("#c41e3a")
		return
	var file = FileAccess.open(nations_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	for n in json.data:
		var id = str(n.get("id", ""))
		var col = str(n.get("color", "#888888"))
		if id != "":
			nation_colors[id] = Color(col)
	print("Nationen geladen: ", nation_colors.keys())

func get_nation_color(nation_id: String) -> Color:
	return nation_colors.get(nation_id, Color(0.7, 0.7, 0.7))

## Temporary prototype ownership – replace later with real border data
func _guess_owner(lon: float, lat: float) -> String:
	# East Prussia roughly German
	if lon >= 19.5 and lat >= 53.2 and lat <= 55.3:
		return "GER"
	# Rough split near the Oder (~14.8–15.0)
	if lon < 14.85:
		return "GER"
	return "POL"

func load_and_draw() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	if occupation_mesh_instance and is_instance_valid(occupation_mesh_instance):
		occupation_mesh_instance.queue_free()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HexWireframe"
	add_child(mesh_instance)

	occupation_mesh_instance = MeshInstance3D.new()
	occupation_mesh_instance.name = "OccupationOverlay"
	add_child(occupation_mesh_instance)

	hex_centers.clear()
	hex_types.clear()
	hex_owners.clear()
	hex_controllers.clear()
	spatial_hash.clear()

	_neighbor_range = neighbor_dist if neighbor_dist > 0.0 else (hex_size * scale_factor * 2.15)
	_cell_size = _neighbor_range * 1.25
	print("Neighbor range: ", _neighbor_range)

	if not FileAccess.file_exists(json_path):
		push_error("Datei nicht gefunden: " + json_path)
		return

	var file = FileAccess.open(json_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON Parse Fehler")
		return
	file.close()

	var data = json.data
	print("Hexes: ", data.size())

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var st_occ = SurfaceTool.new()
	st_occ.begin(Mesh.PRIMITIVE_LINES)

	for i in data.size():
		var h = data[i]
		var lon = float(h.get("lon", 0.0))
		var lat = float(h.get("lat", 0.0))
		var typ = str(h.get("type", "ocean")).to_lower()

		var owner := ""
		var controller := ""
		if typ == "land":
			owner = _guess_owner(lon, lat)
			controller = owner

		var color = ocean_color
		if typ == "land":
			color = get_nation_color(owner)
		elif typ == "lake":
			color = lake_color

		var center = Vector3(lon * scale_factor, 0.0, -lat * scale_factor)
		var idx = hex_centers.size()
		hex_centers.append(center)
		hex_types.append(typ)
		hex_owners.append(owner)
		hex_controllers.append(controller)

		var key = _hash_key(center)
		if not spatial_hash.has(key):
			spatial_hash[key] = PackedInt32Array()
		spatial_hash[key].append(idx)

		_add_hex(st, center, color)

		# Occupation overlay (controller != owner) → dashed in controller color
		if typ == "land" and controller != "" and controller != owner:
			_add_hex_dashed(st_occ, center, get_nation_color(controller))

		if i > 0 and i % 50000 == 0:
			print("  ... ", i)

	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat

	var mesh_occ = st_occ.commit()
	var mat_occ = StandardMaterial3D.new()
	mat_occ.vertex_color_use_as_albedo = true
	mat_occ.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_occ.cull_mode = BaseMaterial3D.CULL_DISABLED
	occupation_mesh_instance.mesh = mesh_occ
	occupation_mesh_instance.material_override = mat_occ

	_center_camera(mesh)
	print("✅ HexMap fertig – ", hex_centers.size(), " Hexes")

func rebuild_occupation_overlay() -> void:
	if occupation_mesh_instance == null or not is_instance_valid(occupation_mesh_instance):
		return
	var st_occ = SurfaceTool.new()
	st_occ.begin(Mesh.PRIMITIVE_LINES)
	for i in hex_centers.size():
		if hex_types[i] != "land":
			continue
		var owner = hex_owners[i]
		var controller = hex_controllers[i]
		if controller != "" and controller != owner:
			_add_hex_dashed(st_occ, hex_centers[i], get_nation_color(controller))
	var mesh_occ = st_occ.commit()
	var mat_occ = StandardMaterial3D.new()
	mat_occ.vertex_color_use_as_albedo = true
	mat_occ.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_occ.cull_mode = BaseMaterial3D.CULL_DISABLED
	occupation_mesh_instance.mesh = mesh_occ
	occupation_mesh_instance.material_override = mat_occ

func set_controller(index: int, nation_id: String) -> void:
	if index < 0 or index >= hex_controllers.size():
		return
	if hex_types[index] != "land":
		return
	if hex_controllers[index] == nation_id:
		return
	hex_controllers[index] = nation_id
	rebuild_occupation_overlay()
	print("Controller Hex ", index, " → ", nation_id)

func get_hex_owner(index: int) -> String:
	if index < 0 or index >= hex_owners.size():
		return ""
	return hex_owners[index]

func get_hex_controller(index: int) -> String:
	if index < 0 or index >= hex_controllers.size():
		return ""
	return hex_controllers[index]

func _hash_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / _cell_size)), int(floor(pos.z / _cell_size)))

func get_closest_hex_index(world_pos: Vector3) -> int:
	if hex_centers.is_empty():
		return -1

	var key = _hash_key(world_pos)
	var best_i := -1
	var best_d := INF

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k = Vector2i(key.x + dx, key.y + dz)
			if not spatial_hash.has(k):
				continue
			for idx in spatial_hash[k]:
				var d = world_pos.distance_squared_to(hex_centers[idx])
				if d < best_d:
					best_d = d
					best_i = idx

	if best_i >= 0:
		return best_i

	best_i = 0
	best_d = world_pos.distance_squared_to(hex_centers[0])
	for i in hex_centers.size():
		var d = world_pos.distance_squared_to(hex_centers[i])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i

func get_closest_hex_center(world_pos: Vector3) -> Vector3:
	var i = get_closest_hex_index(world_pos)
	return hex_centers[i] if i >= 0 else world_pos

func lonlat_to_world(lon: float, lat: float) -> Vector3:
	return Vector3(lon * scale_factor, 0.0, -lat * scale_factor)

func get_neighbors(index: int) -> Array[int]:
	var result: Array[int] = []
	if index < 0 or index >= hex_centers.size():
		return result

	var pos = hex_centers[index]
	var key = _hash_key(pos)
	var max_d2 = _neighbor_range * _neighbor_range

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k = Vector2i(key.x + dx, key.y + dz)
			if not spatial_hash.has(k):
				continue
			for other_i in spatial_hash[k]:
				if other_i == index:
					continue
				if pos.distance_squared_to(hex_centers[other_i]) <= max_d2:
					result.append(other_i)
	return result

func is_passable(index: int, unit_type: String) -> bool:
	if index < 0 or index >= hex_types.size():
		return false
	var t = hex_types[index]
	match unit_type:
		"land":
			return t == "land"
		"naval":
			return t == "ocean" or t == "lake"
		"air", "ballistic":
			return true
	return false

func find_path(from_pos: Vector3, to_pos: Vector3, unit_type: String) -> Array[Vector3]:
	var start_i = get_closest_hex_index(from_pos)
	var goal_i = get_closest_hex_index(to_pos)

	if start_i < 0 or goal_i < 0:
		return []
	if start_i == goal_i:
		return [hex_centers[start_i]]
	if not is_passable(goal_i, unit_type):
		print("Ziel nicht begehbar für ", unit_type, " (type=", hex_types[goal_i], ")")
		return []
	if not is_passable(start_i, unit_type):
		print("Start nicht begehbar für ", unit_type, " (type=", hex_types[start_i], ")")
		return []

	var open: Array[int] = [start_i]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_i: 0.0}
	var f_score: Dictionary = {start_i: hex_centers[start_i].distance_to(hex_centers[goal_i])}
	var closed: Dictionary = {}

	var max_iter = 12000
	var iter = 0

	while open.size() > 0 and iter < max_iter:
		iter += 1

		var current = open[0]
		var best_f = f_score.get(current, INF)
		for n in open:
			var f = f_score.get(n, INF)
			if f < best_f:
				best_f = f
				current = n

		if current == goal_i:
			print("Pfad gefunden in ", iter, " Iterationen")
			return _reconstruct_path(came_from, current)

		open.erase(current)
		closed[current] = true

		for nb in get_neighbors(current):
			if closed.has(nb):
				continue
			if not is_passable(nb, unit_type):
				continue

			var tentative = g_score[current] + hex_centers[current].distance_to(hex_centers[nb])
			if not g_score.has(nb) or tentative < g_score[nb]:
				came_from[nb] = current
				g_score[nb] = tentative
				f_score[nb] = tentative + hex_centers[nb].distance_to(hex_centers[goal_i])
				if not open.has(nb):
					open.append(nb)

	print("Kein Pfad gefunden (", unit_type, ") nach ", iter, " Iterationen")
	return []

func _reconstruct_path(came_from: Dictionary, current: int) -> Array[Vector3]:
	var path: Array[Vector3] = [hex_centers[current]]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(hex_centers[current])
	return path

func _add_hex(st: SurfaceTool, center: Vector3, color: Color) -> void:
	var pts: Array[Vector3] = []
	var r = hex_size * scale_factor * edge_inset
	for i in 6:
		var angle_deg = 60.0 * i
		if not flat_top:
			angle_deg -= 30.0
		var angle = deg_to_rad(angle_deg)
		pts.append(Vector3(center.x + cos(angle) * r, 0.0, center.z + sin(angle) * r))
	for i in 6:
		st.set_color(color)
		st.add_vertex(pts[i])
		st.set_color(color)
		st.add_vertex(pts[(i + 1) % 6])

func _add_hex_dashed(st: SurfaceTool, center: Vector3, color: Color) -> void:
	var pts: Array[Vector3] = []
	var r = hex_size * scale_factor * edge_inset
	for i in 6:
		var angle_deg = 60.0 * i
		if not flat_top:
			angle_deg -= 30.0
		var angle = deg_to_rad(angle_deg)
		pts.append(Vector3(center.x + cos(angle) * r, 0.0, center.z + sin(angle) * r))

	var dash_len = 1.8
	var gap_len = 1.4
	for i in 6:
		var a = pts[i]
		var b = pts[(i + 1) % 6]
		var edge = b - a
		var edge_len = edge.length()
		if edge_len < 0.001:
			continue
		var dir = edge / edge_len
		var pos = 0.0
		var drawing = true
		while pos < edge_len:
			var seg = dash_len if drawing else gap_len
			var next_pos = minf(pos + seg, edge_len)
			if drawing:
				st.set_color(color)
				st.add_vertex(a + dir * pos)
				st.set_color(color)
				st.add_vertex(a + dir * next_pos)
			pos = next_pos
			drawing = not drawing

func _center_camera(mesh: Mesh) -> void:
	var aabb = mesh.get_aabb()
	var center = aabb.get_center()
	var size = aabb.size
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	cam.position = Vector3(center.x, max(size.x, size.z) * 0.55, center.z)
	cam.rotation_degrees = Vector3(-90, 0, 0)
