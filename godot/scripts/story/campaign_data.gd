class_name CampaignData
extends RefCounted
## The twelve-chapter campaign (eight chapters plus the sequel arc, chapters 9 to 12) as plain data: for each chapter a place (district), a chain of 3..5 scripted objective steps, one radio line per step, and the
## cutscene trigger ids. Nothing here runs; it only extends scripts/story/story_data.gd (CHAPTERS[i] has the same id as CAMPAIGN[i], the intro / core / heat
## lines and the end card live there). After the last chapter the game continues as endless sectors (StoryData's aftermath chapter), see is_endless().
##
## A step is {kind, obj, radio}: kind is one of STEP_KINDS, obj the objective line (at most StoryData.OBJ_MAX characters), radio one line {s, t} said when the
## step starts (at most StoryData.LINE_MAX). Optional keys: "interior" (infiltrate only: a mission interior type of InteriorData.MISSION_TYPES), "target"
## (assassinate only: "specialist" or "boss"), "patrol" (escape only: how many Vael patrol vehicles chase the player, see campaign_steps.gd). A chapter's "cutscenes" are ids the Cinematics node can play (KNOWN_CUTSCENES): intro (once per run, may be ""),
## chapter (the objective card), boss (played before the boss step, required exactly when a step has target "boss", "" otherwise).
## Rules checked by tests/test_campaign_data.gd.

const O := StoryData.O
const K := StoryData.K
const A := StoryData.A

const STEP_KINDS: Array[StringName] = [&"reach", &"infiltrate", &"escort", &"defend", &"hack", &"assassinate", &"chase", &"escape", &"rift_hold", &"heist", &"convoy_intercept"]
## Cutscene ids: the first three exist in cinematics (cine_plan.gd), "credits" is the ending sequence described by CREDITS below.
const KNOWN_CUTSCENES: Array[String] = ["", "intro", "chapter", "boss_in", "boss_out", "credits", "credits2"]
const DISTRICT_IDS: Array[String] = ["market", "foundry", "slums", "towers"]   ## same ids as CityDistricts.IDS
const MIN_STEPS := 3
const MAX_STEPS := 5
const CHAPTER_COUNT := 12
const CREDIT_LINE_MAX := 40

