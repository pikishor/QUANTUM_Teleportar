extends RefCounted
## Campaign sequel, data side (chapters 9 and 10 of scripts/story/campaign_data.gd and story_data.gd): the two new chapters line up with the story data, use existing step kinds,
## chapter 10 has the verb bosses and the credits ending (chapter 8 no longer ends the game), the chapter select grows to ten, the difficulty and economy tables reach them and the
## old saves still load. Pure data, no scene.
## Run: tools/test.sh tests/test_campaign_sequel_a.gd

func run(_host: Node) -> void:
	var n := CampaignData.count()
	TestLib.check(n == 12 and StoryData.FINAL == 11 and StoryData.CHAPTERS.size() == 13, "twelve story chapters, FINAL is index 11, then the aftermath")
	for i in [8, 9]:
		var ch: Dictionary = CampaignData.CAMPAIGN[i]
		var sc: Dictionary = StoryData.CHAPTERS[i]
		TestLib.check(str(sc["id"]) == str(ch["id"]) and CampaignData.index_of(str(ch["id"])) == i, "chapter %d: story and campaign ids match (%s)" % [i + 1, ch["id"]])
		TestLib.check(str(sc["sub"]).begins_with("SECTOR %02d" % (i + 1)) and str(sc["sub"]).ends_with(str(ch["place"])), "chapter %d: sector label names its place (%s)" % [i + 1, ch["place"]])
		var steps: Array = ch["steps"]
		TestLib.check(steps.size() >= 3 and steps.size() <= 5, "chapter %d has 3..5 steps (%d)" % [i + 1, steps.size()])
		var valid := true
		for st: Dictionary in steps:
			valid = valid and CampaignData.STEP_KINDS.has(StringName(str(st["kind"]))) and CampaignSteps.validate_step(st) == ""
		TestLib.check(valid and CampaignSteps.validate_chapter(ch).is_empty(), "chapter %d steps pass the runner's validation" % (i + 1))
		TestLib.check(CampaignData.DISTRICT_IDS.has(str(ch["district"])), "chapter %d sits in a real district (%s)" % [i + 1, ch["district"]])
		TestLib.check(str(sc["title"]).length() <= StoryData.TITLE_MAX and (sc["intro"] as Array).size() >= 2 and (sc["cores"] as Dictionary).size() == 3, "chapter %d: title fits, intro and three core lines" % (i + 1))
		TestLib.check(StoryData.SPEAKERS.has(str(sc["heat1"]["s"])) and StoryData.SPEAKERS.has(str(sc["heat3"]["s"])), "chapter %d has heat lines" % (i + 1))
	# unique places and ids against the earlier chapters
	var places := {}
	var ids := {}
	for ch: Dictionary in CampaignData.CAMPAIGN:
		places[ch["place"]] = true
		ids[ch["id"]] = true
	TestLib.check(places.size() == n and ids.size() == n, "the sequel adds new places and ids")

	# chapter 10: verb bosses, boss cutscene, credits
	var verb_bosses: Array[String] = []
	for st: Dictionary in CampaignData.CAMPAIGN[9]["steps"]:
		if str(st.get("target", "")) == "boss":
			verb_bosses.append(str(st.get("enemy", "")))
			var norm := CampaignSteps.normalize_step(st, 0, 9)
			TestLib.check(norm["enemy"] == StringName(str(st["enemy"])) and EnemyTypes.TYPES.has(norm["enemy"]), "boss step enemy '%s' is a real enemy type" % st["enemy"])
	TestLib.check(verb_bosses == ["hound", "phasewright"], "chapter 10 fights two verb bosses (%s)" % str(verb_bosses))
	TestLib.check(str(CampaignData.CAMPAIGN[9]["cutscenes"]["boss"]) == "boss_in" and str(CampaignData.CAMPAIGN[9]["cutscenes"]["ending"]) == "credits", "chapter 10 plays boss_in and ends with the credits")
	TestLib.check(not CampaignData.CAMPAIGN[7]["cutscenes"].has("ending") and str(CampaignData.CAMPAIGN[8]["cutscenes"]["boss"]) == "", "chapter 8 no longer ends the game, chapter 9 has no boss cutscene")
	TestLib.check(str(StoryData.CHAPTERS[7]["end"]["head"]) == "CHAPTER 8 COMPLETE" and str(StoryData.CHAPTERS[9]["end"]["head"]) == "CHAPTER 10 COMPLETE" and str(StoryData.CHAPTERS[11]["end"]["head"]) == "FINAL CHAPTER COMPLETE", "the final end card moved on to chapter 12")
	for cs: String in [str(CampaignData.CAMPAIGN[8]["cutscenes"]["chapter"]), str(CampaignData.CAMPAIGN[9]["cutscenes"]["chapter"])]:
		TestLib.check(CampaignData.KNOWN_CUTSCENES.has(cs) and cs != "", "chapter card cutscene '%s' is known" % cs)

	# the chapter select lists all ten, an old save keeps its unlocked count
	TestLib.check(CampaignRunner.chapter_count() == 12 and CampaignRunner.chapter_title(9) == "THE LAST APERTURE" and CampaignRunner.chapter_title(8) == "THE ECHO TIDE", "the chapter select lists twelve chapters with their titles")
	TestLib.check(StoryData.CONTRACT_CHAPTER.size() == StoryData.CHAPTERS.size(), "one contract line per chapter, sequel included")

	# difficulty and economy tables reach chapters 9 and 10
	var d8 := Progress.difficulty(7)
	var d9 := Progress.difficulty(8)
	var d10 := Progress.difficulty(9)
	var d11 := Progress.difficulty(10)
	TestLib.check(float(d9["hp"]) > float(d8["hp"]) and float(d10["hp"]) > float(d9["hp"]) and float(d10["reward"]) > float(d9["reward"]) and float(d9["reward"]) > float(d8["reward"]), "enemy health and pay keep rising through chapters 9 and 10")
	TestLib.check(float(d11["hp"]) >= float(d10["hp"]) and float(Progress.difficulty(40)["hp"]) == float(Progress.difficulty(12)["hp"]), "the curve flattens after chapter 12")
	TestLib.check(Economy.sector_at(10.0) == 9 and Economy.sector_at(30.0) == 12 and Economy.hourly_income(9.5)["net"] != null, "the economy model plays to the sequel sectors")
	TestLib.check(ContractTypes.WEIGHTS.size() == 13 and ContractTypes.weights(8) != ContractTypes.weights(9) and ContractTypes.weights(9) != ContractTypes.weights(10), "contract weights have rows for chapters 9 and 10")
	var all_kinds := true
	for k: StringName in ContractTypes.KINDS:
		all_kinds = all_kinds and float(ContractTypes.weights(8)[k]) >= 1.0 and float(ContractTypes.weights(9)[k]) >= 1.0
	TestLib.check(all_kinds, "every contract kind stays possible in the sequel")
	TestLib.check(EnemyTypes.specialist_share(8) <= EnemyTypes.specialist_share(9) and EnemyTypes.specialist_share(9) < EnemyTypes.specialist_share(10), "specialist share rises through the sequel (chapters 9-11)")

	# radio lines: speakers and length
	var lines_ok := true
	var seen := {}
	for ch: Dictionary in CampaignData.CAMPAIGN:
		for st: Dictionary in ch["steps"]:
			var t := str(st["radio"]["t"])
			lines_ok = lines_ok and not seen.has(t) and t.length() <= StoryData.LINE_MAX and StoryData.SPEAKERS.has(str(st["radio"]["s"])) and str(st["obj"]).length() <= StoryData.OBJ_MAX
			seen[t] = true
	TestLib.check(lines_ok, "every step line is unique, has a speaker and fits")
