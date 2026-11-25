extends RefCounted
## WAVE 122 ROOMS (owner round 7: "buildings with interiors, stairs and detail"; plan: "rooms that match the outside, furniture"). The real main scene at the phone's 844x390, the
## phone HUD, REAL FINGERS only (the left thumb on the stick, view swipes: tests/w116_fingers.gd through tests/w120_reach_lib.gd), the phone-only layers on (CrateReveal._quiet = 0).
## Start points are set up by teleport on the sidewalk; every way in is a finger on the stick.
##   kinds     an OFFICE tower, an APARTMENTS tower and a HOUSE (a low city block, wave 121: USE door to a 14 x 7 m room far away) are walked into from the street, the inside is the
##             outside's footprint (same lot, same size), no USE, no fade                                                                         [old fails: the house]
##   windows   window holes stand where the facade windows are on the floors; none opens from the stairwell onto the street                          [old fails: 28 stairwell holes]
##   furniture rooms furnished by kind (office desks + chairs + screens + shelves, homes beds + sofas + kitchens, lobby desk + plants) and the pieces are solid
##   look      no bare / white room on LOW and MED: floors, walls and ceilings carry surface detail (tiles, plaster, panels) in the tower shader   [old fails: no detail]
##   rain      MED rain: no lens rain / curtain inside a tower lobby                                                                             [old fails]
##   gun       the gun leaves the frame with the hero when the stairwell camera fades him                                                        [old fails: drawn at fade 0.6]
##   people    people at work on the hero's floor, armed men on the top floor of a held tower                                                    [old fails: nobody]
## W122_OLD=1 = the wave 121 code (TowerFloors.rooms_on false, PlayerBody.gun_fade_on false). Run: tools/test.sh tests/test_rooms_w122.gd
const TIMEOUT_SECONDS := 150
const Lib := preload("res://tests/w120_reach_lib.gd")

var L: Lib
var old := false


func run(h: Node) -> void:
	old = OS.get_environment("W122_OLD") == "1"
	TowerFloors.rooms_on = not old
	PlayerBody.gun_fade_on = not old
	h.get_tree().root.size = Vector2i(844, 390)
	L = Lib.new()
	await L.start(h)
	L.fast(true)
	var tf := TowerFloors.instance
	tf.towers.clear()
	tf._collect()
	var by_kind := {}
	for t in tf.towers:
		by_kind[t["kind"]] = int(by_kind.get(t["kind"], 0)) + 1
	print("walk-in buildings by kind: %s" % by_kind)
	TestLib.check(by_kind.has(&"house") and by_kind.size() >= 4, "houses as well as towers are walked into in place (%s) [old fails: towers only]" % by_kind)
	var office := _held_office()
	for spec in [[&"office", office], [&"apartment", tf.nearest(Game.SPAWN, TowerFloors.MIN_H, &"apartment")], [&"house", tf.nearest(Game.SPAWN, 0.0, &"house")]]:
		await _kind(spec[0], spec[1])
	await _windows(office)
	await _rain_and_gun(office)
	TowerFloors.rooms_on = true
	PlayerBody.gun_fade_on = true
	await L.finish()


## The office tower nearest the spawn whose top floor is held (FOE_CHANCE hash); any office tower when none.
func _held_office() -> Dictionary:
	var tf := TowerFloors.instance
	var best := {}
	var bd := INF
	for t in tf.towers:
		if t["kind"] != &"office":
			continue
		var lot: CityLayout.Lot = t["lot"]
		var held := fposmod(sin(float(lot.index) * 12.9898 + 122.0 * 78.233) * 43758.5453, 1.0) < TowerFloors.FOE_CHANCE
		var d := TowerFloors.door_pos(t).distance_to(Game.SPAWN) + (0.0 if held else 5000.0)
		if d < bd:
			bd = d
			best = t
	return best


## Walk in through the street door by the stick. True when he stands inside the open building.
func _walk_in(tw: Dictionary) -> bool:
	var tf := TowerFloors.instance
	var door := TowerFloors.door_pos(tw, 4.0)
	tf.open(tw)                                  # only to know where the lobby point is (closed again at once; the old code never opens a house)
	var p0 := tf.route(0)[0]
	tf.close()
	await L.tp(TowerFloors.door_pos(tw, 70.0), 0.0)
	await L.secs(0.5)
	await L.tp(door, Lib.yaw_to(door, p0))
	var r := await L.walk(p0, 10.0, 0.6, 0.8)
	await L.secs(0.5)
	return r["reached"] and TowerFloors.inside(L.p.global_position) and TowerFloors.open_lot == (tw["lot"] as CityLayout.Lot).index


