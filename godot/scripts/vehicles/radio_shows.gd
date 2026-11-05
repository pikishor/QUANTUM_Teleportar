class_name RadioShows
extends RefCounted
## The car radio's programme (AUDIO v3). Each station is a show: songs (named, played from the station's loop at a per-song pitch), a host with a short burst of garbled alien
## chatter (no words, only voice-like sound from the generator), and ads between songs. Pure data plus a deterministic schedule so tests can check it; CarRadio plays it.
## Segment = {kind: "song" | "talk" | "ad", name, clip (sound name, empty for a song), pitch (songs), secs}.

const SONG_SECS := 34.0                    ## a song is the station loop repeated for about this long
const AD_BRANDS: Array[String] = ["SKYNOODLE", "RIFT TAXI", "QUANTA CELL"]
const AD_CLIPS: Array[StringName] = [&"ad_0", &"ad_1", &"ad_2"]
## Per station (same order as CarRadio.STATIONS): host name, talk clips, songs [title, pitch scale of the loop].
const SHOWS: Array[Dictionary] = [
	{"host": "DJ GLASSLINE", "talk": [&"talk_neon_0", &"talk_neon_1"], "songs": [["CHROME HORIZON", 1.0], ["LAST TRAM HOME", 0.94], ["SIGNAL IN RED", 1.06]]},
	{"host": "THE HIVE VOICE", "talk": [&"talk_vael_0", &"talk_vael_1"], "songs": [["DRONE PSALM", 1.0], ["CHITIN CHOIR", 1.08], ["HOLLOW COMB", 0.92]]},
	{"host": "MC RIFTWALKER", "talk": [&"talk_club_0", &"talk_club_1"], "songs": [["FLOOR COLLAPSE", 1.0], ["PHASE DANCE", 1.05], ["AFTER THE GATE", 0.95]]},
	{"host": "SLOW ORBIT", "talk": [&"talk_lofi_0", &"talk_lofi_1"], "songs": [["BALCONY RAIN", 1.0], ["SLEEPING RELAY", 0.9], ["TEA AT MERIDIAN", 1.07]]},
]
## One cycle of the programme as kinds: songs carry the show, every second break is an ad.
const CYCLE: Array[String] = ["song", "talk", "song", "ad", "song", "song", "talk", "song", "ad", "song"]


static func show_count() -> int:
	return SHOWS.size()


static func host(station: int) -> String:
	return String(SHOWS[clampi(station, 0, SHOWS.size() - 1)]["host"])


static func songs(station: int) -> Array:
	return SHOWS[clampi(station, 0, SHOWS.size() - 1)]["songs"]


## Segment `index` (0, 1, 2 ...) of a station's programme. Deterministic: the same index is always the same segment.
static func segment(station: int, index: int) -> Dictionary:
	var sh: Dictionary = SHOWS[clampi(station, 0, SHOWS.size() - 1)]
	var kind: String = CYCLE[index % CYCLE.size()]
	var cycle := index / CYCLE.size()
	var songs_before := 0
	var talks_before := 0
	var ads_before := 0
	for k in index:
		match CYCLE[k % CYCLE.size()]:
			"song":
				songs_before += 1
			"talk":
				talks_before += 1
			_:
				ads_before += 1
	match kind:
		"song":
			var s: Array = (sh["songs"] as Array)[songs_before % (sh["songs"] as Array).size()]
			return {"kind": "song", "name": String(s[0]), "clip": &"", "pitch": float(s[1]), "secs": SONG_SECS}
		"talk":
			var clips: Array = sh["talk"]
			return {"kind": "talk", "name": String(sh["host"]), "clip": clips[(talks_before + cycle) % clips.size()], "pitch": 1.0, "secs": 0.0}
		_:
			var a := (ads_before + station) % AD_CLIPS.size()
			return {"kind": "ad", "name": AD_BRANDS[a], "clip": AD_CLIPS[a], "pitch": 1.0, "secs": 0.0}


## The first `count` segments of a station (tests).
static func plan(station: int, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(segment(station, i))
	return out


static func caption(seg: Dictionary, station_name: String) -> String:
	match String(seg["kind"]):
		"song":
			return "%s · %s" % [station_name, String(seg["name"])]
		"talk":
			return "%s · %s" % [station_name, String(seg["name"])]
		_:
			return "AD · %s" % String(seg["name"])
