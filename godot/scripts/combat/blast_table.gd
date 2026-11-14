class_name BlastTable
extends RefCounted
## THE blast table (wave 113, docs: godot/ARCHITECTURE.md "Blast arsenal"). One entry per kind of explosion; Game.explode asks it for the numbers and runs the one resolver below, so a
## radius, a falloff, a damage per target type, a knockback, a status and a look are defined in exactly one place. 65 entries come from scripts/combat/blast_rows.gd (grenades, launchers, mines
## and charges, called-in strikes, vehicle and aircraft ordnance, hero ultimates, world blasters), the blasts of the older weapons are migrated here from their WeaponDefs / Gear / Charges numbers
## (`legacy` category, behaviour unchanged), and anything else registers itself with `register(id, entry)` (the quantum snake bombs of wave 115 do).
##
## API (note: `BlastTable.get` cannot exist in GDScript, Object.get owns that name; the getter is `entry`):
##   BlastTable.entry(id) -> Dictionary            the full entry ({} for an unknown id); `has_entry(id)`, `ids()`, `ids_in(cat)`, `count()`
##   BlastTable.register(id, partial) -> Dictionary  adds or replaces an entry (missing keys come from the category defaults, `cat` defaults to &"ordnance")
##   BlastTable.apply(id, pos, source, opts) -> Dictionary   the blast: look, sound, props, structures, civilians, animals, enemies, vehicles, the hero, chain signal; returns a result dictionary
##   BlastTable.explode(pos, radius, opts)         what Game.explode calls: opts.blast = an id (then apply), otherwise the legacy numbers of the caller (enemy_dmg, car_dmg, player_dmg, color, element ...)
##   BlastTable.factor(entry, d, pad) -> float     share of the centre damage at distance d (core flat, then linear / quad down to `edge` at the radius, 0 beyond; `flat` = full to the radius)
##   BlastTable.damage_at(id, target, d)           the damage a target type ("enemy" "civilian" "animal" "vehicle" "hero") takes at distance d (what a test and the weapon card read)
## Entry keys: id name cat radius core curve edge dmg{enemy civilian animal vehicle structure prop hero} pad{enemy vehicle hero civilian animal} knock lift status{kind time power} element colors{}
##   wave shake snd snd_pitch crater scorch debris level friendly cover cone fx hold pre fire{radius time dps} cluster{n spread gap} tags tier note tag deliver{} w{}
## opts of apply / explode: quiet (no boom, shake, slow motion), radius_mult, dmg_mult, by_hero, dir (cone axis), final (the damage phase of a deferred blast), burn / style (legacy look).

const NEW_PAD := {"enemy": 0.0, "vehicle": 1.5, "hero": 0.0, "civilian": 0.0, "animal": 0.3}
const LEGACY_PAD := {"enemy": 0.8, "vehicle": 2.0, "hero": 0.0, "civilian": 0.0, "animal": 0.0}
const COVER := 0.35                       ## Game.BLAST_COVER: the share of the damage that reaches a target behind a wall
const CIVILIAN_HP_FLOOR := 1.0
const PEOPLE_SHOVE := 0.55                ## a person below this falloff share is not thrown
const MAX_RESULT_IDS := 64

static var _entries: Dictionary = {}
static var _order: Array[StringName] = []
static var _built := false
static var last: Dictionary = {}                      ## the result of the latest blast (animals and tests read it)
static var blasts := 0                                ## counters (tests wait on these)
static var by_id: Dictionary = {}
static var hero_immune_option := false                ## set by an option or by hero mode: the hero takes no damage from blasts
static var _sd: Variant = false                       ## the destruction module (StructureDamage) once it exists: null = absent, false = not looked up yet


# --- the table ------------------------------------------------------------------------------------------------------------

