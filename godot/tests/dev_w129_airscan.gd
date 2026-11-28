extends "res://tests/test_airfield_perf_w129.gd"
## Dev probe (w129-airdraws): at each airfield view (AIR_VIEWS) and one heading, a static census of what draws: every visible GeometryInstance3D inside its visibility range and
## the camera frustum, grouped by its path (SCAN_DEPTH levels below the main scene), with the surfaces drawn in the colour pass and the shadow casters (sun shadow range).
## Prints the measured total next to it. Run like tools/air_perf.sh with --test=res://tests/dev_w129_airscan.gd.

func _measure(view: String, settle := 45) -> void:
	await _f(settle)
	var vp := host.get_viewport()
	var s := PerfProbe.snapshot(vp)
	print("SCAN %s measured total %d visible %d prims %d" % [view, s["total_draws"], s["draws"], s["total_prims"]])
	var cam := vp.get_camera_3d()
	var city := Game.world as City
	var shadow_far := city.sun.directional_shadow_max_distance if city.sun.shadow_enabled else 0.0
	var depth := int(OS.get_environment("SCAN_DEPTH")) if OS.get_environment("SCAN_DEPTH") != "" else 5
	var root: Node = host
	var col := {}
	var shd := {}
	var tris := {}
	var st: Array = [root]
	var planes := cam.get_frustum()
	while not st.is_empty():
		var n: Node = st.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		st.append_array(n.get_children())
		if not (n is GeometryInstance3D):
			continue
		var g := n as GeometryInstance3D
		var surf := 0
		var t := 0
		if g is MeshInstance3D:
			var m := (g as MeshInstance3D).mesh
			if m == null:
				continue
			surf = m.get_surface_count()
			t = PerfProbe.mesh_triangles(m)
		elif g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var vis := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			if vis == 0:
				continue
			surf = mm.mesh.get_surface_count()
			t = PerfProbe.mesh_triangles(mm.mesh) * vis
		else:
			surf = 1
		var aabb := g.global_transform * g.get_aabb()
		var c := aabb.get_center()
		var d := cam.global_position.distance_to(c)
		if g.visibility_range_end > 0.0 and d > g.visibility_range_end + g.visibility_range_end_margin:
			continue
		if d < g.visibility_range_begin:
			continue
		var inside := true
		var r := aabb.size.length() * 0.5
		for pl: Plane in planes:
			if pl.distance_to(c) > r:
				inside = false
				break
		var key := _key(n, depth)
		if inside and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			col[key] = int(col.get(key, 0)) + surf
			tris[key] = int(tris.get(key, 0)) + t
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and d - r < shadow_far:
			shd[key] = int(shd.get(key, 0)) + surf
	var keys := {}
	for k in col:
		keys[k] = true
	for k in shd:
		keys[k] = true
	var rows: Array = []
	var tc := 0
	var ts := 0
	for k in keys:
		rows.append([int(col.get(k, 0)) + int(shd.get(k, 0)), k])
		tc += int(col.get(k, 0))
		ts += int(shd.get(k, 0))
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("SCAN %s census colour %d shadow-casting %d (shadow range %.0f m)" % [view, tc, ts, shadow_far])
	for r2: Array in rows:
		if int(r2[0]) >= 1:
			print("SCAN   %3d  col %3d shd %3d tris %7d  %s" % [r2[0], col.get(r2[1], 0), shd.get(r2[1], 0), tris.get(r2[1], 0), r2[1]])
	await _toggles(view)
	worst[view] = [int(s["total_draws"]), 0]


func _avg() -> Array:
	var a := 0.0
	var v := 0.0
	for i in 3:
		await _f(1)
		var s := PerfProbe.snapshot(host.get_viewport())
		a += float(s["total_draws"])
		v += float(s["draws"])
	return [a / 3.0, v / 3.0]


