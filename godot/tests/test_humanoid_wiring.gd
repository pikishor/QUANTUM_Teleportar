extends RefCounted
## HumanoidAnim wired into the live game (headless, real scene main.tscn): the Vael trooper (operative) drives its rig through HumanoidAnim (windup, fire kick, flinch, death, weapon mount),
## specialists keep the old model, and the citizen actors hang their arms relaxed and swing them against the legs (no rifle pose). Waits are on counters and state, never frame counts.
## Run: tools/test.sh tests/test_humanoid_wiring.gd


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	if not HumanoidVariants.available():
		TestLib.check(true, "hero files absent: nothing to wire")
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	await _trooper(host)
	await _citizens(host)
	await _walk_swing(host)
	main.queue_free()
	await TestLib.frames(host, 2)


func _wait(host: Node, cond: Callable, max_frames := 900) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func _trooper(host: Node) -> void:
	var em := Game.enemies as EnemyManager
	TestLib.check(em != null, "the live game has an EnemyManager")
	if em == null:
		return
	em.patrol_groups().clear()
	em.clear()
	var p: Player = Game.player
	p.invuln = 1.0e6
	var at := p.global_position + Vector3(14.0, 0.0, 0.0)
	var o := em.spawn(&"operative", at, true) as Operative
	TestLib.check(o != null and o.hanim != null and o.rig != null, "a trooper owns a HumanoidAnim on its rig")
	if o == null or o.hanim == null:
		return
	TestLib.check(o.hanim.weapon == &"rifle" and not o.humanoid.is_empty(), "the trooper carries the rifle mount on the Vael model")
	o._cover_on = false
	o._cover_state = 0
	await TestLib.frames(host, 3)
	TestLib.check(o.hanim.state != HumanoidAnim.State.IDLE, "an aware trooper is not idle")
	# windup then burst: the telegraph charges, rounds kick the rifle
	var seen_windup := false
	var max_charge := 0.0
	var max_recoil := 0.0
	var max_ready := 0.0
	var tries := 0
	while o.hanim.shots < 1 and tries < 40 and not o.dead:
		o._aim_t = maxf(o._aim_t, float(o.cfg["aim_time"]))
		o._cover_state = 0
		for i in 60:
			await TestLib.frames(host, 1)
			seen_windup = seen_windup or o.hanim.state == HumanoidAnim.State.WINDUP
			max_charge = maxf(max_charge, o.hanim.charge)
			max_recoil = maxf(max_recoil, o.rig.recoil)
			max_ready = maxf(max_ready, o.rig.ready)
			if o.hanim.shots >= 1:
				break
		tries += 1
	TestLib.check(seen_windup and max_charge > 0.5, "the aim windup runs through the WINDUP state (charge %.2f)" % max_charge)
	TestLib.check(o.hanim.shots >= 1, "a fired round reaches the HumanoidAnim (%d shots)" % o.hanim.shots)
	for i in 6:
		await TestLib.frames(host, 1)
		max_recoil = maxf(max_recoil, o.rig.recoil)
	TestLib.check(max_recoil > 0.3, "the rig takes the recoil kick (%.2f)" % max_recoil)
	TestLib.check(max_ready > 0.7, "the rifle is shouldered while aiming (ready %.2f)" % max_ready)
	# weapon mount: the rifle mount is the model's own muzzle, a pistol mount ends the barrel earlier
	var rifle_m := o.hanim.muzzle_transform(o.rig)
	TestLib.check(o.muzzle != null and o.muzzle.transform.origin.distance_to(rifle_m.origin) < 0.05, "the Muzzle node follows the rifle mount")
	o.hanim.set_weapon(&"pistol")
	var pistol_m := o.hanim.muzzle_transform(o.rig)
	TestLib.check(absf(pistol_m.origin.distance_to(rifle_m.origin) - 0.45) < 0.03, "a pistol mount moves the muzzle along the barrel (%.2f m)" % pistol_m.origin.distance_to(rifle_m.origin))
	o.hanim.set_weapon(&"rifle")
	# flinch: a hit shows in the state machine and on the rig
	o.damage(1.0)
	TestLib.check(o.hanim.flinch > 0.4, "a hit flinches the humanoid (%.2f)" % o.hanim.flinch)
	var max_flinch := 0.0
	for i in 4:
		await TestLib.frames(host, 1)
		max_flinch = maxf(max_flinch, o.rig.flinch)
	TestLib.check(max_flinch > 0.2, "the rig shows the flinch (%.2f)" % max_flinch)
	# death
	o.damage(1.0e6)
	TestLib.check(o.hanim.state == HumanoidAnim.State.DEAD, "the kill puts the HumanoidAnim in DEAD")
	var ok := await _wait(host, func() -> bool: return o.rig.dead >= 0.999, 600)
	TestLib.check(ok and o.rig.knee_buckle > 0.2 and o.rig.death_kind == o.hanim.death_kind, "the body goes limp through the HumanoidAnim fall (dead %.2f buckle %.2f)" % [o.rig.dead, o.rig.knee_buckle])
	var shots_dead := o.hanim.shots
	o.hanim.fire()
	TestLib.check(o.hanim.shots == shots_dead, "a dead trooper cannot fire")
	# pooled reuse starts clean
	em.clear()
	var o2 := em.spawn(&"operative", at, false) as Operative
	if o2 != null and o2.hanim != null:
		TestLib.check(o2.hanim.state == HumanoidAnim.State.IDLE and o2.hanim.dead == 0.0 and o2.hanim.shots == 0, "a respawned trooper starts idle")
	# specialists keep the old model
	em.clear()
	var s := em.spawn(&"shield", at, true) as Operative
	TestLib.check(s != null and s.hanim == null and s.humanoid.is_empty(), "specialists keep the old model (no HumanoidAnim)")
	await TestLib.frames(host, 3)
	em.clear()


