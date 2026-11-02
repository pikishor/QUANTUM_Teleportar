class_name VehicleSpecs
extends RefCounted
## Numbers of the vehicles module: car specs (src/vehicles.js SPECS plus an SUV), the per-tier caps, colours, streaming distances and the traffic rules.
## Keep every tuning number here so the manager, the vehicle and the tests agree.

## max = top speed m/s, acc = acceleration m/s2, brake = braking m/s2, grip = lateral grip (1/s), hp, model = Game.load_model name,
## len / wid / hgt = the model's size in metres (assets contract), wheel = wheel radius, axle_z = axle offset from the centre (wheels sit at +-axle_z).
const SPECS := {
	&"sedan": {"max": 34.0, "acc": 18.0, "brake": 40.0, "grip": 6.5, "hp": 120.0, "model": "car_sedan", "len": 4.75, "wid": 1.86, "hgt": 1.48, "wheel": 0.335},
	&"sport": {"max": 50.0, "acc": 28.0, "brake": 48.0, "grip": 5.2, "hp": 100.0, "model": "car_sport", "len": 4.45, "wid": 1.92, "hgt": 1.20, "wheel": 0.335},
	&"suv": {"max": 30.0, "acc": 15.0, "brake": 36.0, "grip": 6.8, "hp": 150.0, "model": "car_suv", "len": 4.85, "wid": 1.98, "hgt": 1.83, "wheel": 0.385},
	# --- handling classes (optional keys, a spec without them is a plain car) ---
	# cls = "car" | "bike" | "hover"; alt = further Game.load_model names tried when `model` does not exist (the primitive fallback is used when none does);
	# bike: lean_max = body roll in rad at full lean, steer = steering rate factor; hover: hover_h = ride height of the model, bob = bob amplitude in m,
	# drift = extra sideways slide (grip stays low), coast = coast drag; far = look of the kind in the far traffic (tint, speed factor, see ambient_traffic.gd).
	&"bike": {"cls": "bike", "max": 58.0, "acc": 30.0, "brake": 38.0, "grip": 7.8, "hp": 55.0, "model": "bike_street", "alt": ["bike", "bike_sport"], "len": 2.1, "wid": 0.8, "hgt": 1.3,
		"wheel": 0.34, "lean_max": 0.62, "steer": 1.3, "far": {"tint": Color(1.0, 0.95, 0.82), "speed": 1.25}},
	&"hover": {"cls": "hover", "max": 46.0, "acc": 22.0, "brake": 30.0, "grip": 2.2, "hp": 90.0, "model": "car_hover", "alt": ["hover_car", "hovercar"], "len": 4.6, "wid": 2.0, "hgt": 1.15,
		"wheel": 0.3, "hover_h": 0.55, "bob": 0.07, "drift": 1.0, "coast": 0.28, "steer": 1.15, "far": {"tint": Color(0.45, 0.95, 1.0), "speed": 1.1}},
	# Vael patrol vehicle: a hover chassis in the hive colours, chases the player from heat 3 (VehicleManager patrols), hp 160.
	&"vael_patrol": {"cls": "hover", "patrol": true, "max": 44.0, "acc": 24.0, "brake": 34.0, "grip": 3.0, "hp": 160.0, "model": "car_vael_patrol", "alt": ["vael_patrol", "hover_vael"],
		"len": 4.9, "wid": 2.1, "hgt": 1.3, "wheel": 0.3, "hover_h": 0.5, "bob": 0.05, "drift": 0.7, "coast": 0.3, "steer": 1.2, "far": {"tint": Color(0.75, 1.0, 0.45), "speed": 0.6}},
	# --- the Wave 14 art set (tools/blender/model_car_taxi.py ... ): sedan platform variants, a van and a truck. mass = kg, seats = driver included,
	# The paints of a kind are in PALETTES (taxis yellow, vans white and grey, the Vael patrol in hive tones).
	&"taxi": {"max": 32.0, "acc": 17.0, "brake": 38.0, "grip": 6.4, "hp": 130.0, "mass": 1500.0, "seats": 5, "model": "car_taxi", "len": 4.75, "wid": 1.86, "hgt": 1.66, "wheel": 0.335},
	&"wagon": {"max": 33.0, "acc": 16.5, "brake": 38.0, "grip": 6.4, "hp": 135.0, "mass": 1600.0, "seats": 5, "model": "car_wagon", "len": 4.92, "wid": 1.86, "hgt": 1.55, "wheel": 0.35},
	&"van": {"max": 28.0, "acc": 12.0, "brake": 32.0, "grip": 6.0, "hp": 175.0, "mass": 2300.0, "seats": 3, "model": "car_van", "len": 5.2, "wid": 2.0, "hgt": 2.25, "wheel": 0.37},
	&"truck": {"max": 24.0, "acc": 9.0, "brake": 28.0, "grip": 5.4, "hp": 260.0, "mass": 7500.0, "seats": 3, "model": "car_truck", "len": 6.4, "wid": 2.1, "hgt": 3.0, "wheel": 0.42},
	# --- creature kit (tools/creature_kit.py, Quaternius space kit, CC0): a moon rover on four wheels and a hover skiff, both rare in the traffic mix.
	&"rover": {"max": 26.0, "acc": 14.0, "brake": 34.0, "grip": 6.2, "hp": 170.0, "mass": 1900.0, "seats": 2, "model": "car_rover", "len": 2.3, "wid": 1.9, "hgt": 2.03, "wheel": 0.3},
	&"skiff": {"cls": "hover", "max": 54.0, "acc": 26.0, "brake": 32.0, "grip": 2.0, "hp": 80.0, "mass": 900.0, "seats": 2, "model": "car_skiff", "len": 5.2, "wid": 1.85, "hgt": 1.4, "wheel": 0.3,
		"hover_h": 0.6, "bob": 0.09, "drift": 1.1, "coast": 0.25, "steer": 1.2, "far": {"tint": Color(0.7, 0.85, 1.0), "speed": 1.2}},
}
## Paints of the kinds that do not wear the random street palette (VehicleVisual.set_paint maps the random COLORS pick to an entry; a husk keeps WRECK_COLOR).
const PALETTES := {
	&"taxi": [Color(0.86, 0.66, 0.16), Color(0.92, 0.74, 0.2), Color(0.8, 0.58, 0.12), Color(0.88, 0.7, 0.18)],
	&"van": [Color(0.84, 0.86, 0.88), Color(0.62, 0.66, 0.7), Color(0.3, 0.42, 0.56), Color(0.86, 0.87, 0.9), Color(0.4, 0.44, 0.48)],
	&"truck": [Color(0.56, 0.62, 0.66), Color(0.3, 0.42, 0.56), Color(0.68, 0.4, 0.26), Color(0.8, 0.82, 0.84)],
	&"vael_patrol": [Color(0.3, 0.36, 0.26), Color(0.26, 0.2, 0.36), Color(0.2, 0.3, 0.32), Color(0.34, 0.26, 0.3)],
}
## mass (kg) and seats of the kinds that carry no inline "mass" / "seats" key (read them through mass_of() / seats_of()).
const BASE_STATS := {
	&"sedan": {"mass": 1450.0, "seats": 5}, &"sport": {"mass": 1250.0, "seats": 2}, &"suv": {"mass": 2100.0, "seats": 5},
	&"bike": {"mass": 220.0, "seats": 2}, &"hover": {"mass": 1100.0, "seats": 3}, &"vael_patrol": {"mass": 1900.0, "seats": 2},
}
## Cars of the original set (shader warm-up and legacy tests); streaming uses STREAM_KINDS.
const KINDS: Array[StringName] = [&"sedan", &"sport", &"suv"]
const KIND_WEIGHTS: Array[float] = [0.5, 0.25, 0.25]
## Spawn weights of a streamed vehicle (sedan, sport, suv, bike, hover, taxi, wagon, van, truck, rover, skiff). Patrols (vael_patrol) are never streamed, the manager adds them from heat 3.
const STREAM_KINDS: Array[StringName] = [&"sedan", &"sport", &"suv", &"bike", &"hover", &"taxi", &"wagon", &"van", &"truck", &"rover", &"skiff"]
const STREAM_WEIGHTS: Array[float] = [0.18, 0.14, 0.12, 0.1, 0.1, 0.1, 0.06, 0.08, 0.06, 0.03, 0.03]

