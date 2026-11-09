extends RefCounted
## Wave 108 (owner round 5: Halo-inspired energy weapons with ORIGINAL names, destructive heavies, every COD / GTA category): the ENERGY family (plasma pistol with overcharge, plasma repeater, sticky-crystal
## rifle, beam rifle, energy blade with lunge, gravity hammer with shockwave, rocket-pod launcher), the BLAST class (railgun, chain-gun, cluster missile, napalm launcher, singularity cannon, orbital strike
## beacon, guided missile launcher), throwing knives, the sticky plasma grenade, the spike grenade, and the three gadgets (deployable turret, shield emitter, jetpack boost module).
##  * data: every one has a MODEL, a PICTURE (small and large), STATS, its own SOUND, a ROLE in the missions, TWO fire modes, a price and a way to unlock it; generic names only; DPS inside the balance band;
##    the catalogue shows each once (at most 12 tiles a page); the weapon wheel has the ENERGY and BLAST wedges and the discs do not overlap; every classic category of the roster still exists;
##  * the real Player, PlayerWeapon, Throwables, Gadgets and EnemyManager: every weapon fires, and every mechanic does what its card says (counters, never frame counts).
## Run: tools/test.sh tests/test_energy_destructive_weapons.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const DT := 1.0 / 60.0
const ENERGY: Array[StringName] = [&"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod"]
const BLAST: Array[StringName] = [&"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker"]
const NEW_WEAPONS: Array[StringName] = [&"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker", &"tknife"]
const NEW_GEAR: Array[StringName] = [&"plasma", &"spike", &"turret", &"shield", &"jetpack"]
## every category the owner listed (docs/DESIGN.md, WORLD_EXPANSION.md): roster slot ids
const CLASSIC: Array[StringName] = [&"pistol", &"heavy_pistol", &"revolver", &"machine_pistol", &"smg_1", &"ar_1", &"battle_rifle", &"lmg", &"minigun", &"pump_shotgun", &"auto_shotgun", &"sniper", &"amr", &"crossbow",
		&"rpg", &"guided_launcher", &"grenade_launcher", &"frag", &"c4", &"mine", &"flamethrower", &"katana", &"knife", &"throwing_knives"]
## real or protected names that must not appear in a weapon's name
const BRANDS: Array[String] = ["HALO", "SPARTAN", "NEEDLER", "COVENANT", "MJOLNIR", "WARTHOG", "SPARTAN LASER", "PLASMA RIFLE", "GLOCK", "BERETTA", "UZI", "AK-47", "M4A1", "BARRETT", "RPG-7", "TASER"]

class PushVehicle extends StaticBody3D:
	var hp := 800.0
	var hits: Array[float] = []
	var pushes := 0

	func _ready() -> void:
		add_to_group(&"vehicle")
		collision_layer = Game.L_VEHICLE
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.9, 1.3, 4.5)
		cs.shape = box
		cs.position = Vector3(0.0, 0.65, 0.0)
		add_child(cs)

	func damage(amount: float) -> void:
		hits.append(amount)
		hp -= amount

	func apply_impulse(_j: Vector3, _at: Vector3) -> void:
		pushes += 1

	func dealt() -> float:
		var t := 0.0
		for h in hits:
			t += h
		return t


var e := Env.new()
var p: Player
var w: PlayerWeapon
var root: Node3D
var em: EnemyManager
var stub_missions := Stubs.StubMissions.new()
var collapsed := 0
var blasts: Array[Dictionary] = []


func run(host: Node) -> void:
	seed(108)
	_data()
	_ladder_and_shop()
	_catalogue_and_wheel()
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
	Game.exploded.connect(func(pos: Vector3, radius: float) -> void: blasts.append({"pos": pos, "radius": radius}))

	await _every_weapon_fires()
	await _plasma_pistol()
	await _repeater()
	await _crystal_spiker()
	await _beam_rifle()
	await _energy_blade()
	await _gravity_hammer()
	await _rocket_pod()
	await _railgun()
	await _chaingun()
	await _cluster_missile()
	await _napalm()
	await _singularity()
	await _orbital()
	await _seeker()
	await _throwing_knives()
	await _grenades()
	await _gadgets()

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
	collapsed = 0
	blasts.clear()


func _target(type: StringName, at: Vector3, frozen := true, aware := false) -> Drone:
	var d := em.spawn(type, at, aware)
	d.set_physics_process(not frozen)
	await e.frames(2)
	return d


func _aim(d: Drone, up := 0.0) -> void:
	p.camera_rig.aim_at(d.center() + Vector3(0.0, up, 0.0))


func _aim_ground(pos: Vector3) -> void:
	p.camera_rig.aim_at(Vector3(pos.x, 0.0, pos.z))


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
	w.arms.reset()


## Pull the trigger until a round has left (spin-up weapons need a moment), at most `limit` seconds.
func _fire_one(limit := 2.5) -> bool:
	var s0 := w.shots_fired
	for i in int(limit / DT):
		w.tick(DT, true, false, false, false)
		if w.shots_fired > s0:
			return true
	return false


## Pull the trigger until one MELEE swing has gone (melee does not count shots_fired).
func _swing(limit := 2.0) -> bool:
	var c0 := w.combo_hits
	for i in int(limit / DT):
		w.tick(DT, true, false, false, false)
		if w.combo_hits > c0:
			return true
	return false


## Hold a charge weapon to full and release it.
func _charge_shot() -> bool:
	var s0 := w.shots_fired
	for i in 200:
		w.tick(DT, true, false, false, false)
		if w.charge >= 1.0:
			break
	w.tick(DT, false, false, false, false)
	return w.shots_fired > s0


