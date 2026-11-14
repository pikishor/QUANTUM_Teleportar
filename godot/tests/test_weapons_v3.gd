extends RefCounted
## The weapon roster of wave 113 (125 new guns, melee, energy, quantum and exotic weapons on top of the 58 of the first rosters; the blast builder's weapons share the tables): counts per class and family,
## unique ids and names, no brand names, full definitions, models, pictures, sounds (three or more variations per class sound set), ways to get every weapon, HERO MODE, save and load, ammo types,
## the five attachment slots, the weapon browser and the two-level wheel, shops and drops, mechanics that really differ, and (in the real player scene) that EVERY new weapon equips, fires, reloads, uses
## its alt-fire and damages a dummy. Run: tools/test.sh tests/test_weapons_v3.gd (about a minute)

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")
const Roster := preload("res://tests/test_weapon_roster.gd")
const QVfx := preload("res://scripts/fx/quantum_vfx.gd")
const DT := 1.0 / 60.0
## The target of the brief per family (old and new weapons together): pistols 10, SMGs 10, assault rifles 14, battle rifles 6, carbines 6, DMR 6, sniper rifles 8, shotguns 10, LMG 6, heavy rotary 4,
## bows and crossbows 5, flamers and sprayers 4, melee 24, energy 14, quantum guns 8, exotic 6.
const FAMILY_TARGETS := {&"pistol": 10, &"smg": 10, &"assault": 14, &"battle": 6, &"carbine": 6, &"dmr": 6, &"sniper": 8, &"shotgun": 10, &"lmg": 6, &"rotary": 4, &"bow": 5, &"flamer": 4,
		&"melee": 24, &"energy": 14, &"quantum": 8, &"exotic": 6}
## status keys of a def -> the WeaponMech counter that must move when such a weapon hits a dummy
const STATUS_COUNTER := {"slow": "slows", "mark": "marks_made", "zap": "zaps", "chill": "chills", "dissolve": "dissolves", "knock": "knocks", "pull": "pulls"}
## keys that make a weapon's mechanic (the signature of a weapon is the sorted list of those it has, its alt-fire and its fire pattern)
const MECH_KEYS := ["opener", "final", "ramp", "knock", "slow", "mark", "zap", "chill", "dissolve", "ricochet", "pierce_n", "sunder", "p_heal", "p_refund", "p_hot", "steady", "crit_blast", "pull", "cone",
		"mist", "zoom_alt", "scope", "burst", "spin_up", "charge_time", "heat_per", "wall", "stun", "burn", "chain", "silent", "pierce_shield", "twin", "flame", "splash", "combo", "reach"]

var e := Env.new()
var p: Player
var w: PlayerWeapon
var root: Node3D
var em: EnemyManager
var stub_missions := Stubs.StubMissions.new()
var _new: Array = []


func run(host: Node) -> void:
	seed(113)
	_new = WeaponDefsV3.ids()
	Sfx.muted = true
	_counts()
	_identity()
	_definitions()
	_assets()
	_obtain()
	_hero_mode_and_save(host)
	_ammo_and_attachments()
	_distinct_mechanics()
	_browser_and_shops()
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
	await _every_weapon_in_the_scene()
	await _mechanics_in_play()
	await _wheel_with_the_player()
	Game.world = null
	Game.missions = null
	Game.heat = 0.0
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Attachments.reset()
	Upgrades.reset()


# --- data -----------------------------------------------------------------------------------------------------------------

func _counts() -> void:
	var by_fam := {}
	for id: StringName in WeaponDefs.all_ids():
		var fam := WeaponDefs.family_of(id)
		by_fam[fam] = int(by_fam.get(fam, 0)) + 1
	var short: Array[String] = []
	for fam: StringName in FAMILY_TARGETS:
		print("COUNT %-8s %2d (target %d)" % [fam, int(by_fam.get(fam, 0)), int(FAMILY_TARGETS[fam])])
		if int(by_fam.get(fam, 0)) < int(FAMILY_TARGETS[fam]):
			short.append("%s %d of %d" % [fam, int(by_fam.get(fam, 0)), int(FAMILY_TARGETS[fam])])
	TestLib.check(short.is_empty(), "every family reaches the target of the brief (short: %s)" % str(short))
	TestLib.check(_new.size() >= 100, "at least 100 NEW guns, melee and energy weapons (%d)" % _new.size())
	TestLib.check(WeaponDefs.all_ids().size() >= 58 + _new.size(), "the roster holds the 58 of the first rosters and all the new ones (%d)" % WeaponDefs.all_ids().size())
	var by_cls := {}
	for id: StringName in WeaponDefs.all_ids():
		by_cls[WeaponDefs.class_of(id)] = int(by_cls.get(WeaponDefs.class_of(id), 0)) + 1
	print("COUNT classes ", by_cls, " total ", WeaponDefs.all_ids().size())
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		TestLib.check(int(by_cls.get(cls, 0)) >= 3, "the %s class holds three or more weapons (%d)" % [cls, int(by_cls.get(cls, 0))])
		TestLib.check(WeaponDefs.ids_in_class(cls).size() == int(by_cls.get(cls, 0)), "ids_in_class(%s) lists them all" % cls)
	var seen := {}
	for fam: StringName in WeaponDefsV3.FAMILY_ORDER:
		for id: StringName in WeaponDefs.in_family(fam):
			seen[id] = int(seen.get(id, 0)) + 1
	var twice: Array[String] = []
	for id in seen:
		if int(seen[id]) != 1:
			twice.append(String(id))
	TestLib.check(twice.is_empty(), "no weapon is in two families")


func _identity() -> void:
	var ids := {}
	var names := {}
	var dup_id: Array[String] = []
	var dup_name: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		if ids.has(id):
			dup_id.append(String(id))
		ids[id] = true
		var nm := WeaponDefs.title(id)
		if names.has(nm):
			dup_name.append(nm)
		names[nm] = true
	TestLib.check(dup_id.is_empty(), "every weapon id is unique (%s)" % str(dup_id))
	TestLib.check(dup_name.is_empty(), "every weapon name is unique (%s)" % str(dup_name))
	var branded: Array[String] = []
	var plain := true
	for id: StringName in WeaponDefs.all_ids():
		var nm := WeaponDefs.title(id).to_upper()
		for b in Roster.BRANDS:
			if nm.contains(b):
				branded.append("%s %s" % [id, nm])
		plain = plain and nm == WeaponDefs.title(id) and nm.length() >= 4 and nm.length() <= 32
	TestLib.check(branded.is_empty(), "no real brand or trademark in any name (%s)" % str(branded))
	TestLib.check(plain, "every name is plain capitals between 4 and 32 characters")
	var no_role: Array[String] = []
	for id: StringName in _new:
		if String(WeaponDefs.def(id).get("role", "")).length() < 20 or String(WeaponDefs.def(id)["tag"]).length() != 3:
			no_role.append(String(id))
	TestLib.check(no_role.is_empty(), "every new weapon says in plain words what it is for and has a three letter tag (%s)" % str(no_role))


