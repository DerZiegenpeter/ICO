extends Node3D

@export var hex_map_path: NodePath = NodePath("../HexMap")
@export var oob_path: String = "res://data/oob.json"
@export var diplomacy_path: String = "res://data/diplomacy.json"
@export var combat_marker_size: float = 4.0

var hex_map: Node3D
var selected: MilEntity = null
var units: Array[MilEntity] = []

## nation_id -> set of enemy nation_ids
var at_war: Dictionary = {}

## Active combats: key "idA|idB" -> { a, b, marker }
var combats: Dictionary = {}

func _ready() -> void:
	hex_map = get_node_or_null(hex_map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	_load_diplomacy()
	_load_oob()

func _load_diplomacy() -> void:
	at_war.clear()
	if not FileAccess.file_exists(diplomacy_path):
		print("Keine diplomacy.json – keine Kriege")
		return
	var file = FileAccess.open(diplomacy_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	file.close()
	var data = json.data
	for war in data.get("wars", []):
		var a = str(war.get("a", ""))
		var b = str(war.get("b", ""))
		if a == "" or b == "":
			continue
		if not at_war.has(a):
			at_war[a] = {}
		if not at_war.has(b):
			at_war[b] = {}
		at_war[a][b] = true
		at_war[b][a] = true
	print("Diplomatie geladen – Kriege: ", data.get("wars", []).size())

func are_enemies(nation_a: String, nation_b: String) -> bool:
	if nation_a == "" or nation_b == "" or nation_a == nation_b:
		return false
	return at_war.has(nation_a) and at_war[nation_a].has(nation_b)

## Combat rules:
## - Land vs Land
## - Naval vs Naval
## - Air vs Land, Naval, Air
## - Ballistic vs All
func can_fight(a: MilEntity, b: MilEntity) -> bool:
	if not are_enemies(a.nation, b.nation):
		return false
	var ta = a.get_type_string()
	var tb = b.get_type_string()

	if ta == "ballistic" or tb == "ballistic":
		return true
	if ta == "air":
		return tb in ["land", "naval", "air"]
	if tb == "air":
		return ta in ["land", "naval", "air"]
	if ta == "land" and tb == "land":
		return true
	if ta == "naval" and tb == "naval":
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
		unit.nation = nation
		unit.name = unit_name
		# No longer auto-start combat on arrival

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
	var best_dist := 12.0
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
		print("Ausgewählt: ", selected.unit_name, " [", selected.nation, "]")
	else:
		print("Nichts ausgewählt")

func _enemy_on_hex(ground_pos: Vector3, attacker: MilEntity) -> MilEntity:
	for u in units:
		if u == attacker:
			continue
		if not _same_hex(ground_pos, u.get_ground_pos()):
			continue
		if can_fight(attacker, u):
			return u
	return null

func _try_move(world_pos: Vector3) -> void:
	if selected == null or hex_map == null:
		return

	var unit_type = selected.get_type_string()
	var goal_center = hex_map.get_closest_hex_center(world_pos)
	var enemy = _enemy_on_hex(goal_center, selected)

	# Explicit attack order only: right-click on enemy hex starts combat
	# Land/Naval stay put. Air/Ballistic also attack from current position.
	if enemy != null and can_fight(selected, enemy):
		_end_combats_involving(selected)
		_start_combat(selected, enemy)
		print("⚔ Angriffsbefehl: ", selected.unit_name, " vs ", enemy.unit_name, " (keine Bewegung)")
		return

	# Normal movement to empty / non-hostile hex
	print("Suche Pfad für ", unit_type, "...")
	var path: Array[Vector3] = hex_map.find_path(selected.get_ground_pos(), goal_center, unit_type)
	if path.is_empty():
		print("Kein gültiger Pfad")
		return

	print("Pfad mit ", path.size(), " Hexes gefunden")
	_end_combats_involving(selected)
	selected.follow_path(path)

func _same_hex(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 1.5

func _combat_key(a: MilEntity, b: MilEntity) -> String:
	var ida = str(a.get_instance_id())
	var idb = str(b.get_instance_id())
	if ida < idb:
		return ida + "|" + idb
	return idb + "|" + ida

func _start_combat(a: MilEntity, b: MilEntity) -> void:
	var key = _combat_key(a, b)
	if combats.has(key):
		return

	var marker = _create_combat_marker(a, b)
	combats[key] = {"a": a, "b": b, "marker": marker}
	print("⚔ Combat: ", a.unit_name, " vs ", b.unit_name)

func _end_combats_involving(unit: MilEntity) -> void:
	var to_remove: Array[String] = []
	for key in combats:
		var c = combats[key]
		if c.a == unit or c.b == unit:
			if is_instance_valid(c.marker):
				c.marker.queue_free()
			to_remove.append(key)
			print("Combat beendet (", unit.unit_name, " bewegt sich)")
	for key in to_remove:
		combats.erase(key)

func _create_combat_marker(a: MilEntity, b: MilEntity) -> MeshInstance3D:
	var mid = (a.position + b.position) * 0.5
	var mi = MeshInstance3D.new()
	mi.name = "CombatMarker"
	add_child(mi)
	mi.position = mid

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var r = combat_marker_size * 0.5
	var seg = 8
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.1)
	mat.emission_energy_multiplier = 2.5
	mi.mesh = mesh
	mi.material_override = mat
	return mi
