extends RefCounted
## w120-reach PROBE (dev, not in the suite): the real main scene, real fingers only (stick + JUMP + view swipes, tests/w120_reach_lib.gd). For a list of target points over the
## whole world (districts, outskirts settlements, mountain tops, river banks and beds, lakes, shores, the airport, the army yard, a land grid, the world edge in the sea) the hero is
## set 30 m short of the target and walks / swims to it. Writes BLOCK (stopped by something; collider name, normal, terrain slope), FALL (feet more than 1.5 m under the terrain),
## EDGE (reached the world-edge wall) and STUCK lines, then 200 random drops (DROP FAIL lines).
## Run: godot --headless --path . res://tests/runner.tscn -- --test=res://tests/dev_w120_probe.gd --timeout=1500   (PROBE_N=k limits the land grid to k x k, PROBE_DROPS=n)
const TIMEOUT_SECONDS := 140
const Lib := preload("res://tests/w120_reach_lib.gd")


static func targets() -> Array[Dictionary]:
	var t: Array[Dictionary] = []
	for d in [Vector2(0, 0), Vector2(420, -380), Vector2(-450, 400), Vector2(700, 650), Vector2(-800, -760), Vector2(950, -100), Vector2(-135, -55)]:
		t.append({"name": "city %s" % d, "p": d})
	OutskirtsSites.ensure()
	for s: Dictionary in OutskirtsSites.list:
		var sp: Vector3 = s["pos"]
		t.append({"name": "site %s" % s["id"], "p": Vector2(sp.x, sp.z)})
	t.append({"name": "airport", "p": Vector2(900, 1200)})
	# mountain tops: the highest sample of each quadrant
	for q in 4:
		var best := -1e9
		var bp := Vector2.ZERO
		for i in 40:
			for j in 40:
				var x := (float(i) / 39.0) * 4300.0 * (1.0 if q % 2 == 0 else -1.0)
				var z := (float(j) / 39.0) * 4300.0 * (1.0 if q < 2 else -1.0)
				var hh := TerrainHeight.height_at(x, z)
				if hh > best:
					best = hh
					bp = Vector2(x, z)
		t.append({"name": "peak q%d h%.0f" % [q, best], "p": bp, "far": true})
	# rivers: a bank and the bed at three points of each
	WaterLayout.ensure()
	for r: Dictionary in WaterLayout.RIVERS:
		var pts: Array = r["pts"]
		for k in [1, pts.size() / 2, pts.size() - 2]:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var side := (b - a).normalized().orthogonal()
			t.append({"name": "%s bed %d" % [r["name"], k], "p": a})
			t.append({"name": "%s far bank %d" % [r["name"], k], "p": a + side * 30.0, "from": a - side * 30.0})
	for l: Dictionary in WaterLayout.LAKES:
		t.append({"name": "lake %s" % l["name"], "p": l["c"]})
	# shores: the waterline along 8 headings
	for k in 8:
		var a := TAU * float(k) / 8.0
		var dir := Vector2(cos(a), sin(a))
		var r := 1200.0
		while r < 4400.0 and TerrainHeight.height_at(dir.x * r, dir.y * r) > TerrainHeight.SEA_LEVEL:
			r += 20.0
		t.append({"name": "shore h%d" % k, "p": dir * (r + 15.0), "from": dir * (r - 30.0)})
	var n := int(OS.get_environment("PROBE_N")) if OS.get_environment("PROBE_N") != "" else 6
	for i in n:
		for j in n:
			var g := Vector2(-4000.0 + 8000.0 * i / maxf(n - 1, 1), -4000.0 + 8000.0 * j / maxf(n - 1, 1))
			if TerrainHeight.height_at(g.x, g.y) > TerrainHeight.SEA_LEVEL + 0.5:
				t.append({"name": "grid %d,%d" % [i, j], "p": g})
	return t


func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	L.fast(true)
	var only := OS.get_environment("PROBE_ONLY")
	var bad := 0
	for tg: Dictionary in targets():
		var hit := only == ""
		for o in only.split("|", false):
			hit = hit or str(tg["name"]).contains(o)
		if not hit:
			continue
		var to: Vector2 = tg["p"]
		var from: Vector2 = tg.get("from", to - (to.normalized() if to.length() > 1.0 else Vector2(1, 0)) * 30.0)
		var from3 := Vector3(from.x, Lib.ground(from.x, from.y) + 1.0, from.y)
		var to3 := Vector3(to.x, 0.0, to.y)
		await L.tp(from3, Lib.yaw_to(from3, to3))
		await L.secs(1.5)
		var r := await L.walk(to3, 20.0)
		var tag := "OK"
		if r["fell"]:
			tag = "FALL"
		elif not (r["block"] as Array).is_empty():
			tag = "BLOCK"
		elif not r["reached"]:
			tag = "STUCK"
		if tag != "OK":
			bad += 1
		print("PROBE %s %s from=%s start=%s end=%s dist=%.1f swam=%s climbed=%.1f gap=%.1f %s" % [tag, tg["name"], from, L.p.global_position.snapped(Vector3.ONE * 0.1) if false else from3.snapped(Vector3.ONE * 0.1), L.p.global_position.snapped(Vector3.ONE * 0.1), r["dist"], r["swam"], r["climbed"], r["worst_gap"], r["block"]])
	# the world edge: swim out to sea past the edge
	for k in (4 if OS.get_environment("PROBE_EDGE") != "0" else 0):
		var dir := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][k] as Vector2
		var s := dir * (CityLayout.PLAY_HALF - 40.0) + dir.orthogonal() * 300.0
		var s3 := Vector3(s.x, TerrainHeight.SEA_LEVEL - 0.5, s.y)
		var e3 := Vector3(s.x + dir.x * 120.0, 0.0, s.y + dir.y * 120.0)
		await L.place(s3, Lib.yaw_to(s3, e3))
		var r := await L.walk(e3, 40.0)
		print("PROBE EDGE dir=%s end=%s blocked=%s swam=%s turned=%d %s" % [dir, L.p.global_position.snapped(Vector3.ONE * 0.1), r["block"].size() > 0, r["swam"], L.p.swim.turned_back, r["block"]])
	# random drops
	var rng := RandomNumberGenerator.new()
	rng.seed = 120
	var nd := int(OS.get_environment("PROBE_DROPS")) if OS.get_environment("PROBE_DROPS") != "" else 60
	var fails := 0
	for i in nd:
		var x := rng.randf_range(-4300.0, 4300.0)
		var z := rng.randf_range(-4300.0, 4300.0)
		var d := await L.drop(x, z)
		if not d["ok"]:
			fails += 1
			print("PROBE DROP FAIL (%.0f, %.0f) gap=%.1f end=%s water=%s" % [x, z, d["gap"], d["pos"], d["water"]])
	print("PROBE SUMMARY bad=%d drops=%d fails=%d" % [bad, nd, fails])
	TestLib.check(true, "probe ran")
	await L.finish()
