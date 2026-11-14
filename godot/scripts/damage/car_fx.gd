class_name CarFx
extends RefCounted
## DAMAGE ON CARS (wave 113), on top of the Cars v2 damage states of wave 111 (dents, cracked glass, torn parts, lost wheels, fire in the bay):
##   bullets      every round that lands on a car leaves a BULLET HOLE (a dark pit with a bright burr and a scorch halo on the paint, a clear hole with a star of cracks on glass), kept per car (8, 4 on LOW):
##                the shader draws them (CarV2.add_hole), no node and no mesh; a burst of rounds at the windscreen cracks it in stages (30 %, 55 %, 85 %) and then shatters it
##   tyres        a round that lands low next to a wheel flattens that tyre (the underside sags, the car limps: Vehicle.tires_flat) until it is repaired
##   hood         below 40 % of the hull the hood pops open on its hinge (smoke and flames come out of the bay), a torn-off hood stays gone
##   blasts       a blast sprays shrapnel holes into the flank that faces it and cracks the glass; a car that is hit hard throws a few burning bits
##   wrecks       an exploded car stays where it is as a burning husk: flames and smoke from the bay for 25 s (the oldest fire goes out when more burn than the tier allows), a thin smoke for a minute more;
##                the fire spreads: a car or a wooden prop within 4 m catches fire after a few seconds (fuses, never more than the tier's `fires`)
## Pooled: holes are shader uniforms, the flames and smoke are puffs of the shared cloud (BlastFx), flying bits are pieces of the shared debris pool (Breakables.fling).

const WRECK_FIRE := 25.0
const WRECK_SMOULDER := 80.0
const HOOD_TIME := 0.5
const SPREAD_R := 4.0
const SPREAD_EVERY := 2.0
const WOOD := [&"bench", &"crate", &"stall"]

var world: Node
var _marked: Array[int] = []                       ## cars that carry bullet holes, oldest first
var _glass_hits: Dictionary = {}                   ## car id -> rounds that landed on its glass
var _flat: Dictionary = {}                         ## car id -> bit mask of the flat tyres drawn
var _hood: Dictionary = {}                         ## car id -> 0..1 how far the hood stands open
var _wrecks: Array[Dictionary] = []                ## {car, t0, spread_t}
var _hooked: Dictionary = {}                       ## car id -> true (the exploded signal is connected)
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var holes_made := 0
var hoods_popped := 0
var tyres_shot := 0
var shatters := 0
var spread_fires := 0


func _init(w: Node) -> void:
	world = w
	_rng.randomize()


func reset() -> void:
	_marked.clear()
	_glass_hits.clear()
	_flat.clear()
	_hood.clear()
	_wrecks.clear()


func _now() -> float:
	return _clock


func _v2(car: Node) -> CarV2:
	var vis: Variant = car.get(&"visual")
	return (vis as VehicleVisual).v2 if vis is VehicleVisual else null


func _near_camera(p: Vector3, d: float) -> bool:
	var cam := Game.get_tree().root.get_camera_3d()
	return cam == null or cam.global_position.distance_to(p) < d


# --- bullets -----------------------------------------------------------------------------------------------------------------

## Which part of a car a point in the car's own frame is on: &"glass", &"hood", &"tyre" (with the wheel index), &"sill" or &"body".
func zone_at(car: Vehicle, lp: Vector3, n := Vector3.ZERO) -> Dictionary:
	var ln := float(car.spec["len"])
	var hg := float(car.spec["hgt"])
	var fz := lp.z / maxf(ln, 0.1)
	var vis: VehicleVisual = car.visual
	if lp.y < 0.62 and vis != null:
		var best := -1
		var bd := 0.6
		for i in vis.wheels.size():
			var wp := car.to_local(vis.wheels[i].global_position)
			var d := Vector2(wp.x - lp.x, wp.z - lp.z).length()
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			return {"zone": &"tyre", "wheel": best}
		return {"zone": &"sill", "wheel": -1}
	if lp.y > hg * 0.62 and absf(fz) < 0.3:
		if n.y > 0.7:
			return {"zone": &"roof", "wheel": -1}                      # the roof is paint, not glass
		return {"zone": &"glass", "wheel": -1}
	if fz < -0.2 and lp.y > hg * 0.38:
		return {"zone": &"hood", "wheel": -1}
	return {"zone": &"body", "wheel": -1}


