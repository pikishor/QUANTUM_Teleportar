class_name Difficulty
extends RefCounted
## Difficulty setting (STORY, NORMAL, HARD, QUANTUM) plus the per-chapter curves. Pure static rules: `current` is the live mode (UiSettings.publish copies the saved choice here,
## default NORMAL, so older settings files load unchanged). Setting multipliers scale enemy health / damage dealt to the player / aim spread / aggression (fire rate), heat gain,
## credit rewards and how much health a checkpoint retry restores. Chapter curves (index 0-7, then the endless sectors) scale enemy damage and boss health.
## tools/balance_sim.gd prints the resulting time-to-kill and survivability table.

const NAMES: Array[String] = ["STORY", "NORMAL", "HARD", "QUANTUM"]
const NORMAL := 1
## Per mode: hp, dmg (damage the player takes), spread (aim error), aggr (fire-rate factor, > 1 shoots more often), heat, credits, cp (health restored by a checkpoint retry, 0..1).
const MODES: Array[Dictionary] = [
	{"hp": 0.70, "dmg": 0.65, "spread": 1.50, "aggr": 0.80, "heat": 0.60, "credits": 0.80, "cp": 1.0},
	{"hp": 1.00, "dmg": 1.00, "spread": 1.00, "aggr": 1.00, "heat": 1.00, "credits": 1.00, "cp": 1.0},
	{"hp": 1.35, "dmg": 1.35, "spread": 0.75, "aggr": 1.20, "heat": 1.30, "credits": 1.25, "cp": 0.6},
	{"hp": 1.60, "dmg": 1.65, "spread": 0.60, "aggr": 1.35, "heat": 1.70, "credits": 1.60, "cp": 0.3},
]

static var current := NORMAL


static func clamp_mode(m: int) -> int:
	return clampi(m, 0, NAMES.size() - 1)


static func set_mode(m: int) -> void:
	current = clamp_mode(m)


static func mode_name(m: int = -1) -> String:
	return NAMES[clamp_mode(current if m < 0 else m)]


static func next_mode(m: int) -> int:
	return (clamp_mode(m) + 1) % NAMES.size()


static func mult(key: String, m: int = -1) -> float:
	return float((MODES[clamp_mode(current if m < 0 else m)] as Dictionary)[key])


## Chapter curve for the damage enemies deal (1.0 in chapter 1, +6 % per chapter, capped at chapter 12 so the endless sectors stay fair).
static func chapter_dmg(chapter: int) -> float:
	return 1.0 + 0.06 * minf(float(maxi(chapter, 0)), 12.0)


## Chapter curve for normal enemy health (the same line Progress.difficulty uses, capped).
static func chapter_hp(chapter: int) -> float:
	return 1.0 + 0.10 * minf(float(maxi(chapter, 0)), 12.0)


## Boss health curve: bosses already carry big base health, so they scale at about the troops' rate (+9 % per chapter) so a boss fight keeps its length as the hero grows.
static func boss_hp(chapter: int) -> float:
	return 1.0 + 0.09 * minf(float(maxi(chapter, 0)), 12.0)


## Total damage factor on a hit the player takes in `chapter`.
static func damage_taken(chapter: int, m: int = -1) -> float:
	return chapter_dmg(chapter) * mult("dmg", m)


static func story_chapter() -> int:
	var loop := Engine.get_main_loop() as SceneTree          # looked up by node so the class also compiles in -s scripts (tools/balance_sim.gd), where autoloads are not visible
	var g: Node = loop.root.get_node_or_null("Game") if loop != null else null
	var st: Variant = g.get("story") if g != null else null
	if st is Node and is_instance_valid(st):
		return int((st as Node).get("chapter"))
	return 0
