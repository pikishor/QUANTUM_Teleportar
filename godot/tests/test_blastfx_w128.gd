extends RefCounted
## WAVE 128 (owner: "ensure the blast etc are looking more realistic"). The real main scene as a phone (touch forced, reward cards on): blasts of every physical class of the blast table
## (grenade, launcher, mine, strike, ordnance, world blaster) fired with BlastTable.apply where the hero stands, then the pools are read:
##   the fireball burns out into soot (ExplosionPool fire layer `soot`), the ground throws a dust skirt in the colour of the ground (concrete grey in the city, brown soil outside, white over water),
##   the smoke is dark, climbs and drifts downwind (BlastFx cloud puffs), water gives a splash column and no scorch, the sound is layered by distance (debris patter close, the late distant boom far),
##   energy blasts (plasma) keep their clean look, and four blasts at once stay inside the pools of the tier (no new draw).
## Fail-first: W128B_OLD=1 tools/test.sh tests/test_blastfx_w128.gd (the look of wave 127).
## Run: tools/test.sh tests/test_blastfx_w128.gd

const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const CLASSES := [&"gr_frag", &"la_rocket", &"mn_c4", &"st_air_s", &"ord_tank_he", &"wb_gas_tank"]
var A: Audit
var _p: Player


func run(h: Node) -> void:
	A = Audit.new()
	var ok := await A.boot(h, "w128b")
	TestLib.check(ok, "the phone scene boots")
	if not ok:
		await A.shutdown()
		return
	Sfx.muted = true
	_p = Game.player as Player
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	Game.state = &"play"
	(Game.enemies as EnemyManager).clear()
	await A.frames(4)
	var cam := Game.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var street := _p.global_position + fwd * 16.0
	street.y = BlastFx.ground_y(street + Vector3(0.0, 3.0, 0.0))
	# 1 every physical class on the city street: soot, a grey dust skirt, dark smoke
	var soot_ok := 0
	var dust_ok := 0
	var names: Array[String] = []
	for id: StringName in CLASSES:
		_clear()
		BlastTable.apply(id, street, _p, {})
		await A.frames(2)
		var s: Variant = _latest_slot()
		var soot := float(s.fire_mat.get_shader_parameter(&"soot")) if s != null else 0.0
		var dust := float(s.ground_mat.get_shader_parameter(&"dust")) if s != null else 0.0
		var dc: Color = s.ground_mat.get_shader_parameter(&"dust_col") if s != null else Color.BLACK
		if soot > 0.5:
			soot_ok += 1
		if dust > 0.5 and absf(dc.r - dc.b) < 0.1:
			dust_ok += 1
		names.append("%s soot %.1f dust %.1f" % [id, soot, dust])
	TestLib.check(soot_ok == CLASSES.size(), "grenade, launcher, mine, strike, ordnance and world blasts burn out into soot (%s)" % ", ".join(names))
	TestLib.check(dust_ok == CLASSES.size() and BlastFx.last_ground == &"concrete", "and throw a grey concrete dust skirt in the city (%d of %d, ground %s)" % [dust_ok, CLASSES.size(), BlastFx.last_ground])
	# 2 the smoke column: dark puffs that climb and drift downwind
	_clear()
	BlastTable.apply(&"la_rocket", street, _p, {})
	await A.frames(1)
	var fx := BlastFx.shared()
	var dark := _dark_smoke(fx)
	var mine: Array[int] = []                                                    # the puffs of THIS blast (a burning car from the blasts before smokes too)
	for i in BlastFx.CLOUD_TOTAL:
		if fx._c_alive[i] != 0 and int(fx._c_kind[i]) == BlastFx.K_SMOKE and (fx._c_col[i] as Color).get_luminance() < 0.25 and fx._c_age[i] < 0.2 and Vector2(fx._c_pos[i].x - street.x, fx._c_pos[i].z - street.z).length() < 6.0:
			mine.append(i)
	var start := _centre_of(fx, mine)
	for i in 150:
		await A.pframes(1)
	var after := _centre_of(fx, mine)
	var drift := (after - start)
	var down := Vector3(drift.x, 0.0, drift.z).dot(BlastFx.WIND.normalized())
	TestLib.check(dark >= 2, "a rocket leaves a column of %d dark smoke puffs (near-black, not the old pale pink haze)" % dark)
	TestLib.check(drift.y > 3.0 and down > 1.0, "the smoke climbs %.1f m and drifts %.1f m downwind in 2.5 s (%s -> %s, %d dark)" % [drift.y, down, start, after, _dark_smoke(fx)])
	# 3 sound by distance: debris close by, the distant boom far away
	_clear()
	BlastTable.apply(&"ord_tank_he", street, _p, {})
	var near_layers := BlastFx.last_layers.duplicate()
	var far_pos := cam.global_position + fwd * 120.0
	far_pos.y = BlastFx.ground_y(far_pos + Vector3(0.0, 30.0, 0.0))
	BlastTable.apply(&"ord_tank_he", far_pos, _p, {})
	var far_layers := BlastFx.last_layers.duplicate()
	TestLib.check(near_layers.has(&"debris") and not near_layers.has(&"distant_boom"), "a shell 16 m away is followed by falling debris (%s)" % str(near_layers))
	TestLib.check(far_layers.has(&"distant_boom") and not far_layers.has(&"debris"), "a shell 120 m away is a late distant boom (%s)" % str(far_layers))
	# 4 ground types: soil outside the city, water
	var soil := _find(func(x: float, z: float) -> bool: return TerrainHeight.city_distance(x, z) > 30.0 and not TerrainHeight.is_water(x, z) and BlastFx.ground_kind(Vector3(x, TerrainHeight.height_at(x, z), z)) == &"dirt")
	var water := _find(func(x: float, z: float) -> bool: return TerrainHeight.is_water(x, z) and TerrainHeight.city_distance(x, z) > 0.0)
	TestLib.check(soil.is_finite() and water.is_finite(), "the map has soil and water to try (%s, %s)" % [soil, water])
	if soil.is_finite():
		_clear()
		BlastFx.play(BlastTable.entry(&"gr_frag"), soil, 4.0, {"quiet": true})
		var s2: Variant = _latest_slot()
		var dc2: Color = s2.ground_mat.get_shader_parameter(&"dust_col") if s2 != null else Color.BLACK
		TestLib.check(BlastFx.last_ground == &"dirt" and dc2.r > dc2.b + 0.1, "a grenade on soil throws brown dust (%s, %s)" % [BlastFx.last_ground, dc2])
	if water.is_finite():
		_clear()
		var wl := TerrainHeight.water_level_at(water.x, water.z)
		var at := Vector3(water.x, wl + 0.2, water.z)
		_p.global_position = at + Vector3(0.0, 30.0, 25.0)                   # the hero (and the camera) near the shore: the extras of a blast are drawn within 140 m of the camera
		TestMode.god = true
		await A.frames(3)
		var scorch0 := FX.marks.live_of(BlastMarks.K_SCORCH) if FX.marks != null else 0
		BlastFx.play(BlastTable.entry(&"la_rocket"), at, 5.0, {"quiet": true})
		var spray := 0
		for i in BlastFx.CLOUD_TOTAL:
			if fx._c_alive[i] != 0 and int(fx._c_kind[i]) == BlastFx.K_SPRAY:
				spray += 1
		var scorch1 := FX.marks.live_of(BlastMarks.K_SCORCH) if FX.marks != null else 0
		TestLib.check(BlastFx.last_ground == &"water" and spray >= 3 and scorch1 == scorch0, "a rocket on the water is a splash column (%d spray puffs, ground %s) with no scorch on the water (%d -> %d)" % [spray, BlastFx.last_ground, scorch0, scorch1])
	# 5 an energy blast keeps its own clean look
	_clear()
	BlastTable.apply(&"la_plasma", street, _p, {})
	await A.frames(1)
	var s3: Variant = _latest_slot()
	TestLib.check(s3 != null and float(s3.fire_mat.get_shader_parameter(&"soot")) == 0.0, "a plasma blast is clean light, no soot")
	# 6 four blasts at once on LOW stay inside the pools of the tier
	var q0 := Game.quality
	Game.quality = 0
	_clear()
	for i in 4:
		BlastTable.apply(&"la_rocket", street + Vector3(float(i) * 3.0, 0.0, 0.0), _p, {})
	await A.frames(2)
	var pool: Node = FX.explosions
	var act := int(pool.call(&"active_count"))
	TestLib.check(fx.cloud_live() <= BlastFx.cloud_cap(0) and act <= int(pool.get_script().slot_limit(0)), "four rockets on LOW: %d cloud puffs (cap %d), %d pooled blasts (limit %d)" % [fx.cloud_live(), BlastFx.cloud_cap(0), act, int(pool.get_script().slot_limit(0))])
	Game.quality = q0
	_clear()
	TestMode.god = false
	await A.shutdown()


