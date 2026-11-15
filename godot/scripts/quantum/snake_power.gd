class_name SnakePower
extends RefCounted
## The numbers of the QUANTUM SNAKE traversal (SNAKE SWING, SNAKE ZIP, SNAKE CLIMB, SNAKE FLIGHT) in ONE place: the difficulty rows (STORY, NORMAL, HARD, QUANTUM, same index
## as HeroPower.ROWS), the skill-tree nodes of the verb `snake` (RANGE, SPEED, ENERGY, CHAIN BONUS, WING POWER) and HERO MODE (WeaponDefs.hero_mode: unlimited energy, no
## cooldowns). HeroPower owns the rows themselves (the hero power table has one key per number: snake_range ... fly_*), this file only reads them and applies the skill tree.
## Everything is a static function so a test can ask "what does a swing cost on HARD" without a player.
##   range_m()        how far a snake reaches for an anchor (metres)
##   cost(base)       energy cost of an action (the base is in snake energy units, 0..100 pool)
##   regen()          snake energy per second on the ground, in the air it is a third of it
##   speed_cap()      the fastest the hero may swing (m/s)
##   release_boost()  speed multiplier when a swing is let go
##   chain_bonus()    extra speed per chained swing (the skill CHAIN BONUS), at most CHAIN_MAX swings count
##   climb_speed()    metres per second along a wall
##   fly_cruise() / fly_boost() / fly_cost_per_s()   the flight numbers
##   air_jumps()      extra jumps in the air (the double jump)
##   cd(base)         cooldown seconds (HeroPower.cd scale, nothing in HERO MODE)

const CHAIN_MAX := 5


static func row(key: String) -> float:
	return HeroPower.f(key)


static func unlimited() -> bool:
	return WeaponDefs.hero_mode


static func range_m() -> float:
	return row("snake_range") * SkillTree.snake_range_mult()


static func cost(base: float) -> float:
	if unlimited():
		return 0.0
	return base * row("snake_cost") * SkillTree.snake_cost_mult()


static func regen() -> float:
	return row("snake_regen") * (1000.0 if unlimited() else SkillTree.snake_regen_mult())


static func max_energy() -> float:
	return 100.0


static func speed_cap() -> float:
	return row("snake_speed") * SkillTree.snake_speed_mult()


static func release_boost() -> float:
	return row("snake_release")


static func chain_bonus() -> float:
	return SkillTree.snake_chain_bonus()


static func climb_speed() -> float:
	return row("climb_speed") * SkillTree.snake_speed_mult()


static func fly_cruise() -> float:
	return row("fly_cruise") * SkillTree.snake_fly_mult()


static func fly_boost() -> float:
	return row("fly_boost") * SkillTree.snake_fly_mult()


static func fly_cost_per_s() -> float:
	return cost(row("fly_drain")) * SkillTree.snake_fly_cost_mult()


static func air_jumps() -> int:
	return int(row("air_jumps"))


static func cd(base: float) -> float:
	if unlimited():
		return 0.0
	return HeroPower.cd(base)


## Flight is available from the start on STORY and NORMAL; HARD and QUANTUM unlock it with the first WING POWER rank (or HERO MODE), so the skill tree has a real first step there.
static func flight_unlocked() -> bool:
	if unlimited() or row("fly_cruise") <= 0.0:
		return unlimited()
	return row("fly_free") > 0.5 or SkillTree.rank(&"sn_wings") > 0
