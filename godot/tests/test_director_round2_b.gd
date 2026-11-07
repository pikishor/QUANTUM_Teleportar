extends RefCounted
## Director review round 2, part B (docs/SLICE_REVIEW.md defects 6, 7, 14, 13) in the REAL game scene:
##   6  entering a building never kills the hero: the street sends nobody through the walls (city events, reinforcements, patrol streaming, radio calls), a shop's own guard is a bystander,
##      the room's guards start at a share of their damage and warm up, and one killing blow per visit is forgiven (the hero is patched up with a few seconds of cover)
##   7  inside a building the plate never shows a street step's distance (a room without a job, a door step that is not this door)
##   14 a hack / defend step holds the heat under the patrol-car level and bleeds it off while the hero holds the ring
##   13 the fight: an aim error disc that grows with distance, burst climb and a moving or covered hero (hit chance and near misses), six Vael looks that differ in colour and build
##      (the roster picks a look by role), and a live fight that shows near misses and more than one look
## Waits on counters and game seconds, never on frame counts; user:// state is reset first. Time runs 4x in the long parts (time_scale and tick rate together).
## Frames of the same things: tests/bot_round2_fight.gd (FIGHT_LOOKS=1 for the roster, none for the fight), docs/shots/slice/round2_b_*.
## Run: tools/test.sh tests/test_director_round2_b.gd

const TIMEOUT_SECONDS := 130.0
const FightBot := preload("res://tests/fight_bot.gd")
const CityEventsScript := preload("res://scripts/world/city_events.gd")
const K := 4

var host: Node
var camp: CampaignRunner
var p: Player
var hud: Hud
var _dt := 1.0 / 60.0


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://bot_fight2.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_rules()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	p = Game.player as Player
	var m := Game.missions as Missions
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(p != null and m != null and m.campaign != null and hud != null, "the real scene has a player, missions, a campaign and a HUD")
	if p == null or m == null or hud == null:
		return
	camp = m.campaign
	camp.set_physics_process(false)
	camp.enabled = false
	(Game.progress as Progress).autosave_enabled = false
	Game.civilian_casualties = false
	if Game.story != null and Game.story.get("tutorial") != null:
		Game.story.tutorial.set("active", false)
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	await _street_stays_out()
	await _rooms_do_not_kill()
	await _mercy()
	await _plate_inside()
	await _hold_heat()
	await _fight()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _frame() -> void:
	await host.get_tree().physics_frame


func _wait(seconds: float, until := Callable()) -> float:
	var t := 0.0
	while t < seconds:
		await _frame()
		t += _dt
		if until.is_valid() and bool(until.call()):
			break
	return t


func _chapter(steps: Array) -> void:
	camp.abort()
	Game.heat = 0.0
	Game.state = &"play"
	camp.start_custom({"id": "director_b", "clears_sector": false, "steps": steps})


