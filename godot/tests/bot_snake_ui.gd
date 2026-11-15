extends RefCounted
## Visual bot of the snake powers on the phone HUD (wave 115): the WEAPON wheel with its SNAKE and BOMBS wedges, the ring of the verbs (page 1 and 2), the ring of the bombs (locked ones dimmed), the HUD with a power
## armed (the WEAPON button shows its picture and the energy), the ABILITY wheel with the four quick casts.
##   BOT_RES=1200x540 QUALITY=1 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_snake_ui.gd /tmp/x/ui 25 8
## One shot every 25 frames: 1 weapon wheel, 2 verbs ring, 3 verbs page 2, 4 bombs ring, 5 bombs page 2, 6 armed NET (HUD), 7 armed COIL BOMB aiming, 8 ability wheel.

var _tc: TouchControls


func _ring(tab: StringName, page: int) -> void:
	_tc.wheel.close()
	_tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	var pw := (Game.player as Player).weapon
	_tc.wheel.open_at(&"weapon", WeaponWheel.ring_items(tab, page, pw.current), _tc.wheel.centre, _tc.wheel.scale, true, _tc.wheel_bounds())


func step(_t: float, _delta: float) -> bool:
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud == null or Game.player == null:
		return false
	_tc = hud.touch
	var f: int = Dev.get(&"_frame")
	var war := SnakeWar.of(Game.player)
	if f == 3:
		Game.state = &"play"
		_tc.controls_on = true
		_tc.set_process(true)
		TestMode.god = true
		Game.player.snake.energy = 76.0
		SkillTree.reset()
	if f == 10:
		_tc._open_wheel(&"weapon", -1, Vector2.ZERO)
	if f == 35:
		_ring(SnakeUi.TAB_VERBS, 0)
	if f == 60:
		_ring(SnakeUi.TAB_VERBS, 1)
	if f == 85:
		_ring(SnakeUi.TAB_BOMBS, 0)
	if f == 110:
		_ring(SnakeUi.TAB_BOMBS, 1)
	if f == 135:
		_tc.wheel.close()
		war.arm(&"sv_net")
	if f == 160:
		WeaponDefs.hero_mode = true
		war.arm(&"sb_gravity")
	if f == 185:
		war.disarm()
		_tc._open_wheel(&"ability", -1, Vector2.ZERO)
	if f == 205:
		_tc.wheel.close()
	return false
