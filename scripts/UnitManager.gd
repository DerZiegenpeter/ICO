extends Node3D

@export var hex_map_path: NodePath = NodePath("../HexMap")
@export var oob_path: String = "res://data/oob.json"
@export var diplomacy_path: String = "res://data/diplomacy.json"
@export var nations_path: String = "res://data/nations.json"
@export var combat_marker_size: float = 4.0

var hex_map: Node3D
var selected: MilEntity = null
var units: Array[MilEntity] = []

## nation_id -> set of enemy nation_ids
var at_war: Dictionary = {}

## nation_id -> Color
var nation_colors: Dictionary = {}

## Active combats: key "idA|idB" -> { a, b, marker }
var combats: Dictionary = {}

## Path visualization (for currently selected unit's pending order)
var path_mesh_instance: MeshInstance3D = null
var path_unit: MilEntity = null

## ---- Time / Turn system ----
var year: int = 1949
var month: int = 5
var day: int = 23
var date_label: Label
var hint_label: Label
var resolving := false

const MONTH_NAMES := [
	"", "Januar", "Februar", "März", "April", "Mai", "Juni",
	"Juli", "August", "September", "Oktober", "November", "Dezember"
]

func _ready() -> void:
	hex_map = get_node_or_null(hex_map_path)
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_ui()
	_load_nations()
	_load_diplomacy()
	_load_oob()
	_update_date_label()

func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	# Date – top right
	date_label = Label.new()
	date_label.name = "DateLabel"
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	date_label.add_theme_font_size_override("font_size", 24)
	date_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	date_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	date_label.add_theme_constant_override("shadow_offset_x", 1)
	date_label.add_theme_constant_override("shadow_offset_y", 1)
	date_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	date_label.offset_left = -320
	date_label.offset_top = 14
	date_label.offset_right = -18
	date_label.offset_bottom = 50
	canvas.add_child(date_label)

	# Hint – below date
	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	hint_label.text = "Leertaste = Nächster Tag"
	hint_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hint_label.offset_left = -320
	hint_label.offset_top = 48
	hint_label.offset_right = -18
	hint_label.offset_bottom = 72
	canvas.add_child(hint_label)

func _update_date_label() -> void:
	if date_label:
		date_label.text = "%d. %s %d" % [day, MONTH_NAMES[month], year]

func _advance_day() -> void:
	day += 1
	var days_in_month := _days_in_month(year, month)
	if day > days_in_month:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
	_update_date_label()

func _days_in_month(y: int, m: int) -> int:
	match m:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			# leap year
			if (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0):
				return 29
			return 28
	return 30

func end_turn() -> void:
	if resolving:
		return
	resolving = true
	print("========== Tag endet → ", day, ".", month, ".", year, " ==========")

	_clear_path_visual()
	path_unit = null

	# Execute all pending orders simultaneously
	var moved := 0
	for u in units:
		if u.has_order():
			u.execute_order()
			moved += 1
	print("Befehle ausgeführt: ", moved)

	# Advance calendar
	_advance_day()
	print("Neuer Tag: ", day, ". ", MONTH_NAMES[month], " ", year)

	# Refresh movement points for the new day
	for u in units:
		u.reset_move_points()

	resolving = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			end_turn()
			get_viewport().set_input_as_handled()

func _load_nations() -> void:
	nation_colors.clear()
	if not FileAccess.file_exists(nations_path):
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

func get_nation_color(nation_id: String) -> Color:
	return nation_colors.get(nation_id, Color(0.75, 0.75, 0.2))

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

		var unit = MilEntity.new()
		unit.entity_type = typ
		unit.nation = nation
		unit.unit_name = unit_name
		unit.name = unit_name
		unit.color = get_nation_color(nation)
		add_child(unit)
		unit.set_hex_position(world_pos)
		unit.arrived_at_hex.connect(_on_unit_arrived)
		unit.order_finished.connect(_on_order_finished)
		units.append(unit)

	print("OOB geladen – Einheiten: ", units.size())

func _input(event: InputEvent) -> void:
	if resolving:
		return
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
		print("Ausgewählt: ", selected.unit_name, " [", selected.nation, "]  MP: ", selected.move_points, "/", selected.move_points_max)
		# Show pending path if this unit already has an order
		if selected.has_order():
			_show_path(selected.pending_path, get_nation_color(selected.nation))
			path_unit = selected
		else:
			_clear_path_visual()
			path_unit = null
	else:
		print("Nichts ausgewählt")
		_clear_path_visual()
		path_unit = null

