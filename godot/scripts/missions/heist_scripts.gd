class_name HeistScripts
extends RefCounted
## Pure data and rules of the three heist missions (wave 71). The runner is scripts/missions/heist_runner.gd (Game.missions.heists); nothing here touches the scene tree.
## A heist is a CHAPTER DICTIONARY of campaign steps (CampaignSteps kinds, run by CampaignRunner), built from the heist and the approach picked on the planning screen:
##   vault       EXCHANGE VAULT   reach the exchange, hack the door lock, (approach stage), heist (go in, take the data, getaway)
##   convoy      CITY CONVOY      reach the road, convoy_intercept (a train of traffic cars), (approach stage), escape
##   datacenter  DATA CENTRE      reach the campus, hack the gate, (approach stage), heist inside the server room, (loud: the sysop)
## APPROACH: stealth = low heat, no patrols, no fights (a hack or nothing); loud = heat 3 and three patrol vehicles, a wave fight stage, pay x1.4; quantum = a short rift_hold fed by verbs,
## fewer cars / one patrol, pay x1.2. CREW (companion, optional) adds the Vael defector for the run. Pay: Economy.HEIST_PAY x Economy.HEIST_APPROACH x sector factor x reputation bonus,
## HEIST_REPLAY of that on a repeat. Replayable: nothing locks after a run.

const IDS: Array[StringName] = [&"vault", &"convoy", &"datacenter"]
const APPROACHES: Array[StringName] = [&"stealth", &"loud", &"quantum"]
const MAX_FAILS := 3                    ## step failures in one run before the heist is called off
const FAIL_REP := -1
const WIN_REP := 6

const DEFS := {
	&"vault": {"title": "EXCHANGE VAULT", "brief": "Hack the lock, take the ledger data, get away clean.", "stages": "REACH  HACK  APPROACH  VAULT  GETAWAY", "interior": &"lobby"},
	&"convoy": {"title": "CITY CONVOY", "brief": "Stop the armoured train of cars on the road and run.", "stages": "REACH  INTERCEPT  APPROACH  GETAWAY", "interior": &""},
	&"datacenter": {"title": "DATA CENTRE", "brief": "Crack the gate, copy the core, leave nothing behind.", "stages": "REACH  HACK  APPROACH  CORE  GETAWAY", "interior": &"server_room"},
}

const APPROACH_DEFS := {
	&"stealth": {"title": "STEALTH", "note": "Quiet. Low heat, no patrols, no fights.", "heat": 1.0, "patrol": 0, "cars": 1},
	&"loud": {"title": "LOUD", "note": "Fire power. Heat 3, three patrols, a fight. Pays most.", "heat": 3.0, "patrol": 3, "cars": 3},
	&"quantum": {"title": "QUANTUM", "note": "Verbs open the way. One patrol, a short rift.", "heat": 2.0, "patrol": 1, "cars": 2},
}


static func title(id: StringName) -> String:
	return String(DEFS.get(id, {}).get("title", String(id).to_upper()))


static func approach_title(ap: StringName) -> String:
	return String(APPROACH_DEFS.get(ap, {}).get("title", String(ap).to_upper()))


## Sector needed (Economy.HEIST_CHAPTER); DEMO MODE opens all of them.
static func unlocked(id: StringName, chapter: int) -> bool:
	return DEFS.has(id) and (chapter >= int(Economy.HEIST_CHAPTER[id]) or DemoMode.active)


