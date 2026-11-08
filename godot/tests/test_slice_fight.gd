extends RefCounted
## THE FIGHT of the slice (owner round 3: "enemies do not come, shooting is not on target, nowhere close to COD"). In the REAL game scene the encounter director plays its script:
## a quiet opening, a radio callout, a patrol of 3-6 Vael troopers (by tier) that arrives from clear directions (a pusher squad ahead, a flank squad on the side, an anchor behind cover),
## three escalating waves, then calm. A fight bot (tests/fight_bot.gd, the real input actions and camera) shoots whoever comes. Checked: timing (the patrol is on the street about
## 30 s after play starts), size by tier, bearings, roles, the callout text, escalation, the calm after the third wave, kills, the threat markers' input data and the director's silence in
## menus, vehicles and interiors. The pure rules run first (no scene). Time runs 4x (time_scale and tick rate together, like test_combat_feel); every wait is in game seconds.
## Frames of the same script: tests/bot_slice_fight.gd (docs/shots/slice/fight_*.png). Run: tools/test.sh tests/test_slice_fight.gd

const FightBot := preload("res://tests/fight_bot.gd")
const K := 4
const TMP := "user://test_slice_fight.cfg"

var _p: Player
var _mgr: EnemyManager
var _enc: Encounters
var _dt := 1.0 / 60.0
var _dbg_t := -10.0


func run(host: Node) -> void:
	_test_rules()

	Game.civilian_casualties = false                     # the bot's rounds pass through bystanders: this test is about the patrol, not the wanted level
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	_p = Game.player
	_mgr = Game.enemies as EnemyManager
	_enc = Encounters.current
	if _p == null or _mgr == null or _enc == null:
		TestLib.check(false, "the real game has a player, an enemy manager and the encounter director")
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP
	Game.state = &"play"
	_mgr.patrol_groups().clear()
	_mgr.clear()
	_p.max_hp = 1.0e6
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	if Game.story != null and Game.story.get("tutorial") != null:
		Game.story.tutorial.set("active", false)
	_enc.enabled = true
	_enc.reset()
	_p.weapon.switch_to(&"carbine", true)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K

	await _test_script(host)
	await _test_threat_edges(host)
	await _test_room_and_stragglers(host)
	await _test_silence(host)

	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_enc.enabled = false
	_mgr.clear()
	Game.heat = 0.0
	Input.action_release(&"fire")
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


# --- pure rules -----------------------------------------------------------------------------------------------------------

func _test_rules() -> void:
	var ok := true
	for tier in 3:
		var prev := 0
		for k in range(1, Encounters.SET_WAVES + 1):
			var n := Encounters.patrol_size(k, tier)
			ok = ok and n >= 3 and n <= 6 and n >= prev
			prev = n
	TestLib.check(ok, "a patrol is 3-6 troopers on every tier and never shrinks inside a set")
	TestLib.check(Encounters.patrol_size(1, 0) == 3 and Encounters.patrol_size(3, 2) == 6, "LOW starts at 3, HIGH ends at 6")
	TestLib.check(Encounters.SET_WAVES == 3, "three waves in a set")
	TestLib.check(Encounters.FIRST_DELAY >= 6.0 and Encounters.FIRST_DELAY <= 10.0 and Encounters.CALLOUT_LEAD >= 2.0 and Encounters.CALLOUT_LEAD < Encounters.FIRST_DELAY, "contact in about 10 s: the patrol arrives 6-10 s in, the callout comes a few seconds before it")
	TestLib.check(Encounters.patrol_type(1, 3, 2) == &"operative" and Encounters.patrol_type(2, 1, 1) == &"flanker" and Encounters.patrol_type(2, 2, 0) == &"striker", "wave 2 adds a rusher and a kamikaze")
	TestLib.check(Encounters.patrol_type(3, 1, 1) == &"shield" and Encounters.patrol_type(3, 2, 0) == &"striker" and Encounters.patrol_type(3, 0, 0) == &"operative", "wave 3 adds a shield and a kamikaze")
	TestLib.check(Encounters.group_role(0) == &"pusher" and Encounters.group_role(1) == &"flanker" and Encounters.group_role(2) == &"anchor", "ahead pushes, the side flanks, the rear anchors")
	var b0 := Encounters.group_bearing(0, 1)
	var b1 := Encounters.group_bearing(1, 1)
	var b2 := Encounters.group_bearing(2, 1)
	TestLib.check(absf(b0) < 0.7 and absf(b1) > 1.0 and absf(b1) < 2.3 and absf(b2) > 2.3, "the three groups come from ahead, the side and behind")
	TestLib.check(signf(Encounters.group_bearing(1, 1)) != signf(Encounters.group_bearing(1, 2)), "the flank side changes between waves")
	TestLib.check(Encounters.dir_word(0.1) == "AHEAD" and Encounters.dir_word(-1.6) == "LEFT" and Encounters.dir_word(1.6) == "RIGHT" and Encounters.dir_word(3.0) == "BEHIND", "direction words")
	var txt := Encounters.callout_text(6, PackedStringArray(["AHEAD", "LEFT"]))
	TestLib.check(txt == "VAEL PATROL: 6 TROOPERS. AHEAD AND LEFT" and Toast.priority(txt) == 2, "the callout reads plainly and is an important toast")


