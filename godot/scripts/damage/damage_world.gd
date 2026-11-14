class_name DamageWorld
extends Node
## DAMAGE EVERYWHERE, the hub (wave 113): one node in the main scene (scripts/main.gd) that owns the damage layers of people (FoeFx) and cars (CarFx), listens to the game and ticks them. It watches and
## reacts, it changes no enemy, car or weapon script:
##   the hero's hits     Player.hit_confirmed + PlayerWeapon.last_shot (target, zone, hit point, direction) -> FoeFx.on_bullet for a person or a machine, CarFx.on_bullet for a car
##   blasts              Game.exploded (the blast is about to hurt everyone: it is remembered for the deaths of this frame) and, one frame later, what the blast did (BlastTable.last) -> FoeFx.on_blast, CarFx.on_blast
##   deaths and statuses the `died` signal of every enemy, hooked by the 10 Hz tick; statuses of BlastOps are read from the blast entry
##   structure           StructureDamage.apply is called by BlastTable itself; this node only clears its memory on a new game
## Idle cost: a 10 Hz tick over the enemies and the cars near the camera, and a per-frame step only while a body is flying. Switch: Dmg.enabled (QT_DMG=0 in the environment).
##   DamageWorld.current   the node (null before the main scene exists)

static var current: DamageWorld = null

var foes: FoeFx
var cars: CarFx
var last_blast: Dictionary = {}          ## {pos, radius, frame, id}: the latest blast, valid for its own physics frame and the next one
var blasts_seen := 0
var hits_seen := 0
var fires_started := 0                   ## things set alight by a fire field (counter for tests)
var civ_effects := 0                     ## element effects on the citizens a blast killed
var _acc := 0.0
var _hooked := false
var _pending_props: Array[Dictionary] = []     ## wooden props the fire is reaching: {i, t}
var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	name = &"DamageWorld"
	foes = FoeFx.new(self)
	cars = CarFx.new(self)
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	Game.next_sector.connect(reset)
	Game.exploded.connect(_on_exploded)
	_rng.randomize()


func reset() -> void:
	_pending_props.clear()
	foes.reset()
	cars.reset()
	StructureDamage.reset()
	last_blast = {}


func _process(delta: float) -> void:
	if not Dmg.enabled:
		return
	if not _hooked:
		_try_hook()
	if foes.flings_live() > 0 or foes.shields_live() > 0:
		foes.step(delta)
	if not _pending_props.is_empty():
		_tick_props(delta)
	_acc += delta
	if _acc >= FoeFx.TICK:
		var dt := _acc
		_acc = 0.0
		if Game.state == &"play" or Game.state == &"dead":
			foes.tick(dt)
			cars.tick(dt)


func _try_hook() -> void:
	var p := Game.player as Player
	if p == null:
		return
	_hooked = true
	if not p.hit_confirmed.is_connected(_on_hit):
		p.hit_confirmed.connect(_on_hit)


## The hero's weapon hit something: a person, a machine, a car, a citizen or an animal (the last two have their own reactions elsewhere).
func _on_hit(kill: bool, crit: bool) -> void:
	if not Dmg.enabled:
		return
	var p := Game.player as Player
	if p == null or p.weapon == null:
		return
	var w: PlayerWeapon = p.weapon
	var ls: Dictionary = w.last_shot
	if ls.is_empty() or Engine.get_physics_frames() - int(ls.get("frame", -100)) > 4:
		return
	var t: Variant = ls.get("target")
	if not (t is Node3D) or not is_instance_valid(t):
		return
	hits_seen += 1
	if t is Vehicle:
		cars.on_bullet(t as Vehicle, ls, w.def)
	elif (t as Node).is_in_group(&"enemy") or (t as Node).has_method(&"center"):
		foes.on_bullet(t as Node3D, ls, crit, kill, w.def)


## The blast is about to hurt everyone (BlastTable emits this before the targets take damage): remember it, look at the result next frame.
func _on_exploded(pos: Vector3, radius: float) -> void:
	if not Dmg.enabled:
		return
	blasts_seen += 1
	last_blast = {"pos": pos, "radius": radius, "frame": Engine.get_physics_frames(), "id": StringName(BlastTable.last.get("id", &""))}
	_after_blast.call_deferred(pos, radius, Engine.get_physics_frames())


## The blast that is already over: what it did to the enemies and the cars around it.
func _after_blast(pos: Vector3, radius: float, frame: int) -> void:
	var entry := BlastTable.entry(StringName(BlastTable.last.get("id", &"")))
	var tree := get_tree()
	if tree == null:
		return
	var reach := radius + 3.0
	for n: Node in tree.get_nodes_in_group(&"enemy"):
		var en := n as Node3D
		if en == null or not is_instance_valid(en) or bool(en.get(&"dead")):
			continue
		var d := en.global_position.distance_to(pos)
		if d <= reach:
			foes.on_blast(en, pos, radius, entry)
	var fire: Variant = entry.get("fire")
	if fire is Dictionary and not (fire as Dictionary).is_empty():
		_fire_area(pos, float((fire as Dictionary).get("radius", 0.0)), tree)
	if int(BlastTable.last.get("civilians_killed", 0)) > 0:
		_civilians(pos, radius, entry)
	var cap_cars := 4
	for v: Node in tree.get_nodes_in_group(&"vehicle"):
		var car := v as Vehicle
		if car == null or not is_instance_valid(car) or car.dead or car.wreck:
			continue
		var d2 := car.global_position.distance_to(pos)
		if d2 <= reach and cap_cars > 0:
			cap_cars -= 1
			var f := BlastTable.factor(entry, d2, 1.5) if not entry.is_empty() else clampf(1.0 - d2 / reach, 0.0, 1.0)
			cars.on_blast(car, pos, f)


