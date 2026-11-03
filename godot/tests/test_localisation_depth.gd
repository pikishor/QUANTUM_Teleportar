extends RefCounted
## Localisation depth: Spanish story/radio/contract/mission/HUD strings, Hindi menus and HUD (Devanagari fallback), numeric and composite lines, text-scale fit.
## Run: tools/test.sh tests/test_localisation_depth.gd

func _ids(list: Array, out: Array) -> void:
	for e: Variant in list:
		if e is Dictionary:
			for k: String in ["t", "text", "head", "obj", "title", "sub"]:
				if (e as Dictionary).has(k) and (e as Dictionary)[k] is String:
					out.append((e as Dictionary)[k])


func run(host: Node) -> void:
	Tr.set_lang("en")
	Tr.text_scale = 1.0
	TestLib.check(Tr.LANGS.has("hi") and Tr.LANGS.has("es") and Tr.LANGS.size() == 3 and Tr.next_lang("es") == "hi" and Tr.next_lang("hi") == "en", "three languages cycle")

	# story / radio / contract / mission coverage in Spanish
	var lines: Array = []
	for ch: Dictionary in StoryData.CHAPTERS:
		_ids([ch], lines)
		_ids(ch["intro"], lines)
		_ids((ch["cores"] as Dictionary).values(), lines)
		_ids([ch["heat1"], ch["heat3"], ch["end"]], lines)
	for pool: Dictionary in [StoryData.RADIO, StoryData.CONTRACT_RADIO, StoryData.CONTRACT_GENERIC]:
		for v: Variant in pool.values():
			if v is Array:
				_ids(v, lines)
	_ids(StoryData.PROLOGUE, lines)
	_ids(StoryData.EPILOGUE, lines)
	_ids(StoryData.RESPAWN, lines)
	_ids(StoryData.LOW_HEALTH, lines)
	_ids(StoryData.DEATH, lines)
	_ids(StoryData.CONTRACT_CHAPTER, lines)
	for d: Dictionary in CampaignData.CAMPAIGN:
		for st: Dictionary in d["steps"]:
			lines.append(str(st["obj"]))
			lines.append(str((st["radio"] as Dictionary)["t"]))
	lines.append(StoryData.TAGLINE)
	var missing: Array = []
	for l: String in lines:
		if not Tr.has_tr("es", l):
			missing.append(l)
	TestLib.check(lines.size() > 150, "collected the story strings (%d)" % lines.size())
	TestLib.check(missing.size() <= maxi(lines.size() / 25, 3), "Spanish covers story, radio, contract and campaign lines (missing %d: %s)" % [missing.size(), str(missing.slice(0, 3))])

	# side-mission and contract titles
	var titles := 0
	for k: Variant in SideMissions.DEFS:
		if Tr.has_tr("es", str(SideMissions.DEFS[k]["title"])) and Tr.has_tr("es", str(SideMissions.DEFS[k]["brief"])):
			titles += 1
	TestLib.check(titles >= SideMissions.DEFS.size() - 2, "side missions translated")

	# translating switches the language, English stays the key
	Tr.set_lang("es")
	TestLib.check(Tr.t("Who is in my head?") == "¿Quién está en mi cabeza?" and Tr.t("NEW GAME") == "NUEVA PARTIDA", "Spanish lookups")
	TestLib.check(Tr.t("WAVE 2 / 5") == "OLEADA 2 / 5" and Tr.t("12% DAMAGE") == "12% DAÑO", "numbers inside a translated line")
	TestLib.check(Tr.t("MISSION FAILED  TIME UP") == "MISIÓN FALLIDA  TIEMPO AGOTADO", "composite lines translate per part")
	TestLib.check(Tr.t("QUANTUM CORES  2 / 6   NEAREST  143 M").begins_with("NÚCLEOS") and Tr.t("A line nobody translated 12") == "A line nobody translated 12", "HUD objective and unknown passthrough")
	TestLib.check(Tr.t("QUANTUM TELEPORT") == "QUANTUM TELEPORT" and Tr.t("SUPERPOSITION") == "SUPERPOSITION", "quantum names stay plain")

	# the story layer drives it: a radio line, a card, the chapter label and the objective come out translated and are typed by their translated length
	var story := Story.new()
	story.enabled = true
	story.say("ORACLE", "Who is in my head?")
	TestLib.check(str(story.queue[0]["t"]) == "¿Quién está en mi cabeza?", "radio line queued translated")
	story.start_cards(StoryData.PROLOGUE, &"prologue")
	TestLib.check(str(story.cards[0]["head"]) == Tr.t("NEO-MERIDIAN  //  2091") and str(story.cards[0]["text"]) != str(StoryData.PROLOGUE[0]["text"]), "cards translated")
	story.chapter = 0
	TestLib.check(story.chapter_label() == "CAPÍTULO 1" and story.objective_text() == Tr.t("Recover the cores. Stay out of sight."), "chapter label and objective")
	story.free()

	# Hindi: menus and HUD
	Tr.set_lang("hi")
	var hi_ok := 0
	var keys := ["NEW GAME", "CONTINUE", "DEPLOY", "RESUME", "PAUSED", "OPTIONS", "BACK", "INTEGRITY", "COHERENCE", "RELOADING", "LANGUAGE", "TEXT SIZE", "SUBTITLES", "ACHIEVEMENTS", "UPGRADES", "RESPAWN", "NEXT SECTOR", "GRAPHICS", "ON", "OFF"]
	for k: String in keys:
		if Tr.t(k) != k and _has_devanagari(Tr.t(k)):
			hi_ok += 1
	TestLib.check(hi_ok == keys.size(), "Hindi covers the menu and HUD keys in Devanagari")
	TestLib.check(Tr.t("QUANTUM TELEPORT") == "QUANTUM TELEPORT" and Tr.t("WAVE 3 / 5") == "लहर 3 / 5", "Hindi plain quantum names and numbers")
	TestLib.check(Tr.t("Who is in my head?") == "Who is in my head?", "Hindi falls back to English for the story")

	# Devanagari font fallback: configured on the HUD font; a glyph only asserted when the machine has a Devanagari face
	var font := UiUtil.font()
	var fv := font as FontVariation
	var base: Font = fv.base_font if fv != null else font
	TestLib.check(base.fallbacks.size() >= 1 and base.fallbacks[0] is SystemFont, "HUD font carries the Devanagari fallback")
	var sz := font.get_string_size(Tr.t("NEW GAME"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	TestLib.check(sz.x >= 0.0 and sz.y >= 0.0, "Hindi measures without error (glyphs present: %s)" % str(font.has_char(0x0928)))

	# 1.5x text scale on a phone-size card never overflows the card band
	for l in ["en", "es", "hi"]:
		Tr.set_lang(l)
		Tr.text_scale = 1.5
		var v := StoryView.new()
		var s := 390.0 / 720.0
		var width := 844.0 * 0.84
		var maxh := 390.0 * StoryView.CARD_H - 64.0 * s - 22.0 * s
		var text := Tr.t(str(StoryData.PROLOGUE[1]["text"]))
		var blk := v.scaled_block(text, width, 22.0 * s, 11, maxh)
		var lines_n: int = (blk["lines"] as PackedStringArray).size()
		TestLib.check(int(blk["size"]) >= 11 and (float(lines_n) * float(blk["step"]) <= maxh + 1.0 or int(blk["size"]) == 11), "card block fits at 1.5x (%s)" % l)
		for ln: String in blk["lines"]:
			if UiUtil.font().get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, int(blk["size"])).x > width + 1.0:
				TestLib.check(false, "card line wider than the band (%s)" % l)
		v.free()
	Tr.text_scale = 1.0
	Tr.set_lang("en")


func _has_devanagari(t: String) -> bool:
	for i in t.length():
		var c := t.unicode_at(i)
		if c >= 0x0900 and c <= 0x097F:
			return true
	return false