static func _ensure() -> void:
	if _built:
		return
	_built = true
	for pair: Array in BlastRows.all():
		var e := _expand(StringName(pair[0]), pair[1] as Array)
		_put(e)
	# one bolt of the CHAIN LIGHTNING STORM: not a catalogue entry (category internal)
	var bolt := _expand(&"ordnance", [&"ult_storm_bolt", "STORM BOLT", 3.0, 0.8, 120.0, 140.0, &"electric", {"tag": "BLT", "tier": 6, "debris": &"sparks", "level": 0, "friendly": false, "fx": &"shock", "knock": 6.0, "lift": 4.0}])
	bolt["cat"] = &"internal"
	_put(bolt)
	_migrate_legacy()


static func _put(e: Dictionary) -> void:
	var id := StringName(e["id"])
	if not _entries.has(id):
		_order.append(id)
	_entries[id] = e


static func entry(id: StringName) -> Dictionary:
	_ensure()
	return _entries.get(id, {})


static func has_entry(id: StringName) -> bool:
	_ensure()
	return _entries.has(id)


static func ids() -> Array[StringName]:
	_ensure()
	return _order


static func ids_in(cat: StringName) -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for id in _order:
		if StringName(_entries[id]["cat"]) == cat:
			out.append(id)
	return out


static func count(cat: StringName = &"") -> int:
	_ensure()
	return _order.size() if cat == &"" else ids_in(cat).size()


## Adds or replaces an entry. `partial` needs only what differs from its category's defaults (radius, dmg or enemy / vehicle, element ...); the entry that comes back is complete.
static func register(id: StringName, partial: Dictionary) -> Dictionary:
	_ensure()
	var cat := StringName(partial.get("cat", &"ordnance"))
	var row: Array = [id, String(partial.get("name", String(id).to_upper())), float(partial.get("radius", 5.0)), float(partial.get("core", 0.0)),
			float(partial.get("enemy", (partial.get("dmg", {}) as Dictionary).get("enemy", 100.0))), float(partial.get("vehicle", (partial.get("dmg", {}) as Dictionary).get("vehicle", 100.0))),
			StringName(partial.get("element", &"fire")), partial]
	var e := _expand(cat if BlastRows.DEFAULTS.has(cat) else &"ordnance", row)
	e["cat"] = cat
	if partial.has("dmg"):
		for k: String in (partial["dmg"] as Dictionary):
			(e["dmg"] as Dictionary)[k] = float((partial["dmg"] as Dictionary)[k])
	_put(e)
	return e


static func unregister(id: StringName) -> void:
	_ensure()
	if _entries.erase(id):
		_order.erase(id)


## A row of BlastRows (category defaults + the row) as a complete entry.
static func _expand(cat: StringName, row: Array) -> Dictionary:
	var e: Dictionary = (BlastRows.DEFAULTS[cat] as Dictionary).duplicate(true)
	var x: Dictionary = row[7]
	for k: Variant in x:
		var ks := String(k)
		if ks == "deliver" or ks == "w":
			(e[ks] as Dictionary).merge(x[k] as Dictionary, true)
		else:
			e[ks] = x[k]
	var en := float(row[4])
	e["id"] = row[0]
	e["name"] = row[1]
	e["cat"] = cat
	e["radius"] = float(row[2])
	e["core"] = minf(float(row[3]), float(row[2]))
	e["element"] = row[6]
	e["dmg"] = {"enemy": en, "vehicle": float(row[5]), "civilian": en * float(x.get("civ", 1.3)), "animal": en * float(x.get("animal", 0.9)), "hero": en * float(x.get("hero", 0.3)),
			"structure": float(e.get("level", 0)), "prop": float(x.get("prop", 1))}
	e["pad"] = NEW_PAD.duplicate()
	if x.has("status"):
		var s: Dictionary = x["status"]
		e["status"] = {"kind": StringName(s["k"]), "time": float(s["t"]), "power": float(s["p"])}
	else:
		e["status"] = {}
	if x.has("fire"):
		var f: Array = x["fire"]
		e["fire"] = {"radius": float(f[0]), "time": float(f[1]), "dps": float(f[2])}
	else:
		e["fire"] = {}
	if x.has("cluster"):
		var c: Array = x["cluster"]
		e["cluster"] = {"n": int(c[0]), "spread": float(c[1]), "gap": float(c[2])}
	else:
		e["cluster"] = {}
	e["cone"] = float(x.get("cone", 0.0))
	var hold := float(x.get("hold", 0.0))
	var st_kind := StringName((e["status"] as Dictionary).get("kind", &""))
	if st_kind == &"pull" or StringName(e.get("fx", &"")) == &"collapse":
		e["pre"] = hold                                                   # the blast waits while the area pulls in
		e["hold"] = 0.0
	else:
		e["pre"] = 0.0
		e["hold"] = hold
	e["colors"] = {}
	e["tags"] = x.get("tags", [])
	e["tier"] = int(x.get("tier", 1))
	e["note"] = String(x.get("note", ""))
	e["tag"] = String(x.get("tag", String(row[0]).substr(0, 3).to_upper()))
	e["snd_pitch"] = float(x.get("snd_pitch", 1.0))
	e["unlock"] = int(x.get("unlock", 0))
	e["legacy"] = false
	return e


