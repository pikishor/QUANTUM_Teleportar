class_name SnakeWarm
extends RefCounted
## PRE-WARM of the QUANTUM SNAKE visuals (wave 115 PLAY critic). ShaderWarmup.run (behind the loading overlay) shows every hidden mesh of the player for a few frames, but the snake systems keep NOTHING hidden to
## show: the tendril pool and the swarm draw a MultiMesh whose visible_instance_count is 0 until the first snake, the speed lines and the anchor marker are made on first need, and the aim ring, the dots, the lock
## bracket and the blast wall of an armed power are made on first arming. So the first swing, the first armed verb and the first bomb compiled their pipelines on the spot: measured with tests/bot_w115p_firstuse.gd
## (RenderingServer pipeline compilations, the deterministic form of a hitch, WARM=1): tendril 3, swarm 2, speed lines 1, armed verb 5, armed bomb 4 = 15 pipelines (a phone's driver stalls 10 to 50 ms for each
## one, in the middle of the first thing the owner tries). `begin(at)` makes each of them exist and draw once at the warm point, `end()` puts everything back (no state change: no tendril, no snake, no armed power,
## no canvas layer or marker left: the idle hero carries what it carried before, the perf gate counts the same draws). Called by ShaderWarmup.run.

static var _tendrils: Array[SnakeTendril] = []
static var _active := false


## Everything the first snake draws, at `at` (in front of the camera, behind the overlay). Returns the number of things shown.
static func begin(at: Vector3) -> int:
	_active = false
	var p := Game.player as Player
	if not is_instance_valid(p) or p.snake == null or not p.is_inside_tree():
		return 0
	_active = true
	var n := 0
	# 1 two tendrils (a taut one with a head, a slack one without): the pool, its MultiMesh and its pipeline
	for k in 2:
		var t := SnakeTendril.fire(at + Vector3(-1.2, 0.1, 0.0), at + Vector3(1.2 + 0.3 * float(k), 1.4 + float(k), -0.5), {"travel": 0.02, "host": p, "life": 0.0, "head": k == 0, "tension": 0.9 - 0.5 * float(k)})
		t.user["keep"] = true
		_tendrils.append(t)
		n += 1
	# 2 free snakes: the swarm's MultiMesh with each shape it draws
	var sw := SnakeSwarm.get_swarm(p)
	if sw != null:
		sw.spawn(&"ball", at + Vector3(0.0, 0.5, -0.8), {"radius": 0.35, "len": 2.2, "life": 30.0})
		sw.spawn(&"coil", at + Vector3(0.6, 0.0, -0.8), {"radius": 0.6, "len": 5.0, "y0": 0.1, "y1": 1.8, "turns": 2.0, "life": 30.0})
		sw.spawn(&"ring", at + Vector3(-0.6, 0.1, -0.8), {"radius": 0.8, "len": 6.0, "life": 30.0})
		n += 3
	# 3 the speed lines and the anchor marker (made lazily in play: an idle hero carries neither)
	var fx := p.get_node_or_null("SnakeFx") as SnakeFx
	if fx != null:
		fx.warm_begin(at)
		n += 2
	# 4 the aim preview of an armed verb (a ring on the ground and the lock bracket) and of an armed bomb (the arc dots and the blast wall and label)
	var war := SnakeWar.of(p)
	if war != null and p.weapon != null:
		var armed0 := war.armed
		for id: StringName in [&"sv_net", &"sb_coil"]:
			if SnakeRows.has(id):
				SnakeRows.ensure()
				war.armed = id
				war._update_preview(0.0, at + Vector3(0.0, 0.0, -2.0))
				n += 1
		war.armed = armed0
	return n


## The warm-up is over: no tendril, no snake, no layer, no marker, no preview is left.
static func end() -> void:
	if not _active:
		return
	_active = false
	for t in _tendrils:
		if t != null:
			t.kill()
	_tendrils.clear()
	var p := Game.player as Player
	if not is_instance_valid(p):
		return
	if SnakeTendrilPool.current != null:
		SnakeTendrilPool.current.clear()
	if SnakeSwarm.current != null:
		SnakeSwarm.current.clear()
	var fx := p.get_node_or_null("SnakeFx") as SnakeFx
	if fx != null:
		fx.warm_end()
	var war := SnakeWar.instance
	if is_instance_valid(war):
		war._hide_preview()
