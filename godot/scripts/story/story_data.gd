class_name StoryData
extends RefCounted
## Every word of the story, as plain GDScript data so it is easy to edit. Nothing here runs: scripts/story/story.gd reads it.
##
## A line is {"s": speaker, "t": text}. Speakers: ORACLE (the half-corrupted Vael-human interface in Kestrel's head), KESTREL, VAEL BROADCAST.
## Limits (tests/test_story.gd enforces them so every line fits a phone screen): radio lines at most LINE_MAX characters, cards at most CARD_MAX,
## objectives at most OBJ_MAX, chapter titles at most TITLE_MAX.
##
## Setting: Neo-Meridian, 2091. The Vael, a hive species from beyond a collapsed quantum rift, occupy the city and farm human "coherence" with
## bio-mechanical Observer drones. Kestrel, a quantum engineer, was made a quantum-alien hybrid by the rift experiment; teleportation is real
## physics (Bell pair, Alice's two classical bits, Bob's X and Z corrections). Goal: recover the cores (rift anchors) and collapse the Vael gate.
## Twist at the last core: Kestrel is the Vael's lost scout, and ORACLE has been steering them home all along.

const O := "ORACLE"
const K := "KESTREL"
const A := "VAEL BROADCAST"
const SPEAKERS: Array[String] = [O, K, A]

const LINE_MAX := 112
const CARD_MAX := 200
const OBJ_MAX := 56
const TITLE_MAX := 24
## Index of the last story chapter; every sector after it plays the aftermath chapter (the last entry of CHAPTERS).
const FINAL := 4

const TAGLINE := "They farm your fear. Be in two places."

## The three cards typed at DEPLOY.
const PROLOGUE: Array[Dictionary] = [
	{"head": "NEO-MERIDIAN  //  2091", "text": "The rift closed nine years ago and something walked out of it. The Vael did not invade. They harvested, and the rain never stopped falling."},
	{"head": "THE VAEL", "text": "A hive with no faces. Their Observer drones hang over every street and drink what makes you a person: coherence. Look back, and they take more."},
	{"head": "KESTREL", "text": "I was an engineer on the rift project. The experiment split my blood across two states, and now something alien wears my pulse. It can fold space."},
]

## Typed over the win screen after the final sector.
const EPILOGUE: Array[Dictionary] = [
	{"head": "THE LOST SCOUT", "text": "The last core spoke in my voice. I was never taken by the rift. I was sent through it, a Vael scout who forgot the way home."},
	{"head": "THE MERIDIAN GATE", "text": "ORACLE steered me to every anchor. The gate collapsed anyway, because I chose which way the signal would run. The hive screamed once and went quiet."},
	{"head": "KESTREL", "text": "Half human, half other, all mine. ORACLE is still in my ear and the rain is still loud. No one is calling me home."},
]

