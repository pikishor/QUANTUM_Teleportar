extends RefCounted
## Visual bot of the mission guide (render-look-fix loops, docs/shots/slice/guide_*.png): the same seven situations drawn twice, once with the guide's HUD pieces off ("before") and once on
## ("after"): a street step (waypoint + compass), the armed gap (NEXT line), inside a building with the next step armed (LEAVE THE BUILDING), the SKIP STEP offer, the wander reminder, the
## chase car left at hand (TAKE THE CAR), and a verb boss with its hint.
##   GUIDE_OUT=<dir> BOT_RES=2400x1080 QUALITY=0 tools/bot.sh res://tests/bot_mission_guide.gd /tmp/x 100000 1
## Writes <dir>/<n>_<scene>_before.png and _after.png.

var _out := ""
var _hud: Hud
var _camp: CampaignRunner
var _p: Player
var _i := 0
var _phase := 0                     ## 0 setup, 1 before shot, 2 after shot
var _wait := 0
var _scenes := ["street", "armed", "indoors", "stuck", "wander", "chase", "boss"]


func _init() -> void:
	_out = OS.get_environment("GUIDE_OUT")


var _done := false


func step(_t: float, _dt: float) -> bool:
	if _done:
		return true
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null or not (Game.missions is Missions):
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		_p = Game.player as Player
		_camp = (Game.missions as Missions).campaign
		if _hud.settings.path == UiSettings.DEFAULT_PATH:
			_hud.settings = UiSettings.new("user://bot_guide.cfg")
		_hud.touch.controls_on = true
		Game.state = &"play"
		_camp.enabled = false
		_wait = 6
		return false
	_p.invuln = 99.0
	_p.hp = _p.max_hp
	if is_instance_valid(Game.story):
		(Game.story as Story).skip_cards()
	if _wait > 0:
		_wait -= 1
		_hold_state()
		return false
	var name: String = _scenes[_i]
	match _phase:
		0:
			_setup(name)
			MissionGuide.hud_on = false
			_phase = 1
			_wait = 36
		1:
			_save(name, "before")
			MissionGuide.hud_on = true
			_phase = 2
			_wait = 18
		2:
			_save(name, "after")
			_i += 1
			_phase = 0
			_wait = 4
			if _i >= _scenes.size():
				MissionGuide.hud_on = true
				_done = true
				return true
	return false


func _save(name: String, which: String) -> void:
	var img := _hud.get_viewport().get_texture().get_image()
	img.save_png("%s/%02d_%s_%s.png" % [_out, _i, name, which])
	print("GUIDESHOT ", name, " ", which, " line='", _camp.hud_line(), "' guide='", _camp.guide.line(), "'")


func _hold_state() -> void:
	match _scenes[mini(_i, _scenes.size() - 1)]:
		"armed", "indoors":
			_camp._arm_t = 99.0
		"stuck":
			_camp.guide.offering = true
			_camp.guide.idle_seconds = 95.0


func _setup(name: String) -> void:
	var ig := InteriorGameplay.instance
	if InteriorGameplay.active:
		ig.leave(true)
	_camp.abort()
	Game.heat = 0.0
	(Game.enemies as EnemyManager).clear()
	match name:
		"street":
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_camp.start_custom({"id": "g1", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-160.0, 0.0], "obj": "Cross the trading floor to the beacon"}]})
			_camp._arm_t = 0.0
		"armed":
			_camp.start_custom({"id": "g2", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-100.0, 0.0], "obj": "Reach the beacon"}, {"kind": "hack", "pos": [-200.0, -80.0], "obj": "Hack the ledger node"}]})
			_camp._arm_t = 0.0
			_camp.tick(0.1)
			_camp.skip_step()
			_camp._arm_t = 99.0
		"indoors":
			_camp.start_custom({"id": "g3", "clears_sector": false, "steps": [{"kind": "reach", "pos": [-100.0, 0.0], "obj": "Reach the beacon"}, {"kind": "hack", "pos": [-200.0, -80.0], "obj": "Hack the ledger node"}]})
			_camp._arm_t = 0.0
			_camp.tick(0.1)
			_camp.skip_step()
			_camp._arm_t = 99.0
			ig.test_enter(&"lobby")
		"stuck":
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_camp.start_custom({"id": "g4", "clears_sector": false, "steps": [{"kind": "hack", "pos": [-300.0, 0.0], "obj": "Hack the ledger node"}]})
			_camp._arm_t = 0.0
		"wander":
			_camp.start_custom({"id": "g5", "clears_sector": false, "steps": [{"kind": "hack", "pos": [-300.0, 0.0], "obj": "Hack the ledger node"}]})
			_camp._arm_t = 0.0
			Game.say("NEXT: HACK THE LEDGER NODE, 270 M", 60.0)
		"chase":
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_camp.start_custom({"id": "g6", "clears_sector": false, "steps": [{"kind": "chase", "pos": [-130.0, 0.0], "obj": "Run down the courier"}]})
			_camp._arm_t = 0.0
		"boss":
			_p.teleport_to(Vector3(-30.0, 0.0, 4.0))
			_camp.start_custom({"id": "g7", "clears_sector": false, "steps": [{"kind": "kill_target", "enemy": "phasewright", "hp_mult": 1.0, "guards": 0, "name": "VAEL PHASEWRIGHT", "pos": [-60.0, 0.0], "obj": "Break the Vael Phasewright"}]})
			_camp._arm_t = 0.0
