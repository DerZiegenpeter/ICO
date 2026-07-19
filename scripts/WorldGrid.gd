@tool
extends Node3D
class_name HexWorldGrid

@export var radius: float = 50.0
@export_range(0, 9, 1) var subdivisions: int = 9
@export var relaxation_iterations: int = 3
@export var line_color: Color = Color(0.0, 1.0, 0.3, 1.0)

@export_group("GeoJSON Export")
@export var export_path: String = "res://hex_grid.geojson"
@export var auto_export_on_generate: bool = false

var mesh_instance: MeshInstance3D
var last_dual_verts: Array[Vector3] = []
var last_dual_faces: Array[PackedInt32Array] = []

func _ready() -> void:
	generate_hexasphere()

func generate_hexasphere() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HexasphereMesh"
	add_child(mesh_instance)
	
	print("Starte Generierung... Subdiv: ", subdivisions)
	
	var primal_verts: Array[Vector3] = []
	var primal_faces: Array[PackedInt32Array] = []
	
	_create_icosahedron(primal_verts, primal_faces)
	
	for i in subdivisions:
		print("  Subdivision ", i + 1, "/", subdivisions)
		_subdivide(primal_verts, primal_faces)
	
	var dual_verts: Array[Vector3] = []
	var dual_faces: Array[PackedInt32Array] = []
	_build_dual(primal_verts, primal_faces, dual_verts, dual_faces)
	
	if relaxation_iterations > 0:
		print("  Starte Relaxation (", relaxation_iterations, " Iterationen)...")
		_relax_points(dual_verts, dual_faces, relaxation_iterations)
	
	last_dual_verts = dual_verts.duplicate()
	last_dual_faces = dual_faces.duplicate()
	
	_create_wireframe_mesh(mesh_instance, dual_verts, dual_faces)
	
	print("✅ Fertig! Tiles: ", dual_faces.size())
	
	if auto_export_on_generate:
		export_geojson()

# ==================== GeoJSON Export ====================

func export_geojson(path: String = "") -> void:
	if path.is_empty():
		path = export_path
	
	if last_dual_verts.is_empty() or last_dual_faces.is_empty():
		push_warning("Keine Daten vorhanden – zuerst generate_hexasphere() ausführen")
		return
	
	print("Exportiere GeoJSON... (", last_dual_faces.size(), " Features)")
	
	var features: Array = []
	
	for face_idx in last_dual_faces.size():
		var face = last_dual_faces[face_idx]
		var ring: Array = []
		
		for i in face.size():
			var lonlat = _cartesian_to_lonlat(last_dual_verts[face[i]])
			ring.append([lonlat.x, lonlat.y])
		
		if ring.size() > 0:
			ring.append(ring[0].duplicate())
		
		ring = _fix_antimeridian(ring)
		
		var feature = {
			"type": "Feature",
			"properties": {
				"id": face_idx,
				"sides": face.size(),
				"type": "pentagon" if face.size() == 5 else "hexagon"
			},
			"geometry": {
				"type": "Polygon",
				"coordinates": [ring]
			}
		}
		features.append(feature)
		
		if face_idx % 50000 == 0 and face_idx > 0:
			print("  ... ", face_idx, " / ", last_dual_faces.size())
	
	var geojson = {
		"type": "FeatureCollection",
		"features": features
	}
	
	var json_string = JSON.stringify(geojson)
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("✅ GeoJSON gespeichert: ", path)
	else:
		push_error("Konnte Datei nicht schreiben: " + path)

func _cartesian_to_lonlat(v: Vector3) -> Vector2:
	var n = v.normalized()
	var lon = rad_to_deg(atan2(n.x, n.z))
	var lat = rad_to_deg(asin(clamp(n.y, -1.0, 1.0)))
	return Vector2(lon, lat)

func _fix_antimeridian(ring: Array) -> Array:
	if ring.size() < 2:
		return ring
	
	var has_west = false
	var has_east = false
	for p in ring:
		if p[0] < -90.0:
			has_west = true
		if p[0] > 90.0:
			has_east = true
	
	if has_west and has_east:
		var new_ring: Array = []
		for p in ring:
			var lon = p[0]
			if lon < 0.0:
				lon += 360.0
			new_ring.append([lon, p[1]])
		return new_ring
	
	return ring

# ==================== Relaxation ====================

func _relax_points(verts: Array[Vector3], faces: Array[PackedInt32Array], iterations: int) -> void:
	var neighbors: Array = []
	neighbors.resize(verts.size())
	for i in verts.size():
		neighbors[i] = []
	
	for face in faces:
		var n = face.size()
		for i in n:
			var a = face[i]
			var b = face[(i + 1) % n]
			if not neighbors[a].has(b):
				neighbors[a].append(b)
			if not neighbors[b].has(a):
				neighbors[b].append(a)
	
	for iter in iterations:
		print("    Relaxation Iteration ", iter + 1)
		var new_pos: Array[Vector3] = []
		new_pos.resize(verts.size())
		
		for i in verts.size():
			if neighbors[i].is_empty():
				new_pos[i] = verts[i]
				continue
			
			var sum := Vector3.ZERO
			for n_idx in neighbors[i]:
				sum += verts[n_idx]
			
			var avg = (sum / neighbors[i].size()).normalized() * radius
			new_pos[i] = verts[i].lerp(avg, 0.55)
		
		for i in verts.size():
			verts[i] = new_pos[i]

