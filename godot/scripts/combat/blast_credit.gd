class_name BlastCredit
extends RefCounted
## HIT FEEDBACK AND KILL CREDIT FOR EXPLOSIVES, FIRE AND CHAINS (wave 113, play critic). A bullet that hurts an enemy tells the HUD (the crosshair X, the red ring of a kill, the camera tick), pops a damage
## number, plays the hit tick, and a kill reaches everything that counts kills (the side jobs "TAKE DOWN n", the kill stats of the achievements) through Player.hit_confirmed. A grenade, a rocket, a strike,
## a fire field, a shock chain or a burning enemy did none of it: three enemies killed with a frag grenade left the BOSS-LITE HUNT job at 0 of 8, gave no hit marker and no kill stat, while the same
## three bullets counted 3 (measured in the real scene, tests/dev_w113_behaviour.gd). Every place that hurts an enemy for the hero calls `dealt` right after the damage.
##
##   BlastCredit.dealt(enemy, amount, at, marker)  `amount` was just applied to `enemy` by something the hero (or the world he set off) did. A kill sends one hit_confirmed(true, false) per enemy; a
##                                                 hurt that does not kill sends one hit_confirmed(false, false) per physics frame (the marker), a number (at most 3 a frame) and the hit tick.
##                                                 `marker = false` (a burn or a fire field ticking) only credits the kill: the crosshair does not flash every half second.
##   BlastCredit.credited(source, by_hero)         true for the hero's blasts and for the world's (a barrel, a wreck, a strike); false for a blast an enemy fired.
## Counters `marks`, `kills`, `numbers` (tests wait on them). Nothing is allocated per call; blasts farther than NEAR from the hero are not his to feel.

const NEAR := 170.0
const MAX_SIGNALS := 12
const MAX_NUMBERS := 3                       ## damage numbers a physics frame on HIGH (each is a Label3D and a draw call for 0.7 s: MED 2, LOW 1)

static var enabled := OS.get_environment("QT_CREDIT") != "0"      ## QT_CREDIT=0 switches the credit off (the "before" frames of the look-dev bots)
static var marks := 0
static var kills := 0
static var numbers := 0
static var _frame := -1
static var _marked := false
static var _kill_frame := false
static var _sig := 0
static var _nums := 0
static var _snd_hit := false
static var _snd_kill := false


## Is this blast / fire / chain the hero's to be credited with? Everything but a blast that an enemy fired (the world's barrels and wrecks go off because of him in nearly every case).
static func credited(source: Variant, by_hero := false) -> bool:
	if by_hero:
		return true
	if is_instance_valid(source) and source is Node and (source as Node).is_in_group(&"enemy"):
		return false
	return true


## Damage numbers per physics frame by graphics tier: a blast pops one number on LOW, two on MED, three on HIGH.
static func max_numbers() -> int:
	return clampi(Game.quality + 1, 1, MAX_NUMBERS)


## Zero the counters (tests).
static func reset_stats() -> void:
	marks = 0
	kills = 0
	numbers = 0
	_frame = -1


## `amount` of damage was just applied to `en` for the hero: the marker, the number, the tick and, when it died, the kill.
static func dealt(en: Variant, amount: float, at := Vector3.INF, marker := true) -> void:
	if not enabled or amount <= 0.0 or not is_instance_valid(en) or not (en is Node3D) or not Game.is_playing():
		return
	var p := Game.player as Player
	if p == null or not is_instance_valid(p):
		return
	var foe := en as Node3D
	if foe.global_position.distance_to(p.global_position) > NEAR:
		return
	var kill := PlayerWeapon._is_dead(foe)
	if not kill and not marker:
		return
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_marked = false
		_kill_frame = false
		_sig = 0
		_nums = 0
		_snd_hit = false
		_snd_kill = false
	var w := p.weapon
	if w != null:
		w.last_shot = {}                                  # the last bullet is old news: DamageWorld reads last_shot when a hit is confirmed
	p.last_hit_time = PlayerUtil.now()
	if kill:
		_kill_frame = true
	p.last_hit_kill = _kill_frame
	p.last_hit_crit = false
	if kill:
		kills += 1
		if _sig < MAX_SIGNALS:
			_sig += 1
			p.hit_confirmed.emit(true, false)
	elif not _marked:
		_marked = true
		marks += 1
		p.hit_confirmed.emit(false, false)
	if w == null:
		return
	if marker and _nums < max_numbers():
		_nums += 1
		numbers += 1
		var pos := at
		if not pos.is_finite():
			pos = foe.call(&"center") if foe.has_method(&"center") else foe.global_position + Vector3(0.0, 1.0, 0.0)
		w.call(&"_damage_number", pos, amount, false, kill)
	if kill and not _snd_kill:
		_snd_kill = true
		w.call(&"_hit_sound", true, false)
	elif not kill and not _snd_hit and marker:
		_snd_hit = true
		w.call(&"_hit_sound", false, false)
