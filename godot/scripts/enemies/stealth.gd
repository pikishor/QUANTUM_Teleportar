class_name Stealth
extends RefCounted
## Stealth and alert states (A6). Every enemy has an alert level: UNAWARE, SUSPICIOUS (suspicion building, a '?' tell), SEARCHING (walks to the last known position,
## then looks around), ALERTED (the existing `aware` combat state). All tuning lives in TUNING. Noise (gunfire, sprint, vehicles, the SUPERPOSITION decoy) raises
## suspicion of unaware enemies in range; a silent takedown (killing an unaware enemy) pays a bonus; a contract finished with nobody alerted pays a stealth bonus.
## The per-enemy state lives on Drone (suspicion, search_t, last_known); this class holds the table, the pure rules and the run counters.

enum Level { UNAWARE, SUSPICIOUS, SEARCHING, ALERTED }

const TUNING := {
	"sight_fill": 0.6,        ## seconds of seeing the player at the edge of sight range to become alerted (shorter when closer)
	"close_dist": 8.0,        ## within this many metres sight alerts at once
	"susp_decay": 0.35,       ## suspicion lost per second without noise or sight
	"search_sec": 9.0,        ## seconds an enemy searches the last known position before giving up
	"lose_sec": 8.0,          ## an alerted enemy without line of sight for this long (and no heat) starts searching
	"search_arrive": 2.5,     ## metres from the last known position that count as arrived
	"gun_range": 48.0,        ## gunfire hearing range; within gun_alert it alerts at once
	"gun_alert": 12.0,
	"sprint_range": 9.0,      ## footsteps while sprinting
	"sprint_every": 0.5,
	"vehicle_range": 34.0,    ## engine noise at full speed (scaled by speed / vehicle_ref)
	"vehicle_ref": 20.0,
	"vehicle_min": 6.0,       ## m/s below which a vehicle is quiet
	"decoy_range": 28.0,      ## the SUPERPOSITION clone draws unaware enemies this close
	"noise_susp": 0.55,       ## suspicion added by a noise at point blank (scaled down with distance)
	"takedown_bonus": 150,    ## score for killing an unaware enemy
	"contract_bonus": 250,    ## score for finishing a contract with nobody alerted
}

static var alerts := 0              ## enemies that went from unaware to alerted since reset_run()
static var takedowns := 0           ## silent takedowns since reset_run()


static func reset_run() -> void:
	alerts = 0
	takedowns = 0


static func t(key: String) -> float:
	return float(TUNING[key])


## The alert level from the raw state.
static func level_of(aware: bool, search_t: float, suspicion: float) -> int:
	if aware:
		return Level.ALERTED
	if search_t > 0.0:
		return Level.SEARCHING
	if suspicion > 0.05:
		return Level.SUSPICIOUS
	return Level.UNAWARE


## Seconds-rate at which seeing the player at distance d (inside sight range r) fills suspicion; >= 1/dt means instant.
static func sight_rate(d: float, r: float) -> float:
	if d <= t("close_dist"):
		return 1000.0
	return 1.0 / maxf(t("sight_fill") * clampf(d / maxf(r, 1.0), 0.15, 1.0), 0.05)


## Loudness range of a noise kind (metres).
static func noise_range(kind: StringName, speed := 0.0) -> float:
	match kind:
		&"gun":
			return t("gun_range")
		&"sprint":
			return t("sprint_range")
		&"vehicle":
			return t("vehicle_range") * clampf(speed / t("vehicle_ref"), 0.0, 1.0) if speed >= t("vehicle_min") else 0.0
		&"decoy":
			return t("decoy_range")
	return 0.0


## Suspicion added to an enemy `d` metres from a noise of range r (0 when out of range).
static func noise_amount(d: float, r: float) -> float:
	if r <= 0.0 or d >= r:
		return 0.0
	return t("noise_susp") * (1.0 - d / r) + 0.15


## Make noise at `pos`. Unaware enemies in range gain suspicion; at 1.0 they search `pos`; loud gunfire nearby alerts them.
static func noise(list: Array, pos: Vector3, kind: StringName, speed := 0.0) -> void:
	if kind == &"gun" and is_instance_valid(Game.vehicles):
		(Game.vehicles as VehicleManager).hear(pos, &"gun")          # traffic flees from gunfire
	var r := noise_range(kind, speed)
	if r <= 0.0:
		return
	for e in list:
		var d := e as Drone
		if d == null or d.dead or not d.active or d.aware:
			continue
		var dist := Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length()
		if dist >= r:
			continue
		if kind == &"gun" and dist < t("gun_alert"):
			d.alert()
			continue
		d.hear(pos, noise_amount(dist, r))


static func takedown_bonus() -> int:
	return int(TUNING["takedown_bonus"])


static func contract_bonus_due() -> bool:
	return alerts == 0
