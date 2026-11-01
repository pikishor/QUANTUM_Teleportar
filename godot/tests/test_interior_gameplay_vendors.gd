extends RefCounted
## Interior vendors on the real composed game: the weapon dealer (weapons, ammo, damage upgrade), the clinic (full repair, armour, regeneration), the tech den (blink, reload, magazine,
## coherence cell), the bar (rumours: story line, contract hints, synth drink). Prices follow the reputation discount, a purchase needs credits, a maxed upgrade / owned weapon /
## full reserve cannot be bought, and the trade window pauses the game, draws no pause screen and answers taps, keys and CLOSE.
## Run: tools/test.sh tests/test_interior_gameplay_vendors.gd

const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP

var host: Node
var main: Node
var p: Player
var ig: InteriorGameplay
var prog: Progress


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func go(type: StringName) -> void:
	if InteriorGameplay.active:
		ig.leave(true)
		await frames(2)
	var d := ig.doors_of(type, p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(2)
	ig.enter(d, true)
	await frames(20)


func row_index(type: StringName, id: StringName) -> int:
	var rows := VendorLogic.rows(type)
	for i in rows.size():
		if rows[i]["id"] == id:
			return i
	return -1


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	prog = Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	await _prices_and_window()
	await _weapons()
	await _clinic()
	await _tech()
	await _bar()
	await _bodega()
	await _poor_and_maxed()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false


func _prices_and_window() -> void:
	await go(&"weapons")
	var vs := ig.vendor_screen
	TestLib.check(ig.actors.vendor != null and ig.actors.vendor.role == &"vendor", "the weapon dealer stands behind the counter")
	# walk to the vendor: the TALK prompt shows
	var v := ig.actors.vendor.global_position
	p.teleport_to(Vector3(v.x, 0.1, v.z + 2.0))
	await frames(10)
	TestLib.check(InteriorGameplay.prompt.begins_with("TALK"), "near the vendor the prompt says TALK ('%s')" % InteriorGameplay.prompt)
	Input.action_press(&"interact")
	await frames(2)
	Input.action_release(&"interact")
	await frames(3)
	TestLib.check(vs.is_open and Game.state == &"paused" and InteriorGameplay.vendor_open, "USE opens the trade window and pauses the game")
	var hud: Hud = null
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	if hud != null:
		TestLib.check(hud.layers_consistent(), "no pause screen behind the trade window")
	vs.layout()
	TestLib.check(vs.rects.size() == (InteriorData.STOCK[&"weapons"] as Array).size() and vs.close_rect.size.x > 0.0, "one BUY button per stock row plus CLOSE")
	TestLib.check(vs.tap(vs.close_rect.get_center()), "tapping CLOSE closes the window")
	await frames(2)
	TestLib.check(not vs.is_open and Game.state == &"play" and not InteriorGameplay.vendor_open, "closing resumes the game")
	prog.credits = 10000
	prog.reputation = 0
	vs.open(&"weapons")
	await frames(2)
	var r0 := VendorLogic.rows(&"weapons")
	var price0 := int(r0[0]["price"])
	TestLib.check(vs.tap(vs.rects[0].get_center()), "tapping a BUY button buys")
	await frames(2)
	TestLib.check(WeaponDefs.is_unlocked(&"scatter") and prog.credits == 10000 - price0, "the Shard Scatter is bought for %d credits" % price0)
	vs.close()
	await frames(2)
	# keyboard: ESC closes
	vs.open(&"weapons")
	await frames(1)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	vs._input(ev)
	TestLib.check(not vs.is_open, "ESC closes the trade window")
	await frames(2)


func _weapons() -> void:
	prog.credits = 10000
	var vs := ig.vendor_screen
	vs.open(&"weapons")
	await frames(1)
	var rows := VendorLogic.rows(&"weapons")
	TestLib.check(rows[row_index(&"weapons", &"scatter")]["state"] == "done", "an owned weapon is sold out")
	TestLib.check(rows[row_index(&"weapons", &"lance")]["state"] == "buy", "a weapon you can afford is for sale")
	var c := prog.credits
	var res := VendorLogic.buy(&"weapons", &"lance")
	TestLib.check(res["ok"] and WeaponDefs.is_unlocked(&"lance") and prog.credits < c, "buy the Pulse Lance")
	res = VendorLogic.buy(&"weapons", &"lance")
	TestLib.check(not res["ok"], "the same weapon cannot be bought twice")
	# ammo
	var before := p.weapon.reserve_of(&"lance")
	c = prog.credits
	res = VendorLogic.buy(&"weapons", &"ammo_lance")
	TestLib.check(res["ok"] and p.weapon.reserve_of(&"lance") == before + 5 and prog.credits == c - VendorLogic.discount_price(90), "lance cells add 5 rounds (%d -> %d)" % [before, p.weapon.reserve_of(&"lance")])
	res = VendorLogic.buy(&"weapons", &"ammo_grenade")
	TestLib.check(not res["ok"], "ammo for a weapon you do not own is refused ('%s')" % res["msg"])
	for i in 8:
		VendorLogic.buy(&"weapons", &"ammo_lance")
	var full := VendorLogic.rows(&"weapons")[row_index(&"weapons", &"ammo_lance")]
	TestLib.check(full["state"] == "done" and p.weapon.reserve_of(&"lance") <= int(WeaponDefs.def(&"lance")["reserve"]) * 2, "a full reserve stops the sale (%d)" % p.weapon.reserve_of(&"lance"))
	var lvl := prog.level(&"damage")
	res = VendorLogic.buy(&"weapons", &"damage")
	TestLib.check(res["ok"] and prog.level(&"damage") == lvl + 1, "the dealer sells the damage upgrade")
	prog.reputation = 40
	var discounted := int(VendorLogic.rows(&"weapons")[row_index(&"weapons", &"ammo_scatter")]["price"])
	prog.reputation = 0
	var plain := int(VendorLogic.rows(&"weapons")[row_index(&"weapons", &"ammo_scatter")]["price"])
	TestLib.check(discounted < plain, "reputation discounts prices (%d < %d)" % [discounted, plain])
	vs.close()
	await frames(2)


func _clinic() -> void:
	await go(&"clinic")
	var vs := ig.vendor_screen
	prog.credits = 1000
	p.hp = 20.0
	vs.open(&"clinic")
	await frames(1)
	var res := VendorLogic.buy(&"clinic", &"heal")
	TestLib.check(res["ok"] and is_equal_approx(p.hp, p.max_hp) and prog.credits == 1000 - VendorLogic.discount_price(40), "full repair restores hp (%d)" % int(p.hp))
	p.energy = 10.0
	res = VendorLogic.buy(&"clinic", &"energy")
	TestLib.check(res["ok"] and is_equal_approx(p.energy, p.max_energy), "a coherence dose refills energy")
	var l := prog.level(&"armour")
	res = VendorLogic.buy(&"clinic", &"armour")
	TestLib.check(res["ok"] and prog.level(&"armour") == l + 1 and Upgrades.damage_taken() < 1.0, "armour upgrade lowers the damage taken (%.2f)" % Upgrades.damage_taken())
	res = VendorLogic.buy(&"clinic", &"regen")
	TestLib.check(res["ok"] and prog.level(&"regen") == 1, "regeneration upgrade")
	vs.close()
	await frames(2)


func _tech() -> void:
	await go(&"tech")
	var vs := ig.vendor_screen
	prog.credits = 5000
	vs.open(&"tech")
	await frames(1)
	var b := Upgrades.blink_bonus()
	var res := VendorLogic.buy(&"tech", &"blink")
	TestLib.check(res["ok"] and Upgrades.blink_bonus() > b, "the tech den sells blink range (+%.0f m)" % (Upgrades.blink_bonus() - b))
	res = VendorLogic.buy(&"tech", &"reload")
	TestLib.check(res["ok"] and Upgrades.reload_mult() < 1.0, "reload speed")
	var m := Upgrades.mag_size()
	res = VendorLogic.buy(&"tech", &"mag")
	TestLib.check(res["ok"] and Upgrades.mag_size() > m, "magazine size (%d -> %d)" % [m, Upgrades.mag_size()])
	vs.close()
	await frames(2)


func _bar() -> void:
	await go(&"bar")
	var vs := ig.vendor_screen
	prog.credits = 500
	vs.open(&"bar")
	await frames(1)
	var c := prog.credits
	var idx := ig.rumour_index
	var res := VendorLogic.buy(&"bar", &"rumour")
	TestLib.check(res["ok"] and str(res.get("rumour", "")) != "" and prog.credits == c - VendorLogic.discount_price(20), "a rumour costs credits and tells a story line ('%s')" % str(res.get("rumour", "")).left(40))
	TestLib.check(ig.rumour_index == idx + 1, "the rumour index advances")
	var open_before := ig.hinted.size()
	res = VendorLogic.buy(&"bar", &"rumour")
	TestLib.check(ig.hinted.size() == open_before + 1 and str(res["rumour"]).find("MARKED") >= 0, "every second rumour marks an interior contract (%d hinted)" % ig.hinted.size())
	var hid := int(ig.hinted.keys()[0])
	var d := ig.door_by_id(hid)
	TestLib.check(not d.is_empty() and InteriorData.mission_for(d["type"]) != &"", "the hinted door holds an interior mission")
	var seen := false
	if is_instance_valid(Game.story):
		for id: String in Game.story.get("shown"):
			if id.begins_with("int_rumour"):
				seen = true
	TestLib.check(seen, "the rumour went out over the radio (story line queued)")
	p.hp = 50.0
	res = VendorLogic.buy(&"bar", &"drink")
	TestLib.check(res["ok"] and p.hp >= 74.0, "a synth drink heals 25 hp (%d)" % int(p.hp))
	vs.close()
	await frames(2)


func _bodega() -> void:
	await go(&"bodega")
	prog.credits = 300
	p.hp = 30.0
	ig.vendor_screen.open(&"bodega")
	await frames(1)
	var res := VendorLogic.buy(&"bodega", &"heal")
	TestLib.check(res["ok"] and is_equal_approx(p.hp, p.max_hp) and prog.credits == 300 - VendorLogic.discount_price(55), "the corner store sells field kits")
	TestLib.check(ig.actors.vendor != null and InteriorData.has_vendor(&"bodega"), "the corner store has a clerk")
	ig.vendor_screen.close()
	await frames(2)


func _poor_and_maxed() -> void:
	await go(&"tech")
	prog.credits = 3
	var res := VendorLogic.buy(&"tech", &"blink")
	TestLib.check(not res["ok"] and res["msg"] == "NOT ENOUGH CREDITS", "no credits, no purchase")
	var rows := VendorLogic.rows(&"tech")
	TestLib.check(rows[0]["state"] == "poor", "an item you cannot afford shows as poor")
	prog.credits = 100000
	for i in 8:
		VendorLogic.buy(&"tech", &"blink")
	res = VendorLogic.buy(&"tech", &"blink")
	TestLib.check(not res["ok"] and prog.level(&"blink") == Upgrades.MAX_LEVEL, "a maxed upgrade is sold out")
	res = VendorLogic.buy(&"tech", &"nonsense")
	TestLib.check(not res["ok"], "an unknown item is refused")
	TestLib.check(not ig.vendor_screen.open(&"club"), "a club has no vendor window")
	ig.leave(true)
	await frames(3)