## The blasts of the older weapons, gear and charges, built from the numbers where they live (WeaponDefs.DEFS0, Gear, Charges): the same radius, damage and look as before, now through the one resolver.
static func _migrate_legacy() -> void:
	for id: StringName in WeaponDefs.DEFS0:
		var d: Dictionary = WeaponDefs.DEFS0[id]
		if d.has("blast_radius") and String(d.get("kind", "")) == "throw":
			_put(_from_def(id, d))
	for id: StringName in WeaponDefs.PROJ0:
		var pd: Dictionary = WeaponDefs.PROJ0[id]
		if pd.has("blast_radius"):
			_put(_from_def(id, pd))
	for id: StringName in [&"singularity", &"mine", &"plasma"]:
		var g: Dictionary = Gear.THROWABLES[id]
		var e := _legacy(StringName("gear_%s" % String(id)), String(g["name"]), float(g["radius"]), float(g["damage"]), float(g.get("car", 40.0)), 0.0, g["color"], &"gear")
		_put(e)
	_put(_legacy(&"c4", String(Gear.CHARGES[&"c4"]["name"]), Charges.RADIUS, Charges.ENEMY_DAMAGE, Charges.CAR_DAMAGE, Charges.SELF_DAMAGE, Charges.COLOR, &"gear"))


static func _from_def(id: StringName, d: Dictionary) -> Dictionary:
	var col: Color = d.get("blast_color", WeaponDefs.COLLAPSE_COLOR)
	var e := _legacy(StringName("w_%s" % String(id)), String(d["name"]), float(d["blast_radius"]), float(d.get("blast_damage", d["damage"])), float(d.get("car_dmg", 40.0)), 0.0, col, &"weapon")
	e["element"] = StringName(d["blast_element"]) if d.has("blast_element") else BlastElements.of_color(col)
	e["weapon"] = id
	return e


static func _legacy(id: StringName, nm: String, radius: float, enemy: float, car: float, hero: float, col: Color, src: StringName) -> Dictionary:
	var e: Dictionary = (BlastRows.DEFAULTS[&"launcher"] as Dictionary).duplicate(true)
	e["id"] = id
	e["name"] = nm
	e["cat"] = &"legacy"
	e["radius"] = radius
	e["core"] = 0.0
	e["curve"] = &"linear"
	e["edge"] = 0.4
	e["dmg"] = {"enemy": enemy, "vehicle": car, "civilian": 200.0, "animal": enemy, "hero": hero, "structure": 1.0, "prop": 1.0}
	e["pad"] = LEGACY_PAD.duplicate()
	e["status"] = {}
	e["fire"] = {}
	e["cluster"] = {}
	e["cone"] = 0.0
	e["pre"] = 0.0
	e["hold"] = 0.0
	e["colors"] = {"mid": col}
	e["element"] = BlastElements.of_color(col)
	e["tags"] = []
	e["tier"] = 1
	e["note"] = ""
	e["tag"] = String(id).substr(0, 3).to_upper()
	e["snd_pitch"] = 1.0
	e["unlock"] = 0
	e["friendly"] = hero > 0.0
	e["knock"] = 0.0                                                      # migrated blasts keep their old behaviour: no shove unless a caller improves it
	e["lift"] = 0.0
	e["level"] = 1
	e["legacy"] = true
	e["source"] = src
	e["color"] = col
	return e


