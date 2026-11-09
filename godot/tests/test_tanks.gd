extends RefCounted
## Wave 108 (owner: "tanks and heavy vehicles"): the armoured family on the tracked physics of VehicleCraft: BATTLE TANK (cannon + coaxial machine gun), LIGHT TANK (fast, light cannon + coax), ARMOURED CARRIER
## (six seats, autocannon, the fastest), MOBILE ARTILLERY (a howitzer whose shell lands on the crosshair, the gun elevates high), ANTI-AIR TANK (flak that bursts at the aim point, seeker missiles). Each has a procedural body
## with a Turret node and a Gun node, a picture, a name, an engine, a mounted weapon and a spawn point at the army depot; handling (they turn on the spot, accelerate by their own numbers), the turret slews and the
## gun elevates, and destruction: a destroyed tank throws its turret off (TankWreck) and gets it back when recycled. The aircraft weapons and the naval gun turrets of earlier waves are checked as data.
## Run: tools/test.sh tests/test_tanks.gd

const DT := 1.0 / 60.0
const KINDS: Array[StringName] = [&"tank", &"ltank", &"apc", &"artillery", &"aatank"]
const BRANDS: Array[String] = ["ABRAMS", "LEOPARD", "T-90", "T90", "BRADLEY", "PANZER", "SHERMAN", "TIGER", "PALADIN", "STRYKER", "GEPARD", "BUFFALO", "CHALLENGER", "MERKAVA"]

class Target extends StaticBody3D:
	var hp := 5000.0
	var taken := 0.0

	func _ready() -> void:
		add_to_group(&"vehicle")
		collision_layer = Game.L_VEHICLE
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 3.0, 8.0)
		cs.shape = box
		cs.position = Vector3(0.0, 1.5, 0.0)
		add_child(cs)

	func damage(amount: float) -> void:
		taken += amount
		hp -= amount


var _host: Node
var _blasts: Array[Dictionary] = []


func run(host: Node) -> void:
	_host = host
	Sfx.muted = true
	Game.state = &"play"
	Game.exploded.connect(func(pos: Vector3, radius: float) -> void: _blasts.append({"pos": pos, "radius": radius}))
	_data()
	await _handling()
	await _weapons()
	await _destruction()
	Game.state = &"menu"


func _spawn(kind: StringName, pos: Vector3, heading := 0.0) -> Vehicle:
	var v := Vehicle.new()
	_host.add_child(v)
	v.setup(kind, null)
	v.activate(pos, heading)
	return v


func _floor() -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 1.0, 2000.0)
	cs.shape = box
	b.add_child(cs)
	_host.add_child(b)
	b.global_position = Vector3(0.0, -0.5, 0.0)
	return b


