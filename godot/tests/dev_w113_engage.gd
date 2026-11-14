extends RefCounted
## DEV PROBE 4: do the 22 new enemy types come at the hero and shoot from 15, 40 and 80 m on open ground (AlienWorld standalone, a fake hero that counts the hits)? Run: tools/test.sh tests/dev_w113_engage.gd
const TIMEOUT_SECONDS := 140.0
const DT := 0.05
const ARENA := Vector3(-1500.0, 0.0, -900.0)
const IDS: Array[StringName] = [&"merc_rifle", &"merc_shotgun", &"merc_rocket", &"merc_medic", &"merc_officer", &"merc_sniper", &"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher",
	&"auth_ghost", &"auth_drone", &"auth_engineer", &"vael_grunt", &"vael_jackal", &"vael_brute", &"vael_hunter", &"vael_elite", &"vael_stalker", &"vael_bloater", &"grid_walker", &"grid_heavy",
	&"shield_bearer", &"jet_elite", &"beam_sniper", &"strider", &"crawler", &"wasp_drone", &"auto_turret", &"plate_brute", &"veil_stalker", &"hiveling"]

class FakeHero extends Node3D:
	var hp := 1.0e6
	var max_hp := 1.0e6
	var velocity := Vector3.ZERO
	var vehicle = null
	var hits := 0
	func damage(amount: float, _from := Vector3.ZERO) -> void:
		hp -= amount
		hits += 1
	func is_dead() -> bool:
		return false

var w: AlienWorld
var hero: FakeHero


func run(host: Node) -> void:
	Sfx.muted = true
	AlienSites.ensure()
	hero = FakeHero.new()
	host.add_child(hero)
	Game.player = hero
	w = AlienWorld.new()
	host.add_child(w)
	w.force_active = true
	w.ambient_enabled = false
	hero.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z), ARENA.z)
	w._hero_prev = Vector3.INF
	w._focus_hero(DT)
	var rows: Array[String] = []
	for id: StringName in IDS:
		if not RosterSpecies.has(id):
			continue
		var line := "PROBE %-14s" % id
		for dist in [15.0, 40.0, 80.0]:
			hero.hits = 0
			var h := hero.global_position
			var c := w.spawn_one(id, Vector3(h.x + dist, 0.0, h.z), &"", true) as AlienCreature
			if c == null:
				line += " | %2d m: no spawn" % int(dist)
				continue
			c.heading = atan2(-(h.x - c.position.x), -(h.z - c.position.z))
			var d0 := c.global_position.distance_to(hero.global_position)
			var first_att := -1.0
			var t := 0.0
			var min_d := d0
			while t < 12.0:
				w.step(DT)
				t += DT
				if is_instance_valid(c):
					min_d = minf(min_d, c.global_position.distance_to(hero.global_position))
					if first_att < 0.0 and c.attacks_done > 0:
						first_att = t
			var att := c.attacks_done if is_instance_valid(c) else -1
			line += " | %2d m: d %4.0f->%4.0f att %2d first %4.1f hits %2d" % [int(dist), d0, min_d, att, first_att, hero.hits]
			if is_instance_valid(c):
				c.die(false)
			for k in 4:
				w.step(DT)
		rows.append(line)
		print(line)
	w.queue_free()
	hero.queue_free()