## The table radius of a weapon def that has a `bid` (the blast id of the arsenal), else its own `blast_radius`: what the aim ring, the card and the HUD show.
static func radius_of_def(d: Dictionary) -> float:
	if d.has("bid"):
		var e := entry(StringName(d["bid"]))
		if not e.is_empty():
			return float(e["radius"])
	return float(d.get("blast_radius", 0.0))


# --- falloff -------------------------------------------------------------------------------------------------------------------

## Share (0..1) of the centre damage a target takes at distance `d` from the centre. `pad` = the target's own reach on top of the radius (a car's length). Flat core, then the entry's curve
## down to `edge` at the radius; nothing beyond it.
static func factor(e: Dictionary, d: float, pad := 0.0) -> float:
	var r := float(e["radius"]) + pad
	if r <= 0.0 or d > r * 1.0001:
		return 0.0
	var curve := StringName(e["curve"])
	if curve == &"flat":
		return 1.0
	var core := minf(float(e["core"]), r)
	if d <= core:
		return 1.0
	var t := clampf((d - core) / maxf(r - core, 0.001), 0.0, 1.0)
	var edge := clampf(float(e["edge"]), 0.0, 1.0)
	if curve == &"quad":
		return edge + (1.0 - edge) * (1.0 - t) * (1.0 - t)
	return 1.0 - (1.0 - edge) * t


## The damage a target type takes at distance `d` (centre value x falloff), before cover and the hero's damage multipliers.
static func damage_at(id: StringName, target: StringName, d: float) -> float:
	var e := entry(id)
	if e.is_empty():
		return 0.0
	return float((e["dmg"] as Dictionary).get(String(target), 0.0)) * factor(e, d, float((e["pad"] as Dictionary).get(String(target), 0.0)))


## The share of the centre damage at distance d, as the weapon card draws it ("damage at the centre / half way / at the edge").
static func share(id: StringName, d: float) -> float:
	var e := entry(id)
	return 0.0 if e.is_empty() else factor(e, d, 0.0)


# --- the resolver --------------------------------------------------------------------------------------------------------------

## A blast from the table: `source` = who caused it (the hero node, an enemy, a vehicle, null for the world).
static func apply(id: StringName, pos: Vector3, source: Variant = null, opts: Dictionary = {}) -> Dictionary:
	_ensure()
	var e: Dictionary = _entries.get(id, {})
	if e.is_empty():
		push_warning("BlastTable.apply: unknown blast id %s" % String(id))
		return {}
	return _run(e, pos, source, opts)


## Game.explode: a table id in opts.blast, or the numbers of an old caller (the same resolver, with the old falloff and reach).
static func explode(pos: Vector3, radius: float, opts: Dictionary = {}) -> Dictionary:
	_ensure()
	if opts.has("blast"):
		var e: Dictionary = _entries.get(StringName(opts["blast"]), {})
		if not e.is_empty():
			return _run(e, pos, opts.get("source", null), opts)
	return _run(_adhoc(radius, opts), pos, opts.get("source", null), opts)


static func _adhoc(radius: float, opts: Dictionary) -> Dictionary:
	var element: StringName = opts.get("element", &"")
	var color: Color = opts.get("color", BlastElements.color(element, "ring") if BlastElements.valid(element) else Color(1.0, 0.54, 0.19))
	var explicit := BlastElements.valid(element)
	if not explicit:
		element = BlastElements.of_color(color)
	var e := _legacy(&"adhoc", "BLAST", radius, float(opts.get("enemy_dmg", 60.0)), float(opts.get("car_dmg", 60.0)), float(opts.get("player_dmg", 30.0)), color, &"caller")
	e["element"] = element
	e["explicit_element"] = explicit
	e["burn"] = float(opts.get("burn", 0.0))
	e["style"] = int(opts.get("style", -1))
	return e