## Where a round meets the BODY of the car: the physics hull is a box much bigger than the car, so a round is followed on from the hull hit through a simple model of the body (a low box and a
## narrower cabin box, from the spec's length, width and height). Returns {p, n, t} in the car's frame, {} when the round passes through the air round the car (a visual miss).
func surface_hit(car: Vehicle, from_local: Vector3, dir_local: Vector3) -> Dictionary:
	var ln := float(car.spec["len"])
	var wd := float(car.spec["wid"])
	var hg := float(car.spec["hgt"])
	var hb := hg * 0.6
	var boxes: Array = [
		[Vector3(-wd * 0.5, 0.2, -ln * 0.5), Vector3(wd * 0.5, hb, ln * 0.5)],
		[Vector3(-wd * 0.43, hb, -ln * 0.2), Vector3(wd * 0.43, hg, ln * 0.3)],
	]
	var best := INF
	var bn := Vector3.UP
	for bx: Array in boxes:
		var lo: Vector3 = bx[0]
		var hi: Vector3 = bx[1]
		var tmin := 0.0
		var tmax := 3.5
		var nrm := Vector3.ZERO
		var ok := true
		for axis in 3:
			var o := from_local[axis]
			var d := dir_local[axis]
			if absf(d) < 1.0e-6:
				if o < lo[axis] or o > hi[axis]:
					ok = false
					break
				continue
			var t1 := (lo[axis] - o) / d
			var t2 := (hi[axis] - o) / d
			var face := -1.0
			if t1 > t2:
				var tt := t1
				t1 = t2
				t2 = tt
				face = 1.0
			if t1 > tmin:
				tmin = t1
				nrm = Vector3.ZERO
				nrm[axis] = face
			tmax = minf(tmax, t2)
			if tmin > tmax:
				ok = false
				break
		if ok and tmin < best and nrm != Vector3.ZERO:
			best = tmin
			bn = nrm
	if best == INF:
		return {}
	return {"p": from_local + dir_local * best, "n": bn, "t": best}


## A round of the hero landed on `car` (PlayerWeapon.last_shot `ls`): a hole where it went in, the glass cracks, a tyre goes flat.
func on_bullet(car: Vehicle, ls: Dictionary, wdef: Dictionary) -> void:
	if not Dmg.enabled or not is_instance_valid(car) or car.dead or car.wreck:
		return
	var v2 := _v2(car)
	if v2 == null:
		return
	var hit: Vector3 = ls.get("hit", car.global_position + Vector3(0.0, 0.8, 0.0))
	if not _near_camera(hit, 90.0):
		return
	var dir: Vector3 = ls.get("dir", Vector3.ZERO)
	var basis_inv := car.global_transform.basis.inverse()
	var dl := basis_inv * dir
	var lp := car.to_local(hit)
	var wid := float(car.spec["wid"])
	var ln := float(car.spec["len"])
	var hg := float(car.spec["hgt"])
	var sn := Vector3.ZERO
	if dl.length() > 0.1:
		dl = dl.normalized()
		var sh := surface_hit(car, lp - dl * 0.25, dl)                            # follow the round from the hull on to the body
		if sh.is_empty():
			return                                                              # it went through the air above the hood: no hole
		lp = sh["p"]
		sn = sh["n"]
	var z := zone_at(car, lp, sn)
	var zone: StringName = z["zone"]
	# the axis of the round, pointing back at the shooter (car frame): the hole is drawn on the paint along that line
	var nl := -dl if dl.length() > 0.1 else Vector3(signf(lp.x), 0.3, 0.0)
	nl = nl.normalized()
	var dmg := float(wdef.get("damage", 20.0))
	var radius := clampf(0.075 + dmg / 800.0, 0.085, 0.15)            # stylised: a hole is readable from ten metres
	var id := car.get_instance_id()
	var cap := Dmg.cap(&"car_holes")
	if v2.holes.size() >= cap:
		v2.holes.remove_at(0)
	if v2.add_hole(lp, nl, radius):
		holes_made += 1
		Dmg.bump(&"car_hole")
		_mark(car)
	match zone:
		&"glass":
			var g := int(_glass_hits.get(id, 0)) + 1
			_glass_hits[id] = g
			var level: float = [0.0, 0.0, 0.3, 0.3, 0.55, 0.55, 0.85, 1.0][mini(g, 8) - 1]     # the first rounds only star the pane at the hole (the shader), then the whole pane cracks in stages
			if level > 0.0:
				car.visual.crack_glass(level, lp)
			if g >= 9 and v2.cracks >= 0.99 and not v2.glass_shattered:
				shatter_glass(car)
		&"tyre":
			flatten(car, int(z["wheel"]))


