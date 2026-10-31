extends RefCounted
## VFX: explosion pool sizes, tier scaling, no node growth, everything ends by itself, API compatibility, tracers and muzzle flashes, impact surfaces.
## Run: tools/test.sh tests/test_vfx.gd

const Pool := preload("res://scripts/fx/explosion_pool.gd")


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


func _visible_nodes(n: Node, out: Array) -> void:
	if n is Node3D and (n as Node3D).visible and (n is GeometryInstance3D or n is Light3D):
		out.append(n)
	for ch in n.get_children():
		_visible_nodes(ch, out)


## Run the pool's clock without waiting: `seconds` of game time in steps of 0.1.
func _advance(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		FX._process(0.1)
		FX.explosions._process(0.1)


func run(host: Node) -> void:
	var pool: Node3D = FX.explosions
	# --- pool layout
	TestLib.check(pool != null and pool.slots.size() == Pool.SLOTS, "the explosion pool has %d slots" % Pool.SLOTS)
	var lights := 0
	var all := []
	_visible_nodes(FX, all)
	for n in all:
		lights += 1 if n is Light3D else 0
	var omni := 0
	var stack: Array[Node] = [FX]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		omni += 1 if n is OmniLight3D else 0
		stack.append_array(n.get_children())
	TestLib.check(omni == 1, "exactly one pooled OmniLight3D serves all explosions (%d)" % omni)
	TestLib.check(all.is_empty(), "idle: no effect node is visible, so the pool costs no draw call (%d visible)" % all.size())
	var emitters := 0
	for c in FX.get_children():
		emitters += 1 if c is CPUParticles3D else 0
	TestLib.check(emitters == FX.PARTICLE_POOL, "the FX burst pool still has %d emitters (%d)" % [FX.PARTICLE_POOL, emitters])
	TestLib.check(Pool.slot_limit(0) < Pool.slot_limit(1) and Pool.slot_limit(1) <= Pool.slot_limit(2) and Pool.slot_limit(2) <= Pool.SLOTS, "slot limit grows with the tier")
	TestLib.check(Pool.puff_count(0) < Pool.puff_count(1) and Pool.puff_count(1) < Pool.puff_count(2), "smoke puffs per blast grow with the tier")
	TestLib.check(Pool.tier_scale(0) < Pool.tier_scale(1) and Pool.tier_scale(1) < Pool.tier_scale(2), "particle scale grows with the tier")

	# --- tier scaling in practice
	var old_q := Game.quality
	for q in 3:
		Game.quality = q
		pool.clear()
		for i in 8:
			FX.blast(Vector3(i * 3.0, 1.0, 0.0), 8.0, Color(1.0, 0.5, 0.2), 0.5, 0)
		TestLib.check(pool.active_count() <= Pool.slot_limit(q), "tier %d: at most %d explosions at once (%d)" % [q, Pool.slot_limit(q), pool.active_count()])
		TestLib.check(pool.light.visible == (q > 0), "tier %d: the light pulse is %s" % [q, "on" if q > 0 else "off (LOW)"])
		_advance(0.3)
		var puffs := 0
		for s in pool.slots:
			if s.active:
				for p in s.puffs:
					puffs += 1 if p.visible else 0
		TestLib.check(puffs <= pool.active_count() * Pool.puff_count(q), "tier %d: smoke puffs capped (%d)" % [q, puffs])
	Game.quality = old_q
	pool.clear()

	# --- every effect ends by itself, also a burning wreck and a quantum collapse
	FX.blast(Vector3(5.0, 1.0, 0.0), 9.0)                                   # radius 9, orange: a car wreck, burns 6 s
	var wreck: Object = null
	for s in pool.slots:
		if s.active:
			wreck = s
	TestLib.check(wreck != null and wreck.style == Pool.STYLE_WRECK and wreck.burn > 0.0, "a radius-9 orange blast is a burning wreck")
	var total_wreck: float = wreck.total if wreck != null else 0.0
	FX.blast(Vector3(-5.0, 1.0, 0.0), 9.0, Color(0.4, 1.0, 0.93))
	var quantum: Object = null
	for s in pool.slots:
		if s.active and s.style == Pool.STYLE_QUANTUM:
			quantum = s
	TestLib.check(quantum != null and quantum.n_puffs == 0, "a cyan blast is the quantum collapse: ripple ring, no smoke")
	TestLib.check(quantum != null and total_wreck > quantum.total, "a wreck burns longer than a collapse lasts (%.1f > %.1f s)" % [total_wreck, quantum.total if quantum else 0.0])
	_advance(10.0)
	all.clear()
	_visible_nodes(FX, all)
	TestLib.check(pool.active_count() == 0 and all.is_empty(), "10 s later nothing is left on screen (%d visible)" % all.size())
	TestLib.check(not pool.light.visible, "...and the light is off")
	TestLib.check(pool._heat_value.w == 0.0, "...and the heat haze is off")

	# --- a street blast (the review bot saw none): fireball first, smoke still hanging 1.2 s later, everything over by itself; the collapse has a magenta ripple
	Game.quality = 1
	FX.reset()
	Game.explode(Vector3(0.0, 1.0, 0.0), 6.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	var blast: Object = null
	for s in pool.slots:
		if s.active:
			blast = s
	TestLib.check(blast != null and blast.fire.visible and blast.ground.visible, "a street blast shows its fireball and ground ring at once")
	_advance(0.3)
	TestLib.check(blast.fire.visible and blast.sparks.visible and blast.debris.visible, "0.3 s: fireball, sparks and debris")
	_advance(0.9)
	var smoke := 0
	for p in blast.puffs:
		smoke += 1 if p.visible else 0
	TestLib.check(smoke >= 1 and blast.total >= 2.5, "1.2 s: smoke still hangs over the street (%d puffs, lasts %.1f s)" % [smoke, blast.total])
	FX.reset()
	TestLib.check(FX.MUZZLE_POOL >= 10 and FX.TRACER_LIFE >= 0.12, "tracers last long enough to see (%.2f s) and the flash pool covers shots plus impacts" % FX.TRACER_LIFE)
	# --- no node growth after 200 explosions
	var before := _count_nodes(FX)
	for i in 200:
		Game.explode(Vector3(randf_range(-20.0, 20.0), 1.0, randf_range(-20.0, 20.0)), randf_range(2.0, 10.0), {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
		FX.tracer(Vector3.ZERO, Vector3(0.0, 0.0, -20.0))
		if i % 10 == 0:
			_advance(0.3)
			await host.get_tree().process_frame
	_advance(6.0)
	TestLib.check(_count_nodes(FX) == before, "no node growth after 200 explosions (%d -> %d nodes)" % [before, _count_nodes(FX)])
	TestLib.check(FX.shake_amount <= 1.0, "shake stays within 0..1")
	_advance(3.0)
	all.clear()
	_visible_nodes(FX, all)
	TestLib.check(all.is_empty(), "after the spam everything is hidden again (%d visible)" % all.size())

	# --- API compatibility: the old calls still work
	FX.blast(Vector3.ZERO, 3.0)
	FX.blast(Vector3.ZERO, 3.0, Color.RED, 0.4)
	FX.burst(Vector3.ZERO, Color.CYAN)
	FX.burst(Vector3.ZERO, Color.CYAN, 12, 5.0, 0.4, 3.0, 2.0)
	FX.tracer(Vector3.ZERO, Vector3(0.0, 0.0, -5.0))
	FX.tracer(Vector3.ZERO, Vector3(0.0, 0.0, -5.0), Color.RED)
	FX.shake(0.3)
	var beam := FX.make_beam(Color.CYAN, 0.1)
	FX.place_beam(beam, Vector3.ZERO, Vector3(0.0, 0.0, -3.0))
	TestLib.check(beam.visible, "make_beam / place_beam are unchanged")
	beam.free()
	Game.explode(Vector3(0.0, 1.0, -30.0), 4.5, {"enemy_dmg": 0.0, "car_dmg": 30.0, "player_dmg": 0.0, "color": Color(1.0, 0.24, 0.37)})
	Game.explode(Vector3(0.0, 1.0, -40.0), 5.0)
	TestLib.check(pool.active_count() >= 1, "Game.explode keeps its signature (radius, opts dictionary) and draws a blast")
	pool.clear()

	# --- tracers and muzzle flashes
	var flashes := 0
	for i in FX.MUZZLE_POOL * 3:
		FX.tracer(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, -30.0))
	for m in FX._muzzles:
		flashes += 1 if m.visible else 0
	TestLib.check(flashes > 0 and flashes <= FX.MUZZLE_POOL, "a shot draws a pooled muzzle flash (%d of %d)" % [flashes, FX.MUZZLE_POOL])
	TestLib.check((FX._tracers[0].material_override as ShaderMaterial).shader == FX.TRACER_SHADER, "tracers use the bright-head shader")
	FX._process(0.2)
	flashes = 0
	for m in FX._muzzles:
		flashes += 1 if m.visible else 0
	var beams := 0
	for t in FX._tracers:
		beams += 1 if t.visible else 0
	TestLib.check(flashes == 0 and beams == 0, "muzzle flashes and tracers expire after a fraction of a second")

	# --- impact surfaces
	TestLib.check(ImpactSparks.surface_at(Vector3(3.0, 0.0, 0.0), Vector3.UP) == &"asphalt", "a hit on the street is wet asphalt")
	TestLib.check(ImpactSparks.surface_at(Vector3(3.0, 12.0, 0.0), Vector3.RIGHT) == &"concrete", "a hit high on a wall is concrete")
	TestLib.check(ImpactSparks.surface_at(Vector3(3.0, 20.0, 0.0), Vector3.UP) == &"concrete", "a hit on a roof is concrete")
	var glass := 0
	for i in 40:
		glass += 1 if ImpactSparks.surface_at(Vector3(0.0, 1.5, 1.3 + i * 2.6), Vector3.RIGHT) == &"glass" else 0
	TestLib.check(glass > 10 and glass < 35, "shopfront bays along a wall are a mix of glass and concrete (%d of 40 glass)" % glass)
	var sparks := ImpactSparks.new()
	host.add_child(sparks)
	await host.get_tree().process_frame
	for kind in [&"asphalt", &"glass", &"concrete", &"metal"]:
		sparks.impact_world(Vector3.ZERO, Vector3.UP, kind)
		TestLib.check(sparks.active_count() > 0, "impact_world(%s) launches pooled emitters" % kind)
		for i in 20:
			sparks._process(0.1)
		TestLib.check(sparks.active_count() == 0, "...and %s emitters hide again" % kind)
	var n0 := _count_nodes(sparks)
	for i in 300:
		sparks.impact_world(Vector3(i * 0.1, 1.0, 0.0), Vector3.UP)
		sparks.impact_world(Vector3(i * 0.1, 1.5, 0.0), Vector3.RIGHT)
	TestLib.check(_count_nodes(sparks) == n0, "600 impacts create no nodes")
	sparks.queue_free()
	FX.reset()
