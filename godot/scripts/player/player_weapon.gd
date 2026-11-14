class_name PlayerWeapon
extends Node
## The player's four alien weapons (numbers in WeaponDefs): Rift Carbine (default hitscan rifle, 30 rounds, 1.3 s reload, 0.11 s interval), Shard Scatter (8 pellets, per-pellet head
## test and range falloff), Pulse Lance (hold to charge, release for a piercing shot, sniper zoom on ADS) and Singularity Grenade (thrown arc, gravity well, collapse blast through
## Game.explode). `current` is the weapon in hand; `mag`, `ammo`, `reserve`, `reload_t`, `fire_t`, `spread` always describe it (the Player's ammo / mag / reloading / spread read them).
## Every weapon keeps its own ammo and reserve (reserve < 0 = unlimited, the carbine). Switching (weapon_1..4, weapon_next / weapon_prev on the wheel, `swap` on touch) takes SWAP_TIME seconds
## during which the rig plays its quick rifle-lower animation (the reload pose) and nothing fires. Shop upgrades act on every weapon through its own base values (WeaponDefs.mag_size,
## Upgrades.damage_mult, Upgrades.reload_mult).
## The shot is a ray from the CAMERA through the crosshair (mask: world + enemy + vehicle); the tracer is drawn from the muzzle to the hit point. Targets are found two ways and the nearest
## wins: the physics ray (colliders on the enemy / vehicle layers) and a ray-sphere test against every node of group "enemy" that exposes center() and radius.
## A crit is a hit in the upper part of the target: hit.y > center().y + radius * 0.35. A shield trooper's frontal shield (shield_blocks / shield_hit) absorbs the carbine and the
## scatter; the lance and the grenade break it (break_shield). Hit data for the HUD lives on the Player: last_hit_time, last_hit_kill, last_hit_crit, plus hit_confirmed(kill, crit).
## Everything is pooled (FX tracers, the flash sprites, ImpactSparks, ImpactDecals, two grenade nodes): firing creates no nodes after the first throw.

signal weapon_changed(id: StringName)
signal grenade_collapsed(pos: Vector3)

const MAG_SIZE := 30
const RELOAD_TIME := 1.3
const FIRE_INTERVAL := 0.11
const DAMAGE := 14.0
const DAMAGE_CRIT := 30.0
const DAMAGE_VEHICLE := 9.0
const RANGE := 220.0
const CRIT_HEIGHT := 0.35                    ## of the target radius above its centre

const SPREAD_HIP := 0.014                    ## radians (half angle), src/player.js
const SPREAD_ADS := 0.004
const SPREAD_MOVE := 0.010
const BLOOM_PER_SHOT := 0.0032
const BLOOM_MAX := 0.03
const BLOOM_HOLD := 0.18                     ## seconds after a shot before the bloom starts to recover
const BLOOM_RECOVER := 0.08                  ## per second

const RECOIL_START := 0.0095                 ## camera kick per shot (radians): first shots kick hardest, settling toward RECOIL_END
const RECOIL_END := 0.0055
const RECOIL_YAW := 0.0035
const RECOIL_ADS_SCALE := 0.65               ## (kept for reference, now per weapon: def "ads_kick")
const KICK_BOOST := 1.5                      ## the owner's phone test: shots felt like nothing. Camera kick x1.5 (a visible climb per burst), shake x1.35
const NUMBER_POOL := 8
const NUMBER_LIFE := 0.7
const BURST_RESET := 0.35

const TRACER_COLOR := Color(1.0, 0.86, 0.5)
const MASK_SHOT := 1 | 4 | 8                 # world + enemy + vehicle (Game.L_*)
const MUZZLE_CLEAR := 1.2                    ## metres in front of the muzzle that must be free; beyond that the camera ray through the crosshair decides what a shot hits
const MID_BURST_KICK := 0.25                 ## camera kick share of a round that is not the last of its burst
const BURST_BLOOM := 3.0                     ## a whole burst blooms the cone once, by this many single-shot steps
const SWAP_TIME := 0.32
const GRENADE_GRAVITY := 22.0
const WELL_TICK := 0.2
const INSPECT_TIME := 1.6
const INSPECT_IDLE := 9.0                    ## seconds of doing nothing before the rifle is inspected
const AMMO_PACK0 := {&"pistol": 30, &"marksman": 12, &"breacher": 8, &"rocket": 2, &"scatter": 12, &"lance": 5, &"grenade": 2, &"burst": 24, &"rail": 6, &"flux": 60, &"gravity": 2, &"minigun": 100, &"akimbo": 24, &"arc": 14, &"revolver": 12, &"swarm": 72, &"vector": 36, &"battle": 20, &"sawn": 6, &"auto": 12, &"bolt": 6, &"dmr": 20, &"magnum": 16, &"mpistol": 60, &"stun": 8, &"ranger": 30, &"bullpup": 30, &"lmg": 100, &"amr": 5, &"xbow": 6, &"flame": 100, &"qsuper": 20, &"qlink": 24, &"qcollapse": 1, &"qblink": 24, &"qphase": 24, &"qstasis": 20, &"eplasma": 16, &"erepeat": 60, &"espike": 24, &"ebeam": 4, &"epod": 12, &"railgun": 3, &"chaingun": 150, &"cmissile": 2, &"napalm": 3, &"sing": 1, &"orbital": 1, &"seeker": 1, &"tknife": 8}
static var AMMO_PACK: Dictionary = AMMO_PACK0.merged(WeaponDefs.pack_dict("ammo_pack"))      ## the roster packs add theirs (WeaponDefs.PACKS)

var current: StringName = &"carbine"
var def: Dictionary = WeaponDefs.DEFS[&"carbine"]
var inspect_t := 0.0                         ## seconds of the idle inspect left
var ammo_type := 0                           ## index into WeaponDefs.AMMO_TYPES (hitscan weapons only; not saved)
var alt_fired := 0                           ## lifetime alt-fire counter, for tests
var _alt_k := 1.0                            ## damage scale of the shot in flight (alt-fire heavy shot), 1 otherwise
var _alt_spread := 1.0
var _alt_single := false
var _idle_t := 0.0
var _reload_click := false
var heat := 0.0                              ## Plasma Minigun: 0..1, overheats at 1
var overheated := false
var spin := 0.0                              ## Plasma Minigun barrel speed 0..1 (the fire rate follows it)
var combo := 0                               ## melee: index (0..2) of the next swing in the combo
var combo_hits := 0                          ## lifetime melee swings, for tests
var finishers := 0                           ## lifetime combo finishers
var chain_hits := 0                          ## lifetime arc-caster chain jumps
var wall_hits := 0                           ## lifetime rounds that passed a wall (AMR, PHASE RIFLE)
var stuns := 0                               ## lifetime enemies frozen by a hit (STUN GUN, STASIS RAY)
var burn_ticks := 0                          ## lifetime burn damage ticks (FLAMETHROWER)
var blinks := 0                              ## lifetime BLINK PISTOL teleports
var _burning: Dictionary = {}                ## enemy instance id -> {node, left, acc}: damage over time of the flamethrower
var arms: EnergyArms                         ## the mechanics of the ENERGY and BLAST weapons (scripts/player/energy_arms.gd)
var mech: WeaponMech                         ## the mechanics of the roster of wave 113: statuses, openers, ramps, pierce, ricochet, alt-fires (scripts/player/weapon_mech.gd)
var singularities := 0                       ## lifetime SINGULARITY ON CRIT pulses (crafted perk, scripts/progress/crafting.gd)
var _sing_t := 0.0
var overheats := 0
var _combo_t := 0.0
var _lock_t := 0.0
var _side := 1.0                             ## akimbo: which hand fires next (-1 left, 1 right)
var _burst_left := 0                ## shots still to come in the current burst (burst pistol)
var _burst_t := 0.0
var mag := MAG_SIZE
var ammo := MAG_SIZE
var reserve := -1                            ## spare rounds of the current weapon (-1 = unlimited)
var reload_t := 0.0                          ## seconds of reload left, 0 when not reloading
var reload_total := RELOAD_TIME
var fire_t := 0.0                            ## seconds until the next shot may leave the barrel
var bloom := 0.0                             ## spread added by sustained fire
var spread := SPREAD_HIP                     ## current total half angle in radians (what the crosshair shows and what the shot uses)
var shots_fired := 0                         ## lifetime counter, for tests and stats
var charge := 0.0                            ## Pulse Lance: 0..1 while the trigger is held
var swap_t := 0.0                            ## seconds of the switch animation left

var _player: Player
var _since_shot := 99.0
var _burst := 0
var _move_spread := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_b := PhysicsRayQueryParameters3D.new()
var _launch: LaunchAim                       ## the aim indicator of the launchers and grenades; its `target` is the locked enemy or car


## The kind of the weapon in hand ("hit", "charge", "throw", "melee").
func current_kind() -> String:
	return String(def["kind"])
var _exclude_base: Array[RID] = []
var _exclude: Array[RID] = []
var _decals: ImpactDecals
var _last_collider: Object                   ## collider of the last pellet ray (decal surface, breakables)
var _sparks: ImpactSparks
var _store := {}                             ## weapon id -> Vector2i(ammo, reserve) of the weapons not in hand
var _mags := {}                              ## weapon id -> magazine size last applied
var _grenades: Array[Dictionary] = []
var _grenade_mat: StandardMaterial3D
var _charge_fx := 0.0
var civilian_hits := 0                       ## lifetime shots that hit a citizen (tests)
var animal_hits := 0                         ## lifetime shots that hit an animal of the wild (WildlifeWorld, tests)
var spread_override := -1.0                  ## >= 0 forces the dispersion half angle (tests measuring pure aim; the crosshair follows it too)
var last_shot: Dictionary = {}               ## the last pellet: origin, dir (the aimed ray), muzzle, hit, dist, target (Node or null), zone, civ, blocked, spread (tests and the HUD read it)
var shells_ejected := 0                      ## lifetime counters for tests
var numbers_spawned := 0
var _numbers: Array[Label3D] = []
var _number_t: Array[float] = []
var _number_i := 0


