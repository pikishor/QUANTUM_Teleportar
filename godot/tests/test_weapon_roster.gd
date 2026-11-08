extends RefCounted
## The weapon roster of docs/DESIGN.md (every top COD / GTA weapon type with generic names, plus six quantum weapons) against the real game objects.
##  * data (WeaponRoster): every slot the owner asked for exists; every entry has a MODEL, a PICTURE, STATS, a SOUND (a shipped file) and a way to get it (starter, crate, mission, drop, boss, shop);
##    the ladder is consistent (one route per weapon, valid crates / chapters / bosses / enemy types), classes and catalogue pages hold every weapon exactly once, no real brand names;
##  * the real Player, PlayerWeapon and EnemyManager: every new weapon fires, and the mechanics of the roster work (shooting through walls, stun and stasis, burning, the blink alt-fire,
##    the entangle link, the echo burst, the collapse blast, the silent crossbow, the flash grenade).
## Run: tools/test.sh tests/test_weapon_roster.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const DT := 1.0 / 60.0
## what the owner asked for, slot by slot
const WANTED: Array[StringName] = [&"pistol", &"heavy_pistol", &"revolver", &"machine_pistol", &"smg_1", &"smg_2", &"ar_1", &"ar_2", &"ar_3", &"battle_rifle", &"lmg", &"minigun", &"pump_shotgun",
		&"auto_shotgun", &"sniper", &"amr", &"crossbow", &"rpg", &"grenade_launcher", &"frag", &"smoke", &"flash", &"c4", &"mine", &"flamethrower", &"stun_gun", &"katana", &"knife", &"bat",
		&"quantum_1", &"quantum_2", &"quantum_3", &"quantum_4", &"quantum_5", &"quantum_6"]
const NEW_WEAPONS: Array[StringName] = [&"magnum", &"mpistol", &"ranger", &"bullpup", &"lmg", &"amr", &"xbow", &"flame", &"stun", &"katana", &"bat", &"qsuper", &"qlink", &"qcollapse", &"qblink", &"qphase", &"qstasis"]
## trademark names that must not appear in a weapon's name (generic names only)
const BRANDS: Array[String] = ["GLOCK", "BERETTA", "COLT", "DESERT", "EAGLE", "UZI", "MP5", "MP7", "AK-47", "AK47", "KALASHNIKOV", "M4A1", "M16", "AR-15", "AR15", "SCAR", "BARRETT", "REMINGTON",
		"MOSSBERG", "WINCHESTER", "RUGER", "SMITH", "WESSON", "TASER", "MINIGUN M134", "RPG-7", "RPG7", "C-4", "CLAYMORE"]

var e := Env.new()
var p: Player
var w: PlayerWeapon
var root: Node3D
var em: EnemyManager
var stub_missions := Stubs.StubMissions.new()
var collapsed := 0


func run(host: Node) -> void:
	seed(33)
	_data()
	_ladder()
	_classes_and_pages()
	await e.setup(host)
	p = e.p
	root = e.root
	w = p.weapon
	p.max_hp = 1.0e6
	Fixture.release_inputs()
	Game.world = Stubs.StubWorld.new()
	root.add_child(Game.world)
	root.add_child(stub_missions)
	Game.missions = stub_missions
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	em.patrol_groups().clear()
	await e.frames(3)
	w.grenade_collapsed.connect(func(_pos: Vector3) -> void: collapsed += 1)

	await _every_new_weapon_fires()
	await _through_walls()
	await _stun_and_stasis()
	await _burning()
	await _blink()
	await _entangle_link()
	await _echo_burst()
	await _collapse_cannon()
	await _silent_crossbow()
	await _flash_grenade()

	Game.world = null
	Game.missions = null
	Game.heat = 0.0
	WeaponDefs.reset_unlocked()
	Upgrades.reset()
	await e.teardown()


# --- helpers ---------------------------------------------------------------------------------------------------------

func _fresh() -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	Upgrades.reset()
	WeaponDefs.reset_unlocked()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	await e.prep(Vector3(0.0, 0.05, 0.0))
	w.reset()
	w.switch_to(&"carbine", true)
	w.reset()