func _kind(kind: StringName, tw: Dictionary) -> void:
	if tw.is_empty():
		TestLib.check(false, "%s: a building of this kind can be walked into [old fails]" % kind)
		return
	var tf := TowerFloors.instance
	var lot: CityLayout.Lot = tw["lot"]
	var ok := await _walk_in(tw)
	var gp := L.p.global_position
	var fu := TowerFloors.inner_u(tw) + 2.0 * TowerFloors.IN
	var fv := TowerFloors.inner_v(tw) + 2.0 * TowerFloors.IN
	var ow := lot.w if absf((tw["t"] as Vector3).x) > 0.5 else lot.d
	var od := lot.d if absf((tw["t"] as Vector3).x) > 0.5 else lot.w
	TestLib.check(ok and not InteriorGameplay.active and absf(gp.y) < 0.5, "%s lot %d (%.0f x %.0f x %.0f m): by the stick through its street door into the building itself, no USE, no fade (hero %s)" % [kind, lot.index, lot.w, lot.d, lot.h, gp])
	TestLib.check(ok and absf(fu - ow) < 0.05 and absf(fv - od) < 0.05 and tf._levels.size() >= 3, "%s: the inside is the outside's footprint %.1f x %.1f (outside %.1f x %.1f), %d floors + roof on the facade's floor lines" % [kind, fu, fv, ow, od, tf._levels.size() - 2])
	if not ok:
		return
	# furniture by kind: floor 1 is built while he stands on the street floor (his floor and the next); the house's street floor too
	var want := {&"office": [&"desk", &"chair", &"screen", &"shelf", &"table"], &"apartment": [&"bed", &"sofa", &"kitchen", &"table", &"wardrobe"], &"house": [&"kitchen", &"sofa", &"shelf", &"tv"]}
	var tags := {}
	var solid: Array = []
	for k in ([0, 1] if kind == &"house" else [1]):
		for b: Array in tf._room_boxes(k):
			if b.size() > 9:
				tags[b[9]] = true
				if b[6] and b[9] != &"wall" and solid.size() < 6:
					solid.append(b)
	var missing: Array = (want[kind] as Array).filter(func(t: StringName) -> bool: return not tags.has(t))
	TestLib.check(missing.is_empty(), "%s: rooms furnished by kind (missing %s, has %s) [old fails]" % [kind, missing, tags.keys()])
	var hit := 0
	var space := L.p.get_world_3d().direct_space_state
	for b: Array in solid:
		var q := PhysicsPointQueryParameters3D.new()
		q.position = TowerFloors.at(tw, (b[0] + b[3]) * 0.5, (b[1] + b[4]) * 0.5, (b[2] + b[5]) * 0.5)
		q.collision_mask = Game.L_WORLD
		for r in space.intersect_point(q, 4):
			if r["collider"] == tf._room_body:
				hit += 1
				break
	TestLib.check(solid.size() >= 4 and hit == solid.size(), "%s: the furniture is solid (%d of %d pieces have a collider) [old fails]" % [kind, hit, solid.size()])
	if kind == &"office" or kind == &"house":
		# the look on LOW and MED: the tower's own material (unshaded, no fog: never washed white), surface detail on floors, walls and ceilings, shaded walls and floors under 0.6
		for q in [0, 1]:
			Game.set_quality(q)
			await L.f(6)
			var mesh := tf._mesh.mesh as ArrayMesh if tf._mesh != null else null
			var cls := {}
			var bright := 0.0
			var n := 0
			if mesh != null and mesh.get_surface_count() > 0:
				var arr := mesh.surface_get_arrays(0)
				var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
				var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
				var nms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				if uv is PackedVector2Array and (uv as PackedVector2Array).size() == cols.size():
					for i in range(0, cols.size(), 6):
						var c := int(round((uv as PackedVector2Array)[i].x))
						cls[c] = true
						if (c == 1 or c == 2) and cols[i].a < 0.5:
							var sh := 0.40 + 0.16 * nms[i].y + 0.06 * nms[i].x - 0.03 * nms[i].z
							bright += (cols[i].r + cols[i].g + cols[i].b) / 3.0 * sh
							n += 1
			var avg := bright / maxf(1.0, n)
			var mat_ok := tf._mesh != null and tf._mesh.material_override == tf._mat and tf._mat.shader.code.contains("cls")
			TestLib.check(mat_ok and cls.has(1) and cls.has(2) and cls.has(3) and n > 0 and avg < 0.6, "%s on %s: floors, walls and ceilings carry surface detail (classes %s), shaded wall / floor brightness %.2f, not a white bare room [old fails]" % [kind, ["LOW", "MED"][q], cls.keys(), avg])
		Game.set_quality(0)
	# people: at work / at home on his floor; armed men on the top floor of a held tower
	await L.secs(0.6)
	var pp := tf.people()
	var on_floor := 0
	for c in pp["actors"]:
		if TowerFloors.inside((c as Node3D).global_position) and absf((c as Node3D).global_position.y - tf._levels[0]) < 0.5:
			on_floor += 1
	TestLib.check(on_floor >= 2, "%s: people stand on his floor inside the building (%d) [old fails]" % [kind, on_floor])
	if kind == &"office":
		var top := tf._levels[tf._levels.size() - 2]
		var up := 0
		for d in pp["foes"]:
			var dp: Vector3 = (d as Node3D).global_position
			if TowerFloors.inside(dp) and absf(dp.y - top) < 1.0:
				up += 1
		TestLib.check(up >= 1, "held office tower: armed men on the top floor (%d at y %.1f) [old fails]" % [up, top])