static func _dmg_mult(e: Dictionary, source: Variant, opts: Dictionary) -> float:
	if opts.has("dmg_mult"):
		return float(opts["dmg_mult"])
	if bool(e.get("legacy", false)):
		return 1.0
	if _is_hero(source, opts):
		return Upgrades.damage_mult() * HeroPower.f("dmg")
	return 1.0


static func _is_hero(source: Variant, opts: Dictionary) -> bool:
	if bool(opts.get("by_hero", false)):
		return true
	if not (source is Object) or not is_instance_valid(source):
		return false
	return source == Game.player or (source is Node and (source as Node).get(&"driver_is_player") == true)       # the hero, or the car, tank or aircraft he drives


static func hero_immune() -> bool:
	return hero_immune_option or TestMode.god or WeaponDefs.hero_mode


## True when the hero takes damage from a blast of entry `e` caused by `source`: an enemy's or the world's blast always; the hero's own only when the entry is friendly, never on EASY, and
## never with the immunity option.
static func hero_hurt_by(e: Dictionary, source: Variant, opts: Dictionary) -> bool:
	if hero_immune():
		return false
	if bool(e.get("legacy", false)) and not bool(e.get("friendly", false)):
		return false
	if _is_hero(source, opts):
		return bool(e.get("friendly", false)) and Difficulty.current != Difficulty.EASY
	return float((e["dmg"] as Dictionary)["hero"]) > 0.0


static func _run(e: Dictionary, pos: Vector3, source: Variant, opts: Dictionary) -> Dictionary:
	var tree := Game.get_tree()
	var rm := float(opts.get("radius_mult", 1.0))
	var radius := float(e["radius"]) * rm
	var res := {"id": e["id"], "pos": pos, "radius": radius, "enemies": 0, "vehicles": 0, "civilians": 0, "civilians_killed": 0, "animals": 0, "props": 0, "structure": 0, "hero": 0.0,
			"enemy_total": 0.0, "vehicle_total": 0.0, "enemy_hits": {}, "vehicle_hits": {}, "launched": 0, "statuses": 0, "hold": float(e["hold"])}
	last = res
	blasts += 1
	by_id[e["id"]] = int(by_id.get(e["id"], 0)) + 1
	var ops := BlastOps.shared(tree)
	# a deferred blast (a well that pulls first): the zone runs now, the damage phase comes back with `final`
	var pre := float(e["pre"])
	if pre > 0.0 and not bool(opts.get("final", false)) and ops != null:
		ops.start_pre(e, pos, source, opts, radius)
		res["deferred"] = pre
		return res
	var dm := _dmg_mult(e, source, opts)
	var quiet := bool(opts.get("quiet", false))
	# the look, the sound, the shake
	BlastFx.play(e, pos, radius, opts)
	# props and structures
	var dmg: Dictionary = e["dmg"]
	var prop_k := float(dmg["prop"])
	if prop_k > 0.0 and Breakables.current != null:
		res["props"] = Breakables.current.blast(pos, radius * minf(prop_k, 1.0))
	var level := int(dmg["structure"])
	if level > 0:
		res["structure"] = _structure(pos, radius, level)
	res["chain_radius"] = radius
	Game.exploded.emit(pos, radius)                                                        # charges, cars, barrels and mines next to it go off in a chain; animals scare
	if bool(e.get("legacy", false)):
		_legacy_targets(e, pos, radius, dm, source, opts, res)
	else:
		_targets(e, pos, radius, dm, source, opts, res, ops)
	# what the blast leaves behind
	if ops != null:
		var fire: Dictionary = e["fire"]
		if not fire.is_empty():
			ops.fire_field(pos, float(fire["radius"]) * rm, float(fire["time"]), float(fire["dps"]) * dm, source)
		var cl: Dictionary = e["cluster"]
		if not cl.is_empty() and not bool(opts.get("no_cluster", false)):
			ops.cluster(e, pos, source, opts)
		if float(e["hold"]) > 0.0:
			ops.start_zone(e, pos, source, opts, radius)
		ops.note_blast(e, pos, radius)
	return res