const CAMPAIGN: Array[Dictionary] = [
	{
		"id": "split_hour", "district": "market", "place": "OLD EXCHANGE",
		"cutscenes": {"intro": "intro", "chapter": "chapter", "boss": ""},
		"steps": [
			{"kind": "reach", "obj": "Cross the trading floor to the beacon", "radio": {"s": O, "t": "Beacon is live. Cross the trading floor and keep to the shadow of the pillars."}},
			{"kind": "infiltrate", "interior": "lobby", "obj": "Slip into the Exchange lobby", "radio": {"s": O, "t": "The lobby is a Vael checkpoint dressed as an office. Quiet hands, Kestrel."}},
			{"kind": "hack", "obj": "Hack the ledger node", "radio": {"s": K, "t": "The ledger counts people as units of coherence. I am rewriting the sums."}},
		],
	},
	{
		"id": "bell_state", "district": "towers", "place": "GLASS DISTRICT",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Blink up to the sky bridge", "radio": {"s": O, "t": "The sky bridge is the only blind spot. Throw a beacon, cross the gap, count two bits."}},
			{"kind": "hack", "obj": "Hack the relay under the glass", "radio": {"s": O, "t": "The relay node watches every pane. Blind it and the towers stop reporting you."}},
			{"kind": "chase", "obj": "Run down the courier convoy", "radio": {"s": O, "t": "A Vael courier is carrying a core fragment east. Take a car and cut it off."}},
			{"kind": "assassinate", "target": "specialist", "obj": "Eliminate the Glass specialist", "radio": {"s": O, "t": "Their measurement specialist watches from the tallest pane. End the observer."}},
			{"kind": "assassinate", "target": "boss", "enemy": "phasewright", "hp_mult": 1.0, "guards": 0, "name": "VAEL PHASEWRIGHT", "obj": "Break the Vael Phasewright", "radio": {"s": O, "t": "The observer had a keeper. It jumps like you do. COLLAPSE the windup, punish the landing."}},
		],
	},
	{
		"id": "harvest_floor", "district": "slums", "place": "HARVEST FLOOR",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Reach the harvest rig perimeter", "radio": {"s": O, "t": "The rig is ringed by sleepers on drips. Do not wake them. Go around."}},
			{"kind": "infiltrate", "interior": "apartment", "obj": "Find the survivor in the apartment", "radio": {"s": O, "t": "A human is hiding inside, still awake. She knows where the rig's heart is."}},
			{"kind": "escort", "obj": "Escort the survivor to the evac point", "radio": {"s": K, "t": "Stay close to me. If a drone looks at you, look at the floor."}},
			{"kind": "defend", "obj": "Defend the evac point", "radio": {"s": O, "t": "Drones are converging on her heartbeat. Hold the corner until the van leaves."}},
			{"kind": "assassinate", "target": "boss", "obj": "Kill the Vael Overseer", "radio": {"s": O, "t": "The Overseer has woken. This is the last thing keeping the harvest running."}},
		],
	},
	{
		"id": "no_cloning", "district": "foundry", "place": "BRIDGE ARCADE",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Reach the arcade overpass", "radio": {"s": O, "t": "The overpass is the only crossing the Vael do not hover over. Reach it fast."}},
			{"kind": "chase", "obj": "Chase the Vael hauler across the bridge", "radio": {"s": O, "t": "That hauler carries a cradle. Run it down before it reaches the foundry gate."}},
			{"kind": "defend", "obj": "Hold the bridge against the counterstrike", "radio": {"s": O, "t": "They are sending copies of what they cannot copy. Hold the span, Kestrel."}},
			{"kind": "assassinate", "target": "boss", "enemy": "smelter", "hp_mult": 0.8, "guards": 0, "name": "VAEL SMELTER", "obj": "Kill the Vael Smelter", "radio": {"s": O, "t": "The Smelter vents the floor. ENTANGLE it into a ring while the vent is armed."}},
			{"kind": "escape", "patrol": 1, "obj": "Escape the Vael patrol", "radio": {"s": O, "t": "A hunter patrol is on your frequency. Break line of sight and lose them in the arches."}},
		],
	},
	{
		"id": "forge_of_mirrors", "district": "foundry", "place": "FOUNDRY ROW",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "infiltrate", "interior": "checkpoint", "obj": "Infiltrate the forge checkpoint", "radio": {"s": O, "t": "The checkpoint controls the forge doors. Take it from the inside, one guard at a time."}},
			{"kind": "hack", "obj": "Hack the cradle control node", "radio": {"s": K, "t": "Cradle control. If I cannot shut it down, I can at least make it blind."}},
			{"kind": "assassinate", "target": "specialist", "obj": "Eliminate the forge master", "radio": {"s": O, "t": "The forge master tends the cradles like a gardener. Make the garden stop growing."}},
			{"kind": "assassinate", "target": "boss", "enemy": "skimmer", "hp_mult": 1.0, "guards": 0, "name": "VAEL SKIMMER", "obj": "Crash the Vael Skimmer", "radio": {"s": O, "t": "A Skimmer is circling the forge on a hover skiff. Dodge the ram, COLLAPSE to crash it."}},
			{"kind": "escape", "obj": "Escape the burning forge", "radio": {"s": O, "t": "The forge is venting. Out, out, out. The Vael will not follow into the fire."}},
		],
	},
	{
		"id": "drowned_relay", "district": "slums", "place": "RAIN SLUMS",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Reach the Lamplighter hideout", "radio": {"s": O, "t": "The Lamplighters hide under a leaking viaduct. Follow the one lit window."}},
			{"kind": "escort", "obj": "Escort the Lamplighters to the relay", "radio": {"s": O, "t": "They carry the shutdown key. Keep them alive and keep them quiet."}},
			{"kind": "hack", "obj": "Hack the drowned relay", "radio": {"s": K, "t": "The hive song is a protocol. Cut the handshake and the lullaby stops."}},
			{"kind": "defend", "obj": "Defend the Lamplighters while the key turns", "radio": {"s": O, "t": "The key needs ninety seconds. Everything the Vael have is coming down this street."}},
			{"kind": "assassinate", "target": "boss", "obj": "Kill the relay Overseer", "radio": {"s": O, "t": "The relay's Overseer is singing the song itself. Break its voice."}},
		],
	},
	{
		"id": "lantern_night", "district": "market", "place": "NEON MARKET",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Reach the festival arch before the sweep", "radio": {"s": O, "t": "The sweep starts at the south arch. Be through it before the lanterns turn red."}},
			{"kind": "infiltrate", "interior": "club", "obj": "Infiltrate the back-room club", "radio": {"s": O, "t": "The club hides a Vael dispatcher behind the music. Walk in like you belong."}},
			{"kind": "assassinate", "target": "boss", "enemy": "bulwark", "hp_mult": 0.85, "guards": 0, "name": "VAEL BULWARK", "obj": "Break the Vael Bulwark", "radio": {"s": O, "t": "The dispatcher's guard carries a shield that stops everything. COLLAPSE breaks it."}},
			{"kind": "assassinate", "target": "boss", "enemy": "hound", "hp_mult": 0.85, "guards": 0, "name": "VAEL HOUND", "obj": "Kill the Vael Hound", "radio": {"s": O, "t": "A Hound is hunting you through the stalls. Give it a decoy and collapse it up close."}},
			{"kind": "escape", "patrol": 2, "obj": "Escape the Vael patrol sweep", "radio": {"s": O, "t": "The patrol is on you. Run for the dark end of the market and do not stop."}},
		],
	},
	{
		"id": "meridian_gate", "district": "towers", "place": "MERIDIAN GATE",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in"},
		"steps": [
			{"kind": "reach", "obj": "Reach the foot of the Meridian Gate", "radio": {"s": O, "t": "The gate is open and humming. Every anchor you took is singing in it."}},
			{"kind": "hack", "obj": "Hack the gate's control spine", "radio": {"s": K, "t": "I know this protocol. It is mine. I can run the signal either way."}},
			{"kind": "defend", "obj": "Defend the spine until the signal turns", "radio": {"s": O, "t": "The hive is throwing itself at the spine. Hold, Kestrel. Hold for the whole minute."}},
			{"kind": "assassinate", "target": "boss", "obj": "Kill the Gate Warden", "radio": {"s": A, "t": "Scout, come home. The Warden will carry you. Nobody has to hurt anymore."}},
			{"kind": "escape", "obj": "Escape the collapsing gate", "radio": {"s": O, "t": "The gate is folding in on itself. Teleport, Kestrel. Two bits, and run."}},
		],
	},
	{
		"id": "echo_tide", "district": "foundry", "place": "COLD DOCKS",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": ""},
		"steps": [
			{"kind": "reach", "obj": "Reach the flooded loading bay", "radio": {"s": O, "t": "The gate fell, but something answers from the docks. Keep to the high gantries, Kestrel."}},
			{"kind": "infiltrate", "interior": "checkpoint", "obj": "Infiltrate the dockmaster checkpoint", "radio": {"s": O, "t": "The checkpoint still takes orders from a signal that should be dead. Go in quiet."}},
			{"kind": "hack", "obj": "Hack the tide relay", "radio": {"s": K, "t": "Same handshake as the gate, run backwards. Someone is listening on the other side."}},
			{"kind": "chase", "obj": "Run down the salvage convoy", "radio": {"s": O, "t": "A convoy is hauling relay parts out of the docks. Take a car and stop it at the bridge."}},
			{"kind": "assassinate", "target": "specialist", "obj": "Eliminate the dock warden", "radio": {"s": O, "t": "The warden keeps the tide gates shut. End it and the water goes where it wants."}},
		],
	},
	{
		"id": "last_aperture", "district": "towers", "place": "ECHO SPIRE",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in", "ending": "credits"},
		"steps": [
			{"kind": "reach", "obj": "Reach the base of the Echo Spire", "radio": {"s": O, "t": "The spire is the last aperture. Every Vael left in the city is leaning toward it."}},
			{"kind": "defend", "obj": "Defend the climb until the lift is ready", "radio": {"s": O, "t": "The lift needs a minute to spin up. They know. Hold the lobby, Kestrel."}},
			{"kind": "assassinate", "target": "boss", "enemy": "hound", "hp_mult": 0.85, "guards": 0, "name": "VAEL HOUND ALPHA", "obj": "Kill the Hound Alpha", "radio": {"s": O, "t": "The pack leader guards the lift. Decoy first, COLLAPSE it while it feeds."}},
			{"kind": "assassinate", "target": "boss", "enemy": "phasewright", "hp_mult": 0.95, "guards": 0, "name": "VAEL PHASEWRIGHT PRIME", "obj": "Break the Phasewright Prime", "radio": {"s": O, "t": "The Prime jumps faster than the first one. Read the windup, COLLAPSE the jump."}},
			{"kind": "escape", "obj": "Escape the folding spire", "radio": {"s": K, "t": "It is closing, ORACLE. Two bits and out. I am not staying to see what is behind it."}},
		],
	},
	{
		"id": "hollow_choir", "district": "slums", "place": "LANTERN YARD",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": ""},
		"steps": [
			{"kind": "reach", "obj": "Reach the dark end of Lantern Yard", "radio": {"s": O, "t": "The spire fell and the Lamplighters went quiet. Something in the yard is singing instead."}},
			{"kind": "heist", "interior": "lobby", "obj": "Steal the choir ledger from the counting house", "radio": {"s": K, "t": "In, take the data, out before the patrols close the street. I have done worse for rent."}},
			{"kind": "convoy_intercept", "cars": 3, "obj": "Stop the convoy hauling the choir relays", "radio": {"s": O, "t": "Three trucks, one road. ENTANGLE swaps you in, COLLAPSE stops what is left."}},
			{"kind": "rift_hold", "hold": 40.0, "count": 2, "obj": "Hold the choir rift open for the relay", "radio": {"s": K, "t": "Feed it everything I have. Keep moving, keep firing, keep it breathing."}},
			{"kind": "assassinate", "target": "specialist", "obj": "Eliminate the choir master", "radio": {"s": O, "t": "The choir master conducts every drone left in the slums. Cut the baton, Kestrel."}},
		],
	},
	{
		"id": "second_gate", "district": "market", "place": "EXCHANGE VAULT",
		"cutscenes": {"intro": "", "chapter": "chapter", "boss": "boss_in", "ending": "credits2"},
		"steps": [
			{"kind": "reach", "obj": "Reach the sealed Exchange vault", "radio": {"s": O, "t": "It ends where it began. The vault under the Old Exchange is the second gate."}},
			{"kind": "hack", "obj": "Hack the vault's last anchor", "radio": {"s": K, "t": "Same signal, last time. If it screams, I will keep my hands on the keys."}},
			{"kind": "defend", "obj": "Hold the vault door against the hive", "radio": {"s": O, "t": "Everything that is left is coming down the stairs. Hold the door, Kestrel."}},
			{"kind": "assassinate", "target": "boss", "enemy": "bulwark", "hp_mult": 1.0, "guards": 0, "name": "VAEL BULWARK PRIME", "obj": "Break the Bulwark Prime", "radio": {"s": O, "t": "It hides behind its own shield. Wait for the shield to drop, then COLLAPSE it."}},
			{"kind": "escape", "obj": "Escape the folding vault", "radio": {"s": K, "t": "It is folding up, ORACLE. Two bits, one run, and nothing left behind us."}},
		],
	},
]

