class_name SnakeReact
extends RefCounted
## HOW THE WORLD ANSWERS THE SNAKES (wave 115, combat side). Enemies are not blind to what the hero does, and the answers are plain and EASY first (every rate is a row by difficulty, STORY has none):
##   PANIC      troopers near a snake bomb or a swarm break and run (the Operative retreat, its own run animation); bosses, brutes and a squad of the encounter director stand their ground
##   CUT        a rifleman with a clear line to a snake that holds something (SNAKE GRAB) shoots the tendril: the held body drops and the snake is gone (never on STORY)
##   JAM        the warden's phase pulse and the snake hunter's static net jam every snake (Player.snake.jam): the armed power is dropped, the shield and the guards fade, the buttons say SNAKE JAMMED
##   HUNTER     after a run of snake powers (NORMAL: six in a minute, HARD four, QUANTUM three) a SNAKE HUNTER (a specialist with a static net launcher) comes for the hero, one at a time, never on STORY
##   CROWD      civilians within 24 m that are not in the blast stop and film the hero, a cheer when the flare or a big bomb goes off (they run from a blast as always)
## Counters (tests wait on these): panics, cuts, films, cheers, hunters, jams.

const PANIC_RATE := [0.0, 0.6, 0.4, 0.3]               ## by difficulty (STORY, NORMAL, HARD, QUANTUM): the share of troopers near a bomb that run
const CUT_RATE := [0.0, 0.05, 0.12, 0.2]               ## chance a second that a rifleman with a clear line cuts a held snake
const HUNTER_CASTS := [0, 6, 4, 3]                     ## snake casts in 60 s that call a hunter (0 = never)
const HUNTER_COOLDOWN := 75.0
const FILM_RADIUS := 24.0
const FILM_MIN := 9.0
const FILM_MAX := 6

var war: SnakeWar
var p: Player
var panics := 0
var cuts := 0
var films := 0
var cheers := 0
var hunters := 0
var jams := 0
var _casts: Array[float] = []
var _hunter_cd := 0.0
var _cheer_cd := 0.0
var _cut_t := 0.0
var _jam_was := false
var _rng := RandomNumberGenerator.new()
var _now := 0.0


func _init(w: SnakeWar = null) -> void:
	war = w
	p = w.p if w != null else null
	_rng.randomize()


func reset() -> void:
	_casts.clear()
	_hunter_cd = HUNTER_COOLDOWN * 0.5
	_jam_was = false


func _mode() -> int:
	return clampi(Difficulty.clamp_mode(Difficulty.current), 0, 3)


func on_power(id: StringName, at: Vector3) -> void:
	_casts.append(_now)
	_civilians(id, at)


## A snake bomb went off at `pos` (radius `radius`): the troopers around it may run.
func on_blast(id: StringName, pos: Vector3, radius: float) -> void:
	var rate: float = PANIC_RATE[_mode()]
	if rate > 0.0:
		for e: Node3D in Gear.living_enemies(p.get_tree()):
			if e.global_position.distance_to(pos) > radius * 1.5 + 3.0:
				continue
			if _rng.randf() < rate:
				panic(e)
	if radius >= 8.0 and _cheer_cd <= 0.0 and _films_near() > 0:
		cheer()


func panic(en: Node3D) -> bool:
	if not SnakeAim.is_live_enemy(en) or SnakeAim.is_boss(en) or SnakeAim.heavy(en):
		return false
	if not (en is Operative):
		return false
	if bool(en.get(&"squad_job")) or bool(en.get(&"kit_set")) or bool(en.get(&"_retreating")):
		return false
	en.set(&"_retreating", true)
	en.set(&"_retreat_t", 0.0)
	panics += 1
	return true


func cheer() -> void:
	_cheer_cd = 7.0
	cheers += 1
	Sfx.play(&"snw_cheer", -6.0)


func _crowd() -> Object:
	if not is_instance_valid(Game.world):
		return null
	var amb: Object = Game.world.get(&"ambient")
	return amb.get(&"crowd") if amb != null else null


func _films_near() -> int:
	var crowd := _crowd()
	if crowd == null:
		return 0
	var n := 0
	for i in int(crowd.get(&"count")):
		if crowd.call(&"is_alive", i) and StringName(crowd.call(&"state_of", i)) in [&"linger", &"idle"]:
			if (crowd.call(&"person_position", i) as Vector3).distance_to(p.global_position) < FILM_RADIUS:
				n += 1
	return n


## Civilians out of the way stop and turn to the hero (a few seconds): they are filming.
func _civilians(_id: StringName, _at: Vector3) -> void:
	var crowd := _crowd()
	if crowd == null:
		return
	var n := 0
	var me := p.global_position
	for i in int(crowd.get(&"count")):
		if n >= FILM_MAX:
			break
		if not crowd.call(&"is_alive", i) or crowd.call(&"is_dying", i) or crowd.call(&"is_fleeing", i):
			continue
		var pp: Vector3 = crowd.call(&"person_position", i)
		var d := pp.distance_to(me)
		if d < FILM_MIN or d > FILM_RADIUS or _rng.randf() > 0.4:
			continue
		crowd.call(&"attend", i, me, 3.5 + _rng.randf() * 2.0)
		n += 1
		films += 1
	if n > 0 and _cheer_cd <= 0.0 and _rng.randf() < 0.35:
		cheer()