func _target(type: StringName, at: Vector3, frozen := true, aware := false) -> Drone:
	var d := em.spawn(type, at, aware)
	d.set_physics_process(not frozen)
	await e.frames(2)
	return d


func _aim(d: Drone, up := 0.0) -> void:
	p.camera_rig.aim_at(d.center() + Vector3(0.0, up, 0.0))


func _pull(seconds: float, aiming := false) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, true, false, aiming, false)


func _idle(seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, false, false, false, false)


func _equip(id: StringName) -> void:
	w.switch_to(id, true)
	w.ammo = w.mag
	w.fire_t = 0.0
	w.swap_t = 0.0
	w.reload_t = 0.0


# --- data ------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var slots := {}
	for en: Dictionary in WeaponRoster.ENTRIES:
		slots[en["slot"]] = true
	var missing: Array[String] = []
	for s in WANTED:
		if not slots.has(s):
			missing.append(String(s))
	TestLib.check(missing.is_empty() and WeaponRoster.ENTRIES.size() == WANTED.size(), "the roster has every slot the owner asked for (%d, missing %s)" % [WeaponRoster.ENTRIES.size(), str(missing)])
	var ids := WeaponRoster.ids()
	var uniq := {}
	for id in ids:
		uniq[id] = true
	TestLib.check(uniq.size() == ids.size(), "every roster slot is a different object")
	var no_model: Array[String] = []
	var no_icon: Array[String] = []
	var no_stats: Array[String] = []
	var no_sound: Array[String] = []
	var no_unlock: Array[String] = []
	var bad_class: Array[String] = []
	for id in ids:
		var m := WeaponRoster.model(id)
		if m == null or m.get_surface_count() < 1 or m.get_aabb().size.length() < 0.05:
			no_model.append(String(id))
		if WeaponRoster.icon(id) == null:
			no_icon.append(String(id))
		var lines := WeaponRoster.stat_lines(id)
		if lines.size() < 2:
			no_stats.append(String(id))
		var snd := WeaponRoster.sound(id)
		if snd == &"" or Sfx.variants_of(snd).is_empty():
			no_sound.append("%s -> %s" % [id, snd])
		if WeaponRoster.unlock(id) == "" or not WeaponRoster.obtainable(id):
			no_unlock.append(String(id))
		if WeaponRoster.tab_of(id) == &"":
			bad_class.append(String(id))
	TestLib.check(no_model.is_empty(), "every entry has a 3D model (missing %s)" % str(no_model))
	TestLib.check(no_icon.is_empty(), "every entry has a picture in assets/icons (missing %s)" % str(no_icon))
	TestLib.check(no_stats.is_empty(), "every entry has stats a player can read (missing %s)" % str(no_stats))
	TestLib.check(no_sound.is_empty(), "every entry has a shipped sound (missing %s)" % str(no_sound))
	TestLib.check(no_unlock.is_empty(), "every entry has a way to get it (missing %s)" % str(no_unlock))
	TestLib.check(bad_class.is_empty(), "every entry sits on a tab")
	# the large picture of the loadout for every weapon
	var no_big: Array[String] = []
	for id in WeaponDefs.IDS:
		if ItemIcons.weapon_large(id) == null or ItemIcons.path("wl", id) == "" or not ResourceLoader.exists(ItemIcons.path("wl", id)):
			no_big.append(String(id))
	TestLib.check(no_big.is_empty(), "every weapon has its big loadout picture (missing %s)" % str(no_big))
	# each new weapon has its own shot sound, not a copy of another
	var new_snd := {}
	for id in NEW_WEAPONS:
		new_snd[WeaponDefs.def(id)["snd"]] = true
	TestLib.check(new_snd.size() == NEW_WEAPONS.size(), "the %d new weapons have %d different sounds" % [NEW_WEAPONS.size(), new_snd.size()])
	# generic names only
	var branded: Array[String] = []
	for id in WeaponDefs.IDS:
		var nm := String(WeaponDefs.title(id)).to_upper()
		for b in BRANDS:
			if nm.contains(b):
				branded.append("%s %s" % [id, nm])
	TestLib.check(branded.is_empty(), "no real brand names (%s)" % str(branded))
	# the C4 numbers in Gear are the numbers of the Charges node
	var c4 := Gear.def(&"c4")
	TestLib.check(is_equal_approx(float(c4["radius"]), Charges.RADIUS) and is_equal_approx(float(c4["damage"]), Charges.ENEMY_DAMAGE) and int(c4["max"]) == Charges.MAX_LIVE and is_equal_approx(float(c4["range"]), Charges.REACH), "the C4 card shows the real numbers of the charge")
	TestLib.check(WeaponRoster.unlock(&"c4") == "ALWAYS CARRIED" and WeaponRoster.unlock(&"pistol") == "STARTER", "starters and the charge say how they are owned")
	var fl := Gear.def(&"flash")
	TestLib.check(Gear.THROW_IDS.has(&"flash") and float(fl["disable"]) > 1.0 and Economy.THROW_PRICE.has(&"flash"), "the flash grenade is a throwable with a price")
	# traits are readable plain words for the mechanics
	TestLib.check(WeaponRoster.trait_text(&"amr").contains("WALL") and WeaponRoster.trait_text(&"qstasis").contains("FREEZES") and WeaponRoster.trait_text(&"flame").contains("FIRE")
			and WeaponRoster.trait_text(&"xbow").contains("SILENT") and WeaponRoster.trait_text(&"qblink").contains("TELEPORT") and WeaponRoster.trait_text(&"carbine") == "", "the card says what is special")


