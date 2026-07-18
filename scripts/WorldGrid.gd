extends Node3D

@export var radius: float = 20.0
@export_file("*.geojson") var geojson_path: String = "res://data/world_grid_land_water.geojson"

func _ready() -> void:
	_create_base_sphere()
	_load_wireframe_grid()

# Schwarze Grundkugel
func _create_base_sphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere
	mesh_instance.material_override = mat
	add_child(mesh_instance)

# Wireframe Grid (grün = Land, blau = Wasser)
func _load_wireframe_grid() -> void:
	var file := FileAccess.open(geojson_path, FileAccess.READ)
	if file == null:
		print("GeoJSON nicht gefunden unter: ", geojson_path)
		return

	var json_text := file.get_as_text()
	var data: Dictionary = JSON.parse_string(json_text)

	if data == null or not data.has("features"):
		print("Fehler beim Parsen der GeoJSON!")
		return

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()

	for feature in data["features"]:
		var props: Dictionary = {}
		if feature.has("properties"):
			props = feature.get("properties", {}) as Dictionary

		var tile_type: String = "water"
		if props.has("type"):
			tile_type = str(props["type"])

		var line_color := Color(0.2, 0.85, 0.3) if tile_type == "land" else Color(0.25, 0.55, 1.0)

		var coords: Array = []
		if feature.has("geometry") and feature["geometry"].has("coordinates"):
			coords = feature["geometry"]["coordinates"][0]

		for i in range(coords.size() - 1):
			var p1 := _lat_lon_to_vector3(coords[i][1], coords[i][0])
			var p2 := _lat_lon_to_vector3(coords[i + 1][1], coords[i + 1][0])

			vertices.append(p1)
			vertices.append(p2)
			colors.append(line_color)
			colors.append(line_color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	add_child(mesh_instance)

func _lat_lon_to_vector3(lat: float, lon: float) -> Vector3:
	var lat_rad := deg_to_rad(lat)
	var lon_rad := deg_to_rad(-lon)     # Minus = richtige Orientierung (nicht gespiegelt)

	var x := radius * cos(lat_rad) * cos(lon_rad)
	var y := radius * sin(lat_rad)
	var z := radius * cos(lat_rad) * sin(lon_rad)

	return Vector3(x, y, z)
