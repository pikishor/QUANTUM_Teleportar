class_name Companion
extends Node3D
## COMPANION AI ALLY: a recruitable Vael defector (HumanoidVariants "vael" on the shared Superhero rig, driven by Locomotion + HumanoidAnim like the troopers) that follows the hero, takes
## cover from the nearest threat, fires at aware enemies in line of sight, can be commanded with two touch buttons (HOLD toggles hold / follow, ATTACK pushes at the nearest enemy for
## ATTACK_TIME seconds), pulls the hero back from a lethal hit once per mission (rescue, see Player.damage) and can be downed itself (the hero revives it by standing close).
## Appears in the campaign chapters CHAPTERS (the sequel's 11 and 12), in the side missions SIDE_IDS, and on request from the DEMO menu (recruit / dismiss). Hidden while the hero is in
## a vehicle or an interior. Save: Progress.companion_met (optional [companion] section).
## Budget: ONE actor at most (CAP), one skinned body (the shared hero maps: no new textures), the visor light of the model is dropped, the shadow only on MED / HIGH, the shooting
## brain runs 3-5 times a second (target pick: at most three line-of-sight rays), cover search at most once per COVER_EVERY seconds, movement and animation every physics frame.
## Simulates only while Game.is_playing() (Game.state is the only pause).

signal recruited
signal downed
signal revived
signal rescued_hero

enum Mode { FOLLOW, HOLD, ATTACK }
enum Life { UP, DOWNED }

const CAP := 1
const CHAPTERS: Array[int] = [10, 11]                       ## 0-based campaign chapters with the ally (11 THE HOLLOW CHOIR, 12 THE SECOND GATE)
const SIDE_IDS: Array[StringName] = [&"turf", &"hunt", &"rescue"]
const SEED := 4242
const ALLY_TRIM := Color(0.3, 0.9, 1.0)
const MAX_HP := 120.0
const ARMOUR := 0.6                                         ## damage taken multiplier
const WALK := 3.2
const RUN := 6.8
const FOLLOW_NEAR := 3.4
const FOLLOW_FAR := 7.5
const TELEPORT_DIST := 48.0
const SIGHT := 32.0
const HOLD_COVER_R := 9.0
const COVER_R := 16.0
const COVER_EVERY := 1.6
const FIRE_DMG := 11.0
const BURST := 3
const BURST_GAP := 0.13
const BURST_REST := 0.85
const WINDUP := 0.3
const ATTACK_TIME := 12.0
const ATTACK_STAND_OFF := 13.0
const RESCUE_HP := 0.35
const RESCUE_RANGE := 70.0
const RESCUE_INVULN := 3.0
const REVIVE_HOLD := 2.0
const REVIVE_REACH := 3.5
const PRESSURE_RANGE := 12.0                                ## aware enemies this close to the ally (and nearer to it than to the hero) shoot at it
const PRESSURE_EVERY := 1.3
const THINK := [0.35, 0.25, 0.2]                            ## seconds between brain ticks by graphics tier
const POLL_EVERY := 0.5

static var current: Companion

var active := false                     ## recruited and on the map (it may be hidden inside a vehicle or an interior)
var manual := false                     ## recruited by the DEMO menu: stays until dismissed
var mode: Mode = Mode.FOLLOW
var life: Life = Life.UP
var hp := MAX_HP
var revives_left := 1                   ## hero rescues left in this mission
var shots := 0                          ## rounds fired this recruitment
var rescues := 0                        ## hero rescues made this recruitment
var times_downed := 0
var cover_used := 0                     ## times it reached a cover spot
var hold_pos := Vector3.INF
var target: Drone                       ## the enemy it shoots at (null: none in sight)
var test_cover := Vector3.INF           ## tests: a fixed cover spot instead of the world search
var reason := ""                        ## why it is here: "chapter", "side", "demo"