func tick(dt: float) -> void:
	_now += dt
	_hunter_cd = maxf(0.0, _hunter_cd - dt)
	_cheer_cd = maxf(0.0, _cheer_cd - dt)
	while not _casts.is_empty() and _now - _casts[0] > 60.0:
		_casts.pop_front()
	var jam := p.snake.jam_t > 0.0
	if jam and not _jam_was:
		jams += 1
		_on_jam()
	_jam_was = jam
	_cut_t -= dt
	if _cut_t <= 0.0:
		_cut_t = 1.0
		_try_cut()
	_try_hunter()


## A jammer reached the hero: the armed power drops, the shield and the guards fade.
func _on_jam() -> void:
	if war.armed != &"":
		war.disarm()
	war.verbs.cancel_holds()
	war.verbs.jam_drop()
	Game.say("SNAKES JAMMED", 1.0)


## A rifleman with a clear line to a held snake shoots it: the grabbed body drops (never on STORY, rare on NORMAL).
func _try_cut() -> void:
	var rate: float = CUT_RATE[_mode()]
	if rate <= 0.0 or WeaponDefs.hero_mode or not war.verbs.is_grabbing():
		return
	var held := war.verbs.grab_position()
	for e: Node3D in Gear.living_enemies(p.get_tree()):
		if e.get(&"aware") != true or e.get(&"friendly") == true or e == war.verbs.grab_node():
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d > 45.0 or d < 5.0:
			continue
		if not SnakeAim.clear_line(p, SnakeAim.center_of(e), held):
			continue
		if _rng.randf() < rate:
			cuts += 1
			war.verbs.cut_grab()
			Game.say("SNAKE CUT", 0.9)
			FX.burst(held, Color(1.0, 0.4, 0.4), 8, 6.0, 0.4, 2.0, 1.0)
			return


## The static net of a snake hunter: a ball that flies at the hero (led by his speed), lands as a ring; the hero inside it is jammed (every snake of his dies for SnakePower.jam_seconds) and takes a little damage.
static func fire_net(hunter: Node3D) -> void:
	var p := Game.player as Player
	var war := SnakeWar.instance
	if p == null or war == null or war.swarm == null or not is_instance_valid(hunter):
		return
	var from: Vector3 = (hunter.call(&"center") as Vector3) + Vector3(0.0, 0.3, 0.0)
	var to := p.global_position + Vector3(0.0, 0.2, 0.0) + p.velocity * 0.45
	var dur := clampf(from.distance_to(to) / 17.0, 0.5, 2.0)
	var col := Color(0.55, 1.0, 0.4)
	var dmg := float((hunter.get(&"cfg") as Dictionary).get("net_dmg", 8.0)) if hunter.get(&"cfg") is Dictionary else 8.0
	Sfx.play_at(&"snw_bomb_throw", from, -2.0, 0.85)
	war.swarm.spawn(&"ball", from, {"color": col, "thick": 0.1, "len": 2.0, "radius": 0.3, "life": dur + 0.05, "prio": 3,
		"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
			var k := clampf(b.age / dur, 0.0, 1.0)
			b.pos = from.lerp(to, k) + Vector3(0.0, sin(k * PI) * 2.6, 0.0)
			if k >= 1.0:
				_net_lands(to, col, dmg)
				return false
			return true})


static func _net_lands(at: Vector3, col: Color, dmg: float) -> void:
	var p := Game.player as Player
	var war := SnakeWar.instance
	if p == null or war == null:
		return
	war.swarm.spawn(&"ring", at, {"radius": 3.0, "thick": 0.07, "len": 12.0, "color": col, "life": 1.4, "rise_t": 0.2, "prio": 2, "spin": 3.0})
	FX.burst(at + Vector3(0.0, 0.4, 0.0), col, 12, 6.0, 0.4, 2.0, 1.1)
	Sfx.play_at(&"snw_net", at, -3.0)
	if Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() <= 3.2 and absf(p.global_position.y - at.y) < 3.0:
		SnakeTraversal.jam_in_radius(at, 3.6)
		p.damage(dmg, at)
		Game.say("STATIC NET  SNAKES JAMMED", 1.2)


## The counter-unit: a snake hunter comes after a run of snake powers (one at a time).
func _try_hunter() -> void:
	var need: int = HUNTER_CASTS[_mode()]
	if need <= 0 or _hunter_cd > 0.0 or _casts.size() < need or WeaponDefs.hero_mode or Game.quality == 0 and _casts.size() < need + 2:
		return
	var em := Game.enemies as EnemyManager
	if em == null or InteriorGameplay.active or InteriorSpace.active:
		return
	for e: Node3D in Gear.living_enemies(p.get_tree()):
		if StringName(e.get(&"type")) == &"hunter":
			return
	var a := _rng.randf() * TAU
	var at := p.global_position + Vector3(cos(a), 0.0, sin(a)) * 30.0
	var g := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40.0, at + Vector3.DOWN * 80.0, Game.L_WORLD))
	if g.is_empty():
		return
	at = g["position"]
	if not EnemyTypes.TYPES.has(&"hunter"):
		return
	var h := em.spawn(&"hunter", at, true)
	if h != null:
		hunters += 1
		_hunter_cd = HUNTER_COOLDOWN
		_casts.clear()
		Game.say("SNAKE HUNTER", 1.2)