## One chapter per sector. Keys: id, title, sub (place), obj (objective line), intro (radio lines on arrival), cores ({cores collected: line}, only
## counts below the sector's total: the last core ends the chapter), heat1 / heat3 (first time heat reaches 1 / 3 stars in the chapter), end (card
## on the SECTOR STABILIZED screen: {head, text}). The last entry is the aftermath, repeated for every sector after the story ends.
const CHAPTERS: Array[Dictionary] = [
	{
		"id": "split_hour", "title": "THE SPLIT HOUR", "sub": "SECTOR 01  //  OLD EXCHANGE",
		"obj": "Recover the cores. Stay out of sight.",
		"intro": [
			{"s": O, "t": "Kestrel. Eyes open. Old Exchange is Vael-held, and there are rift anchors buried under the trading floor."},
			{"s": K, "t": "Who is in my head?"},
			{"s": O, "t": "A friend with no body and a lot of bandwidth. Call me ORACLE. Six cores. Take them."},
		],
		"cores": {
			1: {"s": K, "t": "The core is warm. It hums at the pitch of my pulse. Cold metal should not know my name."},
			3: {"s": O, "t": "Halfway. Whatever you hear inside the cores, keep moving. It is only noise."},
			5: {"s": O, "t": "One left. Collapse the gate and the Vael lose their grip on this street."},
		},
		"heat1": {"s": A, "t": "Human in Sector 01, you are observed. Hold still. Stillness is a gift to the hive."},
		"heat3": {"s": A, "t": "Unregistered coherence detected. Drones may harvest without consent."},
		"end": {"head": "CHAPTER 1 COMPLETE", "text": "Six cores, and the first one answered to your pulse. ORACLE calls it residue from the rift. ORACLE has not lied to you. Yet."},
	},
	{
		"id": "bell_state", "title": "BELL STATE", "sub": "SECTOR 02  //  GLASS DISTRICT",
		"obj": "Recover the cores. Move like a measurement.",
		"intro": [
			{"s": O, "t": "Sector 02. Glass towers, and the Vael watch from every pane. Blink between them and never stand still."},
			{"s": K, "t": "Every jump costs me a piece of certainty. Where does it go?"},
			{"s": O, "t": "Into the classical channel, where it can be counted. Two bits. That is the whole bill."},
		],
		"cores": {
			1: {"s": K, "t": "There is a voice in the core's trace. Mine. Counting backwards in a language I do not speak."},
			3: {"s": O, "t": "Do not decode it. Reading a record collapses it, and some records must stay unmeasured."},
			5: {"s": K, "t": "You keep changing the subject, ORACLE. Real allies do not flinch like that."},
		},
		"heat1": {"s": A, "t": "Glass District, shelter in place. A measurement event is in progress. Breathe slowly."},
		"heat3": {"s": A, "t": "Heavy drones released. Your resistance has been recorded as appetite."},
		"end": {"head": "CHAPTER 2 COMPLETE", "text": "A voice in the anchors, counting down in your own accent. ORACLE says it is a lure. You say nothing and keep the log."},
	},
	{
		"id": "harvest_floor", "title": "THE HARVEST FLOOR", "sub": "SECTOR 03  //  HARVEST FLOOR",
		"obj": "Break the harvest. Take the cores.",
		"intro": [
			{"s": O, "t": "Sector 03 is where the Vael farm coherence. Every lit window is a human who forgot how to sleep."},
			{"s": K, "t": "The Observers feel familiar. Their wings fold the way my hands do."},
			{"s": O, "t": "Resonance, Kestrel. You were near the rift. Now let us make them regret farming this block."},
		],
		"cores": {
			1: {"s": O, "t": "That rig lost an anchor and a whole block just exhaled. They will feel that in the hive."},
			3: {"s": K, "t": "The Vael broadcast knows my name. How does a hive know a name?"},
			5: {"s": O, "t": "I should have told you sooner. I am part Vael. The rift made me, and I cannot tell which half is lying."},
		},
		"heat1": {"s": A, "t": "Returning one. We have kept your nest warm. The hive misses you."},
		"heat3": {"s": A, "t": "Coherence debt: unbounded. The hive will carry what you will not."},
		"end": {"head": "CHAPTER 3 COMPLETE", "text": "ORACLE confesses it is half Vael, a translation grown to speak to humans. It swears it wants the gate closed. You listen, and you watch."},
	},
	{
		"id": "no_cloning", "title": "NO CLONING", "sub": "SECTOR 04  //  BRIDGE ARCADE",
		"obj": "Hold the line. There can only be one of you.",
		"intro": [
			{"s": O, "t": "An unknown quantum state cannot be copied. The Vael tried to copy you anyway, and failed."},
			{"s": K, "t": "Then they have tried before. How many times?"},
			{"s": O, "t": "Enough that they stopped calling you prey. They call you the Scout."},
		],
		"cores": {
			1: {"s": O, "t": "Your hologram lasts six seconds. Drones that loved you for nine years last longer. Ask yourself why."},
			3: {"s": K, "t": "Every anchor I take, a piece of the hive goes quiet in my skull, like a tooth coming out."},
			5: {"s": O, "t": "After this, the gate. After the gate, the truth. Breathe. You are still you."},
		},
		"heat1": {"s": A, "t": "Hive to all drones: the Scout is located. Do not harm the vessel. Bring the vessel."},
		"heat3": {"s": A, "t": "You always ran toward what you feared to measure. Come and measure it."},
		"end": {"head": "CHAPTER 4 COMPLETE", "text": "The hive has a name for you, and it is not Kestrel. The Meridian Gate is one sector of rain away, and ORACLE is very quiet."},
	},
	{
		"id": "meridian_gate", "title": "THE MERIDIAN GATE", "sub": "SECTOR 05  //  MERIDIAN GATE",
		"obj": "Recover the final cores. Power the gate.",
		"intro": [
			{"s": O, "t": "Last sector. Everything you took is humming in the gate. It wants one more breath."},
			{"s": K, "t": "Collapse it, or open it? You have never said which."},
			{"s": O, "t": "Take the cores, Kestrel. The ending is only a measurement. You decide how it reads."},
		],
		"cores": {
			1: {"s": K, "t": "The logs are open now. I am done being afraid of my own voice."},
			3: {"s": K, "t": "You flinched, ORACLE. Every anchor I pulled, you flinched."},
			5: {"s": K, "t": "I am the scout they lost. The rift never changed me. It sent me."},
		},
		"heat1": {"s": A, "t": "Welcome home, Scout. We kept the sky open for you."},
		"heat3": {"s": A, "t": "Every drone is your eye. Every eye is ours. Why are you fighting yourself?"},
		"end": {"head": "FINAL CHAPTER COMPLETE", "text": "The last core opens and plays your own voice: a Vael scout, a human mask, a mission to bring the hive home. ORACLE steered you here. The gate waits for your choice."},
	},
	{
		"id": "open_city", "title": "THE OPEN CITY", "sub": "FREE SECTOR",
		"obj": "Keep the gate shut. Free the sector.",
		"intro": [
			{"s": O, "t": "The gate is collapsing and Neo-Meridian is breathing. Some drones still follow old orders. Be gentle, or do not."},
		],
		"cores": {
			1: {"s": O, "t": "Another anchor freed. The city is learning what it is to be unwatched."},
			3: {"s": K, "t": "Two halves, one rain. I think I can live in this."},
			5: {"s": O, "t": "Every freed sector is a debt paid. Keep going, Kestrel. The city is counting."},
		},
		"heat1": {"s": A, "t": "Residual order detected. Compliance with the hive is no longer available."},
		"heat3": {"s": A, "t": "Hive directive ninety-nine: nobody is listening. Please stop shooting the speaker."},
		"end": {"head": "SECTOR FREED", "text": "Another block exhales. The rain does not stop, but it no longer sounds like being watched."},
	},
]