## Tick and wait real frames until `cond` holds (a projectile flew, a timer ran down); false after `frames` frames.
func _until(cond: Callable, frames := 360) -> bool:
	for i in frames:
		w.tick(DT, false, false, false, false)
		await e.frames(1)
		if cond.call():
			return true
	return false


func _wait_collapse(c0: int, frames := 300) -> bool:
	var ok: bool = await _until(func() -> bool: return collapsed > c0, frames)
	await e.frames(2)
	return ok


# --- data ------------------------------------------------------------------------------------------------------------

func _data() -> void:
	# the roster has every classic category and every new slot
	var slots := {}
	for en: Dictionary in WeaponRoster.ENTRIES:
		slots[en["slot"]] = true
	var missing: Array[String] = []
	for sl in CLASSIC:
		if not slots.has(sl):
			missing.append(String(sl))
	TestLib.check(missing.is_empty(), "every classic category still exists: pistols, revolvers, SMGs, rifles, LMG, minigun, shotguns, snipers, AMR, crossbow, RPG, GUIDED launcher, grenades, C4, mines, flamethrower, blades, throwing knives (missing %s)" % str(missing))
	var no_model: Array[String] = []
	var no_icon: Array[String] = []
	var no_big: Array[String] = []
	var no_stats: Array[String] = []
	var no_sound: Array[String] = []
	var no_role: Array[String] = []
	var no_unlock: Array[String] = []
	var no_price: Array[String] = []
	var no_alt: Array[String] = []
	var snd_names := {}
	for id in NEW_WEAPONS + NEW_GEAR:
		var m := WeaponRoster.model(id)
		if m == null or m.get_surface_count() < 1 or m.get_aabb().size.length() < 0.08:
			no_model.append(String(id))
		if WeaponRoster.icon(id) == null:
			no_icon.append(String(id))
		if WeaponDefs.DEFS.has(id) and (ItemIcons.weapon_large(id) == null or not ResourceLoader.exists(ItemIcons.path("wl", id))):
			no_big.append(String(id))
		if WeaponRoster.stat_lines(id).size() < 2:
			no_stats.append(String(id))
		var snd := WeaponRoster.sound(id)
		if snd == &"" or Sfx.variants_of(snd).is_empty():
			no_sound.append("%s -> %s" % [id, snd])
		snd_names[snd] = true
		if WeaponRoster.role(id).length() < 12:
			no_role.append(String(id))
		if WeaponRoster.unlock(id) == "" or not WeaponRoster.obtainable(id):
			no_unlock.append(String(id))
		var price := WeaponDefs.price(id) if WeaponDefs.DEFS.has(id) else Economy.gear_price(id)
		if price <= 0:
			no_price.append(String(id))
		if WeaponDefs.DEFS.has(id) and not WeaponDefs.ALTS.has(id):
			no_alt.append(String(id))
	TestLib.check(no_model.is_empty(), "each has a 3D model (missing %s)" % str(no_model))
	TestLib.check(no_icon.is_empty() and no_big.is_empty(), "each has a picture, the weapons a big loadout picture too (%s %s)" % [str(no_icon), str(no_big)])
	TestLib.check(no_stats.is_empty(), "each has a stats card (%s)" % str(no_stats))
	TestLib.check(no_sound.is_empty() and snd_names.size() == NEW_WEAPONS.size() + NEW_GEAR.size(), "each has its own shipped sound (%s, %d different names)" % [str(no_sound), snd_names.size()])
	TestLib.check(no_role.is_empty(), "each has a plain role in the missions (%s)" % str(no_role))
	TestLib.check(no_unlock.is_empty() and no_price.is_empty(), "each has a way to get it and a shop price (%s %s)" % [str(no_unlock), str(no_price)])
	TestLib.check(no_alt.is_empty(), "every weapon has a second fire mode of its own (%s)" % str(no_alt))
	var alt_names := {}
	for id in NEW_WEAPONS:
		alt_names[String(WeaponDefs.alt_of(id)["name"]) + str(WeaponDefs.alt_of(id)["kind"])] = true
		TestLib.check(String(WeaponDefs.alt_of(id)["name"]) != "" and WeaponRoster.sound(id) != &"shot", "%s: alt-fire %s, sound %s" % [id, WeaponDefs.alt_of(id)["name"], WeaponRoster.sound(id)])
	TestLib.check(alt_names.size() >= 11, "the second modes differ (%d kinds)" % alt_names.size())
	# classes and tabs
	TestLib.check(WeaponDefs.CLASS_ORDER.has(&"energy") and WeaponDefs.CLASS_ORDER.has(&"blast") and WeaponDefs.in_class(&"energy").size() == 7 and WeaponDefs.in_class(&"blast").size() == 7, "ENERGY and BLAST are weapon classes of seven")
	TestLib.check(WeaponDefs.in_class(&"melee").has(&"tknife"), "the throwing knives sit in MELEE")
	var tabs := WeaponRoster.tabs()
	var tab_names: Array[String] = []
	for t: Dictionary in tabs:
		tab_names.append(String(t["name"]))
	TestLib.check(tab_names.has("ENERGY") and tab_names.has("BLAST") and tab_names.has("GADGETS") and tab_names.has("EXPLOSIVES"), "the roster tabs: %s" % str(tab_names))
	# original names
	var branded: Array[String] = []
	for id in NEW_WEAPONS + NEW_GEAR:
		var nm := (String(WeaponDefs.title(id)) if WeaponDefs.DEFS.has(id) else String(Gear.title(id))).to_upper()
		for b in BRANDS:
			if nm.contains(b):
				branded.append("%s %s" % [id, nm])
	for id in WeaponDefs.IDS:
		for b in BRANDS:
			if String(WeaponDefs.title(id)).to_upper().contains(b):
				branded.append("%s %s" % [id, WeaponDefs.title(id)])
	TestLib.check(branded.is_empty(), "no trademarked names anywhere in the roster (%s)" % str(branded))
	# power: the sustained damage of every new weapon stays in the balance band
	var base := BalanceModel.weapon_dps(&"carbine")
	var off: Array[String] = []
	for id in NEW_WEAPONS:
		var k := BalanceModel.weapon_dps(id) / base
		if k < BalanceModel.WEAPON_BAND.x or k > BalanceModel.WEAPON_BAND.y:
			off.append("%s %.2f" % [id, k])
	TestLib.check(off.is_empty(), "sustained damage inside the balance band (%s)" % str(off))
	# traits are readable
	TestLib.check(WeaponRoster.trait_text(&"espike").contains("CRYSTALS") and WeaponRoster.trait_text(&"emaul").contains("SHOCKWAVE") and WeaponRoster.trait_text(&"epod").contains("ROCKETS")
			and WeaponRoster.trait_text(&"cmissile").contains("BOMBLETS") and WeaponRoster.trait_text(&"napalm").contains("FIRE") and WeaponRoster.trait_text(&"orbital").contains("ORBITAL")
			and WeaponRoster.trait_text(&"seeker").contains("CROSSHAIR") and WeaponRoster.trait_text(&"ebeam").contains("WALL"), "the card says what is special about each")
	# throwables and gadgets
	TestLib.check(Gear.THROW_IDS.has(&"plasma") and Gear.THROW_IDS.has(&"spike") and Gear.GADGET_IDS.has(&"turret") and Gear.GADGET_IDS.has(&"shield") and Gear.GADGET_IDS.has(&"jetpack"), "the grenades and the gadgets are in Gear")
	TestLib.check(bool(Gear.def(&"plasma")["stick"]) and int(Gear.def(&"spike")["spikes"]) >= 12, "the plasma grenade sticks, the spike grenade throws a ring of spikes")