var yaw := 0.0
var _root: Node3D
var _body: MeshInstance3D
var _variant := {}
var _rig: CharacterRig
var _loco: Locomotion
var _hanim: HumanoidAnim
var _built := false
var _available := true
var _ray := PhysicsRayQueryParameters3D.new()
var _last_pos := Vector3.ZERO
var _have_last := false
var _moving := false
var _running := false
var _think_t := 0.0
var _poll_t := 0.0
var _aim_t := 0.0
var _burst_left := 0
var _shot_t := 0.0
var _rest_t := 0.0
var _attack_t := 0.0
var _cover := Vector3.INF
var _cover_cd := 0.0
var _at_cover := false
var _peek_t := 0.0
var _revive_t := 0.0
var _pressure_t := 0.0
var _hidden_by := ""                    ## "vehicle" / "interior" while it is not drawn
var _lod_t := 0.0
var _clock := 0.0
var _sync_t := 0.0


func _ready() -> void:
	add_to_group(&"companion")
	_ray.collision_mask = Game.L_WORLD
	visible = false
	current = self
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(dismiss)
	Game.state_changed.connect(_on_state)


func _exit_tree() -> void:
	if current == self:
		current = null


# --- API ------------------------------------------------------------------------------------------------------------

## Brings the ally into the game next to the hero. False at the cap (already recruited), without a hero, or when the character files are absent.
func recruit(why := "demo") -> bool:
	if active or not is_instance_valid(Game.player):
		return false
	if not _build():
		return false
	active = true
	reason = why
	manual = why == "demo"
	life = Life.UP
	mode = Mode.FOLLOW
	hp = MAX_HP
	revives_left = 1
	shots = 0
	rescues = 0
	times_downed = 0
	cover_used = 0
	target = null
	hold_pos = Vector3.INF
	_attack_t = 0.0
	_cover = Vector3.INF
	_cover_cd = 0.0
	_revive_t = 0.0
	_hidden_by = ""
	_reset_pose()
	_place_near_hero()
	visible = true
	_root.visible = true
	var prog := Game.progress as Progress
	if prog != null and not prog.companion_met:
		prog.companion_met = true
		prog.changed.emit()
	Game.say("VAEL DEFECTOR JOINED", 2.5)
	recruited.emit()
	return true


## Sends the ally away (mission over, DEMO dismiss, new run). Idempotent.
func dismiss() -> void:
	if not active and not visible:
		return
	active = false
	manual = false
	target = null
	hold_pos = Vector3.INF
	visible = false
	if _root != null:
		_root.visible = false


## Touch commands: &"hold" toggles hold / follow, &"attack" starts an ATTACK_TIME push at the nearest enemy. False when the ally cannot take orders.
func command(cmd: StringName) -> bool:
	if not active or life != Life.UP:
		return false
	match cmd:
		&"hold":
			if mode == Mode.HOLD:
				mode = Mode.FOLLOW
				hold_pos = Vector3.INF
				Game.say("ALLY FOLLOW", 1.2)
			else:
				mode = Mode.HOLD
				hold_pos = global_position
				_attack_t = 0.0
				Game.say("ALLY HOLD", 1.2)
			return true
		&"attack":
			mode = Mode.ATTACK
			hold_pos = Vector3.INF
			_attack_t = ATTACK_TIME
			Game.say("ALLY ATTACK", 1.2)
			return true
	return false


func mode_name() -> String:
	if life == Life.DOWNED:
		return "DOWN"
	return ["FOLLOW", "HOLD", "ATTACK"][mode]


func hp_fraction() -> float:
	return clampf(hp / MAX_HP, 0.0, 1.0)


## True when the controls should show the two command buttons.
static func controllable() -> bool:
	return current != null and current.active and current._hidden_by == ""


