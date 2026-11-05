extends RefCounted
## NPC DIALOGUE v2 on the real composed game (main.tscn): contextual barks (district, time of day, weather, heat, chapter, recent kills, vehicle theft), 2-3 line exchanges spoken
## in turn through Game.say, hint rumours (shards / side jobs), vendor greetings and the rotating vendor special, all through the Tr table (English, Spanish, Hindi).
## Run: tools/test.sh tests/test_npc_dialogue2.gd

const Dlg := preload("res://scripts/npc/npc_dialogue.gd")
const Data := preload("res://scripts/npc/npc_dialogue_data.gd")

var host: Node
var main: Node
var p: Player
var ig: InteriorGameplay
var prog: Progress
var _said: Array[String] = []


func _on_message(text: String, _s: float) -> void:
	_said.append(text)


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	prog = Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	var prev_heat: float = Game.heat
	var prev_weather: StringName = Weather.current
	var city := Game.world as City
	var dn: DayNight = city.day_night
	var prev_hour := dn.hour
	var prev_frozen := dn.frozen
	dn.frozen = true
	Game.message.connect(_on_message)

	_test_data()
	_test_context(dn)
	await _test_street(city)
	_test_hints()
	await _test_vendors()

	Game.message.disconnect(_on_message)
	Tr.set_lang("en")
	Game.heat = prev_heat
	Weather.current = prev_weather
	dn.hour = prev_hour
	dn.frozen = prev_frozen
	Dlg.reset_memory()


func _test_data() -> void:
	var spoken := Data.spoken()
	var longest := 0
	for s in spoken:
		longest = maxi(longest, s.length())
	TestLib.check(spoken.size() >= 60 and longest <= StoryData.LINE_MAX, "every spoken line fits the HUD limit (%d lines, longest %d of %d)" % [spoken.size(), longest, StoryData.LINE_MAX])
	var miss_es := 0
	var miss_hi := 0
	for s in spoken:
		miss_es += 0 if Tr.has_tr("es", s) and Tr.table("es")[s] != s else 1
		miss_hi += 0 if Tr.has_tr("hi", s) and Tr.table("hi")[s] != s else 1
	TestLib.check(miss_es == 0 and miss_hi == 0, "Spanish and Hindi cover every line (missing es %d, hi %d)" % [miss_es, miss_hi])
	var deva := true
	for s in Data.spoken():
		var t: String = Tr.table("hi")[s]
		var found := false
		for ci in t.length():
			var c := t.unicode_at(ci)
			if c >= 0x0900 and c <= 0x097F:
				found = true
				break
		deva = deva and found
	TestLib.check(deva, "Hindi lines are Devanagari")
	var rot_ok := true
	for t: StringName in Data.ROTATION:
		rot_ok = rot_ok and (Data.ROTATION[t] as Array).size() == 3 and InteriorData.has_vendor(t)
		for e: Dictionary in Data.ROTATION[t]:
			var nm := str((e["name"] as Array)[0])
			rot_ok = rot_ok and Tr.has_tr("es", nm) and Tr.has_tr("hi", nm)
	TestLib.check(rot_ok, "every vendor has three rotating specials with Spanish and Hindi names")
	Tr.set_lang("es")
	TestLib.check(Tr.t(spoken[0]) != spoken[0] and Tr.t("QUANTUM TELEPORT") == "QUANTUM TELEPORT", "Tr serves the Spanish line; quantum names stay plain")
	Tr.set_lang("en")
	var banned := ["energy is", "wave function", "photon", "uncertainty principle"]
	var clean := true
	for s in spoken:
		for b in banned:
			clean = clean and not s.to_lower().contains(b)
	TestLib.check(clean, "no physics lessons")


