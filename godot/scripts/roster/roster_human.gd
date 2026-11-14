class_name RosterHuman
extends RefCounted
## The bridge between a RosterFoe (the brain: states, cover, telegraphs, shots, damage) and a FoeHuman body (the skinned, armoured Quaternius human: CharacterRig + Locomotion + HumanoidAnim).
## RosterFoe keeps every rule; this class only turns what it does into the pose of the body:
##   attach(c, look, spec)  builds the body (variant by the creature's id), sets c.model / c.mat / c.hum / c.humanoid_body / c.camp (so the damage system treats it as a person: plates, no fluid)
##   update(c, dt)          once per tick (alive or dying): LOD by camera distance, walk by the real displacement, upper body from the state (idle low ready, aim raised, windup tell, a kick per shot),
##                          flinch on a hit, the fall on death, health pips, telegraph glow, far glow, crouch behind cover
##   on_die / hurt / muzzle / on_wake (the officer's call, the operator's drones, the engineer's turret)
## Death: the rig goes limp (HumanoidAnim) and the body falls over its feet (kind 2 backward when shot from the front, 1 forward from behind, 0 sideways), then AlienCreature's dissolve takes it.

const FALL_TIME := 0.9
const SPECIALS_RANGE := 70.0


static func attach(c: RosterFoe, look: StringName, spec: Dictionary) -> bool:
	if not FoeHuman.available() or not FoeLooks.has(look):
		return false
	var variant := int(absi(int(c.get_instance_id())) % 3)
	var h := FoeHuman.build(look, variant, StringName(spec.get("weapon", &"")))
	if h.is_empty():
		return false
	h["scale3"] = FoeLooks.data(look)["scale"]
	h["state"] = &""
	h["shots"] = 0
	h["hp_seen"] = -1.0
	h["hit_k"] = 0.0
	h["fall"] = 0.0
	h["fall_kind"] = 0
	h["specials"] = false
	c.hum = h
	c.model = h["root"]
	c.add_child(c.model)
	c.mat = h["material"]
	c.mesh = null
	c.humanoid_body = h["body"]
	c.camp = &"merc"
	return true


static func _hero_local(c: RosterFoe) -> Vector2:
	var hp := c.hero_pos()
	if not hp.is_finite():
		return Vector2.ZERO
	var to := Basis(Vector3.UP, c.heading).inverse() * (hp - c.global_position)
	return Vector2(to.x, -to.z)                                   # body space: x right, y forward (the body looks down -Z)


static func update(c: RosterFoe, dt: float) -> void:
	var h := c.hum
	if h.is_empty() or dt <= 0.0:
		return
	var root := h["root"] as Node3D
	var sc: Vector3 = h["scale3"]
	var s := FoeHuman.BASE_SCALE * c.vis
	var squat := 1.0 - 0.3 * c.crouch if not c.dead else 1.0
	root.scale = Vector3(sc.x * s, sc.y * s * squat, sc.z * s)
	var cam := c.get_viewport().get_camera_3d() if c.is_inside_tree() else null
	var dist := cam.global_position.distance_to(c.global_position) if cam != null else 0.0
	FoeHuman.set_lod(h, dist)
	var hit_k := float(h["hit_k"])
	if hit_k > 0.0:
		hit_k = maxf(0.0, hit_k - dt * 8.0)
		h["hit_k"] = hit_k
		FoeHuman.set_hit(h, hit_k)
	if c.dead:
		_dying(c, h, dt)
		return
	if c.downed:
		if StringName(h["state"]) != &"downed":
			h["state"] = &"downed"
			FoeHuman.die(h, 1, 0.8)
		FoeHuman.drive_dead(h, dt)
		var k := clampf(float((h["hanim"] as HumanoidAnim).dead), 0.0, 1.0)
		root.rotation.x = lerpf(root.rotation.x, -1.35 * k, clampf(dt * 8.0, 0.0, 1.0))
		return
	if StringName(h["state"]) == &"downed":                      # a revived medic patient: stand up
		FoeHuman.reset(h)
		h["state"] = &""
		root.rotation.x = 0.0
	var p := c.global_position
	var last: Vector3 = h["_last"]
	var disp := Vector3.ZERO
	if last.is_finite():
		disp = Vector3(p.x - last.x, 0.0, p.z - last.z)
	h["_last"] = p
	var speed := disp.length() / dt
	var st := c.state
	var want: StringName = &"idle"
	if st == &"windup":
		want = &"windup"
	elif st == &"fire" or st == &"recover" or st == &"peek":
		want = &"fire"
	elif c.aggro:
		want = &"aim"
	if want != StringName(h["state"]):
		h["state"] = want
		match want:
			&"windup":
				FoeHuman.windup(h, float(c.spec.get("windup", 0.6)) * c._aggr_k())
			&"idle":
				FoeHuman.aim(h, false)
			_:
				FoeHuman.aim(h, true)
	if int(h["shots"]) != c.attacks_done:
		h["shots"] = c.attacks_done
		FoeHuman.fire(h)
	var want_pitch := 0.0
	var hp3 := c.hero_pos()
	if hp3.is_finite():
		var fd := maxf(c.flat_dist(), 1.0)
		want_pitch = clampf(atan2(hp3.y + 0.9 - (p.y + 1.45), fd) * 0.6, -0.55, 0.65)
	var firing := want == &"fire" or want == &"windup"
	FoeHuman.drive(h, dt, disp, c.rotation.y, 1.0 if speed > 0.4 else 0.0, firing, want_pitch, 0.0)
	var mx := float(c.max_hp)
	var hpk := clampf(c.hp / mx, 0.0, 1.0) if mx > 0.0 else 1.0
	if absf(hpk - float(h["hp_seen"])) > 0.01:
		h["hp_seen"] = hpk
		FoeHuman.set_hp(h, hpk)
	FoeHuman.set_tele(h, c._pulse if st == &"windup" else 0.0)
	var fd2 := c.flat_dist()
	FoeHuman.set_far(h, (0.55 if c.aggro else 0.3) * smoothstep(9.0, 34.0, fd2) if is_finite(fd2) else 0.0)
	if not bool(h["specials"]) and c.aggro:
		h["specials"] = true
		_specials(c)