## The last blast, when it went off in this physics frame or the one before and `p` is within its reach (a death in the blast): {} otherwise.
func blast_near(p: Vector3) -> Dictionary:
	if last_blast.is_empty():
		return {}
	if Engine.get_physics_frames() - int(last_blast["frame"]) > 2:
		return {}
	if p.distance_to(last_blast["pos"] as Vector3) > float(last_blast["radius"]) + 3.5:
		return {}
	return last_blast


# --- fire fields and the people they burn ---------------------------------------------------------------------------------------------

## A fire field (napalm, thermobaric, meteor, fuel) spreads to what burns inside it: cars catch fire (a fuse: they burn and blow up), wooden props go up in flames after a few seconds. At most `fires` things at once.
func _fire_area(pos: Vector3, radius: float, tree: SceneTree) -> void:
	if radius <= 0.5:
		return
	var left := Dmg.cap(&"fires")
	for v: Node in tree.get_nodes_in_group(&"vehicle"):
		var car := v as Vehicle
		if car == null or car.dead or car.wreck or not car.active or car.fuse >= 0.0 or left <= 0:
			continue
		var d := car.global_position.distance_to(pos)
		if d <= radius + 1.0:
			car.ignite(2.0 + d * 0.35 + _rng.randf_range(0.0, 1.5))
			left -= 1
			fires_started += 1
			Dmg.bump(&"fire_car")
	var br := Breakables.current
	if br == null:
		return
	for i in Breakables.COUNT:
		if left <= 0:
			break
		if br.broken[i] == 1:
			continue
		var nm := StringName(Breakables.KINDS[br.kind_of[i]]["name"])
		if not (nm in CarFx.WOOD):
			continue
		if br.positions[i].distance_to(pos) <= radius:
			_pending_props.append({"i": i, "t": _rng.randf_range(1.2, 3.8)})
			left -= 1
			fires_started += 1
			Dmg.bump(&"fire_prop")


func _tick_props(delta: float) -> void:
	var br := Breakables.current
	var bf := BlastFx.instance
	var i := _pending_props.size() - 1
	while i >= 0:
		var it: Dictionary = _pending_props[i]
		it["t"] = float(it["t"]) - delta
		if br != null and is_instance_valid(bf) and br.broken[int(it["i"])] == 0 and _rng.randf() < 0.3:
			bf.puff(br.positions[int(it["i"])] + Vector3(0.0, 0.5, 0.0), Vector3(0.0, 1.8, 0.0), 0.4, 1.1, 0.7, Color(1.0, 0.45, 0.1, 0.9), BlastFx.K_FLAME, 0.8, 0.5, 1.7)     # it burns before it falls apart
		if float(it["t"]) <= 0.0:
			if br != null and br.broken[int(it["i"])] == 0:
				br.break_prop(int(it["i"]), Vector3.UP * 2.0)
			_pending_props.remove_at(i)
		i -= 1


## The citizens a blast killed go in the manner of the blast: flames, arcs, ice or violet dust (they dissolve in quantum light as before; no gore).
func _civilians(pos: Vector3, radius: float, entry: Dictionary) -> void:
	var city := Game.world as City
	if city == null or city.ambient == null or city.ambient.crowd == null:
		return
	var crowd = city.ambient.crowd
	var el := StringName(entry.get("element", &"fire"))
	var st := StringName((entry.get("status", {}) as Dictionary).get("kind", &""))
	var bf := BlastFx.instance
	var left := Dmg.cap(&"foes_fx")
	for i in int(crowd.count):
		if left <= 0:
			break
		if not crowd.is_dying(i) or float(crowd.death_t(i)) > 0.35:
			continue
		var pp: Vector3 = crowd.person_position(i)
		if pp.distance_to(pos) > radius + 1.5:
			continue
		left -= 1
		civ_effects += 1
		Dmg.bump(&"civ_fx")
		var c := pp + Vector3(0.0, 0.9, 0.0)
		if st == &"freeze":
			if is_instance_valid(bf):
				bf.puff(c, Vector3(0.0, 0.4, 0.0), 0.5, 1.3, 1.0, Color(0.75, 0.92, 1.0, 0.5), BlastFx.K_SMOKE, 0.3, 1.0)
		elif el == &"electric" or st == &"shock":
			if FX.qvfx != null:
				FX.qvfx.bolt(c, c + Vector3(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.8, 0.8)), Color(0.7, 0.9, 1.0))
		elif el == &"quantum" or el == &"plasma":
			if FX.qvfx != null:
				FX.qvfx.death_dust(c, 1.5, 0.4, Color(0.7, 0.4, 1.0) if el == &"quantum" else Color(0.4, 0.95, 1.0))
		elif is_instance_valid(bf):
			bf.puff(c, Vector3(0.0, 1.6, 0.0), 0.4, 1.0, 0.8, Color(1.0, 0.45, 0.1, 0.9), BlastFx.K_FLAME, 0.8, 0.5, 1.7)
			bf.puff(c + Vector3(0.0, 0.4, 0.0), Vector3(0.0, 1.2, 0.0), 0.5, 1.4, 1.4, Color(0.1, 0.1, 0.11, 0.55), BlastFx.K_SMOKE, 0.0, 0.5)