## Live cars at once (starter car and a driven car included): LOW 3 / MED 5 / HIGH 8. Each legacy car costs about 10 draw calls.
const CAPS: Array[int] = [3, 5, 8]
const STREAM_RADIUS := 110.0           ## only cars within about this distance of the player exist as nodes (the starter car excepted)
const DESPAWN_RADIUS := 124.0          ## hysteresis: a car is released beyond this
const SPAWN_MIN := 40.0                ## streamed cars appear between SPAWN_MIN and SPAWN_MAX from the player
const SPAWN_MAX := 105.0
const STREAM_EVERY := 0.4              ## seconds between streaming passes
const MIRROR_NEAR := 25.0              ## MirrorProxy only for cars this close (released beyond MIRROR_NEAR + 8)
const WHEELS_NEAR := 50.0              ## wheels are hidden beyond this
const PARKED_SHARE := 0.55             ## fraction of streamed cars that are parked
const WRECK_COLOR := Color(0.045, 0.04, 0.04)   ## the charred paint of a husk
const MAX_WRECKS := 3                  ## husks standing at once (the oldest goes first)
const RESPAWN_TIME := 25.0             ## a destroyed car comes back as a parked car after this many seconds

const BAY := 8.3                       ## parking bay centre offset from the road centre line (bays are 7.0-9.4 m)
const STARTER_DX := 9.0                ## the starter sport car stands at SPAWN.x + this, on the parking bay (z = BAY) of the main avenue, facing +X
const STARTER_COLOR := 2               ## index into COLORS: brass, so the starter car is easy to find
const STARTER_HEADING := -PI * 0.5

