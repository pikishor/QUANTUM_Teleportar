class_name StoryActs
extends RefCounted
## THE LONG TOMORROW as plain data (docs/STORY.md): four acts, twelve story missions, every briefing, radio line, set-piece beat and the ending. Nothing here runs; StoryMissions turns a
## mission into campaign steps, StoryScenes into cutscenes, StoryRunner plays and saves it. Rules checked by tests/test_story_acts.gd.
##
## MISSIONS[i]: id, act (1..4), title (at most TITLE_MAX), place, card (the Mission Board card line, at most CARD_MAX), reward (credits), brief (3..4 lines {s, t}: the briefing cutscene),
## radio (one {s, t} per step, said when the step starts), beats (cutscenes in the middle of the mission: {step, head, sub, lines}; a beat plays when step `step` starts), outro ({s, t} said when
## the mission is done), steps (the number of campaign steps StoryMissions builds: the radio list has exactly that many lines).

const K := StoryCast.HERO
const O := StoryCast.ORACLE
const V := StoryCast.VAEL
const RIVET := "RIVET"
const IRIS := "IRIS"
const BASALT := "BASALT"
const VOSS := "VOSS"

const TITLE_MAX := 22
const CARD_MAX := 76
const LINE_MAX := 112                      ## the story layer's own radio limit (StoryData.LINE_MAX)
const ACT_CARD_MAX := 200

const ACTS: Array[Dictionary] = [
	{"n": 1, "id": "landfall", "title": "LANDFALL", "sub": "THE CITY",
		"card": "2140. Last Light is about to go dark. One courier survives the fold. Tuning Day is tomorrow.",
		"end": "The relay carried the hive's voice. The Authority has been building the Vael a door, and Director Voss runs it."},
	{"n": 2, "id": "highland", "title": "THE HARBOUR AND THE HIGHLAND", "sub": "HARBOUR, MOUNTAINS",
		"card": "The Array's parts come in by sea and go up by road. Somewhere on the mountain a physicist is still awake.",
		"end": "The Array is tuned by a voice, and the voice is Kestrel's. Every jump she made rang the door like a bell."},
	{"n": 3, "id": "long_way", "title": "THE LONG WAY", "sub": "AIR AND SEA",
		"card": "The Authority watches the roads. The sky and the sea are free for now, and a grounded pilot has a plane.",
		"end": "The Array's power cable ends at an alien outpost in the mountains. That is where the door is fed."},
	{"n": 4, "id": "array", "title": "THE ARRAY", "sub": "OUTPOST, CITY",
		"card": "Tuning Day. The damper core, a Warden, a Director and a rig that has one choice left.",
		"end": "ORACLE cut its own link. The Array went deaf and the door never opened. Last Light is lit."},
]