func _leave_all() -> void:
	if InteriorGameplay.active:
		InteriorGameplay.instance.leave(true)
	(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	if p.is_dead() or Game.state == &"dead":
		Game.do_respawn()
	Game.state = &"play"


# --- pure rules -------------------------------------------------------------------------------------------------------------------

func _rules() -> void:
	# 13: the aim error disc
	var still4 := Operative.aim_radius(0.035, 0.0008, 4.0)
	var still8 := Operative.aim_radius(0.035, 0.0008, 8.0)
	var still20 := Operative.aim_radius(0.035, 0.0008, 20.0)
	TestLib.check(still4 < still8 and still8 < still20, "the aim error grows with distance (%.2f, %.2f, %.2f m at 4, 8, 20 m)" % [still4, still8, still20])
	TestLib.check(Operative.aim_radius(0.035, 0.0008, 0.5) >= 0.4, "even point blank a trooper's round is not a certain hit (floor %.2f m)" % Operative.aim_radius(0.035, 0.0008, 0.5))
	TestLib.check(Operative.aim_radius(0.035, 0.0008, 8.0, 2) > Operative.aim_radius(0.035, 0.0008, 8.0, 0) * 1.3, "the muzzle climbs through a volley (3rd round vs 1st)")
	TestLib.check(Operative.aim_radius(0.035, 0.0008, 8.0, 0, 5.0) > still8 * 1.2 and Operative.aim_radius(0.035, 0.0008, 8.0, 0, 6.0, true) > Operative.aim_radius(0.035, 0.0008, 8.0, 0, 5.0), "a running hero is harder to hit, a sprinting one harder still")
	TestLib.check(Operative.aim_radius(0.035, 0.0008, 8.0, 0, 0.0, false, true) > still8 * 1.3, "a hero behind cover is harder to hit")
	TestLib.check(Operative.aim_radius(0.035, 0.0008, 8.0, 0, 0.0, false, false, 1.5) > still8 * 1.4, "a hurt hero is missed more (hurt aim)")
	TestLib.check(Operative.aim_radius(0.002, 0.00005, 40.0) < 0.4, "a sniper's laser lock stays tight (%.2f m at 40 m)" % Operative.aim_radius(0.002, 0.00005, 40.0))
	var p4 := pow(0.5 / still4, 2.0)
	var p20 := pow(0.5 / still20, 2.0)
	TestLib.check(p4 >= 0.35 and p4 <= 0.75 and p20 < 0.25, "chance to hit a standing hero: %.0f %% at 4 m, %.0f %% at 20 m" % [p4 * 100.0, p20 * 100.0])
	TestLib.check(int(EnemyTypes.TYPES[&"operative"]["burst"]) >= 2 and float(EnemyTypes.TYPES[&"operative"]["aim_time"]) >= 0.3, "troopers fire in bursts after an aim windup")
	# 13: the roster
	var jackets: Array[Color] = []
	var worst_lum := 0.0
	var widths: Array[float] = []
	for c: Dictionary in HumanoidVariants.VAEL_CLASSES:
		var j: Color = c["jacket"]
		jackets.append(j)
		worst_lum = maxf(worst_lum, 0.2126 * j.r + 0.7152 * j.g + 0.0722 * j.b)
		widths.append((c["scale3"] as Vector3).x)
	var apart := true
	for i in jackets.size():
		for k in range(i + 1, jackets.size()):
			var a := jackets[i]
			var b := jackets[k]
			apart = apart and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12
	widths.sort()
	TestLib.check(HumanoidVariants.VAEL_CLASSES.size() == HumanoidVariants.VAEL_COUNT and apart, "six Vael looks, every armour colour clearly different from every other")
	TestLib.check(worst_lum < 0.36, "every trooper's armour is dark (%.2f): none reads as the hero's light jacket" % worst_lum)
	TestLib.check(widths[widths.size() - 1] - widths[0] >= 0.25, "the looks differ in build: %.2f to %.2f wide" % [widths[0], widths[widths.size() - 1]])
	var seen := {}
	for s in 24:
		seen[HumanoidVariants.variant(&"vael", s * 7 + 1)["class"]] = true
	TestLib.check(seen.size() >= 4, "24 troopers show %d different looks" % seen.size())
	var forced: Dictionary = HumanoidVariants.variant(&"vael", 5, int(HumanoidVariants.ROLE_CLASS[&"sniper"]))
	TestLib.check(forced["class"] == &"marksman" and HumanoidVariants.variant(&"vael", 5, 1)["class"] == &"gunner", "a role picks its look (sniper marksman, shield gunner)")
	# 14, 6: the numbers
	TestLib.check(CampaignRunner.HOLD_HEAT_CAP <= 1.6 and CampaignRunner.HOLD_HEAT_DECAY > 0.0, "a hack or defend holds the heat under %.1f and bleeds it off" % CampaignRunner.HOLD_HEAT_CAP)
	TestLib.check(InteriorGameplay.PRESSURE_FROM < 0.6 and InteriorGameplay.PRESSURE_SECS >= 30.0 and InteriorGameplay.MERCY_HP >= 0.3 and InteriorGameplay.MERCY_INVULN >= 3.0, "a room's guards start soft and warm up slowly, one blow is forgiven")


# --- 6: the street stays out ------------------------------------------------------------------------------------------------------

func _street_stays_out() -> void:
	var ig := InteriorGameplay.instance
	TestLib.check(ig != null, "the interior system runs in the real scene")
	if ig == null:
		return
	var em := Game.enemies as EnemyManager
	var ev: Node = CityEventsScript.current
	_leave_all()
	p.max_hp = 100.0
	p.hp = 100.0
	p.invuln = 0.0
	TestLib.check(ig.test_enter(&"club").begins_with("INSIDE"), "the hero goes into a club")
	em.clear()
	Game.heat = 3.0                                                # a manhunt outside: the street still sends nobody through the wall
	var events0: int = ev.events.size() if ev != null else 0
	if ev != null:
		ev.next_spawn = 0.0
		ev.clock = 100.0
	var sent := 0
	await _wait(6.0)
	for e in em.list:
		if e.active and not e.dead and not ig.actors.guards.has(e) and not ig.actors.followers.has(e):
			sent += 1
	TestLib.check(sent == 0, "6 s inside a hunted room: no street reinforcement, patrol or event drone came in (%d strangers)" % sent)
	TestLib.check(ev == null or ev.events.size() == events0, "the city's event scheduler is paused inside (%d events)" % (ev.events.size() if ev != null else 0))
	var called := em.call_reinforcement(ig.actors.guards[0]) if not ig.actors.guards.is_empty() else null
	TestLib.check(called == null, "a wounded guard's radio call brings nobody from the street")
	_leave_all()


# --- 6: a room does not kill a hero who looks round ---------------------------------------------------------------------------------

func _rooms_do_not_kill() -> void:
	var ig := InteriorGameplay.instance
	if ig == null:
		return
	var worst := 100.0
	var dead := 0
	var rooms: Array[StringName] = [&"weapons", &"lobby", &"apartment", &"club", &"checkpoint", &"warehouse"]
	for type in rooms:
		for mode in ["idle", "walk"]:
			_leave_all()
			p.max_hp = 100.0
			p.hp = 100.0
			p.invuln = 0.0
			TestLib.check(ig.test_enter(type).begins_with("INSIDE"), "the hero goes into a %s (%s)" % [str(type), mode])
			var min_hp := 100.0
			var t := 0.0
			var secs := 14.0 if mode == "walk" else 18.0
			while t < secs and not p.is_dead():
				await _frame()
				t += _dt
				if mode == "walk":
					Input.action_press(&"move_forward")
				min_hp = minf(min_hp, p.hp)
			Input.action_release(&"move_forward")
			worst = minf(worst, min_hp)
			if p.is_dead() or Game.state == &"dead":
				dead += 1
				print("  DEAD in %s %s" % [str(type), mode])
	_leave_all()
	TestLib.check(dead == 0, "no hero died in %d visits of %d s to six rooms, idle and walking (worst health %.0f)" % [rooms.size() * 2, 18, worst])
	# a shop's guard is a bystander: he never turns on a customer who has not fired
	TestLib.check(ig.test_enter(&"weapons").begins_with("INSIDE"), "the arms dealer's shop")
	var shop_guard_hostile := false
	await _wait(10.0)
	for g in ig.actors.guards:
		shop_guard_hostile = shop_guard_hostile or (is_instance_valid(g) and g.aware)
	TestLib.check(not shop_guard_hostile, "the shop's own guard stays a bystander while the customer does not fire")
	_leave_all()


# --- 6: one blow per visit is forgiven -------------------------------------------------------------------------------------------

func _mercy() -> void:
	var ig := InteriorGameplay.instance
	if ig == null:
		return
	_leave_all()
	p.max_hp = 100.0
	p.hp = 100.0
	p.invuln = 0.0
	TestLib.check(ig.test_enter(&"lobby").begins_with("INSIDE"), "the hero goes into a lobby for the rescue check")
	p.invuln = 0.0
	p.hp = 10.0
	p.damage(500.0, p.global_position + Vector3(0.0, 0.0, 3.0))
	TestLib.check(not p.is_dead() and p.hp >= p.max_hp * InteriorGameplay.MERCY_HP - 1.0, "a killing blow inside leaves the hero on %.0f %% (hp %.0f)" % [InteriorGameplay.MERCY_HP * 100.0, p.hp])
	TestLib.check(p.invuln >= InteriorGameplay.MERCY_INVULN - 0.5, "...with %.0f s of cover (invuln %.1f)" % [InteriorGameplay.MERCY_INVULN, p.invuln])
	p.invuln = 0.0
	p.hp = 10.0
	p.damage(500.0, p.global_position + Vector3(0.0, 0.0, 3.0))
	TestLib.check(p.is_dead() or Game.state == &"dead", "the second blow of the same visit is a real death")
	_leave_all()
	await _wait(0.2)
	p.max_hp = 100.0
	p.hp = 100.0
	p.invuln = 0.0
	# a street death is untouched by the rescue
	p.damage(500.0, p.global_position + Vector3(0.0, 0.0, 3.0))
	TestLib.check(p.is_dead() or Game.state == &"dead", "on the street a killing blow still kills")
	_leave_all()
	await _wait(0.2)


# --- 7: what the plate says inside ---------------------------------------------------------------------------------------------------

func _plate_inside() -> void:
	var ig := InteriorGameplay.instance
	if ig == null:
		return
	_leave_all()
	p.invuln = 0.0
	p.max_hp = 1000.0
	p.hp = 1000.0
	var street := [{"kind": "reach", "pos": [-200.0, 0.0], "obj": "Cross the trading floor to the beacon"}, {"kind": "reach", "pos": [-300.0, 0.0], "obj": "Go on"}]
	_chapter(street)
	camp.tick(0.1)
	await _wait(0.1)
	for type: StringName in [&"bar", &"clinic", &"tech", &"bodega", &"med_bay", &"server_room"]:
		ig.done.clear()
		TestLib.check(ig.test_enter(type).begins_with("INSIDE"), "the hero goes into a %s" % str(type))
		await _wait(0.5)
		var line := hud._campaign_line()
		TestLib.check(line == "LEAVE THE BUILDING TO CONTINUE" and not line.contains(" M"), "%s: no job in the room, the plate says to leave and shows no street distance ('%s')" % [str(type), line])
		if type == &"bar":
			var use := {}
			for b: Dictionary in TouchControls.BUTTONS:
				if b["action"] == &"interact":
					use = b
			var vend := InteriorGameplay.prompt
			var label := hud.touch._label_of(use)
			TestLib.check(vend == "" or label == vend.split(" ")[0], "inside, the USE button says what it does ('%s' for the prompt '%s')" % [label, vend])
		ig.leave(true)
		await _wait(0.2)
	for type: StringName in [&"lobby", &"apartment", &"club", &"checkpoint"]:
		ig.done.clear()
		TestLib.check(ig.test_enter(type).begins_with("INSIDE"), "the hero goes into a %s with a job" % str(type))
		var l2 := InteriorGameplay.hud_line
		TestLib.check(l2 != "" and not l2.contains("TRADING FLOOR") and hud._campaign_line() == "", "%s: the room's own job owns the plate from the first frame ('%s')" % [str(type), l2])
		ig.leave(true)
		await _wait(0.2)
	# the same with the step still armed (the guide waits for the hero to come out): a room with a job keeps the plate, one without says LEAVE
	camp.abort()
	camp.enabled = true
	camp.start_custom({"id": "director_b2", "clears_sector": false, "steps": street})
	await _wait(0.2)
	ig.done.clear()
	TestLib.check(ig.test_enter(&"lobby").begins_with("INSIDE"), "the hero goes into a lobby while the next step is armed (%s)" % str(camp.state))
	await _wait(0.3)
	TestLib.check(InteriorGameplay.hud_line != "" and hud._campaign_line() == "", "an armed step does not hide the room's job (plate '%s')" % hud._campaign_line())
	ig.leave(true)
	await _wait(0.2)
	TestLib.check(ig.test_enter(&"bar").begins_with("INSIDE"), "the hero goes into a bar while the next step is armed")
	await _wait(0.3)
	TestLib.check(hud._campaign_line().begins_with("LEAVE"), "...a room without a job says LEAVE ('%s')" % hud._campaign_line())
	ig.leave(true)
	camp.abort()
	camp.enabled = false
	await _wait(0.2)
	# a door step whose building is another one: still not a street distance
	_chapter([{"kind": "enter_interior", "interior": "warehouse", "obj": "Enter the warehouse", "pos": [-200.0, 0.0]}, {"kind": "reach", "pos": [-300.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	await _wait(0.1)
	TestLib.check(ig.test_enter(&"bar").begins_with("INSIDE"), "the hero goes into the wrong building for a door step")
	await _wait(0.3)
	var wrong := hud._campaign_line()
	TestLib.check(wrong == "LEAVE THE BUILDING TO CONTINUE" or not wrong.contains(" M"), "a door step inside the wrong building shows no distance ('%s')" % wrong)
	ig.leave(true)
	camp.abort()
	_leave_all()
	await _wait(0.2)


# --- 14: the hack ---------------------------------------------------------------------------------------------------------------------

func _hold_heat() -> void:
	_leave_all()
	p.max_hp = 1000.0
	p.hp = 1000.0
	p.invuln = 0.0
	_chapter([{"kind": "hack", "pos": [p.global_position.x + 4.0, p.global_position.z], "obj": "Hack the ledger node", "radius": 12.0}, {"kind": "reach", "pos": [-100.0, 0.0], "obj": "Go on"}])
	camp.tick(0.1)
	camp.tick(2.0)
	await _wait(0.2)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"hack", "the hack step runs (%s)" % str(camp.state))
	Game.heat = 4.6                                               # the step's own wave plus a crowd's casualties
	camp.tick(0.1)
	TestLib.check(Game.heat <= CampaignRunner.HOLD_HEAT_CAP + 0.01 and Game.heat < 2.0, "a hack never holds the heat at patrol-car level (%.2f stars)" % Game.heat)
	var h0 := Game.heat
	for i in 20:
		camp.tick(0.5)
	TestLib.check(Game.heat <= h0 - 0.4 or Game.heat <= 0.05, "10 s on the ring bleed the heat off (%.2f -> %.2f)" % [h0, Game.heat])
	camp.abort()
	Game.heat = 0.0
	_leave_all()


# --- 13: the live fight -------------------------------------------------------------------------------------------------------------------

func _fight() -> void:
	_leave_all()
	var mgr := Game.enemies as EnemyManager
	var enc := Encounters.current
	if enc == null:
		TestLib.check(false, "the encounter director exists")
		return
	camp.abort()
	mgr.patrol_groups().clear()
	mgr.clear()
	p.max_hp = 400.0
	p.hp = 400.0
	p.invuln = 0.0
	p.weapon.switch_to(&"carbine", true)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	enc.enabled = true
	enc.reset()
	enc.play_t = Encounters.FIRST_DELAY - 2.0
	Operative.round_stats = {"fired": 0, "hit": 0, "near": 0}
	var bot := FightBot.new()
	bot.setup(p)
	bot.aim_error = 0.01
	var classes := {}
	var roles := {}
	var most_alive := 0
	var burst_seen := 0
	var t := 0.0
	var started := -1.0
	while t < 75.0:
		await _frame()
		t += _dt
		var hp := p.hp
		bot.step(_dt)
		p.invuln = 0.0
		p.hp = hp                                                   # the bot heals the hero on every step: his health is the test's own
		p.max_hp = 400.0
		for e in mgr.list:
			if e.active and not e.dead:
				if e is Operative:
					var o := e as Operative
					if not e.humanoid.is_empty():
						classes[str(e.humanoid["class"])] = true
					if o.tactic_role != &"":
						roles[str(o.tactic_role)] = true
					if o._burst_left >= 2:
						burst_seen += 1
		most_alive = maxi(most_alive, mgr.alive_count())
		if started < 0.0 and enc.waves_started >= 1:
			started = t
		if started > 0.0 and t - started > 30.0 and Operative.round_stats["fired"] >= 30:
			break
		if p.hp <= 1.0:
			p.hp = 400.0
	bot.finish()
	var rs := Operative.round_stats
	var fired: int = rs["fired"]
	var hit: int = rs["hit"]
	var near: int = rs["near"]
	print("ROUND2 FIGHT: enemy rounds %d, hit %d, near misses %d, looks %s, roles %s, most alive %d, hero shots %d hits %d kills %d" % [fired, hit, near, str(classes.keys()), str(roles.keys()), most_alive, bot.shots, bot.hits, bot.kills])
	TestLib.check(fired >= 12, "the patrol fired %d rounds at the hero" % fired)
	var rate := float(hit) / maxf(float(fired), 1.0)
	TestLib.check(rate > 0.0 and rate < 0.6, "not every round hits and not every round misses: %.0f %% of %d" % [rate * 100.0, fired])
	TestLib.check(near >= 2 and near >= int(fired * 0.15), "misses that pass close are seen: %d near misses of %d rounds" % [near, fired])
	TestLib.check(burst_seen > 0, "the troopers fire bursts")
	TestLib.check(roles.size() >= 2 or most_alive < 3, "the squad plays more than one role (%s)" % str(roles.keys()))
	TestLib.check(classes.size() >= 2 or most_alive < 3, "the troopers in the fight show %d different looks" % classes.size())
	TestLib.check(bot.shots >= 20, "the hero shot back (%d rounds)" % bot.shots)
	enc.enabled = false
	mgr.clear()
	Game.heat = 0.0
	Input.action_release(&"fire")
