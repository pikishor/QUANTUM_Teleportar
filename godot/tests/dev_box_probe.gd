extends RefCounted
## Dev helper (not a test): reachability on the harbour apron. Flood fill (2 m cells, a car-sized body needs 3 m clearance) from the end of the HARBOUR ROAD through the free ground between the collision
## boxes of the harbour kit: which docks, pads and berths can be reached on foot and by car. tools/test.sh tests/dev_box_probe.gd
const TIMEOUT_SECONDS := 100


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var hw := HarbourWorld.instance
	var boxes: Array[AABB] = []
	var body := hw.get_node("Collision") as StaticBody3D
	for c in body.get_children():
		var cs := c as CollisionShape3D
		var bs := cs.shape as BoxShape3D
		boxes.append(AABB(cs.position - bs.size * 0.5, bs.size))
	print("BOX %d boxes" % boxes.size())
	for b in boxes:
		print("BOX x %.0f..%.0f z %.0f..%.0f y %.1f..%.1f" % [b.position.x, b.end.x, b.position.z, b.end.z, b.position.y, b.end.y])
	var x0 := -360.0
	var z0 := 1300.0
	var step := 2.0
	var nx := 380
	var nz := 230
	for clear_r: float in [0.6, 1.6]:
		var blocked := PackedByteArray()
		blocked.resize(nx * nz)
		for j in nz:
			for i in nx:
				var wx := x0 + (float(i) + 0.5) * step
				var wz := z0 + (float(j) + 0.5) * step
				var bl := 0
				for b in boxes:
					if b.end.y < 1.3:
						continue
					if wx > b.position.x - clear_r and wx < b.end.x + clear_r and wz > b.position.z - clear_r and wz < b.end.z + clear_r and b.position.y < 3.5:
						bl = 1
						break
				# water / basin: ground below the quay level - 1 and not covered by a deck box
				if bl == 0:
					var gy := TerrainHeight.height_at(wx, wz)
					if gy < 0.6:
						var deck := false
						for b in boxes:
							if b.end.y > 0.3 and b.end.y < 1.3 and wx > b.position.x and wx < b.end.x and wz > b.position.z and wz < b.end.z:
								deck = true
								break
						if not deck:
							bl = 2
				blocked[j * nx + i] = bl
		var seen := PackedByteArray()
		seen.resize(nx * nz)
		var start := Vector2i(int((-300.0 - x0) / step), int((1334.0 - z0) / step))
		var q: Array[Vector2i] = [start]
		seen[start.y * nx + start.x] = 1
		var n := 0
		while not q.is_empty():
			var c: Vector2i = q.pop_back()
			n += 1
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var o := c + d
				if o.x < 0 or o.y < 0 or o.x >= nx or o.y >= nz or seen[o.y * nx + o.x] != 0 or blocked[o.y * nx + o.x] != 0:
					continue
				seen[o.y * nx + o.x] = 1
				q.append(o)
		print("BOX flood (clearance %.1f m) from the road end reaches %d cells (%.0f m2)" % [clear_r, n, float(n) * step * step])
		var targets: Array = []
		for dk: Dictionary in Harbour.DOCKS:
			targets.append([String(dk["name"]), dk["pos"]])
		targets.append(["PAD harbour", Vector3(-282.0, 1.2, 1360.0)])
		targets.append(["road end", Vector3(-300.0, 1.2, 1338.0)])
		targets.append(["bridge gate south", Vector3(-300.0, 1.2, 1600.0)])
		for t: Array in targets:
			var tp: Vector3 = t[1]
			var ci := Vector2i(int((tp.x - x0) / step), int((tp.z - z0) / step))
			var ok := false
			for dj in range(-3, 4):
				for di in range(-3, 4):
					var o := ci + Vector2i(di, dj)
					if o.x >= 0 and o.y >= 0 and o.x < nx and o.y < nz and seen[o.y * nx + o.x] != 0:
						ok = true
			print("BOX   reach %-18s at (%.0f, %.0f): %s" % [t[0], tp.x, tp.z, "YES" if ok else "NO (blocked: %d)" % blocked[ci.y * nx + ci.x]])
		if clear_r == 0.6:
			var rows := PackedStringArray()
			for j in range(0, nz, 4):
				var line := ""
				for i in range(0, nx, 2):
					var v := blocked[j * nx + i]
					line += ("#" if v == 1 else ("~" if v == 2 else ("o" if seen[j * nx + i] != 0 else ".")))
				rows.append(line)
			for r in rows:
				print("BOXMAP ", r)
	Game.state = &"menu"
	main.queue_free()