const MISSIONS: Array[Dictionary] = [
	{"id": "landfall", "act": 1, "title": "LANDFALL", "place": "THE CITY", "reward": 300, "steps": 2,
		"card": "Find the beacon and drive off the Authority patrol.",
		"brief": [
			{"s": O, "t": "Fold complete. Neo-Meridian, 2091. You are forty-nine years behind us, Kestrel, and the clock is running."},
			{"s": K, "t": "Last Light sent me for one thing: stop the Array before Tuning Day."},
			{"s": O, "t": "Your landing lit a beacon. Authority patrols are closing in. Move."},
		],
		"radio": [
			{"s": O, "t": "The beacon is a few blocks on. Walk, sprint or QUANTUM TELEPORT. Your call."},
			{"s": O, "t": "Authority patrol ahead. Humans, hive-grade armour. Show them what 2140 looks like."},
		],
		"beats": [],
		"outro": {"s": O, "t": "Hive-grade armour on human soldiers. The Authority and the Vael share a supply line. Remember that."}},
	{"id": "borrowed_wheels", "act": 1, "title": "BORROWED WHEELS", "place": "RIVET'S GARAGE", "reward": 350, "steps": 2,
		"card": "Take any car and reach Rivet's garage.",
		"brief": [
			{"s": O, "t": "Someone is answering the beacon on a private channel. They know what you are."},
			{"s": RIVET, "t": "Hey, time girl. Old canal garage. Bring a car, any car. I have a lift and a lot of questions."},
			{"s": K, "t": "Who is this?"},
			{"s": RIVET, "t": "The person keeping the Authority off your back. Drive."},
		],
		"radio": [
			{"s": RIVET, "t": "Any car works. The big pedal is the gas. Do not wait for me, I am already annoyed."},
			{"s": O, "t": "Authority cars are on your tail. Break line of sight and lose them in the side streets."},
		],
		"beats": [],
		"outro": {"s": RIVET, "t": "In one piece! Fine. You can have the loft. Tomorrow I show you the city's ugly secret."}},
	{"id": "the_relay", "act": 1, "title": "THE RELAY", "place": "GLASS DISTRICT", "reward": 450, "steps": 3,
		"card": "Hack the Authority relay, hold it and drop the relay chief.",
		"brief": [
			{"s": RIVET, "t": "That tower in the glass district is the Authority's relay. They call it city defence."},
			{"s": O, "t": "Its traffic is encrypted, but the shape is wrong. It is not listening to the street. It is talking."},
			{"s": K, "t": "Then we listen. Ring, hold, hack."},
		],
		"radio": [
			{"s": O, "t": "Stand in the ring until the upload ends. The patrol will notice. Keep them off the node."},
			{"s": O, "t": "Reinforcements on every corner. Hold the tower until the copy finishes."},
			{"s": O, "t": "The relay chief is wired into the tower. Drop him and the line is ours."},
		],
		"beats": [
			{"step": 1, "head": "THE LINE", "sub": "VOSS AND THE HIVE", "lines": [
				{"s": O, "t": "Kestrel, listen to what the relay is carrying. That is not a human voice."},
				{"s": V, "t": "Director Voss. The door is nearly built. Your city will be spared."},
				{"s": VOSS, "t": "Quiet! Someone is on the line."},
				{"s": K, "t": "Spared. He is selling the whole city."},
			]},
		],
		"outro": {"s": RIVET, "t": "Voss. The Director built the door for them. We need the physicist. Harbour first, then the mountain."}},
	{"id": "container_17", "act": 2, "title": "CONTAINER 17", "place": "HARBOUR, WEST QUAY", "reward": 500, "steps": 3,
		"card": "Clear the quay guards and crack Container 17.",
		"brief": [
			{"s": RIVET, "t": "Harbour, container 17. Authority switchgear stamped for the Array. I know the quay, you know the guns."},
			{"s": O, "t": "South coast, west quay. Drive the coast road or run it. Sirens will follow you in."},
		],
		"radio": [
			{"s": RIVET, "t": "West quay, by the cranes. Park anywhere, nobody checks the harbour road."},
			{"s": O, "t": "Guards around the yard. Containers make good cover for both sides."},
			{"s": O, "t": "Container 17. Pop the lock and read the manifest."},
		],
		"beats": [],
		"outro": {"s": RIVET, "t": "Coils and switchgear for the Array, signed by Dr. Iris Vance. And a courier boat is leaving the bay."}},
	{"id": "ferry_run", "act": 2, "title": "FERRY RUN", "place": "THE BAY", "reward": 550, "steps": 3,
		"card": "Catch the courier boat before it leaves the bay.",
		"brief": [
			{"s": RIVET, "t": "Courier boat, loaded with the tuning fork. Speedboat at pier A. Do not sink it, I like it."},
			{"s": O, "t": "Open water favours it. Stay on its wake and box it in."},
		],
		"radio": [
			{"s": RIVET, "t": "Pier A, the speedboat. Hop in and open her up."},
			{"s": O, "t": "Courier ahead. Ram it, shoot it or stay on it until it stops."},
			{"s": O, "t": "Past the breakwater. Stay close. We want the courier talking."},
		],
		"beats": [
			{"step": 2, "head": "THE COURIER", "sub": "VOSS ON THE LINE", "lines": [
				{"s": VOSS, "t": "Courier, report. Is the fork safe?"},
				{"s": O, "t": "That is the Director himself, on the courier's own radio."},
				{"s": K, "t": "The boat is a decoy. The fork is on the mountain road."},
			]},
		],
		"outro": {"s": O, "t": "A decoy. The real fork is on a pickup climbing Summit Road. Rivet has a 4x4 waiting at the foot."}},
	{"id": "summit_road", "act": 2, "title": "SUMMIT ROAD", "place": "SUMMIT ROAD", "reward": 600, "steps": 3,
		"card": "Chase the fork's pickup up the mountain road.",
		"brief": [
			{"s": RIVET, "t": "4x4 at the foot of Summit Road. The pickup has a head start and a bad attitude."},
			{"s": O, "t": "Hairpins, rock walls, no rail in places. Keep it on the road and keep it in sight."},
		],
		"radio": [
			{"s": RIVET, "t": "4x4 at the foot of the road. Keys are in it, always are."},
			{"s": O, "t": "There it is. Stay on its tail and box it in on the hairpins."},
			{"s": O, "t": "Fork secured. The observatory dish is just above you. Iris should be inside."},
		],
		"beats": [],
		"outro": {"s": IRIS, "t": "I saw the headlights. I am Iris Vance. Please do not shoot the physicist. Come inside."}},
	{"id": "observatory", "act": 2, "title": "THE OBSERVATORY", "place": "MOUNTAIN OBSERVATORY", "reward": 700, "steps": 3,
		"card": "Hold the dish while Iris decodes the Array.",
		"brief": [
			{"s": IRIS, "t": "The Authority made me tune the Array. I left a copy of everything in the dish. It needs minutes."},
			{"s": O, "t": "The patrol will have followed the pickup. Hold the observatory."},
			{"s": K, "t": "Minutes I can do."},
		],
		"radio": [
			{"s": IRIS, "t": "Come to the dish. I will open the side door once you stand in the ring."},
			{"s": O, "t": "Patrol on the road. Hold the dish until Iris has the map."},
			{"s": IRIS, "t": "Almost there. The Array answers to a voice, Kestrel. Give me twenty seconds."},
		],
		"beats": [
			{"step": 2, "head": "THE VOICE", "sub": "EVERY JUMP RANG THE DOOR", "lines": [
				{"s": IRIS, "t": "The Array is tuned by a voice. Every time you folded, it listened. Every blink."},
				{"s": K, "t": "My teleports? ORACLE?"},
				{"s": O, "t": "I knew. I hoped it was not true. I am sorry, Kestrel."},
				{"s": IRIS, "t": "Then we make it deaf. A damper core. First, the sky."},
			]},
		],
		"outro": {"s": IRIS, "t": "Captain Basalt keeps a plane at Eastfield. He flies what the Authority will not. Find him."}},
	{"id": "eastfield", "act": 3, "title": "EASTFIELD", "place": "EASTFIELD AIRPORT", "reward": 800, "steps": 4,
		"card": "Clear the hangar, take Basalt's plane and fly out.",
		"brief": [
			{"s": IRIS, "t": "Eastfield airport. Basalt's plane is in the hangar and the Authority has grounded him."},
			{"s": BASALT, "t": "They took my keys, not my plane. Clear the hangar and I talk you through the rest."},
			{"s": O, "t": "Basalt. That name is carved on the memorial wall at Last Light. Do not tell him."},
		],
		"radio": [
			{"s": BASALT, "t": "Terminal is the long white building. I meet you at the hangar."},
			{"s": O, "t": "Hangar guards, armoured. Keep them off the plane."},
			{"s": BASALT, "t": "That is her. Throttle up, pull back gently, she flies herself."},
			{"s": BASALT, "t": "Set her down on that field. Flare at the end, nose up, and no early brakes."},
		],
		"beats": [],
		"outro": {"s": BASALT, "t": "Smooth. Nobody lands like that the first time. Where did you learn to fly, Kestrel?"}},
	{"id": "canyon_run", "act": 3, "title": "CANYON RUN", "place": "THE GORGE", "reward": 850, "steps": 3,
		"card": "Fly the helicopter through the gorge and land on the pad.",
		"brief": [
			{"s": BASALT, "t": "The Authority watches the open sky. They cannot see the gorge. Stay under the ridge."},
			{"s": IRIS, "t": "The relay for the damper is at an outpost over the range. The gorge is the only way they will not track."},
		],
		"radio": [
			{"s": BASALT, "t": "Helicopter on the pad. Jump lifts, crouch drops, tilt with the stick."},
			{"s": BASALT, "t": "Fly the rings. Low and slow, the walls are closer than they look."},
			{"s": BASALT, "t": "Pad ahead. Bring her down easy and the first round is mine."},
		],
		"beats": [
			{"step": 1, "head": "THE GORGE", "sub": "UNDER THE RIDGE", "lines": [
				{"s": BASALT, "t": "Ridge radar loses you under the rim. Follow the river and do not clip the walls."},
				{"s": O, "t": "I am scanning for patrol. The gorge is clear."},
				{"s": K, "t": "Then fly."},
			]},
		],
		"outro": {"s": BASALT, "t": "Clean flying. The sea is next. Iris says the Array's power cable runs under the sound."}},
	{"id": "deep_water", "act": 3, "title": "DEEP WATER", "place": "THE SOUND", "reward": 900, "steps": 3,
		"card": "Follow the buoys out to sea and find the end of the cable.",
		"brief": [
			{"s": IRIS, "t": "The Array draws power from a cable under the sound. Follow it from the harbour to the sunken relay."},
			{"s": RIVET, "t": "Speedboat at pier A. Fuel is full, spirit is willing."},
		],
		"radio": [
			{"s": RIVET, "t": "Same boat, same pier. Try not to sink it twice."},
			{"s": IRIS, "t": "The buoys mark the cable. Follow them out past the breakwater into open water."},
			{"s": O, "t": "Relay buoy ahead. The cable ends here. Iris is reading the bearing now."},
		],
		"beats": [],
		"outro": {"s": IRIS, "t": "The cable bends north, to the mountain outpost. That is where the hive feeds the door."}},
	{"id": "the_outpost", "act": 4, "title": "THE OUTPOST", "place": "ALIEN OUTPOST", "reward": 1000, "steps": 5,
		"card": "Fly to the alien outpost, break the Warden, plant the core.",
		"brief": [
			{"s": IRIS, "t": "The damper core turns your jumps silent. It has to sit beside the outpost's relay."},
			{"s": O, "t": "Hive grunts, spitters and a Warden. The outpost is a nest with walls."},
			{"s": K, "t": "Then I am knocking."},
		],
		"radio": [
			{"s": BASALT, "t": "A helicopter waits on the mountain pad. I will keep your seat warm."},
			{"s": BASALT, "t": "Climb in. Jump lifts, crouch drops. Same as before."},
			{"s": BASALT, "t": "Outpost on the ridge. Put her down short and hit the camp on foot."},
			{"s": O, "t": "The Warden wears the hive's armour and answers to the Choir. Break it."},
			{"s": IRIS, "t": "Plant the core at the relay. Hold the ring until it takes."},
		],
		"beats": [
			{"step": 4, "head": "THE BEACON", "sub": "ORACLE'S LINK", "lines": [
				{"s": IRIS, "t": "The core is fighting me. The beacon the hive follows is not you, Kestrel."},
				{"s": O, "t": "It is me. My link home to Last Light is the beacon. Every jump rang it."},
				{"s": K, "t": "Then cutting it means losing you."},
				{"s": O, "t": "We will talk on the way to the tower. Plant the core."},
			]},
		],
		"outro": {"s": O, "t": "The core is live and your jumps are silent. The Array is still tuned to my link, and Voss switches it on today."}},
	{"id": "tuning_day", "act": 4, "title": "TUNING DAY", "place": "THE ARRAY TOWER", "reward": 2000, "steps": 4,
		"card": "Reach the Array tower, hold the lobby, break Director Voss.",
		"brief": [
			{"s": RIVET, "t": "Voss is at the Array tower in the glass district. Every Authority car in the city is there."},
			{"s": BASALT, "t": "I keep the skies clear. Make it count, Kestrel."},
			{"s": IRIS, "t": "The Array switches on at dusk. The damper only holds so long."},
			{"s": O, "t": "I have a plan for the beacon. Get me to the top of that tower."},
		],
		"radio": [
			{"s": RIVET, "t": "The tower is the tall one with the red lights. Everyone else is running the other way."},
			{"s": O, "t": "They know you are coming. Hold the lobby until the lift is ready."},
			{"s": O, "t": "Voss believes the hive will keep its word. Break his shield and he has no one."},
			{"s": O, "t": "The Array is folding in on itself. Out, Kestrel. Teleport and run."},
		],
		"beats": [
			{"step": 2, "head": "THE DIRECTOR", "sub": "TUNING DAY", "lines": [
				{"s": VOSS, "t": "Courier. You are early. The door opens at dusk, and then they spare us."},
				{"s": K, "t": "They spare no one, Director. I have seen it."},
				{"s": VOSS, "t": "Then see it again."},
			]},
			{"step": 3, "head": "THE LAST FOLD", "sub": "ORACLE CUTS THE LINK", "lines": [
				{"s": O, "t": "Kestrel, the beacon is me. I am cutting my link now."},
				{"s": K, "t": "No."},
				{"s": O, "t": "It is the plan we made, in a language you have not learned yet. Run."},
			]},
		],
		"outro": {"s": O, "t": "Kestrel? It is quiet. I am still here. Quieter, but here."}},
]