## Incoming damage (enemy rounds, bolts, pressure). The ally goes down at zero hp.
func damage(amount: float, from_pos := Vector3.ZERO) -> void:
	if not active or life != Life.UP or amount <= 0.0 or not Game.is_playing():
		return
	if _hidden_by != "":
		return
	hp -= amount * ARMOUR
	if _hanim != null:
		var d := Vector2.ZERO
		if from_pos != Vector3.ZERO:
			var h := Vector3(from_pos.x - global_position.x, 0.0, from_pos.z - global_position.z)
			if h.length() > 0.1:
				h = h.normalized()
				d = Vector2(h.dot(Vector3(cos(yaw), 0.0, -sin(yaw))), h.dot(Vector3(-sin(yaw), 0.0, -cos(yaw))))
		_hanim.hit(d, clampf(amount / 30.0, 0.3, 1.0))
	if hp <= 0.0:
		_go_down()


## An enemy round that went from `a` to `b`: it hits the ally when it passes within a body radius (called by the troopers' shots).
func shot_passes(a: Vector3, b: Vector3, dmg: float) -> void:
	if not active or life != Life.UP or _hidden_by != "":
		return
	var c := global_position + Vector3(0.0, 1.0, 0.0)
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.01:
		return
	var t := clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	if (a + ab * t).distance_to(c) < 0.55:
		damage(dmg, a)


## An energy bolt at `pos` (enemy manager): true when it hit the ally and is spent.
func bolt_hit(pos: Vector3, dmg: float, from: Vector3) -> bool:
	if not active or life != Life.UP or _hidden_by != "":
		return false
	if Vector2(pos.x - global_position.x, pos.z - global_position.z).length() < 0.6 and pos.y > global_position.y and pos.y < global_position.y + 1.9:
		damage(dmg, from)
		return true
	return false


## The hero would die: the ally pulls them back once per mission. True when the hero was saved (hp restored, a short invulnerability).
static func rescue(p: Node3D) -> bool:
	var c := current
	if c == null or not c.active or c.life != Life.UP or c.revives_left <= 0 or c._hidden_by != "":
		return false
	if c.global_position.distance_to(p.global_position) > RESCUE_RANGE:
		return false
	c.revives_left -= 1
	c.rescues += 1
	p.set(&"hp", float(p.get(&"max_hp")) * RESCUE_HP)
	p.set(&"invuln", maxf(float(p.get(&"invuln")), RESCUE_INVULN))
	c._rush_to(p.global_position)
	Game.say("ALLY REVIVED YOU", 2.5)
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), ALLY_TRIM, 10, 4.0, 0.5, 1.0)
	c.rescued_hero.emit()
	return true


# --- lifecycle ------------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	dismiss()


func _on_respawn() -> void:
	if not active:
		return
	life = Life.UP
	hp = MAX_HP
	revives_left = 1
	target = null
	_cover = Vector3.INF
	_reset_pose()
	_place_near_hero()


func _on_state(s: StringName) -> void:
	if s == &"menu":
		dismiss()


func _reset_pose() -> void:
	if _hanim != null:
		_hanim.reset()
	if _loco != null:
		_loco.reset()
	if _rig != null:
		_rig.reset()
	_have_last = false
	_aim_t = 0.0
	_burst_left = 0
	_shot_t = 0.0
	_rest_t = 0.0
	_at_cover = false


func _go_down() -> void:
	life = Life.DOWNED
	hp = 0.0
	times_downed += 1
	target = null
	_cover = Vector3.INF
	_burst_left = 0
	_aim_t = 0.0
	_revive_t = 0.0
	if _hanim != null:
		_hanim.die(0)
	Game.say("ALLY DOWN", 2.0)
	downed.emit()


func _stand_up() -> void:
	life = Life.UP
	hp = MAX_HP * 0.4
	_reset_pose()
	Game.say("ALLY UP", 1.5)
	revived.emit()


# --- build ----------------------------------------------------------------------------------------------------------

