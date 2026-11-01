class_name InteriorData
extends RefCounted
## Plain data of the interior gameplay: door types and names, actor budgets, vendor stock, rumours, mission definitions and the interior radio lines.
## Nothing here touches the scene tree; tests/test_interior_gameplay.gd checks the limits (radio lines fit a phone screen, actor budgets stay in 3..5).

const TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"club", &"lobby", &"apartment", &"checkpoint", &"bodega", &"warehouse"]
const VENDOR_TYPES: Array[StringName] = [&"weapons", &"clinic", &"tech", &"bar", &"bodega"]
const MISSION_TYPES: Array[StringName] = [&"lobby", &"apartment", &"club", &"checkpoint"]
const ACTOR_CAP := 5
const ACTOR_MIN := 3

const TITLES := {
	&"weapons": "ARMS DEALER", &"clinic": "CLINIC", &"tech": "TECH DEN", &"bar": "BAR", &"club": "CLUB",
	&"lobby": "OFFICE LOBBY", &"apartment": "APARTMENT", &"checkpoint": "VAEL CHECKPOINT", &"bodega": "CORNER STORE", &"warehouse": "WAREHOUSE",
}
## Door glow colours: vendors cyan, bars amber, mission interiors magenta (club, lobby, apartment) / red (Vael checkpoint).
const COLORS := {
	&"weapons": Color(0.35, 0.95, 1.0), &"clinic": Color(0.4, 1.0, 0.6), &"tech": Color(0.5, 0.7, 1.0), &"bar": Color(1.0, 0.72, 0.25),
	&"club": Color(1.0, 0.25, 0.75), &"lobby": Color(1.0, 0.45, 0.9), &"apartment": Color(1.0, 0.6, 0.35), &"checkpoint": Color(1.0, 0.3, 0.32),
	&"bodega": Color(0.7, 1.0, 0.45), &"warehouse": Color(0.8, 0.8, 0.9),
}
const NAME_A: Array[String] = ["KESTREL", "NEON", "ROOK", "HALCYON", "SILT", "ORBIT", "VANTA", "CINDER", "TIDE", "LUMEN", "SABLE", "ARC"]
const NAME_B := {
	&"weapons": ["ARMS", "ORDNANCE", "SURPLUS", "GUNWORKS"], &"clinic": ["CLINIC", "MEDBAY", "WARD", "CARE"], &"tech": ["DEN", "SALVAGE", "CIRCUITS", "LAB"],
	&"bar": ["BAR", "TAP", "LOUNGE", "CANTINA"], &"club": ["CLUB", "PIT", "HALL", "ROOM"], &"lobby": ["TOWER", "HOLDINGS", "PLAZA", "OFFICES"],
	&"apartment": ["APARTMENTS", "FLATS", "COURT", "BLOCK"], &"checkpoint": ["CHECKPOINT", "GATE", "POST", "STATION"],
	&"bodega": ["MARKET", "GROCERY", "CORNER", "MART"], &"warehouse": ["STORAGE", "FREIGHT", "DEPOT", "YARD"],
}

## Door type weights (sum 1.0), used by CityDoors in the world module.
const WEIGHTS: Array[float] = [0.14, 0.11, 0.11, 0.14, 0.09, 0.09, 0.10, 0.07, 0.09, 0.06]


static func title(type: StringName) -> String:
	return str(TITLES.get(type, "INTERIOR"))


static func color(type: StringName) -> Color:
	return COLORS.get(type, Color(0.45, 0.95, 1.0))


static func door_name(type: StringName, id: int) -> String:
	var b: Array = NAME_B.get(type, ["PLACE"])
	var h := fposmod(sin(float(id) * 12.9898 + 4.1) * 43758.5453, 1.0)
	var h2 := fposmod(sin(float(id) * 78.233 + 1.7) * 43758.5453, 1.0)
	return "%s %s" % [NAME_A[int(h * NAME_A.size()) % NAME_A.size()], str(b[int(h2 * b.size()) % b.size()])]


static func has_vendor(type: StringName) -> bool:
	return VENDOR_TYPES.has(type)


static func mission_for(type: StringName) -> StringName:
	match type:
		&"lobby": return &"safe"
		&"apartment": return &"hostage"
		&"club": return &"assassinate"
		&"checkpoint": return &"hack"
	return &""


# --- actors ---------------------------------------------------------------------------------------------------------

## Who stands in an interior: {vendor, civilians, guards}. The sum never exceeds ACTOR_CAP and is at least ACTOR_MIN. Mission actors (the hostage, the officer) are counted
## as part of these (the hostage is one of the civilians, the officer one of the guards) so the cap holds in every interior.
const PLAN := {
	&"weapons": {"vendor": 1, "civilians": 2, "guards": 1},
	&"clinic": {"vendor": 1, "civilians": 3, "guards": 0},
	&"tech": {"vendor": 1, "civilians": 1, "guards": 2},
	&"bar": {"vendor": 1, "civilians": 3, "guards": 1},
	&"club": {"vendor": 0, "civilians": 2, "guards": 3},            # one of the guards is the hidden officer
	&"lobby": {"vendor": 0, "civilians": 2, "guards": 2},
	&"apartment": {"vendor": 0, "civilians": 1, "guards": 3},        # the civilian is the hostage
	&"checkpoint": {"vendor": 0, "civilians": 0, "guards": 3},
	&"bodega": {"vendor": 1, "civilians": 3, "guards": 0},
	&"warehouse": {"vendor": 0, "civilians": 1, "guards": 3},
}


