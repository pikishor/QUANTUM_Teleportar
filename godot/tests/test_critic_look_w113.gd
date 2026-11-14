extends RefCounted
## Wave 113, critic LOOK: regression checks for the defects found in phone-resolution frames of the blasts, the damage and the enemies (frames in docs/shots/round6/critic113_look_*.jpg, log in
## docs/sprint/progress/w113-critic-look.md). Real game scene, no frame counts (game time is advanced by hand), no frames are read.
##  1. STATUS LOOKS: burning, frozen, shocked and dissolving bodies come from ONE include (assets/shaders/dmg_status.gdshaderinc) that the three body shaders share; the first versions drew their
##     flicker along the UV islands (a burning man was a tiger, a frozen one a zebra); the aliens (foe_creature) had no status look at all: FoeFx now sets `dmg_fx` on their own material, and clears it
##  2. a shattered or cracked car window: the crack texture has mip levels and the glass shader blurs the lines with the distance (a 1 px line texture was black and white noise 8 m away)
##  3. torn car panels use their own shader (paint blotched with scorch, a bare metal rim); the flying wheels own a private lighter tyre (the car's tyre is near black: a black ball in the street)
##  4. fire stands ON the street (BlastFx.ground_under), not at the height of the blast
##  5. the preview wall of the blast radius is drawn with normal alpha and a solid foot band (an additive wall added no contrast on a bright or an orange street); the ground scorch has no solid ember plate
##  6. an entry registered at run time (what a snake bomb does) plays, hurts and leaves marks like a built-in row
## Run: tools/test.sh tests/test_critic_look_w113.gd

var host: Node
var floor_body: StaticBody3D
const ORIGIN := Vector3(-700.0, 0.0, 400.0)


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	host.add_child(b)
	b.global_position = pos
	return b


