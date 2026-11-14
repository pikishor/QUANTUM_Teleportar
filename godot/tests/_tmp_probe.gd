extends RefCounted

func run(host: Node) -> void:
	var scene := load("res://assets/models/weapons/probe.glb") as PackedScene
	print("scene ", scene)
	var root := scene.instantiate()
	for c in root.get_children():
		print("child ", c.name, " ", c.get_class(), " pos ", (c as Node3D).position)
	var mi := root.find_child("L0", true, false) as MeshInstance3D
	print("mesh ", mi.mesh, " surfaces ", mi.mesh.get_surface_count())
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	print("normals ", nr[0], nr[100], nr[200], nr[300], " len ", nr[100].length(), " tangent size ", (arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() if arr[Mesh.ARRAY_TANGENT] != null else -1)
	print("verts ", v.size(), " idx ", idx.size(), " colors ", cols.size(), " uv ", uv.size(), " uv2 ", uv2.size(), " tangent ", arr[Mesh.ARRAY_TANGENT] != null)
	var bb := mi.mesh.get_aabb()
	print("aabb ", bb)
	for i in [0, 100, 200, 300, 390]:
		print(i, " p ", v[i], " col ", cols[i], " uv ", uv[i] * 255.0, " uv2 ", uv2[i])
	print("layer ids ", _uniq(uv, 0), " parts ", _uniq(uv, 1))
	var tex := load("res://assets/models/weapons/weapon_atlas_alb.png")
	print("tex ", tex, " ", tex.get_class(), " layers ", (tex as TextureLayered).get_layers(), " ", (tex as TextureLayered).get_width())
	root.free()

func _uniq(uv: PackedVector2Array, c: int) -> Array:
	var d := {}
	for p in uv:
		d[int(round(p[c] * 255.0))] = true
	return d.keys()
