extends RefCounted
## Enemy readability: role colour code, rim on specialist bodies, telegraph boost of tells. Run: tools/test.sh tests/test_enemy_look.gd

func run(host: Node) -> void:
	var cols := {}
	for t: StringName in [&"operative", &"shield", &"flanker", &"sniper", &"brute", &"sentinel", &"striker", &"heavy"]:
		cols[t] = EnemyLook.code_color(EnemyTypes.get_cfg(t))
	var seen := {}
	for t in cols:
		var c: Color = cols[t]
		var k := "%d,%d,%d" % [int(c.r * 10), int(c.g * 10), int(c.b * 10)]
		assert(not seen.has(k), "role colour shared: %s" % t)
		seen[k] = true
	assert(EnemyLook.rim_strength(0) > EnemyLook.rim_strength(2), "LOW has the strongest rim")
	assert(EnemyLook.plate_glow(1.0) > EnemyLook.plate_glow(0.0))
	var mi := EnemyTells.make(&"sniper")
	EnemyLook.boost_tell(mi, 0.0)
	var dim := mi.transparency
	EnemyLook.boost_tell(mi, 1.0)
	assert(mi.transparency < dim and mi.scale.x > 1.2, "charged tell brighter and larger")
	mi.free()
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	body.set_surface_override_material(0, StandardMaterial3D.new())
	root.add_child(body)
	assert(EnemyLook.apply_rim(root, Color.RED, 0) == 1)
	assert((body.get_surface_override_material(0) as StandardMaterial3D).rim_enabled)
	root.free()
	print("test_enemy_look OK")