func _advance(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		FX._process(0.1)
		FX.explosions._process(0.1)
		FX.qvfx._process(0.1)
		if FX.marks.is_processing():
			FX.marks._process(0.1)
		if FX.car_debris.is_processing():
			FX.car_debris._process(0.1)
		var bf := BlastFx.instance
		if is_instance_valid(bf) and bf.is_processing():
			bf._process(0.1)
		DamageWorld.current._process(0.1)


func _code(path: String) -> String:
	return (load(path) as Shader).code


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_shaders_and_textures()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var old_q := Game.quality
	if DamageWorld.current == null or AlienWorld.instance == null:
		TestLib.check(false, "the real scene has the damage world and the alien world")
		return
	var em := Game.enemies as EnemyManager
	em.patrol_groups().clear()
	em.clear()
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	floor_body = _box(ORIGIN + Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	var hero := Game.player as Player
	if hero != null:
		TestMode.god = true
		hero.teleport_to(ORIGIN + Vector3(-20.0, 0.0, 0.0))
	await TestLib.frames(host, 5)
	FX.reset()
	Dmg.reset_stats()
	await _status_on_every_body()
	_debris_and_fire()
	await _registered_entry()
	FX.reset()
	Game.quality = old_q
	floor_body.queue_free()


# --- the files ------------------------------------------------------------------------------------------------------------------

func _shaders_and_textures() -> void:
	var inc := '#include "res://assets/shaders/dmg_status.gdshaderinc"'
	for path in ["res://assets/shaders/hero_body.gdshader", "res://assets/shaders/foe_body.gdshader", "res://assets/shaders/foe_creature.gdshader"]:
		var code := _code(path)
		TestLib.check(code.contains(inc) and code.contains("dmg_status("), "%s uses the shared status looks" % path.get_file())
		TestLib.check(not code.contains("flick * flick"), "%s has no UV-stripe status code left" % path.get_file())
	var inc_code := FileAccess.get_file_as_string("res://assets/shaders/dmg_status.gdshaderinc")
	TestLib.check(inc_code.contains("bool dmg_status(") and inc_code.contains("fx.x < 1.5") and inc_code.contains("fx.x < 2.5") and inc_code.contains("fx.x < 3.5"), "the include knows the four states (burn, freeze, shock, dissolve)")
	var live_code := ""
	for line in inc_code.split("\n"):
		live_code += line.split("//")[0] + "\n"
	TestLib.check(not live_code.contains("UV"), "the status looks never read the UV (the position on the body is what they use, it follows the pose)")
	TestLib.check(_code("res://assets/shaders/foe_creature.gdshader").contains("uniform vec4 dmg_fx"), "the creature shader takes the status as a material parameter")
	var glass := _code("res://assets/shaders/car_glass.gdshader")
	TestLib.check(glass.contains("crack_lod") and glass.contains("textureLod(crack_tex"), "the glass blurs its cracks with the distance")
	var tex := VehicleVisual._cracks_texture()
	TestLib.check(tex != null and tex.get_image().has_mipmaps(), "the crack texture has mip levels")
	var foe := _code("res://assets/shaders/foe_body.gdshader")
	TestLib.check(foe.contains("emis += alb * (0.3"), "the armoured humans keep a fake ambient of their own paint (a backlit mercenary was a black cut-out at 15 m)")
	var cloud := _code("res://assets/shaders/blast_cloud.gdshader")
	TestLib.check(cloud.contains("float lick = vnoise(") and cloud.contains("ragged"), "the flame sprites have climbing licks and a ragged tip (the first version was a flat teardrop)")
	var wall := _code("res://assets/shaders/blast_wall.gdshader")
	TestLib.check(wall.contains("blend_mix") and not wall.contains("blend_add") and wall.contains("skirt"), "the radius wall is drawn with normal alpha and a dark skirt (it reads on any street colour)")
	var marks := _code("res://assets/shaders/fx_marks.gdshader")
	TestLib.check(marks.contains("float glints") and not marks.contains("smoothstep(0.0, 3.0, age)"), "the scorch ember is a short ring of glints, not a solid plate")
	var panel := _code("res://assets/shaders/car_debris_panel.gdshader")
	TestLib.check(panel.contains("bare metal") and panel.contains("v_paint"), "the torn panel shader paints the car's colour with scorch and a metal edge")


# --- people ---------------------------------------------------------------------------------------------------------------------

func _status_on_every_body() -> void:
	var dw := DamageWorld.current
	var foes := dw.foes
	var w := AlienWorld.instance
	w.force_active = true
	w.ambient_enabled = false
	var alien: AlienCreature = null
	var human: AlienCreature = null
	for c in w.spawn_group(&"vael_grunt", ORIGIN + Vector3(0.0, 0.0, -8.0), 1, &"", 0.0, false):
		alien = c
	for c in w.spawn_group(&"auth_rifle", ORIGIN + Vector3(4.0, 0.0, -8.0), 1, &"", 0.0, false):
		human = c
	TestLib.check(alien != null and human != null, "an alien and an armoured human stand in the arena")
	if alien == null or human == null:
		return
	_advance(0.3)
	TestLib.check(alien.mat != null and alien.mat.shader != null and alien.mat.shader.resource_path.ends_with("foe_creature.gdshader"), "the alien wears the creature shader on a material of its own")
	var kinds := {&"burn": 1.0, &"freeze": 2.0, &"shock": 3.0}
	for k: StringName in kinds:
		foes.set_status(alien, k, 3.0)
		var v: Variant = alien.mat.get_shader_parameter(&"dmg_fx")
		TestLib.check(v is Vector4 and absf((v as Vector4).x - float(kinds[k])) < 0.01 and (v as Vector4).y > 0.5, "an alien shows %s through its material (%s)" % [k, str(v)])
		foes.set_status(human, k, 3.0)
		var hb := human.get(&"humanoid_body") as MeshInstance3D
		if hb != null:
			var hv: Variant = hb.get_instance_shader_parameter(&"dmg_fx")
			TestLib.check(hv is Vector4 and absf((hv as Vector4).x - float(kinds[k])) < 0.01, "the armoured human shows %s too" % k)
	# a status ends by itself and the body is clean again (the longest status wins: the 3 s ones above must run out first)
	_advance(3.6)
	var vend: Variant = alien.mat.get_shader_parameter(&"dmg_fx")
	TestLib.check(vend is Vector4 and (vend as Vector4).y < 0.001, "the status ends on the alien and the shader is clean again (%s)" % str(vend))
	# the fourth state is the creature's own dissolve: the plain uniform must not eat the body early
	foes.set_status(alien, &"dissolve", 2.0)
	var vd: Variant = alien.mat.get_shader_parameter(&"dmg_fx")
	TestLib.check(vd is Vector4 and (vd as Vector4).y < 0.001, "a dissolving alien uses its own dissolve (the plain status stays off)")


# --- debris and fire ------------------------------------------------------------------------------------------------------------

func _debris_and_fire() -> void:
	var deb := FX.car_debris
	var pmm: MultiMesh = deb._pmm
	var box := pmm.mesh as BoxMesh
	TestLib.check(box != null and box.material is ShaderMaterial and (box.material as ShaderMaterial).shader.resource_path.ends_with("car_debris_panel.gdshader"), "torn panels use the scorched-paint shader")
	var wmesh := deb._wmm.mesh as ArrayMesh
	var cached := CarParts.wheel_mesh(CarDebris.WHEEL_R, CarDebris.WHEEL_W)
	TestLib.check(wmesh != null and wmesh != cached, "the flying wheels own a private copy of the wheel mesh")
	var lit := 0
	var cached_lit := 0
	for i in wmesh.get_surface_count():
		var m := wmesh.surface_get_material(i) as StandardMaterial3D
		if m != null and m.emission_enabled:
			lit += 1
	for i in cached.get_surface_count():
		var m2 := cached.surface_get_material(i) as StandardMaterial3D
		if m2 != null and m2.emission_enabled:
			cached_lit += 1
	TestLib.check(lit >= 1 and cached_lit == 0, "...with a lit tyre, while the cars' own wheels keep theirs (%d lit, %d on the cached mesh)" % [lit, cached_lit])
	var spawned0: int = deb.spawned
	deb.tear_panel(ORIGIN + Vector3(2.0, 1.0, 0.0), Vector3(2.0, 4.0, 0.0), Color(0.8, 0.1, 0.1), Vector3(1.2, 0.05, 0.6))
	TestLib.check(deb.spawned == spawned0 + 1 and deb.live_panels() >= 1, "a panel can still be torn off (%d live)" % deb.live_panels())
	# fire stands on the street
	var bf := BlastFx.shared()
	var g := bf.ground_under(ORIGIN + Vector3(3.0, 2.0, 3.0))
	TestLib.check(g != Vector3.INF and absf(g.y) < 0.05, "ground_under finds the street under a point 2 m above it (%s)" % str(g))
	TestLib.check(bf.ground_under(ORIGIN + Vector3(3.0, 40.0, 3.0)) == Vector3.INF, "...and nothing under a point 40 m up")
	var live0: int = bf.cloud_live()
	bf.flames(ORIGIN + Vector3(0.0, 2.5, 0.0), 6.0, 7)
	TestLib.check(bf.cloud_live() > live0, "a flame field puts flames into the shared cloud (%d -> %d)" % [live0, bf.cloud_live()])


# --- an entry registered at run time ---------------------------------------------------------------------------------------------

func _registered_entry() -> void:
	var id := &"critic_look_snake"
	var e := BlastTable.register(id, {"cat": &"ordnance", "name": "SNAKE BOMB", "radius": 5.0, "core": 1.0, "enemy": 140.0, "vehicle": 160.0, "element": &"quantum", "knock": 8.0, "lift": 8.0,
			"status": {"k": &"stun", "t": 1.5, "p": 1.0}, "fx": &"default", "deliver": {"mode": &"drop"}})
	TestLib.check(BlastTable.has_entry(id) and float(e["radius"]) == 5.0, "a registered entry is in the table")
	var w := AlienWorld.instance
	var foe: AlienCreature = null
	for c in w.spawn_group(&"vael_grunt", ORIGIN + Vector3(0.0, 0.0, 14.0), 1, &"", 0.0, false):
		foe = c
	if foe == null:
		BlastTable.unregister(id)
		TestLib.check(false, "a foe stands at the registered blast")
		return
	foe.max_hp = 1.0e6
	foe.hp = 1.0e6
	_advance(0.2)
	var hero := Game.player as Player
	var marks0: int = FX.marks.total_added
	var slots0: int = FX.explosions.active_count()
	var res: Dictionary = BlastTable.apply(id, foe.global_position + Vector3(2.5, 0.2, 0.0), hero, {})
	TestLib.check(int(res.get("enemies", 0)) >= 1, "the registered blast reaches the foe 2.5 m from its centre (%d hit)" % int(res.get("enemies", 0)))
	var lost := 1.0e6 - foe.hp
	var want := BlastTable.damage_at(id, &"enemy", 2.5)
	TestLib.check(lost > 0.0 and absf(lost - want) < maxf(2.0, want * 0.08), "...for the damage of the table (%.1f lost, table %.1f)" % [lost, want])
	TestLib.check(FX.explosions.active_count() > slots0 or FX.marks.total_added > marks0, "...with a pooled blast and marks on the street")
	BlastTable.unregister(id)
	TestLib.check(not BlastTable.has_entry(id), "...and it unregisters again")