func _ladder() -> void:
	var seen := {}
	var dup: Array[String] = []
	var bad: Array[String] = []
	var chapters := {}
	for en: Dictionary in WeaponLadder.LADDER:
		var id: StringName = en["id"]
		if seen.has(id):
			dup.append(String(id))
		seen[id] = true
		if not WeaponDefs.DEFS.has(id) or WeaponDefs.STARTERS.has(id):
			bad.append("%s unknown or a starter" % id)
		match StringName(en["route"]):
			WeaponLadder.CRATE:
				var i := int(en["arg"])
				if i < 0 or i >= WeaponLadder.CRATES.size() or StringName(WeaponLadder.CRATES[i]["weapon"]) != id:
					bad.append("%s crate %d" % [id, i])
			WeaponLadder.MISSION:
				var ch := int(en["arg"])
				if ch < 0 or ch >= BalanceModel.CHAPTERS or chapters.has(ch):
					bad.append("%s chapter %d" % [id, ch])
				chapters[ch] = true
			WeaponLadder.BOSS:
				if not ContractTypes.BOSS_DROPS.has(int(en["arg"]) - 1) or ContractTypes.BOSS_DROPS[int(en["arg"]) - 1] != id:
					bad.append("%s boss sector %d" % [id, int(en["arg"])])
			WeaponLadder.DROP:
				if not EnemyTypes.TYPES.has(StringName(en["arg"])):
					bad.append("%s drops from unknown %s" % [id, en["arg"]])
	TestLib.check(dup.is_empty() and bad.is_empty(), "the unlock ladder is consistent (dups %s, bad %s)" % [str(dup), str(bad)])
	var not_on: Array[String] = []
	for id in WeaponDefs.IDS:
		if not WeaponDefs.STARTERS.has(id) and not seen.has(id):
			not_on.append(String(id))
	TestLib.check(not_on.is_empty(), "every weapon that is not a starter is on the ladder (missing %s)" % str(not_on))
	# crates: unique positions, every weapon crate's weapon is on the ladder with the crate route
	var pos := {}
	var same := false
	for i in WeaponLadder.CRATES.size():
		var key := str(WeaponLadder.CRATES[i]["g"]) + str(WeaponLadder.CRATES[i]["sx"]) + str(WeaponLadder.CRATES[i]["sz"])
		same = same or pos.has(key)
		pos[key] = true
	TestLib.check(not same and WeaponLadder.CRATES.size() >= 17, "%d crates, none on another's corner" % WeaponLadder.CRATES.size())
	TestLib.check(WeaponLadder.next_target() == &"marksman" and WeaponLadder.next_line().begins_with("NEXT"), "a next weapon is always on offer")


