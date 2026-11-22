class_name SnakeWar
extends Node
## QUANTUM SNAKE COMBAT: the controller (wave 115, combat side; a child of the Player, made by SnakeWar.attach). The hero arms a SNAKE POWER from the weapon wheel (the SNAKE and SNAKE BOMB wedges)
## or the ABILITY wheel: with a power armed the gun is holstered and FIRE casts it (ALT is its second mode), the aim ring / arc / lock bracket of the grenades show where it lands. Ten VERBS
## (scripts/quantum/snake_verbs.gd) and twelve BOMBS (snake_bombs.gd), numbers in snake_rows.gd, snakes drawn by snake_swarm.gd and the hero's own tendrils (SnakeTendril), enemies held by snake_holds.gd,
## how enemies and civilians answer in snake_react.gd, the wheel and the icons in snake_ui.gd.
## Energy: the SNAKE ENERGY pool of Player.snake (the traversal spends the same bar; SnakePower.cost scales it by difficulty, 0 in HERO MODE) and a cooldown per power (SnakePower.cd, skill QUICK COIL).
## Hooks in shared files: PlayerWeapon.tick (a power in hand fires no gun), Player.damage (SHIELD, DECOY), the weapon wheel (WeaponWheel.items / activate), the touch ability wheel (four quick casts), InputMap actions.
## Everything ticks only while Game.is_playing(). Counters (tests wait on these, never on frames): casts, counts[id], whiffs, denied.

signal armed_changed(id: StringName)
signal used(id: StringName)

const GCD := 0.16                                   ## seconds between two casts of any power
const DIRECT: Dictionary = {&"snake_pull": &"sv_pull", &"snake_net": &"sv_net", &"snake_shield": &"sv_shield"}   ## the ABILITY wheel actions that cast without arming
const ACTIONS: Array[StringName] = [&"snake_pull", &"snake_net", &"snake_shield", &"snake_bomb"]

static var instance: SnakeWar

var p: Player
var swarm: SnakeSwarm
var holds: SnakeHolds
var verbs: SnakeVerbs
var bombs: SnakeBombs
var react: SnakeReact
var armed: StringName = &""
var verb_sel: StringName = &"sv_pull"
var bomb_sel: StringName = &"sb_coil"
var cd: Dictionary = {}                             ## id -> seconds left
var counts: Dictionary = {}                         ## id -> times used (a cast that went off)
var casts := 0
var whiffs := 0                                     ## a verb with nothing to act on (no energy spent)
var denied := 0                                     ## refused: jammed, dry, cooling down, locked, in a vehicle
var last_used: StringName = &""
var last_denied := ""
var aim: Dictionary = {}                            ## what the crosshair is on while a verb is armed {node, kind, pos, dist}
var preview_radius := 0.0                           ## the radius of the aim ring on screen (tests compare it with the table)

var _fire_was := false
var _alt_was := false
var _gcd := 0.0
var _la: LaunchAim
var _aim_t := 0.0
var _holstered := false
var _seen_hint := {}
var _glow_t := 0.0


## The war node of a player (created on first use). Called from Player._ready and by tests.
static func attach(player: Player) -> SnakeWar:
	var n := player.get_node_or_null("SnakeWar") as SnakeWar
	if n == null:
		n = SnakeWar.new()
		n.name = "SnakeWar"
		n.p = player
		player.add_child(n)
	return n


static func of(player: Node = null) -> SnakeWar:
	if is_instance_valid(instance):
		return instance
	var pl := (player if player != null else Game.player) as Player
	return attach(pl) if pl != null and pl.is_inside_tree() else null


## True while a snake power is in the hero's hand (PlayerWeapon.tick: no gun fires then).
static func holding() -> bool:
	return is_instance_valid(instance) and instance.armed != &""


## The hero asks for a GUN (the WEAPON button, a number key, a pick from the weapon wheel, any other equip): a snake power in hand is put away, the gun in hand comes back and fires again
## (wave 115 critic: arming a power from the wheel left FIRE casting it for good, with every gun the hero picked afterwards holstered and silent). True when a power was put away.
static func holster() -> bool:
	if not is_instance_valid(instance) or instance.armed == &"":
		return false
	instance.disarm()
	return true


## Player.damage asks first: the snakes of SNAKE SHIELD eat the hit (True).
static func absorb(amount: float, from_pos: Vector3) -> bool:
	return is_instance_valid(instance) and instance.verbs != null and instance.verbs.shield_absorb(amount, from_pos)