# --- data ------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var missing: Array[String] = []
	var bad: Array[String] = []
	for k in KINDS:
		if not VehicleSpecs.SPECS.has(k):
			missing.append(String(k))
			continue
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		if VehicleSpecs.cls_of(k) != &"tank" or not bool(sp.get("craft", false)) or String(sp.get("turret", "")) != "Turret":
			bad.append("%s class" % k)
		if not VehicleSpecs.ROSTER.has(k) or not VehicleSpecs.CRAFT_KINDS.has(k) or not VehicleSpecs.TANK_KINDS.has(k):
			bad.append("%s lists" % k)
		if not VehicleSpecs.NAMES.has(k) or VehicleSpecs.name_of(k) == "":
			bad.append("%s name" % k)
		if not ResourceLoader.exists("res://assets/icons/v_%s.png" % k):
			bad.append("%s picture" % k)
		if not VehicleWeapons.has_weapon(k):
			bad.append("%s weapon" % k)
		if not AudioDirector.ENGINES.has(k):
			bad.append("%s engine" % k)
		if float(sp["hp"]) < 800.0 or float(sp["mass"]) < 10000.0:
			bad.append("%s is not armoured" % k)
	TestLib.check(missing.is_empty() and bad.is_empty(), "all five armoured kinds are complete: spec, roster, name, picture, weapon, engine (missing %s, bad %s)" % [str(missing), str(bad)])
	var depot := {}
	for pt in VehicleSpawns.POINTS:
		depot[StringName(pt["kind"])] = true
	var no_spawn: Array[String] = []
	for k in KINDS:
		if not depot.has(k):
			no_spawn.append(String(k))
	TestLib.check(no_spawn.is_empty(), "every kind waits at the army depot (%s)" % str(no_spawn))
	# the bodies: a hull Body, a Turret on the axis and a Gun on the trunnion
	var shapes: Array[String] = []
	for k in [&"ltank", &"apc", &"artillery", &"aatank"]:
		var root := VehicleCraftModels.build_tank(String(k), VehicleSpecs.SPECS[k])
		var body := root.get_node_or_null("Body") as MeshInstance3D
		var tur := root.get_node_or_null("Turret") as MeshInstance3D
		var gun := root.get_node_or_null("Turret/Gun") as MeshInstance3D
		if body == null or tur == null or gun == null or body.mesh.get_aabb().size.z < 4.0 or gun.mesh.get_aabb().size.z < 1.0:
			shapes.append(String(k))
		root.free()
	TestLib.check(shapes.is_empty(), "the four procedural bodies have a hull, a turret and a gun (broken %s)" % str(shapes))
	# own numbers: speed order, seats, elevation
	var s := func(k: StringName, key: String) -> float: return float(VehicleSpecs.SPECS[k][key])
	TestLib.check(s.call(&"apc", "max") > s.call(&"ltank", "max") and s.call(&"ltank", "max") > s.call(&"tank", "max") and s.call(&"tank", "max") > s.call(&"artillery", "max"), "the carrier is fastest, then the light tank, the battle tank, the artillery")
	TestLib.check(int(s.call(&"apc", "seats")) >= 6 and s.call(&"tank", "hp") > s.call(&"ltank", "hp"), "the carrier seats six, the battle tank is tougher than the light tank")
	TestLib.check(s.call(&"artillery", "gun_max") > 0.9 and s.call(&"aatank", "gun_max") > 1.2, "the artillery and the anti-air gun elevate far above a tank's")
	TestLib.check(bool(VehicleSpecs.WEAPONS[&"artillery"]["indirect"]) and bool(VehicleSpecs.WEAPONS[&"aatank"]["flak"]) and float(VehicleSpecs.WEAPONS[&"artillery"]["blast"]) >= 10.0, "howitzer shells land on the crosshair with an 11 m blast, flak bursts in the air")
	TestLib.check(VehicleSpecs.ALT_WEAPONS.has(&"tank") and VehicleSpecs.ALT_WEAPONS.has(&"ltank") and VehicleSpecs.ALT_WEAPONS.has(&"aatank") and String(VehicleSpecs.ALT_WEAPONS[&"tank"]["kind"]) == "gun", "the tanks carry a coaxial machine gun, the anti-air tank seeker missiles")
	var branded: Array[String] = []
	for k in KINDS:
		for b in BRANDS:
			if VehicleSpecs.name_of(k).to_upper().contains(b) or String(VehicleSpecs.WEAPONS[k]["name"]).to_upper().contains(b):
				branded.append(String(k))
	TestLib.check(branded.is_empty(), "generic names only (%s)" % str(branded))
	# earlier waves: the aircraft carry guns, the gunship and the jet rockets and missiles, the destroyer has gun turrets
	var air := true
	for k: StringName in [&"heli", &"plane", &"gunship", &"hauler", &"jet", &"boat", &"patrol"]:
		air = air and VehicleWeapons.has_weapon(k)
	TestLib.check(air and VehicleSpecs.ALT_WEAPONS.has(&"gunship") and VehicleSpecs.ALT_WEAPONS.has(&"jet") and String(VehicleSpecs.ALT_WEAPONS[&"jet"]["short"]) == "MISSILE", "aircraft and boats have mounted weapons, the gunship rockets and the jet missiles")
	var destroyer := ShipKit.spec(&"destroyer")
	TestLib.check(destroyer.has("turrets") and (destroyer["turrets"] as Array).size() >= 2, "the naval destroyer has gun turrets (%d)" % (destroyer["turrets"] as Array).size())