static func _dying(c: RosterFoe, h: Dictionary, dt: float) -> void:
	FoeHuman.drive_dead(h, dt)
	var root := h["root"] as Node3D
	var k := clampf(c._dead_t / FALL_TIME, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	match int(h["fall_kind"]):
		2:
			root.rotation.x = 1.5 * e
		1:
			root.rotation.x = -1.5 * e
		_:
			root.rotation.z = 1.5 * e * float(h.get("fall_side", 1.0))


static func on_die(c: RosterFoe) -> void:
	var h := c.hum
	if h.is_empty():
		return
	var from := _hero_local(c)
	var kind := 0
	var side := 1.0
	if from != Vector2.ZERO:
		if absf(from.y) > absf(from.x) * 0.8:
			kind = 2 if from.y > 0.0 else 1
		else:
			side = 1.0 if from.x > 0.0 else -1.0
			kind = 0
	if randf() < 0.25:
		kind = randi() % 3
	h["fall_kind"] = kind
	h["fall_side"] = side
	FoeHuman.die(h, kind, 1.0)
	FoeHuman.set_tele(h, 0.0)
	FoeHuman.set_hp(h, 0.0)


static func hurt(c: RosterFoe, amount: float) -> void:
	var h := c.hum
	if h.is_empty() or c.dead:
		return
	var from := _hero_local(c)
	var dir := from.normalized() if from.length() > 0.01 else Vector2(0.0, 1.0)
	var strength := clampf(amount / maxf(c.max_hp, 1.0) * 5.0, 0.35, 1.0)
	FoeHuman.hit(h, dir, strength)
	h["hit_k"] = 1.0
	FoeHuman.set_hit(h, 1.0)


## Model-space muzzle of the weapon in the world.
static func muzzle(c: RosterFoe) -> Vector3:
	var h := c.hum
	var root := h["root"] as Node3D
	return root.global_transform * FoeHuman.muzzle_transform(h).origin


## The first time the creature wakes: the officer calls the contact, the operator launches its drones, the engineer unfolds a turret.
static func on_wake(c: RosterFoe) -> void:
	if c.hum.is_empty():
		return
	if bool(c.spec.get("officer", false)) and c.world != null and c.world.hero_alive():
		Sfx.bark(&"yelp", c.global_position, 0.8, -3.0)
		for m: Node in c.get_tree().get_nodes_in_group(&"alien"):
			var o := m as RosterFoe
			if o != null and o != c and not o.dead and o.faction == c.faction and o.global_position.distance_to(c.global_position) < 30.0:
				o.aggro = true
				o.cool = minf(o.cool, 0.4)


static func _specials(c: RosterFoe) -> void:
	if c.world == null or not c.is_inside_tree():
		return
	var n := int(c.spec.get("drones", 0))
	for i in n:
		var d := c.world.spawn_one(&"wasp_drone", c.global_position + Vector3(cos(float(i) * PI) * 2.5, 0.0, sin(float(i) * PI) * 2.5), c.site, true)
		if d != null:
			d.set_meta(&"owner_foe", c.get_instance_id())
	if bool(c.spec.get("turret", false)):
		var fwd := Basis(Vector3.UP, c.heading) * Vector3(0.0, 0.0, -1.0)
		var t := c.world.spawn_one(&"auto_turret", c.global_position + fwd * 3.0, c.site, true)
		if t != null:
			t.set_meta(&"owner_foe", c.get_instance_id())
			FX.burst(t.global_position + Vector3(0.0, 0.8, 0.0), Color(1.0, 0.8, 0.2), 10, 4.0, 0.5, 0.0, 1.5)