func _ready() -> void:
	instance = self
	if p == null:
		p = get_parent() as Player
	process_physics_priority = 6
	SnakeRows.ensure()
	swarm = SnakeSwarm.get_swarm(p)
	holds = SnakeHolds.new(self)
	verbs = SnakeVerbs.new(self)
	bombs = SnakeBombs.new(self)
	react = SnakeReact.new(self)
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.quality_changed.connect(func(_l: int) -> void: swarm = SnakeSwarm.get_swarm(p))
	bombs.connect_ops()
	SnakeBlasts.attach(self)                                           # wave 119: the six snake species of the SNAKE BLAST button (scripts/quantum/snake_blasts.gd)
	if p.weapon != null and not p.weapon.weapon_changed.is_connected(_on_weapon_changed):
		p.weapon.weapon_changed.connect(_on_weapon_changed)                    # any equip (a pickup, the shop, a mission, the auto swap) brings the gun back


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_hide_preview()


# --- numbers ---------------------------------------------------------------------------------------------------------------------------

func dmg_mult() -> float:
	return Upgrades.damage_mult() * HeroPower.f("dmg") * SkillTree.snakewar_dmg_mult()


func radius_mult() -> float:
	return SkillTree.snakewar_radius_mult()


func brood_extra() -> int:
	return SkillTree.snakewar_brood()


func cost_of(id: StringName) -> float:
	var base := float(SnakeRows.row(id).get("cost", 10.0))
	return minf(SnakePower.cost(base), SnakePower.max_energy())


func cd_of(id: StringName) -> float:
	return SnakePower.cd(float(SnakeRows.row(id).get("cd", 1.0))) * SkillTree.snakewar_cd_mult()


func cd_left(id: StringName) -> float:
	return float(cd.get(id, 0.0))


func cd_fraction(id: StringName) -> float:
	var total := cd_of(id)
	return clampf(cd_left(id) / total, 0.0, 1.0) if total > 0.001 else 0.0


func energy() -> float:
	return p.snake.energy if p != null and p.snake != null else 0.0


func energy_fraction() -> float:
	return p.snake.energy_fraction() if p != null and p.snake != null else 0.0


## True when `id` could be cast right now; `last_denied` says why when not.
func can_cast(id: StringName, force := false) -> bool:
	last_denied = ""
	if not SnakeRows.has(id) or p == null or not is_instance_valid(p):
		last_denied = "UNKNOWN"
		return false
	if force:
		return true
	if not Game.is_playing() or p.is_dead():
		last_denied = "NOT NOW"
		return false
	if p.vehicle != null:
		last_denied = "NOT IN A VEHICLE"
		return false
	if p.snake.jam_t > 0.0:
		last_denied = "SNAKE JAMMED"
		return false
	if not SnakeRows.unlocked(id):
		last_denied = "LEVEL %d" % SnakeRows.lvl_of(id)
		return false
	if cd_left(id) > 0.0 or _gcd > 0.0:
		last_denied = "READY IN %.1f" % maxf(cd_left(id), _gcd)
		return false
	if not SnakePower.unlimited() and energy() < cost_of(id) - 0.001:
		last_denied = "SNAKE ENERGY"
		return false
	return true


func _deny(id: StringName) -> void:
	denied += 1
	if last_denied != "" and last_denied != "NOT NOW":
		Game.say("%s  %s" % [SnakeRows.title(id), last_denied], 0.9)
		Sfx.play(&"snw_deny", -8.0)


## A power went off: the energy and the cooldown are paid, the counters and the world are told. Called by the verbs and the bombs once they commit (a whiff pays nothing).
func commit(id: StringName, at := Vector3.INF) -> void:
	if not SnakePower.unlimited():
		p.snake.energy = maxf(0.0, p.snake.energy - cost_of(id))
	cd[id] = cd_of(id)
	_gcd = GCD
	casts += 1
	counts[id] = int(counts.get(id, 0)) + 1
	last_used = id
	used.emit(id)
	HeroLook.pulse_glow(SnakeRows.color_of(id), 1.0, 0.4)
	UiSettings.buzz(26 if SnakeRows.is_bomb(id) else 14)
	if react != null:
		react.on_power(id, at if at != Vector3.INF else p.global_position)
	if SnakeWarMissions.hooked():
		SnakeWarMissions.note_power(id)