# --- handling --------------------------------------------------------------------------------------------------------

func _handling() -> void:
	var floor_body := _floor()
	var speeds := {}
	var x := -200.0
	for k in KINDS:
		var v := _spawn(k, Vector3(x, 0.0, 0.0))
		x += 40.0
		for i in int(7.0 / DT):
			v.step_drive(DT, 1.0, 0.0, false)
		speeds[k] = v.speed
		v.queue_free()
	await TestLib.frames(_host, 2)
	TestLib.check(float(speeds[&"apc"]) > float(speeds[&"ltank"]) and float(speeds[&"ltank"]) > float(speeds[&"tank"]) and float(speeds[&"tank"]) > float(speeds[&"artillery"]),
			"after 7 s on the throttle the speeds follow the numbers (carrier %.1f, light %.1f, battle %.1f, artillery %.1f m/s)" % [speeds[&"apc"], speeds[&"ltank"], speeds[&"tank"], speeds[&"artillery"]])
	var spin_ok := true
	var spins := {}
	for k in KINDS:
		var v := _spawn(k, Vector3(300.0 + 40.0 * float(KINDS.find(k)), 0.0, 0.0))
		var h0 := v.heading
		var p0 := v.global_position
		for i in int(1.0 / DT):
			v.step_drive(DT, 0.0, 1.0, false)
		spins[k] = absf(wrapf(v.heading - h0, -PI, PI))
		spin_ok = spin_ok and float(spins[k]) > 0.5 and v.global_position.distance_to(p0) < 0.6
		v.queue_free()
	await TestLib.frames(_host, 2)
	TestLib.check(spin_ok, "every tracked vehicle turns on the spot (%s rad in a second)" % str(spins))
	TestLib.check(float(spins[&"apc"]) > float(spins[&"artillery"]), "the carrier turns faster than the heavy artillery")
	# the turret slews to the crosshair, the gun elevates (artillery far above a tank)
	var results := {}
	for k: StringName in [&"tank", &"artillery", &"aatank"]:
		var v := _spawn(k, Vector3(-300.0 + 40.0 * float(KINDS.find(k)), 0.0, 400.0))
		var aim := v.global_position + Vector3(-60.0, 120.0, -40.0)
		v.set_meta(&"aim_at", aim)
		for i in int(8.0 / DT):
			v.step_drive(DT, 0.0, 0.0, false)
		var want := atan2(-(aim.x - v.global_position.x), -(aim.z - v.global_position.z))
		results[k] = {"yaw": absf(wrapf(v.craft.turret_yaw - want, -PI, PI)), "pitch": v.craft.gun_pitch}
		v.queue_free()
	await TestLib.frames(_host, 2)
	TestLib.check(float((results[&"tank"] as Dictionary)["yaw"]) < 0.1 and float((results[&"artillery"] as Dictionary)["yaw"]) < 0.1 and float((results[&"aatank"] as Dictionary)["yaw"]) < 0.1, "the turrets slew onto the crosshair (%s)" % str(results))
	TestLib.check(float((results[&"tank"] as Dictionary)["pitch"]) <= 0.56 and float((results[&"artillery"] as Dictionary)["pitch"]) > 0.8 and float((results[&"aatank"] as Dictionary)["pitch"]) > 0.8, "the tank's gun stops at 0.55 rad, the artillery and the flak gun lift to the sky")
	floor_body.queue_free()
	await TestLib.frames(_host, 2)


# --- weapons ---------------------------------------------------------------------------------------------------------

func _fire(v: Vehicle, seconds: float) -> void:
	for i in int(seconds / DT):
		v.weapons.tick(DT, true)
		v.weapons.tick_alt(DT, false)


