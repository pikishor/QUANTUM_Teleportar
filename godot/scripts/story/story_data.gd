class_name StoryData
extends RefCounted
## Every word of the story, as plain GDScript data so it is easy to edit. Nothing here runs: scripts/story/story.gd reads it.
##
## A line is {"s": speaker, "t": text}. Speakers: ORACLE (the rogue AI in Kestrel's ear), KESTREL, AUTHORITY BROADCAST.
## Limits (tests/test_story.gd enforces them so every line fits a phone screen): radio lines at most LINE_MAX characters, cards at most CARD_MAX,
## objectives at most OBJ_MAX, chapter titles at most TITLE_MAX.
##
## Setting: Neo-Meridian, 2091, a rain-soaked megacity run by the Observer Authority, whose drones harvest the "coherence" of citizens' quantum
## states. The player is Kestrel, an ex-Authority quantum engineer split across two states by a failed experiment, who can teleport by measuring
## entangled pairs (Bell pair, Alice's two classical bits, Bob's X and Z corrections). ORACLE hides something in every chapter. The last core
## shows that the Authority's Director is Kestrel's own earlier self, the half that stayed measured.

const O := "ORACLE"
const K := "KESTREL"
const A := "AUTHORITY BROADCAST"
const SPEAKERS: Array[String] = [O, K, A]

const LINE_MAX := 112
const CARD_MAX := 200
const OBJ_MAX := 56
const TITLE_MAX := 24
## Index of the last story chapter; every sector after it plays the aftermath chapter (the last entry of CHAPTERS).
const FINAL := 4

const TAGLINE := "The city is watching. Be in two places."

## The three cards typed at DEPLOY.
const PROLOGUE: Array[Dictionary] = [
	{"head": "NEO-MERIDIAN  //  2091", "text": "It has rained for nine years. The Observer Authority calls it weather. Everyone else calls it the price of being watched."},
	{"head": "THE OBSERVER AUTHORITY", "text": "Its drones do not shoot to kill. They measure. Every look collapses a little more of you, and the Authority sells what falls out: coherence."},
	{"head": "KESTREL", "text": "I helped build the engine that made this possible. Then an experiment split me across two states, and one of me woke up on the wrong side of the glass."},
]

## Typed over the win screen after the final sector.
const EPILOGUE: Array[Dictionary] = [
	{"head": "THE DIRECTOR", "text": "He did not fight. He set his badge on the floor and asked me to finish the measurement I had always been too afraid to make."},
	{"head": "THE MERIDIAN GATE", "text": "The gate opened on one long breath. Every drone in Neo-Meridian stopped, turned its lens upward, and for the first time saw the rain."},
	{"head": "KESTREL", "text": "Two halves, one name. ORACLE is still in my ear and the city is still loud. For the first time in nine years nobody is measuring me back."},
]

