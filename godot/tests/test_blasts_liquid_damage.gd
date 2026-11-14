extends RefCounted
## Explosions, liquid and damage (owner: more colour in blasts, liquid on the streets, more damage) in the REAL game scene:
##   * the five elements (fire, plasma, quantum, toxic, electric): colour -> element, every blast gets its element palette, spark and debris ramps;
##   * BlastMarks: coloured fluid, scorch, cracks, puddle ripples on the street and the walls, ONE pooled draw, ring caps per tier, no node growth, lifetime 30-90 s, rebase of the clock;
##   * falling glass and chunks of a hit facade; enemy death splat; a hurt car: wheel flies off, torn panels, oil trail, wreck sends wheels and panels flying; repair / respawn restores;
##   * shake and slow motion on a big blast (and not with Reduce motion); Reduce flash dims the light, the core and the fresh fluid;
##   * everything ends by itself and FX.reset() clears it.
## Waits on game time advanced by hand (the layers' own `_process`), never on frame counts. Run: tools/test.sh tests/test_blasts_liquid_damage.gd

var host: Node
var mgr: VehicleManager
var floor_body: StaticBody3D
var wall_body: StaticBody3D
const ORIGIN := Vector3(-700.0, 0.0, 400.0)


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	host.add_child(b)
	b.global_position = pos
	return b


