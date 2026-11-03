extends RefCounted
## Performance pass test (headless): per-tier budgets are monotonic and tight, the pooled explosion slots are reused (no node growth, never above the tier limit),
## the AI thinker cap per physics frame holds. Run: tools/test.sh tests/test_perf_pass.gd


func run(host: Node) -> void:
	for t in 2:
		var a: Dictionary = PerfProbe.BUDGETS[t]
		var b: Dictionary = PerfProbe.BUDGETS[t + 1]
		TestLib.check(int(a["draws"]) <= int(b["draws"]) and int(a["prims"]) <= int(b["prims"]) and int(a["death_draws"]) <= int(b["death_draws"]), "budgets grow with the tier (%d -> %d)" % [t, t + 1])
	TestLib.check(int(PerfProbe.BUDGETS[2]["draws"]) <= 160 and int(PerfProbe.BUDGETS[0]["draws"]) <= 100, "draw budgets stay tight")
	TestLib.check(EnemyManager.THINKERS[0] <= EnemyManager.THINKERS[1] and EnemyManager.THINKERS[1] <= EnemyManager.THINKERS[2], "AI thinkers are capped by tier")
	var prev := Game.quality
	var pool: Node3D = FX.explosions
	TestLib.check(pool != null, "the explosion pool exists")
	if pool == null:
		return
	for tier in 3:
		Game.quality = tier
		pool.clear()
		var nodes := host.get_tree().get_node_count()
		var limit: int = FX.ExplosionPool.slot_limit(tier)
		var peak := 0
		for k in 12:
			pool.play(Vector3(float(k), 0.0, 0.0), 6.0, Color(1.0, 0.5, 0.1))
			peak = maxi(peak, pool.active_count())
		TestLib.check(peak <= limit, "tier %d: explosions never exceed %d slots (peak %d)" % [tier, limit, peak])
		TestLib.check(host.get_tree().get_node_count() == nodes, "tier %d: playing explosions creates no nodes" % tier)
		pool.clear()
		TestLib.check(pool.active_count() == 0, "tier %d: clear frees every slot for reuse" % tier)
		pool.play(Vector3.ZERO, 6.0, Color(1.0, 0.5, 0.1))
		TestLib.check(pool.active_count() == 1, "tier %d: a freed slot is reused" % tier)
	pool.clear()
	Game.quality = prev