func _classes_and_pages() -> void:
	var counts := {}
	for id in WeaponDefs.IDS:
		var cls := WeaponDefs.class_of(id)
		counts[cls] = int(counts.get(cls, 0)) + 1
		TestLib.check(WeaponDefs.CLASS_ORDER.has(cls) and WeaponDefs.CLASS_NAMES.has(cls), "%s has a class tab" % id)
	var thin: Array[String] = []
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		if int(counts.get(cls, 0)) < 3:
			thin.append(String(cls))
	TestLib.check(thin.is_empty() and WeaponDefs.CLASS_ORDER.has(&"quantum") and int(counts.get(&"quantum", 0)) == 6, "every class tab has three or more weapons, QUANTUM has six (%s)" % str(counts))
	# every tab of the roster
	var tabs := WeaponRoster.tabs()
	var total := 0
	for t: Dictionary in tabs:
		total += (t["ids"] as Array).size()
	TestLib.check(tabs.size() == WeaponDefs.CLASS_ORDER.size() + 1 and total == WeaponRoster.ENTRIES.size(), "the roster is sorted into %d tabs with %d entries" % [tabs.size(), total])
	# the catalogue: every weapon, throwable, charge and gadget is on exactly one page, a page holds at most 12 tiles
	var on_page := {}
	var over := false
	for pg in WeaponsScreen.PAGES:
		var items := WeaponsScreen.page_items(pg)
		over = over or items.size() > 12
		for it: Dictionary in items:
			on_page[it["id"]] = int(on_page.get(it["id"], 0)) + 1
	var lost: Array[String] = []
	for id in WeaponDefs.IDS + Gear.THROW_IDS + Gear.CHARGE_IDS + Gear.GADGET_IDS:
		if int(on_page.get(id, 0)) != 1:
			lost.append(String(id))
	TestLib.check(not over and lost.is_empty() and WeaponsScreen.PAGE_TITLES.size() == WeaponsScreen.PAGES, "the catalogue shows everything once, at most 12 tiles a page (%s)" % str(lost))
	# the weapon wheel shows one wedge per class the hero owns: all eight with everything unlocked
	WeaponDefs.reset_unlocked()
	var starters := WeaponWheel.items().size()
	for id in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var all := WeaponWheel.items()
	TestLib.check(all.size() == WeaponDefs.CLASS_ORDER.size() and starters < all.size(), "the weapon wheel groups the weapons by class: %d wedges with everything, %d with the starters" % [all.size(), starters])
	var quantum_wedge := false
	for it in all:
		quantum_wedge = quantum_wedge or (it["id"] == &"quantum" and int(it["owned"]) == 6)
	TestLib.check(quantum_wedge, "the QUANTUM wedge holds the six quantum weapons")
	WeaponDefs.reset_unlocked()


# --- the real player -------------------------------------------------------------------------------------------------

func _every_new_weapon_fires() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(16.0, 0.0, 0.0))
	var failed: Array[String] = []
	for id in NEW_WEAPONS:
		await _fresh()
		d = await _target(&"heavy", Vector3(16.0, 0.0, 0.0))
		_equip(id)
		_aim(d)
		var kind := String(WeaponDefs.def(id)["kind"])
		var s0 := w.shots_fired
		var c0 := w.combo_hits
		var a0 := w.ammo
		w.tick(DT, true, false, false, false)
		await e.frames(1)
		var fired := w.combo_hits > c0 if kind == "melee" else (w.shots_fired > s0 and (w.ammo < a0 or kind == "throw"))
		if not fired:
			failed.append("%s (%s)" % [id, kind])
		_idle(0.2)
	TestLib.check(failed.is_empty(), "each of the %d new weapons fires when the trigger is pulled (failed %s)" % [NEW_WEAPONS.size(), str(failed)])
	em.clear()