func _ladder_and_shop() -> void:
	var on_ladder := {}
	for en: Dictionary in WeaponLadder.LADDER:
		on_ladder[en["id"]] = en
	var missing: Array[String] = []
	var bad: Array[String] = []
	for id in NEW_WEAPONS:
		if not on_ladder.has(id):
			missing.append(String(id))
			continue
		var en: Dictionary = on_ladder[id]
		match StringName(en["route"]):
			WeaponLadder.CRATE:
				var i := int(en["arg"])
				if i < 0 or i >= WeaponLadder.CRATES.size() or StringName(WeaponLadder.CRATES[i]["weapon"]) != id:
					bad.append("%s crate %d" % [id, i])
			WeaponLadder.DROP:
				if not EnemyTypes.TYPES.has(StringName(en["arg"])):
					bad.append("%s drop %s" % [id, en["arg"]])
			WeaponLadder.MISSION:
				if int(en["arg"]) < 0 or int(en["arg"]) >= BalanceModel.CHAPTERS:
					bad.append("%s chapter" % id)
	TestLib.check(missing.is_empty() and bad.is_empty(), "the unlock ladder carries all 15 (missing %s, bad %s)" % [str(missing), str(bad)])
	# ladder order = power order: the cheap ones first
	var last := 0
	var ordered := true
	for id in [&"tknife", &"eplasma", &"espike", &"epod", &"cmissile", &"railgun", &"orbital"]:
		var at := WeaponLadder.LADDER.find(on_ladder[id])
		ordered = ordered and at > last
		last = at
	TestLib.check(ordered, "light weapons come first on the ladder, the orbital strike last")
	var crates_ok := true
	var seen := {}
	for i in WeaponLadder.CRATES.size():
		var c: Dictionary = WeaponLadder.CRATES[i]
		var key := str(c["g"]) + str(c["sx"]) + str(c["sz"])
		crates_ok = crates_ok and not seen.has(key)
		seen[key] = true
	TestLib.check(crates_ok and WeaponLadder.CRATES.size() >= 25, "%d crates, none on another's corner" % WeaponLadder.CRATES.size())
	# price ladder: the heavy things cost more than the light ones
	TestLib.check(WeaponDefs.price(&"orbital") > WeaponDefs.price(&"railgun") and WeaponDefs.price(&"railgun") > WeaponDefs.price(&"eplasma") and WeaponDefs.price(&"eplasma") > WeaponDefs.price(&"tknife"), "prices rise with power")
	TestLib.check(Economy.gear_price(&"plasma") > 0 and Economy.gear_price(&"spike") > 0 and Economy.gear_price(&"turret") > Economy.gear_price(&"jetpack"), "grenades and gadgets are in the shop")