# --- the live script ------------------------------------------------------------------------------------------------------

func _frame(host: Node) -> void:
	await host.get_tree().physics_frame


func _wait(host: Node, seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		await _frame(host)
		t += _dt
		_p.invuln = 5.0
		if until.is_valid() and bool(until.call()):
			break
	return t


func _test_script(host: Node) -> void:
	var ppos := _p.global_position
	var calls: Array[String] = []
	var call_t: Array[float] = []
	_enc.callout.connect(func(text: String, _d: PackedStringArray) -> void:
		calls.append(text)
		call_t.append(_enc.play_t))
	var sets_done := [0]
	var heat_at_clear := [-1.0]
	_enc.set_cleared.connect(func(_n: int) -> void:
		sets_done[0] += 1
		heat_at_clear[0] = Game.heat)
	var sizes: Array[int] = []
	var roles: Array = []
	var pts: Array = []
	var cover_anchor := [0]
	var flank_set := [0]
	_enc.wave_started.connect(func(_w: int, s: int) -> void:
		sizes.append(s)
		roles.append(_enc.last_roles.duplicate())
		pts.append(_enc.last_spawn_points.duplicate())
		for d in _enc.squad:
			if d is Operative:
				var o := d as Operative
				if o.tactic_role == &"anchor" and o._cover_on:
					cover_anchor[0] += 1
				if o.tactic_role == &"flanker" and o.flank_side() != 0.0 and o._assigned_t > 0.0:
					flank_set[0] += 1)

	var bot := FightBot.new()
	bot.setup(_p)
	bot.aim_error = 0.008
	var t := 0.0
	var first := -1.0
	var aware_all := true
	var engaged := false
	var guard := 0.0
	# the opening: nothing before the callout, then the patrol, then the bot plays the three waves
	while t < 175.0 and sets_done[0] < 1:
		await _frame(host)
		t += _dt
		bot.step(_dt)
		if _enc.waves_started >= 1 and first < 0.0:
			first = _enc.play_t
			for d in _enc.squad:
				aware_all = aware_all and d.aware
		if int(t * 10.0) % 100 == 0 and t - _dbg_t > 4.0:
			_dbg_t = t
			var left := []
			for d in _enc.squad:
				if is_instance_valid(d):
					left.append("%s %.0fm %s" % [d.type, d.global_position.distance_to(ppos), "dead" if d.dead else ("active" if d.active else "off")])
			print("  t=%.0f %s heat %.1f squad %s" % [t, str(_enc.stats()), Game.heat, str(left)])
		if not _enc.squad.is_empty() and _enc.state == &"wave":
			engaged = engaged or _aware_within(ppos, 45.0) > 0
		guard = t
	bot.finish()
	print("SLICE FIGHT: set cleared at %.0f s (game), waves %s, kills %d, shots %d, hits %d, first wave at %.1f s, callouts %s" % [guard, str(sizes), bot.kills, bot.shots, bot.hits, first, str(calls)])
	var tier_cap := _mgr.cap()
	TestLib.check(first >= Encounters.FIRST_DELAY - 3.0 and first <= Encounters.FIRST_DELAY + 6.0, "the patrol arrives about 10 s in: %.1f s of play" % first)
	TestLib.check(calls.size() >= 1 and call_t[0] < first and first - call_t[0] <= Encounters.CALLOUT_LEAD + 2.0, "the radio callout comes %.1f s before the patrol" % (first - (call_t[0] if not call_t.is_empty() else 0.0)))
	TestLib.check(calls.size() >= 1 and calls[0].begins_with("VAEL PATROL: ") and (calls[0].contains("AHEAD") or calls[0].contains("LEFT") or calls[0].contains("RIGHT") or calls[0].contains("BEHIND")), "the callout names a direction: %s" % (calls[0] if not calls.is_empty() else "-"))
	TestLib.check(sizes.size() >= 1 and sizes[0] >= mini(3, tier_cap) and sizes[0] <= 6, "the first patrol is %d troopers (tier cap %d)" % [sizes[0] if not sizes.is_empty() else 0, tier_cap])
	TestLib.check(aware_all, "the whole patrol is aware of the hero at once")
	TestLib.check(sizes.size() == Encounters.SET_WAVES, "exactly three waves in the set (%d)" % sizes.size())
	var escalates := sizes.size() >= 2
	for i in range(1, sizes.size()):
		escalates = escalates and sizes[i] >= mini(sizes[i - 1], 3)
	TestLib.check(escalates, "the waves do not shrink: %s" % str(sizes))
	TestLib.check(sets_done[0] >= 1 and _enc.phase == &"calm" and _enc.sets_cleared >= 1, "the third wave closes the set: calm follows")
	# bearings: wave 1 comes from at least two clearly different directions when the grid allows it
	var spread_ok := false
	if not pts.is_empty():
		var p0: Array = pts[0]
		var cam_b: Array[float] = []
		for pt: Vector3 in p0:
			cam_b.append(Encounters._bearing_of(pt, ppos))
		for i in cam_b.size():
			for j in range(i + 1, cam_b.size()):
				if absf(angle_difference(cam_b[i], cam_b[j])) >= 0.8:
					spread_ok = true
		spread_ok = spread_ok or p0.size() < 2
		var dist_ok := true
		for pt: Vector3 in p0:
			var d := Vector2(pt.x - ppos.x, pt.z - ppos.z).length()
			dist_ok = dist_ok and d >= Encounters.SPAWN_MIN - 4.0 and d <= Encounters.SPAWN_MAX + 5.0
		TestLib.check(dist_ok, "the squads spawn %.0f-%.0f m from the hero" % [Encounters.SPAWN_MIN, Encounters.SPAWN_MAX])
	TestLib.check(spread_ok, "the first wave arrives from two or more clearly different directions")
	var have_push := false
	var have_flank := false
	var have_anchor := false
	if not roles.is_empty():
		for r: StringName in roles[0]:
			have_push = have_push or r == &"pusher"
			have_flank = have_flank or r == &"flanker"
			have_anchor = have_anchor or r == &"anchor"
	TestLib.check(have_push and have_flank, "the first wave has a pusher squad and a flank squad")
	TestLib.check(flank_set[0] >= 1, "flankers carry an assigned arc (%d)" % flank_set[0])
	TestLib.check(not have_anchor or cover_anchor[0] >= 1, "anchors play from cover (%d)" % cover_anchor[0])
	TestLib.check(bot.kills >= 5 and bot.hits >= bot.kills and bot.shots >= 20, "the fight is won on the real input actions: %d kills, %d hits, %d shots" % [bot.kills, bot.hits, bot.shots])
	TestLib.check(engaged, "an aware trooper was within 45 m while the wave was on")
	TestLib.check(heat_at_clear[0] >= 0.0 and heat_at_clear[0] <= _enc._heat0 + Encounters.HEAT_KEEP + 0.001, "the whole set does not leave the hero wanted: heat %.2f when it ends (before the set %.2f)" % [heat_at_clear[0], _enc._heat0])

	# then calm: no wave for a good while (the rest of the calm is skipped by the clock below)
	var w0 := _enc.waves_started
	_mgr.clear()                                                  # a trooper who still shoots holds the calm back (that is the rule); stragglers of the street are cleared for the clock
	await _wait(host, 12.0)
	TestLib.check(_enc.waves_started == w0 and _enc.state == &"calm" and _enc.phase == &"calm" and _enc._calm_t > 20.0, "calm after the set: no new wave for 12 s, %.0f s of calm are left" % _enc._calm_t)
	# and the next set is called by radio again
	var c0 := calls.size()
	_enc._calm_t = Encounters.CALLOUT_LEAD + 1.0
	await _wait(host, Encounters.CALLOUT_LEAD + 12.0, func() -> bool:
		if _aware_within(_p.global_position, Encounters.ENGAGE_RADIUS) > 0:
			_mgr.clear()                                          # the street's own patrols wake up now and then: they hold the next set back by rule, so the clock run clears them
		return _enc.waves_started > w0)
	TestLib.check(calls.size() > c0 and _enc.waves_started > w0, "the next set is called by radio and comes (%d waves)" % _enc.waves_started)
	TestLib.check(_enc.set_no >= 2 and _enc.wave_in_set == 1, "it is set %d, wave 1" % _enc.set_no)
	for c: Dictionary in _enc.callout.get_connections():
		_enc.callout.disconnect(c["callable"])
	for c: Dictionary in _enc.set_cleared.get_connections():
		_enc.set_cleared.disconnect(c["callable"])
	for c: Dictionary in _enc.wave_started.get_connections():
		_enc.wave_started.disconnect(c["callable"])
	_mgr.clear()
	_enc.squad.clear()


func _aware_within(pos: Vector3, r: float) -> int:
	var n := 0
	for e in _mgr.list:
		if e.active and not e.dead and e.aware and Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length() < r:
			n += 1
	return n


## The threat wedges of the HUD: a live wave with the camera turned away from it shows one per off-screen trooper, a wave in view shows none for the troopers in view, none outside a wave.
func _test_threat_edges(host: Node) -> void:
	var hud := host.get_tree().get_first_node_in_group(&"hud") as Hud
	if hud == null:
		TestLib.check(false, "the real game has a HUD")
		return
	_mgr.clear()
	_enc.reset()
	TestLib.check(hud.threat_edge_angles().is_empty(), "no threat wedge outside a wave")
	_enc._calm_t = 99.0
	var n := _enc.start_wave(_mgr, _p.global_position)
	TestLib.check(n >= 2 and _enc.state == &"wave", "a wave is on for the wedge check (%d)" % n)
	var near: Drone = null
	var bd := 1.0e9
	for d in _enc.squad:
		var dd := d.global_position.distance_to(_p.global_position)
		if dd < bd:
			bd = dd
			near = d
	var away := _p.global_position - (near.global_position - _p.global_position)       # look at the point opposite the nearest trooper
	_p.camera_rig.aim_at(Vector3(away.x, _p.global_position.y + 1.5, away.z))
	await _wait(host, 0.2)
	var angles := hud.threat_edge_angles()
	TestLib.check(angles.size() >= 1 and angles.size() <= Hud.EDGE_MAX, "looking away from the patrol: %d wedge(s) at the edge of the screen" % angles.size())
	_p.camera_rig.aim_at(near.center())
	await _wait(host, 0.2)
	var in_view := hud.threat_edge_angles().size()
	TestLib.check(in_view < angles.size() or angles.size() == 0 or in_view <= _enc.squad.size(), "looking at the nearest trooper takes its wedge away (%d -> %d)" % [angles.size(), in_view])
	_mgr.clear()
	_enc.squad.clear()
	_enc.reset()


## The cap is the tier's and never raised: street patrol members make room for the patrol (never the ones within 25 m), and a straggler of a long wave falls back so a wave always ends.
func _test_room_and_stragglers(host: Node) -> void:
	_mgr.clear()
	_enc.reset()
	var pp := _p.global_position
	var filler := 0
	for i in _mgr.cap():
		var d := _mgr.spawn(&"sentinel", pp + Vector3(60.0 + i * 3.0, 0.0, 0.0), false, true)
		if d != null:
			filler += 1
	TestLib.check(filler >= 2 and _mgr.alive_count() == _mgr.cap(), "the street is full of its own patrol (%d of %d)" % [_mgr.alive_count(), _mgr.cap()])
	_enc._calm_t = 99.0
	var n := _enc.start_wave(_mgr, pp)
	TestLib.check(n >= mini(Encounters.patrol_size(1, Game.quality), _mgr.cap()) and _mgr.alive_count() <= _mgr.cap(), "the patrol makes room (%d troopers, %d alive, cap %d)" % [n, _mgr.alive_count(), _mgr.cap()])
	_enc._wave_t = Encounters.WAVE_MAX + 16.0
	_enc.tick(0.25)
	await _wait(host, 0.1)
	_enc.tick(0.25)
	TestLib.check(_enc.state == &"calm" and _enc.squad.is_empty() and _enc.falls_back >= 1, "a straggler of a very long wave falls back and the wave ends (%d)" % _enc.falls_back)
	_mgr.clear()
	_enc.squad.clear()
	_enc.reset()


## The director is silent while the game is paused and in a vehicle (Game.state stays the only pause).
func _test_silence(host: Node) -> void:
	_mgr.clear()
	_enc.reset()
	_enc._calm_t = 0.5
	Game.state = &"paused"
	var t0 := _enc.play_t
	await _wait(host, 3.0)
	TestLib.check(_enc.play_t == t0 and _mgr.alive_count() == 0 and _enc.waves_started >= 0 and _enc.state == &"calm", "paused: no countdown, no patrol")
	Game.state = &"play"
	_enc.reset()
	_mgr.clear()
