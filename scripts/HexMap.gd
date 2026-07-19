@tool
extends Node3D

@export var geojson_path: String = "res://data/hex_final.geojson"
@export var scale_factor: float = 100.0          # damit es nicht winzig ist
@export var height: float = 0.0                 # alles auf y = 0

@export var land_color: Color = Color(0.2, 0.7, 0.25)
@export var ocean_color: Color = Color(0.15, 0.4, 0.9)
@export var lake_color: Color = Color(0.4, 0.7, 0.95)

var mesh_instance: MeshInstance3D

func _ready() -> void:
	load_and_draw()

func load_and_draw() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	if not FileAccess.file_exists(geojson_path):
		push_error("GeoJSON nicht gefunden: " + geojson_path)
		return
	
	var file = FileAccess.open(geojson_path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON Parse Fehler")
		return
	file.close()
	
	var features = json.data.get("features", [])
	print("Features geladen: ", features.size())
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	var land_c = 0
	var ocean_c = 0
	var lake_c = 0
	
	for f in features:
		var props = f.get("properties", {})
		var typ = str(props.get("final_type", props.get("TYPE", "ocean"))).to_lower()
		
		var color = ocean_color
		if typ == "land":
			color = land_color
			land_c += 1
		elif typ == "lake":
			color = lake_color
			lake_c += 1
		else:
			ocean_c += 1
		
		var geom = f.get("geometry", {})
		if geom.get("type") != "Polygon":
			continue
		
		var ring = geom["coordinates"][0]
		_add_ring(st, ring, color)
	
	var mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	
	print("✅ Fertig – Land: ", land_c, " | Ocean: ", ocean_c, " | Lake: ", lake_c)

func _add_ring(st: SurfaceTool, ring: Array, color: Color) -> void:
	var pts: Array[Vector3] = []
	
	for c in ring:
		if c.size() < 2:
			continue
		# Lon/Lat → flache XZ-Ebene
		var x = float(c[0]) * scale_factor
		var z = float(c[1]) * scale_factor
		pts.append(Vector3(x, height, z))
	
	if pts.size() < 2:
		return
	
	for i in pts.size():
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		st.set_color(color)
		st.add_vertex(a)
		st.set_color(color)
		st.add_vertex(b)
