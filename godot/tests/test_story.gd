extends RefCounted
## Story layer: data validity (every line has a known speaker and fits the length limits, at least 60 lines), events trigger the right lines,
## one-shot lines never repeat, pools do not repeat, cards are typed and skippable by tap, lifecycle resets, death / end cards, subtitle layout.
## Run: tools/test.sh tests/test_story.gd

class StubQuantum extends Node:
	var has_beacon := false
	var bits_left := 0.0
	var links: Array = []
	var clone: Node3D


class StubPlayer extends Node3D:
	var hp := 100.0
	var max_hp := 100.0
	var vehicle: Node3D
	var quantum: Node


class StubMissions extends Node:
	var got := 0
	var total := 6


func _all_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ch: Dictionary in StoryData.CHAPTERS:
		for l: Dictionary in ch["intro"]:
			out.append(l)
		for k: Variant in (ch["cores"] as Dictionary):
			out.append(ch["cores"][k])
		out.append(ch["heat1"])
		out.append(ch["heat3"])
	for ev: String in StoryData.RADIO:
		for l: Dictionary in StoryData.RADIO[ev]:
			out.append(l)
	for pool: Array in [StoryData.RESPAWN, StoryData.LOW_HEALTH, StoryData.DEATH]:
		for l: Dictionary in pool:
			out.append(l)
	return out


