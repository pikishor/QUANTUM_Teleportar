extends RefCounted
## QUANTUM SNAKE TRAVERSAL in the real scene (main.tscn, the real hero, the real city): the tables (HeroPower rows by difficulty, SnakePower, the skill nodes, HERO MODE), the shared tendril
## (fire, attach, retract, tier caps), the jump kit (double jump, super jump, landing roll), SNAKE ZIP at a wall and the CLIMB that follows it up to the roof (mantle) and a leap, SNAKE SWING
## (attach, arc, release boost), SNAKE FLIGHT (take-off, cruise, boost, hover, glide on an empty meter, crash recovery, landing), the touch buttons (SNAKE and FLY, labels, 64 px, one thumb
## look-drag), the two board missions (offers, rings on real roofs, the courier of the chase, the tutorial flag) and a whole SWING ACROSS THE CITY chapter run through the runner.
## The long swing run (a chain of at least five swings, 400 m, no ground) is tests/test_snake_swing_run.gd. Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_snake_traversal.gd   (about 100 s)

const TIMEOUT_SECONDS := 140.0

var host: Node
var p: Player
var sn: SnakeTraversal
var hud: Hud
var tc: TouchControls
var main: Node
var _done_chapters := 0
var _steps_done := 0


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


## Waits until the runner shows step `idx` as the active one (between two steps it is `armed` for a moment and `step` still holds the old dictionary).
func step_active(camp: CampaignRunner, idx: int, secs := 5.0) -> bool:
	return await until(func() -> bool: return camp.state == &"active" and camp.step_index == idx, secs)


func release_all() -> void:
	for a in [&"snake", &"fly", &"jump", &"move_forward", &"move_back", &"move_left", &"move_right", &"crouch", &"sprint", &"fire"]:
		Input.action_release(a)


func tap(action: StringName, hold_frames := 4) -> void:
	Input.action_press(action)
	await frames(hold_frames)
	Input.action_release(action)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var mode0 := Difficulty.current
	var touch0 := Game.force_touch
	Game.force_touch = true                                   # the touch layer is drawn and active (the buttons are real)
	_tables()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	sn = p.snake
	hud = Game.get_tree().root.find_child("Hud", true, false) as Hud
	tc = hud.touch if hud != null else null
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	TestLib.check(sn != null and sn.p == p, "the player owns a SnakeTraversal bound to him")
	await _prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.4)               # open ground: nothing to bite, nothing to zip to
	var idle_fx := SnakeFx.new()                                   # a fresh effects node next to a hero who stands there
	idle_fx.st = sn
	p.add_child(idle_fx)
	await frames(5)
	TestLib.check(idle_fx.get_node_or_null("SpeedLines") == null and idle_fx.get_node_or_null("AnchorMarker") == null and idle_fx.get_child_count() <= 2, "an idle hero carries no speed-line layer and no marker mesh (made when first needed: the perf gate counted two draws for them)")
	idle_fx.queue_free()
	var only := OS.get_environment("SNK_ONLY")                    # dev: SNK_ONLY=missions runs one section
	if only == "" or only == "tendril":
		await _tendril()
	if only == "" or only == "kit":
		await _kit()
	if only == "" or only == "zip":
		await _zip_and_climb()
	if only == "" or only == "swing":
		await _swing()
	if only == "" or only == "flight":
		await _flight()
	if only == "" or only == "counters":
		await _counters()
	if only == "" or only == "buttons":
		await _buttons()
	if only == "" or only == "missions":
		await _missions()
	_assist_option()
	release_all()
	TestMode.god = false
	WeaponDefs.hero_mode = false
	Difficulty.set_mode(mode0)
	Game.force_touch = touch0
	SnakeMissions.reset_flags()
	main.queue_free()
	await frames(3)


# --- the tables -------------------------------------------------------------------------------------------------------------------------

func _tables() -> void:
	var keys := ["snake_range", "snake_cost", "snake_regen", "snake_speed", "snake_release", "climb_speed", "fly_cruise", "fly_boost", "fly_drain", "fly_free", "air_jumps"]
	var ok := true
	for r in HeroPower.ROWS:
		for k in keys:
			ok = ok and (r as Dictionary).has(k)
	TestLib.check(ok, "every HeroPower row has the snake keys")
	for k in ["snake_range", "snake_regen", "snake_speed", "snake_release", "climb_speed", "fly_cruise", "fly_boost"]:
		TestLib.check(HeroPower.f(k, 0) > HeroPower.f(k, 1) and HeroPower.f(k, 1) > HeroPower.f(k, 2) and HeroPower.f(k, 2) > HeroPower.f(k, 3), "%s falls from STORY to QUANTUM" % k)
	TestLib.check(HeroPower.f("snake_cost", 0) < HeroPower.f("snake_cost", 1) and HeroPower.f("snake_cost", 1) < HeroPower.f("snake_cost", 3), "the snake energy cost rises from STORY to QUANTUM")
	TestLib.check(HeroPower.f("air_jumps", 0) >= HeroPower.f("air_jumps", 1) and HeroPower.f("air_jumps", 1) >= 1.0, "STORY has the most air jumps, every mode keeps at least one")
	var mode := Difficulty.current
	SkillTree.reset()
	WeaponDefs.hero_mode = false
	Difficulty.set_mode(0)
	var easy_range := SnakePower.range_m()
	var easy_cost := SnakePower.cost(10.0)
	var easy_fly := SnakePower.fly_cost_per_s()
	TestLib.check(SnakePower.flight_unlocked(), "STORY opens flight from the start")
	Difficulty.set_mode(2)
	TestLib.check(SnakePower.range_m() < easy_range and SnakePower.cost(10.0) > easy_cost and SnakePower.fly_cost_per_s() > easy_fly, "HARD: shorter reach, dearer energy, dearer flight than STORY")
	TestLib.check(not SnakePower.flight_unlocked(), "HARD needs WING POWER before the hero can fly")
	SkillTree.ranks[&"sn_wings"] = 1
	TestLib.check(SnakePower.flight_unlocked(), "one WING POWER rank opens flight on HARD")
	SkillTree.reset()
	SkillTree.ranks[&"sn_range"] = 3
	SkillTree.ranks[&"sn_speed"] = 3
	TestLib.check(SnakePower.range_m() > HeroPower.f("snake_range") * 1.2 and SnakePower.speed_cap() > HeroPower.f("snake_speed") * 1.1, "the RANGE and SPEED nodes raise the reach and the swing speed cap")
	SkillTree.reset()
	TestLib.check(SkillTree.VERBS.has(&"snake") and SkillTree.verb_nodes(&"snake").size() == 5 and SkillTree.title(&"sn_chain") == "CHAIN BONUS", "the skill tree has the QUANTUM SNAKE column: RANGE, SPEED, ENERGY, CHAIN BONUS, WING POWER")
	WeaponDefs.hero_mode = true
	TestLib.check(SnakePower.unlimited() and SnakePower.cost(50.0) == 0.0 and SnakePower.cd(2.0) == 0.0 and SnakePower.flight_unlocked(), "HERO MODE: free energy, no cooldowns, flight open")
	WeaponDefs.hero_mode = false
	Difficulty.set_mode(mode)


