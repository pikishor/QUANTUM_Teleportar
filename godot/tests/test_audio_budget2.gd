extends RefCounted
## Audio size pass: the folder is well under its budget, long one-shots and the legacy music loop ship as mono OGG, ambience beds are mono, no big WAV is left,
## and rarely used streams (boss theme, stings, thunder, airship, radio ads) are loaded lazily and dropped again by Sfx.unload_rare() (live Sfx autoload).
## Run: tools/test.sh tests/test_audio_budget2.gd

const DIR := "res://assets/audio/"
const TOTAL_BUDGET_MB := 24.0        ## was 29.6 MB before the pass
const MAX_WAV_BYTES := 450000        ## anything bigger than this must be OGG
const NOW_OGG: Array[String] = ["boom", "boom_1", "distant_boom_0", "distant_gunfire_0", "car_crash_0", "explosion_small_0", "siren", "sting_boss", "sting_win", "sting_death", "core", "music_ambient"]
const MONO_BEDS: Array[String] = ["rain_asphalt", "rain_metal", "rain_awning", "traffic_far", "wind", "city_hum"]


func run(_host: Node) -> void:
	var total := 0
	var big_wavs: Array[String] = []
	for n in DirAccess.get_files_at(DIR):
		if n.ends_with(".wav") or n.ends_with(".ogg"):
			var f := FileAccess.open(DIR + n, FileAccess.READ)
			var sz := f.get_length()
			total += sz
			if n.ends_with(".wav") and sz > MAX_WAV_BYTES:
				big_wavs.append(n)
	var mb := float(total) / 1048576.0
	TestLib.check(mb <= TOTAL_BUDGET_MB, "audio folder %.1f MB is inside the %.0f MB budget after the size pass" % [mb, TOTAL_BUDGET_MB])
	TestLib.check(big_wavs.is_empty(), "no WAV over %d KB is left (%s)" % [MAX_WAV_BYTES / 1000, str(big_wavs)])
	var bad: Array[String] = []
	for n in NOW_OGG:
		var v := Sfx.variants_of(StringName(n))
		if v.is_empty() or not (v[0] is AudioStreamOggVorbis) or (v[0] as AudioStreamOggVorbis).get_length() < 1.0:
			bad.append(n)
	TestLib.check(bad.is_empty(), "long one-shots, stings and the legacy loop load as OGG through Sfx (bad: %s)" % str(bad))
	var loop := Sfx._loop_stream(&"music_ambient") as AudioStreamOggVorbis
	TestLib.check(loop != null and loop.loop and absf(loop.get_length() - 30.0) < 0.5, "music_ambient is a 30 s looping OGG")
	var stereo: Array[String] = []
	for n in MONO_BEDS:
		var s := load(DIR + n + ".ogg") as AudioStreamOggVorbis
		if s == null or s.get_length() < 20.0:
			stereo.append(n)
	TestLib.check(stereo.is_empty(), "ambience beds load as 24 s OGG (%s)" % str(stereo))
	# lazy loading: rare names are cached on first use and dropped by unload_rare(); the sound still plays after a reload
	Sfx.unload_rare()
	TestLib.check(not Sfx._cache.has(&"music_boss"), "rare streams are not cached after unload_rare()")
	var first := Sfx.variants_of(&"music_boss")
	TestLib.check(not first.is_empty() and Sfx._cache.has(&"music_boss"), "the boss theme loads on demand")
	var held: AudioStream = first[0]
	var dropped := Sfx.unload_rare()
	TestLib.check(dropped >= 1 and not Sfx._cache.has(&"music_boss") and held.get_length() > 20.0, "unload_rare() drops the cache entry (%d) and a held stream stays valid" % dropped)
	TestLib.check(not Sfx.variants_of(&"music_boss").is_empty(), "the boss theme reloads on the next use")
	TestLib.check(Sfx.RARE_NAMES.has(&"music_boss") and Sfx.RARE_NAMES.has(&"sting_boss") and not Sfx.RARE_NAMES.has(&"shot") and not Sfx.RARE_NAMES.has(&"music_pulse"), "frequent sounds and the core stems are never unloaded")
	Sfx.unload_rare()
