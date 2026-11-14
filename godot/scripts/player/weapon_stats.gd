class_name WeaponStats
extends RefCounted
## The numbers of a weapon as a player reads them (the info card of the WEAPONS tab and the loadout): damage, fire rate, magazine, reload, effective range, blast radius, spread,
## penetration, recoil, each also as a 0..1 bar so weapons compare at a glance. Pure data and rules from WeaponDefs (or an Attachments.effective copy), no scene tree.
## Range rule (what PlayerWeapon does): full damage out to `falloff_from`, then down to 25 % at `range` (a weapon with falloff_from 9999 keeps full damage to its range). Explosives: full
## damage at the centre, 40 % at the edge of the blast, and cover between the blast and the target takes most of it (Game.explode).

const BARS := [&"damage", &"rate", &"range", &"accuracy", &"control", &"pierce"]
const BAR_NAMES := {&"damage": "DAMAGE", &"rate": "FIRE RATE", &"range": "RANGE", &"accuracy": "ACCURACY", &"control": "CONTROL", &"pierce": "PENETRATION"}
const FAR_DAMAGE := 0.25                  ## share of the damage left at the weapon's maximum range


## All the numbers of weapon `id`. `d` = the def to read (default: the weapon's own DEFS entry; the loadout passes Attachments.effective(id)).
static func card(id: StringName, d: Dictionary = {}) -> Dictionary:
	var def: Dictionary = d if not d.is_empty() else WeaponDefs.def(id)
	var kind := String(def["kind"])
	var pellets := int(def.get("pellets", 1))
	var per := float(def["damage"])
	var burst := int(def.get("burst", 1))
	var interval := maxf(float(def["interval"]), 0.02)
	var out := {"id": id, "kind": kind, "name": String(def["name"]), "class": WeaponDefs.CLASS_NAMES.get(WeaponDefs.class_of(id), "")}
	out["damage"] = per
	out["pellets"] = pellets
	out["damage_shot"] = per * float(pellets)
	out["crit"] = float(def["crit"])
	out["mag"] = int(def["mag"])
	out["reserve"] = int(def["reserve"])
	out["reload"] = float(def["reload"])
	var cycle := interval
	if kind == "charge":
		cycle = interval + float(def.get("charge_time", 1.0)) * 0.7
	out["rate"] = float(burst) / cycle if kind != "melee" else 1.0 / cycle      # shots (or swings) per second
	out["rpm"] = out["rate"] * 60.0
	out["dps"] = per * float(pellets) * float(out["rate"])
	var rng := float(def["range"])
	var fall := float(def["falloff_from"])
	out["range_max"] = rng
	out["range_eff"] = fall if fall < rng else rng
	out["falloff"] = fall < rng
	out["blast"] = BlastTable.radius_of_def(def) if kind == "throw" else float(def.get("blast_radius", 0.0))
	out["blast_damage"] = float(def.get("blast_damage", def["damage"])) if kind == "throw" else 0.0
	out["utility"] = bool(def.get("utility", false))                           # a blast that does no damage (flash, smoke, EMP, freeze): its damage number is nominal
	out["blast_edge"] = 0.0
	out["blast_core"] = 0.0
	if kind == "throw":
		var be := BlastPreview.entry_of(def, id)
		if not be.is_empty():
			out["blast_edge"] = BlastTable.factor(be, float(be["radius"]))          # share of the centre damage at the edge of the radius
			out["blast_core"] = float(be["core"])
	out["well"] = float(def.get("well_radius", 0.0)) if kind == "throw" and float(def.get("well_pull", 0.0)) > 0.0 else 0.0
	out["spread_hip"] = rad_to_deg(float(def["spread_hip"]))
	out["spread_ads"] = rad_to_deg(float(def["spread_ads"]))
	out["recoil"] = float(def["kick"]) + float(def["kick_yaw"]) * 0.5
	out["pierce_shield"] = bool(def.get("pierce_shield", false))
	out["chain"] = int(def.get("chain", 0))
	out["melee"] = kind == "melee"
	out["reach"] = float(def.get("reach", 0.0))
	out["lock"] = lock_on(id)
	out["pen"] = penetration(def)
	var bars := {}
	bars[&"damage"] = clampf(sqrt(float(out["damage_shot"]) / 220.0), 0.0, 1.0)
	bars[&"rate"] = clampf(log(1.0 + float(out["rate"])) / log(1.0 + 20.0), 0.0, 1.0)
	bars[&"range"] = clampf(sqrt(float(out["range_eff"]) / 450.0), 0.0, 1.0) if not out["melee"] else clampf(float(out["reach"]) / 12.0, 0.0, 1.0)
	bars[&"accuracy"] = clampf(1.0 - float(def["spread_hip"]) / 0.1, 0.0, 1.0) if kind != "throw" and not out["melee"] else (1.0 if kind == "throw" else 0.7)
	bars[&"control"] = clampf(1.0 - float(out["recoil"]) / 0.07, 0.05, 1.0) if not out["melee"] else 1.0
	bars[&"pierce"] = float(out["pen"])
	out["bars"] = bars
	return out