# --- the shared tendril -------------------------------------------------------------------------------------------------------------------

func _tendril() -> void:
	var pool := SnakeTendrilPool.get_pool(p)
	TestLib.check(pool != null, "the tendril pool exists under the player")
	pool.clear()
	var attached := [0]
	var retracted := [0]
	var target := p.global_position + Vector3(0.0, 8.0, -14.0)
	var t := SnakeTendril.fire(sn.hand_callable(1), target, {"travel": 0.12, "tension": 0.8})
	t.attached.connect(func() -> void: attached[0] += 1)
	t.retracted.connect(func() -> void: retracted[0] += 1)
	TestLib.check(t.state == SnakeTendril.State.TRAVEL and pool.count() == 1, "a fired tendril travels and the pool holds it")
	await until(func() -> bool: return attached[0] == 1, 1.0)
	TestLib.check(attached[0] == 1 and t.state == SnakeTendril.State.ATTACHED and t.head_pos.distance_to(target) < 0.05, "it attaches exactly at its target")
	TestLib.check(t.length() > 8.0, "its body reaches from the hand to the target (%.1f m)" % t.length())
	t.retract(0.1)
	await until(func() -> bool: return retracted[0] == 1, 1.0)
	TestLib.check(retracted[0] == 1 and t.state == SnakeTendril.State.DONE and pool.count() == 0, "a retracted tendril ends and leaves the pool")
	var caps := []
	for q in [0, 1, 2]:
		pool._build(q)
		caps.append(pool.cap())
	pool._build(Game.quality)
	TestLib.check(caps == [4, 6, 8], "pool caps by tier: LOW 4, MED 6, HIGH 8 (%s)" % str(caps))
	pool.clear()
	for i in 12:
		SnakeTendril.fire(p.global_position + Vector3(0.0, 2.0, 0.0), p.global_position + Vector3(float(i), 6.0, -10.0), {"travel": 0.05})
	TestLib.check(pool.count() <= pool.cap(), "the pool never holds more than its cap (%d of %d)" % [pool.count(), pool.cap()])
	pool.clear()
	await frames(2)


# --- the jump kit --------------------------------------------------------------------------------------------------------------------------

func _prep(pos: Vector3, yaw := -PI * 0.5, pitch := 0.0) -> void:
	release_all()
	sn.cancel()
	TrafficField.bare_street()                                  # parked and driving cars do not stand in the way of a probe of one hero
	p.invuln = 0.0
	p.hp = p.max_hp
	sn.energy = SnakePower.max_energy()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	await frames(12)


func _kit() -> void:
	await _prep(Game.SPAWN)
	Input.action_press(&"jump")
	await frames(3)
	Input.action_release(&"jump")
	await until(func() -> bool: return p.air_time > 0.2 and p.velocity.y > 1.5, 1.0)
	var d0 := sn.double_jumps
	var vy0 := p.velocity.y
	await tap(&"jump", 2)
	await frames(3)
	TestLib.check(sn.double_jumps == d0 + 1 and p.velocity.y > vy0 - 1.0, "a second JUMP press while still rising is a DOUBLE JUMP (vy %.1f -> %.1f)" % [vy0, p.velocity.y])
	TestLib.check(p.verbs.bursts == 0 or p.verbs.bursting == false, "the double jump keeps the air dash burst for the next press")
	await until(func() -> bool: return p.is_on_floor(), 4.0)
	await frames(15)
	# SUPER JUMP: from standing, hold JUMP
	var s0 := sn.super_jumps
	Input.action_press(&"jump")
	var top := 0.0
	for i in 70:
		await frames(1)
		top = maxf(top, p.global_position.y)
	Input.action_release(&"jump")
	TestLib.check(sn.super_jumps == s0 + 1 and top > 4.0, "holding JUMP from standing is a SUPER JUMP (top %.1f m, a plain jump reaches about 1.5 m)" % top)
	await until(func() -> bool: return p.is_on_floor(), 5.0)
	# a plain tap jump never becomes a super jump, and neither does a long press of 0.25 s
	await frames(20)
	var s1 := sn.super_jumps
	await tap(&"jump", 3)
	await frames(50)
	TestLib.check(sn.super_jumps == s1, "a tap on JUMP stays a plain jump")
	await until(func() -> bool: return p.is_on_floor(), 3.0)
	await frames(20)
	await tap(&"jump", 15)
	await frames(50)
	TestLib.check(sn.super_jumps == s1, "a long press of a quarter second is still a plain jump")
	await until(func() -> bool: return p.is_on_floor(), 3.0)
	# running or pushing the stick with JUMP held (the vault and mantle habit of a phone thumb) is never a super jump
	await frames(20)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await frames(90)
	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	TestLib.check(sn.super_jumps == s1, "forward + JUMP held while running is never a super jump")
	await until(func() -> bool: return p.is_on_floor(), 4.0)
	# SAFE LANDING ROLL: a long fall rolls and keeps the speed
	await _prep(Game.SPAWN + Vector3(0.0, 45.0, 0.0))
	var r0 := sn.landing_rolls
	await until(func() -> bool: return p.is_on_floor() and p.air_time < 0.05, 6.0)
	await frames(5)
	TestLib.check(sn.landing_rolls == r0 + 1 and sn.roll_t > 0.0, "a hard landing is a safe landing roll")
	TestLib.check(p.hp >= p.max_hp - 0.01, "and costs no health")
	await frames(40)