func _catalogue_and_wheel() -> void:
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
	TestLib.check(WeaponsScreen.PAGE_TITLES.has("ENERGY WEAPONS") and WeaponsScreen.PAGE_TITLES.has("BLAST WEAPONS") and WeaponsScreen.page_of(&"railgun") == 5 and WeaponsScreen.page_of(&"eplasma") == 4, "ENERGY and BLAST have their own catalogue pages")
	WeaponDefs.reset_unlocked()
	for id in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var items := WeaponWheel.items()
	var energy_wedge := false
	var blast_wedge := false
	for it in items:
		energy_wedge = energy_wedge or (it["id"] == &"energy" and int(it["owned"]) == 7 and String(it["cname"]) == "ENERGY")
		blast_wedge = blast_wedge or (it["id"] == &"blast" and int(it["owned"]) == 7 and String(it["cname"]) == "BLAST")
	TestLib.check(items.size() == 10 and energy_wedge and blast_wedge, "the weapon wheel has ten class wedges, ENERGY and BLAST with seven weapons each")
	var wheel := RadialWheel.new()
	wheel.open_at(&"weapon", items, Vector2(900.0, 400.0), 1.0)
	var gap := 1.0e9
	for i in items.size():
		for j in range(i + 1, items.size()):
			gap = minf(gap, wheel.item_centre(i).distance_to(wheel.item_centre(j)))
	TestLib.check(gap >= RadialWheel.ITEM_R * 2.0 + 4.0, "the ten discs of the wheel do not overlap (closest %.0f px, a disc is %.0f)" % [gap, RadialWheel.ITEM_R * 2.0])
	TestLib.check(LoadoutScreen.owned_classes().size() == 10 and LoadoutScreen.owned_classes().has(&"energy") and LoadoutScreen.owned_classes().has(&"blast"), "the loadout has a tab for each of the ten classes")
	var too_many := false
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		too_many = too_many or WeaponDefs.in_class(cls).size() > 8
	TestLib.check(not too_many, "no class has more than the 8 tiles of a loadout page")
	WeaponDefs.reset_unlocked()


# --- the real player -------------------------------------------------------------------------------------------------

func _every_weapon_fires() -> void:
	var failed: Array[String] = []
	for id in NEW_WEAPONS:
		await _fresh()
		var d := await _target(&"heavy", Vector3(16.0, 0.0, 0.0))
		_equip(id)
		_aim(d)
		var kind := String(WeaponDefs.def(id)["kind"])
		var s0 := w.shots_fired
		var c0 := w.combo_hits
		var ok := false
		match kind:
			"charge":
				ok = _charge_shot()
			"melee":
				ok = _swing()
			_:
				ok = _fire_one()
		await e.frames(1)
		if not ok or w.shots_fired < s0:
			failed.append("%s (%s)" % [id, kind])
		_idle(0.3)
	TestLib.check(failed.is_empty(), "each of the %d new weapons fires when the trigger is pulled (failed %s)" % [NEW_WEAPONS.size(), str(failed)])
	em.clear()


func _plasma_pistol() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_equip(&"eplasma")
	_aim(d)
	var hp0 := d.hp
	var s0 := w.arms.splashes
	_fire_one()
	TestLib.check(w.arms.splashes == s0 + 1 and hp0 - d.hp > 19.0, "the EMBER PLASMA PISTOL pops a small plasma blast where it hits (%.0f damage, %d pops)" % [hp0 - d.hp, w.arms.splashes - s0])
	var shield := await _target(&"shield", Vector3(14.0, 0.0, 6.0), true, true)
	_aim(shield)
	var sh0 := shield.hp
	_idle(0.5)
	_fire_one()
	TestLib.check(shield.hp < sh0, "plasma goes through a shield soldier's shield (%.0f damage)" % (sh0 - shield.hp))
	_idle(0.5)
	w.tick(5.0, false, false, false, false)
	_aim(d)
	var a0 := w.ammo
	var hp1 := d.hp
	var ok := w.alt_fire(false)
	TestLib.check(ok and w.arms.oc_bolts == 1 and a0 - w.ammo == int(WeaponDefs.alt_of(&"eplasma")["cost"]), "OVERCHARGE spends %d rounds on one slow plasma ball" % (a0 - w.ammo))
	var c0 := collapsed
	TestLib.check(await _wait_collapse(c0), "the ball explodes on impact")
	TestLib.check(w.arms.blast_stuns >= 1 and d.is_disabled() and hp1 - d.hp > 50.0, "and its blast stuns the squad it hits (%.0f damage, stunned %s)" % [hp1 - d.hp, d.is_disabled()])
	TestLib.check(blasts.size() > 0 and float(blasts[blasts.size() - 1]["radius"]) >= 4.0, "a 4.5 m coloured blast went off")
	em.clear()


func _repeater() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(12.0, 0.0, 0.0))
	_equip(&"erepeat")
	_aim(d)
	var a0 := w.ammo
	var hp0 := d.hp
	_pull(1.0)
	var fired := a0 - w.ammo
	TestLib.check(fired >= 10 and hp0 - d.hp > 40.0, "the PULSE REPEATER sprays %d rounds in a second (%.0f damage)" % [fired, hp0 - d.hp])
	TestLib.check(w.gauge() > 0.05, "and its heat gauge climbs (%.2f)" % w.gauge())
	em.clear()


func _crystal_spiker() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_equip(&"espike")
	_aim(d)
	var hp0 := d.hp
	for i in 5:
		_fire_one()
		_idle(0.2)
	var pops0 := w.arms.crystal_pops
	TestLib.check(w.arms.crystals_on(d) == 5 and w.arms.crystal_pops == pops0, "five hits plant five crystals and nothing blows yet (%d)" % w.arms.crystals_on(d))
	_fire_one()
	await e.frames(1)
	var dealt := hp0 - d.hp
	TestLib.check(w.arms.crystal_pops == pops0 + 1 and dealt > 75.0 * 0.7 + 6.0 * 12.0 * 0.8 and w.arms.crystals_on(d) == 0, "the sixth crystal supercombines: the blast adds about 75 (%.0f in all)" % dealt)
	em.clear()
	# SHATTER pops a partial set
	await _fresh()
	var d2 := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_equip(&"espike")
	_aim(d2)
	var hp1 := d2.hp
	for i in 3:
		_fire_one()
		_idle(0.2)
	var direct := hp1 - d2.hp
	var pops1 := w.arms.crystal_pops
	w.tick(5.0, false, false, false, false)
	TestLib.check(w.alt_fire(false) and w.arms.crystal_pops == pops1 + 1 and hp1 - d2.hp > direct + 20.0, "SHATTER pops the three crystals at once (%.0f -> %.0f damage)" % [direct, hp1 - d2.hp])
	TestLib.check(not w.alt_fire(false), "and there is nothing left to pop")
	em.clear()