## Endless sectors: after the last chapter every sector plays StoryData's aftermath chapter and draws its objective chain from these kinds.
const ENDLESS_KINDS: Array[StringName] = [&"reach", &"hack", &"defend", &"chase", &"escape"]
const ENDLESS_LABEL := "FREE SECTOR %02d"

## Typed over the win screen after the last chapter's end card, before the credits (head at most 30 characters, text at most StoryData.CARD_MAX).
const ENDING: Array[Dictionary] = [
	{"head": "THE GATE CLOSES", "text": "You ran the signal outward. The last aperture folded in on itself and every Observer in Neo-Meridian fell out of the sky like rain."},
	{"head": "THE CHOICE", "text": "You could have gone home. You stayed, and ORACLE stays with you. It says nothing, which for ORACLE is a kind of love."},
	{"head": "NEO-MERIDIAN", "text": "The rain never stops. It no longer sounds like being watched. Somewhere a Lamplighter turns a lantern back on."},
]

## The credits-style cinematic ("credits"): blocks scroll in order, each shown for CREDITS_BLOCK_SECONDS. {head, lines}. Lines at most CREDIT_LINE_MAX characters.
const CREDITS_BLOCK_SECONDS := 3.6
const CREDITS: Array[Dictionary] = [
	{"head": "QUANTUM TELEPORTAR", "lines": ["A story of two places at once"]},
	{"head": "KESTREL", "lines": ["Quantum engineer", "Vael scout", "Both, and neither"]},
	{"head": "ORACLE", "lines": ["The voice in the dark", "Half corrupted, wholly kept"]},
	{"head": "THE LAMPLIGHTERS", "lines": ["Who kept the streets lit", "Through nine years of rain"]},
	{"head": "THE VAEL", "lines": ["The hive that went quiet"]},
	{"head": "THANK YOU FOR PLAYING", "lines": ["The rain is still loud", "No one is calling you home"]},
]
## Radio lines over the credits ({t0, t1, s, t}, seconds from the start of the scene; the scene lasts CREDITS_BLOCK_SECONDS * CREDITS.size()).
const CREDITS_SUBS: Array[Dictionary] = [
	{"t0": 1.0, "t1": 4.6, "s": K, "t": "I thought I was running from the rift. I was only running back toward it."},
	{"t0": 5.2, "t1": 9.0, "s": O, "t": "The gate is closed, Kestrel. Whatever you decide to be next, I will be in your ear."},
	{"t0": 10.0, "t1": 14.0, "s": K, "t": "Then keep talking, ORACLE. The city has a lot of rain left to name."},
]

