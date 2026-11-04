class_name HeroPower
extends RefCounted
## Hero power by difficulty: ONE table (rows STORY, NORMAL, HARD, QUANTUM, same index as Difficulty.NAMES), read live from Difficulty.current so changing the
## difficulty applies at once. Hooks: Player (regen, sprint, jump, glide, wall-run, damage taken), PlayerWeapon (damage), Quantum (energy cost / regen, cooldowns,
## QUANTUM TELEPORT range and chained hops), CameraRig (sprint FOV).
## regen: health per second multiplier (and the regen pause is divided by it) | dmg: damage the hero deals | energy_regen / energy_cost / cooldown: multipliers |
## sprint: sprint speed multiplier | jump: jump speed multiplier | glide: fall speed cap while gliding (0 = no glide) | wall_run: bool | tp_range: QUANTUM TELEPORT range multiplier |
## tp_hops: teleports in one chain (extra hops inside CHAIN_WINDOW have no cooldown) | taken: extra damage-taken multiplier on top of Difficulty.
const ROWS: Array[Dictionary] = [
	{"regen": 8.0, "dmg": 4.0, "energy_regen": 6.0, "energy_cost": 0.05, "cooldown": 0.1, "sprint": 1.5, "jump": 1.6, "glide": 3.0, "wall_run": true, "tp_range": 3.0, "tp_hops": 6, "taken": 0.5},
	{"regen": 1.0, "dmg": 1.0, "energy_regen": 1.0, "energy_cost": 1.0, "cooldown": 1.0, "sprint": 1.0, "jump": 1.0, "glide": 6.0, "wall_run": true, "tp_range": 1.0, "tp_hops": 2, "taken": 1.0},
	{"regen": 0.7, "dmg": 0.95, "energy_regen": 0.85, "energy_cost": 1.1, "cooldown": 1.1, "sprint": 1.0, "jump": 1.0, "glide": 0.0, "wall_run": false, "tp_range": 1.0, "tp_hops": 1, "taken": 1.0},
	{"regen": 0.5, "dmg": 0.9, "energy_regen": 0.7, "energy_cost": 1.2, "cooldown": 1.2, "sprint": 1.0, "jump": 1.0, "glide": 0.0, "wall_run": false, "tp_range": 1.0, "tp_hops": 1, "taken": 1.0},
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