static func _structure(pos: Vector3, radius: float, level: int) -> int:
	if _sd is bool:
		_sd = load("res://scripts/combat/structure_damage.gd") if ResourceLoader.exists("res://scripts/combat/structure_damage.gd") else null
	if _sd == null:
		return 0
	(_sd as Object).call(&"apply", pos, radius, level)                                    # the damage builder's module: StructureDamage.apply(pos, radius, level)
	return level


## The old Game.explode numbers through the one resolver: linear down to 40 %, reach + 0.8 for people, + 2.0 for cars, cover 35 %, civilians by the crowd's own falloff.
static func _legacy_targets(e: Dictionary, pos: Vector3, radius: float, dm: float, _source: Variant, _opts: Dictionary, res: Dictionary) -> void:
	var dmg: Dictionary = e["dmg"]
	var enemy_dmg := float(dmg["enemy"])
	var tree := Game.get_tree()
	if Game.civilian_casualties and radius >= 2.0 and is_instance_valid(Game.world) and Game.world.get(&"ambient") != null:
		res["civilians_killed"] = Game.world.ambient.blast_civilians(pos, radius, enemy_dmg > 0.0)      # a blast that hurts enemies is the hero's (or his car's); an enemy's striker is not
	if enemy_dmg > 0.0:
		for n: Node in tree.get_nodes_in_group(&"enemy"):
			var en := n as Node3D
			if en == null:
				continue
			var reach := radius + float((e["pad"] as Dictionary)["enemy"])
			var d := en.global_position.distance_to(pos)
			if d < reach:
				var amount := TestMode.damage(enemy_dmg * dm * factor(e, d, float((e["pad"] as Dictionary)["enemy"])) * _cover(pos, en.global_position + Vector3(0.0, 1.0, 0.0)))
				en.call(&"damage", amount)
				res["enemies"] = int(res["enemies"]) + 1
				res["enemy_total"] = float(res["enemy_total"]) + amount
	var car_dmg := float(dmg["vehicle"])
	for v: Node in tree.get_nodes_in_group(&"vehicle"):
		var vn := v as Node3D
		if vn == null:
			continue
		var vpad := float((e["pad"] as Dictionary)["vehicle"])
		var d := vn.global_position.distance_to(pos)
		if d < radius + vpad:
			var amount := car_dmg * factor(e, d, vpad) * _cover(pos, vn.global_position + Vector3(0.0, 0.8, 0.0))
			vn.call(&"damage", amount)
			res["vehicles"] = int(res["vehicles"]) + 1
			res["vehicle_total"] = float(res["vehicle_total"]) + amount
	var hero_dmg := float(dmg["hero"])
	if hero_dmg > 0.0 and is_instance_valid(Game.player):
		var d := Game.player.global_position.distance_to(pos)
		if d < radius:
			var amount := hero_dmg * factor(e, d, 0.0) * _cover(pos, Game.player.global_position + Vector3(0.0, 1.0, 0.0))
			res["hero"] = amount
			Game.player.damage(amount, pos)


static func _cover(from: Vector3, to: Vector3) -> float:
	return Game.blast_cover(from, to)


static func _in_cone(e: Dictionary, pos: Vector3, at: Vector3, opts: Dictionary) -> bool:
	var half := float(e.get("cone", 0.0))
	if half <= 0.0 or not opts.has("dir"):
		return true
	var axis: Vector3 = opts["dir"]
	var flat := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
	if flat.length() < 0.6:
		return true
	return axis.angle_to(flat.normalized()) <= half


