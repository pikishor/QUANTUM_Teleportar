class_name RosterDirector
extends RefCounted
## The encounter director of roster 2 (wave 108; docs/WORLD_EXPANSION.md "encounter director picks groups by biome and mission"). Owned by the AlienWorld (`world.roster`), ticked from its ambient loop.
##   WHAT   RosterSpecies.ENCOUNTERS weighed by the biome under the spawn point (TerrainBase.biome_at), the time of day (stalkers and the hive come out at night, mercenaries stay in), the FACTION BIAS of the
##          running mission (MissionBoard.active type: a heist or bounty brings mercenaries, a hack machines, a rescue the hive) and the hero's progress tier (kills: brutes, walkers, snipers, rocket teams and
##          the bosses wait for tier 1). EASY drops one member from a big group and waits longer.
##   WHERE  a ring around the hero (34-80 / 36-92 / 38-105 m by tier), outside the camera view, on dry land of the right biome, never inside the city skirt and never at a site (the alien camps keep
##          their own garrisons); flyers spawn aloft, a sea boss only on deep water.
##   WHEN   every GAP seconds while the hero is outside, not in a vehicle faster than 26 m/s, not in an interior, and fewer than `cap()` roster units live. A WORLD BOSS roams after 4 minutes outside the
##          city at tier 1 (the boss of the biome: RosterSpecies.BOSS_OF_BIOME), one at a time, announced by a line; it is removed when the hero leaves it far behind.
## `spawn_encounter(eid, pos)` is the entry point for missions and tests. Nothing here draws: the bodies are RosterFoe / RosterBoss.

const GAP := [20.0, 15.0, 11.0]
const RING := [[34.0, 80.0], [36.0, 92.0], [38.0, 105.0]]
const BOSS_FIRST := 240.0
const BOSS_EVERY := 420.0
const BOSS_RING := [90.0, 130.0]
const BOSS_FORGET := 420.0
const BUSY_RADIUS := 70.0
const BUSY_MAX := 6

var world: AlienWorld
var rng := RandomNumberGenerator.new()
var enabled := true
var kills := 0
var encounters := 0
var bosses_spawned := 0
var outside_t := 0.0
var gap_t := 8.0
var boss_cd := BOSS_FIRST
var last: Dictionary = {}
var by_faction := {}
var force_mission: StringName = &""
var force_tier := -1
var seen_ids := {}


func _init(w: AlienWorld) -> void:
	world = w
	rng.seed = 108108
	reset()


func reset() -> void:
	RosterFoe.told.clear()
	kills = 0
	encounters = 0
	bosses_spawned = 0
	outside_t = 0.0
	gap_t = 8.0
	boss_cd = BOSS_FIRST
	last = {}
	by_faction = {}
	seen_ids = {}


func tier() -> int:
	return force_tier if force_tier >= 0 else RosterSpecies.tier_for_kills(kills)


func cap() -> int:
	var n: int = RosterSpecies.CAPS[clampi(world.quality, 0, 2)]
	return LowPlus.scaled(n, 0.6, 1) if LowPlus.on() else n


## The type of the mission the hero is on (&"" for free roam): the running MissionBoard offer.
func mission_kind() -> StringName:
	if force_mission != &"":
		return force_mission
	var tree := world.get_tree()
	if tree == null:
		return &""
	var board := tree.get_first_node_in_group(&"mission_board")
	if board == null:
		return &""
	var act: Variant = board.get(&"active")
	if act is Dictionary and not (act as Dictionary).is_empty():
		return StringName((act as Dictionary).get("type", (act as Dictionary).get("kind", &"")))
	return &""


## Roster units alive that the director spawned (no site garrisons, no bosses).
func live_count() -> int:
	var n := 0
	for c in world.creatures:
		if c is RosterFoe and not c.dead and c.site == &"" and c.family != AlienSpecies.BOSS:
			n += 1
	return n