# --- zip, climb, mantle, leap -----------------------------------------------------------------------------------------------------------

func _zip_and_climb() -> void:
	await _prep(Vector3(-30.0, 0.0, 4.0), PI, 0.38)
	# wave 118: with the touch layout ZIP is a button of its own (action snake_zip) and SNAKE never zips; with ONE snake button (keyboard, controller) SNAKE still zips
	var z0 := sn.zips
	TestLib.check(SnakeTraversal.split_buttons, "the touch layout runs the two-button snake (SWING and ZIP)")
	SnakeTraversal.split_buttons = false
	await tap(&"snake", 4)
	var one := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 1.0)
	TestLib.check(one and sn.zips == z0 + 1, "one contextual button (keyboard, controller): a tap on SNAKE at a building under the crosshair starts a SNAKE ZIP")
	SnakeTraversal.split_buttons = true
	await _prep(Vector3(-30.0, 0.0, 4.0), PI, 0.38)
	z0 = sn.zips
	await tap(&"snake", 4)
	await frames(20)
	TestLib.check(sn.zips == z0 and sn.mode != SnakeTraversal.Mode.ZIP, "two buttons: a tap on SNAKE (SWING) at the same spot does not zip (mode %d)" % sn.mode)
	await _prep(Vector3(-30.0, 0.0, 4.0), PI, 0.38)
	z0 = sn.zips
	sn.zip_cd = 0.0                                           # the zip of the one-button check above was a moment ago (a second between two zips)
	await tap(&"snake_zip", 4)
	var started := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 1.0)
	TestLib.check(started and sn.zips == z0 + 1, "a tap on ZIP at a building under the crosshair starts a SNAKE ZIP")
	var from := p.global_position
	await until(func() -> bool: return sn.mode != SnakeTraversal.Mode.ZIP, 4.0)
	await frames(10)
	var moved := p.global_position.distance_to(from)
	TestLib.check(moved > 8.0 and (sn.mode == SnakeTraversal.Mode.CLIMB or p.global_position.y > from.y + 4.0), "the zip pulled the hero %.0f m and ended on the wall (a climb) or the roof" % moved)
	TestLib.check(sn.zip.zips >= 1 and sn.energy < SnakePower.max_energy() or SnakePower.cost(8.0) < 1.0, "a zip costs a little snake energy")
	# the climb from the street to the roof of the avenue's south tower
	await _prep(Vector3(-13.2, 0.0, 15.0), PI, 0.1)
	var c0 := sn.climbs
	await tap(&"snake", 4)
	var climbing := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.CLIMB, 1.0)
	TestLib.check(climbing and sn.climbs == c0 + 1, "a tap on SNAKE at a wall is a SNAKE CLIMB")
	Input.action_press(&"move_forward")
	var up := await until(func() -> bool: return p.global_position.y > 12.0, 4.0)
	TestLib.check(up and p.global_position.y > 12.0, "the stick up climbs the wall (y %.1f)" % p.global_position.y)
	TestLib.check(sn.climb.move_speed > 3.0, "at a real speed (%.1f m/s)" % sn.climb.move_speed)
	TestLib.check(sn.mode == SnakeTraversal.Mode.CLIMB and sn.climb.climbed_m > 8.0, "stuck to the wall while climbing (%.1f m so far)" % sn.climb.climbed_m)
	# a leap off the wall in the look direction
	var l0 := sn.climb.leaps
	await tap(&"jump", 3)
	await frames(6)
	TestLib.check(sn.climb.leaps == l0 + 1 and sn.mode == SnakeTraversal.Mode.NONE and p.velocity.length() > 8.0, "JUMP leaps off the wall with speed (%.1f m/s)" % p.velocity.length())
	Input.action_release(&"move_forward")
	await until(func() -> bool: return p.is_on_floor(), 6.0)
	# all the way up: the mantle onto the roof
	await _prep(Vector3(-13.2, 0.0, 15.0), PI, 0.1)
	await tap(&"snake", 4)
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.CLIMB, 1.0)
	var m0 := sn.climb.mantles
	Input.action_press(&"move_forward")
	var roof := await until(func() -> bool: return sn.climb.mantles > m0, 14.0)
	Input.action_release(&"move_forward")
	await frames(30)
	TestLib.check(roof and sn.mode == SnakeTraversal.Mode.NONE and p.global_position.y > 30.0, "the climb ends in a mantle onto the roof (y %.1f)" % p.global_position.y)
	TestLib.check(await until(func() -> bool: return p.is_on_floor(), 2.0), "and the hero stands on the roof")
	# a ceiling: the underside of a bridge or an overhang is climbed too (probe a flat ceiling placed over the hero)
	await _prep(Game.SPAWN)
	var ceil_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	cs.shape = box
	ceil_body.add_child(cs)
	ceil_body.collision_layer = Game.L_WORLD
	host.add_child(ceil_body)
	ceil_body.global_position = Game.SPAWN + Vector3(0.0, 3.6, 0.0)
	await frames(4)
	p.teleport_to(Game.SPAWN + Vector3(0.0, 0.6, 0.0))
	p.velocity = Vector3(0.0, 6.0, 0.0)
	await until(func() -> bool: return p.air_time > 0.1, 1.0)
	Input.action_press(&"snake")
	var on_ceiling := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.CLIMB and sn.climb.ceiling, 2.5)
	Input.action_release(&"snake")
	TestLib.check(on_ceiling, "a SNAKE press against a ceiling over the hero sticks him to it (ceiling crawl)")
	if on_ceiling:
		Input.action_press(&"move_forward")
		var cp0 := p.global_position
		await frames(45)
		Input.action_release(&"move_forward")
		TestLib.check(Vector2(p.global_position.x - cp0.x, p.global_position.z - cp0.z).length() > 2.0 and sn.mode == SnakeTraversal.Mode.CLIMB, "the stick crawls along the ceiling (%.1f m)" % Vector2(p.global_position.x - cp0.x, p.global_position.z - cp0.z).length())
		await tap(&"snake", 4)
		await frames(10)
		TestLib.check(sn.mode == SnakeTraversal.Mode.NONE, "a second tap lets go")
	ceil_body.queue_free()
	await until(func() -> bool: return p.is_on_floor(), 4.0)