## Typed over the screen after the last mission (head at most 30 characters, text at most ACT_CARD_MAX).
const ENDING: Array[Dictionary] = [
	{"head": "THE DOOR NEVER OPENS", "text": "The Array folded in on itself and the sky over Neo-Meridian is only sky. Voss fell with his door."},
	{"head": "LAST LIGHT", "text": "A message from 2140 arrives anyway: the redoubt is lit, because the hive never came through."},
	{"head": "ORACLE", "text": "It cut its own link and stayed. A quieter voice, an old name, one hint at a time. The city is yours."},
]
const CREDIT_SECONDS := 3.6
const CREDITS: Array[Dictionary] = [
	{"head": "THE LONG TOMORROW", "lines": ["A story told in one day"]},
	{"head": "KESTREL", "lines": ["Warden of Last Light", "Who stayed"]},
	{"head": "ORACLE", "lines": ["Who cut the link", "And stayed too"]},
	{"head": "RIVET  IRIS  BASALT", "lines": ["A garage, a dish, a plane", "A city worth the fold"]},
	{"head": "THANK YOU FOR PLAYING", "lines": ["The door never opened", "The city is yours"]},
]
const END_SUBS: Array[Dictionary] = [
	{"t0": 1.0, "t1": 5.0, "s": O, "t": "Last Light is lit, Kestrel. I can hear them, very far away. They are singing."},
	{"t0": 5.6, "t1": 9.6, "s": K, "t": "Then keep talking, ORACLE. This city has a lot of streets left to name."},
	{"t0": 10.2, "t1": 14.0, "s": O, "t": "I will name every one. Start walking."},
]

