extends RefCounted
## Visual bot of the TEST MENU: title screen with the TEST button, the open menu (CHEATS, SPAWN pages) and the play view with the 1-4 weapon quick buttons.
## Run: tests/... run_bot style: main.tscn -- --bot=res://tests/bot_testmenu.gd --shot-prefix=/tmp/x --touch   (writes <prefix>_menu_N.png)
var _n := 0
var _prefix := "/tmp/testmenu"

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-prefix="):
			_prefix = a.get_slice("=", 1)

func _shot(tag: String) -> void:
	var img := Engine.get_main_loop().root.get_viewport().get_texture().get_image()
	img.save_png("%s_menu_%s.png" % [_prefix, tag])

func step(_t: float, _dt: float) -> bool:
	_n += 1
	var menu := Engine.get_main_loop().root.get_tree().get_first_node_in_group(&"test_menu") as TestMenu
	if menu == null:
		return false
	match _n:
		5:
			Game.state = &"menu"
		30:
			_shot("title")
			menu.open()
			menu.set_page(0)
		50:
			_shot("cheats")
			menu.set_page(3)
		70:
			_shot("spawn")
			menu.close()
			Game.state = &"play"
			TestMode.give_all_weapons()
		100:
			_shot("play")
			print("BOT_TESTMENU_DONE")
			OS.kill(OS.get_process_id())
			return true
	return false
