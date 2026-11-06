class_name VehicleSpecs
extends RefCounted
## Numbers of the vehicles module: car specs (src/vehicles.js SPECS plus an SUV), the per-tier caps, colours, streaming distances and the traffic rules.
## Keep every tuning number here so the manager, the vehicle and the tests agree.

## Vehicles that feel like cars (owner round 3): top speeds 19-35 m/s (68-126 km/h, a sport car or interceptor 35, a bus 19) so the 1.3 km map takes 40-70 s, hit points are about
## 2.5x the old numbers (a normal crash does not wreck a car, see the CRASH_* constants), `acc` = first-gear acceleration of a CAR (cars use the gearbox + tyre model of
## Vehicle._drive_car, bikes and hover craft the arcade model); mu = optional tyre grip factor, steer = optional steering factor. Nitro adds NITRO_SPEED on top.
## max = top speed m/s, acc = acceleration m/s2, brake = braking m/s2, grip = lateral grip (1/s), hp, model = Game.load_model name,
## len / wid / hgt = the model's size in metres (assets contract), wheel = wheel radius, axle_z = axle offset from the centre (wheels sit at +-axle_z).
const SPECS := {
	&"sedan": {"max": 28.0, "acc": 9.6, "brake": 40.0, "grip": 6.5, "hp": 300.0, "model": "car_sedan", "len": 4.75, "wid": 1.86, "hgt": 1.48, "wheel": 0.335},
	&"sport": {"max": 35.0, "acc": 12.0, "brake": 48.0, "grip": 5.2, "hp": 250.0, "model": "car_sport", "len": 4.45, "wid": 1.92, "hgt": 1.20, "wheel": 0.335, "mu": 1.25, "steer": 1.1},
	&"compact": {"shape": true, "max": 25.0, "acc": 8.6, "brake": 36.0, "grip": 6.2, "hp": 230.0, "mass": 1050.0, "seats": 4, "model": "car_compact", "len": 3.7, "wid": 1.68, "hgt": 1.5, "wheel": 0.3, "mu": 1.0},
	&"suv": {"max": 26.0, "acc": 7.4, "brake": 36.0, "grip": 6.8, "hp": 375.0, "model": "car_suv", "len": 4.85, "wid": 1.98, "hgt": 1.83, "wheel": 0.385, "mu": 1.05},
	# --- handling classes (optional keys, a spec without them is a plain car) ---
	# cls = "car" | "bike" | "hover"; alt = further Game.load_model names tried when `model` does not exist (the primitive fallback is used when none does);
	# bike: lean_max = body roll in rad at full lean, steer = steering rate factor; hover: hover_h = ride height of the model, bob = bob amplitude in m,
	# drift = extra sideways slide (grip stays low), coast = coast drag; far = look of the kind in the far traffic (tint, speed factor, see ambient_traffic.gd).
	&"bike": {"cls": "bike", "max": 33.0, "acc": 18.0, "brake": 38.0, "grip": 7.8, "hp": 140.0, "model": "bike_street", "alt": ["bike", "bike_sport"], "len": 2.1, "wid": 0.8, "hgt": 1.3,
		"wheel": 0.34, "lean_max": 0.62, "steer": 1.3, "far": {"tint": Color(1.0, 0.95, 0.82), "speed": 1.25}},
	&"hover": {"cls": "hover", "max": 30.0, "acc": 14.0, "brake": 30.0, "grip": 2.2, "hp": 225.0, "model": "car_hover", "alt": ["hover_car", "hovercar"], "len": 4.6, "wid": 2.0, "hgt": 1.15,
		"wheel": 0.3, "hover_h": 0.55, "bob": 0.07, "drift": 1.0, "coast": 0.12, "steer": 1.15, "far": {"tint": Color(0.45, 0.95, 1.0), "speed": 1.1}},
	# Vael patrol vehicle: a hover chassis in the hive colours, chases the player from heat 3 (VehicleManager patrols), hp 400.
	&"vael_patrol": {"cls": "hover", "patrol": true, "max": 32.0, "acc": 16.0, "brake": 34.0, "grip": 3.0, "hp": 400.0, "model": "car_vael_patrol", "alt": ["vael_patrol", "hover_vael"],
		"len": 4.9, "wid": 2.1, "hgt": 1.3, "wheel": 0.3, "hover_h": 0.5, "bob": 0.05, "drift": 0.7, "coast": 0.14, "steer": 1.2, "far": {"tint": Color(0.75, 1.0, 0.45), "speed": 0.6}},
	# --- the Wave 14 art set (tools/blender/model_car_taxi.py ... ): sedan platform variants, a van and a truck. mass = kg, seats = driver included,
	# The paints of a kind are in PALETTES (taxis yellow, vans white and grey, the Vael patrol in hive tones).
	&"taxi": {"max": 27.0, "acc": 8.4, "brake": 38.0, "grip": 6.4, "hp": 325.0, "mass": 1500.0, "seats": 5, "model": "car_taxi", "len": 4.75, "wid": 1.86, "hgt": 1.66, "wheel": 0.335},
	&"wagon": {"max": 27.0, "acc": 8.0, "brake": 38.0, "grip": 6.4, "hp": 340.0, "mass": 1600.0, "seats": 5, "model": "car_wagon", "len": 4.92, "wid": 1.86, "hgt": 1.55, "wheel": 0.35},
	&"van": {"max": 24.0, "acc": 6.0, "brake": 32.0, "grip": 6.0, "hp": 440.0, "mass": 2300.0, "seats": 3, "model": "car_van", "len": 5.2, "wid": 2.0, "hgt": 2.25, "wheel": 0.37, "mu": 0.98},
	&"truck": {"max": 21.0, "acc": 5.0, "brake": 28.0, "grip": 5.4, "hp": 650.0, "mass": 7500.0, "seats": 3, "model": "car_truck", "len": 6.4, "wid": 2.1, "hgt": 3.0, "wheel": 0.42, "mu": 0.95},
	# --- creature kit (tools/creature_kit.py, Quaternius space kit, CC0): a moon rover on four wheels and a hover skiff, both rare in the traffic mix.
	&"rover": {"max": 23.0, "acc": 7.0, "brake": 34.0, "grip": 6.2, "hp": 425.0, "mass": 1900.0, "seats": 2, "model": "car_rover", "len": 2.3, "wid": 1.9, "hgt": 2.03, "wheel": 0.3},
	&"skiff": {"cls": "hover", "max": 32.0, "acc": 14.0, "brake": 32.0, "grip": 2.0, "hp": 200.0, "mass": 900.0, "seats": 2, "model": "car_skiff", "len": 5.2, "wid": 1.85, "hgt": 1.4, "wheel": 0.3,
		"hover_h": 0.6, "bob": 0.09, "drift": 1.1, "coast": 0.12, "steer": 1.2, "far": {"tint": Color(0.7, 0.85, 1.0), "speed": 1.2}},
	# --- traffic and emergency set (primitive fallback until the art exists): a city bus, an interceptor and an ambulance (sirens: other traffic yields), a scooter-style quantum bike.
	&"bus": {"shape": true, "max": 19.0, "acc": 4.2, "brake": 24.0, "grip": 5.0, "hp": 800.0, "mass": 11000.0, "seats": 4, "model": "car_bus", "alt": ["bus"], "len": 9.5, "wid": 2.5, "hgt": 3.2, "wheel": 0.5, "mu": 0.9},
	&"interceptor": {"shape": true, "siren": true, "max": 35.0, "acc": 12.0, "brake": 46.0, "grip": 6.0, "hp": 350.0, "mass": 1500.0, "seats": 2, "model": "car_interceptor", "alt": ["interceptor"], "len": 4.7, "wid": 1.95, "hgt": 1.3, "wheel": 0.34, "mu": 1.2},
	&"ambulance": {"shape": true, "siren": true, "max": 27.0, "acc": 6.8, "brake": 34.0, "grip": 6.0, "hp": 475.0, "mass": 2800.0, "seats": 3, "model": "car_ambulance", "len": 5.4, "wid": 2.05, "hgt": 2.4, "wheel": 0.37, "mu": 1.0},
	&"qbike": {"shape": true, "cls": "bike", "max": 35.0, "acc": 19.0, "brake": 36.0, "grip": 8.0, "hp": 110.0, "mass": 140.0, "seats": 1, "model": "bike_quantum", "alt": ["scooter", "bike_street"], "len": 1.8, "wid": 0.6, "hgt": 1.15,
		"wheel": 0.26, "lean_max": 0.7, "steer": 1.4, "far": {"tint": Color(0.4, 0.95, 1.0), "speed": 1.3}},
	# --- open world freedom: the hero's HOVER-BIKE (CALL CAR with an empty garage, also a rare traffic kind): a bike chassis floating on a quantum cushion, fast and slidey, one seat.
	&"hoverbike": {"cls": "hover", "max": 35.0, "acc": 18.0, "brake": 34.0, "grip": 2.6, "hp": 150.0, "mass": 260.0, "seats": 1, "model": "bike_street", "alt": ["car_skiff"], "len": 2.1, "wid": 0.8, "hgt": 1.3,
		"wheel": 0.3, "hover_h": 0.75, "bob": 0.1, "drift": 1.0, "coast": 0.14, "steer": 1.35, "far": {"tint": Color(0.4, 1.0, 0.95), "speed": 1.3}},
}
## Paints of the kinds that do not wear the random street palette (VehicleVisual.set_paint maps the random COLORS pick to an entry; a husk keeps WRECK_COLOR).
const PALETTES := {
	&"taxi": [Color(0.86, 0.66, 0.16), Color(0.92, 0.74, 0.2), Color(0.8, 0.58, 0.12), Color(0.88, 0.7, 0.18)],
	&"van": [Color(0.84, 0.86, 0.88), Color(0.62, 0.66, 0.7), Color(0.3, 0.42, 0.56), Color(0.86, 0.87, 0.9), Color(0.4, 0.44, 0.48)],
	&"truck": [Color(0.56, 0.62, 0.66), Color(0.3, 0.42, 0.56), Color(0.68, 0.4, 0.26), Color(0.8, 0.82, 0.84)],
	&"bus": [Color(0.78, 0.5, 0.18), Color(0.28, 0.5, 0.62), Color(0.62, 0.66, 0.7), Color(0.3, 0.52, 0.48)],
	&"interceptor": [Color(0.12, 0.14, 0.2), Color(0.86, 0.87, 0.9), Color(0.15, 0.18, 0.3), Color(0.2, 0.22, 0.26)],
	&"ambulance": [Color(0.9, 0.91, 0.93), Color(0.86, 0.87, 0.9), Color(0.92, 0.93, 0.94), Color(0.88, 0.9, 0.92)],
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
## Spawn weights of a streamed vehicle (sedan, sport, suv, bike, hover, taxi, wagon, van, truck, rover, skiff, bus, interceptor, ambulance, qbike). Patrols (vael_patrol) are never streamed, the manager adds them from heat 3.
const STREAM_KINDS: Array[StringName] = [&"sedan", &"sport", &"suv", &"compact", &"bike", &"hover", &"taxi", &"wagon", &"van", &"truck", &"rover", &"skiff", &"bus", &"interceptor", &"ambulance", &"qbike", &"hoverbike"]
const STREAM_WEIGHTS: Array[float] = [0.12, 0.1, 0.08, 0.1, 0.07, 0.07, 0.09, 0.05, 0.07, 0.05, 0.03, 0.03, 0.04, 0.03, 0.02, 0.03, 0.02]

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

# --- driving: bikes and hover craft keep the arcade model (src/vehicles.js drive()), cars use the gearbox + tyre model (Vehicle._drive_car) ---
const REVERSE_FRACTION := 0.3          ## top reverse speed as a fraction of max
const COAST_DRAG := 0.5                ## 1/s, no throttle (arcade classes)
const HANDBRAKE_DRAG := 1.2            ## 1/s longitudinal (arcade classes)
const HANDBRAKE_GRIP := 1.4            ## lateral grip with the handbrake (arcade classes)
const STEER_RATE := 2.3                ## rad/s at full authority (arcade classes)
const UNPOWERED_DRAG := 3.0            ## a car nobody drives slows down with this rate

# --- the car model: single-track (bicycle) tyres with a slip-angle curve, weight transfer, a 5 speed gearbox, speed sensitive steering ---
const G := 9.8
const GEAR_TOPS: Array[float] = [0.20, 0.38, 0.57, 0.77, 1.0]     ## top speed of each gear as a fraction of the car's top speed
const GEAR_ACC: Array[float] = [1.0, 0.8, 0.64, 0.52, 0.42]       ## acceleration of each gear relative to the first (the spec's `acc`)
const SHIFT_TIME := 0.2                ## s of torque cut at every gear change (the engine note drops, the car lurches a little)
const UPSHIFT_AT := 0.93               ## rpm fraction of the gear that changes up
const DOWNSHIFT_BELOW := 0.55          ## rpm fraction the LOWER gear would be at that makes the box change down
const IDLE_RPM := 0.16
const ENGINE_BRAKE := 2.4              ## m/s2 of deceleration with the throttle released
const AERO := 0.0016                   ## 1/m: aero + rolling drag decel = AERO * v^2
const BRAKE_K := 0.32                  ## spec["brake"] x this = braking deceleration in m/s2 (a sedan: 15 m/s2)
const CG_FRONT := 0.46                 ## centre of gravity distance from the front axle as a fraction of the wheel base
const WHEEL_BASE := 0.6                ## wheel base as a fraction of the car length (a bus and a van are longer, see wheelbase())
const CG_HEIGHT := 0.34                ## centre of gravity height as a fraction of the car height
const MU := 1.12                       ## tyre grip on dry asphalt (a spec may scale it with "mu"); wet streets take WET_GRIP_LOSS of it
const WET_GRIP_LOSS := 0.2
const PEAK_SLIP := 0.15                ## rad: the slip angle of the most lateral force; beyond it the tyre slides (grip falls to SLIDE_GRIP of the peak)
const SLIDE_GRIP := 0.66
const STEER_MAX := 0.6                 ## rad of front wheel angle at a standstill
const STEER_V0 := 11.0                 ## m/s at which the lock has fallen to about half
const STEER_RATE_CAR := 3.2            ## rad/s wheel speed turning in, STEER_RETURN turning back
const STEER_RETURN := 5.0
const COUNTER_STEER := 0.9             ## assist: the front wheels follow the slip angle of the body, a slide is caught instead of spinning the car
const YAW_DAMP := 0.5                  ## 1/s of extra yaw damping (inertia of the whole car)
const LOW_SPEED := 2.0                 ## m/s: below this the car turns kinematically (a tyre model has no meaning at a walking pace)
const HANDBRAKE_REAR := 0.34           ## rear tyre grip factor while the handbrake is held (it comes back over DRIFT_RECOVER s)
const BODY_PITCH := 0.0042             ## rad per m/s2 of longitudinal acceleration (nose dip under braking, squat under power)
const BODY_ROLL := 0.0055              ## rad per m/s2 of lateral acceleration
const BODY_PITCH_MAX := 0.075
const BODY_ROLL_MAX := 0.085

# --- drift (E1) ---
const DRIFT_RECOVER := 0.6             ## s: traction returns this slowly after the handbrake is released
const DRIFT_ASSIST := 1.1              ## rad/s of extra yaw when steering against a slide (arcade classes)
const SMOKE_SLIP := 3.5                ## lateral speed (m/s) above which the tyres smoke
const TYRE_SMOKE_EVERY := 0.09

# --- collisions and damage (owner round 3: a car survives normal crashes; damage grows with the impact speed along the contact normal) ---
const HIT_SPEED := 5.0                 ## wall impact (normal speed) above this is a collision with sound and sparks (arcade classes also hurt from here)
const HIT_DAMAGE := 2.2                ## arcade classes: hp per m/s of impact
const BOUNCE := 1.2                    ## arcade classes: vn restitution factor (vel -= BOUNCE * vn * n)
const RESTITUTION := 0.22              ## cars: bounce off a wall or another car
const WALL_FRICTION := 0.4             ## tangential speed lost per unit of normal impulse (a scrape)
const CRASH_SAFE := 6.5                ## m/s along the contact normal: below this a bump does nothing to the hull
const CRASH_WRECK := 27.0              ## m/s: a wall hit this hard destroys a stock car (CRASH_REF_HP): a sedan at its top speed (28) is wrecked by a head-on wall, 72 km/h is not
const CRASH_POWER := 1.6               ## damage fraction = ((v - SAFE) / (WRECK - SAFE)) ^ POWER
const CRASH_REF_HP := 300.0            ## hp that fraction is of (a sedan: the damage is absolute, a bus with 800 hp survives much more)
const CAR_SEPARATION := 3.6            ## circle distance of the car-to-car bump (legacy, the OBB test uses the real hull sizes)
const CAR_HIT_SPEED := 6.5             ## relative speed above which two cars hurt each other
const HERO_HURT_SPEED := 16.0          ## the driver is hurt only by hard impacts (m/s along the normal), (v - this) x HERO_HURT hp
const HERO_HURT := 1.6
const EXTERNAL_DAMAGE := 1.0           ## factor of damage() from bullets, blasts and fire (the callers' numbers did not change, the hit points did)
const RAM_SPEED := 8.0                 ## running over enemies needs this speed
const RAM_RADIUS := 2.4
const RAM_FACTOR := 3.5
const RAM_COOLDOWN := 0.6
const CARJACK_HEAT := 0.2
const GLASS_BREAK_AT := 0.35           ## hull damage fraction from which the windows crack (earlier on a hard frontal hit)
const DENT_MIN := 0.04                 ## damage fraction of one impact that dents the panels at all

# --- damage states, enter / exit ---
const SMOKE_BELOW := 0.4               ## hp fraction: smoke
const FIRE_BELOW := 0.15               ## hp fraction: fire, the car burns down (BURN_DPS hp per second) and blows up
const BURN_DPS := 3.4
const FX_RANGE := 70.0                 ## smoke and fire are only spawned this close to the player
const SMOKE_EVERY := 0.34
const FIRE_EVERY := 0.2
const EXIT_SAFE_SPEED := 9.0           ## leaving a car faster than this hurts (EXIT_HURT hp per m/s over it)
const EXIT_HURT := 2.0
const CHAIN_RADIUS := 7.0              ## open world: a car that blows up sets every car within this of it alight ...
const CHAIN_DELAY := 1.4               ## ... and they follow after up to this many seconds (staggered by distance): a pile-up goes off one after the other
const ENTER_REACH := 1.9               ## metres from the hull edge a car can be entered or hijacked (the old 4.2 m from the middle still works); a moving car adds ENTER_MOVING per m/s
const ENTER_MOVING := 0.12
const ENTER_MOVING_MAX := 2.6
const EXIT_BRAKE := 0.6                ## a car the player leaves keeps this share of its speed (it rolls to a stop)

# --- mounted weapons (E2): rate = shots/s, dmg per hit, heat per shot (1.0 locks), cool = heat/s, ammo = rounds, range m, spread rad, blast = radius (0 none) ---
const WEAPONS := {
	&"sport": {"name": "RAIL GUN", "rate": 9.0, "dmg": 9.0, "heat": 0.07, "cool": 0.35, "ammo": 240, "range": 90.0, "spread": 0.025, "color": Color(0.3, 0.95, 1.0)},
	&"suv": {"name": "CANNON", "rate": 1.4, "dmg": 55.0, "heat": 0.4, "cool": 0.3, "ammo": 30, "range": 110.0, "spread": 0.0, "blast": 3.5, "color": Color(1.0, 0.6, 0.2)},
	&"hover": {"name": "BOLT GUN", "rate": 5.0, "dmg": 16.0, "heat": 0.14, "cool": 0.3, "ammo": 120, "range": 100.0, "spread": 0.01, "color": Color(0.8, 0.4, 1.0)},
}
const WEAPON_LOCK_RESUME := 0.4        ## an overheated weapon fires again below this heat

# --- nitro (E4): sprint while driving ---
const NITRO_SPEED := 1.3               ## top speed factor
const NITRO_ACC := 1.9                 ## acceleration factor
const NITRO_DRAIN := 0.33              ## tank (0..1) per second
const NITRO_REGEN := 0.12
const NITRO_DELAY := 1.2               ## s after boosting before the tank refills
const NITRO_MIN := 0.08                ## tank needed to start a boost
const NITRO_COOL := 12.0               ## m/s2 the extra speed bleeds off after a boost

# --- Vael pursuit tactics (E4): ram, boxin (hold station beside him, squeeze), block (get ahead and sit across the road) ---
const TACTICS: Array[StringName] = [&"ram", &"boxin", &"block"]
const BOXIN_SIDE := 4.2                ## m beside the target
const BLOCK_AHEAD := 38.0              ## m ahead of the target (scaled by his speed, see Vehicle.chase_goal)
const BLOCK_STOP := 7.0                ## within this of the road block point the patrol stops and turns broadside

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

# --- police pursuit ladder (VehicleManager._tick_cops) ---
const COP_HEAT := 0.5                  ## heat from which an interceptor tails the hero
const COP_RAM_HEAT := 2.0              ## below: it shadows him with the siren on, from here it rams
const COP_RAM_FACTOR := 0.7            ## a police ram hurts a little less than a Vael patrol's
const COP_SPIKE_HEAT := 3.0            ## from here the police lay spike strips ahead of a driving hero
const COP_CAPS: Array[int] = [2, 3, 4]    ## interceptors at once per tier
const COP_EVERY := 5.0
const COP_MIN := 50.0
const COP_MAX := 95.0
const COP_STAND_DOWN := 0.3
const SPIKE_EVERY := 12.0              ## s between strips
const SPIKE_AHEAD := 60.0              ## m ahead of the hero's motion
const SPIKE_HALF_WIDTH := 4.6
const SPIKE_HALF_DEPTH := 1.0
const SPIKE_LIFE := 25.0
const TIRES_TIME := 9.0
const TIRES_SPEED := 0.55
const TIRES_GRIP := 0.55
const TIRES_DAMAGE := 12.0

# --- traffic (right-hand lanes on Game.LANE, junction turns, stops for obstacles) ---
const AI_LOOK := 11.0                  ## obstacle check distance ahead
const AI_SIDE := 2.6                   ## obstacle check half width
const AI_CRUISE_MIN := 9.0
const AI_CRUISE_MAX := 14.0
const AI_TURN_COOLDOWN := 14.0         ## metres before the next junction may turn again
const AI_STRAIGHT_CHANCE := 0.55
# --- traffic rules (wave 53): lights at every junction, yielding to sirens, reactions to horn / gunfire / crashes ---
const SIGNAL_CYCLE := 18.0             ## s: axis 0 is green for 7.5 s, amber 1.5 s, then red while axis 1 runs (offset by half a cycle)
const SIGNAL_GREEN := 7.5
const SIGNAL_AMBER := 1.5
const LIGHT_LOOK := 22.0               ## a car starts braking for a red this many metres before the junction centre
const LIGHT_COMMIT := 4.5              ## closer than this it is committed and drives through
const AMBER_STOP := 11.0               ## on amber it stops only when farther than this
const SIREN_SPEED := 1.35              ## emergency cars cruise this much faster
const YIELD_RANGE := 45.0              ## a siren this close behind makes traffic pull over
const YIELD_SHIFT := 1.6               ## m towards the kerb while yielding
const YIELD_SPEED := 4.0               ## m/s while yielding
const PANIC_TIME := 4.0                ## s of flight after gunfire
const PANIC_SPEED := 1.5
const GUN_HEAR := 45.0
const HORN_HEAR := 16.0
const HORN_NUDGE := 1.5                ## s a car ahead of a horn hurries on
const CRASH_HEAR := 20.0
const STUN_TIME := 1.4                 ## s traffic near a crash stops


## 0 green, 1 amber, 2 red for traffic travelling along `axis` at signal clock `clock` (s). The two axes are never green together.
static func signal_state(axis: int, clock: float) -> int:
	var t := fposmod(clock + (0.0 if axis == 0 else SIGNAL_CYCLE * 0.5), SIGNAL_CYCLE)
	if t < SIGNAL_GREEN:
		return 0
	return 1 if t < SIGNAL_GREEN + SIGNAL_AMBER else 2


static func is_siren(kind: StringName) -> bool:
	return SPECS.has(kind) and bool(SPECS[kind].get("siren", false))


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


## Wheel base in metres: WHEEL_BASE x the length (a bus, a truck and a van carry their wheels nearer the ends).
static func wheelbase(kind: StringName) -> float:
	var ln := float(SPECS[kind]["len"]) if SPECS.has(kind) else 4.75
	var k := WHEEL_BASE + (0.06 if ln > 5.0 else 0.0)
	return ln * k


## Tyre grip factor of a kind on dry asphalt (MU x the spec's "mu").
static func mu_of(kind: StringName) -> float:
	return MU * (float(SPECS[kind].get("mu", 1.0)) if SPECS.has(kind) else 1.0)


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
	var n: int = CAPS[clampi(quality, 0, 2)]
	if quality == 0:
		n = LowPlus.scaled(n, LowPlus.CAR_SHARE, 2)               # LOW+: 2 live cars
	return PerfTiers.cap_scale(n)        # the Compatibility renderer spawns fewer


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
