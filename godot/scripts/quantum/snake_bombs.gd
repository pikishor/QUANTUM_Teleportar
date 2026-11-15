class_name SnakeBombs
extends RefCounted
## THE TWELVE SNAKE BOMBS (wave 115, combat side; rows in SnakeRows.BOMBS, one BlastTable entry each in the category `snake`). A bomb is thrown as a curled snake ball (the arc, the bounce, the fuse and the
## blast come from BlastOps like every grenade: the table decides radius, falloff, damage, knockback and status), and when it goes off (BlastOps.detonated) this class adds what makes it a snake bomb:
##   COIL BOMB          coils burst out and WRAP everyone in the radius: held still, crushed for damage per second
##   SWARM BOMB         ten snakes slither out and hunt: each homes on an enemy within 11 m, bites and wraps it
##   FLARE SERPENT      a white-hot serpent: everyone in sight is blinded and MARKED (a diamond over their head for nine seconds, through walls)
##   FREEZING VIPER     the stasis field of the table, ringed by five ice vipers
##   SEEKER SNAKE       guided: a snake that hugs the ground, climbs over low walls and drives straight at the enemy nearest the crosshair
##   CHAIN BOMB         arcs from enemy to enemy, six hops, a bolt between them
##   CLUSTER SNAKE BOMB the main blast and four bomblet snakes that fly out and blow up in a ring
##   CONSTRICTOR MINE   a coil on the ground (a BlastOps mine): springs on the first foot, wraps and crushes everyone near
##   BURROWER           dives into the ground, slithers under the nearest car and blows it sky high
##   GRAVITY SNAKE      the pull of the table with five snakes spiralling into the knot, then the collapse
##   STORM COBRA        a cobra rises from the landing spot, flares its hood and arcs lightning at everyone nearby for three seconds
##   MEGA PYTHON        the hero's ultimate: a giant python rises ahead of him and slams (hero mode, or skill level 15)
## All the damage goes through the hero's multipliers (SnakeWar.dmg_mult) and credit (BlastCredit); statuses ride the table (stun, blind, freeze, shock, pull). Counters (tests wait on these):
## thrown, by_id[id] (bombs that went off), bites, hops, bolts, marks_made, seekers, burrows, knots, bomblets, wraps.

const MARK_TIME := 9.0
const MARK_CAP := 24
const HERO_HAND := 1

var war: SnakeWar
var p: Player
var thrown := 0
var by_id: Dictionary = {}
var bites := 0
var hops := 0
var bolts := 0
var marks_made := 0
var seekers := 0
var burrows := 0
var knots := 0
var bomblets := 0
var wraps := 0
var megas := 0
var last_res: Dictionary = {}                            ## the result of the latest snake blast (BlastTable.last copied right after it: a car that explodes in the chain overwrites the table's own)
var marks: Array[Dictionary] = []
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()
var _rq := PhysicsRayQueryParameters3D.new()
var _links: Array[Dictionary] = []                       ## scheduled bolts and bomblets {t, fn}


func _init(w: SnakeWar = null) -> void:
	war = w
	p = w.p if w != null else null
	_rng.randomize()
	_rq.collision_mask = Game.L_WORLD


func connect_ops() -> void:
	var ops := BlastOps.shared(p.get_tree()) if p != null else null
	if ops != null and not ops.detonated.is_connected(_on_detonated):
		ops.detonated.connect(_on_detonated)


func reset() -> void:
	marks.clear()
	_links.clear()
	_update_marks()


func _swarm() -> SnakeSwarm:
	return war.swarm


func _opts() -> Dictionary:
	return {"by_hero": true, "dmg_mult": war.dmg_mult(), "radius_mult": war.radius_mult()}


func _hurt(en: Node3D, amount: float, marker := true) -> void:
	if not is_instance_valid(en) or bool(en.get(&"dead")):
		return
	en.call(&"damage", amount)
	BlastCredit.dealt(en, amount, Vector3.INF, marker)


func _ground(pos: Vector3) -> Vector3:
	_rq.from = pos + Vector3.UP * 2.0
	_rq.to = pos + Vector3.DOWN * 10.0
	var r := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	return (r["position"] as Vector3) if not r.is_empty() else pos


func _foes_in(pos: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for e: Node3D in Gear.living_enemies(p.get_tree()):
		if e.get(&"friendly") == true:
			continue
		if SnakeAim.center_of(e).distance_to(pos) <= radius or e.global_position.distance_to(pos) <= radius:
			out.append(e)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(pos) < b.global_position.distance_squared_to(pos))
	return out


