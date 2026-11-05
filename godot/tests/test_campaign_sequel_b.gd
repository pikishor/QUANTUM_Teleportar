extends RefCounted
## Campaign sequel, data side part 2 (chapters 11 and 12): story and campaign data line up, the new step kinds (heist, convoy_intercept, rift_hold) are used in the chain, the
## two new set pieces splice in (the finale uses all verbs and three verb bosses), the second ending (cards + credits2 scene), tables for the endless sectors after chapter 12,
## Spanish coverage. Pure data plus one runner start, no scene.
## Run: tools/test.sh tests/test_campaign_sequel_b.gd

func run(_host: Node) -> void:
	var n := CampaignData.count()
	TestLib.check(n == 12 and StoryData.FINAL == 11 and StoryData.CHAPTERS.size() == 13 and CampaignData.CHAPTER_COUNT == 12, "twelve chapters, FINAL is index 11, then the aftermath")
	for i in [10, 11]:
		var ch: Dictionary = CampaignData.CAMPAIGN[i]
		var sc: Dictionary = StoryData.CHAPTERS[i]
		TestLib.check(str(sc["id"]) == str(ch["id"]) and CampaignData.index_of(str(ch["id"])) == i, "chapter %d: story and campaign ids match (%s)" % [i + 1, ch["id"]])
		TestLib.check(str(sc["sub"]).begins_with("SECTOR %02d" % (i + 1)) and str(sc["sub"]).ends_with(str(ch["place"])), "chapter %d: sector label names its place" % (i + 1))
		var steps: Array = ch["steps"]
		TestLib.check(steps.size() >= 3 and steps.size() <= 5 and CampaignSteps.validate_chapter(ch).is_empty(), "chapter %d: 3..5 steps that pass validation" % (i + 1))
		var kinds_ok := true
		for st: Dictionary in steps:
			kinds_ok = kinds_ok and CampaignData.STEP_KINDS.has(StringName(str(st["kind"]))) and str(st["obj"]).length() <= StoryData.OBJ_MAX and str(st["radio"]["t"]).length() <= StoryData.LINE_MAX
		TestLib.check(kinds_ok and CampaignData.DISTRICT_IDS.has(str(ch["district"])), "chapter %d: known kinds, short lines, real district" % (i + 1))
		TestLib.check(str(sc["title"]).length() <= StoryData.TITLE_MAX and (sc["intro"] as Array).size() >= 2 and (sc["cores"] as Dictionary).size() == 3, "chapter %d: title fits, intro and three core lines" % (i + 1))
		TestLib.check(StoryData.SPEAKERS.has(str(sc["heat1"]["s"])) and StoryData.SPEAKERS.has(str(sc["heat3"]["s"])), "chapter %d has heat lines" % (i + 1))
		TestLib.check(KNOWN(str(ch["cutscenes"]["chapter"])) and str(ch["cutscenes"]["chapter"]) != "", "chapter %d has a known chapter card" % (i + 1))

	# chapter 11 uses the three new mission kinds, chapter 12 is the boss finale
	var k11: Array[String] = []
	for st: Dictionary in CampaignData.CAMPAIGN[10]["steps"]:
		k11.append(str(st["kind"]))
	TestLib.check(k11.has("heist") and k11.has("convoy_intercept") and k11.has("rift_hold"), "chapter 11 plays heist, convoy intercept and rift hold (%s)" % str(k11))
	var heist: Dictionary = CampaignData.CAMPAIGN[10]["steps"][1]
	TestLib.check(InteriorData.MISSION_TYPES.has(StringName(str(heist["interior"]))), "the heist goes through a mission interior")
	TestLib.check(str(CampaignData.CAMPAIGN[10]["cutscenes"]["boss"]) == "" and not CampaignData.CAMPAIGN[10]["cutscenes"].has("ending"), "chapter 11 has no boss cutscene and no ending")
	var boss12: Array[String] = []
	for st: Dictionary in CampaignData.CAMPAIGN[11]["steps"]:
		if str(st.get("target", "")) == "boss":
			boss12.append(str(st["enemy"]))
			TestLib.check(EnemyTypes.TYPES.has(StringName(str(st["enemy"]))), "boss step enemy '%s' is a real type" % st["enemy"])
	TestLib.check(boss12 == ["bulwark"] and str(CampaignData.CAMPAIGN[11]["cutscenes"]["boss"]) == "boss_in", "chapter 12 fights the Bulwark Prime behind a boss_in scene")
	TestLib.check(str(CampaignData.CAMPAIGN[11]["cutscenes"]["ending"]) == "credits2" and CampaignData.KNOWN_CUTSCENES.has("credits2"), "chapter 12 ends with the second credits scene")
	TestLib.check(str(StoryData.CHAPTERS[10]["end"]["head"]) == "CHAPTER 11 COMPLETE" and str(StoryData.CHAPTERS[11]["end"]["head"]) == "FINAL CHAPTER COMPLETE", "end cards: chapter 11, then the final one on chapter 12")
	var places := {}
	for ch: Dictionary in CampaignData.CAMPAIGN:
		places[ch["place"]] = true
	TestLib.check(places.size() == n, "every chapter has its own place")

	# set pieces: the optional choir surge and the finale with all verb fights
	TestLib.check(SetPieces.id_for_chapter(10) == &"choir_surge" and SetPieces.id_for_chapter(11) == &"final_aperture" and SetPieces.is_optional(&"choir_surge") and not SetPieces.is_optional(&"final_aperture"), "choir surge (optional) on chapter 11, the last gate (finale) on chapter 12")
	var fin := SetPieces.phase_steps(&"final_aperture")
	var fkinds: Array[String] = []
	var fenemies: Array[String] = []
	var all_hazards := true
	for s in fin:
		fkinds.append(str(s["kind"]))
		all_hazards = all_hazards and s.get("hazard") is Dictionary
		if s.has("enemy") and str(s["kind"]) == "kill_target":
			fenemies.append(str(s["enemy"]))
	TestLib.check(fkinds[0] == "rift_hold" and fenemies == ["hound", "phasewright", "skimmer"] and all_hazards, "the last gate: a rift hold, then the Hound (decoy + COLLAPSE), the Phasewright (jump) and the Skimmer (%s)" % str(fenemies))
	for ci in [10, 11]:
		var base := CampaignSteps.normalize_chapter(CampaignData.CAMPAIGN[ci], ci)
		var sp := SetPieces.splice(base, ci)
		var added := sp.size() - base.size()
		TestLib.check(added >= 3 and SetPieces.splice(sp, ci).size() == sp.size(), "chapter %d: set piece phases spliced in once (%d)" % [ci + 1, added])
		TestLib.check(str(sp[sp.size() - 1]["kind"]) == str(base[base.size() - 1]["kind"]), "chapter %d keeps its closing step last" % (ci + 1))
	var r := CampaignRunner.new()
	r.enabled = false
	TestLib.check(r.start_chapter(11, 0, true) and r.steps.size() >= 8, "the runner starts chapter 12 with its set piece (%d steps)" % r.steps.size())
	var ok_n := true
	for s in r.steps:
		ok_n = ok_n and CampaignSteps.kind_of(s) != &""
	TestLib.check(ok_n, "every spliced step has a runner kind")
	TestLib.check(r.start_chapter(10, 0, true) and r.steps.size() >= 8, "the runner starts chapter 11 with its set piece")
	r.free()

	# endings: cards and credits2
	var end_ok := CampaignData.ENDING_2.size() == 3
	for c: Dictionary in CampaignData.ENDING_2:
		end_ok = end_ok and str(c["head"]).length() <= 30 and str(c["text"]).length() > 20 and str(c["text"]).length() <= StoryData.CARD_MAX
	TestLib.check(end_ok, "second ending cards fit")
	TestLib.check(CampaignData.ending_cards_for(9) == CampaignData.ENDING and CampaignData.ending_cards_for(11) == CampaignData.ENDING_2 and CampaignData.ending_cards_for(10).is_empty() and CampaignData.ending_cards_for(12).is_empty(), "ending cards by chapter: 10 first ending, 12 second, none elsewhere")
	var cr_ok := CampaignData.CREDITS_2.size() >= 4
	for blk: Dictionary in CampaignData.CREDITS_2:
		cr_ok = cr_ok and str(blk["head"]).length() <= 30 and (blk["lines"] as Array).size() >= 1
		for ln: Variant in blk["lines"]:
			cr_ok = cr_ok and str(ln).length() <= CampaignData.CREDIT_LINE_MAX
	TestLib.check(cr_ok, "second credits blocks fit")
	var plan := CinePlan.credits_scene({"hero": Vector3(-30, 0, 4), "face": Vector3.RIGHT}, &"credits2")
	TestLib.check(plan.id == &"credits2" and plan.credits == CampaignData.CREDITS_2 and plan.subs == CampaignData.CREDITS_2_SUBS and is_equal_approx(plan.duration, CampaignData.CREDITS_BLOCK_SECONDS * CampaignData.CREDITS_2.size()), "the credits2 plan uses the second blocks and subtitles")
	var subs_ok := true
	for l: Dictionary in CampaignData.CREDITS_2_SUBS:
		subs_ok = subs_ok and float(l["t1"]) > float(l["t0"]) and float(l["t1"]) <= plan.duration and StoryData.SPEAKERS.has(str(l["s"])) and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(subs_ok, "second credits subtitles sit inside the scene")
	TestLib.check(CinePlan.credits_scene({"hero": Vector3.ZERO, "face": Vector3.RIGHT}).id == &"credits", "the default scene is still the first credits")

	# tables after chapter 12
	var d11 := Progress.difficulty(10)
	var d12 := Progress.difficulty(11)
	var d13 := Progress.difficulty(12)
	TestLib.check(float(d12["hp"]) > float(d11["hp"]) and float(d13["hp"]) > float(d12["hp"]) and float(d13["reward"]) > float(d12["reward"]), "enemy health and pay keep rising through chapters 11 and 12")
	TestLib.check(float(Progress.difficulty(40)["hp"]) == float(d13["hp"]) and float(Progress.difficulty(40)["reward"]) == float(d13["reward"]), "the curve flattens after the sequel")
	TestLib.check(Economy.sector_at(30.0) == 12 and Economy.sector_at(100.0) == 12, "the economy model plays to the last sector")
	TestLib.check(ContractTypes.WEIGHTS.size() == n + 1 and ContractTypes.weights(10) != ContractTypes.weights(11) and ContractTypes.weights(11) != ContractTypes.weights(12), "contract weights have a row per chapter plus the endless row")
	var all_kinds := true
	for c in [10, 11]:
		for k: StringName in ContractTypes.KINDS:
			all_kinds = all_kinds and float(ContractTypes.weights(c)[k]) >= 1.0
	TestLib.check(all_kinds, "every contract kind stays possible in chapters 11 and 12")
	TestLib.check(EnemyTypes.specialist_share(9) < EnemyTypes.specialist_share(10) and EnemyTypes.specialist_share(10) < EnemyTypes.specialist_share(11) and EnemyTypes.specialist_share(11) < EnemyTypes.specialist_share(12) and EnemyTypes.specialist_share(12) == EnemyTypes.specialist_share(60) and EnemyTypes.specialist_share(12) <= 0.85, "specialist share rises through chapter 12 and stays under 85 %")
	TestLib.check(EnemyTypes.PICK_BIAS.size() == EnemyTypes.SPECIALIST_SHARE.size() and EnemyTypes.SPECIALIST_SHARE.size() == n + 1, "pick bias and share have a row per chapter plus the endless row")
	var endless_ok := true
	for s in range(n, n + 9):
		var st := CampaignData.steps(s)
		endless_ok = endless_ok and CampaignData.is_endless(s) and st.size() >= CampaignData.MIN_STEPS and st.size() <= CampaignData.MAX_STEPS
		for e: Dictionary in st:
			endless_ok = endless_ok and CampaignData.STEP_KINDS.has(StringName(str(e["kind"])))
	TestLib.check(endless_ok and CampaignData.ENDLESS_LABEL % (n + 1) == "FREE SECTOR 13" and CampaignRunner.chapter_count() == 12, "endless sectors continue as FREE SECTOR 13 and on")

	# lines: unique, speakers, Spanish
	var seen := {}
	var lines_ok := true
	var missing: Array = []
	for ch: Dictionary in CampaignData.CAMPAIGN:
		for st: Dictionary in ch["steps"]:
			var t := str(st["radio"]["t"])
			lines_ok = lines_ok and not seen.has(t) and StoryData.SPEAKERS.has(str(st["radio"]["s"]))
			seen[t] = true
	TestLib.check(lines_ok, "every step line is unique and has a speaker")
	for i in [10, 11]:
		var sc: Dictionary = StoryData.CHAPTERS[i]
		var all: Array[String] = [str(sc["title"]), str(sc["sub"]), str(sc["obj"]), str(sc["end"]["head"]), str(sc["end"]["text"])]
		for l: Dictionary in sc["intro"]:
			all.append(str(l["t"]))
		for l: Dictionary in (sc["cores"] as Dictionary).values():
			all.append(str(l["t"]))
		for st: Dictionary in CampaignData.CAMPAIGN[i]["steps"]:
			all.append(str(st["obj"]))
			all.append(str(st["radio"]["t"]))
		for c: Dictionary in CampaignData.ENDING_2 if i == 11 else []:
			all.append(str(c["text"]))
		for s: String in all:
			if not Tr.has_tr("es", s):
				missing.append(s)
	TestLib.check(missing.is_empty(), "Spanish covers chapters 11 and 12 (missing %d: %s)" % [missing.size(), str(missing.slice(0, 2))])


func KNOWN(id: String) -> bool:
	return CampaignData.KNOWN_CUTSCENES.has(id)
