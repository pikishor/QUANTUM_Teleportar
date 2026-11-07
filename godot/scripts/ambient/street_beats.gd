class_name StreetBeats
extends RefCounted
## Small street events around the hero (owner round 3: "nothing happens in the street"). Every few seconds one beat runs within 12-38 m of the hero, in front of the camera when it can:
##   argue   two walkers stop, turn to each other and shout; gather  a ring of people stops to watch a street performer's light show; chase  a runner bolts and the bystanders turn to look;
##   honk    a near car sounds its horn and the people beside the road turn their heads.
## They only use what the crowd and the near traffic already have (attend / scare / honk): no node, no allocation per frame, no text on the HUD. `active_near` counts them for the census.

const KINDS: Array[StringName] = [&"argue", &"gather", &"chase", &"honk"]
const MIN_D := 11.0
const MAX_D := 38.0
const EVERY := Vector2(6.0, 11.0)        ## seconds between two beats
const LIFE := Vector2(9.0, 14.0)
const MAX_ACTIVE := 3
const WATCH := 15.0                      ## people within this of a performer stop to watch

var crowd: RefCounted
var traffic: NearTraffic
var rng := RandomNumberGenerator.new()
var enabled := true                      ## tests / the BEFORE render of the life bot switch the street events off
var started := 0                         ## beats started so far (tests)
var by_kind := {}                        ## kind -> started
var active: Array[Dictionary] = []       ## {kind, pos, end, t_fx}
var _next := 3.0
var _clock := 0.0
var _scan := 0.0


func setup(crowd_ref: RefCounted, traffic_ref: NearTraffic) -> void:
	crowd = crowd_ref
	traffic = traffic_ref
	rng.seed = 5150
	reset()


func reset() -> void:
	active.clear()
	_next = 2.5
	_clock = 0.0


## Beats that are running within `r` of `pos` (flat).
func active_near(pos: Vector3, r: float) -> int:
	var n := 0
	for b in active:
		var d: Vector3 = b["pos"] - pos
		if d.x * d.x + d.z * d.z <= r * r:
			n += 1
	return n


func step(delta: float, center: Vector3) -> void:
	if not enabled:
		return
	_clock += delta
	var k := active.size() - 1
	while k >= 0:
		var b := active[k]
		if _clock >= float(b["end"]):
			active.remove_at(k)
		elif b["kind"] == &"gather" and _clock >= float(b["t_fx"]):
			b["t_fx"] = _clock + 1.1
			var c := Color(0.35, 0.95, 1.0) if int(_clock) % 2 == 0 else Color(1.0, 0.4, 0.85)
			if Game.quiet > 3.0:                                      # no light show while a fight is on (its particles pile onto the fight's: perf death spike)
				FX.burst((b["pos"] as Vector3) + Vector3(0.0, 1.0, 0.0), c, 8, 3.0, 0.8, -0.6, 1.0)
		k -= 1
	_next -= delta
	if _next > 1.0 and active_near(center, MAX_D) == 0:                # something is always going on within 40 m
		_next = 1.0
	if _next > 0.0 or active.size() >= MAX_ACTIVE:
		return
	if active_near(center, MAX_D + 6.0) >= 2:
		_next = rng.randf_range(EVERY.x, EVERY.y)
		return
	var ok := _start(center)
	_next = rng.randf_range(EVERY.x, EVERY.y) if ok else 1.0


func _candidates(center: Vector3) -> Array[int]:
	var out: Array[int] = []
	var fwd := Vector2.ZERO
	if is_instance_valid(Game.camera):
		var cf := -Game.camera.global_transform.basis.z
		fwd = Vector2(cf.x, cf.z).normalized() if Vector2(cf.x, cf.z).length_squared() > 0.04 else Vector2.ZERO
	for pass_i in 2:
		for i in crowd.count:
			if not crowd.is_alive(i) or crowd.is_pinned(i) or crowd.is_hidden(i):
				continue
			var st: StringName = crowd.state_of(i)
			if st != &"walk" and st != &"idle":
				continue
			var p: Vector3 = crowd.person_position(i)
			var d := Vector2(p.x - center.x, p.z - center.z)
			var l := d.length()
			if l < MIN_D or l > MAX_D:
				continue
			if pass_i == 0 and fwd != Vector2.ZERO and d.normalized().dot(fwd) < 0.2:
				continue                                           # first look in front of the camera
			out.append(i)
		if out.size() >= 3:
			break
	return out


