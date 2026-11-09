class_name RosterWeak
extends RefCounted
## The weak points of a roster-2 enemy (wave 108), shared by RosterFoe and RosterBoss. A weak point is a hit sphere in model space (RosterSpecies `weak`) that WINS over the body sphere it overlaps when
## a ray meets it from the right side (`from`: any | back | front; `need`: a plate that must be gone first), pays `mult` x damage and, when it has a `comp` (component) hp, wears down on its own and
## breaks with an effect (`fx`: ground = the jetpack dies and the elite crashes, crash = a drone falls, stun = a beam sniper's lens goes dark, knee / crystal / engine = boss parts) through the owner's
## `_part_broken(idx, id, fx)`. The weapon asks `hit_ray` and then calls `damage`; `take()` hands the weak point of that very ray to `damage` (a blast has none). The shots that reach a weak point
## carry `crit = true` (HitZones.HEAD) so the weapon's crit number applies as well; a component also lets 35 % of every hit through to the body (LEAK) so a part is never wasted.

const LEAK := 0.35
const FRESH := 0.15                       ## seconds a ray result stays valid for the damage call that follows it

var c: AlienCreature
var defs: Array = []
var hp := PackedFloat32Array()
var alive: Array[bool] = []
var last_idx := -1
var last_t := -10.0
var ray_t := -10.0
var plates_left := Callable()             ## (side) -> bool: is that plate still standing (RosterFoe.plate_up), empty for none
var hits := 0                             ## weak-point hits (tests)


func _init(creature: AlienCreature) -> void:
	c = creature
	defs = (creature.spec.get("weak", []) as Array)
	for d: Dictionary in defs:
		hp.append(float(d.get("comp", 0.0)) * Difficulty.mult("hp"))
		alive.append(true)


static func now() -> float:
	return Time.get_ticks_msec() * 0.001


func parts_alive() -> int:
	var n := 0
	for a in alive:
		if a:
			n += 1
	return n


func index_of(id: StringName) -> int:
	for i in defs.size():
		if StringName((defs[i] as Dictionary)["id"]) == id:
			return i
	return -1


func part_alive(id: StringName) -> bool:
	var i := index_of(id)
	return i >= 0 and alive[i]


## Is weak point `i` open to a ray travelling along `d` (world space)?
func exposed(i: int, d: Vector3) -> bool:
	if i < 0 or i >= defs.size() or not alive[i]:
		return false
	var def: Dictionary = defs[i]
	var need := StringName(def.get("need", &""))
	if need != &"" and plates_left.is_valid() and bool(plates_left.call(need)):
		return false
	var from := StringName(def.get("from", &"any"))
	if from == &"any":
		return true
	var dl := Basis(Vector3.UP, -c.heading) * d
	if from == &"back":
		return dl.z < 0.35                                    # a shot from the sides or behind
	return dl.z > -0.1                                        # `front`: a shot from ahead


## The nearest hit of a ray on the body shapes and the open weak points: {t, zone, point} or {}.
func hit_ray(o: Vector3, d: Vector3) -> Dictionary:
	if c.dead or not c.active or not c.exposed:
		return {}
	var best := INF
	var zone: StringName = HitZones.BODY
	var wi := -1
	for s: Array in c.shapes:
		var k := int(s[3]) if s.size() > 3 else -1
		var pos := c.global_position + c._to_world(s[0] as Vector3)
		var r := float(s[1]) * c.vis
		var t := PlayerUtil.ray_sphere(o, d, pos, r)
		if t == INF:
			continue
		if k >= 0:
			if not exposed(k, d):
				continue
			t -= r * 0.6                                      # a weak point wins over the body it overlaps
		if t < best:
			best = t
			zone = HitZones.HEAD if bool(s[2]) else HitZones.BODY
			wi = k
	if best == INF:
		return {}
	var t_now := now()
	ray_t = t_now
	last_idx = wi
	last_t = t_now
	best = maxf(best, 0.0)
	return {"t": best, "zone": zone, "point": o + d * best}


## True when the damage call in progress follows a ray (a bullet), false for a blast, melee or burn.
func from_ray() -> bool:
	return now() - ray_t < FRESH


## The weak point of the ray that is being resolved (consumed), -1 for none.
func take() -> int:
	var i := -1
	if now() - last_t < FRESH:
		i = last_idx
	last_idx = -1
	last_t = -10.0
	return i


## Damage `amount` (already scaled by the weapon) on weak point `i`: returns what reaches the body hp.
func damage_part(i: int, amount: float) -> float:
	var def: Dictionary = defs[i]
	hits += 1
	var scaled := amount * float(def.get("mult", 1.0))
	if hp[i] <= 0.0:
		return scaled                                         # no component: the multiplier is the whole effect
	hp[i] -= scaled
	if hp[i] <= 0.0:
		alive[i] = false
		if c.has_method(&"_part_broken"):
			c.call(&"_part_broken", i, StringName(def["id"]), StringName(def.get("fx", &"")))
	return scaled * LEAK
