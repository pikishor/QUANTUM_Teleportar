extends RefCounted
## Citizen barks and rumours of Neo-Meridian (alien-latin street talk: Vael hive words, dog-latin, a little neon slang). Short (<= StoryData.LINE_MAX), shown through
## Game.say. Rumour seeds are taken from the story (tagline, freed-sector endings) so the street repeats what the campaign says.

const StoryData := preload("res://scripts/story/story_data.gd")

const PREFIX := "CIVIS: "

## Idle talk at a shop front / bus stop / nowhere in particular.
const SHOP: Array[String] = [
	"Noodles up, neon low. Quo vadis, runner?",
	"Pretium ascendit again. Even the soup is taxed by the hive.",
	"The signs hum in Vael tongue tonight. I do not ask what they say.",
	"Fresh stock behind the shutter. Do not look at the Observers.",
]
const BUS: Array[String] = [
	"The omnibus is late. The omnibus is always late. Vael vigilat.",
	"Waiting for a bus that may not love us. Sit, civis, sit.",
	"Third night this lamp flickers in threes. A message, they say.",
	"No hover will stop here after the patrol passes. Patience.",
]
## Idle talk of a group.
const CHAT: Array[String] = [
	"Audi: the drones sing at three, then they stop. Nobody sleeps.",
	"They say a runner folds space like a blanket. I say, pass the tea.",
	"Tace, civis. The lamp-posts have ears and cores.",
]
## Rumours (general).
const RUMOUR: Array[String] = [
	"Rumour: two halves of one person, one in the rift. Bell pair, they whisper.",
	"A sector went quiet near the old rail. Quiet is not freedom, but it is close.",
	"They say the Overseer never sleeps. I say it never needed to.",
	"Cave canem, cave Vael. Both bite, only one bills you.",
]
## The player is wanted (heat 3 and over): fear and denunciation.
const WANTED: Array[String] = [
	"Non me! I saw nothing, runner. Nihil. Go.",
	"Vigiles are hunting you. Take the alley, not my street!",
	"You bring the red lights. Procul, procul!",
]
## A person who is crouched or has just run.
const SCARED: Array[String] = [
	"Parce! Spare me, I only sell lamps.",
	"Down, down, down. Pax, pax, pax.",
	"Stop the thunder, runner. My children hear it.",
]
## A person who called the patrol.
const CALL: Array[String] = [
	"VIGILES! Gunfire at the crossing!",
	"Patrol, patrol! The runner is here!",
	"Calling the Watch. Forgive me, runner. Fear has a price.",
]


static func pick(pool: Array[String], rng: RandomNumberGenerator) -> String:
	return PREFIX + pool[rng.randi() % pool.size()]


## The rumour pool, with seeds from the story (a short line from the campaign data).
static func rumours() -> Array[String]:
	var out: Array[String] = RUMOUR.duplicate()
	var tag: String = StoryData.TAGLINE
	if tag != "" and PREFIX.length() + tag.length() <= StoryData.LINE_MAX:
		out.append(tag)
	for ch: Dictionary in StoryData.CHAPTERS:
		var e: Dictionary = ch.get("end", {})
		var t: String = e.get("text", "")
		if t != "" and PREFIX.length() + t.length() <= StoryData.LINE_MAX:
			out.append(t)
	return out


static func all_pools() -> Array:
	return [SHOP, BUS, CHAT, RUMOUR, WANTED, SCARED, CALL]