## Start one beat now (`force` picks the kind, for tests). False when nobody is in range.
func start(center: Vector3, force: StringName = &"") -> bool:
	return _start(center, force)


func _start(center: Vector3, force: StringName = &"") -> bool:
	var cand := _candidates(center)
	if cand.is_empty():
		return false
	var kind := KINDS[rng.randi() % KINDS.size()]
	if force != &"":
		kind = force
	elif by_kind.get(kind, 0) > 0 and rng.randf() < 0.35:                 # a little variety: prefer the kind that has run least
		var least := kind
		for kk in KINDS:
			if by_kind.get(kk, 0) < by_kind.get(least, 0):
				least = kk
		kind = least
	var a: int = cand[rng.randi() % cand.size()]
	var pa: Vector3 = crowd.person_position(a)
	var life := rng.randf_range(LIFE.x, LIFE.y)
	match kind:
		&"argue":
			var b := -1
			var bd := 9.0
			for j in crowd.count:
				if j != a and crowd.is_alive(j) and not crowd.is_pinned(j) and crowd.state_of(j) == &"walk":
					var d: float = (crowd.person_position(j) - pa).length()
					if d < bd:
						bd = d
						b = j
			if b < 0:
				kind = &"gather"
			else:
				var pb: Vector3 = crowd.person_position(b)
				crowd.attend(a, pb, life)
				crowd.attend(b, pa, life)
				_bark(a)
				_bark(b)
		&"honk":
			var ci := -1
			var best := 1.0e9
			if traffic != null:
				for c in traffic.count:
					if traffic.car_alive(c) and traffic.car_speed(c) > 3.0:
						var cp := traffic.car_position(c)
						var cd := Vector2(cp.x - center.x, cp.z - center.z).length()
						if cd > MIN_D and cd < MAX_D and cd < best:
							best = cd
							ci = c
			if ci < 0:
				kind = &"gather"
			else:
				var cpos := traffic.car_position(ci)
				traffic.honk(ci)
				pa = cpos
				life = 4.0
				for j in crowd.count:
					if crowd.is_alive(j) and not crowd.is_pinned(j) and crowd.state_of(j) == &"walk" and (crowd.person_position(j) - cpos).length() < 14.0:
						crowd.attend(j, cpos, 2.5)
		&"chase":
			var from := pa + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 3.0
			crowd.scare_person(a, from)
			life = 6.0
			for j in crowd.count:
				if j != a and crowd.is_alive(j) and not crowd.is_pinned(j) and crowd.state_of(j) == &"walk" and (crowd.person_position(j) - pa).length() < 10.0:
					crowd.attend(j, pa, 3.0)
			_bark(a)
	if kind == &"gather":
		var n := 0
		for j in crowd.count:
			if n >= 7:
				break
			if crowd.is_alive(j) and not crowd.is_pinned(j) and not crowd.is_hidden(j) and (crowd.state_of(j) == &"walk" or crowd.state_of(j) == &"idle"):
				if (crowd.person_position(j) - pa).length() < WATCH:
					crowd.attend(j, pa + Vector3(0.0, 0.0, 0.0), life)
					n += 1
		if Game.quiet > 3.0:
			FX.burst(pa + Vector3(0.0, 1.0, 0.0), Color(0.35, 0.95, 1.0), 10, 3.0, 0.8, -0.6, 1.0)
	active.append({"kind": kind, "pos": pa, "end": _clock + life, "t_fx": _clock + 1.1})
	started += 1
	by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	return true


func _bark(i: int) -> void:
	Sfx.bark(&"chitter" if i % 2 == 0 else &"growl", crowd.person_position(i), 0.85 + 0.3 * float((i * 7919) % 100) / 100.0, -8.0)