func _ready() -> void:
	_player = get_parent() as Player
	arms = EnergyArms.new(self)
	mech = WeaponMech.new(self)
	if Game.progress != null and Game.progress.get(&"ammo_type") != null:
		ammo_type = clampi(int(Game.progress.get(&"ammo_type")), 0, WeaponDefs.AMMO_TYPES.size() - 1)     # the saved choice
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = MASK_SHOT
	_ray_b.collide_with_areas = false
	_ray_b.collide_with_bodies = true
	_ray_b.collision_mask = Game.L_WORLD | Game.L_VEHICLE
	if _player != null:
		_exclude_base = [_player.get_rid()]
		_ray_b.exclude = _exclude_base


func set_effects(decals: ImpactDecals, sparks: ImpactSparks) -> void:
	_decals = decals
	_sparks = sparks


func _mag_for(id: StringName) -> int:
	return WeaponDefs.mag_size(id, Upgrades.level(&"mag"))


## Full magazines and starting reserves for every weapon, the carbine (or the last owned weapon) in hand, nothing charging or flying.
func reset() -> void:
	_store.clear()
	for id: StringName in WeaponDefs.IDS:
		_mags[id] = _mag_for(id)
		_store[id] = Vector2i(_mag_for(id), int(WeaponDefs.def(id)["reserve"]))
	if not WeaponDefs.is_unlocked(current):
		current = &"carbine"
	_load(current)
	reload_t = 0.0
	fire_t = 0.0
	bloom = 0.0
	charge = 0.0
	swap_t = 0.0
	_clear_gun_state()
	_since_shot = 99.0
	_burst = 0
	_move_spread = 0.0
	spread = float(def["spread_hip"])
	_burning.clear()
	arms.reset()
	mech.reset()
	_clear_grenades()


func _clear_gun_state() -> void:
	heat = 0.0
	spin = 0.0
	overheated = false
	_lock_t = 0.0
	combo = 0
	_combo_t = 0.0


func _load(id: StringName) -> void:
	current = id
	def = Attachments.effective(id)
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), int(def["reserve"])))
	mag = _mag_for(id)
	_mags[id] = mag
	ammo = clampi(st.x, 0, mag)
	reserve = st.y
	reload_total = float(def["reload"]) * Upgrades.reload_mult()
	spread = float(def["spread_hip"])
	mech.on_load()
	if _player != null:
		if _player.camera_rig != null:
			_player.camera_rig.ads_fov = float(def["zoom"])
		if _player.body != null and _player.body.has_method(&"set_weapon_look"):
			_player.body.call(&"set_weapon_look", id)


func _save_current() -> void:
	_store[current] = Vector2i(ammo, reserve)


## Shop upgrades go live: every weapon's magazine follows its own base. `top_up` gives the new rounds at once (a purchase), otherwise the ammo is only clamped.
func apply_upgrades(top_up := false) -> void:
	_save_current()
	for id: StringName in WeaponDefs.IDS:
		var nw := _mag_for(id)
		var old := int(_mags.get(id, nw))
		var st: Vector2i = _store.get(id, Vector2i(nw, int(WeaponDefs.def(id)["reserve"])))
		var a := st.x + maxi(nw - old, 0) if top_up else mini(st.x, nw)
		_store[id] = Vector2i(clampi(a, 0, nw), st.y)
		_mags[id] = nw
	_load(current)


# --- switching and pickups --------------------------------------------------------------------------------------------

func switch_to(id: StringName, instant := false) -> bool:
	if id == current or not WeaponDefs.DEFS.has(id):
		return false
	if not WeaponDefs.is_unlocked(id):
		Game.say("%s  LOCKED" % WeaponDefs.title(id), 1.2)
		return false
	_save_current()
	_load(id)
	WeaponDefs.last_used = id
	WeaponDefs.last_in_class[WeaponDefs.class_of(id)] = id
	WeaponBrowser.note_used(id)
	reload_t = 0.0
	charge = 0.0
	_burst = 0
	bloom = 0.0
	_burst_left = 0
	_clear_gun_state()
	swap_t = 0.0 if instant else SWAP_TIME
	Sfx.play(&"reload", -9.0, 1.5)
	weapon_changed.emit(id)
	return true


## The next (dir 1) or previous (dir -1) owned weapon. Returns true when the weapon changed.
func cycle(dir: int) -> bool:
	var owned := WeaponDefs.owned_ordered()
	if owned.size() < 2:
		return false
	var i := owned.find(current)
	return switch_to(owned[posmod(i + dir, owned.size())])


## Keyboard 1-4, wheel and the touch SWAP button (Player calls it every physics frame on foot).
func poll_switch() -> void:
	for i in WeaponDefs.IDS.size():
		if InputMap.has_action(StringName("weapon_%d" % (i + 1))) and Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))):
			switch_to(WeaponDefs.IDS[i])
	if Input.is_action_just_pressed(&"weapon_next") or Input.is_action_just_pressed(&"swap"):
		cycle(1)
	if Input.is_action_just_pressed(&"weapon_prev"):
		cycle(-1)


## A weapon pickup: unlocks the weapon (the first time) or adds an ammo pack. Returns the message for the HUD.
func grant(id: StringName) -> String:
	if not WeaponDefs.DEFS.has(id) or id == &"carbine":
		return ""
	_save_current()
	if WeaponDefs.unlock(id):
		if not _store.has(id):
			_store[id] = Vector2i(_mag_for(id), int(WeaponDefs.def(id)["reserve"]))
		return "NEW WEAPON  %s" % WeaponDefs.title(id)
	if int(WeaponDefs.def(id)["reserve"]) < 0:
		return "%s  OWNED" % WeaponDefs.title(id)
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), 0))
	var cap := int(WeaponDefs.def(id)["reserve"]) * 2
	st.y = mini(st.y + int(AMMO_PACK.get(id, 6)), cap)
	_store[id] = st
	if id == current:
		reserve = st.y
	return "+%d %s" % [int(AMMO_PACK.get(id, 6)), WeaponDefs.title(id)]


## An ammo crate: every owned limited weapon gets `frac` of its base reserve (at most twice the base, like a pickup) and the magazine in hand is topped up. Returns the rounds given.
func restock(frac: float) -> int:
	_save_current()
	var given := 0
	for id: StringName in WeaponDefs.IDS:
		var base := int(WeaponDefs.def(id)["reserve"])
		if base <= 0 or not WeaponDefs.is_unlocked(id):
			continue
		var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), base))
		var add := maxi(1, int(ceilf(float(base) * frac)))
		var ny := mini(st.y + add, base * 2)
		given += maxi(0, ny - st.y)
		_store[id] = Vector2i(st.x, ny)
		if id == current:
			reserve = ny
	return given


## Spare rounds of any weapon (the current one live), for the HUD and tests.
func reserve_of(id: StringName) -> int:
	if id == current:
		return reserve
	var st: Vector2i = _store.get(id, Vector2i(0, int(WeaponDefs.def(id)["reserve"])))
	return st.y


func ammo_of(id: StringName) -> int:
	if id == current:
		return ammo
	var st: Vector2i = _store.get(id, Vector2i(_mag_for(id), 0))
	return st.x


## The gun in hand is dry and has no spare rounds: take the best owned weapon that still shoots (same class first, then the unlimited sidearm) instead of clicking on an empty trigger.
func _auto_swap() -> void:
	if swap_t > 0.0:
		return
	var best: StringName = &""
	var cls := WeaponDefs.class_of(current)
	for pass_i in 2:
		for id: StringName in WeaponDefs.owned_ordered():
			if id == current or String(WeaponDefs.def(id)["kind"]) == "melee":
				continue
			if pass_i == 0 and WeaponDefs.class_of(id) != cls:
				continue
			if ammo_of(id) > 0 or reserve_of(id) != 0:
				best = id
				break
		if best != &"":
			break
	if best == &"":
		best = &"blade" if WeaponDefs.is_unlocked(&"blade") else &""
	if best != &"" and switch_to(best):
		Game.say("OUT OF AMMO  %s" % WeaponDefs.title(best), 1.6)


# --- state ----------------------------------------------------------------------------------------------------------

func is_reloading() -> bool:
	return reload_t > 0.0


func cancel_reload() -> void:
	reload_t = 0.0


func start_reload() -> bool:
	if reload_t > 0.0 or ammo >= mag or swap_t > 0.0 or reserve == 0:
		return false
	reload_total = float(def["reload"]) * Upgrades.reload_mult()
	reload_t = reload_total
	charge = 0.0
	Sfx.play(&"reload", 0.0, 1.0 if current != &"scatter" else 0.85)
	_reload_click = false
	inspect_t = 0.0
	return true


func _finish_reload() -> void:
	var need := mag - ammo
	var take := need if reserve < 0 else mini(need, reserve)
	ammo += take
	if reserve >= 0:
		reserve -= take


