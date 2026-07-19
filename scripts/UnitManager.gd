extends Node3D

@export var hex_map_path: NodePath = NodePath("../HexMap")
@export var oob_path: String = "res://data/oob.json"
@export var nations_path: String = "res://data/nations.json"
@export var diplomacy_path: String = "res://data/diplomacy.json"
@export var combat_marker_size: float = 3.0

var hex_map: Node3D
var selected: MilEntity = null
var units: Array[MilEntity] = []

var nations: Dictionary = {}          # id -> name
var wars: Array = []                  # list of {a,b}
var combats: Dictionary = {}          # key "idA|idB" -> MeshInstance3D marker

func _ready() -> void:
	hex_map = get_node_or_null(hex_map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_nations()
	_load_diplomacy()
	_load_oob()

func _load_nations() -> void:
	if not FileAccess.file_exists(nations_path):
		return
	var file = FileAccess.open(nations_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	for n in json.data:
		nations[str(n.get("id", ""))] = str(n.get("name", ""))
	print("Nationen: ", nations.keys())

func _load_diplomacy() -> void:
	if not FileAccess.file_exists(diplomacy_path):
		return
	var file = FileAccess.open(diplomacy_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	wars = json.data.get("wars", [])
	print("Kriege: ", wars)

func at_war(nation_a: String, nation_b: String) -> bool:
	if nation_a == "" or nation_b == "" or nation_a == nation_b:
		return false
	for w in wars:
		var a = str(w.get("a", ""))
		var b = str(w.get("b", ""))
		if (a == nation_a and b == nation_b) or (a == nation_b and b == nation_a):
			return true
	return false

func can_fight(a: MilEntity, b: MilEntity) -> bool:
	if not at_war(a.nation_id, b.nation_id):
		return false
	var ta = a.get_type_string()
	var tb = b.get_type_string()
	# ballistic vs everything
	if ta == "ballistic" or tb == "ballistic":
		return true
	# same domain
	if ta == tb:
		return true
	# land vs naval
	if (ta == "land" and tb == "naval") or (ta == "naval" and tb == "land"):
		return true
	return false

func _load_oob() -> void:
	if hex_map == null:
		push_error("HexMap nicht gefunden")
		return
	if not FileAccess.file_exists(oob_path):
		push_error("oob.json nicht gefunden")
		return

	var file = FileAccess.open(oob_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("oob.json Parse Fehler")
		return
	file.close()

	for entry in json.data:
		var typ_str = str(entry.get("type", "land")).to_lower()
		var typ = MilEntity.Type.LAND
		match typ_str:
			"air":
				typ = MilEntity.Type.AIR
			"naval":
				typ = MilEntity.Type.NAVAL
			"ballistic":
				typ = MilEntity.Type.BALLISTIC

		var lon = float(entry.get("lon", 10.0))
		var lat = float(entry.get("lat", 51.0))
		var unit_name = str(entry.get("name", "Unit"))
		var nation = str(entry.get("nation", ""))

		var world_pos = hex_map.lonlat_to_world(lon, lat)
		world_pos = hex_map.get_closest_hex_center(world_pos)

		var unit = spawn_unit(typ, world_pos)
		unit.unit_name = unit_name
		unit.nation_id = nation
		unit.name = unit_name
		unit.arrived.connect(_on_unit_arrived)

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
	if cam == null:
		return Vector3.ZERO
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.00001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)

func _try_select(world_pos: Vector3) -> void:
	var closest: MilEntity = null
	var best_dist := 10.0
	for u in units:
		var d = u.get_ground_pos().distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			closest = u

	if selected:
		selected.deselect()
	selected = closest
	if selected:
		selected.select()
		print("Ausgewählt: ", selected.unit_name, " [", selected.nation_id, "]")
	else:
		print("Nichts ausgewählt")

func _try_move(world_pos: Vector3) -> void:
	if selected == null or hex_map == null:
		return

	var unit_type = selected.get_type_string()
	print("Suche Pfad für ", unit_type, "...")

	var path: Array[Vector3] = hex_map.find_path(selected.get_ground_pos(), world_pos, unit_type)
	if path.is_empty():
		print("Kein gültiger Pfad")
		return

	print("Pfad mit ", path.size(), " Hexes gefunden")
	# Leaving current hex ends any combat this unit is in
	_end_combats_involving(selected)
	selected.follow_path(path)

func _on_unit_arrived(unit: MilEntity) -> void:
	_check_combat_for(unit)

func _same_hex(a: MilEntity, b: MilEntity) -> bool:
	if hex_map == null:
		return false
	var ca = hex_map.get_closest_hex_center(a.get_ground_pos())
	var cb = hex_map.get_closest_hex_center(b.get_ground_pos())
	return ca.distance_squared_to(cb) < 1.0

func _check_combat_for(unit: MilEntity) -> void:
	for other in units:
		if other == unit:
			continue
		if not _same_hex(unit, other):
			continue
		if not can_fight(unit, other):
			continue
		_start_combat(unit, other)

func _combat_key(a: MilEntity, b: MilEntity) -> String:
	var id_a = str(a.get_instance_id())
	var id_b = str(b.get_instance_id())
	if id_a < id_b:
		return id_a + "|" + id_b
	return id_b + "|" + id_a

func _start_combat(a: MilEntity, b: MilEntity) -> void:
	var key = _combat_key(a, b)
	if combats.has(key):
		return

	var mid = (a.position + b.position) * 0.5
	var marker = _make_combat_marker(mid)
	add_child(marker)
	combats[key] = marker
	print("⚔ Combat: ", a.unit_name, " vs ", b.unit_name)

func _end_combats_involving(unit: MilEntity) -> void:
	var to_remove: Array[String] = []
	for key in combats.keys():
		if str(unit.get_instance_id()) in key.split("|"):
			to_remove.append(key)
	for key in to_remove:
		var marker = combats[key]
		if is_instance_valid(marker):
			marker.queue_free()
		combats.erase(key)
		print("Combat beendet (", key, ")")

func _make_combat_marker(pos: Vector3) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.name = "CombatMarker"
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var r = combat_marker_size
	var seg = 8
	# small glowing sphere (wireframe)
	for i in seg:
		var lat0 = PI * (-0.5 + float(i) / seg)
		var lat1 = PI * (-0.5 + float(i + 1) / seg)
		for j in seg:
			var lon0 = TAU * float(j) / seg
			var lon1 = TAU * float(j + 1) / seg
			var p1 = Vector3(r * cos(lat0) * cos(lon0), r * sin(lat0), r * cos(lat0) * sin(lon0))
			var p2 = Vector3(r * cos(lat0) * cos(lon1), r * sin(lat0), r * cos(lat0) * sin(lon1))
			var p3 = Vector3(r * cos(lat1) * cos(lon0), r * sin(lat1), r * cos(lat1) * sin(lon0))
			st.set_color(Color(1.0, 0.1, 0.1))
			st.add_vertex(p1)
			st.set_color(Color(1.0, 0.1, 0.1))
			st.add_vertex(p2)
			st.set_color(Color(1.0, 0.1, 0.1))
			st.add_vertex(p1)
			st.set_color(Color(1.0, 0.1, 0.1))
			st.add_vertex(p3)
	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.05)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi
