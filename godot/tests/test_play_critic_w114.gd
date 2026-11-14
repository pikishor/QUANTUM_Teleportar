extends RefCounted
## Regression tests of the wave 114 PLAY critic (weapons in hand and the weapon screens), in the REAL game scene. Every check here failed on the tree the critic measured (see docs/sprint/progress/w114-critic-play.md):
##   SOUND   the 56 weapons of the throw kind (grenades, mines, strike beacons, launchers, pods) played the QUANTUM BLINK or another weapon's recording and the 7 charge weapons (lance, beam and rail
##           rifles, bows) the ENTANGLE hum and the overcharge zap: none of them used the sound sets of wave 114 (WeaponAudio.fire ran for hitscan guns only).
##   HUD     the kill / pickup feed hung from the top right across the centred objective line and the toast (23 / 19 % of the line at 844x390 with no wanted stars, 44 / 30 % at 1280x720).
##   REVEAL  a crate opened in a fight dimmed the whole screen and put a 560 x 366 card in the middle of the view for 3.4 s while enemies shot (the reveal never pauses).
##   BURST   the interval of a burst weapon (burst pistol, bullpup, tempo, double tap, triple tap, pulse rifle ...) was counted twice (the last round of the burst added a second interval): 10 weapons fired at
##           half the rate and half the damage per second their card shows (measured 240 rpm against 429 shown for the burst pistol).
##   AMMO    PlayerWeapon._auto_swap (dry with nothing in reserve: the best weapon that still shoots, toast OUT OF AMMO) was written in wave 85 and never called: the trigger clicked for ever.
## Run: tools/test.sh tests/test_play_critic_w114.gd   (W114_ONLY=sound,... runs sections)

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _w: PlayerWeapon
var _only: PackedStringArray = PackedStringArray()


func _want(section: String) -> bool:
	return _only.is_empty() or _only.has(section)


func _equip(id: StringName) -> void:
	_w.switch_to(id, true)
	_w.ammo = _w.mag
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0
	_w.charge = 0.0
	if _w.reserve >= 0:
		_w.reserve = maxi(_w.reserve, 40)


func run(host: Node) -> void:
	_host = host
	var only := OS.get_environment("W114_ONLY")
	if only != "":
		_only = only.split(",", false)
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	_p = Game.player as Player
	_w = _p.weapon
	TestLib.check(_p != null and _w != null, "the game is up")
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	await TestLib.frames(host, 4)
	if _want("sound"):
		await _sound()
	if _want("ammo"):
		await _ammo()
	if _want("hud"):
		await _hud()
	if _want("touch"):
		await _touch()
	if _want("reveal"):
		await _reveal()
	if _want("burst"):
		await _burst()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false


# --- sound: every weapon fires through its own sound set -------------------------------------------------------------------

func _sound() -> void:
	var quantum_blink := [&"blink", &"phase_step"]
	var throws: Array[StringName] = []
	var charges: Array[StringName] = []
	for id: StringName in WeaponDefs.all_ids():
		var kind := String(WeaponDefs.def(id)["kind"])
		if kind == "throw":
			throws.append(id)
		elif kind == "charge":
			charges.append(id)
	TestLib.check(throws.size() >= 50 and charges.size() >= 6, "the roster has %d weapons of the throw kind and %d of the charge kind" % [throws.size(), charges.size()])
	Sfx.muted = false
	var bad_body: Array[String] = []
	var bad_last: Array[String] = []
	var silent: Array[String] = []
	var no_set: Array[String] = []
	for id: StringName in throws:
		_equip(id)
		var sid := WeaponAudio.set_of(id)
		var want := StringName(WeaponAudio.data(sid)["body"])
		var s0 := WeaponAudio.shots
		var fired0 := _w.shots_fired
		Sfx.last_played = &""
		Sfx._last_start.clear()
		WeaponAudio.last_body = &""
		for i in 40:
			_w.tick(DT, true, false, false, false)
			_w.mech.tick(DT)
			if _w.shots_fired > fired0:
				break
		if _w.shots_fired <= fired0:
			silent.append("%s did not throw" % id)
			continue
		if WeaponAudio.shots <= s0:
			no_set.append(String(id))
		elif WeaponAudio.last_body != want:
			bad_body.append("%s played %s, its set %s has %s" % [id, WeaponAudio.last_body, sid, want])
		if quantum_blink.has(Sfx.last_played):
			bad_last.append("%s ends on %s" % [id, Sfx.last_played])
		_w.tick(6.0, false, false, false, false)
		_w._clear_grenades()
	TestLib.check(no_set.is_empty(), "every thrown, placed, called-in and launched weapon fires through its sound set (%d did not: %s)" % [no_set.size(), ", ".join(no_set.slice(0, 8))])
	TestLib.check(bad_body.is_empty(), "the body of the throw is the one of its set (%s)" % "; ".join(bad_body.slice(0, 4)))
	TestLib.check(bad_last.is_empty(), "no throw plays the QUANTUM BLINK (%s)" % "; ".join(bad_last.slice(0, 4)))
	TestLib.check(silent.is_empty(), "every weapon of the throw kind throws when the trigger is pulled (%s)" % "; ".join(silent.slice(0, 4)))
	TestLib.check(WeaponAudio.set_of(&"rocket") == &"lau_rocket" and WeaponAudio.set_of(&"grenade") == &"thr_frag", "the old rocket launcher and hand grenade have the voice of a tube and a hand grenade (%s, %s)" % [WeaponAudio.set_of(&"rocket"), WeaponAudio.set_of(&"grenade")])
	# the charge weapons: the wind-up is the mechanism of their set, the release the set's body (an energy weapon at full charge: the overcharged shot)
	var bad_charge: Array[String] = []
	var bad_start: Array[String] = []
	for id: StringName in charges:
		_equip(id)
		var d := WeaponDefs.def(id)
		var sd := WeaponAudio.data(WeaponAudio.set_of(id))
		var body := StringName(sd["body"])
		var full_oc := StringName(sd["mech"]) == &"wm_charge"
		var m0 := WeaponAudio.mechs
		var s0 := WeaponAudio.shots
		var fired0 := _w.shots_fired
		Sfx.last_played = &""
		WeaponAudio.last_body = &""
		var need := int((float(d["charge_time"]) + 0.5) / DT)
		for i in need:
			_w.tick(DT, true, false, true, false)
			if i == 2 and WeaponAudio.mechs <= m0:
				bad_start.append("%s: no wind-up sound of its set (%s)" % [id, StringName(sd["mech"])])
		_w.tick(DT, false, false, true, false)
		_w.tick(DT, false, false, true, false)
		if _w.shots_fired <= fired0:
			bad_charge.append("%s did not release" % id)
			continue
		var want := &"shot_oc" if full_oc else body
		if WeaponAudio.shots <= s0 or WeaponAudio.last_body != want:
			bad_charge.append("%s released %s (shots +%d), wanted %s" % [id, WeaponAudio.last_body, WeaponAudio.shots - s0, want])
		if [&"link", &"entangle_link", &"boom"].has(Sfx.last_played):
			bad_charge.append("%s ends on %s" % [id, Sfx.last_played])
		_w.tick(6.0, false, false, false, false)
	TestLib.check(bad_start.is_empty(), "a charge weapon winds up with the mechanism of its set, not the ENTANGLE hum (%s)" % "; ".join(bad_start.slice(0, 4)))
	TestLib.check(bad_charge.is_empty(), "a charge weapon releases through its sound set (%s)" % "; ".join(bad_charge.slice(0, 4)))
	# a bow does not zap: its release is the bow's own recording even at full draw
	if WeaponDefs.DEFS.has(&"bw_recurve"):
		_equip(&"bw_recurve")
		WeaponAudio.last_body = &""
		var f0 := _w.shots_fired
		for i in int((float(WeaponDefs.def(&"bw_recurve")["charge_time"]) + 0.5) / DT):
			_w.tick(DT, true, false, true, false)
		_w.tick(DT, false, false, true, false)
		_w.tick(DT, false, false, true, false)
		TestLib.check(_w.shots_fired > f0 and WeaponAudio.last_body == &"shot_v3_bow", "a fully drawn bow plays the bow, not the plasma zap (%s)" % WeaponAudio.last_body)
	Sfx.muted = true


# --- ammo: a dry weapon with nothing in reserve hands the trigger to a weapon that shoots ---------------------------------------

func _pull(seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		_w.tick(DT, true, false, false, false)
		_w.mech.tick(DT)


func _ammo() -> void:
	Sfx.muted = true
	_w.reset()
	LoadoutSlots.reset()
	LoadoutSlots.ensure()
	var slots := LoadoutSlots.slots.duplicate()
	# a dry grenade: the next weapon of the loadout that shoots is in the hand, the toast says so
	_equip(&"gr_frag")
	_w.ammo = 0
	_w.reserve = 0
	_pull(0.3)
	var now := _w.current
	var kind := String(WeaponDefs.def(now)["kind"])
	TestLib.check(now != &"gr_frag" and kind != "melee" and (_w.ammo > 0 or _w.reserve != 0), "a dry grenade with nothing in reserve hands the trigger to a weapon that shoots (%s)" % now)
	TestLib.check(slots.has(now), "the weapon comes from the loadout the hero chose (%s of %s)" % [now, str(slots)])
	# a dry rifle that has rounds in reserve reloads and stays in the hand
	_equip(&"carbine")
	_w.ammo = 0
	_w.reserve = 30
	_pull(0.2)
	TestLib.check(_w.current == &"carbine" and _w.is_reloading(), "a dry rifle with rounds in reserve reloads instead of swapping (%s, reloading %s)" % [_w.current, _w.is_reloading()])
	_w.cancel_reload()
	# a dry charge weapon swaps the same way
	if WeaponDefs.DEFS.has(&"lance"):
		_equip(&"lance")
		_w.ammo = 0
		_w.reserve = 0
		for i in 40:
			_w.tick(DT, true, false, true, false)
		TestLib.check(_w.current != &"lance", "a dry Pulse Lance with nothing in reserve swaps too (%s)" % _w.current)
	# nothing left to shoot anywhere: the blade (the melee weapons never run dry)
	_equip(&"gr_frag")
	_w.ammo = 0
	_w.reserve = 0
	for id: StringName in WeaponDefs.all_ids():
		if id != &"gr_frag":
			_w._store[id] = Vector2i(0, 0)                                         # every other gun is empty, the unlimited ones too
	_w.swap_t = 0.0
	_pull(0.3)
	TestLib.check(_w.current == &"blade", "with every gun empty the hero is handed the blade (%s)" % _w.current)
	_w.reset()
	LoadoutSlots.reset()


# --- hud: the kill feed never crosses the objective line or the toast -------------------------------------------------------------

func _scan_hud(hud: Hud) -> Array[Dictionary]:
	hud.scan_log.clear()
	hud.scan_text = true
	hud.scan_hud = true
	hud._hud.queue_redraw()
	for i in 90:
		await TestLib.frames(_host, 1)
		if not hud.scan_log.is_empty():
			break
	await TestLib.frames(_host, 1)
	hud.scan_text = false
	hud.scan_hud = false
	var out: Array[Dictionary] = []
	var seen := {}
	for e: Dictionary in hud.scan_log:
		var key := "%s|%s" % [e["text"], e["rect"]]
		if not seen.has(key):
			seen[key] = true
			out.append(e)
	return out


func _hud() -> void:
	var hud := _host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(hud != null, "the hud exists")
	if hud == null:
		return
	if hud.touch != null:
		hud.touch.controls_on = true
	var win := _host.get_window()
	var win_old := win.size
	Game.state = &"play"
	var names := ["OPERATIVE  RIFT CARBINE", "BRUTE  SHARD SCATTER", "NEW WEAPON  TWIN RIVET SMG", "VAEL RAIDER  ION BATTLE RIFLE"]
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		win.size = size
		await TestLib.frames(_host, 4)
		for heat in [0.0, 2.0]:
			Game.heat = heat
			var now := PlayerUtil.now()
			hud.feed.clear()
			hud.feed.push(HudFeed.KILL, names[0], now, &"a_pillar")
			hud.feed.push(HudFeed.KILL, names[1], now, &"scatter")
			hud.feed.push(HudFeed.PICKUP, names[2], now, &"s_rivet")
			hud.feed.push(HudFeed.KILL, names[3], now, &"e_ioncarb")
			Game.say("HIJACK COMPACT", 3.0)
			var log := await _scan_hud(hud)
			var feed_rects: Array[Rect2] = []
			var others: Array[Dictionary] = []
			for e: Dictionary in log:
				if names.has(String(e["text"])):
					feed_rects.append(e["rect"])
				else:
					others.append(e)
			var tag := "%dx%d, wanted %.0f" % [size.x, size.y, heat]
			TestLib.check(feed_rects.size() == 4, "%s: the four feed lines are drawn (%d)" % [tag, feed_rects.size()])
			var hit: Array[String] = []
			for fr: Rect2 in feed_rects:
				for e: Dictionary in others:
					var r: Rect2 = e["rect"]
					var inter := fr.intersection(r)
					if inter.has_area() and inter.get_area() > 0.05 * minf(fr.get_area(), r.get_area()):
						hit.append("'%s' crosses '%s'" % [names[feed_rects.find(fr)], e["text"]])
			TestLib.check(hit.is_empty(), "%s: the kill feed crosses no other text of the HUD (%s)" % [tag, "; ".join(hit.slice(0, 3))])
			hud.feed.clear()
	win.size = win_old
	Game.heat = 0.0


# --- touch: the Arsenal with real touch events at 844x390 -------------------------------------------------------------------------

func _tap(hud: Hud, pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	hud._input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	hud._input(up)


func _drag(hud: Hud, from: Vector2, to: Vector2, steps: int, release := true) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = from
	hud._input(down)
	for k in steps:
		var mv := InputEventScreenDrag.new()
		mv.index = 0
		mv.position = from.lerp(to, float(k + 1) / float(steps))
		hud._input(mv)
		await TestLib.frames(_host, 1)
	if release:
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.pressed = false
		up.position = to
		hud._input(up)


func _tiles(hud: Hud) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in hud.buttons:
		if b.has("tile"):
			out.append(b)
	return out


func _button(hud: Hud, id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func _relayout(hud: Hud) -> void:
	hud._layout_key = ""
	hud._ensure_layout()


func _touch() -> void:
	var hud := _host.get_tree().get_first_node_in_group(&"hud") as Hud
	if hud == null:
		TestLib.check(false, "the hud exists")
		return
	var win := _host.get_window()
	var win_old := win.size
	win.size = Vector2i(844, 390)
	await TestLib.frames(_host, 4)
	WeaponDefs.hero_mode = true
	_w.reset()
	LoadoutSlots.reset()
	Game.state = &"play"
	Game.state = &"paused"
	hud._on_state(&"paused")
	hud.screen_age = 5.0
	hud._sub_t = 5.0
	if Game.progress != null:
		Game.progress.credits = 5000
	_relayout(hud)
	hud.press_button(&"loadout")
	_relayout(hud)
	await TestLib.frames(_host, 3)
	var tiles := _tiles(hud)
	TestLib.check(tiles.size() >= 6, "the loadout shows a grid of weapon tiles at 844x390 (%d tiles)" % tiles.size())
	# a finger on a tile selects it (tiles of three columns and the last, clipped row)
	var bad: Array[String] = []
	for k in [0, 1, 2, 4, tiles.size() - 1]:
		tiles = _tiles(hud)
		var tb: Dictionary = tiles[mini(k, tiles.size() - 1)]
		var want: StringName = tb["tile"]
		_tap(hud, (tb["rect"] as Rect2).get_center())
		await TestLib.frames(_host, 2)
		_relayout(hud)
		if hud._loadout_w != want:
			bad.append("%s -> %s" % [want, hud._loadout_w])
	TestLib.check(bad.is_empty(), "a tap on a tile selects exactly that weapon (%s)" % "; ".join(bad.slice(0, 3)))
	# a drag scrolls and does not select
	var stt := Arsenal.st(&"loadout")
	var sel0: StringName = hud._loadout_w
	var taps0 := Arsenal.taps
	var s0 := float(stt["scroll"])
	tiles = _tiles(hud)
	var from := ((tiles[1]["rect"] as Rect2).get_center())
	await _drag(hud, from, from + Vector2(0.0, -150.0), 6)
	TestLib.check(float(stt["scroll"]) > s0 + 20.0, "a finger dragged up the list scrolls it (%.0f -> %.0f)" % [s0, float(stt["scroll"])])
	TestLib.check(hud._loadout_w == sel0 and Arsenal.taps == taps0, "a drag that starts on a tile does not select it")
	TestLib.check(not Arsenal.dragging(), "the finger is let go: no gesture is left over")
	# a flick keeps going and snaps to a whole row
	var s1 := float(stt["scroll"])
	await _drag(hud, from, from + Vector2(0.0, -260.0), 3)
	for i in 240:
		await TestLib.frames(_host, 1)
		if absf(float(stt["vel"])) < 1.0 and is_equal_approx(fposmod(float(stt["scroll"]), Arsenal.ROW), 0.0):
			break
	_relayout(hud)
	TestLib.check(float(stt["scroll"]) > s1 + 100.0, "a flick carries the list on (%.0f -> %.0f)" % [s1, float(stt["scroll"])])
	TestLib.check(absf(fposmod(float(stt["scroll"]) + 0.5 * Arsenal.ROW, Arsenal.ROW) - 0.5 * Arsenal.ROW) < 1.0, "the list comes to rest on a whole row (%.1f)" % float(stt["scroll"]))
	# after the scroll a tap still selects the tile under the finger
	tiles = _tiles(hud)
	var tb2: Dictionary = tiles[mini(3, tiles.size() - 1)]
	var want2: StringName = tb2["tile"]
	_tap(hud, (tb2["rect"] as Rect2).get_center())
	await TestLib.frames(_host, 2)
	TestLib.check(hud._loadout_w == want2, "after scrolling, a tap selects the tile that is drawn there (%s, got %s)" % [want2, hud._loadout_w])
	# a drag that leaves the list and lets go elsewhere selects nothing and leaves no gesture
	var sel3: StringName = hud._loadout_w
	_relayout(hud)
	tiles = _tiles(hud)
	var f3 := (tiles[0]["rect"] as Rect2).get_center()
	await _drag(hud, f3, Vector2(hud.get_viewport().get_visible_rect().size.x - 30.0, f3.y + 40.0), 4)
	TestLib.check(hud._loadout_w == sel3 and not Arsenal.dragging(), "a finger that slides out of the list and lets go picks nothing")
	# EQUIP puts the weapon in the active slot and in the hands
	_relayout(hud)
	tiles = _tiles(hud)
	var pick: StringName = &""
	for tb3: Dictionary in tiles:
		if tb3["tile"] != _w.current and WeaponDefs.is_unlocked(tb3["tile"]):
			pick = tb3["tile"]
			_tap(hud, (tb3["rect"] as Rect2).get_center())
			break
	await TestLib.frames(_host, 2)
	_relayout(hud)
	var eq := _button(hud, &"ars_equip")
	TestLib.check(not eq.is_empty() and (eq["rect"] as Rect2).size.x >= 64.0 and (eq["rect"] as Rect2).size.y >= 64.0 * 0.5, "the EQUIP button is on the screen and big enough")
	if not eq.is_empty():
		_tap(hud, (eq["rect"] as Rect2).get_center())
		await TestLib.frames(_host, 2)
	TestLib.check(_w.current == pick and LoadoutSlots.slots[LoadoutSlots.active] == pick, "EQUIP: %s is in the hands and in slot %d (hands %s)" % [pick, LoadoutSlots.active + 1, _w.current])
	# BACK leaves the loadout for the pause menu, the game stays paused
	_relayout(hud)
	var back := _button(hud, &"loadout_back")
	TestLib.check(not back.is_empty(), "the BACK button is on the screen")
	if not back.is_empty():
		_tap(hud, (back["rect"] as Rect2).get_center())
		await TestLib.frames(_host, 2)
	TestLib.check(not hud._loadout_open and Game.state == &"paused", "BACK closes the loadout and the pause menu is there (open %s, state %s)" % [hud._loadout_open, Game.state])
	# the wheel gesture's quick mode: one tap on a tile takes the weapon and the game runs again
	Game.state = &"play"
	hud._on_state(&"play")
	await TestLib.frames(_host, 2)
	hud.open_wheel()
	_relayout(hud)
	await TestLib.frames(_host, 2)
	TestLib.check(Game.state == &"paused" and hud._loadout_quick, "the wheel gesture opens the loadout in quick mode")
	tiles = _tiles(hud)
	var qid: StringName = &""
	for tb4: Dictionary in tiles:
		if tb4["tile"] != _w.current:
			qid = tb4["tile"]
			_tap(hud, (tb4["rect"] as Rect2).get_center())
			break
	await TestLib.frames(_host, 2)
	TestLib.check(_w.current == qid and Game.state == &"play", "in quick mode a tap on a tile takes the weapon and resumes (%s, %s)" % [_w.current, Game.state])
	win.size = win_old
	Game.state = &"play"
	hud._on_state(&"play")
	_w.reset()
	LoadoutSlots.reset()


# --- reveal: in a fight the card is small, short and leaves the view alone -------------------------------------------------------

func _finish_reveals() -> void:
	var guard := 0
	while CrateReveal.is_showing() and guard < 20:
		CrateReveal.current._process(5.0)
		guard += 1
	CrateReveal._queue.clear()


func _reveal() -> void:
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	Game.state = &"play"
	CrateReveal.enabled = true
	CrateReveal._quiet = 0
	_finish_reveals()
	TestLib.check(not CrateReveal.in_combat(), "with no enemy about there is no fight")
	var s0 := CrateReveal.started
	CrateReveal.request(&"railgun", "CRATE OPENED", true)
	TestLib.check(CrateReveal.started == s0 + 1 and CrateReveal.is_showing() and not CrateReveal.current.compact and is_equal_approx(CrateReveal.current._life, CrateReveal.LIFE), "in a quiet street the reveal is the full card of %.1f s" % CrateReveal.LIFE)
	_finish_reveals()
	# an enemy that has seen the hero 20 m away: the fight is on
	var ahead := _p.global_position + Vector3(0.0, 0.0, -20.0)
	var d := mgr.spawn(&"operative", ahead, false)
	d.set_physics_process(false)
	d.global_position = ahead
	d.aware = false
	TestLib.check(not CrateReveal.in_combat(), "an enemy that has not noticed the hero is no fight")
	d.aware = true
	TestLib.check(CrateReveal.in_combat(), "an alerted enemy 20 m away is a fight")
	var far := _p.global_position + Vector3(0.0, 0.0, -90.0)
	d.global_position = far
	TestLib.check(not CrateReveal.in_combat(), "an alerted enemy 90 m away is not")
	d.global_position = ahead
	var s1 := CrateReveal.started
	CrateReveal.request(&"railgun", "CRATE OPENED", true)
	var v := CrateReveal.current
	TestLib.check(CrateReveal.started == s1 + 1 and v != null and v.compact and is_equal_approx(v._life, CrateReveal.COMPACT_LIFE) and CrateReveal.COMPACT_LIFE < CrateReveal.LIFE, "in a fight the reveal is the small card of %.1f s" % CrateReveal.COMPACT_LIFE)
	v._process(CrateReveal.COMPACT_LIFE + 0.1)
	TestLib.check(not CrateReveal.is_showing(), "the small card is gone after its short life")
	_finish_reveals()
	mgr.clear()
	CrateReveal._quiet = -1


# --- burst: a burst weapon fires at the rate its card shows ---------------------------------------------------------------------

func _burst() -> void:
	Sfx.muted = true
	_w.reset()
	var ids: Array[StringName] = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		if String(d["kind"]) == "hit" and int(d.get("burst", 1)) >= 2:
			ids.append(id)
	TestLib.check(ids.size() >= 8, "the roster has %d burst weapons" % ids.size())
	var bad: Array[String] = []
	for id: StringName in ids:
		_equip(id)
		var d := WeaponDefs.def(id)
		var burst := int(d["burst"])
		var iv := float(d["interval"])
		var window := maxf(3.0, iv * 7.0)
		var s0 := _w.shots_fired
		for i in int(ceil(window / DT)):
			_w.ammo = _w.mag
			_w.tick(DT, true, false, false, false)
			_w.mech.tick(DT)
		var shots := _w.shots_fired - s0
		var expect := (int(floor(window / iv)) + 1) * burst                         # one burst at the start, then one every interval
		var card := WeaponStats.card(id, _w.def)
		var rpm_real := float(shots) / window * 60.0
		if absi(shots - expect) > burst or rpm_real < 0.8 * float(card["rpm"]) or rpm_real > 1.25 * float(card["rpm"]):
			bad.append("%s: %d rounds in %.1f s (%.0f rpm, the card shows %.0f, %d expected)" % [id, shots, window, rpm_real, float(card["rpm"]), expect])
		_w.tick(6.0, false, false, false, false)
	TestLib.check(bad.is_empty(), "every burst weapon fires at the rate of its card (%s)" % "; ".join(bad.slice(0, 3)))
	# the FIRE MODE alt-fire (a burst on a plain weapon, interval x burst_mode_n x 0.85, WeaponMech.interval_mult) cycles at that interval too, not at twice of it
	var mode_id: StringName = &""
	for id: StringName in WeaponDefs.all_ids():
		if String(WeaponDefs.def(id)["kind"]) == "hit" and int(WeaponDefs.def(id).get("burst", 1)) == 1 and String(WeaponDefs.alt_of(id)["kind"]) == "mode":
			mode_id = id
			break
	TestLib.check(mode_id != &"", "a weapon with the FIRE MODE alt-fire exists (%s)" % mode_id)
	if mode_id != &"":
		_equip(mode_id)
		var md := WeaponDefs.def(mode_id)
		_w.mech._mode_burst = false
		var ok_mode := _w.alt_fire(false)
		_w.fire_t = 0.0
		var cycle := float(md["interval"]) * float(md.get("burst_mode_n", 3)) * 0.85
		var window2 := maxf(3.0, cycle * 7.0)
		var s2 := _w.shots_fired
		for i in int(ceil(window2 / DT)):
			_w.ammo = _w.mag
			_w.tick(DT, true, false, false, false)
			_w.mech.tick(DT)
		var shots2 := _w.shots_fired - s2
		var n_burst := int(md.get("burst_mode_n", 3))
		var expect2 := (int(floor(window2 / cycle)) + 1) * n_burst
		TestLib.check(ok_mode and _w.mech._mode_burst and absi(shots2 - expect2) <= n_burst, "%s in burst mode: %d rounds in %.1f s, %d expected (one burst of %d every %.2f s)" % [mode_id, shots2, window2, expect2, n_burst, cycle])
		_w.mech._mode_burst = false
		_w.tick(6.0, false, false, false, false)
	# an alt-fire volley of a plain weapon still ends with one interval of waiting (the old rule for volleys)
	if WeaponDefs.DEFS.has(&"flux"):
		_equip(&"flux")
		_w.ammo = _w.mag
		var a0 := _w.shots_fired
		var ok := _w.alt_fire(false)
		for i in 120:
			_w.tick(DT, false, false, false, false)
			_w.mech.tick(DT)
		TestLib.check(ok and _w.shots_fired - a0 >= 6, "the volley alt-fire of the flux carbine still fires its rounds (%d)" % (_w.shots_fired - a0))
	_w.reset()