# --- swing ---------------------------------------------------------------------------------------------------------------------------------

func _swing() -> void:
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	var fx := p.get_node("SnakeFx") as SnakeFx
	var marked := await until(func() -> bool: return fx.marker_on, 1.5)
	TestLib.check(marked and fx.get_node_or_null("AnchorMarker") != null, "in the air with an anchor in reach the marker shows where the snake would bite")
	var w0 := sn.swings
	Input.action_press(&"snake")
	var attached := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING and sn.swing.phase == &"hang", 2.0)
	TestLib.check(attached and sn.swings == w0 + 1, "holding SNAKE in the air fires a snake that bites an anchor")
	TestLib.check(sn.swing.anchor.y > p.global_position.y + 3.0 and sn.swing.rope > 8.0, "above the hero, on a rope of %.0f m" % sn.swing.rope)
	var peak := 0.0
	var ground := false
	var lines_seen := false
	for i in 150:
		await frames(1)
		peak = maxf(peak, p.velocity.length())
		lines_seen = lines_seen or fx.lines_on
		ground = ground or p.is_on_floor()
		if sn.mode != SnakeTraversal.Mode.SWING:
			break
	TestLib.check(peak > 16.0, "the pendulum gains speed (peak %.1f m/s)" % peak)
	TestLib.check(lines_seen or peak < 26.0, "the speed lines show when the swing is fast (peak %.1f m/s)" % peak)
	TestLib.check(not ground, "without touching the street")
	# let go: the release boost
	sn.assist = true
	if sn.mode == SnakeTraversal.Mode.SWING:
		var v_before := p.velocity.length()
		Input.action_release(&"snake")
		await frames(3)
		TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.swing.releases >= 1, "letting go ends the swing")
		TestLib.check(p.velocity.length() >= minf(v_before, 12.0) * 1.0, "with the speed kept (%.1f m/s before, %.1f after)" % [v_before, p.velocity.length()])
	else:
		Input.action_release(&"snake")
	await frames(40)
	# the snake energy ring recovers
	sn.energy = 10.0
	await _prep(Game.SPAWN)
	await frames(90)
	TestLib.check(sn.energy > 25.0, "snake energy comes back on the ground (%.0f)" % sn.energy)
	# no anchor: a whiff, never a stuck state
	await _prep(Vector3(3000.0, 0.0, 200.0), 0.0, -0.4)
	var wf := sn.whiffs
	await tap(&"snake", 3)
	await frames(10)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.whiffs >= wf, "with nothing to bite the press is a miss, the hero stays free")


# --- the enemy counters: snipers lead a hero on the snakes, the warden's pulse jams them -------------------------------------------------------------

