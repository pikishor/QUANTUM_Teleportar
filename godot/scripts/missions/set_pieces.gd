class_name SetPieces
extends RefCounted
## Three scripted boss set pieces built only from existing systems: each is a chain of ordinary campaign steps (chase, defend, kill_target, survive) called phases, spliced into a
## chapter by CampaignRunner.start_chapter(), plus an environmental hazard per phase (timed strike zones: warning, then damage) and a cinematic intro / outro (Cinematics ids
## "sp_in" / "sp_out", planned here from CinePlan shots).
##   bridge_chase   chapter 2 (index 1), optional   collapsing bridge: run down the courier, then hold while spans drop
##   rooftop_siege  chapter 5 (index 4), optional   helicopter-drone siege: survive waves under rocket strikes, then break the lead drone
##   reactor_core   chapter 8 (index 7), finale     reactor hall: defend the vents under arcs, then kill the Warden's core guard
## Optional pieces can be skipped (CampaignRunner.skip_set_piece()) or are dropped after SKIP_AFTER_FAILS failures; the finale cannot.
## A phase step carries: set_piece (id), phase (index), phases (count), sp_first / sp_last (bool), optional (bool), hazard {period, warn, radius, dmg, count, spread}.

const SKIP_AFTER_FAILS := 2
const IDS: Array[StringName] = [&"bridge_chase", &"rooftop_siege", &"reactor_core"]

const DEFS := {
	&"bridge_chase": {
		"title": "COLLAPSING BRIDGE", "chapter": 1, "optional": true, "after": 1,
		"phases": [
			{"kind": "chase", "obj": "Chase the courier across the bridge", "hp": 120.0, "time": 150.0,
				"hazard": {"period": 7.0, "warn": 1.6, "radius": 5.0, "dmg": 18.0, "count": 2, "spread": 16.0}},
			{"kind": "survive", "obj": "Hold the span while it drops", "hold": 40.0, "gap": 12.0,
				"hazard": {"period": 5.0, "warn": 1.4, "radius": 6.0, "dmg": 22.0, "count": 3, "spread": 18.0}},
		],
	},
	&"rooftop_siege": {
		"title": "ROOFTOP SIEGE", "chapter": 4, "optional": true, "after": 2,
		"phases": [
			{"kind": "defend", "obj": "Hold the rooftop against the drones", "hold": 45.0, "gap": 11.0,
				"hazard": {"period": 6.0, "warn": 1.5, "radius": 5.5, "dmg": 20.0, "count": 2, "spread": 14.0}},
			{"kind": "survive", "obj": "Survive the helicopter strafing run", "hold": 30.0, "gap": 9.0,
				"hazard": {"period": 4.5, "warn": 1.2, "radius": 5.0, "dmg": 20.0, "count": 3, "spread": 16.0}},
			{"kind": "kill_target", "enemy": "overseer", "target": "boss", "guards": 0, "hp_mult": 0.8, "name": "LEAD DRONE", "obj": "Break the lead drone",
				"hazard": {"period": 6.0, "warn": 1.5, "radius": 5.5, "dmg": 20.0, "count": 2, "spread": 14.0}},
		],
	},
	&"reactor_core": {
		"title": "REACTOR CORE", "chapter": 7, "optional": false, "after": 3,
		"phases": [
			{"kind": "defend", "obj": "Hold the coolant vents", "hold": 45.0, "gap": 11.0,
				"hazard": {"period": 6.0, "warn": 1.4, "radius": 5.0, "dmg": 20.0, "count": 2, "spread": 12.0}},
			{"kind": "survive", "obj": "Survive the core surge", "hold": 35.0, "gap": 9.0,
				"hazard": {"period": 4.0, "warn": 1.2, "radius": 5.5, "dmg": 24.0, "count": 3, "spread": 14.0}},
			{"kind": "kill_target", "enemy": "overseer", "target": "boss", "guards": 0, "hp_mult": 1.2, "name": "CORE GUARD", "obj": "Destroy the core guard",
				"hazard": {"period": 5.0, "warn": 1.3, "radius": 5.5, "dmg": 22.0, "count": 3, "spread": 14.0}},
		],
	},
}


## The set piece id attached to a campaign chapter index, &"" for none.
static func id_for_chapter(chapter_index: int) -> StringName:
	for id: StringName in IDS:
		if int(DEFS[id]["chapter"]) == chapter_index:
			return id
	return &""


