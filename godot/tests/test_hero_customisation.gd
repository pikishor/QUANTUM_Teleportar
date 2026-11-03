extends RefCounted
## G2 hero customisation: presets, unlock rules, save round trip (incl. old saves), material application on the live hero, the shop screen's buttons.
## Run: tools/test.sh tests/test_hero_customisation.gd


func run(host: Node) -> void:
	TestLib.check(HeroLook.scheme_count() == 8, "8 colour presets")
	var h := HeroLook.new()
	var none: Array = []
	TestLib.check(h.is_unlocked("suit:standard", none) and h.is_unlocked("scheme:0", none), "defaults are free")
	TestLib.check(not h.is_unlocked("suit:stealth", none) and not h.is_unlocked("suit:phase", none), "paid and achievement suits start locked")
	TestLib.check(h.is_unlocked("suit:phase", [&"aura_phase"]), "an achievement cosmetic unlocks a suit")
	TestLib.check(not h.equip_suit(&"stealth", none) and h.suit == &"standard", "cannot equip a locked suit")
	TestLib.check(not h.set_accent(3), "the accent picker is locked until bought")
	h.grant("suit:stealth")
	h.grant("scheme:1")
	h.grant("accent")
	TestLib.check(h.equip_suit(&"stealth", none) and h.equip_scheme(1, none) and h.set_accent(5), "owned items equip")
	var d := h.to_save()
	var h2 := HeroLook.new()
	h2.from_save(d, none)
	TestLib.check(h2.suit == &"stealth" and h2.scheme == 1 and h2.accent_hue == 5 and h2.owned.size() == 3, "save round trip")
	var h3 := HeroLook.new()
	h3.from_save({"suit": "bogus", "scheme": 99, "accent": "x", "owned": ["nope", "scheme:2"]}, none)
	TestLib.check(h3.suit == &"standard" and h3.scheme == 0 and h3.accent_hue == -1 and h3.owned.size() == 1, "damaged data falls back")
	h3.from_save({}, none)
	TestLib.check(h3.suit == &"standard" and h3.scheme == 0, "an old save without a [hero] section is the default look")
	var h4 := HeroLook.new()
	h4.from_save({"suit": "phase"}, none)
	TestLib.check(h4.suit == &"standard", "an equipped but locked suit is reset on load")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var prog := Game.progress as Progress
	var p: Player = Game.player
	if prog == null or p == null or p.body == null:
		TestLib.check(false, "progress and hero present")
		return
	prog.credits = 5000
	TestLib.check(prog.buy_look("scheme:1") and prog.credits == 5000 - Economy.scheme_price(1), "buying a scheme pays its price")
	TestLib.check(not prog.buy_look("scheme:1") and not prog.buy_look("suit:phase") and not prog.buy_look("suit:standard"), "no double buy, no buying achievement or free items")
	TestLib.check(prog.credits == 5000 - Economy.scheme_price(1), "refused buys cost nothing")
	var gears: Array = p.body._gear_mats
	if gears.is_empty():
		return                                           # primitive fallback body: no override materials to compare
	var before: Color = (gears[0] as BaseMaterial3D).albedo_color
	var emis_before: Color = p.body._gear_emis[0]
	TestLib.check(prog.hero.equip_scheme(1, prog.achievements.cosmetics), "equip the bought scheme")
	var after: Color = (gears[0] as BaseMaterial3D).albedo_color
	TestLib.check(absf(after.r - before.r) + absf(after.b - before.b) > 0.005, "the scheme changes the armour albedo")
	TestLib.check(p.body._gear_emis[0] != emis_before or p.body._look_mix > 0.0, "the accent reaches the emission")
	prog.hero.equip_scheme(0, prog.achievements.cosmetics)
	prog.hero.suit = &"standard"
	TestLib.check(prog.buy_look("suit:stealth") and prog.hero.equip_suit(&"stealth", prog.achievements.cosmetics), "buy and equip a suit")
	TestLib.check(absf((gears[0] as BaseMaterial3D).albedo_color.get_luminance() - before.get_luminance()) > 0.001, "the suit changes the albedo")

	# the save file keeps the look
	prog.path = "user://test_hero_look.cfg"
	prog.hero.suit = &"stealth"
	prog.hero.scheme = 1
	TestLib.check(prog.save_file(), "save")
	prog.hero.reset()
	TestLib.check(prog.load_file() and prog.hero.suit == &"stealth" and prog.hero.scheme == 1, "the look survives save and load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prog.path))

	# the screen buttons
	var hud := get_hud(main)
	if hud != null:
		Game.state = &"paused"
		hud.press_button(&"pause_shop") if false else null
		hud._shop_open = true
		TestLib.check(hud.press_button(&"look_open") and hud._look_open, "SUIT button opens the screen")
		prog.credits = 5000
		TestLib.check(hud.press_button(&"look_scheme_3") and prog.hero.scheme == 3, "tap a scheme: buy and equip")
		TestLib.check(hud.press_button(&"look_hue_buy") and hud.press_button(&"look_hue_4") and prog.hero.accent_hue == 4, "buy the picker and pick a hue")
		TestLib.check(not hud.press_button(&"look_suit_phase"), "a locked achievement suit does not equip")
		TestLib.check(hud.press_button(&"look_back") and not hud._look_open, "BACK returns to the shop")
		Game.state = &"play"


static func get_hud(main: Node) -> Hud:
	for n in main.find_children("*", "Hud", true, false):
		return n as Hud
	return null