func _through_walls() -> void:
	await _fresh()
	var wall := Fixture.add_box(root, Vector3(8.0, 3.0, 0.0), Vector3(1.0, 6.0, 20.0))
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_aim(d)
	_equip(&"carbine")
	var hp0 := d.hp
	_pull(0.01)
	TestLib.check(is_equal_approx(d.hp, hp0) and w.wall_hits == 0, "a carbine round stops in the wall")
	_equip(&"qphase")
	_aim(d)
	var wh0 := w.wall_hits
	hp0 = d.hp
	_pull(0.01)
	var dealt := hp0 - d.hp
	var want := float(WeaponDefs.def(&"qphase")["damage"]) * float(WeaponDefs.def(&"qphase")["wall_k"])
	TestLib.check(w.wall_hits == wh0 + 1 and dealt > 0.5 * want and dealt <= float(WeaponDefs.def(&"qphase")["crit"]), "the PHASE RIFLE goes through the wall and still hurts (%.1f of %.1f)" % [dealt, want])
	_equip(&"amr")
	_aim(d)
	hp0 = d.hp
	_pull(0.01)
	var amr_dealt := hp0 - d.hp
	TestLib.check(amr_dealt > 80.0, "the anti-material rifle shoots through the wall for %.0f" % amr_dealt)
	# the ground is not a wall: aim at the floor (the wall is gone) and the round stops there
	wall.queue_free()
	await e.frames(3)
	_equip(&"qphase")
	p.camera_rig.aim_at(Vector3(6.0, 0.0, 0.0))
	var wh1 := w.wall_hits
	_pull(0.01)
	TestLib.check(w.wall_hits == wh1 and absf(float(w.last_shot["hit"].y)) < 0.3, "a phase round does not fall through the floor")
	em.clear()


func _stun_and_stasis() -> void:
	for id: StringName in [&"stun", &"qstasis"]:
		await _fresh()
		var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
		_aim(d)
		_equip(id)
		var st0 := w.stuns
		_pull(0.01)
		TestLib.check(w.stuns == st0 + 1 and d.is_disabled(), "%s freezes the target it hits" % WeaponDefs.title(id))
		em.clear()
	await _fresh()
	var boss := await _target(&"overseer", Vector3(14.0, 0.0, 0.0))
	_aim(boss)
	_equip(&"qstasis")
	_pull(0.01)
	await e.frames(1)
	var boss_off := float(boss.get(&"_off")) if boss.get(&"_off") != null else 0.0
	TestLib.check(boss_off < float(WeaponDefs.def(&"qstasis")["stun"]) * 0.5, "a boss is frozen only for a moment (%.2f s)" % boss_off)
	em.clear()


func _burning() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(6.0, 0.0, 0.0))
	_aim(d)
	_equip(&"flame")
	var hp0 := d.hp
	_pull(0.3)
	var direct := hp0 - d.hp
	TestLib.check(direct > 10.0 and w.burn_ticks == 0, "the flamethrower hurts at once (%.0f)" % direct)
	var t0 := w.burn_ticks
	_idle(1.6)
	TestLib.check(w.burn_ticks >= t0 + 2 and hp0 - d.hp > direct + 4.0, "and the target keeps burning after the trigger is released (%d ticks, %.0f total)" % [w.burn_ticks - t0, hp0 - d.hp])
	var far := await _target(&"heavy", Vector3(28.0, 0.0, 0.0))
	_aim(far)
	var fhp := far.hp
	_pull(0.3)
	TestLib.check(fhp - far.hp < 1.0, "the flame reaches 15 m, not 28")
	em.clear()


func _blink() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(24.0, 0.0, 0.0))
	_aim(d)
	_equip(&"qblink")
	w.tick(5.0, false, false, false, false)
	var x0 := p.global_position.x
	var b0 := w.blinks
	var ok := w.alt_fire(false)
	await e.frames(2)
	TestLib.check(ok and w.blinks == b0 + 1 and p.global_position.x > x0 + 8.0 and p.global_position.x < 24.5, "the BLINK PISTOL alt-fire teleports the hero toward the crosshair (%.1f -> %.1f m)" % [x0, p.global_position.x])
	TestLib.check(not w.alt_fire(false), "and the blink has a cooldown")
	em.clear()
	p.teleport_to(Vector3(0.0, 0.05, 0.0))