## Advance the weapon by dt. firing / reload_pressed come from the input actions, aiming and moving from the player.
func tick(dt: float, firing: bool, reload_pressed: bool, aiming: bool, moving: bool) -> void:
	if TestMode.infinite_ammo:                                      # test mode: never dry, never reloading
		ammo = mag
		if reserve >= 0:
			reserve = maxi(reserve, int(def["reserve"]))
	if String(def["kind"]) == "melee":                              # melee never runs dry
		ammo = mag
		_combo_t -= dt
		if _combo_t <= 0.0:
			combo = 0
	if def.has("spin_up"):
		_tick_heat(dt, firing and reload_t <= 0.0 and swap_t <= 0.0)
	fire_t -= dt
	_since_shot += dt
	mech.note_input(aiming, moving, dt)
	_tick_numbers(dt)
	_tick_burn(dt)
	if String(def["kind"]) == "throw" or (_launch != null and _launch.active):
		if _launch == null:
			_launch = LaunchAim.new(self)
		_launch.update(dt, def)                                     # the landing ring, the arc and the lock bracket (scripts/player/launch_aim.gd)
	swap_t = maxf(0.0, swap_t - dt)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			reload_t = 0.0
			_finish_reload()
	if reload_pressed:
		start_reload()
	if reload_t > 0.0 and not _reload_click and reload_t < reload_total * 0.3:
		_reload_click = true                                         # the new magazine seats: a second, higher click
		Sfx.play(&"dry_fire", -6.0, 1.5 if current != &"scatter" else 0.8)
	var can_fire := reload_t <= 0.0 and swap_t <= 0.0
	if InputMap.has_action(&"altfire") and Input.is_action_just_pressed(&"altfire"):
		alt_fire(aiming)
	if InputMap.has_action(&"ammo_type") and Input.is_action_just_pressed(&"ammo_type"):
		cycle_ammo_type()
	if InputMap.has_action(&"inspect") and Input.is_action_just_pressed(&"inspect"):
		start_inspect()
	_tick_inspect(dt, firing or aiming or moving or reload_t > 0.0 or swap_t > 0.0)
	match String(def["kind"]):
		"charge":
			_tick_charge(dt, firing and can_fire, aiming)
		_:
			if firing and can_fire:
				if ammo <= 0:
					Sfx.dry_fire()
					start_reload()
				elif fire_t <= 0.0 and _gun_ready():
					_burst_left = mech.burst_n() - 1
					_burst_t = float(def.get("burst_gap", 0.07))
					match String(def["kind"]):
						"throw":
							if int(def.get("salvo", 1)) > 1:
								arms.salvo()
							else:
								_throw()
						"melee":
							_melee_swing(aiming)
						_:
							_shoot(dt, aiming)
	if _burst_left > 0 and String(def["kind"]) == "hit" and can_fire:       # the rest of a burst rides on its own short gap
		_burst_t -= dt
		if _burst_t <= 0.0 and ammo > 0:
			_burst_left -= 1
			_burst_t = float(def.get("burst_gap", 0.07))
			var keep := fire_t
			_shoot(dt, aiming)
			fire_t = maxf(keep, fire_t) if _burst_left <= 0 else keep
	elif _burst_left > 0:
		_burst_left = 0
	if _since_shot > BLOOM_HOLD:
		bloom = maxf(0.0, bloom - BLOOM_RECOVER * dt)
	if _since_shot > BURST_RESET:
		_burst = 0
	_move_spread = PlayerUtil.damp(_move_spread, float(def["spread_move"]) if moving else 0.0, 12.0, dt)
	spread = (float(def["spread_ads"]) if aiming else float(def["spread_hip"])) + bloom * (float(def["ads_spread"]) if aiming else 1.0) + _move_spread
	spread *= mech.spread_mult()
	if spread_override >= 0.0:
		spread = spread_override


## Dispersion applied to a unit direction: uniform inside a cone of half angle `angle` around `dir`, using the camera basis.
static func jitter_dir(basis: Basis, angle: float, rng_a: float, rng_r: float) -> Vector3:
	var fwd := -basis.z
	var a := rng_a * TAU
	var r := angle * sqrt(rng_r)
	return (fwd + basis.x * (cos(a) * r) + basis.y * (sin(a) * r)).normalized()


## The half angle of the cone a shot is rolled in right now: what the crosshair shows (tests can pin it with spread_override).
func cone() -> float:
	return spread_override if spread_override >= 0.0 else spread


## [origin, dir] of an aim ray: the camera through the crosshair with `sp` half angle of dispersion, starting at the player's depth.
func _aim_ray(sp: float) -> Array:
	var rig := _player.camera_rig
	var cam := rig.camera
	var cam_pos := cam.global_position
	var dir := jitter_dir(cam.global_basis, sp, randf(), randf())
	var along := maxf(0.0, (rig.get_pivot_position() - cam_pos).dot(dir))
	return [cam_pos + dir * along, dir]


func _recoil(aiming: bool) -> void:
	var rig := _player.camera_rig
	var k := clampf(float(_burst - 1) / 10.0, 0.0, 1.0)
	var step := WeaponDefs.pattern_at(current, _burst - 1)
	var kick := lerpf(float(def["kick"]), float(def["kick_end"]), k) * step.y * randf_range(0.92, 1.08)
	var kick_yaw := (step.x + randf_range(-0.15, 0.15)) * float(def["kick_yaw"])
	var bm := mech.kick_mult()
	kick *= bm
	kick_yaw *= bm
	if aiming:
		kick *= float(def["ads_kick"])
		kick_yaw *= float(def["ads_kick"])
	var mid_burst := _burst_left > 0 and String(def["kind"]) == "hit"      # the rounds of a burst leave on one line: the view kicks (almost) only after the last one, and the cone does not bloom between them
	var burst_k := MID_BURST_KICK if mid_burst else 1.0
	rig.kick(kick * KICK_BOOST * burst_k, kick_yaw * KICK_BOOST * burst_k)
	FX.shake(float(def["shake"]) * (0.6 if aiming else 1.0) * 1.35)
	rig.punch(0.03 if String(def["kind"]) == "hit" and int(def["pellets"]) == 1 else 0.07)
	if not mid_burst:
		bloom = minf(float(def["bloom_max"]), bloom + float(def["bloom"]) * (BURST_BLOOM if int(def.get("burst", 1)) > 1 else 1.0))


# --- carbine and scatter (hitscan) ------------------------------------------------------------------------------------

func _shoot(dt: float, aiming: bool) -> void:
	var p := _player
	mech.on_shoot()
	ammo -= 1
	shots_fired += 1
	fire_t = maxf(fire_t, -dt) + float(def["interval"]) * float(ammo_info()["rate"]) * _spin_mult() * mech.interval_mult()      # keep the cadence exact whatever the tick rate, without banking shots
	_since_shot = 0.0
	_burst += 1
	var pellets := 1 if _alt_single else int(def["pellets"])
	Sfx.play(Sfx.shot_sound(StringName(def.get("snd", &"shot")), Attachments.part_in(current, &"barrel") == &"suppressor"), float(def["vol"]), randf_range(float(def["pitch_lo"]), float(def["pitch_hi"])))
	if def.has("heat_per"):
		heat = minf(1.0, heat + float(def["heat_per"]))
		if heat >= 1.0 and not overheated:
			_overheat()
	var gm := Game.enemies as EnemyManager
	if gm != null and is_instance_valid(p) and float(def["vol"]) > -20.0 and not bool(def.get("silent", false)):
		Stealth.noise(gm.list, p.global_position, &"gun")
	if pellets > 1 and not bool(def.get("flame", false)):
		Sfx.play(&"explosion_small", -8.0, randf_range(1.4, 1.6))
	if int(def["eject"]) > 0:
		_eject_shell()
	for i in pellets:
		_trace_pellet()
	p.body.fire_flash(float(def["flash"]))
	_recoil(aiming)
	if def.has("twin"):
		_side = -_side
	p.fired.emit()


