extends RefCounted
## WAVE 128 (owner: "why only 4 weapons allowed? Make sure you allow 30-40 to be switched"). The real main scene as a phone (touch forced, reward cards on, 844x390) and a REAL finger
## (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event in window coordinates, tests/touch_audit_lib.gd): the demo's grant carries 36 weapons, the LOADOUT's page chip turns
## to slots 33-36 and a finger on a slot and on EQUIP changes it, the WEAPON button's quick swap visits all 36 carried weapons, the two-level wheel and the favourites (more than 24) reach a carried weapon,
## and the 36 slots survive a save and a load (an old save of four slots is topped up).
## Fail-first: W128A_OLD=1 tools/test.sh tests/test_arsenal_w128.gd (the four slots of wave 114).
## Run: tools/test.sh tests/test_arsenal_w128.gd

const TIMEOUT_SECONDS := 150
const Audit := preload("res://tests/touch_audit_lib.gd")
var A: Audit
var pw: PlayerWeapon


func run(h: Node) -> void:
	A = Audit.new()
	Sfx.muted = true
	var ok := await A.boot(h, "w128a")
	TestLib.check(ok, "the phone scene boots (touch HUD, player, progress)")
	if not ok:
		await A.shutdown()
		return
	pw = (Game.player as Player).weapon
	var prog := Game.progress as Progress
	Game.state = &"play"
	await A.frames(4)
	# 1. the demo equips everything: 36 weapons are carried, a mixed set (not 32 of one class)
	DemoMode._grant_all(prog)
	await A.frames(2)
	var car := LoadoutSlots.carried()
	var classes := {}
	for id in car:
		classes[WeaponDefs.class_of(id)] = true
	TestLib.check(LoadoutSlots.COUNT >= 30 and LoadoutSlots.COUNT <= 40 and car.size() == 36, "the demo's grant carries 36 weapons (slots %d, carried %d; wave 114 carried 4)" % [LoadoutSlots.COUNT, car.size()])
	TestLib.check(classes.size() >= 8, "the 36 carried weapons come from %d classes (a mixed set)" % classes.size())
	await _arsenal()
	await _swap_all()
	await _wheel_and_favs()
	_save_load(prog)
	await A.shutdown()


func _btn(id: StringName) -> Dictionary:
	A.hud._ensure_layout()
	for b: Dictionary in A.hud.buttons:
		if b["id"] == id:
			return b
	return {}


## The LOADOUT by finger: pause, LOADOUT, the page chip to slots 33-36, a slot, a tile, EQUIP.
func _arsenal() -> void:
	var opened := await A.goto(&"paused", ["loadout"])
	TestLib.check(opened and A.hud._loadout_open, "a finger on PAUSE then LOADOUT opens the Arsenal")
	if not A.hud._loadout_open:
		return
	var chip := _btn(&"ars_slotpage")
	TestLib.check(not chip.is_empty(), "the slot bar has a page chip (more than four slots)")
	var turns := 0
	while not chip.is_empty() and LoadoutSlots.page != 8 and turns < 12:
		await A.tap((chip["rect"] as Rect2).get_center())
		turns += 1
		chip = _btn(&"ars_slotpage")
	TestLib.check(LoadoutSlots.page == 8 and not _btn(&"ars_slot_34").is_empty(), "eight fingers on the page chip show slots 33-36 (page %d after %d taps)" % [LoadoutSlots.page + 1, turns])
	var s34 := _btn(&"ars_slot_34")
	if not s34.is_empty():
		var hit := A.hud_target({"rect": s34["rect"], "id": "ars_slot_34"})        # the area a finger hits, in real px at 844x390 (the touch audit's measure)
		var real := Vector2(A.px(hit.size.x), A.px(hit.size.y))
		var back_h := A.px(A.hud_target({"rect": _btn(&"loadout_back")["rect"], "id": "loadout_back"}).size.y)
		TestLib.check(real.x >= Audit.MIN_PX - 0.5 and real.y >= back_h - 0.5, "a slot of the bar is as big a touch target as the bar's BACK (%.1f x %.1f px; BACK %.1f px high)" % [real.x, real.y, back_h])
		await A.tap((s34["rect"] as Rect2).get_center())
		TestLib.check(LoadoutSlots.active == 34 and A.hud._loadout_w == LoadoutSlots.get_slot(34), "a finger on slot 35 makes it active and shows its weapon (%s)" % LoadoutSlots.get_slot(34))
	# a tile of the list by finger, then EQUIP: the weapon goes into slot 35 and the hand
	var tile := {}
	for b: Dictionary in A.hud.buttons:
		var id := String(b["id"])
		if id.begins_with("wheel_") and b.has("tile") and StringName(b["tile"]) != LoadoutSlots.get_slot(34) and StringName(b["tile"]) != pw.current and WeaponDefs.is_unlocked(StringName(b["tile"])):
			tile = b
			break
	TestLib.check(not tile.is_empty(), "the list shows an owned weapon tile")
	if tile.is_empty():
		return
	var pick := StringName(tile["tile"])
	await A.tap((tile["rect"] as Rect2).get_center())
	var eq := _btn(&"ars_equip")
	TestLib.check(not eq.is_empty() and String(eq["label"]).ends_with("35"), "the action says EQUIP SLOT 35 (%s)" % str(eq.get("label", "")))
	if not eq.is_empty():
		await A.tap((eq["rect"] as Rect2).get_center())
	TestLib.check(LoadoutSlots.get_slot(34) == pick and pw.current == pick, "a finger on EQUIP puts %s into slot 35 and into the hand (slot %s, hand %s)" % [pick, LoadoutSlots.get_slot(34), pw.current])
	var back := _btn(&"loadout_back")
	if not back.is_empty():
		await A.tap((back["rect"] as Rect2).get_center())
	await A.to_root(&"play")