func _weapons() -> void:
	var floor_body := _floor()
	# battle tank: the cannon (blast 7 m) and the coaxial machine gun
	var tank := _spawn(&"tank", Vector3(0.0, 0.0, 0.0), 0.0)
	var t1 := Target.new()
	_host.add_child(t1)
	t1.global_position = Vector3(0.0, 0.0, -40.0)
	await TestLib.frames(_host, 3)
	tank.craft.turret_yaw = 0.0
	tank.set_meta(&"aim_at", Vector3(0.0, 1.5, -40.0))
	for i in int(2.0 / DT):
		tank.step_drive(DT, 0.0, 0.0, false)
	var a0 := tank.weapons.ammo
	var b0 := _blasts.size()
	_fire(tank, 1.4)
	TestLib.check(tank.weapons.ammo < a0 and t1.taken > 90.0 and _blasts.size() > b0, "the TANK CANNON hits a target 40 m away for %.0f and blows a 7 m blast" % t1.taken)
	var taken := t1.taken
	var alt0 := tank.weapons.alt_ammo
	var ok := tank.weapons.fire_alt()
	TestLib.check(ok and tank.weapons.alt_ammo == alt0 - 1 and t1.taken > taken + 8.0 and tank.weapons.alt_hits >= 1, "the COAXIAL MACHINE GUN fires on the AIM button (%d rounds left, %.0f damage)" % [tank.weapons.alt_ammo, t1.taken - taken])
	for i in 60:
		tank.weapons.tick_alt(DT, true)
	TestLib.check(tank.weapons.alt_shots >= 8, "and keeps firing while the button is held (%d rounds)" % tank.weapons.alt_shots)
	tank.queue_free()
	t1.queue_free()
	# light tank + coax
	var lt := _spawn(&"ltank", Vector3(60.0, 0.0, 0.0), 0.0)
	TestLib.check(lt.weapons.mounted() and lt.weapons.has_alt() and String(lt.weapons.def["name"]) == "LIGHT CANNON" and float(lt.weapons.def["rate"]) > float(VehicleSpecs.WEAPONS[&"tank"]["rate"]), "the LIGHT TANK fires faster than the battle tank and has a coax gun")
	lt.queue_free()
	# carrier: an autocannon, a stream of rounds
	var apc := _spawn(&"apc", Vector3(100.0, 0.0, 0.0), 0.0)
	var t2 := Target.new()
	_host.add_child(t2)
	t2.global_position = Vector3(100.0, 0.0, -50.0)
	await TestLib.frames(_host, 3)
	apc.set_meta(&"aim_at", Vector3(100.0, 1.5, -50.0))
	for i in int(2.0 / DT):
		apc.step_drive(DT, 0.0, 0.0, false)
	var a1 := apc.weapons.ammo
	_fire(apc, 1.0)
	TestLib.check(a1 - apc.weapons.ammo >= 6 and t2.taken > 60.0, "the ARMOURED CARRIER's autocannon fires a burst (%d rounds, %.0f damage)" % [a1 - apc.weapons.ammo, t2.taken])
	apc.queue_free()
	t2.queue_free()
	# artillery: the shell lands on the crosshair point 300 m away, behind a building-sized obstacle
	var gun := _spawn(&"artillery", Vector3(200.0, 0.0, 0.0), 0.0)
	var far := Target.new()
	_host.add_child(far)
	far.global_position = Vector3(200.0, 0.0, -300.0)
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(40.0, 30.0, 4.0)
	wcs.shape = wbox
	wall.add_child(wcs)
	_host.add_child(wall)
	wall.global_position = Vector3(200.0, 15.0, -60.0)
	await TestLib.frames(_host, 3)
	gun.set_meta(&"aim_at", Vector3(200.0, 0.0, -300.0))
	for i in int(8.0 / DT):
		gun.step_drive(DT, 0.0, 0.0, false)
	var sh0 := gun.weapons.indirect_shells
	var ammo_g := gun.weapons.ammo
	_fire(gun, 0.1)
	TestLib.check(gun.weapons.ammo == ammo_g - 1 and far.taken == 0.0, "the HOWITZER fires and the shell is still in the air")
	var landed := false
	for i in 300:
		await TestLib.frames(_host, 1)
		if gun.weapons.indirect_shells > sh0:
			landed = true
			break
	TestLib.check(landed and far.taken > 100.0, "the shell lands on the crosshair 300 m away, over the wall, for %.0f" % far.taken)
	var big := false
	for bl in _blasts:
		big = big or (float(bl["radius"]) >= 10.0 and (bl["pos"] as Vector3).distance_to(Vector3(200.0, 0.0, -300.0)) < 8.0)
	TestLib.check(big, "with an 11 m blast")
	wall.queue_free()
	far.queue_free()
	gun.queue_free()
	# anti-air: the flak bursts at the aim point in the air, a "plane" there takes it
	var aa := _spawn(&"aatank", Vector3(400.0, 0.0, 0.0), 0.0)
	var plane := Target.new()
	_host.add_child(plane)
	plane.global_position = Vector3(400.0, 70.0, -110.0)
	for c in plane.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	await TestLib.frames(_host, 3)
	aa.set_meta(&"aim_at", Vector3(400.0, 70.0, -110.0))
	for i in int(8.0 / DT):
		aa.step_drive(DT, 0.0, 0.0, false)
	var fb0 := aa.weapons.flak_bursts
	_fire(aa, 0.6)
	TestLib.check(aa.weapons.flak_bursts > fb0 and plane.taken > 8.0, "the FLAK CANNON bursts at the aim point in the sky and the aircraft there takes %.0f (%d bursts)" % [plane.taken, aa.weapons.flak_bursts - fb0])
	var m0 := aa.weapons.alt_ammo
	TestLib.check(aa.weapons.has_alt() and String(aa.weapons.alt_def["name"]) == "SEEKER MISSILES" and m0 == 8, "and it carries eight seeker missiles")
	aa.queue_free()
	plane.queue_free()
	floor_body.queue_free()
	await TestLib.frames(_host, 2)