## Radio lines tied to an event, each said once per run (reset by a new game). Lines of one event play in order.
const RADIO := {
	"first_beacon": [
		{"s": O, "t": "Beacon down. One half of a Bell pair stays here, the other half stays in you. Press again to measure."},
	],
	"first_teleport": [
		{"s": O, "t": "Two classical bits crossed the dark. That is the whole price of moving a body."},
		{"s": K, "t": "And Bob corrects the rest: X when the second bit is one, then Z when the first is."},
	],
	"first_link": [
		{"s": O, "t": "Linked. Hurt one drone and the other bleeds. Entanglement is a terrible secret to keep."},
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
		{"s": A, "t": "Maximum observation. Every Observer in Neo-Meridian is turning its lens on you. Hold still."},
	],
}

## Message triggers: when a Game.message text contains `contains`, the RADIO event `event` fires (once).
const MESSAGE_TRIGGERS: Array[Dictionary] = [
	{"contains": "COMMANDEERED", "event": "carjack"},
	{"contains": "OFFLINE IN VEHICLE", "event": "quantum_offline"},
]

## Pools drawn in random order without repeating until every line has been used.
const RESPAWN: Array[Dictionary] = [
	{"s": O, "t": "Welcome back. Your coherence reassembled from what the hive left. Try to leave more next time."},
	{"s": O, "t": "Reconstruction complete. You died, Kestrel. The city counted it, and so did I."},
	{"s": O, "t": "The cores are still where you left them. So are the Vael."},
	{"s": K, "t": "Still here. Still two halves. Let us try that again, quietly."},
	{"s": K, "t": "My body remembers dying the way a river remembers a stone."},
	{"s": O, "t": "You came back faster than the rift allows. I will not ask how."},
]

const LOW_HEALTH: Array[Dictionary] = [
	{"s": O, "t": "Integrity critical. Run, hide or blink. Stand still and you are just food."},
	{"s": O, "t": "You are bleeding signal. Find cover and a green pickup."},
	{"s": O, "t": "Do not trade hits with the Vael. Trade positions."},
	{"s": K, "t": "Not like this. Not in this rain."},
	{"s": K, "t": "My blood is turning the wrong colour. Move, Kestrel."},
]

## Shown on the DECOHERED screen.
const DEATH: Array[Dictionary] = [
	{"s": O, "t": "Observed. Measured. Collapsed. That is all the Vael ever wanted from you."},
	{"s": K, "t": "It hurts less when half of you is somewhere else."},
	{"s": A, "t": "Subject decohered. Harvest complete. The hive thanks you for your contribution."},
	{"s": O, "t": "No cloning, no backups, Kestrel. Next time, bring more luck."},
	{"s": K, "t": "Get up. They only win if the record says you stayed down."},
	{"s": A, "t": "Citizens, please disregard the sound. The incident has been harvested and closed."},
	{"s": O, "t": "Every death is data. I would prefer you stopped donating."},
	{"s": K, "t": "The rain is the last thing that stops."},
	{"s": A, "t": "Your fear was delicious. The hive will remember it for you."},
]


