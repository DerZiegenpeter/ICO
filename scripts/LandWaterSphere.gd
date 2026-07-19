@tool
extends Node3D
class_name LandWaterSphere

@export var geojson_path: String = "res://data/hex_land_water.geojson"
@export var radius: float = 50.0
@export var land_color: Color = Color(0.25, 0.55, 0.2)
@export var water_color: Color = Color(0.1, 0.25, 0.65)
@export var generate_on_ready: bool = true

var mesh_instance: MeshInstance3D

func _ready() -> void:
	if generate_on_ready:
		build_from_geojson()

func build_from_geojson() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "LandWaterMesh"
	add_child(mesh_instance)
	
	if not FileAccess.file_exists(geojson_path):
		push_error("GeoJSON nicht gefunden: " + geojson_path)
		return
	
	print("Lade GeoJSON... (das kann bei großen Dateien dauern)")
	var file = FileAccess.open(geojson_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		push_error("JSON konnte nicht gelesen werden")
		return
	
	var data = json.data
	if not data.has("features"):
		push_error("Keine Features in der GeoJSON gefunden")
		return
	
	var features = data["features"]
	print("Features geladen: ", features.size())
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var land_count = 0
	var water_count = 0
	
	for i in features.size():
		var feature = features[i]
		var props = feature.get("properties", {})
		var is_land = props.get("is_land", false)
		var geom = feature.get("geometry", {})
		
		if geom.get("type") != "Polygon" and geom.get("type") != "MultiPolygon":
			continue
		
		var color = land_color if is_land else water_color
		if is_land:
			land_count += 1
		else:
			water_count += 1
		
		var coordinates = geom.get("coordinates", [])
		
		var polygons = []
		if geom["type"] == "Polygon":
			polygons = [coordinates]
		else:
			polygons = coordinates
		
		for poly in polygons:
			if poly.is_empty():
				continue
			var ring = poly[0]
			_add_polygon(st, ring, color)
		
		# Fortschritt anzeigen
		if i % 20000 == 0 and i > 0:
			print("  verarbeitet: ", i, " / ", features.size())
	
	print("Erzeuge Mesh...")
	st.generate_normals()
	var mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	
	print("✅ Fertig!")
	print("   Land-Polygone:  ", land_count)
	print("   Wasser-Polygone:", water_count)

func _add_polygon(st: SurfaceTool, ring: Array, color: Color) -> void:
	if ring.size() < 3:
		return
	
	var points: Array[Vector3] = []
	for coord in ring:
		if coord.size() < 2:
			continue
		var lon = deg_to_rad(float(coord[0]))
		var lat = deg_to_rad(float(coord[1]))
		
		var x = radius * cos(lat) * sin(lon)
		var y = radius * sin(lat)
		var z = radius * cos(lat) * cos(lon)
		points.append(Vector3(x, y, z))
	
	if points.size() < 3:
		return
	
	# Einfache Fächer-Triangulierung
	for i in range(1, points.size() - 1):
		st.set_color(color)
		st.add_vertex(points[0])
		st.set_color(color)
		st.add_vertex(points[i])
		st.set_color(color)
		st.add_vertex(points[i + 1])