## Mark the car as holding holes; the oldest marked cars lose theirs when more cars carry them than the tier allows.
func _mark(car: Vehicle) -> void:
	var id := car.get_instance_id()
	if not _marked.has(id):
		_marked.append(id)
	while _marked.size() > Dmg.cap(&"cars_marked"):
		var old := _marked.pop_front() as int
		var oc := instance_from_id(old) as Vehicle
		if oc != null and is_instance_valid(oc) and not oc.driver_is_player:
			var ov := _v2(oc)
			if ov != null:
				ov.holes.clear()
				ov._push_holes()


## The windscreen goes: the pane is almost clear, a handful of glass pieces fly out.
func shatter_glass(car: Vehicle) -> void:
	var v2 := _v2(car)
	if v2 == null or v2.glass_shattered:
		return
	v2.shatter_glass()
	shatters += 1
	Dmg.bump(&"glass_shatter")
	var br := Breakables.current
	if br != null:
		var hg := float(car.spec["hgt"])
		var ln := float(car.spec["len"])
		var base := car.to_global(Vector3(0.0, hg * 0.78, -ln * 0.09))
		for i in clampi(4 + Dmg.tier() * 3, 4, 10):
			br.fling(base + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.1, 0.2), 0.0), car.vel * 0.4 + Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(1.0, 3.5), _rng.randf_range(-3.0, 0.5)), Color(0.75, 0.9, 1.0), _rng.randf_range(0.06, 0.14), Vector3(1.0, 0.15, _rng.randf_range(0.5, 0.9)), 2.0)
	Sfx.impact(&"glass", car.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)


## A tyre goes flat: the car limps (Vehicle.tires_flat), the tyre sags on the visual.
func flatten(car: Vehicle, wheel: int) -> void:
	var v2 := _v2(car)
	if v2 == null or wheel < 0 or wheel > 3 or (v2.wheels_flat & (1 << wheel)) != 0:
		return
	v2.set_wheel_flat(wheel, true)
	_flat[car.get_instance_id()] = v2.wheels_flat
	car.tires_flat = maxf(car.tires_flat, VehicleSpecs.TIRES_TIME * 8.0)
	tyres_shot += 1
	Dmg.bump(&"tyre")
	var p := car.global_position + Vector3(0.0, 0.3, 0.0)
	if is_instance_valid(car.visual) and wheel < car.visual.wheels.size():
		p = car.visual.wheels[wheel].global_position
	Sfx.play_at(&"impact_metal", p, -6.0, 0.6)
	var bf := BlastFx.instance
	if is_instance_valid(bf):
		bf.puff(p, Vector3(0.0, 0.6, 0.0), 0.3, 1.0, 0.7, Color(0.7, 0.68, 0.64, 0.45), BlastFx.K_SMOKE, 0.0, 1.5)


# --- blasts ------------------------------------------------------------------------------------------------------------------

## `car` took part of a blast at `pos` (share `f` of the centre value 0..1): shrapnel holes in the flank that faces it, the glass cracks.
func on_blast(car: Vehicle, pos: Vector3, f: float) -> void:
	if not Dmg.enabled or not is_instance_valid(car) or car.dead or car.wreck or f < 0.15:
		return
	var v2 := _v2(car)
	if v2 == null or not _near_camera(car.global_position, 100.0):
		return
	var wid := float(car.spec["wid"])
	var ln := float(car.spec["len"])
	var hg := float(car.spec["hgt"])
	var toward := car.to_local(pos)
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
	var n := clampi(int(f * 6.0) + 1, 1, 4)
	var along_x := absf(toward.x) > absf(toward.z)
	for i in n:
		var lp: Vector3
		var nl: Vector3
		if along_x:
			lp = Vector3(signf(toward.x) * wid * 0.5, _rng.randf_range(0.3, 0.58) * hg, _rng.randf_range(-0.4, 0.4) * ln)
			nl = Vector3(signf(toward.x), 0.0, 0.0)
		else:
			lp = Vector3(_rng.randf_range(-0.4, 0.4) * wid, _rng.randf_range(0.3, 0.58) * hg, signf(toward.z) * ln * 0.5)
			nl = Vector3(0.0, 0.0, signf(toward.z))
		if v2.holes.size() >= Dmg.cap(&"car_holes"):
			v2.holes.remove_at(0)
		if v2.add_hole(lp, nl, _rng.randf_range(0.07, 0.11)):
			holes_made += 1
			Dmg.bump(&"car_hole")
	_mark(car)
	if f > 0.3:
		var vis: VehicleVisual = car.visual
		vis.set_damage_look(maxf(vis.damage_look, clampf(f * 0.75, 0.0, 0.9)))       # scorched paint: the soot of the blast stays on the car
	if f > 0.35:
		car.visual.crack_glass(clampf(f * 1.4, 0.3, 1.0), car.to_local(pos))
		if f > 0.7 and v2.cracks >= 0.99:
			shatter_glass(car)
	if f > 0.5:
		_burning_bits(car, pos)


