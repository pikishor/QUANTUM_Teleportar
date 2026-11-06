extends RefCounted
## Weapons: availability, display, progression (owner round 3: "weapons display is not good, not enough weapons"). Run: tools/test.sh tests/test_weapons_available_display.gd
## Data checks (roster, starters, ladder, crates, class wheel, icons, models, grips) and the live game: the hero holds the weapon he has selected, in his hand, one mesh, with the
## right grips; the first minute has seven usable weapons; a crate gives a weapon; a fallen enemy drops ammo or the next ladder weapon; switching never loses ammo.

const DT := 1.0 / 60.0


func run(host: Node) -> void:
	_data()
	await _live(host)


func _data() -> void:
	TestLib.check(WeaponDefs.IDS.size() >= 18, "eighteen or more weapons (%d)" % WeaponDefs.IDS.size())
	TestLib.check(WeaponDefs.STARTERS.size() == 7, "seven starters")
	var classes := {}
	for id: StringName in WeaponDefs.STARTERS:
		classes[WeaponDefs.class_of(id)] = true
		TestLib.check(WeaponDefs.DEFS.has(id) and Economy.weapon_price(id) == 0, "starter %s is free" % id)
	TestLib.check(classes.size() == 7 and classes.has(&"pistol") and classes.has(&"smg") and classes.has(&"rifle") and classes.has(&"shotgun") and classes.has(&"sniper") and classes.has(&"heavy") and classes.has(&"melee"),
			"the starters cover pistol, SMG, rifle, shotgun, sniper, launcher and melee")
	WeaponDefs.reset_unlocked()
	TestLib.check(WeaponDefs.unlocked.size() == 7 and WeaponDefs.is_unlocked(&"pistol") and WeaponDefs.is_unlocked(&"gravity") and WeaponDefs.is_unlocked(&"blade"), "a fresh profile owns the seven starters")
	WeaponDefs.set_unlocked(["carbine"])
	TestLib.check(WeaponDefs.unlocked.size() == 7, "an old save that only knew the carbine gets the starters too")
	WeaponDefs.reset_unlocked()
	# every weapon is complete: a mesh with grips, an icon, a class, a drop ammo size, sounds
	for id: StringName in WeaponDefs.IDS:
		var m := WeaponModels.mesh(id)
		TestLib.check(m != null and m.get_surface_count() == 1, "%s has a one-surface mesh" % id)
		if m != null:
			var bb := m.get_aabb()
			TestLib.check(bb.size.z > 0.15 and bb.size.z < 1.5 and bb.end.z > 0.1 and bb.position.z > -0.4, "%s is a sensible length (%.2f m), body behind the muzzle" % [id, bb.size.z])
		TestLib.check(WeaponModels.SPEC.has(id), "%s has grips" % id)
		TestLib.check(WeaponDefs.CLASS_OF.has(id) and WeaponDefs.CLASS_ORDER.has(WeaponDefs.class_of(id)), "%s has a wheel class" % id)
		TestLib.check(WeaponIcons.has_icon(id) and WeaponIcons.texture(id) != null, "%s has a HUD icon built from its mesh" % id)
		var snd := StringName(WeaponDefs.def(id).get("snd", &"shot"))
		TestLib.check((ResourceLoader.exists("res://assets/audio/%s.wav" % snd) or ResourceLoader.exists("res://assets/audio/%s.ogg" % snd)), "%s: sound %s exists" % [id, snd])
		var off := WeaponModels.grip_offsets(id)
		TestLib.check(off.size() == 2 and off[0].length() < 0.8 and off[1].length() < 0.8, "%s: grip offsets are reachable" % id)
	var carbine_off := WeaponModels.grip_offsets(&"carbine")
	TestLib.check(carbine_off[0].length() < 0.001 and carbine_off[1].length() < 0.001 and is_zero_approx(WeaponModels.muzzle_shift(&"carbine")), "the carbine is the rig's own rest grip")
	TestLib.check(WeaponModels.muzzle_shift(&"pistol") > 0.2, "a pistol's muzzle sits nearer the body than a rifle's")
	var lens := {}
	for id: StringName in WeaponDefs.IDS:
		var bb2 := WeaponModels.mesh(id).get_aabb()
		lens["%d_%d_%d" % [roundi(bb2.size.x * 40.0), roundi(bb2.size.y * 40.0), roundi(bb2.size.z * 40.0)]] = true
	TestLib.check(lens.size() >= 15, "the weapons have different silhouettes (%d sizes among %d)" % [lens.size(), WeaponDefs.IDS.size()])
	# the weapon wheel is by class: seven wedges, owned weapons grouped
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		TestLib.check(not WeaponDefs.in_class(cls).is_empty() and not WeaponDefs.owned_in_class(cls).is_empty(), "class %s has an owned starter" % cls)
	# the ladder: a next weapon with a route, in a fresh profile and until everything is owned
	TestLib.check(WeaponLadder.next_target() == &"marksman" and WeaponLadder.next_line().begins_with("NEXT  PHASE MARKSMAN  CRATE"), "the next weapon is shown with how to get it (%s)" % WeaponLadder.next_line())
	var seen := {}
	for e: Dictionary in WeaponLadder.LADDER:
		seen[e["id"]] = true
		TestLib.check(WeaponDefs.DEFS.has(e["id"]) and not WeaponDefs.STARTERS.has(e["id"]) and WeaponLadder.route_text(e["id"]) != "", "ladder entry %s has a route: %s" % [e["id"], WeaponLadder.route_text(e["id"])])
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(WeaponDefs.STARTERS.has(id) or seen.has(id), "%s is a starter or on the ladder" % id)
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	TestLib.check(WeaponLadder.next_target() == &"" and WeaponLadder.next_line() == "", "nothing left to chase once everything is owned")
	WeaponDefs.reset_unlocked()
	# enemy drops: ammo for the dry weapon, the ladder weapon from its enemy type, never a starter weapon pickup as "new"
	TestLib.check(WeaponLadder.enemy_drop(&"sentinel", 0.9, 0.9, &"scatter", 0) == &"scatter", "a dry weapon always gets its ammo dropped")
	WeaponDefs.unlock(&"marksman")
	TestLib.check(WeaponLadder.next_target() == &"burst" and WeaponLadder.enemy_drop(&"operative", 0.1, 0.5, &"carbine", -1) == &"burst", "operatives carry the next weapon (burst pistol)")
	TestLib.check(WeaponLadder.enemy_drop(&"operative", 0.9, 0.9, &"carbine", -1) != &"burst", "... only some of the time")
	TestLib.check(WeaponLadder.enemy_drop(&"sentinel", 0.1, 0.1, &"scatter", 10) == &"scatter", "otherwise ammo for the gun in hand")
	WeaponDefs.reset_unlocked()
	# crate sites
	TestLib.check(WeaponLadder.CRATES.size() >= 10, "ten or more crates")
	var weapon_crates := 0
	for i in WeaponLadder.CRATES.size():
		var cp := WeaponLadder.crate_pos(i)
		TestLib.check(absf(cp.x) < CityLayout.HALF and absf(cp.z) < CityLayout.HALF, "crate %d is inside the map" % i)
		if WeaponLadder.CRATES[i]["weapon"] != &"":
			weapon_crates += 1
	TestLib.check(weapon_crates == 3, "three weapon crates")