func _beam_rifle() -> void:
	await _fresh()
	var wall := Fixture.add_box(root, Vector3(8.0, 3.0, 0.0), Vector3(1.0, 6.0, 20.0))
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_equip(&"ebeam")
	_aim(d)
	var hp0 := d.hp
	var wh0 := w.wall_hits
	var sp0 := w.arms.splashes
	var b0 := blasts.size()
	var fired := _charge_shot()
	await e.frames(1)
	TestLib.check(fired and w.wall_hits == wh0 + 1 and hp0 - d.hp > 80.0, "the PRISM BEAM RIFLE shoots through a wall and still hits for %.0f" % (hp0 - d.hp))
	TestLib.check(w.arms.splashes == sp0 + 1 and blasts.size() > b0, "and burns a blast where it ends (%d blasts)" % (blasts.size() - b0))
	wall.queue_free()
	await e.frames(3)
	em.clear()


func _energy_blade() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(2.4, 0.0, 0.0))
	_equip(&"eblade")
	_aim(d)
	var hp0 := d.hp
	var c0 := w.combo_hits
	_swing()
	TestLib.check(w.combo_hits == c0 + 1 and hp0 - d.hp > 30.0, "the ION BLADE cuts for %.0f" % (hp0 - d.hp))
	var t0 := w.burn_ticks
	var hpb := d.hp
	_idle(1.4)
	TestLib.check(w.burn_ticks >= t0 + 2 and d.hp < hpb, "and the cut keeps burning (%d ticks)" % (w.burn_ticks - t0))
	em.clear()
	await _fresh()
	var far := await _target(&"heavy", Vector3(6.0, 0.0, 0.0))
	_equip(&"eblade")
	_aim(far)
	w.tick(5.0, false, false, false, false)
	var x0 := p.global_position.x
	var hp1 := far.hp
	var ok := w.alt_fire(false)
	await e.frames(2)
	TestLib.check(ok and p.global_position.x > x0 + 2.0 and hp1 - far.hp > 40.0, "LUNGE crosses the gap and strikes (%.1f m, %.0f damage)" % [p.global_position.x - x0, hp1 - far.hp])
	em.clear()
	p.teleport_to(Vector3(0.0, 0.05, 0.0))


func _gravity_hammer() -> void:
	await _fresh()
	var a := await _target(&"heavy", Vector3(3.0, 0.0, 0.0))
	var b := await _target(&"heavy", Vector3(5.5, 0.0, 3.2))
	var car := PushVehicle.new()
	root.add_child(car)
	car.global_position = Vector3(5.0, 0.0, -3.5)
	await e.frames(2)
	_equip(&"emaul")
	_aim(a)
	var ha := a.hp
	var hb := b.hp
	var bx := b.global_position
	var n0 := w.arms.shockwaves
	var b0 := blasts.size()
	_swing()
	await e.frames(1)
	TestLib.check(w.arms.shockwaves == n0 + 1 and ha - a.hp > 70.0, "the TREMOR MAUL hits the one in front for %.0f" % (ha - a.hp))
	TestLib.check(hb - b.hp > 15.0 and b.global_position.distance_to(bx) > 0.5, "and its shockwave hurts and shoves the one beside him (%.0f damage, moved %.1f m)" % [hb - b.hp, b.global_position.distance_to(bx)])
	TestLib.check(car.pushes >= 1 and car.dealt() > 20.0, "and shoves and dents the car beside the squad (%d pushes, %.0f damage)" % [car.pushes, car.dealt()])
	TestLib.check(blasts.size() > b0 and float(blasts[b0]["radius"]) >= 6.0, "the 6.5 m wave breaks props like any blast (%d blasts)" % (blasts.size() - b0))
	w.tick(5.0, false, false, false, false)
	var far := await _target(&"heavy", Vector3(-7.5, 0.0, 0.0))
	var hf := far.hp
	var s1 := w.arms.shockwaves
	TestLib.check(w.alt_fire(false) and w.arms.shockwaves == s1 + 1 and hf - far.hp > 15.0, "GROUND SLAM sends a 9 m wave all round the hero (%.0f damage behind him)" % (hf - far.hp))
	car.queue_free()
	em.clear()


func _rocket_pod() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(20.0, 0.0, 0.0))
	_equip(&"epod")
	_aim_ground(d.global_position)
	var a0 := w.ammo
	var s0 := w.arms.salvo_rockets
	var c0 := collapsed
	w.tick(DT, true, false, false, false)
	TestLib.check(a0 - w.ammo == 3 and w.arms.salvo_rockets == s0 + 3 and w.grenades_active() == 3, "one pull of the HORNET ROCKET POD sends three rockets (%d rounds, %d in the air)" % [a0 - w.ammo, w.grenades_active()])
	var hp0 := d.hp
	TestLib.check(await _until(func() -> bool: return collapsed >= c0 + 3), "all three explode")
	TestLib.check(hp0 - d.hp > 45.0, "and the squad on the ground takes %.0f" % (hp0 - d.hp))
	w.tick(5.0, false, false, false, false)
	var a1 := w.ammo
	var f0 := w.arms.salvo_rockets
	TestLib.check(w.alt_fire(false) and w.arms.salvo_rockets == f0 + 6 and a1 - w.ammo == 6 and w.grenades_active() == 6, "ALL PODS fires six at once (%d in the air)" % w.grenades_active())
	await _until(func() -> bool: return collapsed >= c0 + 9)
	em.clear()