func _build() -> bool:
	if _built:
		return true
	if not _available or not HumanoidVariants.available():
		_available = false
		return false
	var d := HumanoidVariants.variant(&"vael", SEED)
	d["trim"] = ALLY_TRIM
	d["suit"] = Color(0.2, 0.24, 0.3)
	d["key"] = "ally/%s" % String(d["key"])           # its own mid mesh (the troopers' cached one carries their colours)
	var r := HumanoidVariants.build(&"vael", SEED)
	if r["root"] == null or not bool(r["ok"]):
		if r["root"] != null:
			(r["root"] as Node).free()
		_available = false
		return false
	var root := r["root"] as Node3D
	_rig = CharacterRig.find(root)
	if _rig == null:
		root.free()
		_available = false
		return false
	HumanoidVariants.tint(r["material"], d)
	var glow := root.get_node_or_null("VisorGlow")        # one light less in the scene: the trim glow of the material is enough
	if glow != null:
		root.remove_child(glow)
		glow.free()
	_variant = d
	_body = r["body"] as MeshInstance3D
	if _body != null:
		_body.set_meta(&"variant_key", d["key"])
	_root = root
	add_child(root)
	_loco = Locomotion.new(_rig)
	_loco.scale_amp = 0.9
	_hanim = HumanoidAnim.new()
	_hanim.set_weapon(&"rifle")
	_hanim.windup_time = WINDUP
	if _rig.reflection != null:
		_rig.reflection.range = 10.0
	_apply_shadow(Game.quality >= 1)
	_built = true
	return true


func _apply_shadow(on: bool) -> void:
	if _rig != null:
		_rig.set_shadow(on)


# --- simulation -----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL_EVERY
		_poll_mission()
	if not active:
		return
	var p := Game.player as Player
	if p == null or not is_instance_valid(p):
		return
	_tick_hidden(p)
	if _hidden_by != "":
		return
	_clock += delta
	if life == Life.DOWNED:
		_tick_downed(delta, p)
		_animate(delta)
		return
	_think_t -= delta
	_cover_cd -= delta
	if _think_t <= 0.0:
		_think_t = float(THINK[clampi(Game.quality, 0, 2)])
		_think(p)
	if mode == Mode.ATTACK:
		_attack_t -= delta
		if _attack_t <= 0.0:
			mode = Mode.FOLLOW
	_move(delta, p)
	_fire(delta)
	_animate(delta)
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.25
		_lod()


## Mission wiring: the ally is wanted while a campaign chapter of CHAPTERS or a side mission of SIDE_IDS runs (or after a DEMO recruit).
func _poll_mission() -> void:
	var want := manual
	var why := reason
	var m := Game.missions as Missions
	if m != null and not want:
		if m.campaign != null and m.campaign.is_running() and CHAPTERS.has(int(m.campaign.chapter_index)):
			want = true
			why = "chapter"
		elif m.sides != null and m.sides.active and SIDE_IDS.has(m.sides.id):
			want = true
			why = "side"
		elif m.heists != null and m.heists.is_running() and m.heists.crew:
			want = true
			why = "heist"
	if want and not active:
		recruit(why if why != "" else "chapter")
	elif not want and active and not manual:
		dismiss()


func _tick_hidden(p: Player) -> void:
	var want := ""
	if p.vehicle != null:
		want = "vehicle"
	elif InteriorGameplay.active:
		want = "interior"
	if want == _hidden_by:
		if want != "":
			_sync_t -= 0.016
			if _sync_t <= 0.0:
				_sync_t = 0.5
				global_position = p.global_position
		return
	_hidden_by = want
	_root.visible = want == ""
	if want == "":
		_place_near_hero()
		_have_last = false


func _tick_downed(delta: float, p: Player) -> void:
	var near := global_position.distance_to(p.global_position) <= REVIVE_REACH and p.vehicle == null
	_revive_t = _revive_t + delta if near else maxf(0.0, _revive_t - delta * 0.5)
	if _revive_t >= REVIVE_HOLD:
		_stand_up()