const TOTAL := 12


# --- queries -------------------------------------------------------------------------------------------------------------------------

static func count() -> int:
	return MISSIONS.size()


static func mission(i: int) -> Dictionary:
	return MISSIONS[i] if i >= 0 and i < MISSIONS.size() else {}


static func index_of(id: String) -> int:
	for i in MISSIONS.size():
		if str(MISSIONS[i]["id"]) == id:
			return i
	return -1


static func act(n: int) -> Dictionary:
	return ACTS[n - 1] if n >= 1 and n <= ACTS.size() else {}


## The mission indices of act `n` (1..4).
static func act_missions(n: int) -> Array[int]:
	var out: Array[int] = []
	for i in MISSIONS.size():
		if int(MISSIONS[i]["act"]) == n:
			out.append(i)
	return out


## The voice that carries mission `i`: the first speaker of its briefing who is not the hero (the hero when nobody else speaks).
static func lead_speaker(i: int) -> String:
	var m := mission(i)
	for l: Variant in m.get("brief", []):
		if str((l as Dictionary)["s"]) != K:
			return str((l as Dictionary)["s"])
	return K


## True when mission `i` is the first of its act (its briefing carries the act title card).
static func first_of_act(i: int) -> bool:
	return i == 0 or int(MISSIONS[i]["act"]) != int(MISSIONS[i - 1]["act"])


