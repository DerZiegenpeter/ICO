@tool
extends Node3D

@export var json_path: String = "res://data/hex_minimal2.json"
@export var nations_path: String = "res://data/nations.json"
@export var scale_factor: float = 100.0
@export var hex_size: float = 0.104
@export var edge_inset: float = 0.97
@export var flat_top: bool = true
@export var neighbor_dist: float = 0.0

@export var land_color: Color = Color(0.2, 0.72, 0.28)
@export var unowned_land_color: Color = Color(1.0, 0.2, 0.75)  # Pink – land ohne Nation
@export var ocean_color: Color = Color(0.15, 0.42, 0.92)
@export var lake_color: Color = Color(0.4, 0.75, 0.98)

@export var political_full_height: float = 380.0
@export var political_fade_height: float = 140.0
@export var hex_full_height: float = 90.0
@export var hex_fade_height: float = 260.0
@export var city_full_height: float = 55.0
@export var city_fade_height: float = 120.0

var mesh_instance: MeshInstance3D
var occupation_mesh_instance: MeshInstance3D
var city_lights_mesh_instance: MeshInstance3D
var political_mesh_instance: MeshInstance3D

var mat_hex: StandardMaterial3D
var mat_occ: StandardMaterial3D
var mat_city: StandardMaterial3D
var mat_political: StandardMaterial3D

var hex_centers: Array[Vector3] = []
var hex_types: Array[String] = []
var hex_owners: Array[String] = []
var hex_controllers: Array[String] = []
var hex_states: Array[String] = []
var hex_cities: Array[String] = []
var hex_rivers: Array[String] = []
var spatial_hash: Dictionary = {}
var _cell_size: float = 20.0
var _neighbor_range: float = 22.0

var nation_colors: Dictionary = {}

func _ready() -> void:
	print("=== HexMap startet ===")
	_load_nations()
	load_and_draw()

func _process(_delta: float) -> void:
	_update_zoom_fade()

func _update_zoom_fade() -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var h = cam.position.y

	var pol_alpha = smoothstep(political_fade_height, political_full_height, h)
	var hex_alpha = 1.0 - smoothstep(hex_full_height, hex_fade_height, h)
	var city_alpha = 1.0 - smoothstep(city_full_height, city_fade_height, h)

	if mat_political:
		mat_political.albedo_color = Color(1, 1, 1, pol_alpha)
	if mat_hex:
		mat_hex.albedo_color = Color(1, 1, 1, hex_alpha)
	if mat_occ:
		mat_occ.albedo_color = Color(1, 1, 1, hex_alpha)
	if mat_city:
		mat_city.albedo_color = Color(1, 1, 1, city_alpha)
		mat_city.emission_energy_multiplier = 3.5 * city_alpha

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
	print("Nationen geladen: ", nation_colors.size(), " → ", nation_colors.keys())

func get_nation_color(nation_id: String) -> Color:
	if nation_id == "":
		return unowned_land_color
	return nation_colors.get(nation_id, Color(0.55, 0.55, 0.5))

## City / river name from new schema (city bool + city_name) or legacy fields
func _read_place_name(h: Dictionary, flag_key: String, name_key: String) -> String:
	var name_val = h.get(name_key, null)
	if name_val != null:
		var s = str(name_val).strip_edges()
		if s != "" and s.to_lower() != "null" and s.to_lower() != "false":
			return s
	var flag = h.get(flag_key, null)
	if typeof(flag) == TYPE_BOOL:
		return flag_key if flag else ""  # "city" / "river" as placeholder
	if typeof(flag) == TYPE_STRING:
		var s2 = str(flag).strip_edges()
		if s2 == "" or s2.to_lower() in ["false", "0", "null"]:
			return ""
		if s2.to_lower() == "true":
			return flag_key
		return s2
	return ""