func _definitions() -> void:
	var bad: Array[String] = []
	for id: StringName in _new:
		var d := WeaponDefs.def(id)
		var kind := String(d["kind"])
		var why := ""
		if int(d["mag"]) < 1 or float(d["damage"]) <= 0.0 or float(d["interval"]) <= 0.0 or float(d["range"]) <= 0.0:
			why = "numbers"
		elif int(d["tier"]) < 1 or int(d["tier"]) > 6 or int(d["price"]) <= 0:
			why = "tier or price"
		elif not WeaponDefs.CLASS_ORDER.has(WeaponDefs.class_of(id)) or not WeaponDefsV3.FAMILY_ORDER.has(WeaponDefs.family_of(id)):
			why = "class or family"
		elif not (WeaponDefs.ALTS.has(id) and String(WeaponDefs.alt_of(id).get("name", "")) != "" and WeaponDefs.HIT_SND.has(id) and WeaponDefs.TILT.has(id)):
			why = "alt-fire, hit sound or tilt"
		elif not (Economy.WEAPON_PRICE.has(id) and BalanceModel.ACC.has(id) and AimAssist.STAGGER.has(id) and PlayerWeapon.AMMO_PACK.has(id) and ShopScreen.SHOP_WEAPONS.has(id)):
			why = "a table of another file misses it"
		elif not (QVfx.WEAPON_CLASS.has(id) and HeroAnimTuning.WEAPON_CLASS.has(id) and WeaponModels.SPEC.has(id)):
			why = "effects, animation or grips"
		elif kind == "melee" and (float(d["reach"]) <= 0.5 or (d["combo"] as Array).is_empty()):
			why = "melee numbers"
		elif not d.has("pattern") or (d["pattern"] as Array).is_empty():
			why = "recoil pattern"
		if why != "":
			bad.append("%s (%s)" % [id, why])
	TestLib.check(bad.is_empty(), "every new weapon has a full definition and a row in every table that names weapons (bad: %s)" % str(bad))
	var ammo_bad: Array[String] = []
	for id: StringName in _new:
		for k in WeaponDefs.def(id).get("ammo_types", [0]):
			if int(k) < 0 or int(k) >= WeaponDefs.AMMO_TYPES.size():
				ammo_bad.append(String(id))
	TestLib.check(ammo_bad.is_empty() and WeaponDefs.AMMO_TYPES.size() == 7, "seven ammo types (STANDARD HEAVY PIERCING INCENDIARY SHOCK EXPLOSIVE TIPPED QUANTUM) and every weapon names valid ones (%s)" % str(ammo_bad))
	var seen_types := {}
	for id: StringName in _new:
		for k in WeaponDefs.def(id).get("ammo_types", [0]):
			seen_types[int(k)] = true
	TestLib.check(seen_types.size() == 7, "every ammo type is carried by at least one weapon (%d of 7)" % seen_types.size())
	# stats a player can read
	var no_stats: Array[String] = []
	for id: StringName in _new:
		var card := WeaponStats.card(id, WeaponDefs.def(id))
		if (WeaponStats.lines(card) as Array).size() < 2 or (card["bars"] as Dictionary).size() < 4:
			no_stats.append(String(id))
	TestLib.check(no_stats.is_empty(), "every new weapon has a stats card with numbers and bars (%s)" % str(no_stats))


func _assets() -> void:
	var no_model: Array[String] = []
	var shapes := {}
	for id: StringName in _new:
		var m := WeaponModels.mesh(id)
		if m == null or m.get_surface_count() < 1:
			no_model.append(String(id))
			continue
		var bb := m.get_aabb()
		if bb.size.z < 0.12 or bb.size.z > 1.6 or bb.size.length() < 0.15:
			no_model.append("%s size %.2f" % [id, bb.size.z])
		shapes["%d_%d_%d" % [roundi(bb.size.x * 40.0), roundi(bb.size.y * 40.0), roundi(bb.size.z * 40.0)]] = true
	TestLib.check(no_model.is_empty(), "every new weapon has its own 3D model (%s)" % str(no_model))
	TestLib.check(shapes.size() >= int(_new.size() * 0.55), "the models differ in shape, not only in colour (%d silhouettes of %d)" % [shapes.size(), _new.size()])
	var no_icon: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		if ItemIcons.weapon(id) == null or ItemIcons.weapon_large(id) == null or not WeaponIcons.has_icon(id):
			no_icon.append(String(id))
	TestLib.check(no_icon.is_empty(), "every weapon has a small and a large picture (%s)" % str(no_icon))
	var silent: Array[String] = []
	var sets := {}
	for id: StringName in WeaponDefs.all_ids():
		var dd := WeaponDefs.def(id)
		var snd := StringName(dd.get("snd", &"" if String(dd["kind"]) == "throw" else &"shot"))      # a gun without its own sound set uses the old default shot, a launcher throws with its own sounds
		if snd == &"":
			continue
		var n := Sfx.variants_of(snd).size()
		if n < 1:
			silent.append("%s -> %s" % [id, snd])
		sets[snd] = n
	TestLib.check(silent.is_empty(), "no weapon is silent (%s)" % str(silent))
	var thin: Array[String] = []
	for id: StringName in _new:
		var snd := StringName(WeaponDefs.def(id)["snd"])
		if int(sets.get(snd, 0)) < 3:
			thin.append("%s %d" % [snd, int(sets.get(snd, 0))])
	TestLib.check(thin.is_empty(), "every class sound set of the roster has three or more variation layers (%s)" % str(thin))
	TestLib.check(sets.size() >= 16, "the roster has %d different sound sets" % sets.size())
	var hits_missing: Array[String] = []
	for id: StringName in _new:
		var hs: Array = WeaponDefs.hit_snd(id)
		if hs.size() < 3:
			hits_missing.append(String(id))
	TestLib.check(hits_missing.is_empty(), "every new weapon has a hit sound row")
	var layers: Array[String] = []
	for id: StringName in _new:
		var lay := StringName(WeaponDefs.def(id).get("layer", &""))
		if lay != &"" and Sfx.variants_of(lay).is_empty():
			layers.append("%s -> %s" % [id, lay])
	TestLib.check(layers.is_empty(), "an extra sound layer a weapon names exists (%s)" % str(layers))


