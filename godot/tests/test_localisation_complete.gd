extends RefCounted
## Localisation completion (waves 61-77): Spanish and Hindi for weapons, gear, skills, safehouses, factions / wanted, side missions, heists, photo mode, boss rush, controls
## and the HUD / mission lines of those waves. (1) "missing strings" report: every English string collected from the live data tables and the screens' own labels is looked up in
## Spanish and Hindi; the untranslated keys are printed and the test fails above a small threshold. (2) Real scene (main.tscn): the buttons of every screen, drawn at text scale 1.5
## in Spanish and Hindi at 844x390 and 1280x720, fit their button (autoscale) and stay on screen. (3) Hindi stays Devanagari, quantum names stay plain.
## Run: tools/test.sh tests/test_localisation_complete.gd

const LANG_TESTED: Array[String] = ["es", "hi"]
const MISSING_PCT := 2.0                  ## untranslated keys allowed per language, percent of the collected strings (and at least MISSING_MIN)
const MISSING_MIN := 4
const LABEL_MISSING_PCT := 4.0            ## screen button labels that stay English (names shared by the languages are whitelisted below)
const DATA_KEYS: Array[String] = ["name", "title", "brief", "note", "desc", "tag", "earn_text", "label", "stages"]
const KEEP_ENGLISH: Array[String] = ["ARENA", "DEMO", "POST", "SFX", "CINE", "ON", "OFF", "NORMAL", "FRAG", "TEST", "TRITAN", "DEUTAN", "QUANTUM TELEPORT", "SUPERPOSITION", "ENTANGLE", "COLLAPSE", "SWAP", "GRN", "EMP", "OK", "NOVA", "NEON FM", "SFX", "POST", "FPS", "HP", "CR", "RB", "LB", "RT", "LT", "A", "B", "X", "Y", "LS", "RS", "UP"]
## Sprite-sheet style short tags (3 letters, weapon wheel) are not words.
const SCREENS := {
	"title": [&"menu", ""], "title_options": [&"menu", "_options_open"], "title_arena": [&"menu", "_arena_open"], "title_chapters": [&"menu", "_chapters_open"],
	"pause": [&"paused", ""], "pause_options": [&"paused", "_options_open"], "pause_chapters": [&"paused", "_chapters_open"], "pause_ach": [&"paused", "_ach_open"],
	"pause_arena": [&"paused", "_arena_open"], "pause_skills": [&"paused", "_skills_open"], "pause_heist": [&"paused", "_heist_open"], "pause_side": [&"paused", "_side_open"],
	"pause_look": [&"paused", "_look_open"], "pause_loadout": [&"paused", "_loadout_open"], "pause_gear": [&"paused", "gear"], "pause_shop": [&"paused", "_shop_open"],
	"pause_safehouse": [&"paused", "_safe_open"], "pause_controls": [&"paused", "controls"], "dead": [&"dead", ""], "win": [&"win", ""],
}