func _test_context(dn: DayNight) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	Dlg.reset_memory()
	Game.heat = 0.0
	Weather.current = &"clear"
	dn.hour = 23.0
	var ctx := Dlg.context(Vector3(-50.0, 0.0, -50.0))
	TestLib.check(ctx["district"] == "market" and ctx["night"] == true and not ctx["kills"] and not ctx["theft"], "context: district and night")
	TestLib.check(Dlg.context(Vector3(50.0, 0.0, 50.0))["district"] == "towers" and Dlg.context(Vector3(-50.0, 0.0, 50.0))["district"] == "slums" and Dlg.context(Vector3(50.0, 0.0, -50.0))["district"] == "foundry", "four districts by quadrant")
	var tg := Dlg.tags(ctx)
	TestLib.check(tg.has("night") and tg.has("d_market") and tg.has("calm") and not tg.has("rain"), "tags follow the context (%s)" % str(tg))
	dn.hour = 13.0
	Weather.current = &"storm"
	Game.heat = 2.0
	tg = Dlg.tags(Dlg.context(Vector3(50.0, 0.0, 50.0)))
	TestLib.check(tg.has("day") and tg.has("storm") and tg.has("heat") and tg.has("d_towers") and not tg.has("calm"), "weather, heat and day tags (%s)" % str(tg))

	# every context produces a bark with the citizen prefix, inside the limit and in the table
	var spoken := Data.spoken()
	var all_ok := true
	for district in [Vector3(-9, 0, -9), Vector3(9, 0, -9), Vector3(-9, 0, 9), Vector3(9, 0, 9)]:
		for w: StringName in [&"clear", &"rain", &"storm", &"fog"]:
			for ch in [0, 5, 10]:
				Weather.current = w
				var c := Dlg.context(district)
				c["chapter"] = ch
				var b := Dlg.bark(c, rng)
				all_ok = all_ok and b.begins_with(Data.CITIZEN) and spoken.has(b)
	TestLib.check(all_ok, "barks exist for every district / weather / chapter")
	# barks vary with district
	Weather.current = &"clear"
	Game.heat = 0.0
	var seen := {}
	for k in 60:
		seen[Dlg.bark(Dlg.context(Vector3(-9, 0, -9)), rng)] = true
		seen[Dlg.bark(Dlg.context(Vector3(9, 0, 9)), rng)] = true
	TestLib.check(seen.size() >= 8, "barks vary (%d different lines)" % seen.size())

	# hero actions: theft and kills steer the lines, then fade
	Dlg.note_theft()
	var theft_lines := {}
	for e: Array in Data.BARKS["theft"]:
		theft_lines[Data.CITIZEN + str(e[0])] = true
	var hit := 0
	for k in 40:
		hit += 1 if theft_lines.has(Dlg.bark(Dlg.context(Vector3.ZERO), rng)) else 0
	TestLib.check(Dlg.recent_theft() and hit >= 10, "after a vehicle theft the street talks about it (%d of 40)" % hit)
	var ex := Dlg.exchange(Dlg.context(Vector3.ZERO), rng)
	TestLib.check(ex.size() >= 2 and ex.size() <= 3 and ex[0].begins_with(Data.CITIZEN) and ex[1].begins_with(Data.REPLY), "an exchange is 2-3 lines, speakers alternate")
	Dlg.tick(Dlg.THEFT_WINDOW + 1.0)
	TestLib.check(not Dlg.recent_theft(), "the theft is forgotten after a while")
	Dlg.note_kill()
	var kt := Dlg.tags(Dlg.context(Vector3.ZERO))
	TestLib.check(Dlg.recent_kill() and kt[0] == "kills", "a recent kill comes first in the tags")
	Dlg.tick(Dlg.KILL_WINDOW + 1.0)
	TestLib.check(not Dlg.recent_kill(), "kills fade")
	# the vendor reacts too
	Dlg.note_theft()
	var v := ""
	var vend_theft := false
	for k in 30:
		v = Dlg.vendor_line(&"bar", Dlg.context(Vector3.ZERO), rng)
		vend_theft = vend_theft or v == Data.VENDOR + str(Data.VENDOR_LINES["theft"][0][0])
	TestLib.check(vend_theft, "a vendor mentions the stolen hover")
	Dlg.reset_memory()


func _test_street(city: City) -> void:
	var amb: Node3D = city.ambient
	var c: RefCounted = amb.crowd
	var n: RefCounted = amb.npc
	Game.state = &"play"
	amb.simulate = false
	Dlg.reset_memory()
	n.reset()
	for k in 40:
		c.step(0.1, p.global_position)
	n._promote(p.global_position)
	TestLib.check(n.actors.size() > 0, "citizens live around the hero in the real scene")
	var i: int = n.actors[0]
	p.global_position = c.person_position(i) + Vector3(1.2, 0.0, 0.0)
	Game.heat = 0.0
	n._promote(p.global_position)
	# COMMANDEERED is noticed
	var thefts: int = n.theft_seen
	Game.message.emit("VEHICLE COMMANDEERED", 1.4)
	TestLib.check(n.theft_seen == thefts + 1 and Dlg.recent_theft(), "the NpcLife hears a carjacking")
	# the kill counter feeds the memory (first read = baseline)
	Dlg.kills_seen = -1
	Dlg.poll_kills()
	var before := Dlg.recent_kill()
	prog.achievements.stats["kills"] = int(prog.achievements.stats.get("kills", 0)) + 1
	Dlg.poll_kills()
	TestLib.check(not before and Dlg.recent_kill(), "a kill counted by the hero is remembered")
	# an exchange is started and spoken line by line (wait on counters, not frames)
	n.reset()
	n._ext_until = 0.0
	Dlg.reset_memory()
	_said.clear()
	var tries := 0
	while n.exchanges == 0 and tries < 60:
		tries += 1
		n._promote(p.global_position)
		if n.actors.is_empty():
			break
		i = n.actors[0]
		p.global_position = c.person_position(i) + Vector3(1.2, 0.0, 0.0)
		n._promote(p.global_position)
		i = n.actors[0]
		c._flee[i] = 0.0
		c._cower[i] = 0.0
		n._talked.fill(-1000.0)
		n._talk_cd = 0.0
		n._ext_until = 0.0
		n.last_line = ""
		n._talk(p.global_position)
	TestLib.check(n.exchanges >= 1 and _said.size() >= 1 and _said[0].begins_with(Data.CITIZEN), "a citizen starts an exchange (%d tries): %s" % [tries, _said[0] if _said.size() > 0 else "-"])
	var first := _said.size()
	var guard := 0
	while n.lines_said < first + 1 and guard < 20:
		guard += 1
		n.step(n.EXCHANGE_GAP + 0.1, p.global_position)
	TestLib.check(_said.size() > first and _said[first].begins_with(Data.REPLY) and Data.spoken().has(_said[first]), "the reply follows through Game.say: %s" % (_said[first] if _said.size() > first else "-"))
	# nothing is queued after a pause
	Game.state = &"paused"
	n._queue.append("CIVIS: test")
	n._queue_t = 0.0
	var said_n := _said.size()
	n._speak_queue()
	TestLib.check(_said.size() == said_n and n._queue.is_empty(), "a paused game says nothing and drops the queue")
	Game.state = &"play"
	TestLib.check(n.stats().has("exchanges"), "stats report exchanges")
	amb.simulate = true