func _trace_pellet() -> void:
	var p := _player
	if def.has("cone"):                                                 # SONIC CANNON / KINETIC REPULSOR: a cone of force, no ray (WeaponMech)
		mech.cone_fire()
		return
	var ar := _aim_ray(cone() * _alt_spread)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var range_m := float(def["range"])
	var best := range_m
	var target: Node = null
	var normal := Vector3.ZERO
	var space := p.get_world_3d().direct_space_state
	_last_collider = null
	_exclude.assign(_exclude_base)
	_ray.from = origin
	_ray.to = origin + dir * range_m
	var walls_left := int(def.get("wall", 0))                       # AMR / PHASE RIFLE: the round goes through that many walls (not the ground), each one costs wall_k of the damage
	var wall_k := 1.0
	var pierced: Array[Dictionary] = []                             # the cars the round went through: each takes it (wave 113 critic: the AMR passed through a car and never hurt it)
	for _attempt in 6 + walls_left:
		_ray.exclude = _exclude
		var res := space.intersect_ray(_ray)
		if res.is_empty():
			break
		var hit_pos: Vector3 = res["position"]
		var hit_target := _damageable_of(res["collider"] as Node)
		if hit_target != null and (_is_dead(hit_target) or hit_target.has_method(&"hit_ray")):
			_exclude.append(res["rid"])          # a corpse does not stop bullets; people are tested on their real shape below (HitZones), not on the physics blob
			continue
		if walls_left > 0 and (hit_target == null or hit_target.is_in_group(&"vehicle")) and absf((res["normal"] as Vector3).y) < 0.7:
			if hit_target != null:
				pierced.append({"t": hit_target, "pos": hit_pos, "n": res["normal"], "k": wall_k})
			walls_left -= 1
			wall_k *= float(def.get("wall_k", 0.7))
			wall_hits += 1
			_exclude.append(res["rid"])
			continue
		best = origin.distance_to(hit_pos)
		normal = res["normal"]
		target = hit_target
		_last_collider = res["collider"]
		break
	# every enemy is tested on its own shape: head sphere + body capsule for a person, a sphere for a drone (HitZones); the nearest hit of all wins
	var zone: StringName = &""
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or _is_dead(e):
			continue
		var zh := HitZones.of(e, origin, dir)
		if zh.is_empty():
			continue
		var t := float(zh["t"])
		if t < best:
			best = t
			target = e
			zone = zh["zone"]
			normal = -dir
	# the people of the street: a shot at a citizen in front of the wall hits the citizen
	var civ := _civilian_ray(origin, dir, best)
	if not civ.is_empty():
		best = float(civ["t"])
		target = null
		zone = &""
		normal = -dir
	# the animals of the wild: deer, wolves, birds, sharks ... (WildlifeWorld.ray), the nearest of all the things in the line wins
	var animal := _animal_ray(origin, dir, best)
	if not animal.is_empty():
		best = float(animal["t"])
		target = null
		zone = &""
		normal = -dir
		civ = {}
	var hit := origin + dir * best
	var hit_something := best < range_m - 0.001

	# --- the barrel: poking into a wall, or cover right in front of the muzzle
	var mz := p.body.muzzle.global_position
	var anchor := p.camera_rig.get_pivot_position()
	var blocked := _blocked_between(space, anchor, mz) if not def.has("wall") else {}
	if blocked.is_empty() and not def.has("wall"):                                          # cover right in front of the muzzle; nothing farther out: the crosshair is the truth, a lamp post or a corner beside the line never eats a shot the player sees land
		var to_hit := hit - mz
		var reach := minf(to_hit.length(), MUZZLE_CLEAR)
		if reach > 0.05:
			blocked = _blocked_between(space, mz, mz + to_hit.normalized() * reach)
	if not blocked.is_empty():
		hit = blocked["position"]
		normal = blocked["normal"]
		target = _damageable_of(blocked["collider"] as Node)
		hit_something = true
		civ = {}
		animal = {}

	if def.has("twin"):                                             # akimbo: the shot leaves the hand whose turn it is
		mz += p.camera_rig.camera.global_basis.x * (_side * 0.16)
	last_shot = {"origin": origin, "dir": dir, "muzzle": mz, "hit": hit, "dist": best, "target": target, "zone": zone, "civ": not civ.is_empty(), "blocked": not blocked.is_empty(), "spread": cone() * _alt_spread, "frame": Engine.get_physics_frames()}
	for pv: Dictionary in pierced:                                    # a round that crosses a car hurts it (hole, glass, hit marker) before the hit beyond goes on with what is left of it
		if is_instance_valid(pv["t"]) and not _is_dead(pv["t"]):
			var real := last_shot
			last_shot = real.duplicate()
			last_shot["target"] = pv["t"]
			last_shot["hit"] = pv["pos"]
			last_shot["zone"] = &""
			last_shot["civ"] = false
			_hit_target(pv["t"], pv["pos"], pv["n"], float(pv["k"]))
			last_shot = real
	if bool(def.get("flame", false)):                               # a spray of fire along the line, not a laser
		_flame_puffs(mz, hit)
	elif def.has("mist"):                                           # the cold and toxic sprayers: a coloured mist along the line
		mech.mist_puffs(mz, hit)
	else:
		FX.tracer(mz, hit, def["tracer"])
		FX.qvfx.weapon_shot(current, mz, hit)

	var from_d := float(def["falloff_from"])
	var k := wall_k
	if mz.distance_to(hit) > from_d:
		k = lerpf(1.0, 0.25, clampf((mz.distance_to(hit) - from_d) / maxf(range_m - from_d, 1.0), 0.0, 1.0))
	if target != null and not _is_dead(target):
		_hit_target(target, hit, normal, k, zone)
		if def.has("chain"):
			_chain(target, hit, k)
	elif not civ.is_empty():
		_hit_civilian(civ, hit, dir, k)
	elif not animal.is_empty():
		_hit_animal(animal, hit, dir, k)
	elif hit_something:
		_hit_world(hit, normal)
	if def.has("splash") and (hit_something or target != null):          # plasma pop, explosive round, beam impact: a blast where the round landed (EnergyArms)
		arms.splash(hit, shots_fired)
	mech.after_shot(last_shot, k)                                    # pierce_n, ricochet (WeaponMech)


## FLAMETHROWER: fire puffs along the line muzzle -> hit (the fire colour of BlastElements), pooled FX bursts.
func _flame_puffs(mz: Vector3, hit: Vector3) -> void:
	var d := hit - mz
	var n := 2 if Game.quality == 0 else 3
	for i in n:
		var t := (float(i) + randf()) / float(n)
		FX.burst(mz + d * t, Color(1.0, 0.45 + 0.3 * (1.0 - t), 0.1), 3, 2.5 + 2.0 * t, 0.35 + 0.2 * t, -2.0, 1.0 + 1.6 * t)


