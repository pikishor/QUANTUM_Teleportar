class_name Dmg
extends RefCounted
## DAMAGE EVERYWHERE (wave 113): the one place for the switch, the caps by tier and the counters of the damage systems (scripts/damage/*, scripts/combat/structure_damage.gd).
## Everything the systems draw is pooled (MultiMesh rings, the shared puff cloud, the shared debris pool) and every pool has a cap per graphics tier, so a long fight never adds a draw call or a
## node: the oldest piece is recycled. Counters (`bump` / `count`) are what the tests wait on (never frame counts).
##   Dmg.enabled          false with QT_DMG=0 in the environment: the new layers stay off, for before / after captures and the legacy tests
##   Dmg.cap(key)         the cap of a pool on the current tier (LOW, MED, HIGH = Game.quality 0, 1, 2; LOW+ counts as LOW)
##   Dmg.bump(key, n)     counters ("plate", "splat", "window", "breach", "crater", "hole", "wreck_fire", ...)

static var enabled := OS.get_environment("QT_DMG") != "0"
static var stats: Dictionary = {}

## LOW, MED, HIGH
const CAPS := {
	&"debris": [28, 56, 96],             ## live pieces of the shared debris pool (props, plates, chunks)
	&"plates": [4, 8, 14],               ## armour plates in flight at once
	&"burning_foes": [1, 2, 4],          ## corpses and enemies that burn at once
	&"burning_wrecks": [1, 2, 4],        ## burning wrecks (flames and smoke), the oldest is put out first
	&"car_holes": [4, 6, 8],             ## bullet holes kept on one car
	&"cars_marked": [3, 5, 8],           ## cars that carry bullet holes at once (the oldest is wiped when a new one is shot)
	&"wall_rays": [4, 6, 9],             ## probes of a structure blast
	&"windows": [3, 5, 9],               ## broken windows per blast
	&"struct_marks": [8, 16, 24],        ## the structure pool of the mark ring (windows, breaches, craters, chips)
	&"fires": [3, 6, 10],                ## spreading fires (props, cars) at once
	&"splat_tokens": [3, 5, 8],          ## hit splatters a second (tokens refilled over time)
	&"foes_fx": [3, 5, 8],               ## enemies that show status effects (burn, shock, freeze) at once
	&"limp_foes": [3, 6, 10],
	&"decals": [40, 40, 40],             ## bullet holes (ImpactDecals.CAPACITY)
}


## The ground height under a point: the street (0), a rooftop or the terrain outside the city plateau (City.ground_height).
static func ground_y(pos: Vector3) -> float:
	var city := Game.world as City
	if city != null:
		return city.ground_height(pos.x, pos.z, pos.y + 1.0)
	return 0.0


static func tier() -> int:
	return clampi(Game.quality, 0, 2)


static func cap(key: StringName) -> int:
	var row: Array = CAPS.get(key, [1, 1, 1])
	return int(row[tier()])


static func bump(key: StringName, n := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n


static func count(key: StringName) -> int:
	return int(stats.get(key, 0))


static func reset_stats() -> void:
	stats.clear()


## The fluid an enemy of this camp or species leaves: the Vael (hive, aliens) bleed acid-green ichor, the gangs' machines leak amber hydraulic fluid, the rogue drones cyan coolant. A creature with a
## glow colour of its own mixes it in. Mercenaries (humans) leave no fluid: armour chips and dust only (target rating 12+).
static func fluid_of(camp: StringName, glow: Color = Color(0, 0, 0, 0)) -> Variant:
	var base: Color
	match camp:
		&"gang":
			base = Color(1.0, 0.62, 0.12)
		&"drones":
			base = Color(0.25, 0.85, 1.0)
		&"merc":
			return null
		_:
			base = Color(0.5, 1.0, 0.2)
	if glow.a > 0.0:
		base = base.lerp(Color(glow.r, glow.g, glow.b), 0.35)
	return base