## The brain: pick the target, look for cover, pressure from the enemies around.
func _think(p: Player) -> void:
	target = _pick_target(p)
	if target != null and mode != Mode.ATTACK and _cover_cd <= 0.0 and not _cover.is_finite():
		_cover_cd = COVER_EVERY
		var spot := test_cover if test_cover.is_finite() else EnemyCover.find(self, target.global_position, COVER_R)
		if spot.is_finite():
			var anchor := hold_pos if mode == Mode.HOLD and hold_pos.is_finite() else p.global_position
			var lim := HOLD_COVER_R if mode == Mode.HOLD else 24.0
			if Vector2(spot.x - anchor.x, spot.z - anchor.z).length() <= lim:
				_cover = spot
				_at_cover = false
	if target == null and not _is_threatened():
		_cover = Vector3.INF
		_at_cover = false
	_pressure_t -= float(THINK[clampi(Game.quality, 0, 2)])
	if _pressure_t <= 0.0:
		_pressure_t = PRESSURE_EVERY
		_pressure(p)


func _is_threatened() -> bool:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return false
	for e: Drone in mgr.list:
		if e.active and not e.dead and e.aware and Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length() < SIGHT:
			return true
	return false


func _pick_target(p: Player) -> Drone:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return null
	var from := _muzzle()
	var best: Drone = null
	var best_d := INF
	var rays := 0
	var keep := target
	if is_instance_valid(keep) and keep.active and not keep.dead and (keep.aware or mode == Mode.ATTACK):
		var kd := Vector2(keep.global_position.x - global_position.x, keep.global_position.z - global_position.z).length()
		if kd < SIGHT and _clear(from, keep.center()):
			return keep                                    # stay on the target while it is still in sight
	for e: Drone in mgr.list:
		if not is_instance_valid(e) or not e.active or e.dead:
			continue
		if not (e.aware or mode == Mode.ATTACK):
			continue                                       # never wakes a patrol that has not seen the hero
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d >= SIGHT:
			continue
		# the nearest first; three rays at most per brain tick
		if d < best_d and rays < 3:
			rays += 1
			if _clear(from, e.center()):
				best = e
				best_d = d
	return best


func _clear(a: Vector3, b: Vector3) -> bool:
	_ray.from = a
	_ray.to = b
	return get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Enemies close to the ally and nearer to it than to the hero shoot at it now and then (they do not retarget; this stands in for the stray fire).
func _pressure(p: Player) -> void:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return
	for e: Drone in mgr.list:
		if not is_instance_valid(e) or not e.active or e.dead or not e.aware:
			continue
		var dc := e.global_position.distance_to(global_position)
		if dc > PRESSURE_RANGE or dc > e.global_position.distance_to(p.global_position) - 3.0:
			continue
		if randf() < 0.45 and _clear(e.center(), global_position + Vector3(0.0, 1.0, 0.0)):
			damage(float(e.cfg.get("dmg", 8.0)), e.global_position)
			break