## The first person of the street a ray meets before `max_t` (AmbientCity.civilian_ray), {} for none.
func _civilian_ray(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var city := Game.world as City
	if city == null or city.ambient == null:
		return {}
	return city.ambient.civilian_ray(origin, dir, max_t)


## The nearest animal of the wild a ray meets before `max_t` (WildlifeWorld.ray): {c, t, head} or {}.
func _animal_ray(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var w := WildlifeWorld.instance
	if w == null or not w.enabled or w.critters.is_empty():
		return {}
	return w.ray(origin, dir, max_t)


## A shot hit an animal: damage, the usual hit sound / marker, a spark; the wildlife handles flight, the dust death and the bounty.
func _hit_animal(an: Dictionary, hit: Vector3, dir: Vector3, k: float) -> void:
	var w := WildlifeWorld.instance
	var c := an["c"] as Critter
	if w == null or not is_instance_valid(c):
		return
	var p := _player
	k *= _alt_k * float(ammo_info()["dmg"])
	var amount := TestMode.damage(float(def["damage"]) * k * Upgrades.damage_mult() * HeroPower.f("dmg"))
	var kill := w.hurt(c, amount, true, p.global_position)
	_hit_sound(kill, false)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = false
	p.last_hit_crit = false
	p.hit_confirmed.emit(kill, false)
	animal_hits += 1
	_damage_number(hit, amount, false, kill)
	if _sparks != null:
		_sparks.impact_person(hit, -dir)


## A shot hit a citizen: damage (a head shot doubles), the usual hit sound / marker, a spark, and the consequences from the city (scream, heat, drops).
func _hit_civilian(civ: Dictionary, hit: Vector3, dir: Vector3, k: float) -> void:
	var city := Game.world as City
	var p := _player
	k *= _alt_k * float(ammo_info()["dmg"])
	var head: bool = civ["head"]
	var amount := TestMode.damage(float(def["damage"]) * k * Upgrades.damage_mult() * HeroPower.f("dmg"))
	var kill: bool = city.ambient.hurt_civilian(int(civ["i"]), amount, p.global_position, head)
	_hit_sound(kill, head)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = false                                    # the HUD's kill streak is for enemies
	p.last_hit_crit = head
	p.hit_confirmed.emit(kill, head)
	civilian_hits += 1
	if _sparks != null:
		_sparks.impact_person(hit, -dir)


## Is the segment a -> b blocked by the world or a vehicle? Returns the ray result (empty = clear).
func _blocked_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var d := b - a
	var dist := d.length()
	if dist < 0.08:
		return {}
	_ray_b.from = a
	_ray_b.to = a + d * (1.0 - 0.025 / dist)
	return space.intersect_ray(_ray_b)


func _hit_target(target: Node, hit: Vector3, normal: Vector3, k := 1.0, zone: StringName = &"") -> void:
	var p := _player
	k *= _alt_k * float(ammo_info()["dmg"]) * mech.hit_mult(target)
	var is_vehicle := target.is_in_group(&"vehicle") and not target.is_in_group(&"enemy")
	var crit := false
	var human := false
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	if not is_vehicle:
		var c := Vector3.ZERO
		if target.has_method(&"center"):
			c = target.call(&"center")
		else:
			c = (target as Node3D).global_position
		var r := _radius_of(target)
		if zone == &"":                                             # no zone from the ray (melee, chains): the old upper-third rule
			zone = HitZones.HEAD if (r > 0.0 and hit.y > c.y + r * CRIT_HEIGHT) else HitZones.BODY
		crit = zone == HitZones.HEAD
		human = target is Operative or target.get(&"type") == &"operative"
		var base_dmg := float(def["crit"]) if crit else float(def["damage"]) * (HitZones.LEG_MULT if zone == HitZones.LEGS else 1.0)
		var amount := TestMode.damage(base_dmg * k * Upgrades.damage_mult() * HeroPower.f("dmg"))
		if target.has_method(&"shield_blocks"):
			if bool(def["pierce_shield"]) or bool(ammo_info()["pierce"]):
				target.call(&"break_shield")
			elif bool(target.call(&"shield_blocks", p.global_position)):
				target.call(&"shield_hit", amount, hit)                     # the frontal shield eats it: no damage, a cyan spark
				p.last_hit_time = PlayerUtil.now()
				p.last_hit_kill = false
				p.last_hit_crit = false
				p.hit_confirmed.emit(false, false)
				if _sparks != null:
					_sparks.impact_machine(hit, n)
				return
		target.call(&"damage", amount, crit)
		if target.has_method(&"stagger"):
			target.call(&"stagger", AimAssist.stagger_for(current))
		if def.has("stun") and not _is_dead(target):
			_stun(target)
		if def.has("burn") and not _is_dead(target):
			_ignite(target)
		if def.has("stick") and not _is_dead(target):
			arms.stick(target, hit)
		mech.on_hit(target, hit, crit)
	else:
		target.call(&"damage", DAMAGE_VEHICLE * float(def["damage"]) / DAMAGE * k)
	var kill := (not is_vehicle) and _is_dead(target)
	_hit_sound(kill, crit)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = kill
	p.last_hit_crit = crit
	p.hit_confirmed.emit(kill, crit)
	if kill:
		mech.on_kill(target)
		GameFeel.fire(&"heavy_kill" if GameFeel.is_heavy_kill(crit, current) else &"kill")
	if crit and not is_vehicle and def.has("sing"):
		_singularity(hit, target)
	_damage_number(hit, float(def["damage"]) * k * Upgrades.damage_mult() if not crit else float(def["crit"]) * k * Upgrades.damage_mult(), crit, kill)
	if _sparks != null:
		if is_vehicle:
			_sparks.impact_machine(hit, n)
		elif human:
			if Game.graphic_violence:
				_sparks.impact_blood(hit, n)
			_sparks.impact_person(hit, n)
		else:
			_sparks.impact_machine(hit, n)


## SINGULARITY ON CRIT (crafted perk): a crit pulls every enemy near the hit toward it and burns them, at most once per cooldown.
func _singularity(at: Vector3, victim: Node) -> void:
	var s: Dictionary = def["sing"]
	var now := PlayerUtil.now()
	if now < _sing_t:
		return
	_sing_t = now + float(s["cd"])
	singularities += 1
	var radius := float(s["radius"])
	FX.burst(at, WeaponDefs.COLLAPSE_COLOR, 12, 5.0, 0.4, 0.0, 1.0)
	Sfx.play_at(&"superpos", at, -8.0, 0.9)
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if e == victim or not (e is Node3D) or _is_dead(e):
			continue
		var en := e as Node3D
		var off := Vector3(at.x - en.global_position.x, 0.0, at.z - en.global_position.z)
		var dist := off.length()
		if dist > radius:
			continue
		if dist > 1.2:
			en.global_position += off / dist * minf(float(s["pull"]), dist - 1.0)
		e.call(&"damage", float(s["dmg"]) * Upgrades.damage_mult(), false)


## A spent casing leaves the ejection port to the right of the rifle: real tumbling brass (FX.casings, one draw call) and a tiny spark where it left.
func _eject_shell() -> void:
	if _player == null or _player.body == null or _player.body.muzzle == null:
		return
	shells_ejected += 1
	var cam := _player.camera_rig.camera.global_basis
	var port := _player.body.muzzle.global_position + cam.z * 0.45 + cam.x * 0.1 - Vector3(0.0, 0.05, 0.0)       # behind the muzzle, towards the shooter's hand
	var vel := cam.x * randf_range(2.4, 3.6) + Vector3.UP * randf_range(2.2, 3.4) + cam.z * randf_range(0.4, 1.2)
	FX.casings.eject(port, vel, _player.global_position.y)
	FX.burst(port, Color(1.0, 0.8, 0.35), 1, 2.2, 0.3, 9.0, 0.5)


## Floating damage number at a hit: a pooled Label3D (8 of them), crits larger and gold, a kill red, it rises and fades in 0.7 s.
func _damage_number(pos: Vector3, amount: float, crit: bool, kill: bool) -> void:
	if _player == null or not Game.damage_numbers:
		return
	if _numbers.is_empty():
		for i in NUMBER_POOL:
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.fixed_size = true
			l.pixel_size = 0.0012
			l.outline_size = 6
			l.top_level = true
			l.visible = false
			_player.add_child(l)
			_numbers.append(l)
			_number_t.append(0.0)
	var i := _number_i
	_number_i = (_number_i + 1) % NUMBER_POOL
	var l := _numbers[i]
	l.text = str(int(roundf(amount)))
	l.font_size = 40 if crit else 28
	l.modulate = Color(1.0, 0.85, 0.3) if crit else (Color(1.0, 0.35, 0.3) if kill else Color(1.0, 1.0, 1.0))
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.3, 0.0)
	l.visible = true
	_number_t[i] = NUMBER_LIFE
	numbers_spawned += 1


func _tick_numbers(dt: float) -> void:
	for i in _numbers.size():
		if _number_t[i] <= 0.0:
			continue
		_number_t[i] -= dt
		var l := _numbers[i]
		if _number_t[i] <= 0.0:
			l.visible = false
		else:
			l.global_position += Vector3(0.0, 1.2 * dt, 0.0)
			l.modulate.a = clampf(_number_t[i] / (NUMBER_LIFE * 0.5), 0.0, 1.0)


func _hit_world(hit: Vector3, normal: Vector3) -> void:
	var n := normal if normal != Vector3.ZERO else Vector3.UP
	var is_prop := is_instance_valid(_last_collider) and (_last_collider as Node).has_meta(&"surface")
	var surface := Breakables.surface_of(_last_collider) if is_prop else ImpactSparks.surface_at(hit, n)           # a prop knows its material; the street and the facades are told apart by where the hit is (wave 113: asphalt, glass and concrete holes differ)
	if is_instance_valid(_last_collider) and Breakables.current != null:
		Breakables.current.hit_at(_last_collider, hit, n)
	if is_instance_valid(_last_collider) and WorldBlasters.current != null:
		WorldBlasters.current.hit_collider(_last_collider, hit, maxf(1.0, float(def["damage"]) / 14.0))          # a shot barrel, gas tank or fuel truck goes off (scripts/combat/world_blasters.gd)
	if _sparks != null:
		_sparks.impact_world(hit, n, surface if is_prop else &"")
	if _decals != null:
		_decals.add(hit, n, randf_range(0.22, 0.3), surface)


# --- Pulse Lance --------------------------------------------------------------------------------------------------------

func _tick_charge(dt: float, firing: bool, aiming: bool) -> void:
	var need := float(def["charge_time"])
	if firing and ammo > 0 and fire_t <= 0.0:
		if charge <= 0.0:
			Sfx.play(&"link", -8.0, 0.8)
		charge = minf(1.0, charge + dt / need)
		_charge_fx -= dt
		if _charge_fx <= 0.0:                               # the charge is visible: a growing flare at the muzzle, a spark ring at full charge
			_charge_fx = 0.07
			var mz := _player.body.muzzle.global_position
			FX.muzzle_flash(mz, -_player.camera_rig.camera.global_basis.z, def["tracer"], 0.5 + charge * 2.2)
			if charge >= 1.0:
				FX.burst(mz, def["tracer"], 3, 2.0, 0.2, 0.0, 0.8)
	elif charge > 0.0:
		var c := charge
		charge = 0.0
		if c >= float(def["min_charge"]) and ammo > 0 and fire_t <= 0.0 and reload_t <= 0.0 and swap_t <= 0.0:
			_fire_lance(c, aiming)
	elif firing and ammo <= 0 and fire_t <= 0.0:
		Sfx.dry_fire()
		start_reload()


func _fire_lance(c: float, aiming: bool) -> void:
	var p := _player
	ammo -= 1
	shots_fired += 1
	fire_t = float(def["interval"])
	_since_shot = 0.0
	_burst = 1
	if c >= 0.95:
		Sfx.play(Sfx.shot_sound(&"shot", false, true), 0.0, 1.0)             # a full charge: the overcharged shot (sub fall, plasma zap, shimmering tail)
	else:
		Sfx.play(&"boom", -8.0, 1.7)
		Sfx.play(&"shot", 0.0, 0.7)
	var ar := _aim_ray(cone())
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var range_m := float(def["range"])
	var space := p.get_world_3d().direct_space_state
	_ray_b.from = origin
	_ray_b.to = origin + dir * range_m
	var walls_left := int(def.get("wall", 0))                      # PRISM BEAM RIFLE / COIL RAILGUN: the beam goes through that many walls (not the ground, not a car), each costs wall_k of the damage behind it
	var skip: Array[RID] = _exclude_base.duplicate()
	var passed: Array[float] = []
	var wall := {}
	for _w in 1 + walls_left:
		_ray_b.exclude = skip
		wall = space.intersect_ray(_ray_b)
		if wall.is_empty():
			break
		if walls_left > 0 and _damageable_of(wall["collider"] as Node) == null and absf((wall["normal"] as Vector3).y) < 0.7:
			walls_left -= 1
			wall_hits += 1
			passed.append(origin.distance_to(wall["position"]))
			skip.append(wall["rid"])
			continue
		break
	_ray_b.exclude = _exclude_base
	var wall_t := range_m
	var wall_normal := Vector3.UP
	var wall_collider: Node = null
	if not wall.is_empty():
		wall_t = origin.distance_to(wall["position"])
		wall_normal = wall["normal"]
		wall_collider = wall["collider"] as Node
	var victims: Array = []                                 # [t, enemy] sorted by distance
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or _is_dead(e):
			continue
		var zh := HitZones.of(e, origin, dir)
		if zh.is_empty():
			continue
		var t := float(zh["t"])
		if t < wall_t:
			var at := victims.size()
			while at > 0 and float(victims[at - 1][0]) > t:
				at -= 1
			victims.insert(at, [t, e, zh["zone"]])
	var scale := lerpf(0.35, 1.0, clampf((c - float(def["min_charge"])) / (1.0 - float(def["min_charge"])), 0.0, 1.0))
	for _pierced in 4:                                       # the beam goes through the people of the street too
		var civ := _civilian_ray(origin, dir, wall_t)
		if civ.is_empty():
			break
		_hit_civilian(civ, origin + dir * float(civ["t"]), dir, scale * 4.0)
	for _pierced_a in 3:                                     # ... and through the animals
		var an := _animal_ray(origin, dir, wall_t)
		if an.is_empty():
			break
		_hit_animal(an, origin + dir * float(an["t"]), dir, scale * 4.0)
	var mz := p.body.muzzle.global_position
	var end := origin + dir * wall_t
	FX.tracer(mz, end, def["tracer"])
	FX.qvfx.weapon_shot(current, mz, end)
	p.body.fire_flash(float(def["flash"]))
	for v: Array in victims:
		var e: Node = v[1]
		if is_instance_valid(e) and not _is_dead(e):
			var k := scale
			for pw in passed:
				if pw < float(v[0]):
					k *= float(def.get("wall_k", 0.7))
			_hit_target(e, origin + dir * float(v[0]), -dir, k, v[2])
	if wall_collider != null:
		var veh := _damageable_of(wall_collider)
		if veh != null and veh.is_in_group(&"vehicle") and not veh.is_in_group(&"enemy"):
			_hit_target(veh, end, wall_normal, scale * 3.0)
		else:
			_hit_world(end, wall_normal)
	if def.has("splash"):                                    # the beam burns out whatever it ends on: a blast at the end point (EnergyArms)
		if wall_collider != null:
			arms.splash(end, 0)
		elif not victims.is_empty():
			arms.splash(origin + dir * float((victims[victims.size() - 1] as Array)[0]), 0)
	_recoil(aiming)
	p.fired.emit()


# --- Singularity Grenade ----------------------------------------------------------------------------------------------

## `quiet` = the caller plays the launch sound once for a salvo; `opts`: wid (a PROJ sub-def thrown instead of the weapon), airburst (burst in the air over the aim point), dive (top attack).
func _throw(yaw_off := 0.0, quiet := false, opts := {}) -> void:
	var p := _player
	ammo -= 1
	shots_fired += 1
	fire_t = float(def["interval"])
	_since_shot = 0.0
	_burst = 1
	if def.has("bid"):                                       # the BLAST ARSENAL (scripts/combat/blast_ops.gd): its own flight, fuse, mines and strike markers
		BlastOps.weapon_fire(self, yaw_off, opts)
		return
	Sfx.play(&"blink", -6.0, 1.6)
	if bool(def.get("launch", false)) and not quiet:
		Sfx.play(StringName(def.get("snd", &"shot")), float(def.get("vol", -2.0)), randf_range(float(def["pitch_lo"]), float(def["pitch_hi"])))
	var ar := _aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var space := p.get_world_3d().direct_space_state
	_ray_b.from = origin
	_ray_b.to = origin + dir * float(def["range"])
	var res := space.intersect_ray(_ray_b)
	var aim_pt: Vector3 = res["position"] if not res.is_empty() else origin + dir * 40.0
	if _launch != null and is_instance_valid(_launch.target) and not _is_dead(_launch.target) and yaw_off == 0.0:      # a launcher locked on: the round is thrown at the target
		aim_pt = _launch.landing
	var from := p.body.muzzle.global_position
	var delta := aim_pt - from
	if yaw_off != 0.0:
		delta = delta.rotated(Vector3.UP, yaw_off)
	var flat := Vector2(delta.x, delta.z).length()
	var wid := StringName(opts.get("wid", current))
	var td: Dictionary = WeaponDefs.PROJ[wid] if WeaponDefs.PROJ.has(wid) else def                # the projectile's own numbers (the plasma pistol's overcharge ball) or the weapon's
	var t := clampf(flat / float(td["speed"]), 0.3, 2.0)
	var g := _free_grenade()
	g["state"] = 0
	g["wid"] = wid
	g["guided"] = bool(def.get("guided", false))
	g["dive"] = bool(opts.get("dive", false))
	g.erase("fuse")
	g["pos"] = from
	var grav := float(td.get("grav", GRENADE_GRAVITY))
	g["grav"] = grav
	g["vel"] = Vector3(delta.x / t, delta.y / t + 0.5 * grav * t, delta.z / t)
	if bool(opts.get("airburst", false)):                   # AIRBURST: the missile opens in the air, 3.5 m above the aim point, and the bomblets rain down on it
		delta.y += 3.5
		g["vel"] = Vector3(delta.x / t, delta.y / t + 0.5 * grav * t, delta.z / t)
		g["fuse"] = t * 0.985
	if bool(opts.get("dive", false)):                       # TOP ATTACK: the guidance climbs first (EnergyArms.steer), so give it a head start straight up
		g["vel"] = Vector3(0.0, float(def["speed"]) * 0.9, 0.0) + Vector3(delta.x, 0.0, delta.z).normalized() * float(def["speed"]) * 0.35
		g["guided"] = true
	g["t"] = 0.0
	var node: MeshInstance3D = g["node"]
	node.global_position = from
	node.scale = Vector3.ONE * 0.26
	node.visible = true
	p.body.fire_flash(0.7)
	_recoil(false)
	p.fired.emit()


func _free_grenade() -> Dictionary:
	for g in _grenades:
		if int(g["state"]) < 0:
			return g
	if _grenades.size() >= int(def.get("slots", 2)):          # all busy: the oldest collapses early and gives its slot (the multi-round weapons keep more slots, WeaponDefs `slots`)
		var oldest := _grenades[0]
		for g in _grenades:
			if float(g["t"]) > float(oldest["t"]):
				oldest = g
		_collapse(oldest)
		return oldest
	if _grenade_mat == null:
		_grenade_mat = StandardMaterial3D.new()
		_grenade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_grenade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grenade_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_grenade_mat.albedo_color = Color(0.75, 0.35, 1.0, 0.6)
		_grenade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	sm.material = _grenade_mat
	node.mesh = sm
	node.top_level = true
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.add_child(node)
	var g := {"node": node, "state": -1, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "t": 0.0, "well": 0.0, "tick": 0.0}
	_grenades.append(g)
	return g


func _clear_grenades() -> void:
	for g in _grenades:
		g["state"] = -1
		(g["node"] as Node3D).visible = false


## Live grenades (flying or in the well phase), for tests and the bot.
func grenades_active() -> int:
	var n := 0
	for g in _grenades:
		if int(g["state"]) >= 0:
			n += 1
	return n


func well_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for g in _grenades:
		if int(g["state"]) == 1:
			out.append(g["pos"])
	return out


func _physics_process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_physics_process_body(delta)
	PerfTimers.stop(PerfTimers.PLAYER, t0)


func _physics_process_body(delta: float) -> void:
	if not Game.is_playing():
		return
	arms.tick(delta)
	mech.tick(delta)
	if _grenades.is_empty():
		return
	for g in _grenades:
		match int(g["state"]):
			0:
				_fly(g, delta)
			1:
				_well(g, delta)


func _fly(g: Dictionary, dt: float) -> void:
	if bool(g.get("guided", false)):
		arms.steer(g, dt)
	var vel: Vector3 = g["vel"]
	vel.y -= float(g.get("grav", GRENADE_GRAVITY)) * dt
	g["vel"] = vel
	var pos: Vector3 = g["pos"]
	var nxt := pos + vel * dt
	g["t"] = float(g["t"]) + dt
	_ray_b.from = pos
	_ray_b.to = nxt
	var res := _player.get_world_3d().direct_space_state.intersect_ray(_ray_b)
	var land := false
	if not res.is_empty():
		nxt = (res["position"] as Vector3) + (res["normal"] as Vector3) * 0.25
		land = true
	else:
		for e: Node in get_tree().get_nodes_in_group(&"enemy"):
			if e is Node3D and e.has_method(&"center") and not _is_dead(e) and (e.call(&"center") as Vector3).distance_to(nxt) < _radius_of(e) + 0.3:
				land = true
				break
	g["pos"] = nxt
	(g["node"] as Node3D).global_position = nxt
	if land or float(g["t"]) >= float(g.get("fuse", _gdef(g)["fuse"])):
		_start_well(g)


## The definition a thrown projectile uses (the grenade or the gravity launcher that threw it).
func _gdef(g: Dictionary) -> Dictionary:
	var wid: StringName = g.get("wid", &"grenade")
	if WeaponDefs.PROJ.has(wid):
		return WeaponDefs.PROJ[wid]
	return WeaponDefs.def(wid)


static func def_of_grenade() -> Dictionary:
	return WeaponDefs.DEFS[&"grenade"]


func _start_well(g: Dictionary) -> void:
	var d := _gdef(g)
	if bool(d.get("impact", false)):                        # grenade launcher: a short pull, then the blast at once (no well)
		var ip: Vector3 = g["pos"]
		for e: Node in get_tree().get_nodes_in_group(&"enemy"):
			if e is Node3D and not _is_dead(e):
				var off := ip - (e as Node3D).global_position
				off.y = 0.0
				var dist := off.length()
				if dist < float(d["well_radius"]) * 0.6 and dist > 1.4:
					(e as Node3D).global_position += off / dist * minf(float(d.get("impact_pull", 3.0)), dist - 1.2)
		_collapse(g)
		return
	g["state"] = 1
	g["well"] = float(d["well_time"])
	g["tick"] = 0.0
	FX.burst(g["pos"], WeaponDefs.COLLAPSE_COLOR, 16, 7.0, 0.5, 0.0, 1.2)
	Sfx.play_at(&"superpos", g["pos"], -4.0, 0.7)


func _well(g: Dictionary, dt: float) -> void:
	var d := _gdef(g)
	var pos: Vector3 = g["pos"]
	var left := float(g["well"]) - dt
	g["well"] = left
	var life := 1.0 - left / float(d["well_time"])
	var node: MeshInstance3D = g["node"]
	node.scale = Vector3.ONE * (0.6 + 2.6 * life + 0.25 * sin(life * 40.0))
	var radius := float(d["well_radius"])
	var pull := float(d["well_pull"])
	var tick := float(g["tick"]) + dt
	var hurt := false
	if tick >= WELL_TICK:
		tick -= WELL_TICK
		hurt = true
		FX.burst(pos + Vector3(randf_range(-radius, radius), 0.4, randf_range(-radius, radius)) * 0.3, WeaponDefs.COLLAPSE_COLOR, 5, -3.0, 0.4, 0.0, 0.9)
	g["tick"] = tick
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or _is_dead(e):
			continue
		var en := e as Node3D
		var off := Vector3(pos.x - en.global_position.x, 0.0, pos.z - en.global_position.z)
		var dist := off.length()
		if dist > radius:
			continue
		if e.has_method(&"break_shield"):
			e.call(&"break_shield")
		if dist > 1.4:
			en.global_position += off / dist * (pull * (0.45 + 0.55 * (1.0 - dist / radius)) * dt)
		if hurt:
			e.call(&"damage", float(d["well_dps"]) * WELL_TICK * Upgrades.damage_mult(), false)
	if left <= 0.0:
		_collapse(g)


func _collapse(g: Dictionary) -> void:
	var d := _gdef(g)
	var pos: Vector3 = g["pos"]
	g["state"] = -1
	(g["node"] as Node3D).visible = false
	if arms.on_collapse(d, pos):                            # the orbital beacon plants itself, the strike comes later
		grenade_collapsed.emit(pos)
		return
	Game.explode(pos + Vector3(0.0, 0.5, 0.0), float(d["blast_radius"]), {"blast": StringName("w_%s" % String(g.get("wid", &"grenade"))), "dmg_mult": Upgrades.damage_mult(), "source": _player, "by_hero": true,
			"enemy_dmg": float(d.get("blast_damage", d["damage"])), "car_dmg": float(d.get("car_dmg", 40.0)),
			"player_dmg": 0.0, "color": d.get("blast_color", WeaponDefs.COLLAPSE_COLOR), "element": d.get("blast_element", &"")})
	arms.after_blast(d, pos)                                # bomblets, a burning field, the overcharge stun
	grenade_collapsed.emit(pos)


## The node that takes damage for a physics collider: the collider itself or the nearest ancestor in group enemy / vehicle.
static func _damageable_of(collider: Node) -> Node:
	var n := collider
	while n != null:
		if (n.is_in_group(&"enemy") or n.is_in_group(&"vehicle")) and n.has_method(&"damage"):
			return n
		n = n.get_parent()
	return null


static func _radius_of(target: Object) -> float:
	var r: Variant = target.get(&"radius")
	if r is float or r is int:
		return float(r)
	return 0.0


static func _is_dead(target: Object) -> bool:
	if not is_instance_valid(target):
		return true
	var n := target as Node
	if n != null and n.is_queued_for_deletion():
		return true
	var d: Variant = target.get(&"dead")
	if d is bool and d:
		return true
	var h: Variant = target.get(&"hp")
	if (h is float or h is int) and float(h) <= 0.0:
		return true
	return false


## STUN GUN / STASIS RAY: the enemy is frozen (Drone.disable) for the weapon's `stun` seconds; big targets (bosses) only for a short while.
func _stun(target: Node) -> void:
	if not target.has_method(&"disable"):
		return
	var secs := float(def["stun"])
	var hpmax: Variant = target.get(&"max_hp")
	if hpmax != null and float(hpmax) > 400.0:
		secs *= 0.3
	target.call(&"disable", secs)
	stuns += 1
	if target is Node3D:
		FX.burst((target as Node3D).global_position + Vector3(0.0, 1.2, 0.0), def["tracer"], 4, 2.5, 0.35, 0.0, 0.9)


## FLAMETHROWER: the target burns for `burn_time` seconds, `burn` damage per second (a tick twice a second); a new hit renews the time.
func _ignite(target: Node) -> void:
	_ignite_ex(target, float(def["burn"]) * Upgrades.damage_mult(), float(def["burn_time"]))


## Burning with its own numbers (the fields of the NAPALM LAUNCHER call it); a new hit renews the time.
func _ignite_ex(target: Node, dps: float, secs: float) -> void:
	var key := target.get_instance_id()
	var e: Dictionary = _burning.get(key, {})
	e["node"] = target
	e["left"] = maxf(secs, float(e.get("left", 0.0)))
	e["acc"] = float(e.get("acc", 0.0))
	e["dps"] = dps
	_burning[key] = e


func _tick_burn(dt: float) -> void:
	if _burning.is_empty():
		return
	for key: int in _burning.keys():
		var e: Dictionary = _burning[key]
		var n: Node = e["node"] if is_instance_valid(e["node"]) else null
		if n == null or _is_dead(n) or float(e["left"]) <= 0.0:
			_burning.erase(key)
			continue
		e["left"] = float(e["left"]) - dt
		e["acc"] = float(e["acc"]) + dt
		if float(e["acc"]) >= 0.5:
			e["acc"] = float(e["acc"]) - 0.5
			n.call(&"damage", TestMode.damage(float(e["dps"]) * 0.5), false)
			burn_ticks += 1
			if n is Node3D:
				FX.burst((n as Node3D).global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.5, 0.12), 3, 1.5, 0.4, -2.0, 1.1)