func _live(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg.bak"))
	WeaponDefs.reset_unlocked()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	TestLib.check(p != null and w != null, "the game is up")
	WeaponDefs.reset_unlocked()
	w.reset()
	TestMode.god = true
	# seven weapons usable at once, each one switches, fires and is drawn in the hand
	var body := p.body
	var used := 0
	for id: StringName in WeaponDefs.STARTERS:
		TestLib.check(w.switch_to(id, true) or w.current == id, "%s can be selected in the first minute" % id)
		await TestLib.frames(host, 3)
		var look := body.find_child("WeaponLook", true, false) as MeshInstance3D
		TestLib.check(look != null and look.mesh == WeaponModels.mesh(id) and (look.visible or body.hero_mat == null), "the hero holds the %s (its own mesh in his hand)" % id)
		TestLib.check(body.muzzle != null and look != null and look.get_parent() == body.muzzle, "%s rides the muzzle node on the rifle bone" % id)
		if body.rig != null and body.hero_mat != null:
			var g := WeaponModels.grip_offsets(id)
			TestLib.check(body.rig.grip_off_l.is_equal_approx(g[0]) and body.rig.grip_off_r.is_equal_approx(g[1]), "%s: the hands are placed on its grips" % id)
		used += 1
	TestLib.check(used == 7, "seven weapons used")
	if body.hero_mat != null:
		TestLib.check(int(body.hero_info.get("pieces", 0)) > 0 and not body.get_meta(&"x", false), "the superhero is built unarmed (the weapon is a separate mesh)")
	# switching never loses ammo: every weapon keeps its own magazine and reserve through a round trip
	w.switch_to(&"carbine", true)
	w.ammo = 11
	w.switch_to(&"scatter", true)
	w.ammo = 2
	w.reserve = 17
	w.switch_to(&"pistol", true)
	w.ammo = 7
	w.switch_to(&"carbine", true)
	TestLib.check(w.ammo == 11, "the carbine kept its 11 rounds")
	w.switch_to(&"scatter", true)
	TestLib.check(w.ammo == 2 and w.reserve == 17, "the scatter kept 2 + 17")
	w.switch_to(&"pistol", true)
	TestLib.check(w.ammo == 7, "the pistol kept its 7 rounds")
	# switching during a reload cancels it cleanly (no phantom reload on the next weapon)
	w.switch_to(&"carbine", true)
	w.ammo = 3
	w.start_reload()
	TestLib.check(w.reload_t > 0.0, "the carbine is reloading")
	w.switch_to(&"flux", true)
	TestLib.check(w.reload_t == 0.0 and not w.is_reloading() and w.ammo == w.mag, "switching away from a reload leaves the new weapon ready (ammo %d / %d)" % [w.ammo, w.mag])
	w.switch_to(&"carbine", true)
	TestLib.check(w.ammo == 3, "the interrupted carbine still has its 3 rounds (no free ammo, no loss)")
	# a switch locks the trigger for SWAP_TIME and the old weapon's burst / charge state is dropped
	w.switch_to(&"flux")
	TestLib.check(w.swap_t > 0.2, "a switch takes a moment")
	var a0 := w.ammo
	w.tick(DT, true, false, false, false)
	TestLib.check(w.ammo == a0, "no shot during the swap")
	for _i in 30:
		w.tick(DT, false, false, false, false)
	# the weapon wheel by class: one wedge per class with an owned weapon, current weapon marked
	var items := WeaponWheel.items()
	TestLib.check(items.size() == 7, "the weapon wheel shows seven class wedges (%d)" % items.size())
	var cur_marked := false
	var ids := {}
	for it: Dictionary in items:
		ids[it["cls"]] = true
		cur_marked = cur_marked or (bool(it["current"]) and it["cls"] == WeaponDefs.class_of(w.current))
	TestLib.check(cur_marked and ids.size() == 7, "the wheel marks the class of the weapon in hand")
	# every weapon is reachable on the wheel by tapping its class again
	WeaponDefs.unlock(&"burst")
	WeaponDefs.unlock(&"revolver")
	var tc := main.find_child("Touch", true, false)
	w.switch_to(&"pistol", true)
	var cyc := WeaponWheel.next_in_class(&"pistol", w.current)
	TestLib.check(cyc == &"burst", "tapping the pistol class again cycles to the next pistol (%s)" % cyc)
	WeaponDefs.reset_unlocked()
	# crates: a weapon crate hands over its weapon, switches to it, restocks; an opened crate is closed for a while
	var fr := Freedom.current
	TestLib.check(fr != null and fr.crates != null and fr.crates.count() == WeaponLadder.CRATES.size(), "the crates exist in the live game")
	if fr != null and fr.crates != null:
		var cr := fr.crates
		TestLib.check(cr.content(0) == &"marksman" and cr.is_ready(0), "crate 0 carries the marksman")
		var cp := WeaponLadder.crate_pos(0)
		p.global_position = cp + Vector3(0.0, 0.1, 1.0)
		var before := cr.opened_count
		var t0 := Time.get_ticks_msec()
		while cr.opened_count == before and Time.get_ticks_msec() - t0 < 6000:
			await TestLib.frames(host, 5)
		TestLib.check(cr.opened_count == before + 1 and WeaponDefs.is_unlocked(&"marksman") and w.current == &"marksman", "walking up to the crate unlocks and equips the marksman")
		TestLib.check(not cr.is_ready(0) and cr.content(0) == &"", "the opened crate is closed (and now only ammo)")
		TestLib.check(cr.markers().size() < WeaponLadder.CRATES.size() or Game.player == null, "an opened crate leaves the minimap")
		var ammo_crate := 3
		w.switch_to(&"scatter", true)
		w.reserve = 1
		p.global_position = WeaponLadder.crate_pos(ammo_crate) + Vector3(0.0, 0.1, 1.0)
		var b2 := cr.opened_count
		t0 = Time.get_ticks_msec()
		while cr.opened_count == b2 and Time.get_ticks_msec() - t0 < 6000:
			await TestLib.frames(host, 5)
		TestLib.check(cr.opened_count == b2 + 1 and w.reserve > 1, "an ammo crate restocks the reserve (%d)" % w.reserve)
	# a fallen enemy leaves a pickup that grants ammo for the gun in hand
	var m := Game.missions
	w.switch_to(&"scatter", true)
	w.reserve = 0
	var gm := Game.enemies as EnemyManager
	var pk0: int = m.pickups.size()
	WeaponLadder.on_chapter_done(0)
	TestLib.check(WeaponDefs.is_unlocked(&"revolver"), "finishing chapter 1 rewards the spike revolver")
	m.drop_weapon(&"scatter", p.global_position + Vector3(0.5, 0.0, 0.5))
	TestLib.check(m.pickups.size() == pk0 + 1, "a weapon pickup is on the ground")
	for _i in 40:
		await TestLib.frames(host, 3)
		if m.pickups.size() == pk0:
			break
	TestLib.check(w.reserve > 0, "walking over the pickup restocks the dry scatter (%d)" % w.reserve)
	TestMode.god = false
	main.queue_free()
	await TestLib.frames(host, 2)
