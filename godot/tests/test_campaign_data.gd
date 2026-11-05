extends RefCounted
## Campaign data (scripts/story/campaign_data.gd): eight well formed chapters that line up with StoryData.CHAPTERS, 3..5 known steps each, lengths within the
## story limits, unique ids, cutscene ids known and boss cutscenes only where there is a boss step, ending / credits fit, endless sectors follow the last chapter.
## Run: tools/test.sh tests/test_campaign_data.gd

func run(_host: Node) -> void:
	var Districts := load("res://scripts/world/city_districts.gd")
	var n := CampaignData.count()
	TestLib.check(n == 12 and CampaignData.CHAPTER_COUNT == 12, "the campaign has 12 chapters (8 + the sequel arc)")
	TestLib.check(StoryData.FINAL == n - 1 and StoryData.CHAPTERS.size() == n + 1, "story data: 12 story chapters then the aftermath, FINAL points at the last")

	var ids := {}
	var titles := {}
	var places := {}
	var districts := {}
	var texts := {}
	var dup_text := 0
	var order_ok := true
	var shape_ok := true
	var kinds_seen := {}
	var step_ok := true
	var obj_ok := true
	var line_ok := true
	var cut_ok := true
	var boss_ok := true
	var interior_ok := true
	var target_ok := true
	var dist_ok := true
	var interior_types: Array = InteriorData.MISSION_TYPES
	for i in n:
		var ch: Dictionary = CampaignData.CAMPAIGN[i]
		for key: String in ["id", "district", "place", "steps", "cutscenes"]:
			shape_ok = shape_ok and ch.has(key)
		if not shape_ok:
			continue
		ids[ch["id"]] = true
		places[ch["place"]] = true
		districts[ch["district"]] = true
		titles[StoryData.CHAPTERS[i]["title"]] = true
		order_ok = order_ok and str(StoryData.CHAPTERS[i]["id"]) == str(ch["id"]) and CampaignData.index_of(str(ch["id"])) == i
		order_ok = order_ok and str(StoryData.CHAPTERS[i]["sub"]).ends_with(str(ch["place"])) and str(StoryData.CHAPTERS[i]["sub"]).begins_with("SECTOR %02d" % (i + 1))
		dist_ok = dist_ok and CampaignData.DISTRICT_IDS.has(str(ch["district"])) and Districts.IDS.has(StringName(str(ch["district"])))
		var steps: Array = ch["steps"]
		step_ok = step_ok and steps.size() >= CampaignData.MIN_STEPS and steps.size() <= CampaignData.MAX_STEPS
		var has_boss := false
		for st: Dictionary in steps:
			var kind := StringName(str(st.get("kind", "")))
			kinds_seen[kind] = true
			step_ok = step_ok and CampaignData.STEP_KINDS.has(kind)
			var obj := str(st.get("obj", ""))
			obj_ok = obj_ok and obj.length() >= 8 and obj.length() <= StoryData.OBJ_MAX
			var r: Dictionary = st.get("radio", {})
			var t := str(r.get("t", ""))
			line_ok = line_ok and StoryData.SPEAKERS.has(str(r.get("s", ""))) and t.length() >= 8 and t.length() <= StoryData.LINE_MAX
			if texts.has(t):
				dup_text += 1
			texts[t] = true
			if kind == &"infiltrate":
				interior_ok = interior_ok and interior_types.has(StringName(str(st.get("interior", ""))))
			elif kind == &"heist":
				interior_ok = interior_ok and interior_types.has(StringName(str(st.get("interior", ""))))
			else:
				interior_ok = interior_ok and not st.has("interior")
			if kind == &"assassinate":
				var tg := str(st.get("target", ""))
				target_ok = target_ok and (tg == "specialist" or tg == "boss")
				has_boss = has_boss or tg == "boss"
			else:
				target_ok = target_ok and not st.has("target")
		var cs: Dictionary = ch["cutscenes"]
		for key: String in ["intro", "chapter", "boss"]:
			cut_ok = cut_ok and cs.has(key) and CampaignData.KNOWN_CUTSCENES.has(str(cs[key]))
		for k: Variant in cs:
			cut_ok = cut_ok and CampaignData.KNOWN_CUTSCENES.has(str(cs[k]))
		cut_ok = cut_ok and str(cs.get("chapter", "")) != ""
		boss_ok = boss_ok and (str(cs.get("boss", "")) != "") == has_boss
	TestLib.check(shape_ok, "every chapter has id, district, place, steps and cutscenes")
	TestLib.check(ids.size() == n and titles.size() == n and places.size() == n, "chapter ids, titles and places are unique")
	TestLib.check(order_ok, "campaign chapters line up with StoryData.CHAPTERS (id, sector number, place)")
	TestLib.check(dist_ok and districts.size() == 4, "every chapter sits in a real district and all four districts are used")
	TestLib.check(step_ok, "every chapter has %d..%d steps with known kinds" % [CampaignData.MIN_STEPS, CampaignData.MAX_STEPS])
	TestLib.check(kinds_seen.size() == CampaignData.STEP_KINDS.size(), "all %d step kinds appear in the campaign (%d)" % [CampaignData.STEP_KINDS.size(), kinds_seen.size()])
	TestLib.check(obj_ok, "objective lines are 8..%d characters" % StoryData.OBJ_MAX)
	TestLib.check(line_ok, "step radio lines have a known speaker and fit %d characters" % StoryData.LINE_MAX)
	TestLib.check(interior_ok, "infiltrate and heist steps name a mission interior type, no other step does")
	TestLib.check(target_ok, "assassinate steps name specialist or boss, no other step does")
	TestLib.check(cut_ok, "cutscene ids are known and every chapter has a chapter card")
	TestLib.check(boss_ok, "a boss cutscene exists exactly where a boss step does")
	var boss_chapters := 0
	for ch: Dictionary in CampaignData.CAMPAIGN:
		if str(ch["cutscenes"]["boss"]) != "":
			boss_chapters += 1
	TestLib.check(boss_chapters >= 2, "at least two Overseer fights (%d)" % boss_chapters)
	TestLib.check(str(CampaignData.CAMPAIGN[0]["cutscenes"]["intro"]) == "intro", "chapter 1 starts with the intro cutscene")

	# all lines unique, including the story data lines
	for l: Dictionary in CampaignData.CREDITS_SUBS + CampaignData.CREDITS_2_SUBS:
		var t := str(l["t"])
		if texts.has(t):
			dup_text += 1
		texts[t] = true
	for ch: Dictionary in StoryData.CHAPTERS:
		for l: Dictionary in ch["intro"]:
			if texts.has(l["t"]):
				dup_text += 1
			texts[l["t"]] = true
	TestLib.check(dup_text == 0, "no radio line is written twice across the campaign and the story data")
	TestLib.check(CampaignData.all_lines().size() == texts.size() - _story_intro_count() and CampaignData.all_lines().size() > 30, "all_lines covers every step and credits line")

	# every story chapter's own text fits (the new chapters in story_data.gd)
	var story_ok := true
	for ch: Dictionary in StoryData.CHAPTERS:
		story_ok = story_ok and str(ch["title"]).length() <= StoryData.TITLE_MAX and str(ch["obj"]).length() <= StoryData.OBJ_MAX and str(ch["sub"]).length() <= 40
		story_ok = story_ok and str(ch["end"]["text"]).length() <= 220 and str(ch["end"]["head"]).length() <= 30
		var all: Array = []
		all.append_array(ch["intro"])
		all.append(ch["heat1"])
		all.append(ch["heat3"])
		for k: Variant in ch["cores"]:
			all.append(ch["cores"][k])
		for l: Dictionary in all:
			story_ok = story_ok and StoryData.SPEAKERS.has(str(l["s"])) and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(story_ok, "story chapters keep within title, objective and line limits")
	TestLib.check(StoryData.CONTRACT_CHAPTER.size() == StoryData.CHAPTERS.size(), "one contract line per chapter")

	# ending and credits
	var end_ok := CampaignData.ENDING.size() >= 2
	for c: Dictionary in CampaignData.ENDING:
		end_ok = end_ok and str(c["head"]).length() <= 30 and str(c["text"]).length() > 20 and str(c["text"]).length() <= StoryData.CARD_MAX
	TestLib.check(end_ok, "ending cards fit (head 30, text %d)" % StoryData.CARD_MAX)
	TestLib.check(str(CampaignData.CAMPAIGN[n - 1]["cutscenes"].get("ending", "")) == "credits2" and str(CampaignData.CAMPAIGN[9]["cutscenes"].get("ending", "")) == "credits" and not CampaignData.CAMPAIGN[7]["cutscenes"].has("ending") and not CampaignData.CAMPAIGN[10]["cutscenes"].has("ending"), "chapter 10 ends with the credits, the final chapter (12) with the second credits scene")
	var cr_ok := CampaignData.CREDITS.size() >= 4
	for blk: Dictionary in CampaignData.CREDITS:
		cr_ok = cr_ok and str(blk["head"]).length() <= 30 and (blk["lines"] as Array).size() >= 1
		for ln: Variant in blk["lines"]:
			cr_ok = cr_ok and str(ln).length() <= CampaignData.CREDIT_LINE_MAX
	TestLib.check(cr_ok, "credits blocks fit (lines at most %d characters)" % CampaignData.CREDIT_LINE_MAX)
	var duration := CampaignData.CREDITS_BLOCK_SECONDS * CampaignData.CREDITS.size()
	var subs_ok := true
	for l: Dictionary in CampaignData.CREDITS_SUBS:
		subs_ok = subs_ok and float(l["t0"]) >= 0.0 and float(l["t1"]) > float(l["t0"]) and float(l["t1"]) <= duration
	TestLib.check(subs_ok, "credits subtitles sit inside the %.1f second scene" % duration)

	# endless sectors
	TestLib.check(not CampaignData.is_endless(n - 1) and CampaignData.is_endless(n) and CampaignData.chapter(n).is_empty(), "sector %d is the first endless sector" % (n + 1))
	var endless_ok := true
	for s in range(n, n + 12):
		var st := CampaignData.steps(s)
		endless_ok = endless_ok and st.size() >= CampaignData.MIN_STEPS and st.size() <= CampaignData.MAX_STEPS
		for e: Dictionary in st:
			endless_ok = endless_ok and CampaignData.STEP_KINDS.has(StringName(str(e["kind"]))) and str(e["obj"]).length() <= StoryData.OBJ_MAX
	TestLib.check(endless_ok, "endless sectors give 3..5 known steps")
	TestLib.check(str(StoryData.CHAPTERS[StoryData.FINAL + 1]["id"]) == "open_city" and CampaignData.ENDLESS_LABEL % 13 == "FREE SECTOR 13", "the aftermath chapter continues as endless sectors")


func _story_intro_count() -> int:
	var c := 0
	for ch: Dictionary in StoryData.CHAPTERS:
		c += (ch["intro"] as Array).size()
	return c