func _obtain() -> void:
	var missing: Array[String] = []
	var routes := {}
	var no_text: Array[String] = []
	for id: StringName in _new:
		var en := WeaponLadder.entry(id)
		if en.is_empty():
			missing.append(String(id))
			continue
		routes[String(en["route"])] = int(routes.get(String(en["route"]), 0)) + 1
		if WeaponLadder.route_text(id) == "" or WeaponStats.where(id).is_empty():
			no_text.append(String(id))
	TestLib.check(missing.is_empty() and no_text.is_empty(), "every new weapon is on the ladder and says how to get it (%s %s)" % [str(missing), str(no_text)])
	print("ROUTES ", routes)
	TestLib.check(int(routes.get("crate", 0)) >= 20 and int(routes.get("drop", 0)) >= 20 and int(routes.get("shop", 0)) >= 20, "the roster is spread over crates, enemy drops and shops (%s)" % str(routes))
	var crates_bad: Array[String] = []
	var site_ids := {}                                                             # the places of the outskirts (no need to build the terrain to know their names)
	for sd in OutskirtsSites.DEFS + SettlementDefs.DEFS:
		site_ids[sd["id"]] = true
	var secret := 0
	var city := 0
	for en: Dictionary in WeaponLadder.LADDER:
		if StringName(en["route"]) != WeaponLadder.CRATE or not _new.has(en["id"]):
			continue
		var i := int(en["arg"])
		if i < 0 or i >= WeaponLadder.CRATES.size() or StringName(WeaponLadder.CRATES[i]["weapon"]) != en["id"]:
			crates_bad.append(String(en["id"]))
			continue
		var c: Dictionary = WeaponLadder.CRATES[i]
		if c.has("site"):
			secret += 1
			if not site_ids.has(StringName(c["site"])):
				crates_bad.append("%s site %s" % [en["id"], c["site"]])
		else:
			city += 1
	TestLib.check(crates_bad.is_empty(), "every crate of the roster holds its weapon and every secret cache stands at a real place (%s)" % str(crates_bad))
	TestLib.check(secret >= 8 and city >= 8, "secret caches in the outskirts (%d) and crates on the city corners (%d)" % [secret, city])
	var drops_bad: Array[String] = []
	for en: Dictionary in WeaponLadder.LADDER:
		if StringName(en["route"]) == WeaponLadder.DROP and _new.has(en["id"]) and not EnemyTypes.TYPES.has(StringName(en["arg"])):
			drops_bad.append("%s %s" % [en["id"], en["arg"]])
	TestLib.check(drops_bad.is_empty(), "every enemy that carries a weapon of the roster exists (%s)" % str(drops_bad))
	# ladder order follows the tiers: the cheap tiers come first
	var last_tier := 0
	var order_ok := true
	var first_new := -1
	for i in WeaponLadder.LADDER.size():
		var id: StringName = WeaponLadder.LADDER[i]["id"]
		if not _new.has(id):
			continue
		if first_new < 0:
			first_new = i
		var t := WeaponDefsV3.tier_of(id)
		order_ok = order_ok and t >= last_tier
		last_tier = t
	TestLib.check(order_ok, "the roster's part of the ladder runs from tier 1 to tier 6")
	# prices rise with the tier
	var sum_tier := {}
	var cnt_tier := {}
	for id: StringName in _new:
		var tr := WeaponDefsV3.tier_of(id)
		sum_tier[tr] = float(sum_tier.get(tr, 0.0)) + float(WeaponDefs.price(id))
		cnt_tier[tr] = int(cnt_tier.get(tr, 0)) + 1
	var tiers: Array = sum_tier.keys()
	tiers.sort()
	var rising := true
	var avgs: Array[String] = []
	for i in tiers.size():
		avgs.append("T%d %d" % [tiers[i], roundi(float(sum_tier[tiers[i]]) / float(cnt_tier[tiers[i]]))])
		if i > 0:
			rising = rising and float(sum_tier[tiers[i]]) / float(cnt_tier[tiers[i]]) > float(sum_tier[tiers[i - 1]]) / float(cnt_tier[tiers[i - 1]])
	TestLib.check(tiers.size() == 6 and rising, "six tiers whose average price rises (%s)" % str(avgs))


func _hero_mode_and_save(host: Node) -> void:
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	var locked: Array[String] = []
	for id: StringName in _new:
		if WeaponDefs.is_unlocked(id):
			locked.append(String(id))
	TestLib.check(locked.is_empty() and WeaponDefs.unlocked == WeaponDefs.STARTERS, "a new hero owns the seven starters and none of the roster")
	WeaponDefs.hero_mode = true
	var open := true
	for id: StringName in WeaponDefs.all_ids():
		open = open and WeaponDefs.is_unlocked(id)
	TestLib.check(open and WeaponDefs.owned_in_class(&"rifle").size() == WeaponDefs.in_class(&"rifle").size(), "HERO MODE unlocks every weapon at once")
	WeaponDefs.hero_mode = false
	TestLib.check(not WeaponDefs.is_unlocked(&"a_pillar"), "and takes nothing from the profile when it is switched off")
	var prog := Progress.new()
	host.add_child(prog)
	prog.path = "user://test_weapons_v3_save.cfg"
	prog.new_campaign()
	TestLib.check(prog.grant_weapon(&"a_pillar") and prog.grant_weapon(&"m_arcsabre") and prog.grant_weapon(&"q_ppistol") and not prog.grant_weapon(&"a_pillar"), "granting a weapon of the roster unlocks it once")
	WeaponBrowser.reset()
	WeaponBrowser.toggle_favourite(&"a_pillar")
	WeaponBrowser.note_used(&"m_arcsabre")
	Attachments.reset()
	Attachments.give(&"foregrip")
	Attachments.give(&"laser")
	TestLib.check(Attachments.equip(&"a_pillar", &"foregrip") and Attachments.equip(&"a_pillar", &"laser"), "parts of the new slots equip")
	TestLib.check(prog.save_file(), "saved")
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Attachments.reset()
	TestLib.check(not WeaponDefs.is_unlocked(&"a_pillar") and not WeaponBrowser.is_favourite(&"a_pillar") and Attachments.part_in(&"a_pillar", &"grip") == &"", "wiped")
	TestLib.check(prog.load_file(), "loaded")
	TestLib.check(WeaponDefs.is_unlocked(&"a_pillar") and WeaponDefs.is_unlocked(&"m_arcsabre") and WeaponDefs.is_unlocked(&"q_ppistol"), "the unlocked weapons of the roster come back")
	TestLib.check(WeaponBrowser.is_favourite(&"a_pillar") and WeaponBrowser.recent.has(&"m_arcsabre"), "favourites and recent weapons come back")
	TestLib.check(Attachments.part_in(&"a_pillar", &"grip") == &"foregrip" and Attachments.part_in(&"a_pillar", &"laser") == &"laser", "fitted parts of the new slots come back")
	prog.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_weapons_v3_save.cfg"))
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	Attachments.reset()