## The plan for `type` with `followers` hunters that came in from the street: guards first, then civilians give way so the total stays within ACTOR_CAP.
static func plan(type: StringName, followers := 0) -> Dictionary:
	var p: Dictionary = (PLAN.get(type, PLAN[&"bar"]) as Dictionary).duplicate()
	var over: int = int(p["vendor"]) + int(p["civilians"]) + int(p["guards"]) + followers - ACTOR_CAP
	while over > 0 and int(p["guards"]) > 0 and int(p["guards"]) + followers > 1:
		p["guards"] = int(p["guards"]) - 1
		over -= 1
	while over > 0 and int(p["civilians"]) > 0:
		p["civilians"] = int(p["civilians"]) - 1
		over -= 1
	p["followers"] = followers
	return p


static func actor_total(p: Dictionary) -> int:
	return int(p["vendor"]) + int(p["civilians"]) + int(p["guards"]) + int(p.get("followers", 0))


# --- vendors --------------------------------------------------------------------------------------------------------

## Stock per vendor type. kind: "upgrade" (Progress.buy), "weapon" (Progress.buy_weapon, owned = sold out), "ammo" (rounds for an owned weapon), "heal", "energy", "rumour", "drink".
const STOCK := {
	&"weapons": [
		{"id": &"scatter", "kind": "weapon", "name": "SHARD SCATTER"}, {"id": &"lance", "kind": "weapon", "name": "PULSE LANCE"},
		{"id": &"grenade", "kind": "weapon", "name": "SINGULARITY GRENADE"},
		{"id": &"ammo_scatter", "kind": "ammo", "weapon": &"scatter", "rounds": 12, "price": 60, "name": "SCATTER SHELLS  +12"},
		{"id": &"ammo_lance", "kind": "ammo", "weapon": &"lance", "rounds": 5, "price": 90, "name": "LANCE CELLS  +5"},
		{"id": &"ammo_grenade", "kind": "ammo", "weapon": &"grenade", "rounds": 2, "price": 120, "name": "SINGULARITIES  +2"},
		{"id": &"damage", "kind": "upgrade", "name": "WEAPON DAMAGE"},
	],
	&"clinic": [
		{"id": &"heal", "kind": "heal", "price": 40, "name": "FULL REPAIR"}, {"id": &"energy", "kind": "energy", "price": 30, "name": "COHERENCE DOSE"},
		{"id": &"armour", "kind": "upgrade", "name": "ARMOUR"}, {"id": &"regen", "kind": "upgrade", "name": "COHERENCE REGEN"},
	],
	&"tech": [
		{"id": &"blink", "kind": "upgrade", "name": "BLINK RANGE"}, {"id": &"reload", "kind": "upgrade", "name": "RELOAD SPEED"},
		{"id": &"mag", "kind": "upgrade", "name": "MAGAZINE"}, {"id": &"energy", "kind": "energy", "price": 30, "name": "COHERENCE CELL"},
	],
	&"bar": [
		{"id": &"rumour", "kind": "rumour", "price": 20, "name": "BUY A RUMOUR"}, {"id": &"drink", "kind": "drink", "price": 10, "name": "SYNTH DRINK  +25 HP"},
	],
	&"bodega": [
		{"id": &"drink", "kind": "drink", "price": 10, "name": "SYNTH DRINK  +25 HP"}, {"id": &"heal", "kind": "heal", "price": 55, "name": "FIELD KIT  FULL REPAIR"},
		{"id": &"energy", "kind": "energy", "price": 35, "name": "COHERENCE CELL"},
	],
}

## The rumour pool: even entries are story (a radio line), odd entries come with a hint at an interior contract (the hinted door glows on the minimap).
const RUMOURS: Array[String] = [
	"They say the Vael Overseers carry a key shard. Take one down and it opens things.",
	"A lobby on the grid keeps a data safe the Observers never audited. Worth cracking.",
	"The drones read fear, not faces. Stay calm and they walk past you.",
	"Someone is held in a flat nearby. Vael guards, three of them. Nobody has come back.",
	"Rift sickness is real. People hum before they fade. Stay near the light.",
	"A Vael officer hides in the back of a club. He hates noise. Be quiet or be loud, not both.",
	"The quantum cores sing at night. If you hear it near a wall, the core is close.",
	"A checkpoint terminal still talks to the old network. Hack it and the guards come running.",
]