func load_and_draw() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	if occupation_mesh_instance and is_instance_valid(occupation_mesh_instance):
		occupation_mesh_instance.queue_free()
	if city_lights_mesh_instance and is_instance_valid(city_lights_mesh_instance):
		city_lights_mesh_instance.queue_free()
	if political_mesh_instance and is_instance_valid(political_mesh_instance):
		political_mesh_instance.queue_free()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HexWireframe"
	add_child(mesh_instance)

	occupation_mesh_instance = MeshInstance3D.new()
	occupation_mesh_instance.name = "OccupationOverlay"
	add_child(occupation_mesh_instance)

	city_lights_mesh_instance = MeshInstance3D.new()
	city_lights_mesh_instance.name = "CityLights"
	add_child(city_lights_mesh_instance)

	political_mesh_instance = MeshInstance3D.new()
	political_mesh_instance.name = "PoliticalMap"
	add_child(political_mesh_instance)

	hex_centers.clear()
	hex_types.clear()
	hex_owners.clear()
	hex_controllers.clear()
	hex_states.clear()
	hex_cities.clear()
	hex_rivers.clear()
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

	var st_city = SurfaceTool.new()
	st_city.begin(Mesh.PRIMITIVE_POINTS)

	var st_pol = SurfaceTool.new()
	st_pol.begin(Mesh.PRIMITIVE_TRIANGLES)

	var city_count := 0
	var owned_count := 0
	var unowned_land := 0

	for i in data.size():
		var h = data[i]
		var lon = float(h.get("lon", 0.0))
		var lat = float(h.get("lat", 0.0))
		var typ = str(h.get("type", "ocean")).to_lower()

		var city_name := _read_place_name(h, "city", "city_name")
		var river_name := _read_place_name(h, "river", "river_name")

		# Owner / controller ONLY from JSON – no GER/POL geographic guess
		var owner := str(h.get("owner", "")).strip_edges()
		var controller := str(h.get("controller", "")).strip_edges()
		var state := str(h.get("state", "")).strip_edges()
		if owner.to_lower() in ["null", "none"]:
			owner = ""
		if controller.to_lower() in ["null", "none"]:
			controller = ""
		if typ == "land" and controller == "" and owner != "":
			controller = owner
		if owner != "":
			owned_count += 1
		elif typ == "land":
			unowned_land += 1

		var color = ocean_color
		if typ == "land":
			# Pink if land has no nation – easy to spot gaps
			color = get_nation_color(owner) if owner != "" else unowned_land_color
		elif typ == "lake":
			color = lake_color

		var center = Vector3(lon * scale_factor, 0.0, -lat * scale_factor)
		var idx = hex_centers.size()
		hex_centers.append(center)
		hex_types.append(typ)
		hex_owners.append(owner)
		hex_controllers.append(controller)
		hex_states.append(state)
		hex_cities.append(city_name)
		hex_rivers.append(river_name)

		var key = _hash_key(center)
		if not spatial_hash.has(key):
			spatial_hash[key] = PackedInt32Array()
		spatial_hash[key].append(idx)

		_add_hex(st, center, color)

		if typ == "land":
			_add_hex_filled(st_pol, center, color)

		if typ == "land" and controller != "" and owner != "" and controller != owner:
			_add_hex_dashed(st_occ, center, get_nation_color(controller))

		if city_name != "" and typ == "land":
			_add_city_lights(st_city, center)
			city_count += 1

		if i > 0 and i % 50000 == 0:
			print("  ... ", i)

	var mesh = st.commit()
	mat_hex = StandardMaterial3D.new()
	mat_hex.vertex_color_use_as_albedo = true
	mat_hex.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_hex.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_hex.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_hex.albedo_color = Color(1, 1, 1, 0.0)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat_hex

	var mesh_occ = st_occ.commit()
	mat_occ = StandardMaterial3D.new()
	mat_occ.vertex_color_use_as_albedo = true
	mat_occ.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_occ.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_occ.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_occ.albedo_color = Color(1, 1, 1, 0.0)
	occupation_mesh_instance.mesh = mesh_occ
	occupation_mesh_instance.material_override = mat_occ

	var mesh_city = st_city.commit()
	mat_city = StandardMaterial3D.new()
	mat_city.vertex_color_use_as_albedo = true
	mat_city.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_city.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_city.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_city.use_point_size = true
	mat_city.point_size = 3.5
	mat_city.emission_enabled = true
	mat_city.emission = Color(1.0, 0.97, 0.85)
	mat_city.emission_energy_multiplier = 0.0
	mat_city.albedo_color = Color(1, 1, 1, 0.0)
	city_lights_mesh_instance.mesh = mesh_city
	city_lights_mesh_instance.material_override = mat_city

	var mesh_pol = st_pol.commit()
	mat_political = StandardMaterial3D.new()
	mat_political.vertex_color_use_as_albedo = true
	mat_political.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_political.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_political.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_political.albedo_color = Color(1, 1, 1, 1.0)
	political_mesh_instance.mesh = mesh_pol
	political_mesh_instance.material_override = mat_political

	_center_camera(mesh)
	_update_zoom_fade()
	print("✅ HexMap fertig – ", hex_centers.size(), " Hexes, ", city_count, " Städte, ", owned_count, " mit Owner, ", unowned_land, " Land ohne Nation (pink)")

func _add_hex_filled(st: SurfaceTool, center: Vector3, color: Color) -> void:
	var pts: Array[Vector3] = []
	var r = hex_size * scale_factor * edge_inset
	var y = -0.05
	for i in 6:
		var angle_deg = 60.0 * i
		if not flat_top:
			angle_deg -= 30.0
		var angle = deg_to_rad(angle_deg)
		pts.append(Vector3(center.x + cos(angle) * r, y, center.z + sin(angle) * r))
	var c = Vector3(center.x, y, center.z)
	for i in 6:
		st.set_color(color)
		st.add_vertex(c)
		st.set_color(color)
		st.add_vertex(pts[i])
		st.set_color(color)
		st.add_vertex(pts[(i + 1) % 6])

func _add_city_lights(st: SurfaceTool, center: Vector3) -> void:
	var r = hex_size * scale_factor * edge_inset * 0.82
	var num_lights = randi_range(18, 38)
	for _i in num_lights:
		var angle = randf() * TAU
		var dist = r * sqrt(randf())
		var px = center.x + cos(angle) * dist
		var pz = center.z + sin(angle) * dist
		var py = 0.12 + randf() * 0.08
		st.set_color(Color(1.0, 0.97, 0.88))
		st.add_vertex(Vector3(px, py, pz))

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
		if controller != "" and owner != "" and controller != owner:
			_add_hex_dashed(st_occ, hex_centers[i], get_nation_color(controller))
	var mesh_occ = st_occ.commit()
	occupation_mesh_instance.mesh = mesh_occ

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

func get_hex_state(index: int) -> String:
	if index < 0 or index >= hex_states.size():
		return ""
	return hex_states[index]

func get_hex_city(index: int) -> String:
	if index < 0 or index >= hex_cities.size():
		return ""
	return hex_cities[index]

func get_hex_river(index: int) -> String:
	if index < 0 or index >= hex_rivers.size():
		return ""
	return hex_rivers[index]

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