# --- destruction -----------------------------------------------------------------------------------------------------

func _destruction() -> void:
	var floor_body := _floor()
	var turret_hidden := true
	for k in KINDS:
		var v := _spawn(k, Vector3(-100.0 + 25.0 * float(KINDS.find(k)), 0.0, -500.0))
		await TestLib.frames(_host, 2)
		var tur := v.visual.parts.get("Turret") as Node3D
		var pop0 := TankWreck.popped
		v.damage(100000.0)
		await TestLib.frames(_host, 2)
		turret_hidden = turret_hidden and v.dead and TankWreck.popped == pop0 + 1 and tur != null and not tur.visible
		v.queue_free()
	TestLib.check(turret_hidden, "every kind blows up and throws its turret off (%d turrets popped)" % TankWreck.popped)
	var v2 := _spawn(&"tank", Vector3(0.0, 0.0, -600.0))
	await TestLib.frames(_host, 2)
	var hull := v2.global_position
	var pieces := TankWreck.live
	var wreck := TankWreck.pop_turret(v2)
	TestLib.check(wreck != null and TankWreck.live == pieces + 1, "a turret wreck is a node in the scene")
	var landed := false
	for i in 200:
		await TestLib.frames(_host, 1)
		if is_instance_valid(wreck) and wreck.global_position.y < 2.2 and i > 60:
			landed = true
			break
	TestLib.check(landed and wreck.global_position.distance_to(hull) < 8.0, "it comes down beside the hull (%.1f m away)" % wreck.global_position.distance_to(hull))
	v2.activate(Vector3(0.0, 0.0, -600.0), 0.0)
	var back := v2.visual.parts.get("Turret") as Node3D
	TestLib.check(back != null and back.visible, "recycled, the tank has its turret again")
	if is_instance_valid(wreck):
		wreck.queue_free()
	v2.queue_free()
	floor_body.queue_free()
	await TestLib.frames(_host, 2)
