class_name TacticsTable
extends RefCounted
## Cover AI v2 and squad tactics v2: EVERY tuning number lives here. Three factions behave differently (a Operative picks one when it activates):
##   observer  disciplined corps: scores cover by height and arc, leapfrogs (one team moves while the other covers), suppresses while flankers arc round,
##             flushes a hero who holds cover with a grenade, retreats at 25 % and regroups on a mender or two allies.
##   vael      the hive: rushes, barely hides, pushes in pairs, never retreats, no grenades.
##   raider    hit-and-run (flankers): short hides, quick flank orders, retreats early (40 %), regroups fast, no leapfrog.
## Per-tier caps (thinkers per frame, leapers, flush grenades in flight) keep the budgets; nothing here adds nodes or draws.

const OBSERVER := &"observer"
const VAEL := &"vael"
const RAIDER := &"raider"

## Faction numbers. Keys: cover_use (chance a search is made), w_dist / w_height / w_arc / w_adv (cover score weights), hide (s hidden), peek (s), leapfrog, leap_min (m to the target before a
## leap), leap_step (m closer per leap), flush, flush_hold (s the hero holds cover), suppress (s between blind bursts), suppress_flank_mult (x faster while a flanker arcs), flank_cd (s),
## camp_s (s before a camping hero is flanked), push_every (every Nth neighbour pushes), retreat_hp, regroup_s, regroup_hp (health share to return), regroup_allies, regroup_radius.
const FACTIONS := {
	&"observer": {
		"cover_use": 1.0, "w_dist": 1.0, "w_height": 6.0, "w_arc": 8.0, "w_adv": 0.6, "hide": Vector2(0.9, 1.8), "peek": 3.0,
		"leapfrog": true, "leap_min": 12.0, "leap_step": 4.0, "flush": true, "flush_hold": 3.0,
		"suppress": Vector2(2.2, 3.4), "suppress_flank_mult": 0.55, "flank_cd": 12.0, "camp_s": 3.5, "push_every": 3,
		"retreat_hp": 0.25, "regroup_s": 4.0, "regroup_hp": 0.5, "regroup_allies": 2, "regroup_radius": 22.0,
	},
	&"vael": {
		"cover_use": 0.35, "w_dist": 1.5, "w_height": 2.0, "w_arc": 2.0, "w_adv": 1.4, "hide": Vector2(0.4, 0.9), "peek": 2.0,
		"leapfrog": false, "leap_min": 99.0, "leap_step": 0.0, "flush": false, "flush_hold": 99.0,
		"suppress": Vector2(4.5, 6.0), "suppress_flank_mult": 1.0, "flank_cd": 7.0, "camp_s": 2.0, "push_every": 2,
		"retreat_hp": 0.0, "regroup_s": 0.0, "regroup_hp": 0.0, "regroup_allies": 99, "regroup_radius": 0.0,
	},
	&"raider": {
		"cover_use": 0.5, "w_dist": 2.0, "w_height": 3.0, "w_arc": 4.0, "w_adv": 1.0, "hide": Vector2(0.5, 1.1), "peek": 2.2,
		"leapfrog": false, "leap_min": 99.0, "leap_step": 0.0, "flush": false, "flush_hold": 99.0,
		"suppress": Vector2(3.0, 4.2), "suppress_flank_mult": 0.8, "flank_cd": 6.0, "camp_s": 2.5, "push_every": 4,
		"retreat_hp": 0.4, "regroup_s": 2.0, "regroup_hp": 0.4, "regroup_allies": 1, "regroup_radius": 30.0,
	},
}

## Cover geometry: a body at least FULL_H tall hides a standing trooper (quality 1.0), a waist-high one (EnemyCover.MIN_HEIGHT) only 0.45.
const FULL_H := 1.5
const LOW_QUALITY := 0.45
## A body is also an unsafe hide when the threat looks down on it: elevation of the line threat -> body top above this tan hides less (the hero standing on a roof).
const ARC_BEST := 0.5                       ## sine of the half angle the body covers from the threat at which the arc score saturates

## Caps by graphics tier (LOW, MED, HIGH). THINKERS stay in EnemyManager.THINKERS.
const LEAPERS: Array[int] = [1, 1, 2]                      ## troopers advancing between covers at once, per squad radius
const LEAP_SQUAD_RADIUS := 35.0
const FLUSH_ACTIVE: Array[int] = [1, 1, 2]                 ## flush grenades in flight at once
const FLUSH_COOLDOWN := 9.0                                ## seconds between flush throws of the whole squad
const FLUSH_FUSE := 1.3
const FLUSH_RADIUS := 3.6
const FLUSH_DAMAGE := 22.0
const FLUSH_RANGE := Vector2(7.0, 26.0)

## Medics (mender): the most wounded ally within PATIENT_RADIUS gets MEDIC_FULL x the heal rate, the rest MEDIC_REST. A retreating trooper heads for a mender within MEDIC_CALL.
const PATIENT_RADIUS := 26.0
const PATIENT_BELOW := 0.85
const MEDIC_FULL := 1.0
const MEDIC_REST := 0.4
const MEDIC_CALL := 32.0

