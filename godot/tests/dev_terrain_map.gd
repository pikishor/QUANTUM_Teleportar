extends RefCounted
## Dev helper (not a test): writes a top-down hill-shaded map of the whole world to $TERR_MAP_OUT (PNG). tools/test.sh tests/dev_terrain_map.gd
## env: TERR_MAP_OUT (path), TERR_MAP_PX (metres per pixel, default 10), TERR_MAP_ROADS=1 draws TerrainRoads when the class exists.


func run(_host: Node) -> void:
	var out := OS.get_environment("TERR_MAP_OUT")
	if out == "":
		print("set TERR_MAP_OUT")
		return
	var mpp := float(OS.get_environment("TERR_MAP_PX")) if OS.get_environment("TERR_MAP_PX") != "" else 10.0
	TerrainHeight.warm()
	var half := TerrainHeight.WORLD_HALF
	var n := int(2.0 * half / mpp)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var hs := PackedFloat32Array()
	hs.resize((n + 2) * (n + 2))
	var t0 := Time.get_ticks_msec()
	for j in n + 2:
		for i in n + 2:
			hs[j * (n + 2) + i] = TerrainHeight.height_at(-half + (float(i) - 0.5) * mpp, -half + (float(j) - 0.5) * mpp)
	print("sampled ", n * n, " in ms ", Time.get_ticks_msec() - t0)
	var sun := Vector3(-0.6, 0.7, -0.4).normalized()
	for j in n:
		for i in n:
			var h := hs[(j + 1) * (n + 2) + i + 1]
			var x := -half + (float(i) + 0.5) * mpp
			var z := -half + (float(j) + 0.5) * mpp
			var dx := (hs[(j + 1) * (n + 2) + i + 2] - hs[(j + 1) * (n + 2) + i]) / (2.0 * mpp)
			var dz := (hs[(j + 2) * (n + 2) + i + 1] - hs[j * (n + 2) + i + 1]) / (2.0 * mpp)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			var shade := clampf(nrm.dot(sun) * 0.9 + 0.2, 0.15, 1.2)
			var w := TerrainHeight.water_level_at(x, z)
			var col: Color
			if w != TerrainHeight.NO_WATER:
				col = Color(0.1, 0.3, 0.55).lerp(Color(0.02, 0.1, 0.25), clampf((w - h) / 30.0, 0.0, 1.0))
			else:
				var b := TerrainBase.biome_at(x, z, h)
				match b:
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
	if OS.get_environment("TERR_MAP_ROADS") == "1":
		for r in TerrainRoads.roads():
			var pts: PackedVector2Array = r["pos"]
			for p in pts:
				var ix := int((p.x + half) / mpp)
				var iy := int((p.y + half) / mpp)
				for ox in range(-1, 2):
					for oy in range(-1, 2):
						if ix + ox >= 0 and ix + ox < n and iy + oy >= 0 and iy + oy < n:
							img.set_pixel(ix + ox, iy + oy, Color(1.0, 0.9, 0.2) if r["kind"] == "highway" else Color(0.9, 0.4, 0.1))
	# the city square
	var c0 := int((-1100.0 + half) / mpp)
	var c1 := int((1100.0 + half) / mpp)
	for k in range(c0, c1):
		for e in [c0, c1]:
			img.set_pixel(k, e, Color(1, 0, 1))
			img.set_pixel(e, k, Color(1, 0, 1))
	img.save_png(out)
	print("saved ", out)