func _busy() -> int:
	var n := 0
	var h := world.hero_pos
	for c in world.creatures:
		if not c.dead and c.aggro and c.global_position.distance_to(h) < BUSY_RADIUS:
			n += 1
	return n


func live_boss() -> RosterBoss:
	for c in world.creatures:
		if c is RosterBoss and not c.dead:
			return c as RosterBoss
	return null


# --- the loop ----------------------------------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if not enabled or not world.hero_pos.is_finite():
		return
	var outside := maxf(absf(world.hero_pos.x), absf(world.hero_pos.z)) >= AlienWorld.CITY_SKIRT + 20.0
	var b := live_boss()
	if b != null and b.site == &"" and Vector2(b.position.x, b.position.z).distance_to(Vector2(world.hero_pos.x, world.hero_pos.z)) > BOSS_FORGET:
		world._remove(b)                                                  # left far behind: it goes away, a new one comes later
		boss_cd = maxf(boss_cd, 120.0)
	if not outside:
		return
	outside_t += dt
	boss_cd -= dt
	gap_t -= dt
	if boss_cd > 20.0 and mission_kind() == &"boss":                    # a boss mission brings the roaming boss within seconds
		boss_cd = 20.0
	if gap_t <= 0.0:
		gap_t = float(GAP[world.quality]) * (1.4 if Difficulty.current == Difficulty.EASY else 1.0) * rng.randf_range(0.8, 1.3)
		try_spawn()
	if boss_cd <= 0.0 and tier() >= 1 and outside_t > BOSS_FIRST * 0.5:
		boss_cd = BOSS_EVERY
		try_boss()


func _allowed() -> bool:
	return not InteriorGameplay.active and world.hero_speed() <= 26.0 and world.creatures.size() < AlienWorld.MAX_CREATURES - 4 and world.hero_alive()


## Spawns one encounter on the ring around the hero. True when units were placed.
func try_spawn() -> bool:
	if not _allowed() or live_count() >= cap() or _busy() >= BUSY_MAX:
		return false
	for t in 8:
		var p := _ring_point(RING[world.quality][0], RING[world.quality][1], true)
		if not p.is_finite():
			continue
		var biome := TerrainBase.biome_at(p.x, p.z, p.y)
		var w := TerrainHeight.water_level_for(p.x, p.z, p.y)
		if (w != TerrainHeight.NO_WATER and w - p.y > 0.4) or TerrainHeight.slope_at(p.x, p.z) > 1.0:
			continue
		var list := RosterSpecies.weights(biome, DayNight.night_now, mission_kind(), tier())
		var eid := RosterSpecies.pick(list, rng.randf())
		if eid == &"":
			continue
		var made := spawn_encounter(eid, p, false)
		if not made.is_empty():
			return true
	return false


func spawn_encounter(eid: StringName, pos: Vector3, aggro := false) -> Array[AlienCreature]:
	var out: Array[AlienCreature] = []
	var e: Dictionary = RosterSpecies.ENCOUNTERS.get(eid, {})
	if e.is_empty():
		return out
	var room := maxi(1, cap() - live_count()) + (4 if aggro else 0)
	var members := RosterSpecies.roll_members(eid, rng, Difficulty.current == Difficulty.EASY, room)
	var g := {"members": [], "id": eid}
	var k := 0
	for sid in members:
		var a := TAU * float(k) / float(maxi(members.size(), 1)) + rng.randf() * 0.6
		var rr := rng.randf_range(2.0, 4.0 + 0.6 * float(members.size())) if members.size() > 1 else 0.0
		var at := pos + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var c := world.spawn_one(sid, at, &"", aggro)
		k += 1
		if c == null:
			continue
		c.group = g
		(g["members"] as Array).append(c)
		out.append(c)
	if not out.is_empty():
		encounters += 1
		var f := StringName(e["faction"])
		by_faction[f] = int(by_faction.get(f, 0)) + 1
		for c in out:
			seen_ids[c.id] = int(seen_ids.get(c.id, 0)) + 1
		last = {"id": eid, "name": String(e["name"]), "faction": f, "pos": pos, "count": out.size(), "biome": TerrainBase.biome_at(pos.x, pos.z, pos.y)}
	return out


