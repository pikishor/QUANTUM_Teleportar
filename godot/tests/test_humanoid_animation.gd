extends RefCounted
## Humanoid enemy animation layer and readability. Run: tools/test.sh tests/test_humanoid_animation.gd

func run(host: Node) -> void:
	var a := HumanoidAnim.new()
	a.set_weapon(&"launcher")
	a.set_state(HumanoidAnim.State.AIM)
	for i in 60:
		a.update(0.016, 0.3)
	assert(a.ready > 0.9 and absf(a.aim_pitch - 0.3) < 0.05, "aim raises the weapon")
	a.fire()
	assert(a.recoil > 0.9 and a.shots == 1)
	for i in 60:
		a.update(0.016)
	assert(a.recoil < 0.05 and a.state == HumanoidAnim.State.AIM, "recoil decays, back to aim")
	a.hit(Vector2(1, 0), 1.0)
	assert(a.state == HumanoidAnim.State.HIT and a.flinch > 0.9)
	for i in 80:
		a.update(0.016)
	assert(a.flinch == 0.0 and a.state == HumanoidAnim.State.AIM, "flinch ends")
	a.windup_time = 0.4
	a.set_state(HumanoidAnim.State.WINDUP)
	var prev := -1.0
	for i in 200:
		a.update(0.016)
		assert(a.charge >= prev - 0.0001, "charge monotonic")
		prev = a.charge
	assert(a.windup_done(), "windup completes")
	a.die(1)
	a.fire()
	a.hit(Vector2.UP)
	for i in 200:
		a.update(0.016)
	assert(a.state == HumanoidAnim.State.DEAD and a.dead >= 1.0 and a.shots == 1, "death is final")
	var rig := CharacterRig.new()
	a.write(rig)
	assert(rig.dead >= 1.0 and rig.death_kind == 1 and rig.knee_buckle > 0.0)
	a.set_weapon(&"bogus")
	assert(a.weapon == &"rifle")
	# role colours unique across the new roles and the old ones
	var seen := {}
	for r in EnemyLook.ROLE_COLORS:
		var c: Color = EnemyLook.ROLE_COLORS[r]
		var k := "%d,%d,%d" % [int(c.r * 10), int(c.g * 10), int(c.b * 10)]
		assert(not seen.has(k), "colour clash: %s" % r)
		seen[k] = true
	assert(EnemyLook.code_color({"role": &"medic"}) == EnemyLook.ROLE_COLORS[&"medic"])
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.set_surface_override_material(0, StandardMaterial3D.new())
	root.add_child(body)
	EnemyLook.apply_rim(root, Color.RED, 1)
	var lo := EnemyLook.windup_rim(root, 1, 0.0)
	var hi := EnemyLook.windup_rim(root, 1, 1.0)
	assert(hi > lo * 1.9 and absf((body.get_surface_override_material(0) as StandardMaterial3D).rim - hi) < 0.001)
	root.free()
	print("test_humanoid_animation OK")