## BLINK PISTOL alt-fire: teleport to the point the crosshair sees (at most `range` metres; a wall, a car or an enemy stops the jump short of it), a flash at both ends.
func _blink_to_aim(range_m: float) -> bool:
	var p := _player
	var ar := _aim_ray(0.0)
	var origin: Vector3 = ar[0]
	var dir: Vector3 = ar[1]
	var space := p.get_world_3d().direct_space_state
	_ray_b.from = origin
	_ray_b.to = origin + dir * range_m
	_ray_b.collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY
	_ray_b.exclude = _exclude_base
	var res := space.intersect_ray(_ray_b)
	var dest: Vector3
	if not res.is_empty():
		dest = (res["position"] as Vector3) - dir * 1.4                    # land in front of what stopped the jump
		var col := res["collider"] as Node
		if col != null and col.is_in_group(&"enemy"):
			dest = (res["position"] as Vector3) - dir * 2.4
	else:
		dest = origin + dir * range_m
	_ray_b.from = dest + Vector3(0.0, 2.0, 0.0)                              # then down to the ground below the landing point
	_ray_b.to = dest + Vector3(0.0, -40.0, 0.0)
	_ray_b.collision_mask = Game.L_WORLD
	var ground := space.intersect_ray(_ray_b)
	_ray_b.exclude = []
	_ray_b.collision_mask = 1
	if not ground.is_empty():
		dest = (ground["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	if dest.distance_to(p.global_position) < 2.0:
		return false
	var from := p.global_position + Vector3(0.0, 1.0, 0.0)
	FX.burst(from, def["tracer"], 10, 5.0, 0.45, 0.0, 1.2)
	FX.tracer(from, dest + Vector3(0.0, 1.0, 0.0), def["tracer"])
	p.teleport_to(dest)
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), def["tracer"], 10, 5.0, 0.45, 0.0, 1.2)
	Sfx.play(&"blink", -2.0, 1.2)
	blinks += 1
	return true


