class_name RosterFire
extends RefCounted
## The slow, readable explosives of the roster-2 enemies (wave 108): rockets, grenades, mortar shells and missile salvos. Every one shows a RING on the ground as wide as its blast for the whole flight
## (and the fuse), flies as a glowing sprite along an arc, and explodes through `Game.explode` (enemy_dmg 0: the hero and his cars are hurt, other enemies are not). The ring is the telegraph: the hero
## walks out of it. Plain bullets are `AlienWorld.shoot`. At most SLOTS live at once (the oldest explodes early when a new one is asked for); the sprites use AlienFx slots FIRST.. FIRST + SLOTS - 1.
##   shell(from, to, flight, radius, dmg, color, ...)   an arc to `to`, `fuse` seconds of rest, then the blast
##   rocket(from, to, speed, radius, dmg, color, ...)   a straight (slightly arched) flight at `speed`, the blast on arrival
##   explosions  count of blasts so far,  hero_hits  blasts that reached the hero (tests and balance)

const FIRST := 22
const SLOTS := 8

var world: AlienWorld
var live: Array[Dictionary] = []
var explosions := 0
var hero_hits := 0
var launched := 0


func _init(w: AlienWorld) -> void:
	world = w
	for i in SLOTS:
		live.append({"on": false})


func active() -> int:
	var n := 0
	for s in live:
		if bool(s["on"]):
			n += 1
	return n


func clear() -> void:
	for i in SLOTS:
		if bool(live[i]["on"]) and world != null and world.fx != null:
			world.fx.sprite_off(FIRST + i)
		live[i]["on"] = false


func _slot() -> int:
	for i in SLOTS:
		if not bool(live[i]["on"]):
			return i
	var oldest := 0
	var best := -1.0
	for i in SLOTS:
		var age := float(live[i]["age"])
		if age > best:
			best = age
			oldest = i
	_blast(oldest)                                              # the oldest goes off early: never more than SLOTS rings
	return oldest


## An arched shell from `from` to the ground point `to`: `flight` seconds in the air, then `fuse` seconds on the ground, then the blast of `radius` and `dmg` on the hero.
func shell(from: Vector3, to: Vector3, flight: float, radius: float, dmg: float, color: Color, size := 0.7, fuse := 0.0, arc := 0.3, owner: Object = null) -> bool:
	if world == null or world.fx == null:
		return false
	var i := _slot()
	var g := Vector3(to.x, TerrainHeight.height_at(to.x, to.z) + 0.08, to.z)
	live[i] = {"on": true, "from": from, "to": g, "t": 0.0, "flight": maxf(flight, 0.2), "fuse": fuse, "r": radius, "dmg": dmg, "col": color, "size": size, "arc": arc, "age": 0.0, "owner": owner}
	world.fx.ring(g, radius, maxf(flight, 0.2) + fuse, color)
	launched += 1
	return true


## A rocket: straight at `speed` toward `to` (a ground point), with a small arch; explodes when it arrives.
func rocket(from: Vector3, to: Vector3, speed: float, radius: float, dmg: float, color: Color, size := 0.8, owner: Object = null) -> bool:
	var dist := from.distance_to(to)
	return shell(from, to, dist / maxf(speed, 1.0), radius, dmg, color, size, 0.0, 0.05, owner)


func tick(dt: float) -> void:
	for i in SLOTS:
		var s: Dictionary = live[i]
		if not bool(s["on"]):
			continue
		s["age"] = float(s["age"]) + dt
		var t := float(s["t"]) + dt
		s["t"] = t
		var flight := float(s["flight"])
		var a: Vector3 = s["from"]
		var b: Vector3 = s["to"]
		if t < flight:
			var k := t / flight
			var p := a.lerp(b, k)
			p.y += (a.distance_to(b)) * float(s["arc"]) * 4.0 * k * (1.0 - k)
			world.fx.sprite(FIRST + i, p, float(s["size"]), s["col"])
		else:
			world.fx.sprite(FIRST + i, b + Vector3(0.0, 0.25, 0.0), float(s["size"]) * (1.0 + 0.25 * sin(t * 24.0)), s["col"])
			if t >= flight + float(s["fuse"]):
				_blast(i)


func _blast(i: int) -> void:
	var s: Dictionary = live[i]
	if not bool(s["on"]):
		return
	s["on"] = false
	world.fx.sprite_off(FIRST + i)
	var at: Vector3 = s["to"]
	var r := float(s["r"])
	var col: Color = s["col"]
	explosions += 1
	var hp := world.hero_pos
	if world.hero_alive() and hp.is_finite() and Vector3(hp.x, at.y, hp.z).distance_to(at) < r + 0.4:
		hero_hits += 1
	Game.explode(at + Vector3(0.0, 0.2, 0.0), r, {"enemy_dmg": 0.0, "car_dmg": 25.0, "player_dmg": float(s["dmg"]), "color": col})