## One chapter per sector. Keys: id, title, sub (place), obj (objective line), intro (radio lines on arrival), cores ({cores collected: line}, only
## counts below the sector's total: the last core ends the chapter), heat1 / heat3 (first time heat reaches 1 / 3 stars in the chapter), end (card
## on the SECTOR STABILIZED screen: {head, text}). The last entry is the aftermath, repeated for every sector after the story ends.
const CHAPTERS: Array[Dictionary] = [
	{
		"id": "split_hour", "title": "THE SPLIT HOUR", "sub": "SECTOR 01  //  OLD EXCHANGE",
		"obj": "Recover the cores. Stay out of sight.",
		"intro": [
			{"s": O, "t": "Kestrel. Eyes open. You are in Sector 01, and your other half is somewhere else, thinking about you."},
			{"s": K, "t": "Who am I talking to?"},
			{"s": O, "t": "A friend with no body and a lot of bandwidth. Six cores are buried in this grid. Find them."},
		],
		"cores": {
			1: {"s": K, "t": "The core is warm. It hums at the same pitch as my pulse. That should not be possible."},
			3: {"s": O, "t": "Halfway. Whatever you think you hear in the cores, keep moving. It is only noise."},
			5: {"s": O, "t": "One left. Power the Meridian Gate and the rain finally has a reason to stop."},
		},
		"heat1": {"s": A, "t": "Citizen in Sector 01, you are being observed. Remain where you are. Observation is care."},
		"heat3": {"s": A, "t": "Unregistered coherence detected. Drones are authorized to measure without consent."},
		"end": {"head": "CHAPTER 1 COMPLETE", "text": "Six cores, and the first one carried your signature. ORACLE calls it a coincidence. ORACLE has never lied to you. Yet."},
	},
	{
		"id": "bell_state", "title": "BELL STATE", "sub": "SECTOR 02  //  GLASS DISTRICT",
		"obj": "Recover the cores. Move like a measurement.",
		"intro": [
			{"s": O, "t": "Sector 02. Taller towers, more eyes. Blink between them, link their drones, and do not stand still."},
			{"s": K, "t": "Every jump costs me a piece of certainty. Where does it go?"},
			{"s": O, "t": "Into the classical channel, where it can be counted. Two bits. That is the whole bill."},
		],
		"cores": {
			1: {"s": K, "t": "There is a voice in the core's trace. Mine. Counting backwards."},
			3: {"s": O, "t": "Do not decode that log. Reading it collapses the record, and some records should stay unmeasured."},
			5: {"s": K, "t": "You keep changing the subject, ORACLE. People who help do not do that."},
		},
		"heat1": {"s": A, "t": "Glass District residents, shelter in place. A measurement event is in progress."},
		"heat3": {"s": A, "t": "Heavy units dispatched. Your cooperation has already been recorded as refusal."},
		"end": {"head": "CHAPTER 2 COMPLETE", "text": "A voice in the cores, counting down in your own accent. ORACLE says it is a decoy. You say nothing and keep the log."},
	},
	{
		"id": "harvest_floor", "title": "THE HARVEST FLOOR", "sub": "SECTOR 03  //  HARVEST FLOOR",
		"obj": "Break the harvest. Take the cores.",
		"intro": [
			{"s": O, "t": "Sector 03 is where they farm coherence. Look up. Every lit window is someone who forgot how to sleep."},
			{"s": K, "t": "I designed the sensors on those rigs."},
			{"s": O, "t": "I know. Let us make them regret you."},
		],
		"cores": {
			1: {"s": O, "t": "That rig lost a core and a whole block just exhaled. Keep going. They will feel it."},
			3: {"s": K, "t": "The Authority knows my badge number. Why would a broadcast know my badge number?"},
			5: {"s": O, "t": "I should have told you sooner. I was written by someone with your clearance. I am sorry."},
		},
		"heat1": {"s": A, "t": "Engineer Kestrel, your absence has been noted. It has also been forgiven. Come home."},
		"heat3": {"s": A, "t": "Coherence debt: unbounded. Neo-Meridian will carry what you will not."},
		"end": {"head": "CHAPTER 3 COMPLETE", "text": "ORACLE confesses: its code carries your clearance and your habits. Someone with your hands built the thing that built the cage."},
	},
	{
		"id": "no_cloning", "title": "NO CLONING", "sub": "SECTOR 04  //  BRIDGE ARCADE",
		"obj": "Hold the line. There can only be one of you.",
		"intro": [
			{"s": O, "t": "An unknown quantum state cannot be copied. The Authority copied you anyway."},
			{"s": K, "t": "Then one of us is a forgery."},
			{"s": O, "t": "Or you are both the original, and neither of you can prove it."},
		],
		"cores": {
			1: {"s": O, "t": "Your hologram lasts six seconds. The other you has lasted nine years. Ask what he is made of."},
			3: {"s": K, "t": "Every core I take, a piece of him goes quiet. I can feel it, like a tooth coming out."},
			5: {"s": O, "t": "After this, the gate. After the gate, the Director. Breathe, Kestrel."},
		},
		"heat1": {"s": A, "t": "Director to all units: priority subject located. Do not harm the body. Bring the body."},
		"heat3": {"s": A, "t": "You always did run toward the thing you were afraid to measure. Come and measure it."},
		"end": {"head": "CHAPTER 4 COMPLETE", "text": "The Authority has a Director, and the Director has a heartbeat. Yours. The Meridian Gate is one sector of rain away."},
	},
	{
		"id": "meridian_gate", "title": "THE MERIDIAN GATE", "sub": "SECTOR 05  //  MERIDIAN GATE",
		"obj": "Recover the final cores. Power the gate.",
		"intro": [
			{"s": O, "t": "Last sector. Everything you took is already humming in the gate. It wants one more breath."},
			{"s": K, "t": "And the Director?"},
			{"s": O, "t": "Waiting at the top. He has not moved since the day he measured you."},
		],
		"cores": {
			1: {"s": K, "t": "The logs are open now. I am not afraid to read them anymore."},
			3: {"s": O, "t": "The Authority was never an army. It was one engineer who could not bear to be uncertain."},
			5: {"s": K, "t": "He kept the half of me that said yes to everything. I kept the half that said no."},
		},
		"heat1": {"s": A, "t": "Welcome home. I kept the city warm for you."},
		"heat3": {"s": A, "t": "Every drone is my eye. Every eye is yours. Why are you fighting yourself?"},
		"end": {"head": "FINAL CHAPTER COMPLETE", "text": "The last core opens the gate. At its centre stands the Director in your old badge, wearing your face. He is not a monster. He is you, measured once and never allowed to wonder."},
	},
	{
		"id": "open_city", "title": "THE OPEN CITY", "sub": "FREE SECTOR",
		"obj": "Keep the gate open. Free the sector.",
		"intro": [
			{"s": O, "t": "The gate is open and Neo-Meridian is breathing. Some drones still follow old orders. Be gentle, or do not."},
		],
		"cores": {
			1: {"s": O, "t": "Another core freed. The city is learning what it is like to be unwatched."},
			3: {"s": K, "t": "Two halves, one rain. I think I can live in this."},
			5: {"s": O, "t": "Every freed sector is a debt paid. Keep going, Kestrel. The city is counting."},
		},
		"heat1": {"s": A, "t": "Residual order detected. Compliance is no longer available."},
		"heat3": {"s": A, "t": "Authority directive ninety-nine: nobody is listening. Please stop shooting the speaker."},
		"end": {"head": "SECTOR FREED", "text": "Another block exhales. The rain does not stop, but it no longer sounds like surveillance."},
	},
]