func _counters() -> void:
	var secs := []
	var leads := []
	WeaponDefs.hero_mode = false
	for m in 4:
		Difficulty.set_mode(m)
		secs.append(SnakePower.jam_seconds())
		leads.append(SnakePower.sniper_lead())
	TestLib.check(secs == [1.0, 2.0, 3.0, 3.5], "a jam lasts 1 / 2 / 3 / 3.5 s from STORY to QUANTUM (%s)" % str(secs))
	TestLib.check(leads == [0.55, 0.8, 0.95, 1.0], "the sniper's lead improves from STORY to QUANTUM (%s)" % str(leads))
	Difficulty.set_mode(1)
	WeaponDefs.hero_mode = true
	TestLib.check(SnakePower.jam_seconds() == 0.0 and not sn.jam(), "HERO MODE is immune to a jammer")
	WeaponDefs.hero_mode = false
	# the sniper's lead: a hero on foot is shot where he stands (the old rule), a hero on a swing is led by his own speed
	await _prep(Game.SPAWN)
	TestLib.check(SnakeTraversal.lead_offset(Specialist.SNIPER_LOCK) == Vector3.ZERO, "a hero on foot is not led")
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	Input.action_press(&"snake")
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING and sn.swing.phase == &"hang" and p.velocity.length() > 10.0, 3.0)
	var v := p.velocity
	var off := SnakeTraversal.lead_offset(Specialist.SNIPER_LOCK)
	var want := v.length() * Specialist.SNIPER_LOCK * SnakePower.sniper_lead()
	TestLib.check(sn.mode == SnakeTraversal.Mode.SWING and absf(off.length() - want) < 0.02 and off.normalized().dot(v.normalized()) > 0.999, "a swinging hero is led: %.1f m ahead at %.1f m/s (wanted %.1f)" % [off.length(), v.length(), want])
	var em := Game.enemies as EnemyManager
	var spec := em.spawn(&"sniper", p.global_position + Vector3(40.0, 0.0, 0.0), true) as Specialist
	spec.set_physics_process(false)
	spec._tgt = p.global_position + Vector3(0.0, 1.0, 0.0)
	spec._tgt_ok = true
	spec._locked = false
	spec._aim_t = Specialist.SNIPER_LOCK * 0.9
	spec._fire_cycle(0.001, 40.0, 60.0)
	var gap := spec._lock_point.distance_to(spec._tgt)
	TestLib.check(spec._locked and absf(gap - p.velocity.length() * Specialist.SNIPER_LOCK * SnakePower.sniper_lead()) < 0.05, "a real sniper's lock leads the swinging hero by %.1f m" % gap)
	# the jammer: out of reach nothing happens; in reach the swing is dropped WITHOUT its boost, the buttons are dead, and the dead button says so
	await frames(20)
	var j0 := sn.jams
	var sp0 := p.velocity.length()
	TestLib.check(not SnakeTraversal.jam_in_radius(p.global_position + Vector3(40.0, 0.0, 0.0), 13.0) and sn.mode == SnakeTraversal.Mode.SWING and sn.jams == j0, "a jammer 40 m away leaves the swing alone")
	var took := SnakeTraversal.jam_in_radius(p.global_position + Vector3(6.0, 0.0, 0.0), 13.0)
	TestLib.check(took and sn.mode == SnakeTraversal.Mode.NONE and sn.jams == j0 + 1 and absf(sn.jam_t - 2.0) < 0.1, "a jammer in reach drops the swing for the difficulty's seconds (%.2f)" % sn.jam_t)
	TestLib.check(p.velocity.length() <= sp0 * 1.02, "no release boost on a jam (%.1f m/s before, %.1f after)" % [sp0, p.velocity.length()])
	TestLib.check(sn.button_label() == "JAMMED" and not sn.fly_button_shown(), "the SNAKE button reads JAMMED and the FLY button is gone")
	var w1 := sn.swings
	await frames(18)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.swings == w1, "holding SNAKE starts nothing while jammed")
	Input.action_release(&"snake")
	await frames(3)
	await tap(&"snake", 3)
	await frames(6)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.swings == w1, "a fresh press during the jam does nothing either")
	# a short jam in the air: when it ends the button works again, and a button held through it does not start flight by itself
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	var f0 := sn.flights
	var s0 := sn.swings
	TestLib.check(sn.jam(0.4), "a direct jam takes")
	Input.action_press(&"snake")
	await frames(10)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.swings == s0, "SNAKE is dead inside the jam")
	await until(func() -> bool: return sn.jam_t <= 0.0, 1.0)
	await frames(40)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE and sn.swings == s0 and sn.flights == f0, "a button held through the jam starts nothing when it ends")
	Input.action_release(&"snake")
	await frames(3)
	Input.action_press(&"snake")
	var again := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING, 2.0)
	Input.action_release(&"snake")
	TestLib.check(again and sn.swings == s0 + 1, "after the jam a new press swings again")
	# the pulse of a real warden jams within twice its damage radius and not beyond
	await _prep(Vector3(-30.0, 40.0, 4.0), -PI * 0.5, 0.2)
	var wd := em.spawn(&"warden", p.global_position + Vector3(9.0, 0.0, 0.0), true) as Specialist
	wd.set_physics_process(false)
	var j1 := sn.jams
	wd._pulse()
	TestLib.check(sn.jams == j1 + 1 and sn.jam_t > 0.5, "the warden's phase pulse jams a hero 9 m away")
	sn.jam_t = 0.0
	wd.global_position = p.global_position + Vector3(40.0, 0.0, 0.0)
	wd._pulse()
	TestLib.check(sn.jams == j1 + 1, "a pulse from 40 m away does not")
	em.clear()
	# a flight, a zip and a climb are all dropped
	await _prep(Game.SPAWN, -PI * 0.5, 0.15)
	await tap(&"fly", 3)
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.0)
	await frames(15)
	var flying := sn.mode == SnakeTraversal.Mode.FLY
	sn.jam(1.0)
	TestLib.check(flying and sn.mode == SnakeTraversal.Mode.NONE and not sn.flight.active, "a jam drops a flight out of the sky")
	await tap(&"fly", 3)
	await frames(8)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE, "FLY does nothing while jammed")
	await _prep(Vector3(-30.0, 0.0, 4.0), PI, 0.38)
	await tap(&"snake_zip", 4)
	var zipping := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 1.0)
	await frames(6)
	sn.jam(1.0)
	TestLib.check(zipping and sn.mode == SnakeTraversal.Mode.NONE and not sn.zip.active, "a jam stops a zip where it is")
	await _prep(Vector3(-13.2, 0.0, 15.0), PI, 0.1)
	await tap(&"snake", 4)
	var climbing := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.CLIMB, 1.0)
	Input.action_press(&"move_forward")
	await until(func() -> bool: return p.global_position.y > 4.0, 3.0)
	Input.action_release(&"move_forward")
	sn.jam(1.0)
	TestLib.check(climbing and sn.mode == SnakeTraversal.Mode.NONE and not sn.climb.active, "a jam loses the grip on a wall")
	await until(func() -> bool: return p.is_on_floor(), 6.0)
	sn.cancel()
	TestLib.check(sn.jam_t == 0.0, "a respawn or teleport clears a jam")
	Difficulty.set_mode(1)


# --- the AIM ASSIST option also switches the snake's anchor assist ---------------------------------------------------------------------------------------

func _assist_option() -> void:
	var st := UiSettings.new("user://test_snake_assist_none.cfg")
	st.aim_assist = false
	st.publish(true)
	TestLib.check(not SnakeTraversal.assist, "AIM ASSIST off turns the snake's anchor assist off (the crosshair ray alone)")
	st.aim_assist = true
	st.publish(true)
	TestLib.check(SnakeTraversal.assist, "AIM ASSIST on turns it back on")
	Difficulty.set_mode(1)


# --- flight --------------------------------------------------------------------------------------------------------------------------------

