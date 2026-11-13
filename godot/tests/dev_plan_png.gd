extends RefCounted
## Dev helper (not a test): draws the plan of every town (ellipse, main street, side streets, buildings, props) top-down into one PNG. PLAN_OUT=/path.png tools/test.sh tests/dev_plan_png.gd
func run(_host: Node) -> void:
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	var towns := SettlementData.towns()
	var tile := Vector2i(330, 480)
	var img := Image.create(tile.x * towns.size(), tile.y, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.14, 0.12))
	var k := 1.35
	for ti in towns.size():
		var s := towns[ti]
		var pl := SettlementData.plan_of(s)
		var ox := ti * tile.x + tile.x / 2
		var oy := tile.y / 2
		var pxy := func(v: Vector2) -> Vector2i: return Vector2i(ox + int(v.x * k), oy + int(v.y * k))
		for a in 720:
			var an := TAU * float(a) / 720.0
			var q: Vector2i = pxy.call(Vector2(cos(an) * pl.r, sin(an) * pl.ln))
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				img.set_pixelv(q, Color(0.9, 0.9, 0.3))
		for i in pl.street.size() - 1:
			for t in 20:
				var q2: Vector2i = pxy.call(pl.street[i].lerp(pl.street[i + 1], float(t) / 20.0))
				for dx in range(-5, 6):
					if q2.x + dx >= 0 and q2.x + dx < img.get_width():
						img.set_pixel(q2.x + dx, clampi(q2.y, 0, img.get_height() - 1), Color(0.3, 0.3, 0.33))
		for sd in pl.sides:
			for t in 40:
				var q3: Vector2i = pxy.call((sd["a"] as Vector2).lerp(sd["b"], float(t) / 40.0))
				for dd in range(-2, 3):
					if q3.x + dd >= 0 and q3.x + dd < img.get_width() and q3.y >= 0 and q3.y < img.get_height():
						img.set_pixel(q3.x + dd, q3.y, Color(0.45, 0.45, 0.5))
		for it in pl.items:
			var c := Color(0.9, 0.55, 0.3) if it["kind"] == &"house" else Color(0.4, 0.8, 1.0)
			var hw: float = float(it["w"]) * 0.5
			var hd: float = float(it["d"]) * 0.5
			var yaw: float = it["yaw"]
			for u in range(-int(hw * k), int(hw * k) + 1):
				for v in range(-int(hd * k), int(hd * k) + 1):
					var lx := float(u) / k
					var lz := float(v) / k
					var wx: float = float(it["x"]) + lx * cos(yaw) + lz * sin(yaw)
					var wz: float = float(it["z"]) - lx * sin(yaw) + lz * cos(yaw)
					var q4: Vector2i = pxy.call(Vector2(wx, wz))
					if q4.x >= 0 and q4.y >= 0 and q4.x < img.get_width() and q4.y < img.get_height():
						img.set_pixelv(q4, c)
		var sea := pl.sea
		if sea.length() > 0.1:
			var e: Vector2i = pxy.call(sea * 140.0)
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					var qq := Vector2i(e.x + dx, e.y + dy)
					if qq.x >= 0 and qq.y >= 0 and qq.x < img.get_width() and qq.y < img.get_height():
						img.set_pixelv(qq, Color(0.2, 0.5, 1.0))
		for pr in pl.props:
			var q5: Vector2i = pxy.call(Vector2(pr["x"], pr["z"]))
			if q5.x >= 0 and q5.y >= 0 and q5.x < img.get_width() and q5.y < img.get_height():
				img.set_pixelv(q5, Color(0.3, 0.7, 0.3) if String(pr["kind"]).begins_with("tree") else Color(0.9, 0.9, 0.9))
	img.save_png(OS.get_environment("PLAN_OUT") if OS.get_environment("PLAN_OUT") != "" else "/tmp/plans.png")
