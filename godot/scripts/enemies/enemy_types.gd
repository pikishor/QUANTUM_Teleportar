class_name EnemyTypes
extends RefCounted
## The ENEMY table of src/models.js (numbers play-tested in the prototype) plus the human operative.
## Models are authored at final size: `scale` of the prototype is not applied. center_y / radius follow the asset contract
## (body centres at 0.95 / 0.82 / 1.40 m for the drones, hit radii 0.95 / 0.8 / 1.35 m).
##   hover: height of the drone's node above the ground (the model's origin is its ground contact, the body hangs 0.7-1.4 m above it)
##   fire:  seconds between shots (drones) or between bursts (operative); burst: rounds per volley; dmg per round / bolt

const TYPES := {
	&"sentinel": {
		"hp": 60.0, "speed": 4.6, "range": 22.0, "fire": Vector2(1.0, 1.7), "dmg": 7.0, "bolt": 30.0, "burst": 1,
		"color": Color(1.0, 0.24, 0.37), "score": 50, "radius": 0.95, "heat": 0.22, "center_y": 0.95, "hover": 0.35,
		"model": "drone_sentinel", "drone": true, "kamikaze": false,
	},
	&"striker": {
		"hp": 34.0, "speed": 10.5, "range": 0.0, "fire": Vector2(1.0, 1.0), "dmg": 30.0, "bolt": 0.0, "burst": 0,
		"color": Color(1.0, 0.63, 0.23), "score": 40, "radius": 0.8, "heat": 0.15, "center_y": 0.82, "hover": 0.4,
		"model": "drone_striker", "drone": true, "kamikaze": true,
	},
	&"heavy": {
		"hp": 230.0, "speed": 3.0, "range": 30.0, "fire": Vector2(1.5, 2.1), "dmg": 9.0, "bolt": 26.0, "burst": 3,
		"color": Color(0.70, 0.36, 1.0), "score": 160, "radius": 1.35, "heat": 0.5, "center_y": 1.40, "hover": 0.1,
		"model": "drone_heavy", "drone": true, "kamikaze": false,
	},
	&"operative": {
		"hp": 80.0, "speed": 4.4, "range": 30.0, "fire": Vector2(1.1, 2.0), "dmg": 5.0, "bolt": 0.0, "burst": 3,
		"color": Color(1.0, 0.22, 0.2), "score": 70, "radius": 0.55, "heat": 0.25, "center_y": 1.05, "hover": 0.0,
		"model": "operative", "drone": false, "kamikaze": false,
		"walk": 1.5, "burst_gap": 0.12, "aim_time": 0.45, "spread": 0.035, "spread_per_m": 0.0008,
	},
}

## Alive at once, per graphics tier (Game.quality): LOW, MED, HIGH.
const CAPS: Array[int] = [5, 8, 12]
## Energy the player gets back for a kill.
const ENERGY_REFUND := 8.0


static func get_cfg(type: StringName) -> Dictionary:
	return TYPES[type] if TYPES.has(type) else TYPES[&"sentinel"]