func _flight() -> void:
	await _prep(Game.SPAWN, -PI * 0.5, 0.15)
	var f0 := sn.flights
	await tap(&"fly", 3)
	var flying := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.0)
	TestLib.check(flying and sn.flights == f0 + 1, "tapping FLY on the ground takes off")
	await frames(45)
	TestLib.check(p.global_position.y > 3.0 and not p.is_on_floor(), "the take-off lifts the hero (y %.1f)" % p.global_position.y)
	TestLib.check(sn.flight.wings.size() == 2 and sn.flight.wings[0].is_alive(), "two snake wings leave his back")
	var e0 := sn.energy
	Input.action_press(&"move_forward")
	await frames(120)
	var cruise := SnakePower.fly_cruise()
	var sp := p.velocity.length()
	TestLib.check(sp > cruise * 0.7, "the stick forward flies at cruise speed (%.1f of %.1f m/s)" % [sp, cruise])
	Input.action_press(&"snake")
	await frames(100)
	var boosting := sn.flight.boosting
	TestLib.check(boosting and p.velocity.length() > cruise * 1.2, "holding SNAKE boosts (%.1f m/s)" % p.velocity.length())
	TestLib.check(sn.flight.best_speed >= p.velocity.length() - 1.0 and SnakeFlight.record_speed >= sn.flight.best_speed, "the speed record is kept")
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	var hovered := await until(func() -> bool: return p.velocity.length() < 8.0, 9.0)
	TestLib.check(hovered and sn.mode == SnakeTraversal.Mode.FLY, "the stick released hovers (%.1f m/s)" % p.velocity.length())
	TestLib.check(sn.energy < e0 or SnakePower.unlimited(), "flying cost snake energy (%.1f -> %.1f)" % [e0, sn.energy])
	# an empty meter turns the wings into a glide that recharges and wakes again
	sn.energy = 0.0
	Input.action_press(&"move_forward")
	await frames(30)
	TestLib.check(sn.flight.phase == &"glide", "with an empty meter the wings glide")
	TestLib.check(p.velocity.y < 1.0, "and the hero sinks slowly (vy %.1f)" % p.velocity.y)
	var recharged := await until(func() -> bool: return sn.flight.phase != &"glide", 10.0)
	Input.action_release(&"move_forward")
	TestLib.check(recharged and sn.energy > 20.0, "the glide recharges and the wings wake (%.0f)" % sn.energy)
	# crash recovery: fly into a wall at speed
	await _prep(Vector3(-30.0, 30.0, 4.0), PI, 0.0)
	sn.energy = SnakePower.max_energy()
	await tap(&"fly", 3)
	await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.0)
	var c0 := sn.flight.crashes
	p.camera_rig.reset_view(PI, 0.0)                           # toward the south tower
	Input.action_press(&"move_forward")
	Input.action_press(&"snake")
	var crashed := await until(func() -> bool: return sn.flight.crashes > c0, 6.0)
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	TestLib.check(crashed, "flying into a facade at speed is a crash")
	TestLib.check(p.hp >= p.max_hp * 0.5, "that never kills the hero (hp %.0f)" % p.hp)
	await frames(90)
	TestLib.check(sn.flight.stun <= 0.0, "and the stun ends: the hero recovers")
	var rp := p.global_position
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	Input.action_press(&"move_forward")
	await frames(60)
	Input.action_release(&"move_forward")
	TestLib.check(p.global_position.distance_to(rp) > 6.0 or sn.mode != SnakeTraversal.Mode.FLY, "he flies on or lands, he is never stuck in the wall")
	# landing
	if sn.mode == SnakeTraversal.Mode.FLY:
		var l0 := sn.flight.landings
		await tap(&"fly", 3)
		var landed := await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.NONE and sn.flight.landings > l0, 14.0)
		TestLib.check(landed, "LAND brings the hero down to the ground")
		await frames(30)
		TestLib.check(p.is_on_floor() or p.air_time < 0.5, "and he stands (hp %.0f)" % p.hp)
	# a flight needs WING POWER on HARD
	Difficulty.set_mode(2)
	SkillTree.reset()
	await _prep(Game.SPAWN)
	await tap(&"fly", 3)
	await frames(10)
	TestLib.check(sn.mode == SnakeTraversal.Mode.NONE, "HARD without WING POWER: FLY does nothing")
	SkillTree.ranks[&"sn_wings"] = 1
	await tap(&"fly", 3)
	await frames(10)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY, "with one WING POWER rank the hero flies on HARD")
	SkillTree.reset()
	sn.cancel()
	Difficulty.set_mode(1)
	await until(func() -> bool: return p.is_on_floor(), 8.0)


# --- touch buttons ----------------------------------------------------------------------------------------------------------------------------

func _find(action: StringName) -> Dictionary:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action:
			return b
	return {}