## Game time without waiting: the layers' own clocks in steps of 0.1 s.
func _advance(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		FX._process(0.1)
		FX.explosions._process(0.1)
		FX.qvfx._process(0.1)
		if FX.marks.is_processing():
			FX.marks._process(0.1)
		if FX.car_debris.is_processing():
			FX.car_debris._process(0.1)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	mgr = Game.vehicles as VehicleManager
	var old_q := Game.quality
	var old_rf := UiSettings.s_reduce_flash
	var old_rm := UiSettings.s_reduce_motion
	UiSettings.s_reduce_flash = false
	UiSettings.s_reduce_motion = false
	TestLib.check(mgr != null and FX.marks != null and FX.car_debris != null, "the real scene has the vehicle manager and FX owns the marks and the car debris")
	if mgr == null or FX.marks == null:
		return
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	floor_body = _box(ORIGIN + Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	wall_body = _box(ORIGIN + Vector3(9.0, 4.0, 0.0), Vector3(1.0, 8.0, 30.0))      # a facade east of the blast point; its west face is at x = 8.5
	await TestLib.frames(host, 3)
	FX.reset()

	_elements()
	_idle_cost()
	_blasts_leave_marks()
	_wall_damage()
	_caps_and_lifetime()
	_reduce_settings()
	_slowmo()
	await _enemy_death()
	await _car_damage()
	FX.reset()
	TestLib.check(FX.marks.live_count() == 0 and FX.car_debris.draws() == 0 and not FX.marks.visible_draw(), "FX.reset() clears the marks and the car parts")
	Game.quality = old_q
	UiSettings.s_reduce_flash = old_rf
	UiSettings.s_reduce_motion = old_rm
	floor_body.queue_free()
	wall_body.queue_free()


func _elements() -> void:
	TestLib.check(BlastElements.of_color(Color(1.0, 0.54, 0.19)) == BlastElements.FIRE, "orange is fire")
	TestLib.check(BlastElements.of_color(Color(0.4, 1.0, 0.93)) == BlastElements.PLASMA, "cyan is plasma")
	TestLib.check(BlastElements.of_color(Color(0.72, 0.3, 1.0)) == BlastElements.QUANTUM and BlastElements.of_color(Color(1.0, 0.15, 0.85)) == BlastElements.QUANTUM, "violet and magenta are quantum")
	TestLib.check(BlastElements.of_color(Color(0.5, 1.0, 0.3)) == BlastElements.TOXIC, "green is toxic")
	TestLib.check(BlastElements.of_color(Color(0.6, 0.65, 1.0)) == BlastElements.ELECTRIC, "blue is electric")
	var colors := {}
	for el in BlastElements.ALL:
		TestLib.check(BlastElements.valid(el) and BlastElements.spark_ramp(el).get_point_count() >= 3 and BlastElements.chunk_ramp(el).get_point_count() >= 3, "%s has a palette with spark and debris ramps" % el)
		colors[BlastElements.color(el, "mid").to_html()] = true
	TestLib.check(colors.size() == 5, "five different fireball colours")
	TestLib.check(BlastElements.spark_ramp(BlastElements.TOXIC) == BlastElements.spark_ramp(BlastElements.TOXIC), "ramps are built once and cached")


func _idle_cost() -> void:
	TestLib.check(not FX.marks.visible_draw() and FX.marks.shower_live() == 0 and FX.car_debris.draws() == 0, "idle: no mark, no debris, no draw call")


func _active_slot() -> Object:
	for s in FX.explosions.slots:
		if s.active:
			return s
	return null


func _blasts_leave_marks() -> void:
	Game.quality = 1
	var seen_colors := {}
	for el in BlastElements.ALL:
		FX.reset()
		var before := FX.marks.total_added
		Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": el, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
		var s := _active_slot()
		TestLib.check(s != null and s.elem == el, "%s: the blast plays with its element palette" % el)
		TestLib.check(FX.marks.total_added - before >= 3, "%s: the blast leaves marks on the street (%d)" % [el, FX.marks.total_added - before])
		TestLib.check(FX.marks.visible_draw(), "%s: the marks are one visible draw" % el)
		if s != null:
			seen_colors[s.fire_mat.get_shader_parameter(&"c_mid").to_html()] = true
	TestLib.check(seen_colors.size() == 5, "the five elements show five fireball colours (%d)" % seen_colors.size())
	# the colour of an old call site picks the element
	FX.reset()
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 4.0, {"color": Color(0.5, 1.0, 0.3), "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	var s2 := _active_slot()
	TestLib.check(s2 != null and s2.elem == BlastElements.TOXIC, "a green colour passed to Game.explode is a toxic blast")
	# fire leaves soot, the liquid elements leave a pool
	FX.reset()
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": BlastElements.FIRE, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.marks.live_of(BlastMarks.K_SCORCH) >= 1 and FX.marks.live_of(BlastMarks.K_OIL) >= 1, "a fire blast leaves scorch and an oil puddle")
	FX.reset()
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": BlastElements.PLASMA, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.marks.live_of(BlastMarks.K_SPLAT) >= 2, "a plasma blast leaves glowing fluid (%d splats)" % FX.marks.live_of(BlastMarks.K_SPLAT))
	# puddle ripples
	FX.reset()
	FX.marks.ripple(ORIGIN, 0.9)
	TestLib.check(FX.marks.live_of(BlastMarks.K_RIPPLE) == 1, "a puddle ripple")
	_advance(1.2)
	TestLib.check(FX.marks.live_of(BlastMarks.K_RIPPLE) == 0, "...it rings out within a second")


func _wall_damage() -> void:
	Game.quality = 1
	FX.reset()
	var n0 := _count_nodes(FX)
	Game.explode(ORIGIN + Vector3(3.0, 1.0, 0.0), 6.0, {"element": BlastElements.TOXIC, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	# the rays start at random angles: fire a few blasts so one reaches the wall for sure (the wall is 5.5 m away, reach 10.4 m)
	for i in 6:
		Game.explode(ORIGIN + Vector3(3.0, 1.0, float(i) - 3.0), 6.0, {"element": BlastElements.TOXIC, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.marks.live_of(BlastMarks.K_CRACK) >= 1, "a blast next to a facade cracks and pocks it (%d)" % FX.marks.live_of(BlastMarks.K_CRACK))
	TestLib.check(FX.marks.live_of(BlastMarks.K_WALL) >= 1, "...and splashes fluid that runs down it (%d)" % FX.marks.live_of(BlastMarks.K_WALL))
	TestLib.check(FX.marks.shower_live() >= 1, "...glass and chunks fall (%d emitters)" % FX.marks.shower_live())
	TestLib.check(_count_nodes(FX) == n0, "no node was created by seven blasts (%d -> %d)" % [n0, _count_nodes(FX)])
	_advance(3.0)
	TestLib.check(FX.marks.shower_live() == 0, "falling glass and chunks end by themselves")
	# LOW: chunks only, no glass
	Game.quality = 0
	FX.marks.facade_shower(ORIGIN + Vector3(8.5, 2.0, 0.0), Vector3(-1.0, 0.0, 0.0), 1.0)
	TestLib.check(FX.marks.chunks.visible and not FX.marks.shards.visible, "LOW: chunks fall, no glass emitter")
	FX.marks.shards.visible = false
	Game.quality = 1


func _caps_and_lifetime() -> void:
	for q in 3:
		Game.quality = q
		FX.reset()
		var n0 := _count_nodes(FX)
		for i in 160:
			FX.marks.splat(ORIGIN + Vector3(randf_range(-30.0, 30.0), 0.0, randf_range(-30.0, 30.0)), Vector3.UP, 2.0, BlastElements.ALL[i % 5])
			FX.marks.ripple(ORIGIN + Vector3(randf_range(-5.0, 5.0), 0.0, 0.0), 0.8)
		TestLib.check(FX.marks.live_count() - FX.marks.struct_live() <= BlastMarks.cap_long(q) + BlastMarks.cap_ripples(q), "tier %d: at most %d long marks and %d ripples (%d; the structure pool of wave 113 has its own cap, tests/test_damage_everywhere.gd)" % [q, BlastMarks.cap_long(q), BlastMarks.cap_ripples(q), FX.marks.live_count() - FX.marks.struct_live()])
		TestLib.check(_count_nodes(FX) == n0, "tier %d: 320 marks created no node" % q)
	TestLib.check(BlastMarks.cap_long(0) < BlastMarks.cap_long(1) and BlastMarks.cap_long(1) < BlastMarks.cap_long(2), "the ring cap grows with the tier")
	Game.quality = 1
	FX.reset()
	FX.marks.splat(ORIGIN, Vector3.UP, 3.0, BlastElements.TOXIC, 50.0)
	FX.marks.scorch(ORIGIN, Vector3.UP, 3.0, Color(1.0, 0.5, 0.2), 60.0)
	var c0 := FX.marks.clock()
	_advance(44.0)                                                      # the shader clock passes REBASE_AT: the marks must survive the rebase
	TestLib.check(FX.marks.clock() < c0 + 44.0 - 1.0 and FX.marks.live_count() == 2, "after the clock was rebased (%.1f -> %.1f) a 50 s splat and a 60 s scorch are still there (%d)" % [c0, FX.marks.clock(), FX.marks.live_count()])
	_advance(8.0)
	TestLib.check(FX.marks.live_count() == 1, "the 50 s splat is gone at 52 s (%d)" % FX.marks.live_count())
	_advance(10.0)
	TestLib.check(FX.marks.live_count() == 0 and not FX.marks.visible_draw(), "the scorch is gone at 62 s and the draw call with it")
	TestLib.check(BlastMarks.LIFE_LIQUID.x >= 30.0 and BlastMarks.LIFE_LIQUID.y <= 60.0, "liquid stays 30-60 s")


func _reduce_settings() -> void:
	Game.quality = 1
	FX.reset()
	UiSettings.s_reduce_flash = false
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": BlastElements.FIRE, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	var peak: float = FX.explosions._light_peak
	var gain: float = _active_slot().fire_mat.get_shader_parameter(&"gain")
	FX.reset()
	UiSettings.s_reduce_flash = true
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": BlastElements.FIRE, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.explosions._light_peak < peak * 0.5, "reduce flash: the light pulse is far dimmer (%.2f < %.2f)" % [FX.explosions._light_peak, peak])
	TestLib.check(float(_active_slot().fire_mat.get_shader_parameter(&"gain")) < gain, "reduce flash: the fireball core is dimmer")
	TestLib.check(float(FX.marks._mat.get_shader_parameter(&"dim")) < 0.5, "reduce flash: fresh fluid glows less")
	FX.reset()
	Game.explode(ORIGIN + Vector3(-20.0, 1.0, 0.0), 6.0, {"element": BlastElements.ELECTRIC, "enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.explosions._heat_value.w == 0.0, "reduce flash: no heat haze")
	UiSettings.s_reduce_flash = false
	FX.reset()


func _slowmo() -> void:
	Game.quality = 1
	var stab := Stability.current
	TestLib.check(stab != null, "the stability watchdog is running")
	if stab == null:
		return
	var base := Engine.time_scale
	Game._slowmo_last = -100.0
	TestLib.check(not Game.blast_feel(3.0, 5.0, true), "a small blast has no slow motion")
	TestLib.check(not Game.blast_feel(9.0, 80.0, true), "a far blast has no slow motion")
	UiSettings.s_reduce_motion = true
	TestLib.check(not Game.blast_feel(9.0, 5.0, true), "Reduce motion: no slow motion")
	UiSettings.s_reduce_motion = false
	FX.shake_amount = 0.0
	Game.explode(ORIGIN + Vector3(0.0, 1.0, 0.0), 8.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.shake_amount > 0.0 or not is_instance_valid(Game.camera), "a big blast shakes the camera")
	Game._slowmo_last = -100.0
	TestLib.check(Game.blast_feel(9.0, 5.0, true) and stab.slowmo_active and Engine.time_scale < base, "a big close blast plays a slow motion")
	TestLib.check(not Game.blast_feel(9.0, 5.0, true), "...never over another one")
	stab.end_slowmo()
	TestLib.check(is_equal_approx(Engine.time_scale, base), "the time scale is restored (%.2f)" % Engine.time_scale)
	UiSettings.s_reduce_motion = true
	FX.shake_amount = 0.0
	Game.explode(ORIGIN + Vector3(0.0, 1.0, 0.0), 8.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(FX.shake_amount == 0.0, "Reduce motion: no shake")
	UiSettings.s_reduce_motion = false
	FX.reset()


func _enemy_death() -> void:
	FX.reset()
	var em := Game.enemies as EnemyManager
	if em == null:
		return
	em.clear()
	var d := em.spawn(&"striker", ORIGIN + Vector3(-25.0, 0.0, 10.0))
	TestLib.check(d != null, "an enemy spawns")
	if d == null:
		return
	await TestLib.frames(host, 2)
	var before := FX.marks.live_of(BlastMarks.K_SPLAT) + FX.marks.live_of(BlastMarks.K_OIL)
	d.die()
	var after := FX.marks.live_of(BlastMarks.K_SPLAT) + FX.marks.live_of(BlastMarks.K_OIL)
	TestLib.check(after > before, "a dying enemy leaves its fluid on the street (%d -> %d)" % [before, after])
	em.clear()
	FX.reset()


func _car_damage() -> void:
	Game.quality = 1
	FX.reset()
	var v := mgr.spawn_parked(&"sedan", ORIGIN + Vector3(-30.0, 0.0, -20.0), 0.0)
	TestLib.check(v != null, "a car spawns")
	if v == null:
		return
	await TestLib.frames(host, 3)
	v._dist = 5.0
	var vis: VehicleVisual = v.visual
	TestLib.check(vis.wheels.size() == 4 and vis.wheels_lost() == 0, "a new car has four wheels")
	v.damage(60.0)
	TestLib.check(FX.car_debris.live_panels() >= 1 and v._panels_torn >= 1, "a big hit tears a panel off (%d)" % FX.car_debris.live_panels())
	for i in 6:
		v.tear_panel_now(Vector3(0.8, 0.6, 0.0), Vector3(1, 0, 0))
	TestLib.check(v._panels_torn <= Vehicle.PANELS_PER_CAR, "at most %d panels per car (%d)" % [Vehicle.PANELS_PER_CAR, v._panels_torn])
	v._hurt(v.max_hp * 0.7)
	TestLib.check(vis.wheels_lost() == 1 and FX.car_debris.live_wheels() == 1, "a badly hurt car loses a wheel")
	var wheel_node := vis.wheels[0]
	TestLib.check(FX.car_debris.draws() >= 1, "flying parts are drawn (%d draws)" % FX.car_debris.draws())
	_advance(6.0)
	var w: CarDebris.Piece = null
	for p in FX.car_debris.wheels:
		if p.age >= 0.0:
			w = p
	TestLib.check(w != null and absf(w.pos.y - w.half) < 0.05, "the wheel has landed on the street and stays above it")
	_advance(30.0)
	TestLib.check(FX.car_debris.live_wheels() == 0 and FX.car_debris.live_panels() == 0 and FX.car_debris.draws() == 0, "parts vanish on their own and the draw calls end")
	# the oil trail
	v._damage_fx(0.1)
	TestLib.check(FX.marks.live_of(BlastMarks.K_OIL) >= 1, "a hurt car leaks oil on the street")
	for i in 40:
		v._leak_t = 0.0
		v._damage_fx(0.1)
	TestLib.check(FX.marks.live_of(BlastMarks.K_OIL) <= 10 + 1, "the oil trail is capped (%d)" % FX.marks.live_of(BlastMarks.K_OIL))
	# repair puts the wheel back
	v.hp = v.max_hp * 0.5
	v.repair()
	TestLib.check(vis.wheels_lost() == 0 and wheel_node.visible, "repair puts the wheel back")
	# the wreck: all four wheels and three panels fly
	FX.reset()
	v.hp = v.max_hp
	v._panels_torn = 0
	v.explode()
	TestLib.check(vis.wheels_lost() == 4, "an exploding car loses all four wheels")
	TestLib.check(FX.car_debris.live_wheels() >= 1 and FX.car_debris.live_panels() >= 1 and FX.car_debris.live_wheels() <= CarDebris.wheel_cap(1), "wheels and panels fly (%d / %d), within the tier cap" % [FX.car_debris.live_wheels(), FX.car_debris.live_panels()])
	TestLib.check(FX.marks.live_of(BlastMarks.K_SCORCH) >= 1, "the wreck scorches the street")
	v.deactivate()
	TestLib.check(vis.wheels_lost() == 0, "a respawned car has its wheels again")
	FX.reset()