## Chapter 12's ending: typed over the win screen after its end card, then the second credits scene ("credits2") plays on NEXT SECTOR.
const ENDING_2: Array[Dictionary] = [
	{"head": "THE SECOND GATE", "text": "Every anchor, every echo and every Observer folded into the vault and the vault folded into nothing. The sky over Neo-Meridian is only sky."},
	{"head": "TWO PLACES", "text": "You stopped running between them. Kestrel stands in one city, with one voice in her ear, and it is enough."},
	{"head": "THE LAMPLIGHTERS", "text": "Lantern Yard lights up one window at a time. Nobody counts how many. Somebody is already carrying the first of them upstairs."},
]

## The second credits scene ("credits2"): same format as CREDITS, plays after chapter 12.
const CREDITS_2: Array[Dictionary] = [
	{"head": "QUANTUM TELEPORTAR", "lines": ["The sequel", "Two places, then one"]},
	{"head": "KESTREL", "lines": ["Who closed three gates", "And kept the key"]},
	{"head": "ORACLE", "lines": ["Whole again", "Still in her ear"]},
	{"head": "THE LAMPLIGHTERS", "lines": ["Who lit Lantern Yard", "One window at a time"]},
	{"head": "NEO-MERIDIAN", "lines": ["The rain goes on", "Nobody is watching"]},
	{"head": "THANK YOU FOR PLAYING", "lines": ["The gates are closed", "The city is yours"]},
]
const CREDITS_2_SUBS: Array[Dictionary] = [
	{"t0": 1.0, "t1": 4.8, "s": O, "t": "Three gates, Kestrel. You closed every one and you are still here."},
	{"t0": 5.4, "t1": 9.2, "s": K, "t": "I had good company. Even when the company was just a voice."},
	{"t0": 10.0, "t1": 14.2, "s": O, "t": "Then walk. The street is open, and I will name every puddle for you."},
]