func note_whiff(id: StringName, text := "") -> void:
	whiffs += 1
	_gcd = 0.1
	if text != "":
		Game.say(text, 0.8)
	Sfx.play(&"snk_miss", -9.0)
	cd[id] = minf(cd_left(id), 0.0) + 0.25


# --- arming ----------------------------------------------------------------------------------------------------------------------------

func arm(id: StringName) -> bool:
	if not SnakeRows.has(id):
		return false
	if not SnakeRows.unlocked(id):
		last_denied = "LEVEL %d" % SnakeRows.lvl_of(id)
		Game.say("%s  LEVEL %d" % [SnakeRows.title(id), SnakeRows.lvl_of(id)], 1.2)
		return false
	SnakeRows.ensure()
	if SnakeRows.is_bomb(id):
		bomb_sel = id
	else:
		verb_sel = id
	var was := armed
	armed = id
	_holster(true)
	_glow_hands(true)
	if was != id:
		armed_changed.emit(id)
		Sfx.play(&"snw_arm", -6.0)
		var row := SnakeRows.row(id)
		Game.say("%s  %s" % [String(row["name"]), "FIRE TO THROW" if SnakeRows.is_bomb(id) else ("HOLD FIRE" if bool(row.get("hold", false)) else "FIRE TO USE")], 1.6)
	return true


func _on_weapon_changed(_id: StringName) -> void:
	if armed != &"":
		disarm()


func disarm() -> void:
	if armed == &"":
		return
	var was := armed
	armed = &""
	verbs.cancel_holds()
	_holster(false)
	_hide_preview()
	_glow_hands(false, was)
	armed_changed.emit(&"")


## The suit's hands burn in the colour of the power in hand (HeroGlow layer `flow`: the snake emitters), a flash on every cast.
func _glow_hands(on: bool, id: StringName = &"") -> void:
	var c: Color = SnakeRows.color_of(armed if on else id)
	HeroLook.set_glow(c, 0.85 if on else 0.0, &"flow")


## The gun goes away while a power is in the hand and comes back after it (PlayerBody keeps the mesh; set_weapon_look restores it).
func _holster(on: bool) -> void:
	if p == null or p.body == null or p.weapon == null:
		return
	if on == _holstered:
		return
	_holstered = on
	var mi: Variant = p.body.get(&"_wp_mi")
	if on:
		if mi is MeshInstance3D:
			(mi as MeshInstance3D).visible = false
	else:
		p.body.set_weapon_look(p.weapon.current)


func reset() -> void:
	if armed != &"":
		_glow_hands(false, armed)
	armed = &""
	cd.clear()
	_gcd = 0.0
	if holds != null:
		holds.clear()
	if verbs != null:
		verbs.reset()
	if bombs != null:
		bombs.reset()
	if react != null:
		react.reset()
	_holster(false)
	_hide_preview()
	armed_changed.emit(&"")


func _hide_preview() -> void:
	preview_radius = 0.0
	if _la != null:
		_la.hide()


# --- the tick --------------------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if p == null or not is_instance_valid(p) or not Game.is_playing():
		return
	_gcd = maxf(0.0, _gcd - dt)
	for k: Variant in cd.keys():
		var v := float(cd[k]) - dt
		if v <= 0.0:
			cd.erase(k)
		else:
			cd[k] = v
	if p.is_dead() or p.vehicle != null:
		if armed != &"":
			disarm()
		return
	holds.tick(dt)
	verbs.tick(dt)
	bombs.tick(dt)
	react.tick(dt)
	SnakeWarMissions.tick(self, dt)
	_poll(dt)
	if armed != &"":
		_glow_t -= dt
		if _glow_t <= 0.0:
			_glow_t = 0.5
			_glow_hands(true)                                    # the traversal releases the same layer when a swing ends
		if _holstered:
			var mi: Variant = p.body.get(&"_wp_mi")
			if mi is MeshInstance3D and (mi as MeshInstance3D).visible:
				(mi as MeshInstance3D).visible = false           # a weapon change inside PlayerBody puts the mesh back
		_update_preview(dt)