func _ammo_and_attachments() -> void:
	TestLib.check(Attachments.SLOTS.size() == 5 and Attachments.SLOTS.has(&"optic") and Attachments.SLOTS.has(&"grip") and Attachments.SLOTS.has(&"laser"), "five attachment slots: optic, muzzle, grip, magazine, laser")
	var labels: Array[String] = []
	for sl in Attachments.SLOTS:
		labels.append(Attachments.slot_label(sl))
	TestLib.check(labels == ["OPTIC", "MUZZLE", "GRIP", "MAGAZINE", "LASER"], "the slots are called %s" % str(labels))
	TestLib.check(Attachments.IDS.size() >= 21 and AttachmentPartsV3.IDS.size() == 12, "21 parts (%d)" % Attachments.IDS.size())
	var part_bad: Array[String] = []
	for part: StringName in Attachments.IDS:
		var pd: Dictionary = Attachments.PARTS[part]
		if not Attachments.SLOTS.has(StringName(pd["slot"])) or int(Economy.attachment_price(part)) <= 0 or String(AttachmentPartsV3.FX.get(part, "")) == "" or String(pd["name"]).length() < 3:
			part_bad.append(String(part))
	TestLib.check(part_bad.is_empty(), "every part has a slot, a price and a line that says what it does (%s)" % str(part_bad))
	# who may wear what
	TestLib.check(Attachments.slots_for_weapon(&"m_arcsabre").is_empty() and Attachments.slots_for_weapon(&"knife").is_empty() and Attachments.slots_for_weapon(&"rocket").is_empty(), "a blade or a launcher takes no parts")
	TestLib.check(Attachments.fits(&"quickgrip", &"p_spark") and not Attachments.fits(&"foregrip", &"p_spark") and Attachments.fits(&"foregrip", &"a_pillar"), "a pistol takes the quick grip but not the angled one")
	TestLib.check(Attachments.fits(&"choke", &"g_bulwark") and not Attachments.fits(&"choke", &"a_pillar"), "the choke is for shotguns")
	TestLib.check(not Attachments.fits(&"fastmag", &"bw_hunter") and Attachments.fits(&"fastmag", &"a_pillar"), "a bow has no magazine to change")
	for slot in Attachments.SLOTS:
		TestLib.check(not Attachments.parts_for_weapon(slot, &"carbine").is_empty(), "the carbine can wear something in the %s slot" % Attachments.slot_label(slot))
	# every new part changes a number in the direction it promises
	Attachments.reset()
	for part: StringName in Attachments.IDS:
		Attachments.give(part)
	var base: Dictionary = WeaponDefs.def(&"a_pillar")
	var shot_base: Dictionary = WeaponDefs.def(&"g_bulwark")
	var effects := {&"scope4": ["zoom", -1, &"a_pillar"], &"snap": ["spread_move", -1, &"a_pillar"], &"heavybore": ["damage", 1, &"a_pillar"], &"foregrip": ["kick", -1, &"a_pillar"],
			&"steadygrip": ["bloom", -1, &"a_pillar"], &"quickgrip": ["reload", -1, &"a_pillar"], &"fastmag": ["reload", -1, &"a_pillar"], &"armourmag": ["damage", 1, &"a_pillar"],
			&"laser": ["spread_hip", -1, &"a_pillar"], &"precision": ["spread_hip", -1, &"a_pillar"], &"choke": ["spread_hip", -1, &"g_bulwark"]}
	var wrong: Array[String] = []
	for part: StringName in effects:
		var wid: StringName = effects[part][2]
		Attachments.equip(wid, part)
		var eff := Attachments.effective(wid)
		var bd: Dictionary = shot_base if wid == &"g_bulwark" else base
		var key := String(effects[part][0])
		var dirn := int(effects[part][1])
		var delta := (float(eff[key]) - float(bd[key])) * float(dirn)
		if delta <= 0.0:
			wrong.append("%s %s %.4f -> %.4f" % [part, key, float(bd[key]), float(eff[key])])
		Attachments.unequip(wid, StringName(Attachments.PARTS[part]["slot"]))
	TestLib.check(wrong.is_empty(), "every new part moves its number the way its line says (wrong: %s)" % str(wrong))
	Attachments.equip(&"a_pillar", &"marker")
	TestLib.check(float(Attachments.effective(&"a_pillar").get("mark", 0.0)) > 0.0 and not WeaponDefs.def(&"a_pillar").has("mark"), "the MARKER LASER gives a weapon the mark perk")
	Attachments.unequip(&"a_pillar", &"laser")
	Attachments.equip(&"a_pillar", &"armourmag")
	TestLib.check(bool(Attachments.effective(&"a_pillar").get("pierce_shield", false)) and not bool(WeaponDefs.def(&"a_pillar").get("pierce_shield", false)), "the PIERCING MAG cracks shields")
	TestLib.check(WeaponDefs.def(&"a_pillar") == base, "the base definition never changes")
	# a part that does not fit is ignored when it is loaded from an old profile
	Attachments.reset()
	Attachments.from_save({"owned": ["foregrip", "reddot"], "equipped": {"p_spark": {"grip": "foregrip", "optic": "reddot"}}})
	TestLib.check(Attachments.part_in(&"p_spark", &"grip") == &"" and Attachments.part_in(&"p_spark", &"optic") == &"reddot", "a part the weapon cannot wear is dropped from a saved profile")
	Attachments.reset()


func _signature(id: StringName) -> String:
	var d := WeaponDefs.def(id)
	var bits: Array[String] = []
	for k: String in MECH_KEYS:
		if d.has(k) and not (d[k] is bool and not bool(d[k])):
			bits.append(k)
	bits.sort()
	bits.append("alt:%s" % String(WeaponDefs.alt_of(id).get("name", "")))
	bits.append("pat:%s" % str(d["pattern"]))
	bits.append("ammo:%s" % str(d.get("ammo_types", [])))
	bits.append("mag:%d iv:%.3f dmg:%.1f" % [int(d["mag"]), float(d["interval"]), float(d["damage"])])
	return "|".join(bits)


func _distinct_mechanics() -> void:
	var by_sig := {}
	var twins: Array[String] = []
	for id: StringName in _new:
		var sg := _signature(id)
		if by_sig.has(sg):
			twins.append("%s = %s" % [id, by_sig[sg]])
		by_sig[sg] = id
	TestLib.check(twins.is_empty(), "no weapon is a reskin of another: mechanics, alt-fire, pattern and numbers differ (%s)" % str(twins))
	# a family does not use one mechanic for everything: at least three different mechanic sets in every family of five or more new weapons
	var thin: Array[String] = []
	for fam: StringName in WeaponDefsV3.FAMILY_ORDER:
		var kits := {}
		var n := 0
		for id: StringName in _new:
			if WeaponDefs.family_of(id) != fam:
				continue
			n += 1
			var d := WeaponDefs.def(id)
			var bits: Array[String] = []
			for k: String in MECH_KEYS:
				if d.has(k) and not (d[k] is bool and not bool(d[k])):
					bits.append(k)
			bits.sort()
			kits["|".join(bits)] = true
		if n >= 5 and kits.size() < 3:
			thin.append("%s %d kits for %d weapons" % [fam, kits.size(), n])
	TestLib.check(thin.is_empty(), "each family has several mechanic sets, not one (%s)" % str(thin))
	var perks := {}
	for id: StringName in _new:
		for k: String in MECH_KEYS:
			if WeaponDefs.def(id).has(k):
				perks[k] = true
	TestLib.check(perks.size() >= 24, "the roster uses %d different mechanics" % perks.size())
	var alts := {}
	for id: StringName in _new:
		alts[String(WeaponDefs.alt_of(id)["kind"])] = true
	TestLib.check(alts.size() >= 12, "%d kinds of alt-fire" % alts.size())
	var scopes := {}
	for id: StringName in _new:
		scopes[int(float(WeaponDefs.def(id)["zoom"]))] = true
	TestLib.check(scopes.size() >= 7, "%d different ads zoom levels" % scopes.size())