func _step(story: Story, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		story.advance(minf(left, 0.1))
		left -= 0.1


func _drain(story: Story, limit := 600.0) -> void:
	var t := 0.0
	while (not story.queue.is_empty() or story.line_visible() or not story.current.is_empty()) and t < limit:
		story.advance(0.1)
		t += 0.1


func run(host: Node) -> void:
	# --- data ---------------------------------------------------------------------------------------------------
	var lines := _all_lines()
	TestLib.check(lines.size() >= 70, "at least 70 radio lines written (%d)" % lines.size())
	var bad := 0
	for l: Dictionary in lines:
		if not (l.has("s") and l.has("t")) or not StoryData.SPEAKERS.has(str(l["s"])) or str(l["t"]).length() < 8 or str(l["t"]).length() > StoryData.LINE_MAX:
			bad += 1
			printerr("bad line: ", l)
	TestLib.check(bad == 0, "every line has a known speaker and 8..%d characters" % StoryData.LINE_MAX)
	var seen := {}
	var dup := 0
	for l: Dictionary in lines:
		if seen.has(l["t"]):
			dup += 1
		seen[l["t"]] = true
	TestLib.check(dup == 0, "no line of text is written twice")
	var speakers := {}
	for l: Dictionary in lines:
		speakers[l["s"]] = true
	TestLib.check(speakers.size() == 3, "ORACLE, KESTREL and VAEL BROADCAST all speak")
	var cards_ok := StoryData.PROLOGUE.size() == 3 and StoryData.EPILOGUE.size() >= 3
	for c: Dictionary in StoryData.PROLOGUE + StoryData.EPILOGUE:
		cards_ok = cards_ok and str(c["text"]).length() <= StoryData.CARD_MAX and str(c["head"]).length() <= 30 and str(c["text"]).length() > 20
	TestLib.check(cards_ok, "3 prologue cards and an epilogue, text within %d characters" % StoryData.CARD_MAX)
	var ch_ok := StoryData.CHAPTERS.size() == StoryData.FINAL + 2
	for ch: Dictionary in StoryData.CHAPTERS:
		ch_ok = ch_ok and str(ch["title"]).length() <= StoryData.TITLE_MAX and str(ch["obj"]).length() <= StoryData.OBJ_MAX and str(ch["sub"]).length() <= 40
		ch_ok = ch_ok and (ch["cores"] as Dictionary).size() >= 3 and (ch["intro"] as Array).size() >= 1
		ch_ok = ch_ok and str(ch["end"]["text"]).length() <= 220 and str(ch["end"]["head"]).length() <= 30
		for k: Variant in (ch["cores"] as Dictionary):
			ch_ok = ch_ok and int(k) >= 1 and int(k) <= 5          # every sector has at least 6 cores; the last core ends the chapter
	TestLib.check(ch_ok, "8 story chapters + aftermath: titles, objectives, core lines (1..5) and end cards fit")
	TestLib.check(StoryData.TAGLINE.length() > 10 and StoryData.TAGLINE.length() < 60, "title tagline fits")
	var triggers_ok := true
	for t: Dictionary in StoryData.MESSAGE_TRIGGERS:
		triggers_ok = triggers_ok and StoryData.RADIO.has(t["event"])
	TestLib.check(triggers_ok, "every message trigger points at a radio event")
	# wrap fits the phone width: a 112 character line wraps to at most 4 lines at the subtitle width
	var font := UiUtil.font()
	var wrapped := StoryView.wrap_text(font, "x".repeat(10) + " " + "word ".repeat(20), 340.0, 17)
	TestLib.check(wrapped.size() >= 2 and wrapped.size() <= 6, "word wrap splits long text (%d lines)" % wrapped.size())
	var worst := 0
	for l: Dictionary in lines:
		worst = maxi(worst, StoryView.wrap_text(font, str(l["t"]), 340.0 - 24.0, 17).size())
	TestLib.check(worst <= 4, "every radio line fits in 4 lines even at the narrowest subtitle width (%d)" % worst)
	# the phone subtitle plate: measured and wrapped to a 320 px plate, never clipped, never taller than SUB_MAX_LINES
	var sv := StoryView.new()
	var inner := StoryView.SUB_W - 26.0
	var too_wide := 0
	var too_tall := 0
	var shrunk := 0
	for l: Dictionary in lines:
		var fl := sv.fit_lines(str(l["t"]), inner, int(StoryView.SUB_FONT), int(StoryView.SUB_SMALL), StoryView.SUB_MAX_LINES)
		var fs := sv.fit_size()
		shrunk += 1 if fs < int(StoryView.SUB_FONT) else 0
		too_tall += 1 if fl.size() > StoryView.SUB_MAX_LINES + 1 else 0
		for ln in fl:
			too_wide += 1 if font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > inner + 1.0 else 0
	TestLib.check(too_wide == 0 and too_tall == 0, "every radio line wraps inside the %d px subtitle plate and needs at most %d lines (%d too wide, %d too tall, %d shrunk to %d px)" % [int(StoryView.SUB_W), StoryView.SUB_MAX_LINES + 1, too_wide, too_tall, shrunk, int(StoryView.SUB_SMALL)])
	var broken := StoryView.wrap_text(font, "A" + "W".repeat(60) + " end", inner, 22)
	var broken_ok := broken.size() >= 3
	for ln in broken:
		broken_ok = broken_ok and font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x <= inner + 1.0
	TestLib.check(broken_ok, "a single word wider than the plate is broken by characters instead of clipping (%d lines)" % broken.size())
	TestLib.check(StoryView.fit_font(font, "A rather long chapter subtitle that cannot fit", 120.0, 22, 15) == 15, "fit_font shrinks to its floor when nothing fits")
	sv.free()

	# --- behaviour ----------------------------------------------------------------------------------------------
	var story := Story.new()
	host.add_child(story)
	var player := StubPlayer.new()
	var quantum := StubQuantum.new()
	player.add_child(quantum)
	player.quantum = quantum
	host.add_child(player)
	var missions := StubMissions.new()
	host.add_child(missions)
	var old_player: Node3D = Game.player
	var old_missions: Node = Game.missions
	Game.player = player
	Game.missions = missions
	Game.state = &"play"
	TestLib.check(Game.story == story, "Story registers as Game.story")
	TestLib.check(story.tagline() == StoryData.TAGLINE, "tagline for the title screen")

	# new game: three prologue cards, tap-skippable, then the chapter banner and intro
	Game.new_game.emit()
	TestLib.check(story.cards_active() and story.cards.size() == 3 and story.card_kind == &"prologue", "DEPLOY starts the 3 prologue cards")
	story.advance(0.1)
	TestLib.check(story.card_text() != "" and story.card_text().length() < str(StoryData.PROLOGUE[0]["text"]).length(), "the card text is typed, not shown at once")
	TestLib.check(story.advance_card(), "a tap right after the card appears is swallowed (no skip)")
	TestLib.check(story.cards.size() == 3, "...and does not skip a card within the first moments")
	_step(story, 0.5)
	story.advance_card()
	TestLib.check(story.card_text() == str(StoryData.PROLOGUE[0]["text"]) and story.cards.size() == 3, "first tap completes the typing")
	story.advance_card()
	TestLib.check(story.cards.size() == 2, "second tap moves to the next card")
	_step(story, 0.5)
	story.skip_cards()
	TestLib.check(not story.cards_active() and story.card_kind == &"", "skipping ends the prologue")
	TestLib.check(story.banner_visible() and story.chapter_label() == "CHAPTER 1", "chapter 1 banner after the prologue")
	TestLib.check(story.objective_text() == str(StoryData.CHAPTERS[0]["obj"]), "objective line of chapter 1")
	TestLib.check(story.shown.has("c1.intro") and not story.queue.is_empty(), "chapter 1 intro lines are queued")
	var seen_speaker := ""
	var guard := 0
	while not story.line_visible() and guard < 50:
		story.advance(0.1)
		guard += 1
	seen_speaker = str(story.current.get("s", ""))
	TestLib.check(story.line_visible() and seen_speaker == "ORACLE", "the first radio line is ORACLE's, shown after a short gap")
	_step(story, 0.5)
	TestLib.check(story.line_text().length() > 0 and story.line_text().length() < str(story.current["t"]).length(), "radio lines are typed")
	_drain(story)
	TestLib.check(story.queue.is_empty() and not story.line_visible(), "the queue drains and the subtitle disappears")
	var t0 := 0.0
	while story.banner_visible() and t0 < 10.0:
		story.advance(0.1)
		t0 += 0.1
	TestLib.check(not story.banner_visible(), "the banner leaves by itself")

	# missions: cores
	missions.got = 1
	story.advance(0.1)                                  # first poll baselines nothing new (resync), the next one sees the core
	story.advance(0.1)
	TestLib.check(story.shown.has("c1.core1"), "first core triggers the chapter's core-1 line")
	missions.got = 6
	var before := story.shown.size()
	story.advance(0.1)
	TestLib.check(story.shown.size() == before + 2 or story.shown.size() == before + 3, "cores 2..6 trigger only the lines that exist (3 and 5), never one for the last core")
	TestLib.check(not story.shown.has("c1.core6"), "the last core has no radio line (the win screen takes over)")
	_drain(story)

	# quantum first use, each once
	quantum.has_beacon = true
	story.advance(0.1)
	TestLib.check(story.shown.has("first_beacon"), "first beacon throw")
	quantum.bits_left = 4.0
	story.advance(0.1)
	TestLib.check(story.shown.has("first_teleport"), "first teleport explains the two bits")
	quantum.links = [{}]
	story.advance(0.1)
	TestLib.check(story.shown.has("first_link"), "first entangle")
	var clone := Node3D.new()
	host.add_child(clone)
	quantum.clone = clone
	story.advance(0.1)
	TestLib.check(story.shown.has("first_super"), "first superposition")
	var count := story.shown.size()
	quantum.has_beacon = false
	quantum.bits_left = 0.0
	story.advance(0.1)
	quantum.has_beacon = true
	quantum.bits_left = 4.0
	story.advance(0.1)
	TestLib.check(story.shown.size() == count, "one-shot lines never repeat")
	TestLib.check(story.trigger("first_beacon") == false, "trigger() refuses a repeat")
	_drain(story)

	# vehicle
	player.vehicle = Node3D.new()
	story.advance(0.1)
	TestLib.check(story.shown.has("first_vehicle"), "entering a vehicle")
	player.vehicle.free()
	player.vehicle = null
	# messages
	Game.say("VEHICLE COMMANDEERED", 1.0)
	TestLib.check(story.shown.has("carjack"), "the carjack message triggers its line")
	Game.say("BLINK OFFLINE IN VEHICLE", 1.0)
	TestLib.check(story.shown.has("quantum_offline"), "the offline message triggers its line")
	Game.say("VEHICLE COMMANDEERED", 1.0)
	TestLib.check(story.shown.count("carjack") == 1, "a repeated message does not repeat the line")
	_drain(story)

	# heat
	Game.heat = 0.0
	Game.heat = 1.2
	TestLib.check(story.shown.has("c1.heat1"), "heat 1 triggers the chapter's heat line")
	Game.heat = 3.1
	TestLib.check(story.shown.has("c1.heat3"), "heat 3 triggers the escalation line")
	Game.heat = 5.0
	TestLib.check(story.shown.has("heat5"), "maximum heat triggers the broadcast")
	Game.heat = 0.5
	Game.heat = 1.5
	TestLib.check(story.shown.count("c1.heat1") == 1, "the chapter's heat line is said once")
	_drain(story)
	var q_before := story.queue.size()
	Game.state = &"paused"
	Game.heat = 4.0
	Game.heat = 5.0
	Game.state = &"play"
	TestLib.check(story.queue.size() == q_before, "nothing is said while paused")

	# low health
	player.hp = 20.0
	story.advance(0.1)
	TestLib.check(story.shown.has("first_low_health"), "low health warning")
	player.hp = 100.0
	story.advance(0.1)
	_drain(story)

	# queue cap and priorities
	for i in 8:
		story.say("ORACLE", "Line number %d of a long queue." % i, "q%d" % i, 0.0, 0)
	TestLib.check(story.queue.size() <= Story.QUEUE_MAX, "the radio queue is capped (%d)" % story.queue.size())
	TestLib.check(story.say("KESTREL", "Urgent now.", "urgent", 0.0, 2), "an urgent line gets in when the queue is full")
	story.skip_line()
	_drain(story)

	# death, quotes without repeats
	player.hp = 0.0
	Game.state = &"dead"
	Game.player_died.emit()
	TestLib.check(not story.death_quote.is_empty() and StoryData.SPEAKERS.has(str(story.death_quote["s"])), "death shows a quote with a speaker")
	TestLib.check(story.queue.is_empty() and not story.line_visible(), "death clears the radio")
	var quotes := {}
	var repeats := 0
	var last := ""
	for i in StoryData.DEATH.size():
		Game.player_died.emit()
		var q := str(story.death_quote["t"])
		if quotes.has(q) or q == last:
			repeats += 1
		quotes[q] = true
		last = q
	TestLib.check(repeats <= 1, "death quotes do not repeat until the pool is used up (%d repeats)" % repeats)
	story.advance(1.0)
	TestLib.check(story.death_age >= 1.0, "the death quote fades in over the DECOHERED screen")
	var before_cp := story.shown.size()
	player.hp = 100.0
	Game.state = &"play"
	Game.respawn.emit()
	TestLib.check(story.death_quote.is_empty() and story.shown.back() == "respawn", "respawn clears the quote and queues a respawn line")
	TestLib.check(story.shown.size() == before_cp + 1 and story.chapter == 0, "respawn keeps the chapter")
	_drain(story)
	Game.heat = 0.0
	Game.heat = 1.2
	TestLib.check(story.shown.count("c1.heat1") == 1, "respawn does not replay the chapter's lines")
	_drain(story)

	# chapter end card, next sector
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(story.end_card.get("head", "") == "CHAPTER 1 COMPLETE" and not story.cards_active(), "the chapter end card shows on the win screen")
	TestLib.check(story.shown.has("c1.end"), "end card logged")
	story.advance(1.0)
	TestLib.check(not story.cards_active(), "no epilogue after chapter 1")
	Game.state = &"play"
	Game.next_sector.emit()
	TestLib.check(story.chapter == 1 and story.banner_visible() and story.chapter_label() == "CHAPTER 2" and story.end_card.is_empty(), "next sector starts chapter 2 with its banner")
	TestLib.check(story.shown.has("c2.intro"), "chapter 2 intro queued")
	_drain(story)
	missions.got = 0
	story.advance(0.1)
	story.advance(0.1)
	TestLib.check(story.objective_text() == str(StoryData.CHAPTERS[1]["obj"]), "the objective line follows the chapter")

	# final chapter: epilogue
	for i in 6:
		Game.next_sector.emit()
	TestLib.check(story.chapter == 7 and story.chapter_data()["id"] == "meridian_gate", "chapter 8 is the Meridian Gate")
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(story.end_card.get("head", "") == "FINAL CHAPTER COMPLETE", "final end card reveals the twist")
	story.advance(Story.EPILOGUE_DELAY + 0.1)
	TestLib.check(story.cards_active() and story.card_kind == &"epilogue", "the epilogue follows the final sector")
	var cards_n := story.cards.size()
	_step(story, 0.5)
	story.advance_card()
	story.advance_card()
	TestLib.check(story.cards.size() == cards_n - 1, "epilogue cards are tap-skippable too")
	story.skip_cards()
	TestLib.check(story.epilogue_seen and not story.cards_active(), "the epilogue ends")
	Game.state = &"play"
	Game.next_sector.emit()
	TestLib.check(story.chapter == 8 and story.chapter_data()["id"] == "open_city" and story.chapter_label() == "FREE SECTOR 09", "after the story: the aftermath chapter")
	Game.next_sector.emit()
	TestLib.check(story.chapter_data()["id"] == "open_city", "the aftermath repeats")

	# a new run resets everything
	Game.new_game.emit()
	TestLib.check(story.chapter == 0 and story.cards_active() and story.shown == ["prologue"], "a new game resets chapter, one-shots and log")
	TestLib.check(story.trigger("first_beacon"), "one-shot lines can be said again in a new run")
	story.skip_cards()
	TestLib.check(story.queue.size() >= 1 and story.shown.has("c1.intro"), "the new run's chapter 1 intro is queued again")

	# cards swallow taps; the view lays out
	Game.new_game.emit()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	story._input(ev)
	TestLib.check(story.cards_active(), "an early tap does not skip")
	TestLib.check(story.view != null and story.view.get_parent() is CanvasLayer and (story.view.get_parent() as CanvasLayer).layer > 10, "the story view sits above the HUD layer")
	story.enabled = false
	TestLib.check(not story.say("ORACLE", "disabled", "x"), "a disabled story is silent")
	story.enabled = true

	# cleanup
	Game.state = &"play"
	story.skip_cards()
	story.queue.clear()
	story.skip_line()
	Game.player = old_player
	Game.missions = old_missions
	clone.queue_free()
	player.queue_free()
	missions.queue_free()
	story.queue_free()
	await TestLib.frames(host, 2)
	TestLib.check(Game.story == null, "Game.story is cleared when the story leaves the tree")
