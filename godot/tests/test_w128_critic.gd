extends RefCounted
## WAVE 128 CRITIC (w128-critic): the defects found by the independent review of wave 128 (aircraft look, seated hero, 36 carried weapons, realistic blasts, open items), each a check
## on the real main scene as a phone (Game.force_touch, reward cards on: CrateReveal._quiet = 0; controls driven by REAL fingers through Input.parse_input_event, tests/touch_audit_lib.gd).
## Every check marked [old fails] failed on the wave tree before the critic's fix.
##   fire    the fireball flipbook was block-compressed (DXT1 / ETC2 4x4 blocks): a near blast showed hard staircase squares in the fire and the new soot (frames docs/shots)
##   thermo  the thermobaric blast still drew a big see-through orange sphere (the pressure dome) around a realistic fireball: a sci-fi bubble, not an explosion
## Run: tools/test.sh tests/test_w128_critic.gd   (CRIT_PARTS=fire,thermo to run some parts)
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const Pool := preload("res://scripts/fx/explosion_pool.gd")
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