# --- Wave 61: minigun spin / heat, arc chain, melee ------------------------------------------------------------------

func _spin_mult() -> float:
	return lerpf(3.0, 1.0, spin) if def.has("spin_up") else 1.0


## Can the trigger fire a shot right now (minigun: spun up and not overheated; everything else always).
func _gun_ready() -> bool:
	if not def.has("spin_up"):
		return true
	return not overheated and spin >= float(def["spin_ready"])


func _tick_heat(dt: float, trigger: bool) -> void:
	var up := float(def["spin_up"])
	if trigger and not overheated:
		spin = minf(1.0, spin + dt / up)
	else:
		spin = maxf(0.0, spin - dt / (up * 0.8))
	if overheated:
		_lock_t -= dt
		heat = maxf(0.0, 1.0 - (1.0 - 0.3) * (1.0 - _lock_t / float(def["heat_lock"])))
		if _lock_t <= 0.0:
			overheated = false
			heat = 0.3
	elif _since_shot > 0.2 and def.has("heat_cool"):                       # a weapon that only spins up (the DRUMMER SMG) has no heat to shed
		heat = maxf(0.0, heat - float(def["heat_cool"]) * dt)


func _overheat() -> void:
	overheated = true
	overheats += 1
	heat = 1.0
	_lock_t = float(def["heat_lock"])
	_burst_left = 0
	Sfx.play(&"overheat", -2.0, 1.0)
	if _player != null and _player.body != null and _player.body.muzzle != null:
		FX.burst(_player.body.muzzle.global_position, Color(1.0, 0.5, 0.2), 6, 2.5, 0.5, 0.0, 1.0)


## 0..1 gauge for the HUD: the lance charge, or the minigun heat.
func gauge() -> float:
	return heat if def.has("heat_per") else charge


## The arc caster: the hit jumps to up to `chain` other enemies near the target, each for `chain_k` of the damage (a bolt between them).
func _chain(first: Node, at: Vector3, k: float) -> void:
	if _player == null or not (first is Node3D):
		return
	var prev := at
	var used: Array[Node] = [first]
	for _j in int(def["chain"]):
		var best: Node = null
		var best_d := float(def["chain_range"])
		for e: Node in get_tree().get_nodes_in_group(&"enemy"):
			if used.has(e) or not (e is Node3D) or not e.has_method(&"center") or _is_dead(e):
				continue
			var d: float = (e.call(&"center") as Vector3).distance_to(prev)
			if d < best_d:
				best_d = d
				best = e
		if best == null:
			return
		used.append(best)
		var c: Vector3 = best.call(&"center")
		FX.tracer(prev, c, def["tracer"])
		FX.qvfx.bolt(prev, c, def["tracer"])
		_hit_target(best, c, Vector3.UP, k * float(def["chain_k"]))
		chain_hits += 1
		prev = c


## One melee swing: the next step of the 3-hit combo (the third is the finisher, a bigger hit with more stagger). Hits every enemy in reach inside the cone in front of the camera.
func _melee_swing(aiming: bool, mult := 1.0, reach_add := 0.0) -> int:
	var p := _player
	mech.on_shoot()
	var steps: Array = def["combo"]
	var step := combo % steps.size()
	var finisher := step == steps.size() - 1
	combo = (step + 1) % steps.size()
	_combo_t = float(def["combo_window"])
	combo_hits += 1
	if finisher:
		finishers += 1
	fire_t = float(def["interval"]) * (1.7 if finisher else 1.0)
	_since_shot = 0.0
	_burst = step + 1
	Sfx.play(StringName(def.get("snd", &"shot")), float(def["vol"]), (0.85 if finisher else 1.0) + 0.06 * step)
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var origin := p.global_position
	var reach := float(def["reach"]) + reach_add
	var k: float = float(steps[step]) * mult
	var n := 0
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or not e.has_method(&"center") or _is_dead(e):
			continue
		var c: Vector3 = e.call(&"center")
		var off := Vector3(c.x - origin.x, 0.0, c.z - origin.z)
		var dist := off.length() - _radius_of(e)
		if dist > reach or (dist > 1.2 and off.normalized().dot(fwd) < float(def["cone"])):
			continue
		_melee_hit(e, c, k, finisher)
		n += 1
	var city := Game.world as City
	if city != null and city.ambient != null and Game.civilian_casualties:
		var spot := origin + fwd * minf(reach, 3.0) * 0.6
		if city.ambient.blast_civilians(spot, maxf(1.2, minf(reach, 3.0) * 0.6), true, float(def["damage"]) * k * 0.9, &"melee") > 0:
			n += 1
	if def.has("shock"):                                     # the TREMOR MAUL: every swing sends a shockwave (works on the ground, breaks cover)
		arms.melee_shock(origin, fwd, reach)
	var mz := p.body.muzzle.global_position
	var tip := origin + Vector3(0.0, 1.2, 0.0) + fwd * minf(reach, 3.0)
	var swing := p.camera_rig.camera.global_basis.x * (0.8 if step % 2 == 0 else -0.8)
	FX.tracer(mz, tip + swing, def["tracer"])
	FX.qvfx.weapon_id = current
	FX.qvfx.bolt(origin + Vector3(0.0, 1.5, 0.0) - swing, tip + swing, def["tracer"])
	_recoil(aiming)
	if finisher:
		FX.shake(0.12)
	p.fired.emit()
	return n


