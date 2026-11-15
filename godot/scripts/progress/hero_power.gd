class_name HeroPower
extends RefCounted
## Hero power by difficulty: ONE table (rows STORY, NORMAL, HARD, QUANTUM, same index as Difficulty.NAMES), read live from Difficulty.current so changing the
## difficulty applies at once. Hooks: Player (regen, sprint, jump, glide, wall-run, damage taken), PlayerWeapon (damage), Quantum (energy cost / regen, cooldowns,
## QUANTUM TELEPORT range and chained hops), CameraRig (sprint FOV).
## regen: health per second multiplier (and the regen pause is divided by it) | dmg: damage the hero deals | energy_regen / energy_cost / cooldown: multipliers |
## sprint: sprint speed multiplier | jump: jump speed multiplier | glide: fall speed cap while gliding (0 = no glide) | wall_run: bool | tp_range: QUANTUM TELEPORT range multiplier |
## tp_hops: teleports in one chain (extra hops inside CHAIN_WINDOW have no cooldown) | taken: extra damage-taken multiplier on top of Difficulty.
## QUANTUM SNAKES (wave 115, read through SnakePower): snake_range anchor reach in metres | snake_cost cost multiplier of snake energy | snake_regen energy per second on the ground | snake_speed swing speed cap |
## snake_release speed multiplier when a swing is let go | climb_speed m/s on a wall | fly_cruise / fly_boost flight speeds | fly_drain flight energy per second | fly_free 1 = flight is open from the start (else it needs a WING POWER rank) | air_jumps extra jumps in the air.
const ROWS: Array[Dictionary] = [
	{"regen": 8.0, "dmg": 1.4, "energy_regen": 6.0, "energy_cost": 0.05, "cooldown": 0.1, "sprint": 1.5, "jump": 1.6, "glide": 3.0, "wall_run": true, "tp_range": 3.0, "tp_hops": 6, "taken": 0.9, "snake_range": 70.0, "snake_cost": 0.1, "snake_regen": 45.0, "snake_speed": 62.0, "snake_release": 1.25, "climb_speed": 9.5, "fly_cruise": 40.0, "fly_boost": 72.0, "fly_drain": 6.0, "fly_free": 1.0, "air_jumps": 2.0},
	{"regen": 1.0, "dmg": 1.0, "energy_regen": 1.0, "energy_cost": 1.0, "cooldown": 1.0, "sprint": 1.0, "jump": 1.0, "glide": 6.0, "wall_run": true, "tp_range": 1.0, "tp_hops": 2, "taken": 1.0, "snake_range": 56.0, "snake_cost": 0.55, "snake_regen": 24.0, "snake_speed": 54.0, "snake_release": 1.18, "climb_speed": 7.5, "fly_cruise": 34.0, "fly_boost": 60.0, "fly_drain": 6.0, "fly_free": 1.0, "air_jumps": 1.0},
	{"regen": 0.7, "dmg": 0.95, "energy_regen": 0.85, "energy_cost": 1.1, "cooldown": 1.1, "sprint": 1.0, "jump": 1.0, "glide": 0.0, "wall_run": false, "tp_range": 1.0, "tp_hops": 1, "taken": 1.0, "snake_range": 46.0, "snake_cost": 1.0, "snake_regen": 15.0, "snake_speed": 46.0, "snake_release": 1.1, "climb_speed": 6.0, "fly_cruise": 30.0, "fly_boost": 50.0, "fly_drain": 6.0, "fly_free": 0.0, "air_jumps": 1.0},
	{"regen": 0.5, "dmg": 0.9, "energy_regen": 0.7, "energy_cost": 1.2, "cooldown": 1.2, "sprint": 1.0, "jump": 1.0, "glide": 0.0, "wall_run": false, "tp_range": 1.0, "tp_hops": 1, "taken": 1.0, "snake_range": 40.0, "snake_cost": 1.2, "snake_regen": 11.0, "snake_speed": 42.0, "snake_release": 1.06, "climb_speed": 5.2, "fly_cruise": 28.0, "fly_boost": 46.0, "fly_drain": 6.0, "fly_free": 0.0, "air_jumps": 1.0},
]
const CHAIN_WINDOW := 4.0
const WALL_GRAVITY := 0.15


static func row(m: int = -1) -> Dictionary:
	return ROWS[Difficulty.clamp_mode(Difficulty.current if m < 0 else m)]


static func f(key: String, m: int = -1) -> float:
	return float(row(m)[key])


static func cost(base: float) -> float:
	return base * f("energy_cost")


static func cd(base: float) -> float:
	return base * f("cooldown")


static func can_wall_run() -> bool:
	return bool(row()["wall_run"])


static func hops() -> int:
	return int(row()["tp_hops"])