func _browser_and_shops() -> void:
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	# pages: every weapon on exactly one page of its class, balanced, within the grid
	var on_page := {}
	var over := false
	var unbalanced := false
	var pages := WeaponBrowser.pages(true)
	for pg: Dictionary in pages:
		var ids: Array = pg["ids"]
		over = over or ids.size() > WeaponBrowser.PAGE or ids.is_empty()
		for id in ids:
			on_page[id] = int(on_page.get(id, 0)) + 1
	var lone: Array[String] = []
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var sizes: Array[int] = []
		for pg: Dictionary in pages:
			if pg["tab"] == cls:
				sizes.append((pg["ids"] as Array).size())
		if sizes.size() > 1:
			unbalanced = unbalanced or (sizes.max() - sizes.min()) > 1
			if sizes.min() < 3:
				lone.append(String(cls))
	var lost: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		if int(on_page.get(id, 0)) != 1:
			lost.append(String(id))
	TestLib.check(not over and lost.is_empty(), "every weapon is on exactly one page of the loadout, a page holds at most %d (%s)" % [WeaponBrowser.PAGE, str(lost)])
	TestLib.check(not unbalanced and lone.is_empty(), "the pages of a class are balanced: they differ by one weapon at most (small: %s)" % str(lone))
	# captions: at most 11 characters and different inside a class
	var long_caps: Array[String] = []
	var clash: Array[String] = []
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var caps := {}
		for id: StringName in WeaponDefs.in_class(cls):
			var cap := WeaponBrowser.caption(id)
			if cap.length() > WeaponBrowser.CAP_MAX or cap == "":
				long_caps.append("%s %s" % [id, cap])
			if caps.has(cap):
				clash.append("%s = %s (%s)" % [id, caps[cap], cap])
			caps[cap] = id
	TestLib.check(long_caps.is_empty() and clash.is_empty(), "every tile caption fits the tile and no two weapons of a class share one (%s %s)" % [str(long_caps), str(clash)])
	# favourites and recent
	TestLib.check(WeaponBrowser.toggle_favourite(&"a_pillar") and WeaponBrowser.is_favourite(&"a_pillar") and not WeaponBrowser.toggle_favourite(&"a_pillar") and not WeaponBrowser.is_favourite(&"a_pillar"), "a star toggles a favourite")
	for i in WeaponBrowser.FAV_MAX + 3:
		WeaponBrowser.toggle_favourite(WeaponDefs.all_ids()[i])
	TestLib.check(WeaponBrowser.favourites.size() == WeaponBrowser.FAV_MAX, "the favourites list holds %d at most" % WeaponBrowser.FAV_MAX)
	WeaponBrowser.reset()
	for i in 12:
		WeaponBrowser.note_used(WeaponDefs.all_ids()[i])
	TestLib.check(WeaponBrowser.recent.size() == WeaponBrowser.RECENT_MAX and WeaponBrowser.recent[0] == WeaponDefs.all_ids()[11], "RECENT keeps the last %d weapons, the newest first" % WeaponBrowser.RECENT_MAX)
	WeaponBrowser.note_used(WeaponDefs.all_ids()[8])
	TestLib.check(WeaponBrowser.recent[0] == WeaponDefs.all_ids()[8] and WeaponBrowser.recent.count(WeaponDefs.all_ids()[8]) == 1, "a weapon used again moves to the front")
	var tabs := WeaponBrowser.tabs(true)
	TestLib.check(tabs[0]["id"] == WeaponBrowser.RECENT and tabs.size() == WeaponDefs.CLASS_ORDER.size() + 1, "RECENT opens the tab list (and FAVOURITES when there are stars)")
	WeaponBrowser.toggle_favourite(&"m_phaseblade")
	tabs = WeaponBrowser.tabs(true)
	TestLib.check(tabs[0]["id"] == WeaponBrowser.FAV and tabs[1]["id"] == WeaponBrowser.RECENT, "FAVOURITES comes first, RECENT second")
	var rt := WeaponBrowser.to_save()
	WeaponBrowser.reset()
	WeaponBrowser.from_save(rt)
	TestLib.check(WeaponBrowser.is_favourite(&"m_phaseblade") and WeaponBrowser.recent[0] == WeaponDefs.all_ids()[8], "the browser state survives a save")
	WeaponBrowser.from_save({"favourites": ["nope", "a_pillar"], "recent": ["also_nope"]})
	TestLib.check(WeaponBrowser.favourites == [&"a_pillar"] and WeaponBrowser.recent.is_empty(), "unknown weapons in a profile are dropped")
	# loadout paging follows the selection and flips through classes
	WeaponBrowser.reset()
	LoadoutScreen.reset_page()
	var start := LoadoutScreen.page_items(&"carbine")
	TestLib.check(start.has(&"carbine") and start.size() <= WeaponBrowser.PAGE and LoadoutScreen.page_name() == "RIFLE", "the loadout opens on the page of the weapon in hand (%s)" % LoadoutScreen.page_name())
	var visited := {}
	for i in LoadoutScreen.page_count():
		for id in LoadoutScreen.page_items(&"carbine"):
			visited[id] = true
		LoadoutScreen.flip(1)
	TestLib.check(visited.size() == WeaponDefs.all_ids().size(), "flipping the pages reaches all %d weapons (%d)" % [WeaponDefs.all_ids().size(), visited.size()])
	var names: Array[String] = []
	for i in LoadoutScreen.tab_count():
		names.append(LoadoutScreen.page_name())
		LoadoutScreen.flip_class(1)
	TestLib.check(names.size() == WeaponDefs.CLASS_ORDER.size() and names[0] != names[1], "the class chips visit every class (%s)" % str(names))
	# the catalogue: a page of at most nine, every class has a tab, the chips jump between classes
	var cat_over := false
	var cat_seen := {}
	for pg in WeaponsScreen.PAGES:
		var items := WeaponsScreen.page_items(pg)
		cat_over = cat_over or items.size() > WeaponsScreen.PER_PAGE or items.is_empty()
		for it: Dictionary in items:
			cat_seen[it["id"]] = true
	var cat_lost: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		if not cat_seen.has(id):
			cat_lost.append(String(id))
	TestLib.check(not cat_over and cat_lost.is_empty(), "the catalogue lists every weapon on pages of at most %d (%s)" % [WeaponsScreen.PER_PAGE, str(cat_lost)])
	var tab := 0
	var tabs_seen := {}
	for i in 40:
		tabs_seen[WeaponsScreen.page_list()[tab]["tab"]] = true
		tab = WeaponsScreen.tab_jump(tab, 1)
	TestLib.check(tabs_seen.size() == WeaponDefs.CLASS_ORDER.size() + 2, "the catalogue chips visit %d tabs: every class, EXPLOSIVES and GADGETS" % tabs_seen.size())
	# shops by tier, drops
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	TestLib.check(WeaponShopsV3.hero_tier() == 1, "a new hero is at tier 1")
	var cand := WeaponShopsV3.candidates()
	var cand_ok := not cand.is_empty()
	for id in cand:
		cand_ok = cand_ok and WeaponDefsV3.tier_of(id) <= 1 and not WeaponDefs.is_unlocked(id) and _new.has(id)
	TestLib.check(cand_ok, "the shops offer unowned weapons of the hero's tier (%d)" % cand.size())
	for id in _new.slice(0, 40):
		WeaponDefs.unlock(id)
	TestLib.check(WeaponShopsV3.hero_tier() >= 3, "owning weapons raises the tier (%d)" % WeaponShopsV3.hero_tier())
	WeaponDefs.reset_unlocked()
	var rows := InteriorData.stock(&"weapons")
	var base_rows: Array = InteriorData.STOCK[&"weapons"]
	TestLib.check(rows.size() == base_rows.size(), "the ARMS DEALER shows as many rows as before")
	WeaponDefs.unlock(&"marksman")
	var rows1 := InteriorData.stock(&"weapons")
	var same := true
	for i in rows1.size():
		same = same and rows1[i]["id"] == base_rows[i]["id"]
	TestLib.check(same, "a tier 1 hero finds the stock he knows: the weapon he bought is marked OWNED in its row")
	for id in _new.slice(0, 20):
		WeaponDefs.unlock(id)
	var rows2 := InteriorData.stock(&"weapons")
	var restocked := false
	for r in rows2:
		restocked = restocked or (str(r["kind"]) == "weapon" and _new.has(r["id"]) and not WeaponDefs.is_unlocked(r["id"]))
	TestLib.check(WeaponShopsV3.hero_tier() >= 2 and restocked and rows2.size() == base_rows.size(), "from tier 2 a weapon the hero owns is sold out and the back room offers one of the roster he does not own")
	WeaponDefs.reset_unlocked()
	var carriers := {}
	for ty: StringName in [&"operative", &"flanker", &"brute", &"sniper", &"heavy", &"striker", &"shield", &"sentinel"]:
		var pool := WeaponDefsV3.drop_candidates(ty, 6, func(_w: StringName) -> bool: return false)
		if not pool.is_empty():
			carriers[ty] = pool.size()
	TestLib.check(carriers.size() >= 6, "at least six kinds of enemy carry weapons of the roster (%s)" % str(carriers))
	var tier1 := WeaponShopsV3.drop_for(&"operative", 0.3)
	TestLib.check(tier1 == &"" or (_new.has(tier1) and WeaponDefsV3.tier_of(tier1) <= 1), "a tier 1 hero is only offered tier 1 weapons by a drop (%s)" % tier1)
	var band := WeaponLadder.enemy_drop(&"operative", WeaponLadder.DROP_CHANCE + 0.01, 0.2, &"carbine", -1)
	var out_band := WeaponLadder.enemy_drop(&"operative", WeaponLadder.DROP_CHANCE + WeaponShopsV3.DROP_BAND + 0.01, 0.2, &"carbine", -1)
	TestLib.check((band == &"" or _new.has(band) or WeaponDefs.DEFS.has(band)) and out_band != &"" , "a roll in the roster band of the drop table gives a weapon (%s) and the others keep their meaning (%s)" % [band, out_band])
	WeaponDefs.reset_unlocked()
	WeaponBrowser.reset()
	LoadoutScreen.reset_page()