# ==================== Geometry ====================

func _create_icosahedron(verts: Array[Vector3], faces: Array[PackedInt32Array]) -> void:
	var t = (1.0 + sqrt(5.0)) / 2.0
	var raw = [
		Vector3(-1, t, 0), Vector3(1, t, 0),
		Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1),
		Vector3(-t, 0, -1), Vector3(-t, 0, 1)
	]
	for v in raw:
		verts.append(v.normalized())
	
	var base_faces = [
		[0,11,5], [0,5,1], [0,1,7], [0,7,10], [0,10,11],
		[1,5,9], [5,11,4], [11,10,2], [10,7,6], [7,1,8],
		[3,9,4], [3,4,2], [3,2,6], [3,6,8], [3,8,9],
		[4,9,5], [2,4,11], [6,2,10], [8,6,7], [9,8,1]
	]
	for f in base_faces:
		faces.append(PackedInt32Array(f))

func _subdivide(verts: Array[Vector3], faces: Array[PackedInt32Array]) -> void:
	var new_faces: Array[PackedInt32Array] = []
	var mid_cache := {}
	for face in faces:
		var a = face[0]
		var b = face[1]
		var c = face[2]
		var ab = _midpoint(a, b, verts, mid_cache)
		var bc = _midpoint(b, c, verts, mid_cache)
		var ca = _midpoint(c, a, verts, mid_cache)
		new_faces.append(PackedInt32Array([a, ab, ca]))
		new_faces.append(PackedInt32Array([b, bc, ab]))
		new_faces.append(PackedInt32Array([c, ca, bc]))
		new_faces.append(PackedInt32Array([ab, bc, ca]))
	faces.clear()
	faces.append_array(new_faces)

func _midpoint(i1: int, i2: int, verts: Array[Vector3], cache: Dictionary) -> int:
	var key = "%d_%d" % [min(i1, i2), max(i1, i2)]
	if key in cache:
		return cache[key]
	var v = (verts[i1] + verts[i2]) * 0.5
	v = v.normalized()
	var idx = verts.size()
	verts.append(v)
	cache[key] = idx
	return idx

func _build_dual(primal_verts: Array[Vector3], primal_faces: Array[PackedInt32Array], dual_verts: Array[Vector3], dual_faces: Array[PackedInt32Array]) -> void:
	for f in primal_faces:
		var a = primal_verts[f[0]]
		var b = primal_verts[f[1]]
		var c = primal_verts[f[2]]
		var center = ((a + b + c) / 3.0).normalized() * radius
		dual_verts.append(center)
	
	var incident := {}
	for f_idx in primal_faces.size():
		for v_idx in primal_faces[f_idx]:
			if not incident.has(v_idx):
				incident[v_idx] = []
			incident[v_idx].append(f_idx)
	
	for v_idx in incident:
		var face_ids = incident[v_idx]
		if face_ids.size() < 5:
			continue
		var sorted = _sort_angular_around(primal_verts[v_idx], face_ids, dual_verts)
		dual_faces.append(PackedInt32Array(sorted))

func _sort_angular_around(normal: Vector3, face_ids: Array, dual_verts: Array[Vector3]) -> Array[int]:
	var angles = []
	var basis = _tangent_basis(normal)
	for f_idx in face_ids:
		var c = dual_verts[f_idx]
		var proj = c - normal * normal.dot(c)
		var x = basis.x.dot(proj)
		var y = basis.y.dot(proj)
		angles.append(atan2(y, x))
	
	var idxs = range(face_ids.size())
	for i in idxs.size():
		for j in range(i + 1, idxs.size()):
			if angles[idxs[i]] > angles[idxs[j]]:
				var tmp = idxs[i]
				idxs[i] = idxs[j]
				idxs[j] = tmp
	
	var result: Array[int] = []
	for i in idxs:
		result.append(face_ids[i])
	return result

func _tangent_basis(n: Vector3) -> Basis:
	var up = Vector3.UP if abs(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t = n.cross(up).normalized()
	return Basis(t, n.cross(t).normalized(), n)

func _create_wireframe_mesh(mi: MeshInstance3D, verts: Array[Vector3], faces: Array[PackedInt32Array]) -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	
	for v in verts:
		st.add_vertex(v)
	
	var edges := {}
	for face in faces:
		var n = face.size()
		for i in n:
			var a = face[i]
			var b = face[(i + 1) % n]
			var key = "%d_%d" % [min(a, b), max(a, b)]
			if not edges.has(key):
				edges[key] = true
				st.add_index(a)
				st.add_index(b)
	
	var mesh = st.commit()
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = line_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	mi.mesh = mesh
	mi.material_override = mat