## The table-driven targets: damage by type and curve, cover, knockback and lift, status, civilians and animals, the hero.
static func _targets(e: Dictionary, pos: Vector3, radius: float, dm: float, source: Variant, opts: Dictionary, res: Dictionary, ops: BlastOps) -> void:
	var tree := Game.get_tree()
	var dmg: Dictionary = e["dmg"]
	var pad: Dictionary = e["pad"]
	var by_hero := _is_hero(source, opts)
	var knock := float(e["knock"])
	var lift := float(e["lift"])
	var cover_on := bool(e.get("cover", true))
	var st: Dictionary = e["status"]
	var st_kind := StringName(st.get("kind", &""))
	# --- civilians and animals: hurt by the curve, the rest flee
	if Game.civilian_casualties and float(dmg["civilian"]) >= 0.0 and is_instance_valid(Game.world) and Game.world.get(&"ambient") != null:
		_civilians(e, pos, radius, dm, by_hero, res, st_kind)
	# --- enemies
	var base_enemy := float(dmg["enemy"]) * dm
	for n: Node in tree.get_nodes_in_group(&"enemy"):
		var en := n as Node3D
		if en == null or not is_instance_valid(en) or not en.is_inside_tree() or bool(en.get(&"dead")):
			continue
		var p := en.global_position
		var d := p.distance_to(pos)
		var epad := float(pad["enemy"])
		if d > radius + epad or not _in_cone(e, pos, p, opts):
			continue
		var f := factor(e, d, epad)
		var cov := _cover(pos, p + Vector3(0.0, 1.0, 0.0)) if cover_on else 1.0
		var amount := TestMode.damage(base_enemy * f * cov) if base_enemy > 0.0 else 0.0
		if amount > 0.0:
			en.call(&"damage", amount)
		res["enemies"] = int(res["enemies"]) + 1
		res["enemy_total"] = float(res["enemy_total"]) + amount
		if (res["enemy_hits"] as Dictionary).size() < MAX_RESULT_IDS:
			(res["enemy_hits"] as Dictionary)[en.get_instance_id()] = amount
		if ops != null and not bool(en.get(&"dead")):
			var away := Vector3(p.x - pos.x, 0.0, p.z - pos.z)
			away = away.normalized() if away.length() > 0.2 else Vector3(0.0, 0.0, 1.0)
			if (absf(knock) > 0.01 or lift > 0.01) and f * cov >= 0.2:
				if ops.launch_body(en, away * knock * f * cov, lift * f * cov):
					res["launched"] = int(res["launched"]) + 1
			if not st.is_empty() and (cov > 0.5 or not cover_on):
				if ops.status(en, e, f, source, pos):
					res["statuses"] = int(res["statuses"]) + 1
	# --- vehicles
	var base_car := float(dmg["vehicle"]) * dm
	var hero_vehicle: Variant = Game.player.get(&"vehicle") if is_instance_valid(Game.player) else null
	for v: Node in tree.get_nodes_in_group(&"vehicle"):
		var vn := v as Node3D
		if vn == null or not is_instance_valid(vn) or not vn.is_inside_tree() or bool(vn.get(&"dead")):
			continue
		var vp := vn.global_position
		var d := vp.distance_to(pos)
		var vpad := float(pad["vehicle"])
		if d > radius + vpad or not _in_cone(e, pos, vp, opts):
			continue
		var f := factor(e, d, vpad)
		var cov := _cover(pos, vp + Vector3(0.0, 0.8, 0.0)) if cover_on else 1.0
		var amount := base_car * f * cov
		if amount > 0.0:
			vn.call(&"damage", amount)
		res["vehicles"] = int(res["vehicles"]) + 1
		res["vehicle_total"] = float(res["vehicle_total"]) + amount
		if (res["vehicle_hits"] as Dictionary).size() < MAX_RESULT_IDS:
			(res["vehicle_hits"] as Dictionary)[vn.get_instance_id()] = amount
		if ops != null and (absf(knock) > 0.01 or lift > 0.01) and f * cov >= 0.15 and vn.has_method(&"apply_impulse"):
			var away := Vector3(vp.x - pos.x, 0.0, vp.z - pos.z)
			away = away.normalized() if away.length() > 0.2 else Vector3(0.0, 0.0, 1.0)
			ops.shove_vehicle(vn, away, knock * f * cov, lift * f * cov, pos)
		if ops != null and not st.is_empty() and cov > 0.5:
			ops.status_vehicle(vn, e, f)
	# --- the hero
	if is_instance_valid(Game.player) and not Game.player.get(&"_dead"):
		var hp := Game.player.global_position
		var d := hp.distance_to(pos)
		var hpad := float(pad["hero"])
		if d <= radius + hpad and _in_cone(e, pos, hp, opts):
			var f := factor(e, d, hpad)
			var cov := _cover(pos, hp + Vector3(0.0, 1.0, 0.0)) if cover_on else 1.0
			res["hero_f"] = f * cov
			if hero_hurt_by(e, source, opts):
				var amount := float(dmg["hero"]) * f * cov
				amount = _soften(amount)
				res["hero"] = amount
				if amount > 0.0:
					Game.player.damage(amount, pos)
			if ops != null and not hero_immune() and hero_vehicle == null and (absf(knock) > 0.01 or lift > 0.01) and not by_hero_safe(e, by_hero):
				ops.shove_hero(Vector3(hp.x - pos.x, 0.0, hp.z - pos.z), knock * f * cov, lift * f * cov)
			if ops != null and not st.is_empty() and st_kind in [&"blind", &"emp", &"stun"] and not hero_immune():
				ops.status_hero(e, f, pos)