static func last_of_act(i: int) -> bool:
	return i == MISSIONS.size() - 1 or int(MISSIONS[i]["act"]) != int(MISSIONS[i + 1]["act"])


## The first mission not in `done` (a Dictionary id -> completions), count() when the story is finished. Missions unlock in order.
static func next_index(done: Dictionary) -> int:
	for i in MISSIONS.size():
		if int(done.get(str(MISSIONS[i]["id"]), 0)) <= 0:
			return i
	return MISSIONS.size()


static func done_count(done: Dictionary) -> int:
	var n := 0
	for m: Dictionary in MISSIONS:
		if int(done.get(str(m["id"]), 0)) > 0:
			n += 1
	return n


## "ACT 2  MISSION 5 OF 12" for mission `i`.
static func progress_text(i: int) -> String:
	if i < 0 or i >= MISSIONS.size():
		return "STORY COMPLETE"
	return "ACT %d  MISSION %d OF %d" % [int(MISSIONS[i]["act"]), i + 1, MISSIONS.size()]


## Seconds a subtitle of `text` stays up (reading time on a phone).
static func line_seconds(text: String) -> float:
	return clampf(1.3 + 0.048 * float(text.length()), 2.0, 7.0)


## Every {s, t} line of the story, for the length and speaker checks.
static func all_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in MISSIONS:
		out.append_array(m["brief"] as Array)
		out.append_array(m["radio"] as Array)
		for b: Dictionary in m["beats"]:
			out.append_array(b["lines"] as Array)
		out.append(m["outro"])
	out.append_array(END_SUBS)
	return out