func _hits_of_last() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var res := BlastTable.last
	if res.is_empty():
		return out
	for k: Variant in (res.get("enemy_hits", {}) as Dictionary):
		var o := instance_from_id(int(k))
		if o is Node3D and is_instance_valid(o) and SnakeAim.is_live_enemy(o):
			out.append(o as Node3D)
	return out


func _after(secs: float, fn: Callable) -> void:
	_links.append({"t": secs, "fn": fn})


# --- the throw -------------------------------------------------------------------------------------------------------------------------

## Casts bomb `id` from the hero's hand along the crosshair. True when it left the hand.
func throw(id: StringName, force := false) -> bool:
	SnakeRows.ensure()
	connect_ops()
	var row := SnakeRows.row(id)
	var reach := float(row["range"])
	var aim_pt := SnakeAim.point(p, reach)
	match id:
		&"sb_seeker":
			war.commit(id, aim_pt)
			return _seeker(aim_pt)
		&"sb_burrow":
			war.commit(id, aim_pt)
			return _burrow(aim_pt)
		&"sb_mega":
			war.commit(id, aim_pt)
			return _mega()
	war.commit(id, aim_pt)
	var ops := BlastOps.shared(p.get_tree())
	if ops == null:
		return false
	var ar := SnakeAim.ray(p)
	var from: Vector3 = p.snake.hand_pos(HERO_HAND)
	var ctx := {"from": from, "aim": aim_pt, "dir": ar[1], "origin": ar[0], "yaw": 0.0, "locked": null, "hit": {}}
	var it: Dictionary
	if id == &"sb_constrict":
		it = ops.place(id, p, ctx)
	else:
		it = ops.spawn_projectile(id, p, ctx)
	if it.is_empty():
		return false
	thrown += 1
	_ball_for(it, id)
	Sfx.play(&"snw_bomb_throw", -3.0)
	UiSettings.buzz(20)
	p.camera_rig.kick(0.02)
	FX.burst(from, SnakeRows.color_of(id), 6, 4.0, 0.3, 1.0, 1.0)
	return true


## The curled snake ball that stands for the BlastOps item: it follows the item until it goes off; the item's own pooled mesh is hidden.
func _ball_for(it: Dictionary, id: StringName) -> void:
	var node: Variant = it.get("node")
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = false
	var sw := _swarm()
	if sw == null:
		return
	var col := SnakeRows.color_of(id)
	var mine := id == &"sb_constrict"
	var b := sw.spawn(&"coil" if mine else &"ball", it["pos"], {"color": col, "thick": 0.07 if not mine else 0.09, "len": 1.6 if not mine else 4.0, "radius": 0.2 if not mine else 0.7, "life": 40.0 if mine else 8.0,
			"prio": 3, "head": 1.0, "rate": 1.4, "y0": 0.04, "y1": 0.28, "turns": 2.2, "spin": 2.0, "anchor_pos": it["pos"],
			"tick": func(b2: SnakeSwarm.Body, _dt: float) -> bool:
				if not bool(it.get("alive", false)):
					return false
				b2.pos = it["pos"]
				if mine:
					b2.anchor_pos = it["pos"]
				return true})
	if b != null:
		b.user["id"] = id


# --- what a detonation adds ---------------------------------------------------------------------------------------------------------------

func _on_detonated(id: StringName, pos: Vector3) -> void:
	if not String(id).begins_with("sb_"):
		return
	by_id[id] = int(by_id.get(id, 0)) + 1
	if StringName(BlastTable.last.get("id", &"")) == id:                  # a car that blows up in the chain would have overwritten the table's own `last`
		last_res = BlastTable.last.duplicate()
	war.react.on_blast(id, pos, float(BlastTable.entry(id).get("radius", 5.0)) * war.radius_mult())
	match id:
		&"sb_coil", &"sb_constrict": _wrap_blast(id, pos)
		&"sb_swarm": _swarm_burst(id, pos)
		&"sb_flare": _flare(id, pos)
		&"sb_freeze": _freeze(id, pos)
		&"sb_chain": _chain(id, pos)
		&"sb_cluster": _cluster(id, pos)
		&"sb_gravity": _gravity(id, pos)
		&"sb_storm": _storm(id, pos)


