extends RefCounted
## Screenshot bot for the mission result card and the flat UPGRADES list (render-look-fix loops). Use:
##   CARD_OUT=<dir> BOT_RES=2400x1080 tools/bot.sh res://tests/bot_result_card.gd /tmp/x 100000 1
## Finishes missions through the real completion signals (mission 1 mod, 2 weapon, 3 upgrade, 5 crate, 11 weapon, a cash fallback) and saves one frame of each card, the UPGRADES list
## and the LOADOUT with a NEW mod.
var _i := 0
var _wait := 0
var _out := ""
var _hud: Hud
var _card: ResultCard
var _steps: Array = []


func _init() -> void:
	_out = OS.get_environment("CARD_OUT")
	_steps = ["card_mod", "card_weapon", "card_upgrade", "card_mod2", "card_crate", "card_after_ten", "card_cash", "upgrades", "loadout_new"]


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		_card = n.get_first_node_in_group(&"result_card") as ResultCard
		if _hud == null or _card == null or Game.player == null or Game.progress == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		if _hud.touch != null:
			_hud.touch.controls_on = true
		ResultCard.enabled = true
		_card._process(0.0)                                  # connect to Progress.mission_result now
		(Game.progress as Progress).new_campaign()
		(Game.progress as Progress).credits = 350
		_begin()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	_hud.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, _steps[_i]])
	print("CARDSHOT ", _steps[_i])
	_i += 1
	if _i >= _steps.size():
		_wait = 1 << 20
		_hud.get_tree().quit()
		return true
	_begin()
	return false


func _finish_mission(kind: int) -> void:
	var m := Game.missions as Missions
	m.contracts.started.emit(&"courier")
	(Game.progress as Progress).add_credits(260 + kind * 40)
	m.contracts.completed.emit(&"courier", {})


func _open_card() -> void:
	if _card.is_open:
		_card.press_next()
	_card._delay = 0.0
	_card.open(_card.queue.pop_front())


func _begin() -> void:
	Game.state = &"play"
	var name: String = _steps[_i]
	var prog := Game.progress as Progress
	if name.begins_with("card"):
		match name:
			"card_cash":
				for id: StringName in WeaponDefs.IDS:
					prog.grant_weapon(id)
				for p: StringName in Attachments.IDS:
					MissionRewards.grant_mod(p)
				for u: StringName in Upgrades.SIMPLE:
					while prog.level(u) < Upgrades.MAX_LEVEL:
						prog.grant_upgrade(u)
			"card_after_ten":
				pass
		if name == "card_after_ten":
			while MissionRewards.missions_done < 10:
				MissionRewards.complete(&"contract", "FILL")
			_card.queue.clear()
		_finish_mission(_i)
		if _card.queue.is_empty():
			return
		_open_card()
	elif name == "upgrades":
		if _card.is_open:
			_card.press_next()
		prog.new_campaign()
		MissionRewards.grant_mod(&"scope")
		prog.grant_upgrade(&"damage")
		prog.credits = 900
		Game.state = &"paused"
		_hud._on_state(&"paused")
		_hud.screen_age = 5.0
		_hud._ensure_layout()
		_hud.press_button(&"hero_open")
		_hud._ensure_layout()
	elif name == "loadout_new":
		prog.new_campaign()
		MissionRewards.grant_mod(&"scope")
		Game.state = &"paused"
		_hud._on_state(&"paused")
		_hud.screen_age = 5.0
		_hud._ensure_layout()
		_hud.press_button(&"loadout")
		_hud._ensure_layout()
	_wait = 12