var host: Node
var main: Node
var hud: Hud


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _gather(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k: Variant in (v as Dictionary):
			var val: Variant = (v as Dictionary)[k]
			if k is String or k is StringName:
				if DATA_KEYS.has(String(k)) and val is String and String(val) != "":
					out[String(val)] = true
			_gather(val, out)
	elif v is Array:
		for e: Variant in (v as Array):
			_gather(e, out)


func _script_consts(cls: Variant, out: Dictionary) -> void:
	var scr: Script = cls as Script
	if scr == null:
		return
	var m := scr.get_script_constant_map()
	for k: Variant in m:
		_gather(m[k], out)


## Every player-visible English name / brief / note of the content of waves 61-77, read from the live tables.
func _collect() -> Array[String]:
	var out := {}
	for cls: Variant in [WeaponDefs, Gear, Safehouses, SafehouseData, SideMissions, HeistScripts, ArenaScripts, StealthScripts, ChaseScripts, Attachments, Upgrades, RadioShows, SetPieces, Achievements]:
		_script_consts(cls, out)
	for id: StringName in SkillTree.ids():
		out[SkillTree.title(id)] = true
		var node: Array = SkillTree.NODES[id]
		out[str(node[4])] = true
	for t: Variant in Factions.TITLES.values():
		out[str(t)] = true
	for s: String in ["HOSTILE", "NEUTRAL", "ALLIED", "FOOT PATROLS", "PATROL CARS", "ROADBLOCKS", "HUNTER DRONES", "ELITE SQUAD", "HIDDEN", "SPOTTED", "SEARCHING", "WANTED LOST",
			"PHOTO MODE", "PHOTO SAVED", "SHARE", "BOSS RUSH", "ENDLESS ARENA", "CONTROLS", "KEYBOARD", "CONTROLLER", "HAPTICS", "WARDROBE", "WEAPON BENCH", "SAFEHOUSES",
			"ALLY FOLLOW", "ALLY HOLD", "ALLY ATTACK", "UNSEEN", "ALERTED", "SUSPICIOUS"]:
		out[s] = true
	var keys: Array[String] = []
	for k: String in out:
		if _wanted(k):
			keys.append(k)
	keys.sort()
	return keys


## Strings worth translating: has letters, not a 3-letter weapon tag, not a debug / validator message, not on the keep-English list.
func _wanted(s: String) -> bool:
	if s.length() < 3 or KEEP_ENGLISH.has(s):
		return false
	var letters := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			letters += 1
	if letters < 3:
		return false
	if s.length() == 3 and s == s.to_upper():
		return false
	if s.begins_with("missing") or s.contains("too long") or s.contains("unknown ") or s.contains("already has"):
		return false
	return true


func _is_translated(l: String, key: String) -> bool:
	if Tr.has_tr(l, key):
		return true
	var saved := Tr.lang
	Tr.set_lang(l)
	var t := Tr.t(key)
	Tr.set_lang(saved)
	return t != key


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Tr.set_lang("en")
	Tr.text_scale = 1.0
	TestMode.reset_toggles()

	# 1. missing strings report over the live data
	var keys := _collect()
	TestLib.check(keys.size() > 200, "collected the strings of waves 61-77 from the live tables (%d)" % keys.size())
	var limit := maxi(MISSING_MIN, int(ceil(float(keys.size()) * MISSING_PCT / 100.0)))
	for l: String in LANG_TESTED:
		var missing: Array[String] = []
		for k: String in keys:
			if not _is_translated(l, k):
				missing.append(k)
		print("MISSING_STRINGS %s: %d of %d untranslated (limit %d)%s" % [l, missing.size(), keys.size(), limit, "" if missing.is_empty() else "  e.g. " + " | ".join(missing.slice(0, 25))])
		TestLib.check(missing.size() <= limit, "%s: untranslated keys %d <= %d: %s" % [l, missing.size(), limit, ", ".join(missing.slice(0, 10))])

	# 2. spot checks: wave items in both languages (and the plain quantum names)
	Tr.set_lang("es")
	TestLib.check(Tr.t("SAFEHOUSES") == "REFUGIOS" and Tr.t("PHOTO MODE") == "MODO FOTO" and Tr.t("BOSS RUSH") == "ASALTO DE JEFES" and Tr.t("RIFT CARBINE") == "CARABINA DE GRIETA", "Spanish wave strings")
	TestLib.check(Tr.t("BOSS 2 / 4  VAEL OVERSEER") != "" and Tr.t("GATE 2 / 3") == "PUERTA 2 / 3" and Tr.t("DONE x3") == "HECHO x3", "Spanish numbers and composites")
	Tr.set_lang("hi")
	var dev_ok := true
	for k: String in ["SAFEHOUSES", "PHOTO MODE", "BOSS RUSH", "RIFT CARBINE", "SKILLS  4", "COURIER", "EXCHANGE VAULT", "HOSTILE", "CONTROLS", "WARDROBE", "ARMOURED"]:
		var tt := Tr.t(k)
		if tt == k or not _has_devanagari(tt):
			dev_ok = false
			print("HI_NOT_DEVANAGARI ", k, " -> ", tt)
	TestLib.check(dev_ok, "Hindi wave strings come out in Devanagari")
	TestLib.check(Tr.t("QUANTUM TELEPORT") == "QUANTUM TELEPORT" and Tr.t("ENTANGLE") == "ENTANGLE" and Tr.t("COLLAPSE") == "COLLAPSE", "quantum names stay plain in Hindi")
	TestLib.check(Tr.t("GATE 2 / 3") == "द्वार 2 / 3" and Tr.t("SHARDS  4 / 30") == "शार्ड  4 / 30", "Hindi numbers inside lines")
	Tr.set_lang("en")

	# 3. real scene: every screen at 1.5x in es / hi at both sizes
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	var win := host.get_window()
	var old := win.size
	var total := 0
	var untr := 0
	var untr_names: Array[String] = []
	var floor_hits := 0
	var worst := ""
	var seen_labels := {}
	for lang: String in LANG_TESTED:
		Tr.set_lang(lang)
		Tr.text_scale = 1.5
		for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
			win.size = size
			await frames(4)
			var vp := hud.get_viewport().get_visible_rect().size
			var s := UiUtil.ui_scale(vp)
			var font := UiUtil.font()
			for name: String in SCREENS:
				_open(name)
				TestLib.check(not hud.buttons.is_empty() or name == "dead" or name == "win", "%s %dx%d %s has buttons" % [lang, size.x, size.y, name])
				for b: Dictionary in hud.buttons:
					var label := str(b["label"])
					if OptionsScreen.is_slider(b["id"]) or PhotoScreen.is_slider(b["id"]):
						continue
					var r: Rect2 = b["rect"]
					TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r), "%s %dx%d %s: button %s is on screen" % [lang, size.x, size.y, name, b["id"]])
					var bl := Tr.t(label)
					var fs := UiUtil.fit_size(font, bl, r.size.x - 10.0 * s, int(20.0 * s))
					var sz := Tr.scaled_size(font, bl, r.size.x, fs)
					var w := font.get_string_size(bl, HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
					total += 1
					if fs <= 8:
						floor_hits += 1
						worst = "%s/%s/%s" % [lang, name, label]
					TestLib.check(w <= r.size.x + 1.0 or fs <= 8, "%s %dx%d %s: '%s' fits its button (%.0f of %.0f px at size %d)" % [lang, size.x, size.y, name, bl, w, r.size.x, sz])
					if not seen_labels.has(lang + label):
						seen_labels[lang + label] = true
						if bl == label and _wanted(label) and not _numeric_only(label) and not _same_everywhere(lang, label):
							untr += 1
							untr_names.append(label)
		_reset_flags()
	win.size = old
	await frames(3)
	var label_limit := maxi(MISSING_MIN, int(ceil(float(seen_labels.size()) * LABEL_MISSING_PCT / 100.0)))
	print("LABELS %d drawn at 1.5x, %d at the 8 px floor (last %s), %d untranslated of %d distinct (limit %d): %s" % [total, floor_hits, worst, untr, seen_labels.size(), label_limit, " | ".join(untr_names.slice(0, 25))])
	TestLib.check(total > 200, "scanned the buttons of the real screens (%d)" % total)
	TestLib.check(untr <= label_limit, "screen labels untranslated %d <= %d: %s" % [untr, label_limit, ", ".join(untr_names.slice(0, 10))])
	TestLib.check(floor_hits * 20 <= total, "at most 5%% of the buttons need the smallest font (%d of %d)" % [floor_hits, total])

	Tr.text_scale = 1.0
	Tr.set_lang("en")
	_reset_flags()
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


## A label made only of words that are the same in the language (a table entry that maps to itself, a keep-English name) or of non-English text already.
func _same_everywhere(l: String, label: String) -> bool:
	var tbl := Tr.table(l)
	for i in label.length():
		if label.unicode_at(i) > 127:
			return true
	var first := label.split(" ", false)[0] if not label.strip_edges().is_empty() else ""
	if tbl.values().has(first):
		return true
	for w: String in label.split(" ", false):
		if KEEP_ENGLISH.has(w) or _numeric_only(w) or tbl.get(w, "") == w:
			continue
		for i in w.length():
			if w.unicode_at(i) > 127:
				return true
		return false
	return true


func _numeric_only(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 65 and c <= 90 and not "%dsf".contains(char(c).to_lower())) or (c >= 97 and c <= 122 and not "dsf".contains(char(c))):
			return false
	return true


func _open(name: String) -> void:
	var spec: Array = SCREENS[name]
	_reset_flags()
	Game.state = spec[0]
	var flag := String(spec[1])
	if flag == "gear":
		hud._loadout_open = true
		hud._loadout_page = 1
	elif flag == "controls":
		hud._options_open = true
		UiSettings.s_opt_page = 2
	elif flag != "":
		hud.set(flag, true)
	hud._layout_key = ""
	hud._ensure_layout()


func _reset_flags() -> void:
	hud._shop_open = false
	hud._ach_open = false
	hud._skills_open = false
	hud._side_open = false
	hud._heist_open = false
	hud._arena_open = false
	hud._loadout_open = false
	hud._loadout_page = 0
	hud._look_open = false
	hud._chapters_open = false
	hud._options_open = false
	hud._safe_open = false
	UiSettings.s_opt_page = 0
	hud._layout_key = ""


func _has_devanagari(t: String) -> bool:
	for i in t.length():
		var c := t.unicode_at(i)
		if c >= 0x0900 and c <= 0x097F:
			return true
	return false