## A few dark, glowing bits thrown from a hurt car.
func _burning_bits(car: Vehicle, from: Vector3) -> void:
	var br := Breakables.current
	if br == null:
		return
	var away := car.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(0.0, 0.0, 1.0)
	for i in clampi(2 + Dmg.tier() * 2, 2, 6):
		br.fling(car.global_position + Vector3(0.0, 0.8, 0.0), away * _rng.randf_range(2.0, 6.0) + Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(3.0, 7.0), _rng.randf_range(-2.0, 2.0)), Color(0.12, 0.1, 0.09).lerp(Color(0.7, 0.3, 0.1), _rng.randf() * 0.35), _rng.randf_range(0.1, 0.24), Vector3(1.0, _rng.randf_range(0.3, 0.9), _rng.randf_range(0.5, 1.0)), 2.6)


# --- ticking -----------------------------------------------------------------------------------------------------------------

## 10 Hz: the hood of the hurt cars, flat tyres that recovered, the fires of the wrecks.
func tick(dt: float) -> void:
	_clock += dt
	var tree := Game.get_tree()
	var cam := tree.root.get_camera_3d()
	var now := _now()
	for n: Node in tree.get_nodes_in_group(&"vehicle"):
		var car := n as Vehicle
		if car == null or car.wreck or not car.active:
			continue
		if not _hooked.has(car.get_instance_id()):
			_hooked[car.get_instance_id()] = true
			if not car.exploded.is_connected(_on_exploded):
				car.exploded.connect(_on_exploded)
			if _hooked.size() > 300:
				_hooked.clear()
		if cam == null or cam.global_position.distance_to(car.global_position) > 80.0:
			continue
		var v2 := _v2(car)
		if v2 == null:
			continue
		var id := car.get_instance_id()
		# the hood: stage 2 (smoke) and 3 (fire) open it
		var want := 1.0 if car.damage_stage() >= 2 else 0.0
		var cur := float(_hood.get(id, 0.0))
		if want > cur or (want < cur and car.hp >= car.max_hp * 0.99):
			var nxt := move_toward(cur, want, dt / HOOD_TIME)
			if absf(nxt - cur) > 0.001 and v2.set_hood_pop(nxt):
				_hood[id] = nxt
				if cur < 0.01 and nxt > 0.0:
					hoods_popped += 1
					Dmg.bump(&"hood")
		# flat tyres that healed
		if int(_flat.get(id, 0)) != 0 and car.tires_flat <= 0.0:
			for k in 4:
				v2.set_wheel_flat(k, false)
			_flat.erase(id)
	_tick_wrecks(dt, now, cam)


func _on_exploded(car: Vehicle) -> void:
	if not Dmg.enabled or not is_instance_valid(car):
		return
	_wrecks.append({"car": car, "t0": _now(), "spread_t": SPREAD_EVERY, "fx_t": 0.0})
	if _wrecks.size() > 12:
		_wrecks.pop_front()
	_burning_bits(car, car.global_position + Vector3(0.0, -0.5, 0.0))
	Dmg.bump(&"wreck")


func wrecks_live() -> int:
	return _wrecks.size()