## Coverage of the tower mesh at a world point on a wall plane: true when a triangle of the mesh covers it.
func _covered(tf: TowerFloors, p: Vector3, n: Vector3) -> bool:
	var arr := (tf._mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in range(0, v.size(), 3):
		var a := v[i]
		var b := v[i + 1]
		var c := v[i + 2]
		var tn := (b - a).cross(c - a)
		if tn.length() < 1e-6 or absf(tn.normalized().dot(n)) < 0.95 or absf((p - a).dot(tn.normalized())) > 0.03:
			continue
		var w: Variant = Geometry3D.ray_intersects_triangle(p + n * 0.05, -n, a, b, c)
		if w != null:
			return true
		w = Geometry3D.ray_intersects_triangle(p - n * 0.05, n, a, b, c)
		if w != null:
			return true
	return false


func _windows(tw: Dictionary) -> void:
	var tf := TowerFloors.instance
	var ok := await _walk_in(tw)
	if not ok or tf._mesh == null:
		TestLib.check(false, "windows: inside the office tower")
		return
	var style: int = tw["b"].style
	var fu := TowerFloors.inner_u(tw) + 2.0 * TowerFloors.IN
	var iv := TowerFloors.inner_v(tw)
	var open_street := 0
	var street_n := 0
	var stair_open := 0
	var stair_n := 0
	for k in [1, 2]:
		for w: Rect2 in tf._windows(fu, TowerFloors.IN, k, style):
			var mid := w.get_center()
			# street wall (v = iv): the facade window is a hole
			if mid.x > 0.5 and mid.x < TowerFloors.inner_u(tw) - 0.5:
				street_n += 1
				if not _covered(tf, TowerFloors.at(tw, mid.x, iv, mid.y), tw["n"]):
					open_street += 1
			# back wall over the stairwell (v = 0, u < SHAFT_L): no hole onto the street
			if mid.x > 0.2 and mid.x < TowerFloors.SHAFT_L:
				stair_n += 1
				if not _covered(tf, TowerFloors.at(tw, mid.x, 0.0, mid.y), tw["n"]):
					stair_open += 1
	TestLib.check(street_n > 0 and open_street == street_n, "windows: every facade window of floors 1-2 is a hole in the street wall at the same place (%d of %d)" % [open_street, street_n])
	TestLib.check(stair_n > 0 and stair_open == 0, "windows: no window opens from the stairwell onto the street (%d of %d open) [old fails]" % [stair_open, stair_n])


func _rain_and_gun(tw: Dictionary) -> void:
	var tf := TowerFloors.instance
	Game.set_quality(1)
	var atm := Game.atmosphere as Atmosphere
	atm.set_weather(0.9, 0.9, true)
	var ok := await _walk_in(tw)
	await L.secs(1.0)
	var lens: float = atm.post._rain
	TestLib.check(ok and atm.rain_now > 0.5 and lens < 0.01, "MED, heavy rain: no lens rain / rain curtain inside the lobby (lens %.2f, rain %.2f) [old fails]" % [lens, atm.rain_now])
	# the stairwell: the right thumb turns the view round until the lens is against the wall and the hero fades; the gun must be gone with him
	var pts := tf.route(1)
	for i in range(1, 4):
		await L.walk(pts[i], 5.0, 0.5, 0.6)
	var body := L.p.body as PlayerBody
	var worst := 0.0
	var seen_fade := 0.0
	for s in 24:
		L.fg.look(70.0, 25.0 if s % 2 == 0 else -25.0, 4)
		await L.f(4)
		var f := L.p.camera_rig.hero_fade
		if f < 0.5:
			continue
		seen_fade = maxf(seen_fade, f)
		for n in body.muzzle.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if g.is_visible_in_tree() and g.layers != 0 and g.transparency < 0.9:
				worst = maxf(worst, f)
	TestLib.check(seen_fade >= 0.5, "the stairwell camera faded the hero by the fingers' swipes (max fade %.2f)" % seen_fade)
	TestLib.check(seen_fade >= 0.5 and worst == 0.0, "no gun drawn alone while the hero is faded (gun seen at fade %.2f) [old fails]" % worst)
	atm.set_weather(0.0, 0.3, true)
	Game.set_quality(0)