const COLORS: Array[Color] = [
	# desaturated lacquer palette (clear coat + flakes, see VehicleVisual.set_paint): oxblood, steel blue, brass (the starter), sage teal,
	# dusk violet, pearl, burnt copper, midnight. Nothing is a flat saturated primary any more.
	Color(0.56, 0.20, 0.24), Color(0.30, 0.42, 0.56), Color(0.78, 0.66, 0.44), Color(0.30, 0.52, 0.48),
	Color(0.42, 0.38, 0.60), Color(0.86, 0.87, 0.90), Color(0.68, 0.40, 0.26), Color(0.15, 0.18, 0.30),
]
const PAINT_GAIN := 1.0
const GLOWS: Array[Color] = [Color(0.22, 0.96, 1.0), Color(1.0, 0.24, 0.94), Color(0.22, 1.0, 0.69), Color(0.61, 0.42, 1.0)]

# --- driving (arcade, src/vehicles.js drive()) ---
const REVERSE_FRACTION := 0.35         ## top reverse speed as a fraction of max
const COAST_DRAG := 0.5                ## 1/s, no throttle
const HANDBRAKE_DRAG := 1.2            ## 1/s longitudinal
const HANDBRAKE_GRIP := 1.4            ## lateral grip with the handbrake (slides)
const STEER_RATE := 2.3                ## rad/s at full authority
const UNPOWERED_DRAG := 3.0            ## a car nobody drives slows down with this rate

# --- drift (E1) ---
const DRIFT_RECOVER := 0.45            ## s: traction returns this slowly after the handbrake is released
const DRIFT_ASSIST := 1.1              ## rad/s of extra yaw when steering against a slide
const SMOKE_SLIP := 4.5                ## lateral speed (m/s) above which the tyres smoke
const TYRE_SMOKE_EVERY := 0.09

# --- collisions and damage ---
const HIT_SPEED := 5.0                 ## wall impact (normal speed) above this hurts
const HIT_DAMAGE := 2.2                ## hp per m/s of impact
const BOUNCE := 1.4                    ## vn restitution factor (vel -= BOUNCE * vn * n)
const CAR_SEPARATION := 3.6            ## circle distance of the car-to-car bump
const CAR_HIT_SPEED := 6.0
const RAM_SPEED := 8.0                 ## running over enemies needs this speed
const RAM_RADIUS := 2.4
const RAM_FACTOR := 3.5
const RAM_COOLDOWN := 0.6
const CARJACK_HEAT := 0.2

# --- damage states, enter / exit ---
const SMOKE_BELOW := 0.4               ## hp fraction: smoke
const FIRE_BELOW := 0.15               ## hp fraction: fire, the car burns down (BURN_DPS hp per second) and blows up
const BURN_DPS := 2.2
const FX_RANGE := 70.0                 ## smoke and fire are only spawned this close to the player
const SMOKE_EVERY := 0.34
const FIRE_EVERY := 0.2
const EXIT_SAFE_SPEED := 9.0           ## leaving a car faster than this hurts (EXIT_HURT hp per m/s over it)
const EXIT_HURT := 2.0
const EXIT_BRAKE := 0.6                ## a car the player leaves keeps this share of its speed (it rolls to a stop)

# --- Vael patrols (chase from heat PATROL_HEAT) ---
const PATROL_HEAT := 3.0
const PATROL_CAPS: Array[int] = [1, 1, 2]       ## patrol vehicles at once per tier (they use the car cap)
const PATROL_EVERY := 6.0              ## seconds between spawn attempts
const PATROL_MIN := 55.0
const PATROL_MAX := 100.0
const PATROL_STAND_DOWN := 2.0         ## heat below this: patrols stop chasing and are released once 45 m away
const PATROL_RAM_DAMAGE := 9.0         ## hp of the player (or the driven car x 0.6) per ram, PATROL_RAM_COOLDOWN apart
const PATROL_RAM_COOLDOWN := 1.1
const PATROL_SIREN := [Color(1.0, 0.1, 0.1), Color(0.2, 0.4, 1.0)]