static func is_optional(id: StringName) -> bool:
	return DEFS.has(id) and bool(DEFS[id]["optional"])


## The phase steps of a set piece as normalised step dictionaries marked with the keys documented above.
static func phase_steps(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DEFS.has(id):
		return out
	var d: Dictionary = DEFS[id]
	var ph: Array = d["phases"]
	for i in ph.size():
		var raw: Dictionary = (ph[i] as Dictionary).duplicate(true)
		raw["id"] = "%s_%d" % [id, i]
		var s := CampaignSteps.normalize_step(raw, i)
		s["set_piece"] = id
		s["phase"] = i
		s["phases"] = ph.size()
		s["sp_first"] = i == 0
		s["sp_last"] = i == ph.size() - 1
		s["optional"] = bool(d["optional"])
		out.append(s)
	return out


## `list` (a chapter's normalised steps) with the chapter's set piece phases inserted after step index "after" - 1 (clamped, so the closing step stays last when there is one).
static func splice(list: Array[Dictionary], chapter_index: int) -> Array[Dictionary]:
	var id := id_for_chapter(chapter_index)
	if id == &"" or list.is_empty():
		return list
	for s in list:
		if s.has("set_piece"):
			return list
	var at := clampi(int(DEFS[id]["after"]), 0, list.size() - 1)
	var out: Array[Dictionary] = []
	out.append_array(list.slice(0, at))
	out.append_array(phase_steps(id))
	out.append_array(list.slice(at))
	return out


## Index of the first step after the set piece phases that begin at `from` (for skipping an optional piece).
static func end_index(list: Array[Dictionary], from: int) -> int:
	var id: Variant = list[from].get("set_piece", null) if from >= 0 and from < list.size() else null
	var i := from
	while i < list.size() and list[i].get("set_piece", null) == id:
		i += 1
	return i


# --- hazards ---------------------------------------------------------------------------------------------------------------------

## Strike cycle `cycle` of hazard h around `anchor`: `count` zone centres (deterministic from the cycle number).
static func zones(h: Dictionary, cycle: int, anchor: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := int(h.get("count", 1))
	var spread := float(h.get("spread", 10.0))
	for i in n:
		var a := float(hash("%d|%d" % [cycle, i]) % 6283) / 1000.0
		var r := spread * (0.35 + 0.65 * float(hash("r%d|%d" % [cycle, i]) % 100) / 100.0)
		out.append(anchor + Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


## Where cycle time `t` seconds into a hazard is: &"idle" (first part of the period), &"warn" (the last `warn` seconds before the hit) or &"hit" (a 0.3 s window).
static func hazard_state(h: Dictionary, t: float) -> StringName:
	var period := maxf(float(h.get("period", 6.0)), 0.5)
	var u := fposmod(t, period)
	var warn := minf(float(h.get("warn", 1.5)), period - 0.4)
	if u >= period - 0.3:
		return &"hit"
	if u >= period - 0.3 - warn:
		return &"warn"
	return &"idle"


static func cycle_of(h: Dictionary, t: float) -> int:
	return int(floorf(t / maxf(float(h.get("period", 6.0)), 0.5)))


## Damage a point takes from the zones of a hit window (0 when not hitting or outside every zone; one strike counts once).
static func damage_at(h: Dictionary, t: float, anchor: Vector3, p: Vector3) -> float:
	if hazard_state(h, t) != &"hit":
		return 0.0
	for z in zones(h, cycle_of(h, t), anchor):
		if Vector2(p.x - z.x, p.z - z.z).length() < float(h.get("radius", 5.0)):
			return float(h.get("dmg", 15.0))
	return 0.0


# --- cinematics ------------------------------------------------------------------------------------------------------------------

## Intro ("sp_in") and outro ("sp_out") plans: ctx {boss (focus point), hero, face}. Skippable, no slow motion.
static func plan(id: StringName, set_piece: StringName, ctx: Dictionary) -> CinePlan:
	var p: CinePlan
	var title := str(DEFS.get(set_piece, {}).get("title", "SET PIECE"))
	if id == &"sp_in":
		p = CinePlan.boss_in(ctx)
		p.head = title
		p.sub_line = ""
		p.subs = []
	else:
		p = CinePlan.boss_out(ctx)
		p.head = title
		p.sub_line = "CLEARED"
		p.subs = []
		p.slowmo = false
	p.id = id
	return p