# ---------------------------------------------------------------------------------------------------------------------
# Contracts (scripts/missions/contracts.gd): procedural side missions. Lines are picked at random from the list of an event, said once per occurrence.
# Keys per kind: offer (a contract marker appears), start (accepted), mid (halfway / under pressure), done, fail. Same length limits as the radio lines.
# ---------------------------------------------------------------------------------------------------------------------

const CONTRACT_RADIO := {
	"officer": {
		"offer": [
			{"s": O, "t": "A Vael officer is coordinating this block. Remove him and the street goes quiet. Step into the marker."},
			{"s": O, "t": "Command chitin, one body, a lot of rank. Mark him, Kestrel. I will pay for the scalp."},
		],
		"start": [
			{"s": O, "t": "Officer marked on your map. He hits harder and takes more punishment. Do not fight him in the open."},
		],
		"mid": [
			{"s": A, "t": "Officer to hive: the vessel bites back. Send everything you have."},
		],
		"done": [
			{"s": K, "t": "Officer down. The mandibles are still clicking. Tell me that is not a language."},
			{"s": O, "t": "Chain of command broken. The credits are already in your account."},
		],
		"fail": [
			{"s": O, "t": "He slipped the net. Officers heal faster than rumours. We try again."},
		],
	},
	"hack": {
		"offer": [
			{"s": O, "t": "A Vael relay node is feeding the Observers. Stand inside its ring and I will take the keys."},
			{"s": O, "t": "Node ahead. Hold the zone, keep breathing, and let me do the arithmetic."},
		],
		"start": [
			{"s": O, "t": "Link established. Stay inside the ring. If you step out, the handshake decays."},
		],
		"mid": [
			{"s": O, "t": "Halfway through the key. They know. Drones inbound, hold your ground."},
		],
		"done": [
			{"s": O, "t": "Node cracked. Every Observer on this block just lost an eye."},
		],
		"fail": [
			{"s": O, "t": "Handshake lost. The node re-keyed itself. It will be there when you are ready."},
		],
	},
	"chase": {
		"offer": [
			{"s": O, "t": "A Vael courier is running a harvest manifest. Get wheels and run him down before the hive does."},
			{"s": O, "t": "Fleeing target, one car, fast. Take a vehicle and stop it. I need what it carries."},
		],
		"start": [
			{"s": O, "t": "That car is the target. Shoot it, ram it, I do not care. Do not let it reach the hive lanes."},
		],
		"mid": [
			{"s": K, "t": "He is faster than he looks. Close the gap, ORACLE, I am not losing a car chase to a bug."},
		],
		"done": [
			{"s": O, "t": "Target wrecked. The manifest burned with it, and the hive just lost a week of harvest."},
		],
		"fail": [
			{"s": O, "t": "Target gone. The manifest is on its way to the hive. Next time stay on his bumper."},
		],
	},
	"courier": {
		"offer": [
			{"s": O, "t": "A human cell needs a coherence cell delivered across the sector. The Vael are watching the street."},
			{"s": O, "t": "Package pickup ahead. Fast hands, fast legs, no heroics. Step into the marker."},
		],
		"start": [
			{"s": O, "t": "Package aboard. Follow the route line on the road. The clock is real, and so is the rain."},
		],
		"mid": [
			{"s": O, "t": "Half the clock is gone. A car would help. A blink would help more."},
		],
		"done": [
			{"s": O, "t": "Delivered. The cell will run for a month on that. Good work, Kestrel."},
		],
		"fail": [
			{"s": O, "t": "Too slow. The cell went cold before you arrived. We will find another courier job."},
		],
	},
	"survive": {
		"offer": [
			{"s": O, "t": "A rift anchor is unstable and the Vael smell it. Hold it until the pulse settles. This will be loud."},
			{"s": O, "t": "Anchor ahead. It will call every drone in range. Stand at the ring and do not give ground."},
		],
		"start": [
			{"s": O, "t": "Anchor live. Waves incoming. Stay within sixty metres or the pulse collapses without you."},
		],
		"mid": [
			{"s": O, "t": "Next wave is heavier. Use your blink to reposition and your link to thin them."},
		],
		"done": [
			{"s": O, "t": "Anchor stabilized. The Vael pulled back. That bought the city a little more quiet."},
		],
		"fail": [
			{"s": O, "t": "The anchor collapsed. It will rebuild, and so will they. Try again when you are ready."},
		],
	},
	"drones": {
		"offer": [
			{"s": O, "t": "Entanglement trial. Link two Observers with the link ability and let one shot do the work of two."},
			{"s": O, "t": "A drone nest is waiting for a clean demonstration. Link them, hit one, watch both fall."},
		],
		"start": [
			{"s": O, "t": "Only kills made through a quantum link count. Aim, press link, then shoot either drone."},
		],
		"mid": [
			{"s": K, "t": "Mirrored damage. Hurt one drone and the other bleeds. I am starting to enjoy this."},
		],
		"done": [
			{"s": O, "t": "Trial complete. Entanglement is a terrible secret to keep, and a wonderful one to spend."},
		],
		"fail": [
			{"s": O, "t": "Too many direct kills. The nest scattered. Link first, shoot second."},
		],
	},
}