## How far a round gets through shields and cover, 0..1: heavy single rounds and pierce_shield weapons high, pellets and light rounds low.
static func penetration(def: Dictionary) -> float:
	var kind := String(def["kind"])
	if kind == "melee":
		return 0.45 if bool(def.get("pierce_shield", false)) else 0.12
	var per := float(def["damage"])
	var v := clampf(per / 150.0, 0.0, 0.7)
	if bool(def.get("pierce_shield", false)):
		v += 0.3
	if int(def.get("pellets", 1)) > 1:
		v *= 0.5
	if kind == "throw":
		v = 0.15
	return clampf(v, 0.05, 1.0)


## A launcher locks on to the target under the crosshair (a bracket on it, the round steers to it).
static func lock_on(id: StringName) -> bool:
	var d := WeaponDefs.def(id)
	return String(d["kind"]) == "throw" and bool(d.get("impact", false))


## Damage of one hit at `dist` metres, in the units of the def (before any multiplier): the range falloff PlayerWeapon applies.
static func damage_at(id: StringName, dist: float, crit := false) -> float:
	var d := WeaponDefs.def(id)
	var base := float(d["crit"]) if crit else float(d["damage"])
	var fall := float(d["falloff_from"])
	var rng := float(d["range"])
	if dist <= fall:
		return base
	return base * lerpf(1.0, FAR_DAMAGE, clampf((dist - fall) / maxf(rng - fall, 1.0), 0.0, 1.0))


## Explosion damage share at `d` metres from the centre of a blast of radius `r`: 1.0 at the centre down to 0.4 at the edge (Game.explode), 0 outside.
static func blast_share(d: float, r: float) -> float:
	var reach := r + 0.8
	if d >= reach:
		return 0.0
	return 1.0 - 0.6 * d / reach


## Where a weapon comes from, as short lines for the catalogue: the starter, the free route of the ladder, the shop price.
static func where(id: StringName) -> Array[String]:
	var out: Array[String] = []
	if WeaponDefs.STARTERS.has(id):
		out.append("STARTER  YOU HAVE IT")
		return out
	var e := WeaponLadder.entry(id)
	if not e.is_empty():
		match StringName(e["route"]):
			WeaponLadder.CRATE:
				out.append("CRATE  %s" % String(WeaponLadder.CRATES[int(e["arg"])]["name"]))
			WeaponLadder.MISSION:
				out.append("MISSION REWARD  CHAPTER %d" % (int(e["arg"]) + 1))
			WeaponLadder.BOSS:
				out.append("BOSS DROP  SECTOR %d" % int(e["arg"]))
			WeaponLadder.DROP:
				out.append("ENEMY DROP  %s" % String(e["arg"]).to_upper())
	out.append("SHOP  %d" % WeaponDefs.price(id))
	return out


## The weapon crates of the map that hold `id` (indices into WeaponLadder.CRATES), for the marker on the map.
static func crates_of(id: StringName) -> Array[int]:
	var out: Array[int] = []
	for i in WeaponLadder.CRATES.size():
		if StringName(WeaponLadder.CRATES[i]["weapon"]) == id:
			out.append(i)
	return out


## The lines of the card under the bars: "22 DMG  x8", "300 RPM", "MAG 15  RELOAD 1.0 S", "FULL TO 45 M  MAX 120 M", "BLAST 7.0 M".
static func lines(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if c["melee"]:
		out.append("%d DAMAGE PER HIT" % int(roundf(float(c["damage"]))))
		out.append("REACH %.1f M" % float(c["reach"]))
		out.append("%.1f SWINGS PER SECOND" % float(c["rate"]))
		return out
	var dmg := "%d DAMAGE" % int(roundf(float(c["damage"])))
	if int(c["pellets"]) > 1:
		dmg += "  x%d PELLETS" % int(c["pellets"])
	if bool(c.get("utility", false)):
		dmg = "UTILITY  IT DOES NO DAMAGE"
	out.append(dmg)
	out.append("%d RPM" % int(roundf(float(c["rpm"]))))
	var mag := "MAG %d" % int(c["mag"])
	if int(c["reserve"]) >= 0:
		mag += "  SPARE %d" % int(c["reserve"])
	out.append("%s  RELOAD %.1f S" % [mag, float(c["reload"])])
	if float(c["blast"]) > 0.0 and bool(c.get("utility", false)):
		out.append("BLAST %.1f M  NO DAMAGE  A TOOL" % float(c["blast"]))
	elif float(c["blast"]) > 0.0:
		out.append("BLAST %.1f M  %d DAMAGE AT THE CENTRE  %d%% AT THE EDGE" % [float(c["blast"]), int(roundf(float(c["blast_damage"]))), int(roundf(float(c.get("blast_edge", 0.4)) * 100.0))])
	elif bool(c["falloff"]):
		out.append("FULL DAMAGE TO %d M  WEAK AT %d M" % [int(roundf(float(c["range_eff"]))), int(roundf(float(c["range_max"])))])
	else:
		out.append("FULL DAMAGE TO %d M" % int(roundf(float(c["range_max"]))))
	return out