## Measured cost of a few families: hide (or switch off), read, restore.
func _toggles(view: String) -> void:
	var city := Game.world as City
	var main := host.get_child(host.get_child_count() - 1)
	var fams := {
		"SUN_SHADOW": [city.sun],
		"AirTraffic": main.find_children("AirTraffic", "", true, false),
		"Terrain": main.find_children("Terrain", "", true, false),
		"Vehicles": main.find_children("Car_*", "", true, false).filter(func(n): return is_instance_valid(n)),
		"Wildlife": main.find_children("Wildlife", "", true, false),
		"Geometry": main.find_children("Geometry", "", true, false),
		"Mirror": main.find_children("Mirror", "", false, false) + city.find_children("Mirror", "", false, false),
		"ShipWorld": main.find_children("ShipWorld", "", true, false),
		"Towns": main.find_children("Towns", "", true, false),
		"Vegetation": main.find_children("Vegetation", "", true, false),
		"Landscape": main.find_children("Landscape", "", true, false),
		"Sites": main.find_children("Sites", "", true, false),
		"Airport": main.find_children("AirportWorld", "", true, false),
		"Player": [Game.player],
	}
	var only_t := OS.get_environment("SCAN_TOGGLES")
	for k: String in fams:
		if only_t == "none":
			break
		var nodes: Array = fams[k]
		var b0: Array = await _avg()
		nodes = nodes.filter(func(n): return is_instance_valid(n))
		for n in nodes:
			if k == "SUN_SHADOW":
				(n as DirectionalLight3D).shadow_enabled = false
			elif n is Node3D:
				(n as Node3D).visible = false
		await _f(1)
		var b1: Array = await _avg()
		for n in nodes:
			if k == "SUN_SHADOW":
				(n as DirectionalLight3D).shadow_enabled = true
			elif n is Node3D:
				(n as Node3D).visible = true
		print("SCAN %s toggle %-11s n %2d  total -%.0f  visible -%.0f" % [view, k, nodes.size(), b0[0] - b1[0], b0[1] - b1[1]])
	var split := OS.get_environment("SCAN_SPLIT").split(",", false)
	for nm in split:
		var parents := main.find_children(nm, "", true, false)
		if parents.is_empty():
			continue
		for c in (parents[0] as Node).get_children():
			if not (c is Node3D) or not (c as Node3D).visible:
				continue
			var a0: Array = await _avg()
			(c as Node3D).visible = false
			await _f(1)
			var a1: Array = await _avg()
			(c as Node3D).visible = true
			if a0[0] - a1[0] >= 0.9:
				print("SCAN %s split %s/%s  total -%.0f visible -%.0f" % [view, nm, c.name, a0[0] - a1[0], a0[1] - a1[1]])
	var hud: Array = []
	for c in host.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if (c as CanvasLayer).visible:
			hud.append(c)
	var h0: Array = await _avg()
	for c in hud:
		(c as CanvasLayer).visible = false
	await _f(1)
	var h1: Array = await _avg()
	for c in hud:
		(c as CanvasLayer).visible = true
	print("SCAN %s toggle %-11s n %2d  total -%.0f  visible -%.0f" % [view, "CANVAS", hud.size(), h0[0] - h1[0], h0[1] - h1[1]])
	if OS.get_environment("SCAN_CANVAS") != "":
		for c in hud:
			var a0: Array = await _avg()
			(c as CanvasLayer).visible = false
			await _f(1)
			var a1: Array = await _avg()
			(c as CanvasLayer).visible = true
			print("SCAN %s canvas %s (layer %d) -%.0f" % [view, (c as Node).get_path(), (c as CanvasLayer).layer, a0[0] - a1[0]])
		var hudn := host.get_tree().get_first_node_in_group(&"hud")
		if hudn != null:
			for ch in hudn.find_children("*", "CanvasItem", false, false):
				if not (ch as CanvasItem).visible:
					continue
				var b0: Array = await _avg()
				(ch as CanvasItem).visible = false
				await _f(1)
				var b1: Array = await _avg()
				(ch as CanvasItem).visible = true
				if b0[0] - b1[0] >= 0.9:
					print("SCAN %s hud child %s -%.0f" % [view, ch.name, b0[0] - b1[0]])


func _key(n: Node, depth: int) -> String:
	var parts: Array[String] = []
	var x := n
	while x != null and x != host:
		parts.push_front(String(x.name).rstrip("0123456789").replace("@", ""))
		x = x.get_parent()
	if parts.size() > depth:
		parts.resize(depth)
	return "/".join(parts)
