class_name CineData
extends RefCounted
## The words of the cutscenes (subtitles use StoryData's speakers and colours). A subtitle is {t0, t1, s, t}: seconds from the start of the scene, speaker, text.
## Limits (tests/test_cinematic.gd): every line at most StoryData.LINE_MAX characters, known speaker, inside the scene's duration.

const INTRO_TITLE := "QUANTUM TELEPORTAR"

const INTRO_SUBS: Array[Dictionary] = [
	{"t0": 1.0, "t1": 5.6, "s": StoryData.O, "t": "Neo-Meridian, 2091. Forty-nine years before the dark. The hive is already scouting this city."},
	{"t0": 6.2, "t1": 10.4, "s": StoryData.O, "t": "Observers. They hang over every street and drink coherence from anyone who looks up."},
	{"t0": 10.9, "t1": 13.4, "s": StoryData.O, "t": "Do not stare back, Kestrel. Looking is what they feed on."},
	{"t0": 14.2, "t1": 17.6, "s": StoryData.O, "t": "Your fold dropped you here. Tuning Day is tomorrow. We stop the Array."},
	{"t0": 17.8, "t1": 19.5, "s": StoryData.K, "t": "Two places at once."},
]

const CHAPTER_SUBS: Array[Dictionary] = []

const BOSS_IN_SUBS: Array[Dictionary] = [
	{"t0": 0.6, "t1": 4.2, "s": StoryData.O, "t": "Contact. A Vael Overseer, wired into every drone on this street. Do not fight it in the open."},
]
const BOSS_OUT_SUBS: Array[Dictionary] = [
	{"t0": 0.5, "t1": 3.8, "s": StoryData.O, "t": "Its signal just dropped out of every drone in the sector. Breathe, Kestrel. You did that."},
]

const GARAGE_SUBS: Array[Dictionary] = [
	{"t0": 0.8, "t1": 3.6, "s": StoryData.O, "t": "This is the garage. Everything you need is under that tarp."},
	{"t0": 4.4, "t1": 7.4, "s": StoryData.K, "t": "It still runs."},
]
const TELEPORT_SUBS: Array[Dictionary] = [
	{"t0": 0.8, "t1": 3.0, "s": StoryData.O, "t": "Step onto the pad, Kestrel."},
	{"t0": 4.6, "t1": 6.4, "s": StoryData.K, "t": "Two places at once."},
]
const GARAGE_HEAD := "THE GARAGE"
const GARAGE_SUB := "YOUR BASE"
const TELEPORT_HEAD := "QUANTUM TELEPORT"
const TELEPORT_SUB := "FIRST JUMP"

const CHAPTER_HEAD := "OBJECTIVE"
const BOSS_IN_HEAD := "VAEL OVERSEER"
const BOSS_IN_SUB := "HIVE COMMANDER  //  THREE PHASES"
const BOSS_OUT_HEAD := "OVERSEER DOWN"
const BOSS_OUT_SUB := "THE HIVE FELT THAT"


## Every subtitle of every scene (the test checks them against the story limits).
static func all_subs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for list: Array[Dictionary] in [INTRO_SUBS, CHAPTER_SUBS, GARAGE_SUBS, TELEPORT_SUBS, BOSS_IN_SUBS, BOSS_OUT_SUBS]:
		out.append_array(list)
	return out