func _clear() -> void:
	BlastFx.shared().reset()
	if FX.explosions != null:
		FX.explosions.call(&"clear")
	BlastFx.last_layers.clear()


func _latest_slot() -> Variant:
	var pool: Node = FX.explosions
	if pool == null:
		return null
	var best: Variant = null
	for s: Variant in pool.get(&"slots"):
		if s.active and (best == null or s.serial > best.serial):
			best = s
	return best


func _dark_smoke(fx: BlastFx) -> int:
	var n := 0
	for i in BlastFx.CLOUD_TOTAL:
		if fx._c_alive[i] != 0 and int(fx._c_kind[i]) == BlastFx.K_SMOKE:
			var c: Color = fx._c_col[i]
			if c.get_luminance() < 0.25 and c.a > 0.3:
				n += 1
	return n


func _centre_of(fx: BlastFx, ids: Array[int]) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for i in ids:
		if fx._c_alive[i] != 0:
			sum += fx._c_pos[i]
			n += 1
	return sum / float(n) if n > 0 else Vector3.INF


func _find(cond: Callable) -> Vector3:
	for ring in range(1, 40):
		var r := float(ring) * 150.0
		for k in 24:
			var a := TAU * float(k) / 24.0
			var x := cos(a) * r
			var z := sin(a) * r
			if cond.call(x, z):
				return Vector3(x, TerrainHeight.height_at(x, z), z)
	return Vector3.INF