func _ring_point(rmin: float, rmax: float, avoid_view: bool) -> Vector3:
	var cam := world.get_viewport().get_camera_3d() if world.get_viewport() != null else null
	var fwd := Vector2(0.0, -1.0)
	if cam != null:
		var f3 := -cam.global_basis.z
		fwd = Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.05 else fwd
	var a := atan2(fwd.y, fwd.x) + rng.randf_range(-1.4, 1.4) if rng.randf() < 0.6 else rng.randf() * TAU
	var r := lerpf(rmin, rmax, sqrt(rng.randf()))
	var x := world.hero_pos.x + cos(a) * r
	var z := world.hero_pos.z + sin(a) * r
	if maxf(absf(x), absf(z)) < AlienWorld.CITY_SKIRT or maxf(absf(x), absf(z)) > TerrainHeight.WORLD_HALF - 60.0:
		return Vector3.INF
	if OutskirtsSites.inside(x, z, 20.0) >= 0:
		return Vector3.INF
	var p := Vector3(x, TerrainHeight.height_at(x, z), z)
	if avoid_view and cam != null and r < rmax * 0.9 and cam.is_position_in_frustum(p + Vector3(0.0, 1.0, 0.0)):
		return Vector3.INF
	return p


## A world boss of the biome under a point 90-130 m from the hero (tier 1 and up, one at a time).
func try_boss() -> RosterBoss:
	if not _allowed() or live_boss() != null:
		return null
	for t in 10:
		var p := _ring_point(BOSS_RING[0], BOSS_RING[1], false)
		if not p.is_finite():
			continue
		var biome := TerrainBase.biome_at(p.x, p.z, p.y)
		var bid := RosterSpecies.boss_for(biome)
		if bid == &"":
			continue
		var b := spawn_boss(bid, p)
		if b != null:
			return b
	return null


## Places boss `bid` at `pos` (ground, the sea line for the leviathan, aloft for the gunship). Null when the spot does not suit it.
func spawn_boss(bid: StringName, pos: Vector3) -> RosterBoss:
	var spec := RosterSpecies.data(bid)
	if spec.is_empty():
		return null
	var gy := TerrainHeight.height_at(pos.x, pos.z)
	var w := TerrainHeight.water_level_for(pos.x, pos.z, gy)
	var depth := w - gy if w != TerrainHeight.NO_WATER else 0.0
	var at := Vector3(pos.x, gy, pos.z)
	if spec["cls"] == AlienSpecies.WATER:
		if depth < 4.0:
			return null
		at.y = w
	elif spec["cls"] == AlienSpecies.GROUND and (depth > 0.4 or TerrainHeight.slope_at(pos.x, pos.z) > 0.8):
		return null
	var b := world.spawn_one(bid, at, &"", false) as RosterBoss
	if b == null:
		return null
	b.lair = at
	b.leash = float(spec["sight"]) * 2.0
	if spec["cls"] == AlienSpecies.AIR:
		b.alt = 24.0
		b.position.y = gy + 24.0
	bosses_spawned += 1
	seen_ids[bid] = int(seen_ids.get(bid, 0)) + 1
	Game.say("%s ROAMS NEAR" % String(spec["title"]), 2.6)
	return b


func on_died(c: AlienCreature, hero_kill: bool) -> void:
	if not (c is RosterFoe or c is RosterBoss) or not hero_kill:
		return
	kills += 1
	if c is RosterBoss:
		boss_cd = BOSS_EVERY * 0.85


func stats() -> Dictionary:
	return {"kills": kills, "encounters": encounters, "bosses": bosses_spawned, "live": live_count(), "tier": tier(), "last": last.duplicate(), "factions": by_faction.duplicate()}