func _enemy_on_hex(ground_pos: Vector3, attacker: MilEntity) -> MilEntity:
	for u in units:
		if u == attacker:
			continue
		if not _same_hex(ground_pos, u.get_ground_pos()):
			continue
		if can_fight(attacker, u):
			return u
	return null

func _truncate_path(path: Array[Vector3], max_steps: int) -> Array[Vector3]:
	## path[0] is start, so max length = max_steps + 1
	if path.size() <= max_steps + 1:
		return path
	return path.slice(0, max_steps + 1)

func _try_move(world_pos: Vector3) -> void:
	if selected == null or hex_map == null:
		return
	if selected.move_points <= 0:
		print("Keine Bewegungspunkte mehr übrig")
		return

	var unit_type = selected.get_type_string()
	var goal_center = hex_map.get_closest_hex_center(world_pos)
	var enemy = _enemy_on_hex(goal_center, selected)

	# Explicit attack order on enemy hex
	if enemy != null and can_fight(selected, enemy):
		_end_combats_involving(selected)

		if unit_type == "air" or unit_type == "ballistic":
			# Air/Ballistic: order to fly over target (executes on day end)
			print("Suche Pfad für ", unit_type, " (Angriff über Ziel)...")
			var path: Array[Vector3] = hex_map.find_path(selected.get_ground_pos(), goal_center, unit_type)
			if path.is_empty():
				print("Kein gültiger Pfad zum Ziel")
				return
			path = _truncate_path(path, selected.move_points)
			print("Befehl: ", path.size() - 1, " Hexes (von max ", selected.move_points, ") – wird bei Tagesende ausgeführt")
			selected.set_order(path)
			_show_path(path, get_nation_color(selected.nation))
			path_unit = selected
		else:
			# Land & Naval: stay put, combat starts immediately (no movement order)
			_start_combat(selected, enemy)
			print("⚔ Angriffsbefehl: ", selected.unit_name, " vs ", enemy.unit_name, " (bleiben stehen)")
			selected.clear_order()
			_clear_path_visual()
		return

	# Normal movement order (pending until day advances)
	print("Suche Pfad für ", unit_type, "...")
	var path: Array[Vector3] = hex_map.find_path(selected.get_ground_pos(), goal_center, unit_type)
	if path.is_empty():
		print("Kein gültiger Pfad")
		return

	path = _truncate_path(path, selected.move_points)
	if path.size() < 2:
		print("Ziel ist das aktuelle Hex – kein Befehl")
		return

	print("Befehl erteilt: ", path.size() - 1, " Hexes (MP: ", selected.move_points, ") – Bewegung bei Tagesende")
	_end_combats_involving(selected)
	selected.set_order(path)
	_show_path(path, get_nation_color(selected.nation))
	path_unit = selected

func _on_unit_arrived(unit: MilEntity) -> void:
	# 1) Combat if landing on same hex as fightable enemy (Air/Ballistic)
	var ground = unit.get_ground_pos()
	for other in units:
		if other == unit:
			continue
		if not can_fight(unit, other):
			continue
		if _same_hex(ground, other.get_ground_pos()):
			_start_combat(unit, other)
			break

	# 2) Territory capture / re-capture (only Land units)
	if unit.get_type_string() == "land" and hex_map != null:
		var idx = hex_map.get_closest_hex_index(ground)
		if idx >= 0:
			var controller = hex_map.get_hex_controller(idx)
			if controller != "" and controller != unit.nation and are_enemies(unit.nation, controller):
				hex_map.set_controller(idx, unit.nation)
				print("🏴 ", unit.unit_name, " übernimmt Kontrolle (war: ", controller, " → jetzt: ", unit.nation, ")")

func _on_order_finished(unit: MilEntity) -> void:
	if path_unit == unit:
		_clear_path_visual()
		path_unit = null

func _show_path(points: Array[Vector3], color: Color) -> void:
	_clear_path_visual()
	if points.size() < 2:
		return

	var curve := Curve3D.new()
	for p in points:
		curve.add_point(Vector3(p.x, 0.45, p.z))

	var baked: PackedVector3Array = curve.tessellate(6, 0.15)
	if baked.size() < 2:
		baked = PackedVector3Array()
		for p in points:
			baked.append(Vector3(p.x, 0.45, p.z))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in baked:
		st.set_color(color)
		st.add_vertex(p)

	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8

	path_mesh_instance = MeshInstance3D.new()
	path_mesh_instance.name = "PathVisual"
	path_mesh_instance.mesh = mesh
	path_mesh_instance.material_override = mat
	add_child(path_mesh_instance)

func _clear_path_visual() -> void:
	if path_mesh_instance and is_instance_valid(path_mesh_instance):
		path_mesh_instance.queue_free()
	path_mesh_instance = null

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