## The cards typed over the win screen after chapter `sector` (0-based): ENDING after chapter 10, ENDING_2 after chapter 12, [] for every other chapter.
static func ending_cards_for(sector: int) -> Array:
	var cs: Variant = chapter(sector).get("cutscenes", {})
	match str((cs as Dictionary).get("ending", "")) if cs is Dictionary else "":
		"credits": return ENDING
		"credits2": return ENDING_2
	return []


## The credits blocks and subtitles of an ending scene id ("credits" or "credits2").
static func credits_for(id: StringName) -> Array[Dictionary]:
	if id == &"story_end":
		return StoryActs.CREDITS                       # THE LONG TOMORROW's finale (docs/STORY.md)
	return CREDITS_2 if id == &"credits2" else CREDITS


static func credits_subs_for(id: StringName) -> Array[Dictionary]:
	if id == &"story_end":
		return StoryActs.END_SUBS
	return CREDITS_2_SUBS if id == &"credits2" else CREDITS_SUBS


static func count() -> int:
	return CAMPAIGN.size()


## Index of the chapter with this id, -1 when unknown.
static func index_of(id: String) -> int:
	for i in CAMPAIGN.size():
		if str(CAMPAIGN[i]["id"]) == id:
			return i
	return -1


## True once the campaign is over: sector index (0-based) at or after the aftermath.
static func is_endless(sector: int) -> bool:
	return sector >= CAMPAIGN.size()


## The chapter's data, or {} for an endless sector.
static func chapter(sector: int) -> Dictionary:
	if sector < 0 or sector >= CAMPAIGN.size():
		return {}
	return CAMPAIGN[sector]


## The objective chain of a sector; endless sectors get one step per ENDLESS_KINDS entry in a rotating order.
static func steps(sector: int) -> Array:
	if not is_endless(sector):
		return CAMPAIGN[maxi(sector, 0)]["steps"]
	var out: Array = []
	var n := 3 + (sector - CAMPAIGN.size()) % 3
	for i in n:
		var kind: StringName = ENDLESS_KINDS[(sector + i) % ENDLESS_KINDS.size()]
		out.append({"kind": str(kind), "obj": "Free the sector: %s" % str(kind)})
	return out


## Every radio line the campaign adds (step radio and credits subtitles), for length / speaker checks.
static func all_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ch: Dictionary in CAMPAIGN:
		for st: Dictionary in ch["steps"]:
			out.append(st["radio"])
	out.append_array(CREDITS_SUBS)
	out.append_array(CREDITS_2_SUBS)
	return out