## The WEAPON button: a tap is a quick swap. 36 taps visit the 36 carried weapons and come back.
func _swap_all() -> void:
	Game.state = &"play"
	SnakeWar.holster()
	pw.switch_to(LoadoutSlots.get_slot(0), true)
	await A.frames(3)
	var seen := {}
	var outside := 0
	var n := LoadoutSlots.filled().size()
	for i in n:
		var b := A.hud_button("swap")
		if b.is_empty():
			break
		await A.tap(A.centre_of(b))
		await A.until(func() -> bool: return not Input.is_action_pressed(&"swap"), 60)        # a thumb taps slower than the 0.12 s pulse of the button: the next tap is a new press
		await A.pframes(2)
		seen[pw.current] = true
		if LoadoutSlots.slot_of(pw.current) < 0:
			outside += 1
	TestLib.check(n == 36 and seen.size() == 36 and outside == 0, "36 fingers on WEAPON visit the %d carried weapons, nothing else (%d seen, %d outside)" % [n, seen.size(), outside])
	TestLib.check(pw.current == LoadoutSlots.get_slot(0), "and the 37th weapon is the first again (%s)" % pw.current)


## The two-level wheel: hold WEAPON, a class wedge, then the weapon on its ring (a weapon carried in slot 30+). FAVOURITES: a 25th star by finger, its ring has pages.
func _wheel_and_favs() -> void:
	Game.state = &"play"
	var target := LoadoutSlots.get_slot(31)
	var cls := WeaponDefs.class_of(target)
	if pw.current == target:
		pw.switch_to(LoadoutSlots.get_slot(0), true)
	var got := await _wheel_pick_weapon(cls, target)
	TestLib.check(got and pw.current == target, "the wheel by finger (hold WEAPON, the %s wedge, its ring) takes %s, carried in slot 32 (hand %s)" % [cls, target, pw.current])
	# favourites: 24 starred, the 25th by a finger on the star of the LOADOUT
	WeaponBrowser.favourites.clear()
	var ids := WeaponDefs.all_ids()
	for i in 24:
		WeaponBrowser.toggle_favourite(ids[i])
	var opened := await A.goto(&"paused", ["loadout"])
	var star_ok := false
	if opened:
		var tile := {}
		for b: Dictionary in A.hud.buttons:
			if String(b["id"]).begins_with("wheel_") and b.has("tile") and not WeaponBrowser.is_favourite(StringName(b["tile"])) and WeaponDefs.is_unlocked(StringName(b["tile"])):
				tile = b
				break
		if not tile.is_empty():
			await A.tap((tile["rect"] as Rect2).get_center())
			var st := _btn(&"ars_star")
			if not st.is_empty():
				await A.tap((st["rect"] as Rect2).get_center())
			star_ok = WeaponBrowser.is_favourite(StringName(tile["tile"]))
	TestLib.check(star_ok and WeaponBrowser.favourites.size() == 25, "a finger on the star makes a 25th favourite (%d; wave 114 stopped at 24)" % WeaponBrowser.favourites.size())
	await A.to_root(&"play")
	TestLib.check(WeaponWheel.ring_pages(WeaponWheel.FAV) >= 4, "the FAVOURITES ring pages through all of them (%d pages of %d)" % [WeaponWheel.ring_pages(WeaponWheel.FAV), WeaponWheel.RING])


## Hold WEAPON until the wheel opens, release on the wedge of `cls`, then tap NEXT until `target` shows, then tap it.
func _wheel_pick_weapon(cls: StringName, target: StringName) -> bool:
	var b := A.hud_button("swap")
	if b.is_empty():
		return false
	var c := A.centre_of(b)
	A.finger_down(c)
	var opened := await A.until(func() -> bool: return A.tc.wheel.is_open, 120)
	if not opened:
		A.finger_up()
		return false
	var wi := -1
	for i in A.tc.wheel.items.size():
		if StringName(A.tc.wheel.items[i]["id"]) == cls:
			wi = i
	if wi < 0:
		A.finger_up()
		return false
	var to := A.tc.wheel.item_centre(wi)
	for k in 6:
		A.finger_move(c.lerp(to, float(k + 1) / 6.0))
		await A.frames(1)
	A.finger_up()
	await A.frames(3)
	for page in 30:
		if not A.tc.wheel.is_open:
			return false
		var hit := -1
		var nxt := -1
		for i in A.tc.wheel.items.size():
			var it: Dictionary = A.tc.wheel.items[i]
			if StringName(it["id"]) == target and StringName(it.get("type", &"")) == &"weapon":
				hit = i
			if StringName(it.get("type", &"")) == &"page":
				nxt = i
		if hit >= 0:
			await A.tap(A.tc.wheel.item_centre(hit))
			await A.pframes(2)
			return true
		if nxt < 0:
			return false
		await A.tap(A.tc.wheel.item_centre(nxt))
	return false


## Save and load: the 36 slots come back; an old save of four slots is topped up to 36 from the owned weapons.
func _save_load(prog: Progress) -> void:
	var before := LoadoutSlots.to_save()
	TestLib.check(prog.save_file(), "the profile saves")
	LoadoutSlots.reset()
	TestLib.check(prog.load_file(), "the profile loads")
	TestLib.check(LoadoutSlots.to_save() == before and LoadoutSlots.filled().size() == 36, "the 36 carried slots come back from the save (%d filled)" % LoadoutSlots.filled().size())
	LoadoutSlots.from_save(before.slice(0, 4))
	TestLib.check(LoadoutSlots.filled().size() == 36 and LoadoutSlots.get_slot(0) == StringName(before[0]), "a save of the old four slots keeps them and carries 32 more (%d filled)" % LoadoutSlots.filled().size())