## Radio lines tied to an event, each said once per run (reset by a new game). Lines of one event play in order.
const RADIO := {
	"first_beacon": [
		{"s": O, "t": "Beacon down. One half of a Bell pair stays here, the other half stays with you. Press again to measure."},
	],
	"first_teleport": [
		{"s": O, "t": "Two classical bits crossed the dark. That is the whole price of moving a person."},
		{"s": K, "t": "And Bob corrects the rest: X when the second bit is one, then Z when the first is."},
	],
	"first_link": [
		{"s": O, "t": "Linked. Hurt one drone and the other feels it. Entanglement is a terrible secret to keep."},
	],
	"first_super": [
		{"s": O, "t": "A hologram for six seconds, one of you in two places. Let it draw their fire, then collapse it."},
	],
	"first_vehicle": [
		{"s": K, "t": "Four wheels and no warrant. ORACLE, I am driving."},
		{"s": O, "t": "Blink and superposition go dark in a vehicle, so drive like you mean it."},
	],
	"carjack": [
		{"s": K, "t": "Nothing personal, friend. I need the car more than you need the commute."},
	],
	"quantum_offline": [
		{"s": O, "t": "Quantum powers do not run inside a vehicle. Step out, then measure."},
	],
	"first_low_health": [
		{"s": O, "t": "Your integrity is bleeding out. Break line of sight, find a green pickup, stop being a target."},
	],
	"heat5": [
		{"s": A, "t": "Maximum observation. Every lens in Neo-Meridian is turning to face you. Smile."},
	],
}

## Message triggers: when a Game.message text contains `contains`, the RADIO event `event` fires (once).
const MESSAGE_TRIGGERS: Array[Dictionary] = [
	{"contains": "COMMANDEERED", "event": "carjack"},
	{"contains": "OFFLINE IN VEHICLE", "event": "quantum_offline"},
]

## Pools drawn in random order without repeating until every line has been used.
const RESPAWN: Array[Dictionary] = [
	{"s": O, "t": "Welcome back. Your coherence reassembled itself from what was left. Try to leave more next time."},
	{"s": O, "t": "Reconstruction complete. You died, Kestrel. The city counted it, and so did I."},
	{"s": O, "t": "The cores are still where you left them. So is the Authority."},
	{"s": K, "t": "Still here. Still two halves. Let us try that again, quietly."},
]

const LOW_HEALTH: Array[Dictionary] = [
	{"s": O, "t": "Integrity critical. Run, hide or blink. Stand still and you are just data."},
	{"s": O, "t": "You are bleeding signal. Find cover and a green pickup."},
	{"s": O, "t": "Do not trade hits with the Authority. Trade positions."},
	{"s": K, "t": "Not like this. Not in this rain."},
]

## Shown on the DECOHERED screen.
const DEATH: Array[Dictionary] = [
	{"s": O, "t": "Observed. Measured. Collapsed. That is all the Authority ever wanted from you."},
	{"s": K, "t": "It hurts less when half of you is somewhere else."},
	{"s": A, "t": "Subject decohered. Observation concluded. Thank you for your cooperation."},
	{"s": O, "t": "No cloning, no backups, Kestrel. Next time, bring more luck."},
	{"s": K, "t": "Get up. They only win if the record says you stayed down."},
	{"s": A, "t": "Citizens, please disregard the sound. The incident has been measured and closed."},
	{"s": O, "t": "Every death is data. I would prefer you stopped donating."},
	{"s": K, "t": "The rain is the last thing that stops."},
]