## The chapter dictionary of one run. `id` and `ap` outside the tables give {}.
static func chapter(id: StringName, ap: StringName) -> Dictionary:
	if not DEFS.has(id) or not APPROACH_DEFS.has(ap):
		return {}
	var a: Dictionary = APPROACH_DEFS[ap]
	var t := title(id)
	var steps: Array = []
	match id:
		&"vault":
			steps.append({"kind": "reach", "text": "Get to the exchange", "radius": 9.0})
			steps.append({"kind": "hack", "text": "Hack the vault lock", "hold": 12.0 if ap == &"stealth" else 16.0, "count": 0 if ap == &"stealth" else 2})
			steps.append_array(_extra(ap, "vault"))
			steps.append({"kind": "heist", "interior": "lobby", "text": "Take the exchange data", "heat": a["heat"], "patrol": a["patrol"], "escape_time": 140.0 if ap == &"stealth" else 110.0})
		&"convoy":
			steps.append({"kind": "reach", "text": "Get to the convoy road", "radius": 9.0})
			steps.append({"kind": "convoy_intercept", "text": "Stop the convoy", "cars": a["cars"], "time": 150.0})
			steps.append_array(_extra(ap, "convoy"))
			steps.append({"kind": "escape", "text": "Lose the pursuit", "heat": a["heat"], "patrol": a["patrol"], "time": 150.0})
		&"datacenter":
			steps.append({"kind": "reach", "text": "Get to the data centre", "radius": 9.0})
			steps.append({"kind": "hack", "text": "Crack the gate", "hold": 12.0 if ap == &"stealth" else 18.0, "count": 0 if ap == &"stealth" else 3})
			steps.append_array(_extra(ap, "datacenter"))
			steps.append({"kind": "heist", "interior": "server_room", "text": "Copy the core", "heat": a["heat"], "patrol": a["patrol"], "escape_time": 140.0 if ap == &"stealth" else 110.0})
			if ap == &"loud":
				steps.insert(steps.size() - 1, {"kind": "kill_target", "text": "Take out the sysop", "guards": 2})
	for i in steps.size():
		var s: Dictionary = steps[i]
		s["id"] = "heist_%s_%d" % [id, i]
		s["text"] = "%s  %s" % [t, String(s["text"])] if String(s["text"]).length() + t.length() + 2 <= CampaignSteps.MAX_TEXT else String(s["text"])
	return {"id": "heist_%s_%s" % [id, ap], "title": t, "clears_sector": false, "steps": steps}


## The approach's own stage between the opening and the job.
static func _extra(ap: StringName, _id: String) -> Array:
	match ap:
		&"loud":
			return [{"kind": "defend", "text": "Hold the zone", "hold": 35.0, "count": 3}]
		&"quantum":
			return [{"kind": "rift_hold", "text": "Hold the rift open", "hold": 20.0, "count": 1}]
	return []


## Credits: base x approach x sector factor x reputation bonus, a multiple of 5, never below 5; `replay` keeps Economy.HEIST_REPLAY of it.
static func reward(id: StringName, ap: StringName, chapter_i: int, rep: int, replay: bool) -> int:
	if not DEFS.has(id) or not APPROACH_DEFS.has(ap):
		return 0
	var v := float(Economy.HEIST_PAY[id]) * float(Economy.HEIST_APPROACH[ap]) * float(Progress.difficulty(chapter_i)["reward"]) * (1.0 + Progress.rep_bonus(rep))
	if replay:
		v *= Economy.HEIST_REPLAY
	return maxi(5, int(round(v / 5.0)) * 5)


## "" when the entry is complete and sane (the test walks every id and approach).
static func validate(id: StringName, ap: StringName) -> String:
	if not DEFS.has(id) or not Economy.HEIST_PAY.has(id) or not Economy.HEIST_CHAPTER.has(id):
		return "missing table entry"
	if not APPROACH_DEFS.has(ap) or not Economy.HEIST_APPROACH.has(ap):
		return "missing approach"
	var ch := chapter(id, ap)
	var why := CampaignSteps.validate_chapter(ch)
	if not why.is_empty():
		return why[0]
	if String(DEFS[id]["brief"]).length() > 80 or String(APPROACH_DEFS[ap]["note"]).length() > 80:
		return "text too long"
	var iid := StringName(DEFS[id]["interior"])
	if iid != &"" and not InteriorData.TYPES.has(iid):
		return "unknown interior"
	return ""