func _entangle_link() -> void:
	await _fresh()
	var a := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	var b := await _target(&"heavy", Vector3(14.0, 0.0, -30.0))
	_aim(a)
	_equip(&"qlink")
	var ha := a.hp
	var hb := b.hp
	_pull(0.01)
	TestLib.check(ha - a.hp > 5.0 and hb - b.hp > 5.0 and w.chain_hits >= 1, "the ENTANGLE LINKER hurts a second enemy 30 m away as much as the first (%.1f and %.1f)" % [ha - a.hp, hb - b.hp])
	em.clear()


func _echo_burst() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_aim(d)
	_equip(&"qsuper")
	var a0 := w.ammo
	var hp0 := d.hp
	_pull(0.01)
	_idle(0.4)
	TestLib.check(a0 - w.ammo == 2 and hp0 - d.hp > 1.5 * float(WeaponDefs.def(&"qsuper")["damage"]) * 0.9, "the SUPERPOSITION GUN fires a shot and its echo (%d rounds, %.0f damage)" % [a0 - w.ammo, hp0 - d.hp])
	em.clear()


func _collapse_cannon() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(20.0, 0.0, 0.0))
	var near := await _target(&"heavy", Vector3(20.0, 0.0, 8.0))
	_aim(d)
	_equip(&"qcollapse")
	var c0 := collapsed
	var hp0 := d.hp
	var hn := near.hp
	_pull(0.01)
	for _i in 240:
		w.tick(DT, false, false, false, false)
		await e.frames(1)
		if collapsed > c0:
			break
	await e.frames(3)
	TestLib.check(collapsed == c0 + 1 and hp0 - d.hp > 100.0, "the COLLAPSE CANNON blows on impact for %.0f" % (hp0 - d.hp))
	TestLib.check(hn - near.hp > 30.0, "and its 10 m blast reaches the enemy 8 m away (%.0f)" % (hn - near.hp))
	em.clear()


func _silent_crossbow() -> void:
	for id: StringName in [&"carbine", &"xbow"]:
		await _fresh()
		var target := await _target(&"heavy", Vector3(60.0, 0.0, 0.0))
		var by := await _target(&"operative", Vector3(0.0, 0.0, -9.0))
		by.aware = false
		_aim(target)
		_equip(id)
		_pull(0.01)
		await e.frames(2)
		if id == &"carbine":
			TestLib.check(by.aware or float(by.get(&"suspicion")) > 0.0, "a carbine shot wakes the guard 9 m away")
		else:
			TestLib.check(not by.aware and float(by.get(&"suspicion")) <= 0.0001, "the SILENT CROSSBOW does not")
		em.clear()


func _flash_grenade() -> void:
	await _fresh()
	var th: Throwables = p.throwables
	TestLib.check(th != null and th.count(&"flash") == 3, "the hero carries three flash grenades")
	var d := await _target(&"operative", Vector3(10.0, 0.0, 0.0), true, true)
	var far := await _target(&"operative", Vector3(40.0, 0.0, 0.0), true, true)
	p.camera_rig.aim_at(Vector3(10.0, 0.0, 0.0))                     # at the ground beside the enemy: the crosshair point is the world, not the enemy
	var n0 := th.detonations
	var landed: Array[Vector3] = []
	th.detonated.connect(func(_id: StringName, pos: Vector3) -> void: landed.append(pos))
	TestLib.check(th.throw(&"flash"), "a flash grenade is thrown")
	for _i in 160:
		await e.frames(1)
		if th.detonations > n0:
			break
	await e.frames(2)
	TestLib.check(th.detonations == n0 + 1 and d.is_disabled() and not far.is_disabled(), "the flash freezes the enemies in range and only them")
	TestLib.check(not d.aware, "and they lose the hero")
	em.clear()