func _poll(dt: float) -> void:
	var fire := Input.is_action_pressed(&"fire")
	var fire_pressed := fire and not _fire_was
	var fire_released := _fire_was and not fire
	_fire_was = fire
	var alt := InputMap.has_action(&"altfire") and Input.is_action_pressed(&"altfire")
	var alt_pressed := alt and not _alt_was
	_alt_was = alt
	for a: StringName in ACTIONS:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			if a == &"snake_bomb":
				cast(bomb_sel)
			else:
				cast(DIRECT[a])
	if armed == &"":
		return
	if SnakeRows.is_bomb(armed):
		if fire_pressed:
			cast(armed)
	else:
		verbs.handle(armed, fire_pressed, fire, fire_released, alt_pressed, dt)


## Casts power `id` now (a verb or a bomb): the energy, cooldown and jam checks, then the power itself. True when it went off.
func cast(id: StringName, force := false) -> bool:
	if not can_cast(id, force):
		if not force:
			_deny(id)
		return false
	SnakeRows.ensure()
	var ok := false
	if SnakeRows.is_bomb(id):
		ok = bombs.throw(id, force)
	else:
		ok = verbs.press(id, force)
	return ok


# --- the aim preview ---------------------------------------------------------------------------------------------------------------

func _update_preview(dt: float, aim_at := Vector3.INF) -> void:                  # aim_at: the pre-warm (SnakeWarm) puts the rings and the wall in front of the camera
	if p.weapon == null:
		return
	if _la == null:
		_la = LaunchAim.new(p.weapon)
	if _la._ring == null:
		_la._build()
	var row := SnakeRows.row(armed)
	var reach := maxf(float(row.get("range", 30.0)), 12.0)
	var col: Color = row.get("color", SnakeRows.CYAN)
	_la.active = true
	if SnakeRows.is_bomb(armed):
		var e := BlastTable.entry(armed)
		if e.is_empty():
			return
		var dv: Dictionary = e["deliver"]
		var pt := SnakeAim.point(p, reach) if aim_at == Vector3.INF else aim_at
		var d := {"bid": armed, "range": reach, "speed": float(dv.get("speed", 20.0)), "grav": float(dv.get("grav", 22.0)), "blast_radius": float(e["radius"])}
		_la.landing = pt
		_la.target = null
		_la._lock.visible = false
		_la._update_dots(pt, d)
		BlastPreview.update(p.weapon, d, pt, _la)
		var r := float(e["radius"]) * radius_mult()
		if absf(radius_mult() - 1.0) > 0.001:                                 # the COIL SPREAD skill: the ring and the wall show the bigger radius
			_la._ring.scale = Vector3(r * 2.0, r * 2.0, 1.0)
			if is_instance_valid(BlastPreview._wall):
				var wt := BlastPreview._wall.global_transform
				BlastPreview._wall.global_transform = Transform3D(Basis.from_scale(Vector3(r, wt.basis.get_scale().y, r)), wt.origin)
			BlastPreview.radius_shown = r
		preview_radius = BlastPreview.radius_shown
		return
	# a verb: the lock bracket on the target (10 times a second), the ring of an area verb on the aim point
	BlastPreview.hide()
	_la._dots.visible = false
	_aim_t -= dt
	if _aim_t <= 0.0:
		_aim_t = 0.1
		aim = verbs.preview_target(armed)
	var area := float(row.get("radius", 0.0))
	var ring_at := Vector3.INF
	if armed == &"sv_net" or armed == &"sv_trap":                           # (the shield has no ring: it is centred on the hero and a disc round the feet filled the bottom of the phone frame)
		ring_at = SnakeAim.ground_under(p, SnakeAim.point(p, reach) if aim_at == Vector3.INF else aim_at)
	if ring_at != Vector3.INF:
		_la._ring.visible = true
		_la._ring.global_position = ring_at + Vector3(0.0, 0.07, 0.0)
		var ra := area * radius_mult()
		_la._ring.scale = Vector3(ra * 2.0, ra * 2.0, 1.0)
		(_la._ring.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.8)
		preview_radius = ra
	else:
		_la._ring.visible = false
		preview_radius = 0.0
	var has_aim: bool = not aim.is_empty() and (aim.get("kind") == &"pickup" or is_instance_valid(aim.get("node")))
	if has_aim:
		_la._lock.visible = true
		_la._lock.global_position = aim["pos"]
		var pulse := 1.0 + 0.12 * sin(float(Time.get_ticks_msec()) * 0.009)
		_la._lock.scale = Vector3.ONE * (1.9 if aim.get("kind") != &"car" else 3.6) * pulse
	else:
		_la._lock.visible = false
