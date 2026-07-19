@tool
extends Node3D
class_name LandWaterViewer

@export var geojson_path: String = "res://data/hex_land_water.geojson"
@export var radius: float = 50.0
@export var land_color: Color = Color(0.22, 0.55, 0.18)
@export var water_color: Color = Color(0.1, 0.28, 0.65)
@export var max_features: int = 100000

var mesh_instance: MeshInstance3D

func _ready() -> void:
	load_and_show()

func load_and_show() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	if not FileAccess.file_exists(geojson_path):
		push_error("Datei nicht gefunden: " + geojson_path)
		return
	
	print("Lade Ergebnis von Python...")
	var file = FileAccess.open(geojson_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON Parse Fehler")
		return
	file.close()
	
	var features = json.data.get("features", [])
	print("Features: ", features.size())
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var count = mini(features.size(), max_features)
	var land_c = 0
	var water_c = 0
	
	for i in count:
		var f = features[i]
		var is_land = f.get("properties", {}).get("is_land", false)
		var color = land_color if is_land else water_color
		if is_land: land_c += 1
		else: water_c += 1
		
		var geom = f.get("geometry", {})
		var polys = []
		if geom.get("type") == "Polygon":
			polys = [geom["coordinates"]]
		elif geom.get("type") == "MultiPolygon":
			polys = geom["coordinates"]
		
		for poly in polys:
			if poly.is_empty(): continue
			_add_ring(st, poly[0], color)
	
	st.generate_normals()
	var mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	
	print("✅ Angezeigt – Land: ", land_c, " | Wasser: ", water_c)

func _add_ring(st: SurfaceTool, ring: Array, color: Color) -> void:
	var pts: Array[Vector3] = []
	for c in ring:
		if c.size() < 2: continue
		var lon = deg_to_rad(float(c[0]))
		var lat = deg_to_rad(float(c[1]))
		pts.append(Vector3(
			radius * cos(lat) * sin(lon),
			radius * sin(lat),
			radius * cos(lat) * cos(lon)
		))
	if pts.size() < 3: return
	for i in range(1, pts.size()-1):
		st.set_color(color)
		st.add_vertex(pts[0])
		st.set_color(color)
		st.add_vertex(pts[i])
		st.set_color(color)
		st.add_vertex(pts[i+1])
