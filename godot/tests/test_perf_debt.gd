extends RefCounted
## Perf debt census caps (headless, real main scene): the draw families that were cut to bring the MED / HIGH death spike and the staged view back under budget stay cut.
##   * the LOW death budget is back at 115 and every tier keeps its tight ceilings
##   * FX burst emitters: only TIER_PARTICLES[tier] of the 24 pooled emitters ever rotate (each live emitter is a draw call)
##   * mission core markers (ring + beacon column) carry a distance range per tier, so far cores cost no draw
## The real draw numbers come from tools/perf_report.sh (PERF_CHECK=1, PERF_SEED=n); a dummy renderer cannot count them. Run: tools/test.sh tests/test_perf_debt.gd

var host: Node
var main: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	_budgets()
	await _bursts()
	_core_ranges()
	_pickup_caps()


func _budgets() -> void:
	TestLib.check(int(PerfProbe.BUDGETS[0]["death_draws"]) <= 115, "LOW death spike ceiling is 115 (%d)" % int(PerfProbe.BUDGETS[0]["death_draws"]))
	TestLib.check(int(PerfProbe.BUDGETS[1]["death_draws"]) <= 150 and int(PerfProbe.BUDGETS[1]["draws"]) <= 140, "MED ceilings are 140 / 150")
	TestLib.check(int(PerfProbe.BUDGETS[2]["death_draws"]) <= 170 and int(PerfProbe.BUDGETS[2]["draws"]) <= 160, "HIGH ceilings are 160 / 170")
	TestLib.check(float(PerfProbe.TEX_MB_MAX[0]) <= 200.0 and float(PerfProbe.TEX_MB_MAX[1]) <= 260.0 and float(PerfProbe.TEX_MB_MAX[2]) <= 360.0, "texture memory limits untouched")


func _bursts() -> void:
	var t: Array = FX.TIER_PARTICLES
	TestLib.check(t.size() == 3 and int(t[0]) <= int(t[1]) and int(t[1]) <= int(t[2]) and int(t[2]) <= FX.PARTICLE_POOL, "burst emitters in rotation grow with the tier and fit the pool (%s)" % str(t))
	TestLib.check(int(t[1]) <= 6 and int(t[2]) <= 9, "MED / HIGH rotate at most 6 / 9 burst emitters (%s)" % str(t))
	var prev := Game.quality
	for tier in 3:
		Game.quality = tier
		FX.reset()
		for k in 40:
			FX.burst(Vector3(float(k), 1.0, 0.0), Color(1.0, 0.5, 0.1), 12, 6.0, 5.0)
		var live := 0
		for n in FX.get_children():
			if n is CPUParticles3D and (n as CPUParticles3D).visible:
				live += 1
		TestLib.check(live <= int(t[tier]), "tier %d: at most %d burst emitters live after 40 bursts (%d)" % [tier, int(t[tier]), live])
	FX.reset()
	Game.quality = prev


func _core_ranges() -> void:
	var m := Game.missions as Missions
	TestLib.check(m != null, "the missions module runs in the real scene")
	if m == null:
		return
	m.new_round(6)
	var prev := Game.quality
	for tier in 3:
		Game.quality = tier
		Game.quality_changed.emit(tier)
		var want := float(Missions.CORE_BEAM_RANGE[tier])
		var ok := not m.cores.is_empty()
		for c: Dictionary in m.cores:
			ok = ok and is_equal_approx((c.ring as GeometryInstance3D).visibility_range_end, Missions.CORE_RING_RANGE) and is_equal_approx((c.beam as GeometryInstance3D).visibility_range_end, want)
		TestLib.check(ok, "tier %d: core rings end at %.0f m, beacon columns at %.0f m (0 = unlimited)" % [tier, Missions.CORE_RING_RANGE, want])
	TestLib.check(float(Missions.CORE_BEAM_RANGE[2]) == 0.0 or float(Missions.CORE_BEAM_RANGE[2]) >= float(Missions.CORE_BEAM_RANGE[1]), "HIGH sees beacons at least as far as MED")
	Game.quality = prev
	Game.quality_changed.emit(prev)


func _pickup_caps() -> void:
	var m := Game.missions as Missions
	if m == null:
		return
	var prev := Game.quality
	for tier in 3:
		Game.quality = tier
		m.clear_pickups()
		for k in 6:
			m.drop(&"health", Game.SPAWN + Vector3(3.0 * k, 0.0, 4.0))
		var halos := 0
		var columns := 0
		for o: Dictionary in m.pickups:
			halos += 1 if (o.halo as MeshInstance3D).visible else 0
			columns += 1 if (o.column as MeshInstance3D).visible else 0
		TestLib.check(halos <= int(Missions.HALO_CAP[tier]) and columns <= int(Missions.COLUMN_CAP[tier]), "tier %d: at most %d halos / %d columns of 6 drops (%d / %d)" % [tier, Missions.HALO_CAP[tier], Missions.COLUMN_CAP[tier], halos, columns])
	Game.quality = prev