func _burst_snakes(pos: Vector3, color: Color, n: int, reach: float, life := 0.7) -> void:
	var sw := _swarm()
	if sw == null:
		return
	var count := mini(n, 4 if Game.quality == 0 else n)
	for k in count:
		var a := TAU * float(k) / float(count) + _rng.randf() * 0.5
		var dir := Vector3(cos(a), 0.0, sin(a))
		var start := _ground(pos + dir * 0.3) + Vector3(0.0, 0.1, 0.0)
		sw.spawn(&"crawl", start, {"color": color, "thick": 0.15, "len": 3.0, "life": life, "prio": 1, "heading": dir, "head": 1.0, "amp": 0.25, "lift": 0.35,
			"tick": func(b: SnakeSwarm.Body, dt: float) -> bool:
				b.pos += b.heading * (reach / life) * dt * clampf(1.2 - b.age / life, 0.2, 1.2)
				return true})
	sw.spawn(&"ring", pos, {"radius": reach, "thick": 0.06, "len": reach * 4.0, "color": color, "life": life + 0.15, "rise_t": 0.2, "prio": 1, "spin": 3.0})


func _wrap_blast(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	var color := SnakeRows.color_of(id)
	_burst_snakes(pos, color, 6, float(e["radius"]) * war.radius_mult(), 0.6)
	var n := 0
	for en in _hits_of_last():
		if war.holds.hold(en, float(snake.get("wrap", 3.0)), {"kind": &"wrap", "dps": float(snake.get("dps", 14.0)), "coils": int(snake.get("coils", 3)), "color": color}):
			n += 1
			wraps += 1
	Sfx.play_at(&"snw_coil", pos, -2.0)


func _swarm_burst(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	var sw := _swarm()
	if sw == null:
		return
	var reach := float(e["radius"]) * war.radius_mult()
	var foes := _foes_in(pos, reach)
	var n := int(snake.get("snakes", 10)) + war.brood_extra()
	n = clampi(n, 4, sw.cap() - 3)
	var bite := float(snake.get("bite", 24.0))
	var speed := float(snake.get("speed", 13.0))
	for k in n:
		var a := TAU * float(k) / float(n) + _rng.randf() * 0.4
		var dir := Vector3(cos(a), 0.0, sin(a))
		var start := _ground(pos + dir * 0.4) + Vector3(0.0, 0.1, 0.0)
		var foe: Node3D = foes[k % foes.size()] if not foes.is_empty() else null
		var b := sw.spawn(&"crawl", start, {"color": SnakeRows.GREEN, "thick": 0.12, "len": 2.5, "life": 6.0, "prio": 3, "heading": dir, "head": 1.0, "amp": 0.2, "speed": speed * _rng.randf_range(0.85, 1.2),
				"steer": 7.0, "reach": 1.0, "target": foe, "mode": &"hunt" if foe != null else &"none", "stick": true,
				"on_arrive": func(b2: SnakeSwarm.Body) -> bool:
					var tgt := b2.target
					if not is_instance_valid(tgt) or bool(tgt.get(&"dead")):
						return false
					bites += 1
					_hurt(tgt, TestMode.damage(bite * war.dmg_mult()))
					war.holds.hold(tgt, 1.8, {"kind": &"wrap", "coils": 1, "color": SnakeRows.GREEN})
					FX.burst(SnakeAim.center_of(tgt), SnakeRows.GREEN, 5, 4.0, 0.3, 1.0, 1.0)
					Sfx.play_at(&"snw_hit", SnakeAim.center_of(tgt), -7.0, 1.0 + _rng.randf() * 0.2)
					b2.life = b2.age + 1.8
					return true})
		if b != null and foe == null:
			b.tick = func(b3: SnakeSwarm.Body, dt: float) -> bool:                     # nobody in reach: wander, then fade
				b3.life = minf(b3.life, 2.4)
				b3.pos += b3.heading * 3.5 * dt
				return true
	var ring_r := reach
	sw.spawn(&"ring", pos, {"radius": ring_r * 0.55, "thick": 0.05, "len": ring_r * 3.0, "color": SnakeRows.GREEN, "life": 0.8, "rise_t": 0.25, "prio": 1, "spin": 3.0})
	Sfx.play_at(&"snw_swarm", pos, -2.0)


func _flare(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	_burst_snakes(pos, SnakeRows.AMBER.lerp(Color.WHITE, 0.3), 5, float(e["radius"]) * 0.5, 0.45)
	var reach := float(e["radius"]) * war.radius_mult()
	var t := float(snake.get("mark", MARK_TIME)) + SkillTree.snakewar_grip()
	for en in _foes_in(pos, reach * 1.6):
		_mark(en, t)
	FX.burst(pos + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.95, 0.8), 14, 9.0, 0.5, 2.0, 1.4)
	Sfx.play_at(&"snw_flare", pos, -2.0)


func _mark(en: Node3D, secs: float) -> void:
	for m in marks:
		if m["node"] == en:
			m["left"] = maxf(float(m["left"]), secs)
			return
	if marks.size() >= MARK_CAP:
		marks.remove_at(0)
	marks.append({"node": en, "left": secs})
	marks_made += 1


func _freeze(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var sw := _swarm()
	if sw == null:
		return
	var reach := float(e["radius"]) * war.radius_mult()
	var snake: Dictionary = e.get("snake", {})
	var n := int(snake.get("fangs", 5))
	var life := float(e["hold"]) + SkillTree.snakewar_grip()
	for k in n:
		var a := TAU * float(k) / float(n)
		var base := _ground(pos + Vector3(cos(a), 0.0, sin(a)) * reach * 0.72)
		sw.spawn(&"rise", base, {"color": SnakeRows.ICE, "thick": 0.13, "len": 4.0, "height": 2.4 + 0.3 * float(k % 2), "rise_t": 0.5, "life": life, "prio": 2, "head": 1.0, "heading": Vector3(-cos(a), 0.0, -sin(a)), "tension": 0.2})
	sw.spawn(&"ring", pos, {"radius": reach * 0.72, "thick": 0.07, "len": reach * 4.0, "color": SnakeRows.ICE, "life": life, "rise_t": 0.4, "spin": 0.5, "prio": 1})
	for en in _hits_of_last():
		war.holds.hold(en, float((e["status"] as Dictionary).get("time", 5.0)), {"kind": &"snare", "coils": 0})
	Sfx.play_at(&"snw_freeze", pos, -2.0)


func _chain(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	var n := int(snake.get("hops", 6))
	var gap := float(snake.get("gap", 0.11))
	var range := float(snake.get("hop_range", 9.0)) * war.radius_mult()
	var dmg := float(snake.get("hop_dmg", 42.0))
	var foes := _foes_in(pos, float(e["radius"]) * 1.6)
	if foes.is_empty():
		foes = _foes_in(pos, range)
	if foes.is_empty():
		FX.burst(pos + Vector3(0.0, 0.5, 0.0), SnakeRows.STORM, 8, 6.0, 0.4, 1.0, 1.0)
		return
	var seen: Array[Node3D] = []
	var cur: Node3D = foes[0]
	var from := pos + Vector3(0.0, 0.5, 0.0)
	for k in n:
		if cur == null:
			break
		seen.append(cur)
		var target := cur
		var a := from
		_after(gap * float(k), func() -> void:
			if not is_instance_valid(target) or bool(target.get(&"dead")):
				return
			var c := SnakeAim.center_of(target)
			hops += 1
			var arc := SnakeTendril.fire(a, c, {"host": p, "travel": 0.05, "life": 0.22, "wriggle": 0.55, "tension": 0.35, "thickness": 0.11, "color": SnakeRows.STORM})
			arc.user["keep"] = false
			if FX.qvfx != null:
				FX.qvfx.bolt(a, c, SnakeRows.STORM)
			_hurt(target, TestMode.damage(dmg * war.dmg_mult()))
			if target.has_method(&"stagger"):
				target.call(&"stagger", 1.0)
			if target.has_method(&"disable"):
				target.call(&"disable", 0.9)
			FX.burst(c, SnakeRows.STORM, 6, 5.0, 0.3, 1.0, 1.0)
			Sfx.play_at(&"snw_storm", c, -6.0, 1.0 + 0.04 * float(k)))
		from = SnakeAim.center_of(cur)
		var nxt: Node3D = null
		var bd := range
		for f: Node3D in _foes_in(SnakeAim.center_of(cur), range):
			if seen.has(f):
				continue
			var d := SnakeAim.center_of(f).distance_to(SnakeAim.center_of(cur))
			if d < bd:
				bd = d
				nxt = f
		cur = nxt


func _cluster(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	var n := int(snake.get("bomblets", 4))
	var sw := _swarm()
	var r := float(e["radius"]) * war.radius_mult()
	_burst_snakes(pos, SnakeRows.CYAN, 4, r, 0.5)
	for k in n:
		var a := TAU * (float(k) + _rng.randf() * 0.4) / float(n)
		var dist := _rng.randf_range(4.5, 6.8)
		var to := _ground(pos + Vector3(cos(a) * dist, 0.0, sin(a) * dist))
		var delay := 0.14 * float(k + 1)
		var from := pos + Vector3(0.0, 0.4, 0.0)
		bomblets += 1
		if sw != null:
			sw.spawn(&"ball", from, {"color": SnakeRows.CYAN, "thick": 0.1, "len": 1.8, "radius": 0.3, "life": delay + 0.3, "prio": 2, "head": 1.0,
				"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
					var k2 := clampf(b.age / delay, 0.0, 1.0)
					b.pos = from.lerp(to + Vector3(0.0, 0.3, 0.0), k2) + Vector3(0.0, sin(k2 * PI) * 2.2, 0.0)
					return k2 < 1.0})
		_after(delay, func() -> void:
			BlastTable.apply(&"sb_bomblet", to + Vector3(0.0, 0.2, 0.0), p, _opts()))


func _gravity(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var sw := _swarm()
	if sw == null:
		return
	var reach := float(e["radius"]) * war.radius_mult()
	var pre := float(e["pre"]) if float(e["pre"]) > 0.0 else 1.4
	var n := int((e.get("snake", {}) as Dictionary).get("knots", 5))
	knots += 1
	for k in n:
		var a0 := TAU * float(k) / float(n)
		sw.spawn(&"crawl", _ground(pos + Vector3(cos(a0), 0.0, sin(a0)) * reach * 0.9), {"color": SnakeRows.VIOLET, "thick": 0.09, "len": 2.2, "life": pre + 0.1, "prio": 2, "head": 1.0, "amp": 0.15,
			"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
				var k2 := clampf(b.age / pre, 0.0, 1.0)
				var ang := a0 + k2 * 5.0
				var r := lerpf(reach * 0.9, 0.7, k2 * k2)
				var np := pos + Vector3(cos(ang) * r, 0.25 + 0.5 * k2, sin(ang) * r)
				var d := np - b.pos
				if d.length() > 0.01:
					b.heading = Vector3(d.x, 0.0, d.z).normalized() if Vector2(d.x, d.z).length() > 0.01 else b.heading
				b.pos = np
				return true})
	sw.spawn(&"ball", pos + Vector3(0.0, 1.0, 0.0), {"color": SnakeRows.VIOLET, "thick": 0.1, "len": 3.0, "radius": 0.6, "life": pre + 0.25, "prio": 2,
		"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
			b.radius = lerpf(0.3, 1.0, clampf(b.age / pre, 0.0, 1.0))
			return true})
	Sfx.play_at(&"snw_gravity", pos, -2.0)


func _storm(id: StringName, pos: Vector3) -> void:
	var e := BlastTable.entry(id)
	var snake: Dictionary = e.get("snake", {})
	var sw := _swarm()
	if sw == null:
		return
	var n := int(snake.get("bolts", 10))
	var gap := float(snake.get("gap", 0.3))
	var dmg := float(snake.get("bolt_dmg", 30.0))
	var rise := float(snake.get("rise", 0.7))
	var reach := float(e["radius"]) * war.radius_mult() * 1.4
	var base := _ground(pos)
	var life := rise + gap * float(n) + 0.7
	var u := {"fired": 0, "next": rise}
	sw.spawn(&"rise", base, {"color": SnakeRows.STORM, "thick": 0.2, "len": 5.0, "height": 3.4, "rise_t": rise, "life": life, "prio": 3, "head": 1.4, "stick": true, "tension": 0.2,
		"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
			if b.age < float(u["next"]) or int(u["fired"]) >= n:
				return true
			u["fired"] = int(u["fired"]) + 1
			u["next"] = b.age + gap
			var head := base + Vector3(0.0, 3.3, 0.0) + b.heading * 0.9
			var foes := _foes_in(pos, reach)
			var c: Vector3
			if foes.is_empty():
				var a := _rng.randf() * TAU
				c = pos + Vector3(cos(a), 0.4, sin(a)) * _rng.randf_range(2.0, reach)
			else:
				var f: Node3D = foes[int(u["fired"]) % foes.size()]
				c = SnakeAim.center_of(f)
				bolts += 1
				_hurt(f, TestMode.damage(dmg * war.dmg_mult()))
				if f.has_method(&"stagger"):
					f.call(&"stagger", 1.0)
				if f.has_method(&"disable"):
					f.call(&"disable", 0.7)
			if FX.qvfx != null:
				FX.qvfx.bolt(head, c, SnakeRows.STORM)
			FX.burst(c, SnakeRows.STORM, 5, 5.0, 0.25, 1.0, 1.0)
			Sfx.play_at(&"snw_storm", c, -5.0, 0.9 + _rng.randf() * 0.3)
			return true})
	Sfx.play_at(&"snw_storm", pos, -2.0, 0.7)


# --- the seeker ------------------------------------------------------------------------------------------------------------------------

func _seeker(aim_pt: Vector3) -> bool:
	var sw := _swarm()
	if sw == null:
		return false
	SnakeRows.ensure()
	var e := BlastTable.entry(&"sb_seeker")
	var snake: Dictionary = e.get("snake", {})
	var dir: Vector3 = SnakeAim.ray(p)[1]
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
	var from: Vector3 = _ground(p.global_position + Vector3(0.0, 0.3, 0.0)) + Vector3(0.0, 0.1, 0.0) + flat * 1.2
	var near := _best_seek_target(aim_pt, 18.0)
	var u := {"hop": 0.0, "blocked": 0.0, "target": near, "goal": aim_pt}
	seekers += 1
	var speed := float(snake.get("speed", 15.0))
	var life := float(snake.get("life", 7.0))
	var b := sw.spawn(&"crawl", from, {"color": SnakeRows.CYAN, "thick": 0.12, "len": 4.2, "life": life, "prio": 3, "heading": flat, "head": 1.2, "amp": 0.12, "speed": speed, "steer": float(snake.get("steer", 5.0)),
			"stick": true, "user": u, "tick": _seeker_tick})
	if b == null:
		return false
	_hand_pop(from)
	Sfx.play(&"snw_bomb_throw", -3.0, 1.2)
	return true


## The snake leaves the hand on its own legs: a small pop of sparks at the hand (a rope from the hand to its first metre was a thick clump of loops next to the shoulder camera).
func _hand_pop(at: Vector3) -> void:
	var hand: Vector3 = p.snake.hand_pos(HERO_HAND)
	FX.burst(hand.lerp(at, 0.5), SnakeRows.CYAN, 6, 3.0, 0.3, 0.0, 1.0)


func _tendril_to(at: Vector3) -> void:
	var t := SnakeTendril.fire(p.snake.hand_callable(HERO_HAND), at, {"host": p, "travel": 0.12, "life": 0.05, "tension": 0.5, "thickness": 0.07, "color": SnakeRows.CYAN})
	t.user["keep"] = false


func _best_seek_target(aim_pt: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	var bd := reach
	for e: Node3D in Gear.living_enemies(p.get_tree()):
		if e.get(&"friendly") == true:
			continue
		var d := e.global_position.distance_to(aim_pt)
		if d < bd:
			bd = d
			best = e
	return best


func _seeker_tick(b: SnakeSwarm.Body, dt: float) -> bool:
	var u := b.user
	var tgt := u.get("target") as Node3D
	if tgt != null and (not is_instance_valid(tgt) or bool(tgt.get(&"dead"))):
		tgt = null
		u["target"] = null
	var goal: Vector3 = Vector3(tgt.global_position.x, tgt.global_position.y, tgt.global_position.z) if tgt != null else (u["goal"] as Vector3)
	# a wall ahead: hop over it (a low one) or give up after a moment
	if float(u["hop"]) <= 0.0:
		_rq.from = b.pos + Vector3(0.0, 0.5, 0.0)
		_rq.to = _rq.from + b.heading * 1.4
		if not p.get_world_3d().direct_space_state.intersect_ray(_rq).is_empty():
			u["blocked"] = float(u["blocked"]) + dt
			if float(u["blocked"]) > 0.15:
				u["hop"] = 0.55
				u["blocked"] = 0.0
		else:
			u["blocked"] = 0.0
	var rest := 99.0
	if float(u["hop"]) > 0.0:
		u["hop"] = float(u["hop"]) - dt
		var k := 1.0 - float(u["hop"]) / 0.55
		b.pos += b.heading * b.speed * dt
		b.pos.y += (6.0 - 14.0 * k) * dt
		rest = Vector2(goal.x - b.pos.x, goal.z - b.pos.z).length()
		b.lift = 0.5
	else:
		rest = _swarm().crawl_to(b, goal, dt, b.speed)
	u["trail"] = float(u.get("trail", 0.0)) - dt
	if float(u["trail"]) <= 0.0:
		u["trail"] = 0.06
		FX.burst(b.pos + Vector3(0.0, 0.25, 0.0), SnakeRows.CYAN, 2, 1.5, 0.35, 0.0, 1.3)       # a bright trail: a snake that runs across a street at 15 m/s is seen by what it leaves behind
	if rest < 1.7 or b.age >= b.life - 0.05:
		last_res = BlastTable.apply(&"sb_seeker", b.pos + Vector3(0.0, 0.6, 0.0), p, _opts()).duplicate()
		by_id[&"sb_seeker"] = int(by_id.get(&"sb_seeker", 0)) + 1
		Sfx.play_at(&"snw_burst", b.pos, -3.0)
		return false
	return true


# --- the burrower ----------------------------------------------------------------------------------------------------------------------

func _burrow(aim_pt: Vector3) -> bool:
	var sw := _swarm()
	if sw == null:
		return false
	var e := BlastTable.entry(&"sb_burrow")
	var snake: Dictionary = e.get("snake", {})
	var reach := float(snake.get("reach", 26.0))
	var car: Node3D = null
	var bd := reach
	for v: Node in p.get_tree().get_nodes_in_group(&"vehicle"):
		var vn := v as Node3D
		if vn == null or not is_instance_valid(vn) or vn == p.vehicle or bool(vn.get(&"dead")):
			continue
		var d := vn.global_position.distance_to(aim_pt)
		if d < bd:
			bd = d
			car = vn
	var dir: Vector3 = SnakeAim.ray(p)[1]
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
	var from := _ground(p.global_position) + flat * 1.3
	burrows += 1
	var u := {"car": car, "goal": aim_pt, "trail": 0.0}
	var b := sw.spawn(&"crawl", from, {"color": SnakeRows.GREEN, "thick": 0.15, "len": 4.5, "life": float(snake.get("life", 6.0)), "prio": 3, "heading": flat, "head": 1.0, "amp": 0.06, "speed": float(snake.get("speed", 11.0)),
			"steer": 6.0, "stick": true, "user": u, "tick": _burrow_tick})
	if b == null:
		return false
	_hand_pop(from)
	Sfx.play(&"snw_bomb_throw", -3.0, 0.8)
	return true


func _burrow_tick(b: SnakeSwarm.Body, dt: float) -> bool:
	var u := b.user
	var car := u.get("car") as Node3D
	if car != null and (not is_instance_valid(car) or bool(car.get(&"dead"))):
		car = null
		u["car"] = null
	var goal: Vector3 = car.global_position if car != null else (u["goal"] as Vector3)
	var rest := _swarm().crawl_to(b, goal, dt, b.speed)
	b.pos.y -= 0.06                                                             # most of the body is under the ground: the head and a ridge show
	u["trail"] = float(u["trail"]) - dt
	if float(u["trail"]) <= 0.0:
		u["trail"] = 0.09
		FX.burst(b.pos + Vector3(0.0, 0.2, 0.0), Color(0.5, 0.42, 0.3), 3, 3.0, 0.45, 5.0, 1.6)
	if rest < 1.9 or b.age >= b.life - 0.05:
		var at := (car.global_position if car != null else goal) - Vector3(0.0, 0.3, 0.0)
		last_res = BlastTable.apply(&"sb_burrow", at, p, _opts()).duplicate()
		by_id[&"sb_burrow"] = int(by_id.get(&"sb_burrow", 0)) + 1
		Sfx.play_at(&"snw_burst", at, -2.0)
		return false
	return true


# --- the mega python -----------------------------------------------------------------------------------------------------------------

func _mega() -> bool:
	var sw := _swarm()
	if sw == null:
		return false
	var e := BlastTable.entry(&"sb_mega")
	var snake: Dictionary = e.get("snake", {})
	var dir: Vector3 = SnakeAim.ray(p)[1]
	var flat := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.05 else Vector3.FORWARD
	var at := _ground(p.global_position + flat * 9.0)
	var rise := float(snake.get("rise", 1.1))
	megas += 1
	var radius := float(e["radius"]) * war.radius_mult()
	var big := sw.spawn(&"rise", at, {"color": SnakeRows.GOLD, "thick": 0.8, "len": 20.0, "height": 15.0, "rise_t": rise, "life": rise + 1.0, "prio": 3, "head": 1.0, "stick": true, "heading": flat, "tension": 0.1})
	for k in int(snake.get("coils", 8)):
		var a := TAU * float(k) / float(snake.get("coils", 8))
		sw.spawn(&"rise", at + Vector3(cos(a), 0.0, sin(a)) * 4.0, {"color": SnakeRows.VIOLET.lerp(SnakeRows.GOLD, 0.3), "thick": 0.25, "len": 8.0, "height": 5.0 + 1.5 * float(k % 3), "rise_t": rise * 0.8, "life": rise + 0.9, "prio": 2, "head": 1.0,
			"heading": Vector3(-cos(a), 0.0, -sin(a))})
	sw.spawn(&"ring", at, {"radius": 3.0, "thick": 0.2, "len": 30.0, "color": SnakeRows.GOLD, "life": rise + 0.8, "rise_t": rise, "prio": 2, "spin": 1.2})
	FX.shake(0.4)
	GameFeel.fire(&"slam")
	Game.say("MEGA PYTHON", 1.4)
	Sfx.play_at(&"snw_mega", at, 0.0)
	_after(rise, func() -> void:
		last_res = BlastTable.apply(&"sb_mega", at + Vector3(0.0, 0.2, 0.0), p, _opts()).duplicate()
		by_id[&"sb_mega"] = int(by_id.get(&"sb_mega", 0)) + 1
		sw.spawn(&"ring", at, {"radius": radius, "thick": 0.3, "len": radius * 6.0, "color": SnakeRows.GOLD, "life": 0.9, "rise_t": 0.35, "prio": 2, "spin": 2.5})
		FX.shake(1.2)
		Sfx.play_at(&"snw_slam", at, 0.0, 0.6))
	return big != null


# --- marks and the tick ----------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	var i := _links.size() - 1
	while i >= 0:
		var l := _links[i]
		l["t"] = float(l["t"]) - dt
		if float(l["t"]) <= 0.0:
			_links.remove_at(i)
			(l["fn"] as Callable).call()
		i -= 1
	if not marks.is_empty():
		var j := marks.size() - 1
		while j >= 0:
			var m := marks[j]
			m["left"] = float(m["left"]) - dt
			if float(m["left"]) <= 0.0 or not is_instance_valid(m["node"]) or bool((m["node"] as Node3D).get(&"dead")):
				marks.remove_at(j)
			j -= 1
		_update_marks()
	elif _mmi != null and _mmi.visible:
		_update_marks()


## Diamonds over the marked enemies: one MultiMesh of billboards that ignores depth (visible through walls), hidden while no mark lives.
func _update_marks() -> void:
	if marks.is_empty():
		if _mmi != null and is_instance_valid(_mmi):
			_mmi.visible = false
		return
	if _mmi == null or not is_instance_valid(_mmi):
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.use_colors = true
		_mm.instance_count = MARK_CAP
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 0.7)
		_mm.mesh = q
		_mmi = MultiMeshInstance3D.new()
		_mmi.name = "SnakeMarks"
		_mmi.multimesh = _mm
		_mmi.top_level = true
		_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mmi.custom_aabb = SnakeSwarm.FAR_AABB
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.no_depth_test = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _diamond_texture()
		mat.render_priority = 5
		_mmi.material_override = mat
		p.add_child(_mmi)
	_mmi.visible = true
	_mm.visible_instance_count = marks.size()
	var t := float(Time.get_ticks_msec()) * 0.001
	for k in marks.size():
		var n := marks[k]["node"] as Node3D
		var c := SnakeAim.center_of(n) + Vector3(0.0, 1.35 + 0.08 * sin(t * 5.0 + float(k)), 0.0)
		var dist := c.distance_to(p.global_position)
		var s := clampf(dist * 0.045, 0.7, 2.6)
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * s), c))
		var fade := clampf(float(marks[k]["left"]) / 1.0, 0.0, 1.0)
		_mm.set_instance_color(k, Color(1.0, 0.78, 0.25, 0.95 * fade))


static var _diamond_tex: Texture2D


static func _diamond_texture() -> Texture2D:
	if _diamond_tex != null:
		return _diamond_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dx := absf(float(x) - 15.5) / 15.0
			var dy := absf(float(y) - 15.5) / 15.0
			var d := dx + dy
			var edge := smoothstep(1.0, 0.82, d)
			var ring := smoothstep(0.55, 0.7, d) * edge
			var a := ring + (1.0 - smoothstep(0.0, 0.25, d)) * 0.8
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	_diamond_tex = ImageTexture.create_from_image(img)
	return _diamond_tex