func _melee_hit(e: Node, c: Vector3, k: float, finisher: bool) -> void:
	var p := _player
	k *= float(ammo_info()["dmg"]) * mech.hit_mult(e)
	var amount := TestMode.damage(float(def["damage"]) * k * Upgrades.damage_mult() * HeroPower.f("dmg"))
	if e.has_method(&"shield_blocks") and bool(def["pierce_shield"]):
		e.call(&"break_shield")
	e.call(&"damage", amount, finisher)
	if e.has_method(&"stagger"):
		e.call(&"stagger", AimAssist.stagger_for(current) * (1.8 if finisher else 1.0))
	if def.has("burn") and not _is_dead(e):                  # the ION BLADE sears what it cuts
		_ignite(e)
	if def.has("stun") and not _is_dead(e):
		_stun(e)
	mech.on_hit(e, c, finisher)
	var kill := _is_dead(e)
	if kill:
		mech.on_kill(e)
	_hit_sound(kill, finisher)
	p.last_hit_time = PlayerUtil.now()
	p.last_hit_kill = kill
	p.last_hit_crit = finisher
	p.hit_confirmed.emit(kill, finisher)
	if kill:
		GameFeel.fire(&"heavy_kill" if finisher else &"kill")
	_damage_number(c, amount, finisher, kill)
	if _sparks != null:
		_sparks.impact_machine(c, Vector3.UP)


# --- alt-fire, ammo types, inspect, hit sounds --------------------------------------------------------------------------

func ammo_info() -> Dictionary:
	return WeaponDefs.AMMO_TYPES[ammo_type] if String(def["kind"]) == "hit" and mech.allows(ammo_type) else WeaponDefs.AMMO_TYPES[0]


## Next ammo type (hitscan weapons only). Returns false when the weapon in hand has only one.
func cycle_ammo_type() -> bool:
	if String(def["kind"]) != "hit" or swap_t > 0.0:
		return false
	ammo_type = mech.next_ammo(ammo_type)
	if Game.progress != null and Game.progress.has_method(&"set_ammo_type"):
		Game.progress.call(&"set_ammo_type", ammo_type)
	Sfx.play(&"ui_tap", -4.0, 1.3)
	Game.say("AMMO  %s" % String(ammo_info()["name"]), 1.4)                  # the phone has an AMMO button behind MORE (touch_controls.gd): the toast says what is loaded now
	return true


## HUD line: the alt-fire of the weapon in hand and (hitscan weapons) the ammo type, "ALT HEAVY SHOT   AMMO PIERCING".
func alt_text() -> String:
	var t := "ALT " + alt_name()
	if String(def["kind"]) == "hit":
		t += "   AMMO " + str(ammo_info()["name"])
	return t


func alt_name() -> String:
	return str(WeaponDefs.alt_of(current)["name"])


## The alternate fire of the weapon in hand. False (nothing happens) while reloading / switching / on cooldown or short of rounds.
func alt_fire(aiming := false) -> bool:
	if _player == null or reload_t > 0.0 or swap_t > 0.0 or fire_t > 0.0:
		return false
	var a := WeaponDefs.alt_of(current)
	var cost := int(a["cost"])
	if ammo < cost:
		Sfx.dry_fire()
		return false
	inspect_t = 0.0
	var kind := String(a["kind"])
	var start := ammo
	var before := shots_fired
	match kind:
		"heavy":
			_alt_k = float(a["mult"])
			_alt_spread = 0.25
			_alt_single = true
			_burst = 1
			_shoot(0.0, aiming)
			_alt_k = 1.0
			_alt_spread = 1.0
			_alt_single = false
			Sfx.play(&"boom", -10.0, 1.8)
			FX.burst(_player.body.muzzle.global_position, def["tracer"], 5, 3.0, 0.25, 0.0, 0.8)
			ammo = maxi(0, start - cost)
		"volley":                                              # the remaining rounds ride the burst machinery (one round each)
			_burst_left = mini(int(a["count"]), ammo) - 1
			_burst_t = 0.04
			_shoot(0.0, aiming)
		"quick":
			_fire_lance(1.0, aiming)
			ammo = maxi(0, start - cost)
		"cluster":
			_throw(-0.12)
			_throw(0.12)
			ammo = maxi(0, start - cost)
		"vent":                                                 # the minigun dumps its heat at once
			heat = 0.0
			overheated = false
			_lock_t = 0.0
			spin = 0.0
			Sfx.play(&"overheat", -8.0, 1.6)
			FX.burst(_player.body.muzzle.global_position, Color(0.7, 0.9, 1.0), 5, 2.0, 0.6, 0.0, 0.8)
		"pull":                                                 # the whip yanks the nearest enemy in front to arm's length and staggers it
			if not _whip_pull(float(a["range"])):
				return false
		"lunge":                                                # the blade dashes forward (the wall stops it) and strikes for a multiple
			_blade_lunge(float(a["dist"]), float(a["mult"]), aiming)
		"blink":                                                # the BLINK PISTOL: QUANTUM TELEPORT to the crosshair
			if not _blink_to_aim(float(a["range"])):
				return false
		"oc_bolt", "pop", "slam", "repulse", "fan", "airburst", "dive", "fire_line":      # the ENERGY and BLAST weapons (scripts/player/energy_arms.gd)
			if not arms.alt(kind, a, aiming):
				return false
			if kind in ["oc_bolt", "fan", "airburst", "dive"]:
				ammo = maxi(0, start - cost)
		_:
			if not mech.alt(kind, a, aiming, start):                           # underbarrel, scope switch, bipod, fire mode, overdrive, spin, shove, throw (WeaponMech)
				return false
	fire_t = maxf(fire_t, float(a["cd"]))
	alt_fired += 1
	Sfx.play(&"link", -8.0, 1.6)
	return shots_fired > before or kind in ["vent", "pull", "lunge", "blink", "pop", "zoom", "brace", "mode", "surge"]


func _whip_pull(range_m: float) -> bool:
	var p := _player
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var best: Node = null
	var best_d := range_m
	for e: Node in get_tree().get_nodes_in_group(&"enemy"):
		if not (e is Node3D) or _is_dead(e):
			continue
		var off := (e as Node3D).global_position - p.global_position
		off.y = 0.0
		if off.length() < best_d and off.normalized().dot(fwd) > 0.5:
			best_d = off.length()
			best = e
	if best == null:
		Sfx.dry_fire()
		return false
	var en := best as Node3D
	en.global_position = p.global_position + fwd * 2.4
	if best.has_method(&"stagger"):
		best.call(&"stagger", 1.6)
	best.call(&"damage", float(def["damage"]) * 0.5 * Upgrades.damage_mult() * HeroPower.f("dmg"), false)
	FX.tracer(p.body.muzzle.global_position, en.global_position + Vector3(0.0, 1.0, 0.0), def["tracer"])
	Sfx.play(&"melee_whip", -2.0, 0.7)
	shots_fired += 1
	return true


func _blade_lunge(dist: float, mult: float, aiming: bool) -> void:
	var p := _player
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var from := p.global_position + Vector3(0.0, 1.0, 0.0)
	_ray_b.from = from
	_ray_b.to = from + fwd * dist
	var res := p.get_world_3d().direct_space_state.intersect_ray(_ray_b)
	var d := dist if res.is_empty() else maxf(0.0, from.distance_to(res["position"]) - 0.7)
	p.global_position += fwd * d
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), def["tracer"], 6, 3.0, 0.3, 0.0, 0.9)
	combo = 2                                               # the lunge always lands as a finisher
	_melee_swing(aiming, mult / 1.9)
	shots_fired += 1


func start_inspect() -> bool:
	if inspect_t > 0.0 or reload_t > 0.0 or swap_t > 0.0 or _player == null:
		return false
	inspect_t = INSPECT_TIME
	_idle_t = 0.0
	Sfx.play(&"ui_tap", -8.0, 0.7)
	return true


func _tick_inspect(dt: float, busy: bool) -> void:
	if busy:
		_idle_t = 0.0
		inspect_t = 0.0
		return
	if inspect_t > 0.0:
		inspect_t = maxf(0.0, inspect_t - dt)
		return
	_idle_t += dt
	if _idle_t >= INSPECT_IDLE:
		start_inspect()


## Weapon-specific hit confirm: pitch / volume per class, a heavier layer on the slow weapons, a brighter tick on a kill.
func _hit_sound(kill: bool, crit: bool) -> void:
	var h := WeaponDefs.hit_snd(current)
	Sfx.play(&"hit", float(h[1]) - 6.0, float(h[0]) * (1.25 if kill else (1.1 if crit else 1.0)))
	if kill:
		Sfx.play(&"hit_kill", -4.0, float(h[0]) * 0.9 + 0.15)                     # a kill has its own dull thock and glassy tick on top of the hit
	if StringName(h[2]) != &"":
		Sfx.play(StringName(h[2]), -9.0, float(h[0]) + 0.3)