func _railgun() -> void:
	await _fresh()
	var wall := Fixture.add_box(root, Vector3(8.0, 3.0, 0.0), Vector3(1.0, 6.0, 20.0))
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 0.0))
	_equip(&"railgun")
	_aim(d)
	var hp0 := d.hp
	var wh0 := w.wall_hits
	var fired := _charge_shot()
	await e.frames(1)
	TestLib.check(fired and w.wall_hits == wh0 + 1 and hp0 - d.hp > 150.0, "the COIL RAILGUN goes through the wall and hits for %.0f" % (hp0 - d.hp))
	wall.queue_free()
	await e.frames(3)
	em.clear()
	await _fresh()
	var tank := Fixture.add_vehicle(root, Vector3(18.0, 0.0, 0.0), Vector3(3.0, 2.4, 7.0), true, false) as Node3D
	await e.frames(2)
	_equip(&"railgun")
	p.camera_rig.aim_at(Vector3(18.0, 1.0, 0.0))
	var b0 := blasts.size()
	_charge_shot()
	await e.frames(1)
	var hits: Array = tank.get(&"hits")
	var total := 0.0
	for h in hits:
		total += float(h)
	TestLib.check(total > 400.0 and blasts.size() > b0, "and one round wrecks a tank-sized vehicle (%.0f damage, %d blasts)" % [total, blasts.size() - b0])
	tank.queue_free()
	await e.frames(2)


func _chaingun() -> void:
	await _fresh()
	var car := Fixture.add_vehicle(root, Vector3(14.0, 0.0, 0.0), Vector3(1.9, 1.3, 4.5), true, false) as Node3D
	await e.frames(2)
	_equip(&"chaingun")
	p.camera_rig.aim_at(Vector3(14.0, 0.8, 0.0))
	var a0 := w.ammo
	var sp0 := w.arms.splashes
	_pull(1.6)
	var shots := a0 - w.ammo
	var hits: Array = car.get(&"hits")
	var total := 0.0
	for h in hits:
		total += float(h)
	var pops := w.arms.splashes - sp0
	TestLib.check(shots >= 15 and pops >= shots / 3 - 1 and pops <= shots / 3 + 1, "the STORM CHAINGUN makes every third round explosive (%d rounds, %d blasts)" % [shots, pops])
	TestLib.check(total > 100.0, "and chews a car for %.0f" % total)
	car.queue_free()
	await e.frames(2)
	em.clear()


func _cluster_missile() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(22.0, 0.0, 0.0))
	var near := await _target(&"heavy", Vector3(22.0, 0.0, 6.0))
	_equip(&"cmissile")
	_aim_ground(d.global_position)
	var hp0 := d.hp
	var hn := near.hp
	var c0 := collapsed
	w.tick(DT, true, false, false, false)
	TestLib.check(await _wait_collapse(c0), "the HIVE CLUSTER MISSILE explodes on impact")
	TestLib.check(await _until(func() -> bool: return w.arms.cluster_blasts >= 6), "and six bomblets follow, one after another (%d)" % w.arms.cluster_blasts)
	TestLib.check(hp0 - d.hp > 70.0 and hn - near.hp > 20.0, "the whole car park takes it (%.0f and %.0f)" % [hp0 - d.hp, hn - near.hp])
	# AIRBURST opens the missile in the air
	await _fresh()
	var d2 := await _target(&"heavy", Vector3(22.0, 0.0, 0.0))
	_equip(&"cmissile")
	_aim_ground(d2.global_position)
	var c1 := collapsed
	var ok := w.alt_fire(false)
	var at: Array[Vector3] = []
	w.grenade_collapsed.connect(func(pos: Vector3) -> void: at.append(pos), CONNECT_ONE_SHOT)
	var landed := await _wait_collapse(c1)
	var up := at[0].y if not at.is_empty() else 0.0
	TestLib.check(ok and landed and up > 2.0, "AIRBURST bursts above the target (%.1f m up)" % up)
	await _until(func() -> bool: return w.arms.cluster_blasts >= 6)
	em.clear()


func _napalm() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(18.0, 0.0, 0.0))
	_equip(&"napalm")
	_aim_ground(d.global_position)
	var hp0 := d.hp
	var c0 := collapsed
	w.tick(DT, true, false, false, false)
	TestLib.check(await _wait_collapse(c0), "the CINDER NAPALM LAUNCHER lands")
	TestLib.check(w.arms.fire_zones_made >= 1 and w.arms.zones_live() >= 1, "and leaves a burning field on the ground")
	var ok: bool = await _until(func() -> bool: return w.arms.fire_ticks >= 3 and w.burn_ticks >= 2, 600)
	TestLib.check(ok and hp0 - d.hp > 40.0, "whoever stands in it burns (%.0f damage, %d burn ticks)" % [hp0 - d.hp, w.burn_ticks])
	w.tick(5.0, false, false, false, false)
	var z0 := w.arms.fire_zones_made
	TestLib.check(w.alt_fire(false) and w.arms.fire_zones_made == z0 + 5, "WALL OF FIRE lays five fields in a line (%d)" % (w.arms.fire_zones_made - z0))
	em.clear()


