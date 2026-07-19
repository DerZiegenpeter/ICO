@tool
extends Node3D
class_name LandWaterViewer

@export var geojson_path: String = "res://data/hex_land_water.geojson"
@export var radius: float = 50.2
@export var land_color: Color = Color(0.2, 0.85, 0.25)      # Grün für Land
@export var water_color: Color = Color(0.15, 0.45, 0.95)     # Blau für Wasser
@export var max_features: int = 100000

var mesh_instance: MeshInstance3D

func _ready() -> void:
	load_and_show()

func load_and_show() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "LandWaterWireframe"
	add_child(mesh_instance)
	
	if not FileAccess.file_exists(geojson_path):
		push_error("Datei nicht gefunden: " + geojson_path)
		return
	
	print("Lade Ergebnis von Python...")
	var file = FileAccess.open(geojson_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(content) != OK:
		push_error("JSON Parse Fehler")
		return
	
	var features = json.data.get("features", [])
	print("Features: ", features.size())
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)          # ← nur Linien!
	
	var count = mini(features.size(), max_features)
	var land_c = 0
	var water_c = 0
	
	for i in count:
		var f = features[i]
		var props = f.get("properties", {})
		var is_land = props.get("is_land", false)
		var color = land_color if is_land else water_color
		
		if is_land:
			land_c += 1
		else:
			water_c += 1
		
		var geom = f.get("geometry", {})
		var geom_type = geom.get("type", "")
		
		var polys = []
		if geom_type == "Polygon":
			polys = [geom.get("coordinates", [])]
		elif geom_type == "MultiPolygon":
			polys = geom.get("coordinates", [])
		
		for poly in polys:
			if poly.is_empty():
				continue
			var ring = poly[0]          # äußerer Ring
			_add_ring_as_lines(st, ring, color)
	
	var mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	
	print("✅ Wireframe angezeigt – Land: ", land_c, " | Wasser: ", water_c)

func _add_ring_as_lines(st: SurfaceTool, ring: Array, color: Color) -> void:
	var pts: Array[Vector3] = []
	
	for c in ring:
		if typeof(c) != TYPE_ARRAY or c.size() < 2:
			continue
		var lon = deg_to_rad(float(c[0]))
		var lat = deg_to_rad(float(c[1]))
		
		var x = radius * cos(lat) * sin(lon)
		var y = radius * sin(lat)
		var z = radius * cos(lat) * cos(lon)
		pts.append(Vector3(x, y, z))
	
	if pts.size() < 2:
		return
	
	# Linien zwischen den Punkten des Rings zeichnen
	for i in pts.size():
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		
		st.set_color(color)
		st.add_vertex(a)
		st.set_color(color)
		st.add_vertex(b)