## The hero is shoved by blasts that can hurt him; his own harmless ones (a flash he threw himself, EASY) only shake the camera.
static func by_hero_safe(e: Dictionary, by_hero: bool) -> bool:
	return by_hero and (not bool(e.get("friendly", false)) or Difficulty.current == Difficulty.EASY)


## No sudden deaths on EASY and NORMAL: a blast alone never takes more than this much of the hero's health (all of it on HARD and QUANTUM).
static func _soften(amount: float) -> float:
	var p := Game.player as Player
	if p == null or Difficulty.current >= 2:
		return amount
	var floor_hp := p.max_hp * (0.25 if Difficulty.current == Difficulty.NORMAL else 0.4)
	return clampf(amount, 0.0, maxf(p.hp - floor_hp, 0.0) / maxf(Difficulty.damage_taken(Difficulty.story_chapter()), 0.1))


static func _civilians(e: Dictionary, pos: Vector3, radius: float, dm: float, by_hero: bool, res: Dictionary, st_kind: StringName) -> void:
	var amb: Object = Game.world.get(&"ambient")
	var crowd: Object = amb.get(&"crowd")
	var npc: Object = amb.get(&"npc")
	if crowd == null:
		return
	var base := float((e["dmg"] as Dictionary)["civilian"]) * dm
	var flee_r := radius * 2.4 + 6.0
	var killed := 0
	var near := PackedInt32Array()
	for i in int(crowd.get(&"count")):
		if not crowd.call(&"is_alive", i):
			continue
		var pp: Vector3 = crowd.call(&"person_position", i)
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if d <= radius and base > 0.0 and radius >= 2.0:
			near.append(i)
		elif d <= flee_r:
			crowd.call(&"scare_person", i, pos)
	for i in near:
		var pp: Vector3 = crowd.call(&"person_position", i)
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		var amount := base * factor(e, d, 0.0)
		if crowd.call(&"damage_person", i, amount, pos):
			killed += 1
		res["civilians"] = int(res["civilians"]) + 1
	for i in near:
		if npc != null and crowd.call(&"is_dying", i):
			npc.call(&"on_civilian_down", i, crowd.call(&"person_position", i), by_hero or float((e["dmg"] as Dictionary)["enemy"]) > 0.0, &"blast")
	res["civilians_killed"] = killed
	if st_kind == &"smoke":
		crowd.call(&"scare_from", pos, radius * 1.5)


## Damage an animal takes from the blast that just went off (WildlifeWorld asks while it handles Game.exploded): the table's number when the blast is a table blast at this spot, else `fallback`.
static func animal_damage(pos: Vector3, radius: float, d: float, fallback: float) -> float:
	if last.is_empty() or not (last["pos"] as Vector3).is_equal_approx(pos) or absf(float(last["radius"]) - radius) > 0.01:
		return fallback
	var e := entry(StringName(last["id"]))
	if e.is_empty() or bool(e.get("legacy", false)):
		return fallback
	return float((e["dmg"] as Dictionary)["animal"]) * factor(e, d, float((e["pad"] as Dictionary)["animal"]))


## Sets the blast counters and the last result back to zero (tests).
static func reset_stats() -> void:
	blasts = 0
	by_id.clear()
	last = {}
