extends RefCounted
## Slice art pass: the market street and the three most used interiors (corner bodega, noodle bar, freight warehouse).
## Pure data (plans, meshes) plus the REAL composed game (scenes/main.tscn): a bodega entered through its door has lit people, the street has the shopfront sets.
## Looked at with tests/bot_slice_art.gd (SLICE_HUD=0 BOT_RES=2400x1080 tools/bot.sh ...), sheets in docs/shots/slice/slice_art_*.png.
## Run: tools/test.sh tests/test_slice_art.gd

const TYPES: Array[StringName] = [&"bodega", &"bar", &"warehouse"]
const SEEDS := 6
const SPEED_UP := 4

var host: Node


func run(h: Node) -> void:
	host = h
	_walls()
	_pools()
	_styles()
	_meshes()
	await _real_scene()


func _hue(c: Color) -> float:
	return c.h


# --- no flat wall longer than about 4 m ---------------------------------------------------------------------------------

func _walls() -> void:
	for t in TYPES:
		var worst := 0.0
		var dressed := 0
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd + 1)
			worst = maxf(worst, plan.bare_run_max())
			for p: Dictionary in plan.props:
				if String(p["kind"]) in ["wall_shelf", "ad_panel", "banner", "hazard_sign", "mural", "clock"]:
					dressed += 1
		TestLib.check(worst <= 4.4, "%s: no bare wall run longer than 4.4 m over %d seeds (worst %.2f m)" % [t, SEEDS, worst])
		TestLib.check(dressed >= 3, "%s: walls are dressed with shelves / boards / banners (%d pieces over %d seeds)" % [t, dressed, SEEDS])


# --- two or three coloured light pools -----------------------------------------------------------------------------------

func _pools() -> void:
	for t in TYPES:
		var bad: Array[String] = []
		for sd in SEEDS:
			var plan := InteriorPlan.generate(t, sd + 1)
			var acc: Array = []
			for p: Dictionary in plan.pools:
				if bool(p.get("accent", false)):
					acc.append(p)
			if acc.size() < 2 or acc.size() > 3:
				bad.append("seed %d has %d accent pools" % [sd + 1, acc.size()])
			var hues := {}
			for p: Dictionary in acc:
				var c: Color = p["col"]
				if c.s <= 0.25:
					bad.append("seed %d: an accent pool lost its colour (s %.2f)" % [sd + 1, c.s])
				if float(p["radius"]) <= 0.0:
					bad.append("seed %d: negative plan radius" % [sd + 1])
				hues[snappedf(c.h, 0.08)] = true
			if hues.size() < 2:
				bad.append("seed %d: the accent pools share one colour" % [sd + 1])
			for i in acc.size():
				for j in range(i + 1, acc.size()):
					var a: Vector3 = acc[i]["pos"]
					var b: Vector3 = acc[j]["pos"]
					if Vector2(a.x - b.x, a.z - b.z).length() < 2.9:
						bad.append("seed %d: accent pools closer than 3 m" % [sd + 1])
			# the cheapest tier draws all of them: they sort first
			var n_first := 0
			for p: Dictionary in plan.pools.slice(0, mini(Interior.POOLS_BY_TIER[0], plan.pools.size())):
				if bool(p.get("accent", false)):
					n_first += 1
			if n_first != acc.size():
				bad.append("seed %d: LOW draws %d of %d accent pools" % [sd + 1, n_first, acc.size()])
		TestLib.check(bad.is_empty(), "%s: 2-3 coloured accent pools, distinct hues, 3 m apart, drawn on LOW %s" % [t, str(bad)])


# --- wall and floor styles -----------------------------------------------------------------------------------------------

func _styles() -> void:
	var want := {&"bodega": [1, 1], &"bar": [3, 2], &"warehouse": [2, 3]}
	for t in TYPES:
		var plan := InteriorPlan.generate(t, 2)
		var r: Dictionary = plan.rooms[0]
		TestLib.check(int(r["style"]) == int(want[t][0]), "%s: street room wall style %d (got %d)" % [t, want[t][0], int(r["style"])])
		TestLib.check(int(r["fstyle"]) == int(want[t][1]), "%s: street room floor style %d (got %d)" % [t, want[t][1], int(r["fstyle"])])


func _meshes() -> void:
	for t in TYPES:
		for q in 3:
			var plan := InteriorPlan.generate(t, 3)
			var ms := InteriorMesher.build(plan, q)
			TestLib.check(ms["surface"] != null and int(ms["tris"]) > 1000, "%s tier %d meshes (%d tris)" % [t, q, int(ms["tris"])])
			TestLib.check(int(ms["tris"]) < 24000, "%s tier %d stays under 24k triangles (%d)" % [t, q, int(ms["tris"])])
	# every new wall piece is built on every tier (they are not detail props)
	for k in ["wall_shelf", "ad_panel", "banner", "hazard_sign", "mural", "clock"]:
		TestLib.check(not InteriorProps.has_collider(k) and InteriorProps.flags_of(k) & InteriorProps.F_DETAIL == 0, "%s: no collider, not dropped by a lower tier" % k)


# --- the real game ---------------------------------------------------------------------------------------------------------

func _real_scene() -> void:
	Sfx.muted = true
	Engine.physics_ticks_per_second = 60 * SPEED_UP
	Engine.time_scale = float(SPEED_UP)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var p := Game.player as Player
	var city := Game.world as City
	var ig := InteriorGameplay.instance
	TestLib.check(p != null and city != null and ig != null, "main.tscn is composed")
	if p == null or city == null or ig == null:
		_end()
		return
	# the street has the shopfront sets (merged mesh, one family)
	var sets := 0
	for part in city._props.parts:
		if String(part["name"]) == "ShopSets":
			sets = (part["mm"] as MultiMesh).instance_count
	TestLib.check(sets >= 40, "the street has shopfront sets in front of the shops (%d)" % sets)
	# enter a bodega: its people are lit by the room (the interior's own material), not black cut-outs
	var doors := ig.doors_of(&"bodega", Game.SPAWN)
	TestLib.check(not doors.is_empty(), "there is a bodega door")
	if not doors.is_empty():
		var d: Dictionary = doors[0]
		p.teleport_to(d["pos"])
		ig.enter(d, true)
		var guard := 0
		while (not InteriorGameplay.active or ig.busy) and guard < 120:
			await TestLib.frames(host, 2)
			guard += 1
		TestLib.check(InteriorGameplay.active and ig.interior != null, "the bodega is entered")
		if ig.interior != null and ig.actors != null:
			var lit := 0
			var total := 0
			for c in ig.actors.civilians:
				total += 1
				var body := c.get_node_or_null("Body") as MeshInstance3D
				if body != null and body.material_override == ig.interior.call("actor_material"):
					lit += 1
			if ig.actors.vendor != null:
				total += 1
				var vb := ig.actors.vendor.get_node_or_null("Body") as MeshInstance3D
				if vb != null and vb.material_override == ig.interior.call("actor_material"):
					lit += 1
			TestLib.check(total >= 3 and lit == total, "every person in the bodega is lit by the room (%d of %d)" % [lit, total])
			ig.leave(true)
			await TestLib.frames(host, 6)
			var after := 0
			for c in ig.actors.civilians:
				var body2 := c.get_node_or_null("Body") as MeshInstance3D
				if body2 != null and body2.material_override != null:
					after += 1
			TestLib.check(after == 0, "leaving clears the room material from pooled people (%d left)" % after)
	main.queue_free()
	await TestLib.frames(host, 4)
	_end()


func _end() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false