func _move(delta: float, p: Player) -> void:
	var here := global_position
	var goal := Vector3.INF
	var run := false
	match mode:
		Mode.HOLD:
			var anchor := hold_pos if hold_pos.is_finite() else here
			goal = _cover if _cover.is_finite() else anchor
			run = true
		Mode.ATTACK:
			if is_instance_valid(target) and not target.dead:
				var away := Vector3(here.x - target.global_position.x, 0.0, here.z - target.global_position.z)
				var d := away.length()
				if d > ATTACK_STAND_OFF + 1.5:
					goal = target.global_position + away.normalized() * ATTACK_STAND_OFF
					run = true
				else:
					goal = here
		_:
			if _cover.is_finite() and target != null:
				goal = _cover
				run = true
			else:
				goal = _follow_spot(p)
				var dp := Vector2(p.global_position.x - here.x, p.global_position.z - here.z).length()
				if dp > TELEPORT_DIST:
					_rush_to(p.global_position)
					return
				if dp > FOLLOW_FAR:
					run = true
				elif dp < FOLLOW_NEAR:
					goal = here
	var to := Vector3(goal.x - here.x, 0.0, goal.z - here.z) if goal.is_finite() else Vector3.ZERO
	var dist := to.length()
	_moving = dist > (0.35 if _moving else 0.7)
	_running = run and dist > 3.0
	var face := Vector3.ZERO
	if _moving:
		var dir := to / dist
		var sp := RUN if _running else WALK
		sp = minf(sp, dist / maxf(delta, 0.001))
		_step(dir * sp * delta)
		face = dir
	if _cover.is_finite():
		var dc := Vector2(_cover.x - global_position.x, _cover.z - global_position.z).length()
		if dc < 1.0 and not _at_cover:
			_at_cover = true
			cover_used += 1
	var look := face
	if target != null and is_instance_valid(target) and not target.dead:
		look = Vector3(target.global_position.x - here.x, 0.0, target.global_position.z - here.z)
	elif not _moving:
		look = Vector3(-sin(p.yaw), 0.0, -cos(p.yaw)) if p != null else face
	if look.length() > 0.05:
		var want := atan2(-look.x, -look.z)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-10.0 * delta))
	rotation.y = yaw


func _follow_spot(p: Player) -> Vector3:
	var b := Vector3(sin(p.yaw), 0.0, cos(p.yaw))
	var r := Vector3(cos(p.yaw), 0.0, -sin(p.yaw))
	return p.global_position + b * 2.6 + r * 1.8


func _step(v: Vector3) -> void:
	var np := global_position + v
	if _blocked(np):
		var nx := global_position + Vector3(v.x, 0.0, 0.0)
		var nz := global_position + Vector3(0.0, 0.0, v.z)
		if not _blocked(nx) and absf(v.x) >= absf(v.z):
			np = nx
		elif not _blocked(nz):
			np = nz
		else:
			return
	np.y = _ground_y(np.x, np.z)
	global_position = np


func _blocked(at: Vector3) -> bool:
	var city := Game.world as City
	return city != null and not InteriorSpace.contains_xz(at.x, at.z) and city.is_inside_building(Vector3(at.x, 1.0, at.z))


func _ground_y(x: float, z: float) -> float:
	if InteriorSpace.contains_xz(x, z):
		return InteriorSpace.floor_y
	var city := Game.world as City
	if city != null:
		return city.ground_height(x, z, global_position.y + 1.0)
	return global_position.y


func _place_near_hero() -> void:
	var p := Game.player as Node3D
	if p == null:
		return
	var spot := _follow_spot(p as Player) if p is Player else p.global_position + Vector3(2.0, 0.0, 2.0)
	spot.y = _ground_y(spot.x, spot.z) if not InteriorSpace.contains_xz(spot.x, spot.z) else InteriorSpace.floor_y
	if _blocked(spot):
		spot = p.global_position
	global_position = spot
	_have_last = false
	if p is Player:
		yaw = (p as Player).yaw
		rotation.y = yaw


## Next to the hero at once (rescue, too far behind).
func _rush_to(at: Vector3) -> void:
	var spot := at + Vector3(1.4, 0.0, 1.0)
	if _blocked(spot):
		spot = at
	spot.y = _ground_y(spot.x, spot.z)
	global_position = spot
	_have_last = false
	_cover = Vector3.INF


# --- shooting -------------------------------------------------------------------------------------------------------

func _muzzle() -> Vector3:
	if _hanim != null and _rig != null and _root != null and _root.is_inside_tree():
		return _root.to_global(_hanim.muzzle_transform(_rig).origin)
	return global_position + Vector3(0.0, 1.35, 0.0)


