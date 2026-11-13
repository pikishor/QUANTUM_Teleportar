extends RefCounted
## Dev helper (not a test): finds flat dry land for the settlements and writes a top-down map with a 500 m grid, roads, sites and the flat spots.
##   TERR_MAP_OUT=/tmp/x.png TERR_MAP_PX=15 SCAN_R=110 tools/test.sh tests/dev_world_scan.gd
## env: TERR_MAP_OUT (png path), TERR_MAP_PX (metres per pixel, default 15), SCAN_R (flat radius in metres, default 110), SCAN_STEP (grid step, default 120), SCAN_SLOPE (max height range in the ring, default 3.5),
##      SCAN_BOX "x0,z0,x1,z1" crops the picture (metres), SCAN_FLAT=0 skips the flat-spot search (only the map).
## prints "FLAT x z range h biome road_d coast_d" lines (best first).


func run(_host: Node) -> void:
	TerrainHeight.warm()
	var half := TerrainHeight.WORLD_HALF
	var mpp := float(OS.get_environment("TERR_MAP_PX")) if OS.get_environment("TERR_MAP_PX") != "" else 15.0
	var rad := float(OS.get_environment("SCAN_R")) if OS.get_environment("SCAN_R") != "" else 110.0
	var step := float(OS.get_environment("SCAN_STEP")) if OS.get_environment("SCAN_STEP") != "" else 120.0
	var maxr := float(OS.get_environment("SCAN_SLOPE")) if OS.get_environment("SCAN_SLOPE") != "" else 3.5
	var bx0 := -half
	var bz0 := -half
	var bx1 := half
	var bz1 := half
	if OS.get_environment("SCAN_BOX") != "":
		var bp := OS.get_environment("SCAN_BOX").split(",")
		bx0 = float(bp[0])
		bz0 = float(bp[1])
		bx1 = float(bp[2])
		bz1 = float(bp[3])
	var n := int((bx1 - bx0) / mpp)
	var nz := int((bz1 - bz0) / mpp)
	var img := Image.create(n, nz, false, Image.FORMAT_RGB8)
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (nz + 2))
	for j in nz + 2:
		for i in n + 2:
			hs[j * (n + 2) + i] = TerrainHeight.height_at(bx0 + (float(i) - 0.5) * mpp, bz0 + (float(j) - 0.5) * mpp)
	var sun := Vector3(-0.6, 0.7, -0.4).normalized()
	for j in nz:
		for i in n:
			var h := hs[(j + 1) * (n + 2) + i + 1]
			var x := bx0 + (float(i) + 0.5) * mpp
			var z := bz0 + (float(j) + 0.5) * mpp
			var dx := (hs[(j + 1) * (n + 2) + i + 2] - hs[(j + 1) * (n + 2) + i]) / (2.0 * mpp)
			var dz := (hs[(j + 2) * (n + 2) + i + 1] - hs[j * (n + 2) + i + 1]) / (2.0 * mpp)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			var shade := clampf(nrm.dot(sun) * 0.9 + 0.2, 0.15, 1.2)
			var w := TerrainHeight.water_level_at(x, z)
			var col: Color
			if w != TerrainHeight.NO_WATER:
				col = Color(0.1, 0.3, 0.55).lerp(Color(0.02, 0.1, 0.25), clampf((w - h) / 30.0, 0.0, 1.0))
			else:
				match TerrainBase.biome_at(x, z, h):
					&"city": col = Color(0.5, 0.5, 0.55)
					&"beach": col = Color(0.85, 0.8, 0.6)
					&"forest": col = Color(0.18, 0.4, 0.16)
					&"desert": col = Color(0.72, 0.55, 0.3)
					&"mountain": col = Color(0.5, 0.48, 0.45)
					_: col = Color(0.4, 0.5, 0.25)
				if h > TerrainBase.SNOW_LINE:
					col = col.lerp(Color(0.95, 0.97, 1.0), clampf((h - TerrainBase.SNOW_LINE) / 80.0, 0.0, 1.0))
				col = col * shade
			img.set_pixel(i, j, col)
	var found: Array = []
	if OS.get_environment("SCAN_FLAT") != "0":
		var gx := bx0 + step * 0.5
		while gx < bx1 - step * 0.5:
			var gz := bz0 + step * 0.5
			while gz < bz1 - step * 0.5:
				var c := Vector2(gx, gz)
				if TerrainHeight.city_distance(gx, gz) < rad + 150.0 or absf(gx) > half - 200.0 or absf(gz) > half - 200.0:
					gz += step
					continue
				var h0 := TerrainHeight.height_at(gx, gz)
				if h0 < 1.5 or TerrainHeight.is_water(gx, gz):
					gz += step
					continue
				var lo := h0
				var hi := h0
				var wet := false
				for ring in [0.5, 1.0]:
					for k in 12:
						var a := TAU * float(k) / 12.0
						var q := c + Vector2(cos(a), sin(a)) * rad * float(ring)
						var hh := TerrainHeight.height_at(q.x, q.y)
						lo = minf(lo, hh)
						hi = maxf(hi, hh)
						if TerrainHeight.is_water(q.x, q.y) or hh < 1.0:
							wet = true
				if not wet and hi - lo <= maxr:
					var rn := TerrainRoads.nearest(gx, gz)
					var biome := TerrainBase.biome_at(gx, gz, h0)
					found.append({"x": gx, "z": gz, "range": hi - lo, "h": h0, "biome": biome, "road": float(rn[0]), "coast": TerrainHeight.coast_distance(gx, gz) - TerrainHeight.city_distance(gx, gz)})
					_dot(img, n, nz, int((gx - bx0) / mpp), int((gz - bz0) / mpp), 1, Color(1.0, 0.0, 1.0))
				gz += step
			gx += step
	for r in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		for p in pts:
			_dot(img, n, nz, int((p.x - bx0) / mpp), int((p.y - bz0) / mpp), 0, Color(1.0, 0.9, 0.2) if r["kind"] == "highway" else Color(0.95, 0.45, 0.1))
	for s in OutskirtsSites.list:
		var sp: Vector3 = s["pos"]
		_dot(img, n, nz, int((sp.x - bx0) / mpp), int((sp.z - bz0) / mpp), 2, Color(1.0, 1.0, 1.0) if String(s["kind"]) != "town" else Color(1.0, 0.2, 0.2))
	var g := ceilf(bx0 / 500.0) * 500.0
	while g <= bx1:
		var ip := int((g - bx0) / mpp)
		var bright := absi(int(round(g / 1000.0)) * 1000 - int(round(g))) < 1
		if ip >= 0 and ip < n:
			for k in nz:
				img.set_pixel(ip, k, img.get_pixel(ip, k).lerp(Color.WHITE, 0.4 if bright else 0.16))
		g += 500.0
	g = ceilf(bz0 / 500.0) * 500.0
	while g <= bz1:
		var ip2 := int((g - bz0) / mpp)
		var bright2 := absi(int(round(g / 1000.0)) * 1000 - int(round(g))) < 1
		if ip2 >= 0 and ip2 < nz:
			for k in n:
				img.set_pixel(k, ip2, img.get_pixel(k, ip2).lerp(Color.WHITE, 0.4 if bright2 else 0.16))
		g += 500.0
	var out := OS.get_environment("TERR_MAP_OUT")
	if out != "":
		img.save_png(out)
		print("saved ", out, " ", n, "x", nz)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["range"]) < float(b["range"]))
	var shown := 0
	for f: Dictionary in found:
		if shown >= 160:
			break
		shown += 1
		print("FLAT %5.0f %5.0f range %.1f h %.0f %s road %.0f coast %.0f" % [f["x"], f["z"], f["range"], f["h"], String(f["biome"]), f["road"], f["coast"]])
	print("flat candidates: ", found.size())


static func _dot(img: Image, n: int, nz: int, ix: int, iy: int, r: int, c: Color) -> void:
	for ox in range(-r, r + 1):
		for oy in range(-r, r + 1):
			var px := ix + ox
			var py := iy + oy
			if px >= 0 and px < n and py >= 0 and py < nz:
				img.set_pixel(px, py, c)