## One extra line when a contract is offered, by chapter index (the last entry covers every later sector).
const CONTRACT_CHAPTER: Array[Dictionary] = [
	{"s": O, "t": "Old Exchange runs on rumour and rent. Contracts pay in credits, and credits buy survival."},
	{"s": O, "t": "Glass District jobs bend toward entanglement. Practise linking, it pays double in these streets."},
	{"s": O, "t": "The Harvest Floor is full of relay nodes. Crack them and the drones go blind."},
	{"s": O, "t": "Bridge Arcade has fast traffic and faster couriers. Wheels will matter here."},
	{"s": O, "t": "Meridian Gate is crowded with anchors. Every job here is a siege. Bring everything."},
	{"s": O, "t": "The city is free, but not quiet. There is always another contract for a hand that will take it."},
]

const CONTRACT_GENERIC := {
	"retry": [
		{"s": O, "t": "Same contract, same marker. Try it again, and try it smarter."},
		{"s": K, "t": "Once more. I know where the teeth are now."},
	],
	"abandon": [
		{"s": O, "t": "The job went cold. I will find you another. Reputation took a small hit."},
	],
	"decohered": [
		{"s": O, "t": "You died mid-job. The contract is on hold. Walk back into the marker when you are ready."},
	],
	"rep_up": [
		{"s": O, "t": "Your name is moving through the cells. Trusted contacts get better prices at the shop."},
	],
	"rep_down": [
		{"s": O, "t": "People are noticing the failures. Reputation is not free, Kestrel."},
	],
	"upgrade": [
		{"s": O, "t": "A grateful contact left a free upgrade in your kit. Check the shop in the pause menu."},
	],
}

# ---------------------------------------------------------------------------------------------------------------------
# Tutorial (scripts/story/tutorial.gd): five short steps on a first launch. `kb` and `touch` are the prompt for keyboard and touch (at most PROMPT_MAX characters),
# `done` is the radio line when the step is completed. Steps: id move, look, shoot, blink, car.
# ---------------------------------------------------------------------------------------------------------------------

const PROMPT_MAX := 44

const TUTORIAL: Array[Dictionary] = [
	{"id": "move", "kb": "MOVE WITH  W A S D", "touch": "DRAG THE LEFT STICK TO MOVE",
		"done": {"s": O, "t": "Good. Legs work. Sprint by pushing the stick all the way, or holding shift."}},
	{"id": "look", "kb": "LOOK AROUND WITH THE MOUSE", "touch": "DRAG THE RIGHT SIDE TO LOOK",
		"done": {"s": O, "t": "Eyes work too. Keep the crosshair on the Vael and off the sky."}},
	{"id": "shoot", "kb": "HOLD LEFT MOUSE TO FIRE", "touch": "HOLD THE FIRE BUTTON TO SHOOT",
		"done": {"s": O, "t": "Rifle online. Reload when it clicks, and keep aiming high for the head."}},
	{"id": "blink", "kb": "PRESS Q TO THROW A BEACON", "touch": "TAP BLINK TO THROW A BEACON",
		"kb2": "PRESS Q AGAIN TO BLINK THERE", "touch2": "TAP BLINK AGAIN TO JUMP THERE",
		"done": {"s": K, "t": "Two bits crossed the dark and I came out the other side. I will never get used to that."}},
	{"id": "car", "kb": "WALK TO THE CAR AND PRESS F", "touch": "WALK TO THE CAR AND TAP USE",
		"done": {"s": O, "t": "Four wheels. Contracts show up as markers on your map. Take one, earn credits, buy upgrades."}},
]

const TUTORIAL_DONE := "TRAINING COMPLETE"
const TUTORIAL_SKIP_KB := "TAB  SKIP"
const TUTORIAL_SKIP_TOUCH := "SKIP"