func _fire(delta: float) -> void:
	if life != Life.UP or not is_instance_valid(target) or target.dead:
		_aim_t = 0.0
		_burst_left = 0
		return
	# from cover the ally ducks between bursts: it only shoots while peeking
	if _cover.is_finite() and _at_cover:
		_peek_t += delta
		if fmod(_peek_t, 3.2) > 2.2:
			_aim_t = 0.0
			_burst_left = 0
			return
	if _burst_left > 0:
		_shot_t -= delta
		if _shot_t <= 0.0:
			_shot_t = BURST_GAP
			_burst_left -= 1
			_shoot(target)
			if _burst_left == 0:
				_rest_t = BURST_REST
		return
	if _rest_t > 0.0:
		_rest_t -= delta
		return
	if _aim_t <= 0.0:
		_aim_t = WINDUP
		return
	_aim_t -= delta
	if _aim_t <= 0.0:
		_burst_left = BURST
		_shot_t = 0.0


func _shoot(t: Drone) -> void:
	var origin := _muzzle()
	var aim := t.center()
	var d := origin.distance_to(aim)
	var spread := 0.03 + 0.0025 * d
	var dir := (aim - origin).normalized()
	var off := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	dir = (dir + (off - dir * off.dot(dir)) * spread).normalized()
	var t_close := maxf((aim - origin).dot(dir), 0.0)
	var closest := origin + dir * t_close
	var miss := closest.distance_to(aim)
	var end := origin + dir * (t_close + 6.0)
	_ray.from = origin
	_ray.to = end
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var blocked := false
	if not hit.is_empty():
		end = hit["position"]
		blocked = origin.distance_to(end) < t_close - 0.3
	shots += 1
	if _hanim != null:
		_hanim.fire()
	FX.tracer(origin, end, ALLY_TRIM)
	Sfx.play_at(&"enemy_shot", origin, -8.0)
	if blocked:
		return
	if miss < t.radius and t.active and not t.dead:
		t.damage(FIRE_DMG, false)


# --- animation ------------------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _rig == null or _loco == null:
		return
	var disp := Vector3.ZERO
	if _have_last:
		disp = Vector3(global_position.x - _last_pos.x, 0.0, global_position.z - _last_pos.z)
	_last_pos = global_position
	_have_last = true
	var dt := maxf(delta, 0.001)
	var down := life == Life.DOWNED
	var firing := (_aim_t > 0.0 or _burst_left > 0) and not down
	var want_pitch := 0.0
	var look_off := 0.0
	if not down and is_instance_valid(target) and not target.dead:
		var o := _muzzle()
		var hd := maxf(Vector2(target.global_position.x - o.x, target.global_position.z - o.z).length(), 1.0)
		want_pitch = clampf(atan2(target.center().y - o.y, hd) * 0.6, -0.55, 0.65)
		look_off = angle_difference(yaw, atan2(-(target.global_position.x - o.x), -(target.global_position.z - o.z)))
	_loco.update(dt, disp, yaw, true, 0.0, 1.0 if _moving and not down else 0.0, _running and not down, firing, look_off)
	if not down:
		var st := _hanim.state
		if _aim_t > 0.0 and _burst_left == 0:
			if st != HumanoidAnim.State.WINDUP:
				_hanim.set_state(HumanoidAnim.State.WINDUP)
		elif st == HumanoidAnim.State.WINDUP:
			_hanim.set_state(HumanoidAnim.State.AIM)
		elif target != null and st == HumanoidAnim.State.IDLE:
			_hanim.set_state(HumanoidAnim.State.AIM)
		elif target == null and (st == HumanoidAnim.State.AIM):
			_hanim.set_state(HumanoidAnim.State.IDLE)
	_hanim.update(dt, want_pitch)
	_hanim.write(_rig)
	_rig.head_yaw = 0.0
	_rig.apply()


func _lod() -> void:
	var cam := Game.camera
	if cam == null or not is_instance_valid(cam) or _body == null:
		return
	HumanoidVariants.set_lod(_body, _variant, cam.global_position.distance_to(global_position))
	_apply_shadow(Game.quality >= 1)
