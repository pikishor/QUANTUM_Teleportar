extends RefCounted
## Campaign data wired into the runner (scripts/story/campaign_data.gd read by scripts/missions/campaign_runner.gd): every chapter of CampaignData normalises into exactly its steps with the
## canonical kinds, keys (obj, radio {s, t}, interior, target) are understood, boss steps become Overseer hunts, the runner's own chapter lookup is the campaign data, the boss chapters of
## the contracts cover the three boss chapters, and the endless aftermath has no scripted steps. The full playthrough is tests/bot_campaign.gd.
## Run: tools/test.sh tests/test_campaign_wiring.gd

func run(_host: Node) -> void:
	var camp := CampaignRunner.new()
	var n := CampaignData.count()
	TestLib.check(CampaignRunner._campaign_data().size() == n, "the runner reads all %d chapters from CampaignData" % n)
	TestLib.check(CampaignRunner.chapter_count() == StoryData.FINAL + 1 and CampaignRunner.chapter_count() == n, "the chapter select lists every campaign chapter")
	var all_ok := true
	var kinds := {}
	var bosses := []
	var verb_bosses := []
	var radio_ok := true
	var interior_ok := true
	for i in n:
		var ch := camp.chapter_data(i)
		var raw: Array = CampaignData.steps(i)
		var list := CampaignSteps.normalize_chapter(ch, i)
		all_ok = all_ok and list.size() == raw.size() and CampaignSteps.validate_chapter(ch).is_empty() and camp.has_steps(i)
		for j in list.size():
			var st := list[j]
			var src: Dictionary = raw[j]
			kinds[st["kind"]] = true
			all_ok = all_ok and CampaignRunner.StepKinds.has(st["kind"]) and str(st["text"]) == str(src["obj"])
			radio_ok = radio_ok and src["radio"] is Dictionary and src["radio"].has("s") and src["radio"].has("t")
			if st["kind"] == &"enter_interior":
				interior_ok = interior_ok and st["interior"] == StringName(str(src["interior"])) and InteriorData.MISSION_TYPES.has(st["interior"])
			if st["kind"] == &"kill_target" and str(src.get("target", "")) == "boss":
				if src.has("enemy"):
					verb_bosses.append(i)   # wave 34 verb bosses: their own enemy type, not the contracts' Overseer
					all_ok = all_ok and st["enemy"] == StringName(str(src["enemy"]))
				else:
					bosses.append(i)
					all_ok = all_ok and st["enemy"] == &"overseer"
			if st["kind"] == &"kill_target" and str(src.get("target", "")) == "specialist":
				all_ok = all_ok and st["enemy"] == &""
	TestLib.check(all_ok, "every campaign step normalises (same count, canonical kind, objective text from obj, boss = overseer, specialist = picked per chapter)")
	TestLib.check(radio_ok and interior_ok, "radio lines {s, t} and interior types of the data fit the runner")
	TestLib.check(kinds.size() == 8, "the campaign uses 8 step kinds (%s)" % str(kinds.keys()))
	TestLib.check(bosses == [2, 5, 7], "Overseer boss steps are still in chapters 3, 6 and 8 (%s)" % str(bosses))
	TestLib.check(verb_bosses == [1, 3, 4, 6, 6, 9, 9], "verb boss steps (own enemy type) are in chapters 2, 4, 5, 7 and the sequel finale 10 (%s)" % str(verb_bosses))
	for b: int in bosses:
		TestLib.check(ContractTypes.is_boss_chapter(b), "chapter %d is a boss chapter of the contracts" % (b + 1))
	for b: int in bosses + verb_bosses:
		TestLib.check(str(CampaignData.chapter(b)["cutscenes"]["boss"]) == "boss_in", "chapter %d plays the boss_in cutscene" % (b + 1))
	TestLib.check(not camp.has_steps(n) and camp.chapter_data(n).is_empty() and CampaignData.is_endless(n), "the aftermath chapter has no scripted steps (plain core hunt)")
	TestLib.check(not camp.start_chapter(n), "the runner refuses to start the aftermath")
	camp.free()