func _singularity() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(16.0, 0.0, 0.0))
	var side := await _target(&"heavy", Vector3(16.0, 0.0, 9.0))
	_equip(&"sing")
	_aim_ground(d.global_position)
	var hp0 := d.hp
	var z0 := side.global_position.z
	var c0 := collapsed
	w.tick(DT, true, false, false, false)
	var pulled := false
	for i in 400:
		w.tick(DT, false, false, false, false)
		await e.frames(1)
		if w.grenades_active() > 0 and absf(side.global_position.z - z0) > 1.0:
			pulled = true
		if collapsed > c0:
			break
	await e.frames(2)
	TestLib.check(pulled, "the VOID SINGULARITY CANNON drags a squad 9 m away toward its well")
	TestLib.check(collapsed == c0 + 1 and hp0 - d.hp > 250.0, "then collapses for %.0f in an 11 m violet blast" % (hp0 - d.hp))
	TestLib.check(blasts.size() > 0 and float(blasts[blasts.size() - 1]["radius"]) >= 10.0, "(blast radius %.0f m)" % float(blasts[blasts.size() - 1]["radius"]))
	em.clear()
	await _fresh()
	var near := await _target(&"heavy", Vector3(5.0, 0.0, 0.0))
	_equip(&"sing")
	var x0 := near.global_position.x
	var s0 := w.arms.shockwaves
	TestLib.check(w.alt_fire(false) and w.arms.shockwaves == s0 + 1 and near.global_position.x > x0 + 1.0, "REPULSE throws the squad away from the hero (%.1f m)" % (near.global_position.x - x0))
	em.clear()


func _orbital() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(20.0, 0.0, 0.0))
	var car := PushVehicle.new()
	root.add_child(car)
	car.global_position = Vector3(20.0, 0.0, 7.0)
	await e.frames(2)
	_equip(&"orbital")
	_aim_ground(d.global_position)
	var hp0 := d.hp
	var hero_hp := p.hp
	w.tick(DT, true, false, false, false)
	var planted: bool = await _until(func() -> bool: return w.arms.beacons_planted == 1, 200)
	TestLib.check(planted and w.arms.live_beams() == 1 and w.arms.strikes_pending() == 1, "the ORBITAL STRIKE BEACON lands and a column of light rises")
	TestLib.check(d.hp >= hp0 - 1.0 and w.arms.beacon_strikes == 0, "nothing has fallen yet: there is time to run")
	var struck: bool = await _until(func() -> bool: return w.arms.beacon_strikes >= 3, 900)
	TestLib.check(struck, "three strikes fall from orbit (%d)" % w.arms.beacon_strikes)
	TestLib.check(hp0 - d.hp > 250.0 and car.dealt() > 300.0, "the squad dies and the car beside it is wrecked (%.0f, %.0f damage)" % [hp0 - d.hp, car.dealt()])
	TestLib.check(p.hp >= hero_hp - 0.01, "and the hero, 20 m away, is not hurt")
	await _until(func() -> bool: return w.arms.live_beams() == 0, 200)
	TestLib.check(w.arms.live_beams() == 0 and w.arms.strikes_pending() == 0, "the column fades out")
	car.queue_free()
	em.clear()
	await _fresh()
	_equip(&"orbital")
	_aim_ground(Vector3(24.0, 0.0, 0.0))
	var f0 := w.arms.salvo_rockets
	TestLib.check(w.alt_fire(false) and w.arms.salvo_rockets == f0 + 3 and w.grenades_active() == 3, "BARRAGE throws three beacons for one round")
	await _until(func() -> bool: return w.arms.beacons_planted >= 3, 300)
	TestLib.check(w.arms.beacons_planted >= 3, "all three plant (%d)" % w.arms.beacons_planted)
	await _until(func() -> bool: return w.arms.beacon_strikes >= 9, 1200)
	em.clear()


func _seeker() -> void:
	await _fresh()
	var d := await _target(&"heavy", Vector3(26.0, 0.0, 12.0))
	_equip(&"seeker")
	p.camera_rig.aim_at(Vector3(26.0, 0.0, -10.0))                  # aim 22 m away from the target ...
	var hp0 := d.hp
	var c0 := collapsed
	w.tick(DT, true, false, false, false)
	for i in 6:
		w.tick(DT, false, false, false, false)
		await e.frames(1)
	_aim(d)                                                         # ... then steer the missile onto him
	TestLib.check(await _wait_collapse(c0, 600), "the SEEKER explodes")
	TestLib.check(w.arms.guided_steers >= 5 and hp0 - d.hp > 60.0, "the round followed the crosshair onto a target 22 m off its first line (%d steering frames, %.0f damage)" % [w.arms.guided_steers, hp0 - d.hp])
	em.clear()
	await _fresh()
	var d2 := await _target(&"heavy", Vector3(20.0, 0.0, 0.0))
	_equip(&"seeker")
	_aim(d2)
	var c1 := collapsed
	var hp1 := d2.hp
	w.tick(5.0, false, false, false, false)
	var ok := w.alt_fire(false)
	var steered := w.arms.guided_steers
	var top := 0.0
	for i in 600:
		w.tick(DT, false, false, false, false)
		await e.frames(1)
		for g in w._grenades:
			if int(g["state"]) == 0:
				top = maxf(top, (g["pos"] as Vector3).y)
		if collapsed > c1:
			break
	await e.frames(2)
	TestLib.check(ok and collapsed == c1 + 1 and top > 8.0 and w.arms.guided_steers > steered and hp1 - d2.hp > 60.0, "TOP ATTACK climbs (%.0f m) and dives onto the target (%.0f damage)" % [top, hp1 - d2.hp])
	em.clear()