# --- traffic (right-hand lanes on Game.LANE, junction turns, stops for obstacles) ---
const AI_LOOK := 11.0                  ## obstacle check distance ahead
const AI_SIDE := 2.6                   ## obstacle check half width
const AI_CRUISE_MIN := 9.0
const AI_CRUISE_MAX := 14.0
const AI_TURN_COOLDOWN := 14.0         ## metres before the next junction may turn again
const AI_STRAIGHT_CHANCE := 0.55


static func starter_pos() -> Vector3:
	return Vector3(Game.SPAWN.x + STARTER_DX, 0.0, BAY)


static func pick_kind(r: float) -> StringName:
	var acc := 0.0
	for i in STREAM_KINDS.size():
		acc += STREAM_WEIGHTS[i]
		if r < acc:
			return STREAM_KINDS[i]
	return STREAM_KINDS[STREAM_KINDS.size() - 1]


## Handling class of a kind: &"car", &"bike" or &"hover".
static func cls_of(kind: StringName) -> StringName:
	return StringName(SPECS[kind].get("cls", &"car")) if SPECS.has(kind) else &"car"


## Every Game.load_model name of a kind, best first.
static func model_names(kind: StringName) -> Array[String]:
	var out: Array[String] = []
	if not SPECS.has(kind):
		return out
	out.append(String(SPECS[kind]["model"]))
	for a: String in SPECS[kind].get("alt", []):
		out.append(a)
	return out


## Mass in kg (the inline "mass" key, else BASE_STATS, else a sedan's).
static func mass_of(kind: StringName) -> float:
	if SPECS.has(kind) and SPECS[kind].has("mass"):
		return float(SPECS[kind]["mass"])
	return float(BASE_STATS.get(kind, BASE_STATS[&"sedan"])["mass"])


## Seats, driver included (the inline "seats" key, else BASE_STATS, else 4).
static func seats_of(kind: StringName) -> int:
	if SPECS.has(kind) and SPECS[kind].has("seats"):
		return int(SPECS[kind]["seats"])
	return int(BASE_STATS.get(kind, {"seats": 4})["seats"])


## The paint a kind wears for the random COLORS entry `c`: its own palette (taxis are yellow, vans white and grey ...) when it has one in PALETTES and `c` is one of COLORS, else `c` itself
## (a husk's WRECK_COLOR and every kind without a palette are untouched).
static func paint_for(kind: StringName, c: Color) -> Color:
	if not PALETTES.has(kind):
		return c
	var i := COLORS.find(c)
	if i < 0:
		return c
	var pal: Array = PALETTES[kind]
	return pal[i % pal.size()]


## The first model of the kind that exists as an asset ("" when none does: the primitive fallback is drawn).
static func available_model(kind: StringName) -> String:
	for m in model_names(kind):
		if ResourceLoader.exists("res://assets/models/%s.glb" % m):
			return m
	return ""


## The look of a kind in the far traffic, falling back to the sedan's when the kind is unknown or its model is not built yet.
static func far_look(kind: StringName) -> Dictionary:
	if SPECS.has(kind) and SPECS[kind].has("far") and (available_model(kind) != "" or cls_of(kind) == &"car"):
		return SPECS[kind]["far"]
	return {"tint": Color(1.0, 0.92, 0.78), "speed": 1.0}


static func cap_for(quality: int) -> int:
	return PerfTiers.cap_scale(CAPS[clampi(quality, 0, 2)])        # the Compatibility renderer spawns fewer


## Vehicle heading (Node3D.rotation.y, forward = -Z) for travelling along `axis` (0 = +-X, 1 = +-Z) in direction `dir` (+1 / -1).
static func heading_for(axis: int, dir: int) -> float:
	if axis == 0:
		return -PI * 0.5 if dir > 0 else PI * 0.5
	return PI if dir > 0 else 0.0


## Signed offset from a road's centre line of the right-hand lane (or bay, with dist = BAY) for travel direction `dir` along `axis`. Facing +X the right
## hand is +Z, facing +Z it is -X, so axis 0 gives +dist * dir and axis 1 gives -dist * dir (src/vehicles.js used +dist * dir on both: left-hand traffic on Z roads).
static func lane_offset(axis: int, dir: int, dist: float) -> float:
	return dist * dir if axis == 0 else -dist * dir


## Road centre line coordinate of road `i` (0..N).
static func road_center(i: int) -> float:
	return -Game.HALF + i * Game.PITCH


## Index of the road centre line nearest to v.
static func road_index(v: float) -> int:
	return clampi(roundi((v + Game.HALF) / Game.PITCH), 0, Game.N)