# --- the real scene -------------------------------------------------------------------------------------------------------

func _fresh() -> void:
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	Upgrades.reset()
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	Attachments.reset()
	await e.prep(Vector3(0.0, 0.05, 0.0))
	w.reset()
	w.switch_to(&"carbine", true)
	w.reset()


func _equip(id: StringName) -> void:
	w.switch_to(id, true)
	w.ammo = w.mag
	w.fire_t = 0.0
	w.swap_t = 0.0
	w.reload_t = 0.0
	if w.reserve >= 0:
		w.reserve = maxi(w.reserve, 40)


func _pull(seconds: float, aiming := false) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, true, false, aiming, false)
		w.mech.tick(DT)                                                             # the game ticks the mechanics in the weapon's _physics_process


func _idle(seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		w.tick(DT, false, false, false, false)
		w.mech.tick(DT)


func _aim(d: Drone) -> void:
	p.camera_rig.aim_at(d.center())


## The distance a dummy stands from the muzzle for a weapon: close for melee and sprayers, half the effective range for the rest.
func _dist_for(id: StringName) -> float:
	var d := WeaponDefs.def(id)
	if String(d["kind"]) == "melee":
		return clampf(float(d["reach"]) * 0.55, 1.2, 2.4)
	var reach := float(d.get("cone_range", d["range"]))
	return clampf(minf(reach * 0.45, float(d["falloff_from"])), 3.5, 14.0)


func _every_weapon_in_the_scene() -> void:
	await _fresh()
	var dummy := em.spawn(&"heavy", Vector3(10.0, 0.0, 0.0), false)
	dummy.set_physics_process(false)
	await e.frames(2)
	var failed_fire: Array[String] = []
	var failed_hit: Array[String] = []
	var failed_reload: Array[String] = []
	var failed_alt: Array[String] = []
	var failed_equip: Array[String] = []
	for id: StringName in _new:
		var d := WeaponDefs.def(id)
		var kind := String(d["kind"])
		_equip(id)
		if w.current != id:
			failed_equip.append(String(id))
			continue
		dummy.max_hp = 1.0e6
		dummy.hp = 1.0e6
		p.teleport_to(Vector3(0.0, 0.05, 0.0))                                    # a lunge, a blink or a pull of the weapon before moved the hero
		dummy.global_position = Vector3(_dist_for(id), 0.0, 0.0)
		await e.frames(1)
		_aim(dummy)
		var hp0 := dummy.hp
		var s0 := w.shots_fired
		var c0 := w.combo_hits
		if d.has("charge_time"):                                                  # hold until the charge is full, then let go
			_pull(float(d["charge_time"]) + 0.3, true)
			w.tick(DT, false, false, true, false)
			w.tick(DT, false, false, true, false)
		else:
			_pull(1.6 if (d.has("spin_up") or d.has("ramp")) else 0.6, false)
		var fired := w.combo_hits > c0 if kind == "melee" else w.shots_fired > s0
		if not fired:
			failed_fire.append("%s (%s)" % [id, kind])
		if hp0 - dummy.hp <= 0.0:
			failed_hit.append("%s %.1f m" % [id, _dist_for(id)])
		_idle(0.3)
		if kind != "melee" and int(d["mag"]) >= 1:                                    # reload from empty
			w.cancel_reload()                                                       # a small magazine reloads by itself while the trigger is held
			w.ammo = 0
			var r_ok := w.start_reload()
			_idle(w.reload_total + 0.5)
			if not (r_ok and w.ammo > 0):
				failed_reload.append("%s (%s, %.1f s)" % [id, r_ok, w.reload_total])
		_equip(id)
		var a0 := w.alt_fired
		var alt_ok := w.alt_fire(false)
		_idle(0.2)
		if not alt_ok or w.alt_fired <= a0:
			failed_alt.append("%s (%s)" % [id, WeaponDefs.alt_of(id)["kind"]])
		w.tick(6.0, false, false, false, false)                                       # let every cooldown and toggle run out before the next weapon
	TestLib.check(failed_equip.is_empty(), "each of the %d new weapons equips (failed %s)" % [_new.size(), str(failed_equip)])
	TestLib.check(failed_fire.is_empty(), "each of the %d new weapons fires when the trigger is pulled (failed %s)" % [_new.size(), str(failed_fire)])
	TestLib.check(failed_hit.is_empty(), "each of the %d new weapons damages a dummy at its own distance (failed %s)" % [_new.size(), str(failed_hit)])
	TestLib.check(failed_reload.is_empty(), "each gun reloads from empty (failed %s)" % str(failed_reload))
	TestLib.check(failed_alt.is_empty(), "each weapon's alt-fire works (failed %s)" % str(failed_alt))
	em.clear()


func _mechanics_in_play() -> void:
	# the status of a weapon really lands: every weapon with such a key moves its counter
	await _fresh()
	var dummy := em.spawn(&"heavy", Vector3(8.0, 0.0, 0.0), false)
	dummy.set_physics_process(false)
	await e.frames(2)
	var silent: Array[String] = []
	var checked := 0
	for id: StringName in _new:
		var d := WeaponDefs.def(id)
		if String(d["kind"]) == "melee" and not (d.has("slow") or d.has("zap") or d.has("knock") or d.has("mark") or d.has("chill") or d.has("dissolve")):
			continue
		for k: String in STATUS_COUNTER:
			if not d.has(k) or float(d[k]) <= 0.0:
				continue
			checked += 1
			_equip(id)
			dummy.max_hp = 1.0e6
			dummy.hp = 1.0e6
			p.teleport_to(Vector3(0.0, 0.05, 0.0))
			dummy.global_position = Vector3(_dist_for(id), 0.0, 0.0)
			await e.frames(1)
			_aim(dummy)
			w.mech.reset()
			var before := int(w.mech.get(STATUS_COUNTER[k]))
			_pull(0.7)
			_idle(0.25)
			if int(w.mech.get(STATUS_COUNTER[k])) <= before:
				silent.append("%s %s" % [id, k])
			w.tick(5.0, false, false, false, false)
	TestLib.check(checked >= 30 and silent.is_empty(), "the status of a weapon lands on a hit: %d weapon keys checked (silent: %s)" % [checked, str(silent)])
	# an opener hits harder than the shots after it, the last round of a magazine hits harder
	_equip(&"p_spark")
	dummy.global_position = Vector3(6.0, 0.0, 0.0)
	await e.frames(1)
	_aim(dummy)
	_idle(1.5)
	dummy.hp = dummy.max_hp
	var hp0 := dummy.hp
	w.tick(DT, true, false, false, false)
	var first := hp0 - dummy.hp
	_idle(0.5)
	hp0 = dummy.hp
	w.tick(DT, true, false, false, false)
	var second := hp0 - dummy.hp
	TestLib.check(first > second * 1.2 and w.mech.openers >= 1, "the first shot after a pause hits harder (%.1f against %.1f)" % [first, second])
	_equip(&"s_rivet")
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	dummy.global_position = Vector3(6.0, 0.0, 0.0)
	await e.frames(1)
	_aim(dummy)
	dummy.max_hp = 1.0e6
	dummy.hp = 1.0e6
	var per_shot: Array[float] = []
	for i in 10:
		var h := dummy.hp
		w.fire_t = 0.0
		w.tick(DT, true, false, false, false)
		w.mech.tick(DT)
		per_shot.append(h - dummy.hp)
		w.tick(0.06, false, false, false, false)                               # the next round is due (the cadence of the weapon), the trigger is held between shots
		w.mech.tick(0.06)
	TestLib.check(w.mech.ramp_peak >= 3 and per_shot[9] > per_shot[0] * 1.15, "a RIVET SMG ramps up while it stays on a target (peak %d, first round %.1f, tenth %.1f)" % [w.mech.ramp_peak, per_shot[0], per_shot[9]])
	# a kill gives rounds back
	_equip(&"a_gravel")
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	dummy.global_position = Vector3(7.0, 0.0, 0.0)
	await e.frames(1)
	_aim(dummy)
	dummy.hp = 3.0
	w.ammo = 10
	var rf0 := w.mech.refunds
	w.fire_t = 0.0
	w.tick(DT, true, false, false, false)
	TestLib.check(dummy.hp <= 0.0 and w.mech.refunds > rf0, "a kill with the GRAVEL SERVICE RIFLE gives rounds back (%d)" % w.mech.refunds)
	dummy.hp = dummy.max_hp
	# two enemies in a line: a round that pierces hits both
	em.clear()
	await e.frames(1)
	var near := em.spawn(&"heavy", Vector3(7.0, 0.0, 0.0), false)
	var far := em.spawn(&"heavy", Vector3(10.0, 0.0, 0.0), false)
	near.set_physics_process(false)
	far.set_physics_process(false)
	await e.frames(2)
	var pierce_id := &""
	for id: StringName in _new:
		if WeaponDefs.def(id).has("pierce_n"):
			pierce_id = id
			break
	if pierce_id != &"":
		_equip(pierce_id)
		_aim(near)
		var fh := far.hp
		_pull(0.5)
		TestLib.check(fh - far.hp > 0.0 and w.mech.pierces >= 1, "%s sends a round through the first enemy into the second" % WeaponDefs.title(pierce_id))
	em.clear()
	# ammo types: incendiary burns, shock zaps (a type changes the shot, the key costs nothing)
	await _fresh()
	var t1 := em.spawn(&"heavy", Vector3(9.0, 0.0, 0.0), false)
	t1.set_physics_process(false)
	await e.frames(2)
	_equip(&"a_pillar")
	_aim(t1)
	var types: Array = WeaponDefs.def(&"a_pillar")["ammo_types"]
	var burning := -1
	var shocking := -1
	for k in types:
		var tn := String(WeaponDefs.AMMO_TYPES[int(k)]["name"])
		if tn == "INCENDIARY":
			burning = int(k)
		if tn == "SHOCK":
			shocking = int(k)
	TestLib.check(burning >= 0 and shocking >= 0, "the PILLAR carries incendiary and shock rounds")
	var seen_names := {}
	for i in 12:
		seen_names[String(w.ammo_info()["name"])] = true
		w.cycle_ammo_type()
	TestLib.check(seen_names.size() == types.size(), "the ammo key walks through the %d types the weapon carries (%d)" % [types.size(), seen_names.size()])
	w.ammo_type = burning
	t1.hp = t1.max_hp
	var bt0 := w.burn_ticks
	_pull(0.4)
	_idle(1.8)
	TestLib.check(w.burn_ticks > bt0 or w.mech.has_status(&"burn", t1), "incendiary rounds set a target alight")
	w.ammo_type = shocking
	_equip(&"a_pillar")
	w.ammo_type = shocking
	var z0 := w.mech.zaps
	_pull(0.4)
	TestLib.check(w.mech.zaps > z0, "shock rounds zap")
	w.ammo_type = 0
	# attachments in play: the loadout parts change the live weapon
	Attachments.reset()
	for part: StringName in Attachments.IDS:
		Attachments.give(part)
	_equip(&"a_pillar")
	var kick0 := float(w.def["kick"])
	var rel0 := w.reload_total
	Attachments.equip(&"a_pillar", &"foregrip")
	Attachments.equip(&"a_pillar", &"fastmag")
	Attachments.equip(&"a_pillar", &"marker")
	w.apply_upgrades()
	TestLib.check(float(w.def["kick"]) < kick0 and w.reload_total < rel0, "fitted parts change the weapon in the hand at once (kick %.4f -> %.4f, reload %.2f -> %.2f)" % [kick0, float(w.def["kick"]), rel0, w.reload_total])
	t1.hp = t1.max_hp
	_aim(t1)
	var mk0 := w.mech.marks_made
	_pull(0.3)
	TestLib.check(w.mech.marks_made > mk0, "the MARKER LASER tags what the weapon hits")
	Attachments.reset()
	em.clear()


func _wheel_with_the_player() -> void:
	await _fresh()
	WeaponDefs.hero_mode = true
	WeaponBrowser.reset()
	w.switch_to(&"carbine", true)
	var items := WeaponWheel.items()
	TestLib.check(items.size() == WeaponDefs.CLASS_ORDER.size(), "the wheel starts with a wedge for each class and nothing else (%d)" % items.size())
	w.switch_to(&"p_hush", true)
	w.switch_to(&"carbine", true)
	items = WeaponWheel.items()
	var has_recent := false
	for it in items:
		has_recent = has_recent or it["id"] == &"recent"
	TestLib.check(has_recent and items.size() == WeaponDefs.CLASS_ORDER.size() + 1, "a RECENT wedge shows once a second weapon has been in the hand")
	WeaponBrowser.toggle_favourite(&"q_ppistol")
	items = WeaponWheel.items()
	TestLib.check(items.size() == WeaponDefs.CLASS_ORDER.size() + 2 and items[items.size() - 1]["id"] == &"fav", "and a FAVOURITES wedge once something is starred")
	var wheel := RadialWheel.new()
	wheel.open_at(&"weapon", items, Vector2(900.0, 500.0), 1.0, false, Rect2(0.0, 0.0, 2400.0, 1000.0))
	var gap := 1.0e9
	for i in items.size():
		for j in range(i + 1, items.size()):
			gap = minf(gap, wheel.item_centre(i).distance_to(wheel.item_centre(j)))
	TestLib.check(gap >= wheel.disc_scale() * RadialWheel.ITEM_R * 2.0 - 1.0 and wheel.disc_scale() * RadialWheel.ITEM_R * 2.0 >= 64.0, "the twelve discs of the wheel do not overlap and stay above the 64 px touch size (closest %.0f, disc %.0f)" % [gap, wheel.disc_scale() * RadialWheel.ITEM_R * 2.0])
	# a class wedge: equips the last weapon of the class and opens its ring
	w.switch_to(&"carbine", true)
	w.switch_to(&"pistol", true)
	var next := WeaponWheel.activate(_item(items, &"rifle"), w)
	TestLib.check(WeaponDefs.class_of(w.current) == &"rifle" and w.current == &"carbine" and next["tab"] == &"rifle", "a class wedge equips the last weapon of the class (%s) and opens its ring" % w.current)
	var ring := WeaponWheel.ring_items(next["tab"], next["page"], w.current)
	TestLib.check(ring.size() == WeaponWheel.RING + 1 and ring[ring.size() - 1]["type"] == &"page", "the ring shows %d weapons and a NEXT disc (%d)" % [WeaponWheel.RING, ring.size()])
	var ring_ok := true
	for it in ring:
		ring_ok = ring_ok and (it["type"] == &"page" or WeaponDefs.class_of(it["id"]) == &"rifle")
	TestLib.check(ring_ok, "every weapon of the ring is of the class")
	var next_page := WeaponWheel.activate(ring[ring.size() - 1], w)
	var ring2 := WeaponWheel.ring_items(next_page["tab"], next_page["page"], w.current)
	TestLib.check(int(next_page["page"]) == 1 and ring2[0]["id"] != ring[0]["id"], "the NEXT disc turns the page")
	var pick: Dictionary = ring2[1]
	var none := WeaponWheel.activate(pick, w)
	TestLib.check(none.is_empty() and w.current == pick["id"], "a weapon disc equips the weapon and closes the wheel (%s)" % w.current)
	# RECENT: the weapon before this one
	w.switch_to(&"p_hush", true)
	w.switch_to(&"s_rivet", true)
	var rec := WeaponWheel.activate({"id": &"recent", "type": &"tab"}, w)
	TestLib.check(w.current == &"p_hush" and rec["tab"] == &"recent", "the RECENT wedge swaps to the weapon before this one (%s)" % w.current)
	# a class with one owned weapon only equips
	WeaponDefs.hero_mode = false
	WeaponDefs.reset_unlocked()
	w.switch_to(&"carbine", true)
	var only := WeaponWheel.activate({"id": &"shotgun", "type": &"class"}, w)
	TestLib.check(only.is_empty() and w.current == &"scatter", "a class of one weapon just equips it (%s)" % w.current)
	WeaponDefs.hero_mode = true


func _item(items: Array, id: StringName) -> Dictionary:
	for it: Dictionary in items:
		if it["id"] == id:
			return it
	return {}