func _throwing_knives() -> void:
	await _fresh()
	var target := await _target(&"heavy", Vector3(30.0, 0.0, 0.0))
	var by := await _target(&"operative", Vector3(-12.0, 0.0, 0.0))
	by.aware = false
	_equip(&"tknife")
	_aim(target)
	var hp0 := target.hp
	_fire_one()
	await e.frames(2)
	TestLib.check(hp0 - target.hp > 25.0, "a THROWING KNIFE hits for %.0f at 30 m" % (hp0 - target.hp))
	TestLib.check(not by.aware and float(by.get(&"suspicion")) <= 0.0001, "and it is silent: the guard 12 m behind the hero does not hear it")
	w.tick(5.0, false, false, false, false)
	var a0 := w.ammo
	TestLib.check(w.alt_fire(false) and a0 - w.ammo >= 1, "FAN OF KNIVES throws a handful")
	_idle(1.0)
	em.clear()


func _grenades() -> void:
	await _fresh()
	var th: Throwables = p.throwables
	TestLib.check(th != null and th.count(&"plasma") == 2 and th.count(&"spike") == 3, "the hero carries two sticky novas and three spike grenades")
	# STICKY NOVA on an enemy
	var d := await _target(&"heavy", Vector3(10.0, 0.0, 0.0))
	_aim_ground(Vector3(11.5, 0.0, 0.0))                              # grenades fly at the world point under the crosshair: just behind him, so the arc passes through him
	var hp0 := d.hp
	var n0 := th.detonations
	var st0 := th.stuck_on_targets
	TestLib.check(th.throw(&"plasma"), "a sticky nova is thrown")
	for _i in 200:
		await e.frames(1)
		if th.detonations > n0:
			break
	await e.frames(2)
	TestLib.check(th.stuck_on_targets == st0 + 1 and th.detonations == n0 + 1 and hp0 - d.hp > 100.0, "it sticks to the enemy and blows on him for %.0f" % (hp0 - d.hp))
	em.clear()
	# ... and on a vehicle
	await _fresh()
	var car := PushVehicle.new()
	root.add_child(car)
	car.global_position = Vector3(10.0, 0.0, 0.0)
	await e.frames(2)
	p.camera_rig.aim_at(Vector3(10.0, 0.8, 0.0))
	var n1 := th.detonations
	var st1 := th.stuck_on_targets
	TestLib.check(th.throw(&"plasma"), "a second nova is thrown at a car")
	for _i in 200:
		await e.frames(1)
		if th.detonations > n1:
			break
	await e.frames(2)
	TestLib.check(th.stuck_on_targets == st1 + 1 and car.dealt() > 200.0, "it sticks to the car and wrecks it (%.0f damage)" % car.dealt())
	car.queue_free()
	await e.frames(2)
	em.clear()
	# SPIKE GRENADE: a ring of spikes through the room, a wall stops them
	await _fresh()
	var near := await _target(&"heavy", Vector3(9.0, 0.0, 0.0))
	var behind := await _target(&"heavy", Vector3(15.0, 0.0, 0.0))
	var wall := Fixture.add_box(root, Vector3(12.0, 3.0, 0.0), Vector3(1.0, 6.0, 12.0))
	var close := await _target(&"heavy", Vector3(9.0, 0.0, 3.5))
	await e.frames(2)
	_aim_ground(Vector3(9.0, 0.0, 1.5))
	var hn := near.hp
	var hb := behind.hp
	var hc := close.hp
	var n2 := th.detonations
	var sp0 := th.spike_hits
	TestLib.check(th.throw(&"spike"), "a spike grenade is thrown")
	for _i in 200:
		await e.frames(1)
		if th.detonations > n2:
			break
	await e.frames(2)
	TestLib.check(th.spike_hits > sp0 and hn - near.hp > 20.0 and hc - close.hp > 20.0, "the spikes hit both enemies in the room (%.0f and %.0f damage)" % [hn - near.hp, hc - close.hp])
	TestLib.check(hb - behind.hp < 1.0, "and the wall stops them for the one behind it")
	wall.queue_free()
	await e.frames(2)
	em.clear()


func _gadgets() -> void:
	await _fresh()
	var g: Gadgets = p.gadgets
	p.energy = p.max_energy
	# SENTRY TURRET
	var d := await _target(&"heavy", Vector3(14.0, 0.0, 6.0), true, false)
	TestLib.check(g.use(&"turret") and g.turret_alive(), "the SENTRY TURRET drops and stands")
	var hp0 := d.hp
	for i in 300:
		await e.frames(1)
		if g.turret_hits >= 3:
			break
	TestLib.check(g.turret_hits >= 3 and hp0 - d.hp > 30.0, "and holds the spot on its own: %d hits, %.0f damage" % [g.turret_hits, hp0 - d.hp])
	em.clear()
	# SHIELD EMITTER
	p.energy = p.max_energy
	p.hp = p.max_hp
	TestLib.check(g.use(&"shield") and g.shield_up(), "the SHIELD EMITTER raises its dome")
	var before := p.hp
	p.damage(30.0)
	TestLib.check(p.hp == before and g.shield_absorbed >= 29.9, "a hit inside the dome is eaten (%.0f absorbed)" % g.shield_absorbed)
	for i in 20:
		p.damage(30.0)
	TestLib.check(not g.shield_up() and p.hp < before, "and when its 400 are used up the dome is gone and the hero takes damage again")
	# BOOST MODULE
	p.energy = p.max_energy
	await e.prep(Vector3(0.0, 0.05, 0.0))
	var y0 := p.global_position.y
	TestLib.check(g.use(&"jetpack") and g.boosts >= 1, "the BOOST MODULE fires")
	var top := y0
	for i in 140:
		await e.frames(1)
		top = maxf(top, p.global_position.y)
	TestLib.check(top > y0 + 2.5, "and lifts the hero %.1f m, enough for a low roof" % (top - y0))