## Radio lines (ORACLE / KESTREL) per interior type, and per mission stage. Each at most StoryData.LINE_MAX characters.
const RADIO := {
	&"weapons": [
		["ORACLE", "Arms dealer. Every barrel in here was pulled from a Vael wreck. Pay in credits, not questions."],
		["KESTREL", "A counter, a cage and a man who has seen worse than me. Fine."],
	],
	&"clinic": [
		["ORACLE", "Coherence clinic. They patch what the Observers drain. I will not charge you for the scan."],
		["KESTREL", "Warm light for once. I could almost forget the rain."],
	],
	&"tech": [
		["ORACLE", "A tech den. Rift salvage in every drawer. Ask for the quantum bench."],
		["KESTREL", "Half of this is my old lab, resold in pieces."],
	],
	&"bar": [
		["ORACLE", "A bar. Rumours are the only currency the Vael cannot tax. Buy one."],
		["KESTREL", "Quiet corners, loud neon. People talk when they think the drones are deaf."],
	],
	&"club": [
		["ORACLE", "A club. Loud enough to hide a gunshot and an officer. One of them is here."],
		["KESTREL", "Bass in my teeth. The kind of dark where you hear a man before you see him."],
	],
	&"lobby": [
		["ORACLE", "A corporate lobby. Marble, cameras and a safe that holds a ledger of Vael collaborators."],
		["KESTREL", "Polished floors, quiet guards. Someone sold this city out in here."],
	],
	&"apartment": [
		["ORACLE", "Residential. I read three Vael heat traces and one human pulse. Somebody is held."],
		["KESTREL", "Family photos on the wall. I will not leave without whoever lives here."],
	],
	&"checkpoint": [
		["ORACLE", "A Vael checkpoint. Armoured, watched, and wired into the old network. I can ride a terminal in."],
		["KESTREL", "Walls full of eyes. Let them close in. I will be quicker."],
	],
	&"bodega": [
		["ORACLE", "A corner store. Synth food, cheap kits, a clerk who has not looked up from the counter in years."],
		["KESTREL", "Rain on the awning, a hum from the cooler. Almost like a normal night."],
	],
	&"warehouse": [
		["ORACLE", "Freight depot. Vael crates, Vael guards, nothing a collaborator should be storing."],
		["KESTREL", "Stacked cargo and long sight lines. Keep to the aisles."],
	],
	&"heat": [
		["ORACLE", "They followed you in. Doors do not stop the Vael, only the rain."],
		["KESTREL", "I carry the heat in here with me. It does not cool behind a wall."],
	],
	&"exit": [
		["ORACLE", "Back on the street. The rain remembers you."],
	],
}

const MISSION_LINES := {
	&"safe": {"start": "The safe is in the back. Crack it quietly: guards drift past every few seconds.", "done": "Ledger copied. Names, dates, bribes. The collaborators have a problem now.",
			"alarm": "The vault shrieked. They know. Walk out or burn through them."},
	&"hostage": {"start": "Three Vael inside, one captive. Clear the room first or the hostage dies in the crossfire.", "done": "She is free. Tell her to run. The city will be kinder to her than to us.",
			"clear": "Room clear. Cut the restraints."},
	&"assassinate": {"start": "A Vael officer hides here, away from the dance floor. Find him in the back booths.", "done": "Officer down. The hive will be blind in this block for hours.",
			"found": "That is him. The one pretending not to watch."},
	&"hack": {"start": "Stay at the terminal. Every few seconds the checkpoint sends someone to check on it.", "done": "Terminal burned through. I own the gate cameras for ten minutes.",
			"wave": "Guards closing in. Hold the console."},
}

## Rewards before the sector and reputation factors: credits, score, reputation.
const REWARDS := {
	&"safe": {"credits": 320, "score": 300, "rep": 5},
	&"hostage": {"credits": 420, "score": 400, "rep": 8},
	&"assassinate": {"credits": 620, "score": 600, "rep": 6},
	&"hack": {"credits": 460, "score": 450, "rep": 4},
}


static func reward(kind: StringName, chapter: int, rep: int) -> Dictionary:
	var r: Dictionary = REWARDS.get(kind, {"credits": 100, "score": 100, "rep": 1})
	var diff := Progress.difficulty(chapter)
	var f: float = float(diff["reward"]) * (1.0 + Progress.rep_bonus(rep))
	return {"credits": int(roundf(float(r["credits"]) * f / 5.0)) * 5, "score": int(float(r["score"]) * f), "rep": int(r["rep"])}


## Every radio line (speaker, text) of this file, for the length test.
static func all_lines() -> Array:
	var out: Array = []
	for k: StringName in RADIO:
		for pair: Array in RADIO[k]:
			out.append(pair)
	for k: StringName in MISSION_LINES:
		for stage: String in MISSION_LINES[k]:
			out.append(["ORACLE", str(MISSION_LINES[k][stage])])
	for t in RUMOURS:
		out.append(["ORACLE", t])
	return out
