@tool
extends Node3D
class_name HexGenerator

@export var radius: float = 50.0
@export_range(0, 7, 1) var subdivisions: int = 5
@export var relaxation_iterations: int = 3
@export var line_color: Color = Color(0.0, 1.0, 0.35, 1.0)
@export var export_path: String = "res://data/hex_grid.geojson"

var mesh_instance: MeshInstance3D
var dual_verts: Array[Vector3] = []
var dual_faces: Array[PackedInt32Array] = []

func _ready() -> void:
	generate()

func generate() -> void:
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	
	print("Generiere Hex-Grid (Subdiv ", subdivisions, ")...")
	
	var primal_verts: Array[Vector3] = []
	var primal_faces: Array[PackedInt32Array] = []
	_create_icosahedron(primal_verts, primal_faces)
	
	for i in subdivisions:
		_subdivide(primal_verts, primal_faces)
	
	dual_verts.clear()
	dual_faces.clear()
	_build_dual(primal_verts, primal_faces)
	
	if relaxation_iterations > 0:
		_relax(dual_verts, dual_faces, relaxation_iterations)
	
	_create_wireframe()
	print("✅ Grid fertig – Tiles: ", dual_faces.size())

func export_geojson() -> void:
	if dual_faces.is_empty():
		push_warning("Zuerst generieren!")
		return
	
	print("Exportiere GeoJSON...")
	var features = []
	
	for i in dual_faces.size():
		var face = dual_faces[i]
		var ring = []
		for idx in face:
			var ll = _to_lonlat(dual_verts[idx])
			ring.append([ll.x, ll.y])
		ring.append(ring[0].duplicate())
		
		features.append({
			"type": "Feature",
			"properties": {"id": i, "sides": face.size()},
			"geometry": {"type": "Polygon", "coordinates": [ring]}
		})
	
	var geojson = {"type": "FeatureCollection", "features": features}
	var file = FileAccess.open(export_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(geojson))
	file.close()
	print("✅ Exportiert nach: ", export_path)

func _to_lonlat(v: Vector3) -> Vector2:
	var n = v.normalized()
	return Vector2(rad_to_deg(atan2(n.x, n.z)), rad_to_deg(asin(clamp(n.y, -1.0, 1.0))))

func _create_wireframe() -> void:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for v in dual_verts:
		st.add_vertex(v)
	
	var edges = {}
	for face in dual_faces:
		for i in face.size():
			var a = face[i]
			var b = face[(i+1) % face.size()]
			var key = "%d_%d" % [mini(a,b), maxi(a,b)]
			if not edges.has(key):
				edges[key] = true
				st.add_index(a)
				st.add_index(b)
	
	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = line_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat

# ---------- Geometry ----------
func _create_icosahedron(verts, faces):
	var t = (1.0 + sqrt(5.0)) / 2.0
	var raw = [
		Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),
		Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),
		Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)
	]
	for v in raw: verts.append(v.normalized() * radius)
	var base = [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	for f in base: faces.append(PackedInt32Array(f))

func _subdivide(verts, faces):
	var new_faces = []
	var cache = {}
	for face in faces:
		var a=face[0]; var b=face[1]; var c=face[2]
		var ab=_mid(a,b,verts,cache); var bc=_mid(b,c,verts,cache); var ca=_mid(c,a,verts,cache)
		new_faces.append(PackedInt32Array([a,ab,ca]))
		new_faces.append(PackedInt32Array([b,bc,ab]))
		new_faces.append(PackedInt32Array([c,ca,bc]))
		new_faces.append(PackedInt32Array([ab,bc,ca]))
	faces.clear()
	faces.append_array(new_faces)

func _mid(i1,i2,verts,cache):
	var key = "%d_%d"%[mini(i1,i2),maxi(i1,i2)]
	if cache.has(key): return cache[key]
	var v = ((verts[i1]+verts[i2])*0.5).normalized()*radius
	var idx = verts.size()
	verts.append(v)
	cache[key] = idx
	return idx

func _build_dual(primal_verts, primal_faces):
	for f in primal_faces:
		var c = ((primal_verts[f[0]]+primal_verts[f[1]]+primal_verts[f[2]])/3.0).normalized()*radius
		dual_verts.append(c)
	
	var incident = {}
	for fi in primal_faces.size():
		for vi in primal_faces[fi]:
			if not incident.has(vi): incident[vi] = []
			incident[vi].append(fi)
	
	for vi in incident:
		var ids = incident[vi]
		if ids.size() < 5: continue
		dual_faces.append(PackedInt32Array(_sort_around(primal_verts[vi], ids)))

func _sort_around(normal, face_ids):
	var basis = _tangent(normal)
	var angles = []
	for fi in face_ids:
		var p = dual_verts[fi] - normal * normal.dot(dual_verts[fi])
		angles.append(atan2(basis.y.dot(p), basis.x.dot(p)))
	var order = range(face_ids.size())
	order.sort_custom(func(a,b): return angles[a] < angles[b])
	var res = []
	for i in order: res.append(face_ids[i])
	return res

func _tangent(n):
	var up = Vector3.UP if abs(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t = n.cross(up).normalized()
	return Basis(t, n.cross(t).normalized(), n)

func _relax(verts, faces, iterations):
	var neighbors = []
	neighbors.resize(verts.size())
	for i in verts.size(): neighbors[i] = []
	for face in faces:
		for i in face.size():
			var a = face[i]; var b = face[(i+1)%face.size()]
			if not neighbors[a].has(b): neighbors[a].append(b)
			if not neighbors[b].has(a): neighbors[b].append(a)
	
	for _i in iterations:
		var neu = []
		neu.resize(verts.size())
		for i in verts.size():
			if neighbors[i].is_empty():
				neu[i] = verts[i]
				continue
			var s = Vector3.ZERO
			for n in neighbors[i]: s += verts[n]
			neu[i] = verts[i].lerp((s/neighbors[i].size()).normalized()*radius, 0.55)
		for i in verts.size(): verts[i] = neu[i]
