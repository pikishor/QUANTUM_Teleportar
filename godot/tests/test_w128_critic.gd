extends RefCounted
## WAVE 128 CRITIC (w128-critic): the defects found by the independent review of wave 128 (aircraft look, seated hero, 36 carried weapons, realistic blasts, open items), each a check
## on the real main scene as a phone (Game.force_touch, reward cards on: CrateReveal._quiet = 0; controls driven by REAL fingers through Input.parse_input_event, tests/touch_audit_lib.gd).
## Every check marked [old fails] failed on the wave tree before the critic's fix.
##   fire    the fireball flipbook was block-compressed (DXT1 / ETC2 4x4 blocks): a near blast showed hard staircase squares in the fire and the new soot (frames docs/shots)
##   seat    the seated pilot (new in wave 128) cast his own shadows inside the closed cockpit: +9 draw calls aboard a fighter on LOW (122 -> 131, bot_w128_critic CR_ONLY=perf), shadows nobody sees
##   thermo  the thermobaric blast still drew a big see-through orange sphere (the pressure dome) around a realistic fireball: a sci-fi bubble, not an explosion
## Run: tools/test.sh tests/test_w128_critic.gd   (CRIT_PARTS=fire,thermo to run some parts)
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const Pool := preload("res://scripts/fx/explosion_pool.gd")
const Fingers := preload("res://tests/w116_fingers.gd")
var A: Audit
var _p: Player


func _on(part: String) -> bool:
	var parts := OS.get_environment("CRIT_PARTS")
	return parts == "" or parts.split(",").has(part)


func run(h: Node) -> void:
	A = Audit.new()
	var ok := await A.boot(h, "w128c")
	TestLib.check(ok, "the phone scene boots (touch HUD, player, progress)")
	if not ok:
		await A.shutdown()
		return
	Sfx.muted = true
	_p = Game.player as Player
	TestMode.god = true
	Game.state = &"play"
	if _on("fire"):
		_fire()
	if _on("thermo"):
		await _thermo()
	if _on("seat"):
		await _seat()
	await A.shutdown()


## [old fails] The fire layer's flipbook keeps its smooth gradients: not a block-compressed texture (BC1 / ETC2 cut every 128 px frame into 4x4 blocks, magnified to 20 px squares on a near blast).
func _fire() -> void:
	var im: Image = (Pool.FLIP as Texture2D).get_image()
	TestLib.check(im != null and not im.is_compressed(), "the fireball flipbook is not block-compressed (format %s): no staircase squares in a near fireball" % (str(im.get_format()) if im != null else "none"))


## [old fails] A thermobaric blast on the street: a fireball, soot, dust and a shock flash, but no see-through sphere around it.
func _thermo() -> void:
	var fx := BlastFx.shared()
	var cam := Game.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := _p.global_position + fwd * 16.0
	at.y = BlastFx.ground_y(at + Vector3(0.0, 3.0, 0.0))
	var before := fx.domes_made
	BlastTable.apply(&"la_thermo", at, _p, {})
	await A.pframes(3)
	TestLib.check(fx.domes_made == before and fx.domes_live() == 0, "a thermobaric blast draws no glass sphere around its fireball (domes made %d, live %d)" % [fx.domes_made - before, fx.domes_live()])
	before = fx.domes_made
	BlastTable.apply(&"gr_still", at + fwd * 6.0, _p, {})
	await A.pframes(3)
	TestLib.check(fx.domes_made > before, "a STILL POD keeps its bubble (a dome is right there: %d)" % (fx.domes_made - before))


func _casters() -> Array[String]:
	var out: Array[String] = []
	for n in _p.body.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.is_visible_in_tree() and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and g.layers != 0:
			out.append(String(g.name))
	return out


## [old fails] Board a fighter by finger (ENTER): the seated pilot casts no shadow (his meshes are under the canopy); out again by finger (EXIT), the hero casts his shadow again.
func _seat() -> void:
	var fg := Fingers.new(A.host)
	var vm := Game.vehicles as VehicleManager
	var at := Airport.to_world(Vector3(1250.0, 0.0, -600.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	_p.teleport_to(at + Vector3(-40.0, 0.5, 0.0))
	await A.pframes(20)
	var on_foot := _casters().size()
	vm._release_farthest(at)
	var v := vm.spawn_parked(&"p_fighter", at, 0.0)
	await A.pframes(4)
	_p.teleport_to(v.global_position + v.right() * 3.0 + Vector3(0.0, 0.3, 0.0))
	await A.pframes(20)
	var ok := false
	for i in 60:
		if fg.button_label(&"interact") == "ENTER":
			ok = true
			break
		fg.stick(Vector2(-1.0, 0.0))
		await A.pframes(2)
	fg.stick(Vector2.ZERO)
	await A.pframes(2)
	if ok and fg.press(6, &"interact"):
		await A.frames(3)
		fg.up(6)
	await A.frames(40)
	TestLib.check(_p.vehicle == v and _p.body.visible, "a finger on ENTER seats the hero in the fighter (in %s, body shown %s)" % [_p.vehicle.kind if _p.vehicle else "-", _p.body.visible])
	var seated := _casters()
	TestLib.check(on_foot > 0 and seated.is_empty(), "the seated pilot casts no shadow in the cockpit (%d casters on foot, seated %s)" % [on_foot, seated])
	if fg.press(6, &"interact"):
		await A.frames(3)
		fg.up(6)
	await A.frames(30)
	TestLib.check(_p.vehicle == null and _casters().size() == on_foot, "a finger on EXIT: on foot he casts his shadow again (%d of %d)" % [_casters().size(), on_foot])