## Commanders (cfg "commander"): allies within BUFF_RADIUS fire harder and move faster; the manager refreshes it every BUFF_EVERY seconds.
const BUFF_RADIUS := 14.0
const BUFF_DMG := 1.25
const BUFF_SPEED := 1.15
const BUFF_EVERY := 0.4

## Squad kits of the encounter director's troopers (real-fight wave): the roster LOOK says what the trooper does, so a player reads the role at a glance (shape and colour).
## speed / hp / range are multipliers of the operative's cfg; `throws` = lobs grenades (EnemyGrenades), `cover` = how readily it takes low cover (x the faction's cover_use), `aim` = aim time
## multiplier (a marksman takes his time and the aim line shows it). Looks: HumanoidVariants.VAEL_CLASSES.
const KITS := {
	&"rifleman": {"speed": 1.0, "hp": 1.0, "range": 1.0, "throws": false, "cover": 1.0, "aim": 1.0, "what": "RIFLEMAN"},
	&"gunner": {"speed": 0.8, "hp": 1.7, "range": 1.0, "throws": false, "cover": 0.3, "aim": 1.0, "what": "HEAVY"},
	&"scout": {"speed": 1.32, "hp": 0.7, "range": 0.8, "throws": false, "cover": 0.2, "aim": 0.8, "what": "RUSHER"},
	&"grenadier": {"speed": 0.95, "hp": 1.0, "range": 1.0, "throws": true, "cover": 0.8, "aim": 1.0, "what": "GRENADIER"},
	&"marksman": {"speed": 0.85, "hp": 0.85, "range": 1.35, "throws": false, "cover": 1.2, "aim": 1.5, "what": "MARKSMAN"},
	&"commander": {"speed": 1.0, "hp": 1.4, "range": 1.0, "throws": true, "cover": 0.5, "aim": 1.0, "what": "COMMANDER"},
}
const SQUAD_RANGE := 0.7                            ## the director's troopers fight at 70 % of the cfg range (24 m -> 17 m): they close to 7-17 m, so the figures are big enough to read on a phone
const SQUAD_HP := 1.5                               ## ... and take 50 % more rounds: a wave lasts 10-15 s instead of 5 (the hero is strong, the fight must still be seen)
const GRENADE_RANGE := Vector2(9.0, 26.0)           ## a grenadier lobs only from this far
const GRENADE_FIRST := Vector2(1.0, 2.2)            ## seconds after he engages before the first throw
const GRENADE_EVERY := Vector2(6.0, 9.0)            ## seconds between his throws
const GRENADE_WIND := 0.55                          ## seconds he stands (arm back) before the ball leaves


static func kit(look_name: StringName) -> Dictionary:
	return KITS[look_name] if KITS.has(look_name) else KITS[&"rifleman"]


## Operatives of later chapters join the hive: share by chapter index (the last row covers every later sector).
const VAEL_SHARE: Array[float] = [0.0, 0.0, 0.2, 0.3, 0.35, 0.4, 0.45]
## Types that take the raider faction (flankers).
const RAIDER_TYPES: Array[StringName] = [&"flanker"]


static func faction_for(type: StringName, chapter: int, roll: float) -> StringName:
	if RAIDER_TYPES.has(type):
		return RAIDER
	if roll < VAEL_SHARE[clampi(chapter, 0, VAEL_SHARE.size() - 1)]:
		return VAEL
	return OBSERVER


static func row(faction: StringName) -> Dictionary:
	return FACTIONS[faction] if FACTIONS.has(faction) else FACTIONS[OBSERVER]


static func val(faction: StringName, key: String) -> Variant:
	return row(faction)[key]


static func tier_cap(arr: Array[int], tier: int) -> int:
	return arr[clampi(tier, 0, 2)]


## Cover quality 0..1 of a body of `height` and `radius` seen from `dist` metres: height (waist-high 0.45 .. full 1.0) times how much of the view the body fills (arc).
static func cover_quality(height: float, radius: float, dist: float) -> float:
	var h := clampf(inverse_lerp(EnemyCover.MIN_HEIGHT, FULL_H, height), 0.0, 1.0)
	var hq := lerpf(LOW_QUALITY, 1.0, h)
	var arc := clampf(radius / maxf(dist, 1.0) / ARC_BEST, 0.0, 1.0)
	return hq * (0.4 + 0.6 * arc)


## Score of a candidate hide (lower is better): walking distance, minus the quality of the cover, minus how far it moves the trooper closer when advancing.
static func score(faction: StringName, walk: float, quality: float, closer_by: float, advancing: bool) -> float:
	var r := row(faction)
	var s := walk * float(r["w_dist"]) - quality * (float(r["w_height"]) + float(r["w_arc"])) * 2.0
	if advancing:
		s -= closer_by * float(r["w_adv"])
	return s