func _citizens(host: Node) -> void:
	var city := Game.world as City
	var amb: Node3D = city.ambient
	amb.set_quality(2)
	var cz = amb.citizens
	amb.reset()
	amb.simulate = true
	var ok := await _wait(host, func() -> bool: return cz.assigned_total > 0 and cz.active_count() > 0, 800)
	TestLib.check(ok, "citizen actors exist in the live scene")
	await TestLib.frames(host, 20)
	var relaxed := true
	var n := 0
	for s: Dictionary in cz.slots:
		var rig := s["rig"] as CharacterRig
		n += 1
		relaxed = relaxed and rig.hand_w == Vector2.ONE and rig.hand_off_l.y < -0.3 and rig.hand_off_r.y < -0.3
		for k in 2:
			var w := rig.wrist_position(k)
			relaxed = relaxed and w.y < 1.05 and w.z > -0.3
	TestLib.check(n > 0 and relaxed, "live citizens hold their arms relaxed at the sides (%d actors), not up on a rifle" % n)
	amb.reset()


## A citizen rig walked by Locomotion: the arms swing against the legs and hang low at rest.
func _walk_swing(host: Node) -> void:
	var r := HumanoidVariants.build(&"citizen", 3)
	TestLib.check(r["root"] != null, "a citizen builds")
	if r["root"] == null:
		return
	var root := r["root"] as Node3D
	host.add_child(root)
	var rig := CharacterRig.find(root)
	TestLib.check(rig != null, "the citizen has the shared rig")
	if rig == null:
		root.free()
		return
	var loco := Locomotion.new(rig)
	loco.scale_amp = 0.95
	rig.ready = 0.0
	var zl: Array[float] = []
	var zr: Array[float] = []
	var low_ok := true
	for i in 150:
		loco.update(1.0 / 60.0, Vector3(0.0, 0.0, -0.05), 0.0, true, 0.0, 1.0, false, false)
		HumanoidAnim.relax_arms(rig)
		rig.apply()
		if i >= 60:
			var l := rig.wrist_position(0)
			var rr := rig.wrist_position(1)
			zl.append(l.z)
			zr.append(rr.z)
			low_ok = low_ok and l.y < 1.05 and rr.y < 1.05
	var ml := 0.0
	var mr := 0.0
	for i in zl.size():
		ml += zl[i]
		mr += zr[i]
	ml /= zl.size()
	mr /= zr.size()
	var cov := 0.0
	var rl := 0.0
	for i in zl.size():
		cov += (zl[i] - ml) * (zr[i] - mr)
		rl = maxf(rl, absf(zl[i] - ml))
	TestLib.check(low_ok, "walking arms stay low")
	TestLib.check(rl > 0.08, "the arms swing while walking (%.2f m)" % rl)
	TestLib.check(cov < 0.0, "the arms swing against each other (covariance %.4f)" % cov)
	root.queue_free()
	await TestLib.frames(host, 1)