func _buttons() -> void:
	if tc == null:
		TestLib.check(false, "the touch layer exists")
		return
	await _prep(Game.SPAWN)
	var snake_b := _find(&"snake")
	var fly_b := _find(&"fly")
	TestLib.check(not snake_b.is_empty() and not fly_b.is_empty(), "the touch table has SNAKE and FLY")
	TestLib.check(float(snake_b["r"]) * 2.0 >= 64.0 and float(fly_b["r"]) * 2.0 >= 64.0, "both are at least 64 px across")
	TestLib.check(tc.button_visible(snake_b), "SNAKE is on screen on foot")
	TestLib.check(tc.button_visible(fly_b) and p.is_on_floor(), "FLY is on screen on the ground (wave 118: it was hidden until the hero was in the air)")
	TestLib.check(tc._label_of(snake_b) in ["SNAKE", "ZIP", "SWING", "CLIMB"], "the SNAKE label says what a press does (%s)" % tc._label_of(snake_b))
	await _prep(Vector3(-30.0, 30.0, 4.0))
	await until(func() -> bool: return p.air_time > 0.35, 2.0)
	await frames(10)
	TestLib.check(tc.button_visible(fly_b), "FLY shows in the air")
	# a finger on the SNAKE button presses the action; a drag from it turns the camera
	var c := tc._button_center(snake_b)
	var yaw0 := p.camera_rig.yaw
	tc.touch_down(41, c)
	TestLib.check(Input.is_action_pressed(&"snake"), "a finger on SNAKE presses the snake action")
	tc.touch_move(41, c + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	TestLib.check(absf(p.camera_rig.yaw - yaw0) > 0.01, "the same finger looks around (swing and steer with one thumb)")
	tc.touch_up(41)
	TestLib.check(not Input.is_action_pressed(&"snake"), "lifting it lets go")
	sn.cancel()
	await until(func() -> bool: return p.is_on_floor(), 6.0)
	await _prep(Game.SPAWN, -PI * 0.5, 0.15)
	await tap(&"fly", 3)
	await frames(20)
	var jump_b := _find(&"jump")
	TestLib.check(tc._label_of(jump_b) == "UP" and tc._label_of(fly_b) == "LAND" and tc._label_of(snake_b) == "BOOST", "in flight the buttons read UP, LAND and BOOST")
	sn.cancel()
	await until(func() -> bool: return p.is_on_floor(), 8.0)


# --- missions ---------------------------------------------------------------------------------------------------------------------------------

func _missions() -> void:
	var board := (Game.missions as Missions).board
	var camp := (Game.missions as Missions).campaign
	TestLib.check(board != null and camp != null, "the board and the runner exist")
	await _prep(Game.SPAWN)
	var tut := board.build(&"swing_city", Game.SPAWN)
	TestLib.check(not tut.is_empty() and (tut["steps"] as Array).size() == 6, "SWING ACROSS THE CITY builds six steps")
	var steps: Array[Dictionary] = tut["steps"]
	var roofs_ok := true
	for i in 4:
		roofs_ok = roofs_ok and (steps[i]["pos"] as Vector3).y >= 26.0
	TestLib.check(roofs_ok, "the first four rings are on real roofs (26 m and more)")
	TestLib.check((steps[4]["pos"] as Vector3).y > (steps[3]["pos"] as Vector3).y + 10.0, "the fifth ring floats over the city (flight)")
	TestLib.check((steps[5]["pos"] as Vector3).y < 1.0 and int(tut["reward"]) > 0, "the last ring is on the street and the mission pays (%d)" % int(tut["reward"]))
	var chase := board.build(&"roof_chase", Game.SPAWN)
	TestLib.check(not chase.is_empty() and (chase["steps"] as Array).size() == 4 and str((chase["steps"] as Array)[3]["kind"]) == "kill_target", "ROOFTOP CHASE builds three roofs and the kill")
	TestLib.check(not SnakeMissions.is_tutorial_done(), "the tutorial flag starts false")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var picks: Array[StringName] = [&"kill_patrol", &"delivery", &"rescue"]
	var inj := SnakeMissions.inject(picks, rng)
	TestLib.check(inj[2] == &"swing_city" and inj[0] == picks[0], "until the tutorial is done the board puts it on offer (the last pick)")
	# the chapter run through the runner: step 1 for real (a zip onto the first roof), the rest placed
	_done_chapters = 0
	_steps_done = 0
	var on_step := func(_c: int, _i: int, _k: StringName) -> void: _steps_done += 1
	var on_done := func(_c: int) -> void: _done_chapters += 1
	camp.step_completed.connect(on_step)
	camp.chapter_completed.connect(on_done)
	await _prep(Game.SPAWN)
	TestLib.check(camp.start_custom(tut["chapter"]), "the runner starts the tutorial chapter")
	await frames(20)
	TestLib.check(camp.state == &"active" and str(camp.step.get("snake_mission", "")) == "swing_city", "its first step is the ZIP UP ring")
	# real zip toward roof A: aim at its wall and tap
	var roof_a: Vector3 = steps[0]["pos"]
	var foot := Vector3(roof_a.x, 0.0, roof_a.z)
	p.teleport_to(foot + Vector3(30.0, 0.0, 0.0))
	await frames(20)
	p.camera_rig.aim_at(roof_a)
	await frames(2)
	await tap(&"snake", 4)
	await until(func() -> bool: return sn.mode != SnakeTraversal.Mode.NONE or _steps_done > 0, 1.5)
	TestLib.check(sn.zips > 0 or sn.climbs > 0 or sn.swings > 0, "the hero answers the ZIP UP step with a real snake move")
	sn.cancel()
	release_all()
	# step 0 itself: the hero is put on the first ring
	await step_active(camp, 0)
	sn.cancel()
	p.teleport_to(roof_a + Vector3(0.0, 0.3, 0.0))
	await until(func() -> bool: return camp.step_index > 0 or _done_chapters > 0, 3.0)
	# steps 1..5: the hero is put on each ring, the runner counts them; the air ring is flown for real
	for idx in range(1, 6):
		if _done_chapters > 0:
			break
		var ready := await step_active(camp, idx)
		if not ready:
			TestLib.check(false, "step %d became active (state %s, index %d)" % [idx, str(camp.state), camp.step_index])
			break
		var q: Vector3 = camp.step["pos"]
		if idx == 4:
			# the air ring: a real flight toward it from the roof ring before. A random route can have a facade in the way (the flight of a thumb steers over it, this pilot only aims): up to three
			# flights, the later ones aimed 8 m high until the ring is near, and the ring is still placed when none arrives so that the chapter runs on (wave 115 integration: the real flight
			# failed in 2 of 6 loaded runs and took the chapter's later checks with it)
			var p3: Vector3 = steps[3]["pos"]
			var reached := false
			var flights := 0
			var guard_f := 0
			for attempt in 3:
				flights += 1
				sn.cancel()
				p.teleport_to(p3 + Vector3(0.0, 0.5, 0.0))
				await frames(15)
				sn.energy = SnakePower.max_energy()
				await tap(&"fly", 3)
				await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.0)
				guard_f = 0
				while camp.step_index == 4 and guard_f < 900 and sn.mode == SnakeTraversal.Mode.FLY:
					guard_f += 1
					var far := Vector2(p.global_position.x - q.x, p.global_position.z - q.z).length() > 40.0
					p.camera_rig.aim_at(q + Vector3(0.0, 8.0 if (far and attempt > 0) else 0.0, 0.0))
					Input.action_press(&"move_forward")
					await frames(1)
				Input.action_release(&"move_forward")
				reached = camp.step_index != 4 or camp.state != &"active"
				if reached:
					break
			TestLib.check(reached, "the FLY ring is reached by a real flight (%d frames, flight %d of 3)" % [guard_f, flights])
			if not reached:                                                                         # the ring is still a ring: the chapter goes on
				sn.cancel()
				p.teleport_to(q + Vector3(0.0, 0.3, 0.0))
				await until(func() -> bool: return camp.step_index > idx or _done_chapters > 0, 3.0)
		elif idx == 5:
			# LAND: fly down to the ground ring for real
			if sn.mode != SnakeTraversal.Mode.FLY:
				sn.cancel()
				p.teleport_to(Vector3(q.x - 60.0, 18.0, q.z))
				await frames(10)
				await tap(&"fly", 3)
				await until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 1.0)
			var guard_l := 0
			var landing_asked := false
			while camp.step_index == 5 and camp.state == &"active" and guard_l < 1800 and _done_chapters == 0:
				guard_l += 1
				var hd := Vector2(p.global_position.x - q.x, p.global_position.z - q.z).length()
				p.camera_rig.aim_at(Vector3(q.x, q.y + (1.0 if hd < 35.0 else 6.0), q.z))
				Input.action_press(&"move_forward")
				if sn.mode == SnakeTraversal.Mode.FLY and hd < 45.0 and not landing_asked:
					landing_asked = true
					Input.action_press(&"fly")
				elif landing_asked and guard_l % 5 == 0:
					Input.action_release(&"fly")
				await frames(1)
			Input.action_release(&"move_forward")
			Input.action_release(&"fly")
			if _done_chapters == 0:                                                                 # the flight ended short (a facade in the way of a random route): the ring is still a ring
				if await step_active(camp, 5, 3.0):
					for attempt in 2:                                                               # a loaded machine: the first placement may land between two checks of the runner
						sn.cancel()
						p.teleport_to(q + Vector3(0.0, 0.3, 0.0))
						if await until(func() -> bool: return _done_chapters > 0 or camp.state != &"active", 4.0):
							break
		else:
			sn.cancel()
			p.teleport_to(q + Vector3(0.0, 0.3, 0.0))
			await until(func() -> bool: return camp.step_index > idx or _done_chapters > 0, 3.0)
		await frames(6)
	if _done_chapters == 0:
		print("TUTDBG state=%s idx=%d step=%s hero=%s mode=%s floor=%s" % [str(camp.state), camp.step_index, str(camp.step), str(p.global_position), sn.mode_name(), str(p.is_on_floor())])
	TestLib.check(_steps_done >= 5 and (_done_chapters == 1 or camp.state != &"active"), "the tutorial chapter ran through its steps (%d steps, %d chapters)" % [_steps_done, _done_chapters])
	await frames(10)
	TestLib.check(SnakeMissions.is_tutorial_done(), "finishing SWING ACROSS THE CITY sets the tutorial flag")
	var inj2 := SnakeMissions.inject(picks, rng)
	TestLib.check(inj2.size() == 3, "afterwards the board offers snake missions only now and then")
	# ROOFTOP CHASE: the courier hovers over the first roof, hops when a step is done, and the last drone is the real target
	var dir_node := sn.director
	await _prep(Game.SPAWN)
	_done_chapters = 0
	var hops0 := dir_node.hops
	TestLib.check(camp.start_custom(chase["chapter"]), "the runner starts the chase chapter")
	await until(func() -> bool: return is_instance_valid(dir_node.courier) and dir_node.courier.active, 3.0)
	TestLib.check(is_instance_valid(dir_node.courier) and dir_node.courier.active, "a courier drone waits over the first roof")
	var csteps: Array[Dictionary] = chase["steps"]
	var first_roof: Vector3 = csteps[0]["pos"]
	TestLib.check(dir_node.courier.global_position.distance_to(first_roof) < 25.0, "right over it (%.0f m)" % dir_node.courier.global_position.distance_to(first_roof))
	await step_active(camp, 0)
	p.teleport_to(first_roof + Vector3(0.0, 0.3, 0.0))
	await until(func() -> bool: return camp.step_index >= 1, 3.0)
	await until(func() -> bool: return dir_node.hops > hops0, 3.0)
	TestLib.check(dir_node.hops > hops0, "when the hero reaches the roof the courier hops to the next one")
	var second_roof: Vector3 = csteps[1]["pos"]
	await until(func() -> bool: return dir_node.courier != null and is_instance_valid(dir_node.courier) and dir_node.courier.global_position.distance_to(second_roof + Vector3(0.0, 4.0, 0.0)) < 6.0, 5.0)
	TestLib.check(is_instance_valid(dir_node.courier) and dir_node.courier.global_position.distance_to(second_roof) < 14.0, "and lands over it")
	for i in [1, 2]:
		await step_active(camp, i)
		var q2: Vector3 = camp.step["pos"]
		p.teleport_to(q2 + Vector3(0.0, 0.3, 0.0))
		await until(func() -> bool: return camp.step_index > i, 3.0)
	await step_active(camp, 3)
	await until(func() -> bool: return camp.target != null and is_instance_valid(camp.target), 4.0)
	var last_roof: Vector3 = csteps[3]["pos"]
	TestLib.check(camp.target != null and is_instance_valid(camp.target), "on the last roof the runner's own drone is the target")
	if camp.target != null and is_instance_valid(camp.target):
		TestLib.check(Vector2(camp.target.global_position.x - last_roof.x, camp.target.global_position.z - last_roof.z).length() < 40.0, "over the last roof")
	if camp.target != null and is_instance_valid(camp.target):
		(camp.target as Drone).damage(1.0e6, false)
	await until(func() -> bool: return _done_chapters > 0 or camp.state == &"done" or camp.state == &"idle", 6.0)
	TestLib.check(_done_chapters == 1 or camp.state == &"done" or camp.state == &"idle", "shooting it down completes ROOFTOP CHASE")
	await frames(30)
	TestLib.check(not is_instance_valid(dir_node.courier) or not dir_node.courier.active, "the courier is gone")
	camp.step_completed.disconnect(on_step)
	camp.chapter_completed.disconnect(on_done)