## Flames and smoke from the wrecks nearest to the camera (the tier's cap), the spread of the fire.
func _tick_wrecks(dt: float, now: float, cam: Camera3D) -> void:
	if _wrecks.is_empty():
		return
	var live: Array[Dictionary] = []
	for w in _wrecks:
		if not is_instance_valid(w["car"]):
			continue
		var car := w["car"] as Vehicle
		if not car.wreck or now - float(w["t0"]) > WRECK_SMOULDER:
			continue
		live.append(w)
	_wrecks = live
	if cam == null:
		return
	# the nearest ones burn, the rest only smoulder
	live.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return cam.global_position.distance_squared_to((a["car"] as Vehicle).global_position) < cam.global_position.distance_squared_to((b["car"] as Vehicle).global_position))
	var cap := Dmg.cap(&"burning_wrecks")
	var bf := BlastFx.instance
	for i in live.size():
		var w: Dictionary = live[i]
		var car := w["car"] as Vehicle
		var age := now - float(w["t0"])
		var d := cam.global_position.distance_to(car.global_position)
		var burning := age < WRECK_FIRE and i < cap
		w["burning"] = burning
		w["fx_t"] = float(w["fx_t"]) - dt
		if burning and float(w["spread_t"]) > 0.0:
			w["spread_t"] = float(w["spread_t"]) - dt
			if float(w["spread_t"]) <= 0.0:
				w["spread_t"] = SPREAD_EVERY
				_spread(car)
		if d > 70.0 or not is_instance_valid(bf) or float(w["fx_t"]) > 0.0:
			continue
		var at := car.global_position + Vector3(0.0, float(car.spec["hgt"]) * 0.7, 0.0) + car.forward() * float(car.spec["len"]) * 0.2
		if burning:
			w["fx_t"] = [0.34, 0.24, 0.16][Dmg.tier()]
			bf.puff(at + Vector3(_rng.randf_range(-0.5, 0.5), -0.1, _rng.randf_range(-0.6, 0.6)), Vector3(0.0, 2.6, 0.0), 1.0, 2.3, 0.95, Color(1.0, 0.42, 0.08, 0.95), BlastFx.K_FLAME, 0.85, 0.4, 1.9)
			if _rng.randf() < 0.6:
				bf.puff(at + Vector3(0.0, 0.8, 0.0), Vector3(_rng.randf_range(-0.4, 0.4), 2.0, _rng.randf_range(-0.4, 0.4)), 1.2, 3.6, 2.6, Color(0.09, 0.09, 0.1, 0.75), BlastFx.K_SMOKE, 0.0, 0.5)
		else:
			w["fx_t"] = [1.5, 1.1, 0.8][Dmg.tier()]
			bf.puff(at, Vector3(0.0, 1.2, 0.0), 0.7, 2.2, 3.0, Color(0.2, 0.2, 0.21, 0.4), BlastFx.K_SMOKE, 0.0, 0.4)


## The fire of a wreck reaches a car or a wooden prop within SPREAD_R: it catches fire (a fuse), at most `fires` things burn at once.
func _spread(wreck: Vehicle) -> void:
	var burning := 0
	for w in _wrecks:
		if bool(w.get("burning", false)):
			burning += 1
	var cap := Dmg.cap(&"fires")
	if burning > cap:
		return
	var mgr := wreck.manager as VehicleManager
	if mgr != null:
		for o in mgr.list:
			if o == wreck or o.dead or not o.active or o.wreck or o.fuse >= 0.0:
				continue
			var d := o.global_position.distance_to(wreck.global_position)
			if d <= SPREAD_R and _rng.randf() < 0.35:
				o.ignite(2.5 + d * 0.6 + _rng.randf_range(0.0, 2.0))
				spread_fires += 1
				Dmg.bump(&"fire_spread")
				return
	var br := Breakables.current
	if br != null:
		for i in Breakables.COUNT:
			if br.broken[i] == 1:
				continue
			var nm := StringName(Breakables.KINDS[br.kind_of[i]]["name"])
			if not (nm in WOOD):
				continue
			if br.positions[i].distance_to(wreck.global_position) <= SPREAD_R and _rng.randf() < 0.5:
				br.break_prop(i, Vector3.UP * 2.0)
				spread_fires += 1
				Dmg.bump(&"fire_spread")
				var bf := BlastFx.instance
				if is_instance_valid(bf):
					bf.puff(br.positions[i], Vector3(0.0, 2.0, 0.0), 0.5, 1.4, 1.0, Color(1.0, 0.45, 0.1, 0.9), BlastFx.K_FLAME, 0.8, 0.5, 1.6)
				return