func _test_hints() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var keys := Dlg.hint_keys()
	var has_shard := false
	for k in keys:
		has_shard = has_shard or k.begins_with("shards_")
	TestLib.check(has_shard, "a fresh campaign hints at shards left (%s)" % str(keys))
	var h := Dlg.hint(rng)
	TestLib.check(h.begins_with(Data.CITIZEN + "Rumour:") and Data.spoken().has(h) and h.length() <= StoryData.LINE_MAX, "a hint rumour: %s" % h)
	# a side job done no longer hints at its district: finish every unlocked job and the side keys vanish
	for mid: StringName in SideMissions.DEFS:
		prog.side_done[mid] = 1
	var side_left := false
	for k in Dlg.hint_keys():
		side_left = side_left or k.begins_with("side_")
	TestLib.check(not side_left, "completed side jobs stop hinting")
	prog.side_done.clear()


func _test_vendors() -> void:
	prog.credits = 10000
	prog.reputation = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for type: StringName in Data.ROTATION:
		var names := {}
		for k in 3:
			ig.enter_count = k
			names[str(VendorLogic.special(type)["name"])] = true
		TestLib.check(names.size() == 3, "%s: three enters show three different specials" % str(type))
		var g := Dlg.vendor_line(type, {"heat": 0.0, "night": false, "weather": &"clear"}, rng)
		TestLib.check(Data.spoken().has(g) and g.begins_with(Data.VENDOR), "%s greets: %s" % [str(type), g])
	# real scene: walk into the bar, open the window, the greeting shows and the special can be bought
	var d := ig.doors_of(&"bar", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(2)
	ig.enter(d, true)
	await frames(20)
	var vs := ig.vendor_screen
	TestLib.check(vs.open(&"bar"), "the bar's trade window opens")
	await frames(2)
	TestLib.check(vs.greeting != "" and Data.spoken().has(vs.greeting) and vs.greeting.length() <= StoryData.LINE_MAX, "the vendor greets: %s" % vs.greeting)
	var rows := VendorLogic.rows(&"bar")
	var last: Dictionary = rows[rows.size() - 1]
	TestLib.check(last["id"] == VendorLogic.SPECIAL_ID and vs.rects.size() == rows.size() and int(last["price"]) > 0, "the rotating special is the last row, with its own BUY button")
	var pl := Game.player as Player
	pl.hp = 10.0
	var credits0 := prog.credits
	var res := vs.press_row(rows.size() - 1)
	TestLib.check(bool(res["ok"]) and pl.hp > 10.0 and prog.credits == credits0 - int(last["price"]), "buying the special heals and costs credits (hp %.0f)" % pl.hp)
	Tr.set_lang("es")
	TestLib.check(Tr.t(vs.greeting) != vs.greeting and Tr.t(str(last["name"])) != str(last["name"]), "greeting and special are translated")
	Tr.set_lang("en")
	vs.close()
	await frames(2)
	TestLib.check(Game.state == &"play", "closing resumes the game")
	prog.credits = 0
	var poor := VendorLogic.rows(&"bar")
	TestLib.check(poor[poor.size() - 1]["state"] == "poor", "a special you cannot afford shows as poor")
	ig.leave(true)
	await frames(5)
