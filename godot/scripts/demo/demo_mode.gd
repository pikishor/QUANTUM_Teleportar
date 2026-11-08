class_name DemoMode
extends RefCounted
## DEMO MODE: a sandbox profile started from the DEMO button on the title screen (hud.gd). Everything is accessible at once (all chapters, side missions, weapons, attachments,
## upgrades at max, suits / schemes, a maxed garage car, the whole map, large credits) and every activity, set piece, boss, event, contract and interior is launchable from the
## DEMO menu (scripts/ui/demo_menu.gd). The profile lives in its own files (user://demo_*.cfg): Progress, the map, the interiors and the activities are pointed at them while the
## demo runs, so the real save is never read for writing or touched. Leaving the demo (QUIT DEMO, ABORT TO MENU, or state `menu`) puts the real paths, the real state, the difficulty
## and the toggles back. God mode and infinite ammo reuse TestMode. Headless-testable (tests/test_demo_mode.gd).

const SAVE := "user://demo_save.cfg"
const MAP := "user://demo_map.cfg"
const INTERIORS := "user://demo_interiors.cfg"
const ACTIVITIES := "user://demo_activities.cfg"
const FILES: Array[String] = [SAVE, SAVE + ".tmp", MAP, INTERIORS, ACTIVITIES]
const CREDITS := 999999
const CityEventsScript := preload("res://scripts/world/city_events.gd")

static var active := false

static var _hooked := false
static var _stash := {}


## Whether the DEMO button can start a demo now (title screen, a profile loaded, none running).
static func can_enter() -> bool:
	return not active and Game.state == &"menu" and Game.progress is Progress


## Starts the sandbox: fresh demo files, everything granted, a run begun without a new campaign. Returns false when it cannot start.
static func enter() -> bool:
	if not can_enter():
		return false
	var prog := Game.progress as Progress
	_stash_real(prog)
	active = true
	TestMode.reset_toggles()
	for f in FILES:
		_remove(f)
	_point_files(true, prog)
	_grant_all(prog)
	var m := Game.missions as Missions
	if m != null and m.campaign != null:
		m.campaign.enabled = false                      # a sandbox: no scripted step starts by itself (the DEMO menu starts chapters on request)
	if not _hooked:
		_hooked = true
		Game.state_changed.connect(_on_state)
	prog.autosave_enabled = true                       # saves go to the demo file only (prog.path)
	prog.begin_sandbox_run()
	prog.save_file()
	Game.say("DEMO MODE", 2.0)
	return true


## Leaves the demo (idempotent): stops whatever runs, restores the real paths and state, returns to the title.
static func quit() -> void:
	if not active:
		return
	_stop_everything()
	_finish()
	Game.state = &"menu"


static func _on_state(s: StringName) -> void:
	if active and s == &"menu":                        # ABORT TO MENU from the pause screen ends the demo too
		_stop_everything()
		_finish()


static func _finish() -> void:
	var prog := Game.progress as Progress
	active = false
	Upgrades.show_all = false
	TestMode.reset_toggles()
	Difficulty.set_mode(int(_stash.get("difficulty", Difficulty.NORMAL)))
	if prog != null:
		_point_files(false, prog)
		prog.autosave_enabled = bool(_stash.get("autosave", false))
		prog.path = String(_stash.get("path", Progress.DEFAULT_PATH))
		if FileAccess.file_exists(prog.path) and prog.load_file():
			pass
		else:
			prog.new_campaign()
			prog.unlocked = int(_stash.get("unlocked", 1))
			prog.best = int(_stash.get("best", 0))
			prog.tutorial_done = bool(_stash.get("tutorial_done", false))
			prog.cine_seen = _stash.get("cine_seen", [] as Array[StringName])
	var m := Game.missions as Missions
	if m != null and m.campaign != null:
		m.campaign.enabled = bool(_stash.get("campaign", true))


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _stash_real(prog: Progress) -> void:
	var ig := InteriorGameplay.instance
	var acts := _activities()
	_stash = {
		"path": prog.path, "autosave": prog.autosave_enabled, "difficulty": Difficulty.current, "unlocked": prog.unlocked, "best": prog.best,
		"tutorial_done": prog.tutorial_done, "cine_seen": prog.cine_seen.duplicate(),
		"campaign": (Game.missions as Missions).campaign.enabled if Game.missions is Missions and (Game.missions as Missions).campaign != null else true,
		"map_path": MapScreen.path_override,
		"ig_path": ig.save_path if ig != null else "", "ig_done": ig.done.duplicate() if ig != null else {}, "ig_hinted": ig.hinted.duplicate() if ig != null else {},
		"ig_rumour": ig.rumour_index if ig != null else 0,
		"act_path": acts.save_path if acts != null else "", "act_best": acts.best.duplicate() if acts != null else {}, "act_board": acts.board.duplicate() if acts != null else [],
	}


## Points Progress, the map, the interiors and the activities at the demo files (on) or back at the real ones (off).
static func _point_files(on: bool, prog: Progress) -> void:
	var ig := InteriorGameplay.instance
	var acts := _activities()
	if on:
		prog.path = SAVE
		MapScreen.path_override = MAP
		if ig != null:
			ig.save_path = INTERIORS
			ig.done = {}
			ig.hinted = {}
			ig.rumour_index = 0
		if acts != null:
			acts.save_path = ACTIVITIES
			acts.best = {Activities.RANGE: 0.0, Activities.PARKOUR: 0.0, Activities.DRIFT: 0.0, Activities.ARENA: 0.0}
			acts.board = []
	else:
		MapScreen.path_override = String(_stash.get("map_path", ""))
		if ig != null:
			ig.save_path = String(_stash.get("ig_path", InteriorGameplay.SAVE_PATH))
			ig.done = _stash.get("ig_done", {})
			ig.hinted = _stash.get("ig_hinted", {})
			ig.rumour_index = int(_stash.get("ig_rumour", 0))
		if acts != null:
			acts.save_path = String(_stash.get("act_path", "user://activities.cfg"))
			acts.best = _stash.get("act_best", acts.best)
			acts.board = _stash.get("act_board", acts.board)
		for map: MapScreen in _maps():                  # the live map screen goes back to the real discovery file
			map.reload()


static func _activities() -> Activities:
	return Game.get_tree().get_first_node_in_group(&"activities") as Activities if Game.is_inside_tree() else null


static func _maps() -> Array[MapScreen]:
	var out: Array[MapScreen] = []
	for n in Game.get_tree().root.find_children("MapScreen", "MapScreen", true, false):
		out.append(n as MapScreen)
	return out


## Everything unlocked, owned and maxed (the profile in memory; the caller saves it to the demo file).
static func _grant_all(prog: Progress) -> void:
	prog.credits = CREDITS
	Upgrades.show_all = true                            # the demo shows every upgrade row and the skill / workbench tabs
	prog.reputation = Progress.REP_MAX
	prog.unlock(CampaignRunner.chapter_count() - 1)
	prog.unlock(11)
	for id: StringName in WeaponDefs.IDS:
		prog.grant_weapon(id)
	for part: StringName in Attachments.IDS:
		Attachments.give(part)
	Gear.give_all()
	SkillTree.max_all()
	for id: StringName in Upgrades.IDS:
		var guard := 0
		while prog.level(id) < Upgrades.MAX_LEVEL and guard < 12:
			prog.grant_upgrade(id)
			guard += 1
	var keys: Array[String] = ["accent"]
	for s: StringName in HeroLook.SUIT_ORDER:
		keys.append("suit:%s" % s)
	for i in HeroLook.scheme_count():
		keys.append("scheme:%d" % i)
	for k in keys:
		prog.hero.grant(k)
		var need := HeroLook.item_need(k)
		if need != "" and not prog.achievements.cosmetics.has(StringName(need)):
			prog.achievements.cosmetics.append(StringName(need))
	Safehouses.grant_all(prog)
	Crafting.grant_all(prog)
	prog.garage.kind = &"sport"
	prog.garage.levels = {}
	for st: StringName in Garage.STATS:
		prog.garage.levels[st] = Garage.MAX_LEVEL
	for b in CampaignRunner.chapter_count():
		if not prog.bosses_cleared.has(b):
			prog.bosses_cleared.append(b)
	for map: MapScreen in _maps():
		map.reveal_all()
	prog.changed.emit()


# --- the DEMO menu's catalogue and actions ---------------------------------------------------------------------------------------------

## Launch groups, in tab order: [{kind, title, items: [{id, label}]}].
static func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ch: Array[Dictionary] = []
	for i in CampaignRunner.chapter_count():
		ch.append({"id": i, "label": "%d  %s" % [i + 1, CampaignRunner.chapter_title(i)]})
	out.append({"kind": &"chapter", "title": "CHAPTERS", "items": ch})
	var side: Array[Dictionary] = []
	for id: StringName in SideMissions.ORDER:
		side.append({"id": id, "label": String(SideMissions.def(id).get("title", String(id))).to_upper()})
	out.append({"kind": &"side", "title": "SIDE MISSIONS", "items": side})
	var acts: Array[Dictionary] = []
	for id: StringName in Activities.IDS:
		acts.append({"id": id, "label": String(Activities.NAMES[id])})
	out.append({"kind": &"activity", "title": "ACTIVITIES", "items": acts})
	var sps: Array[Dictionary] = []
	for id: StringName in SetPieces.IDS:
		sps.append({"id": id, "label": String(SetPieces.DEFS[id]["title"])})
	out.append({"kind": &"setpiece", "title": "SET PIECES", "items": sps})
	var bosses: Array[Dictionary] = [{"id": &"contract", "label": "BOSS CONTRACT"}]
	for t: StringName in EnemyTypes.TYPES:
		if bool(EnemyTypes.TYPES[t].get("boss", false)):
			bosses.append({"id": t, "label": String(t).to_upper()})
	out.append({"kind": &"boss", "title": "BOSSES", "items": bosses})
	var ev: Array[Dictionary] = []
	for k: StringName in CityEventsScript.KINDS:
		ev.append({"id": k, "label": String(CityEventsScript.DEF[k]["label"])})
	out.append({"kind": &"event", "title": "EVENTS", "items": ev})
	var cons: Array[Dictionary] = []
	for k: StringName in TestMode.CONTRACTS:
		cons.append({"id": k, "label": ContractTypes.title(k)})
	out.append({"kind": &"contract", "title": "CONTRACTS", "items": cons})
	var ints: Array[Dictionary] = []
	for t: StringName in InteriorData.TYPES:
		ints.append({"id": t, "label": InteriorData.title(t)})
	out.append({"kind": &"interior", "title": "INTERIORS", "items": ints})
	var seq: Array[Dictionary] = []
	for id: StringName in CampaignSteps.DEMO_IDS:
		seq.append({"id": id, "label": String(CampaignSteps.DEMO_TITLES[id])})
	out.append({"kind": &"sequel", "title": "SEQUEL MECHANICS", "items": seq})
	var chs: Array[Dictionary] = []
	for id: StringName in ChaseScripts.IDS:
		chs.append({"id": id, "label": ChaseScripts.title(id)})
	out.append({"kind": &"chase", "title": "VEHICLE CHASES", "items": chs})
	out.append({"kind": &"companion", "title": "COMPANION", "items": [{"id": &"recruit", "label": "RECRUIT VAEL DEFECTOR"}, {"id": &"dismiss", "label": "DISMISS ALLY"}]})
	var sts: Array[Dictionary] = []
	for id: StringName in StealthScripts.IDS:
		sts.append({"id": id, "label": StealthScripts.title(id)})
	out.append({"kind": &"stealth", "title": "STEALTH MISSIONS", "items": sts})
	var hts: Array[Dictionary] = []
	for id: StringName in HeistScripts.IDS:
		for ap: StringName in HeistScripts.APPROACHES:
			hts.append({"id": "%s:%s" % [id, ap], "label": "%s  %s" % [HeistScripts.title(id), HeistScripts.approach_title(ap)]})
	out.append({"kind": &"heist", "title": "HEIST MISSIONS", "items": hts})
	var ars: Array[Dictionary] = []
	for d: StringName in ArenaScripts.DIFFS:
		ars.append({"id": "rush:%s" % d, "label": "BOSS RUSH  %s" % ArenaScripts.diff_title(d)})
	ars.append({"id": "endless:", "label": "ENDLESS ARENA"})
	ars.append({"id": "endless:armoured,swarm,brutal", "label": "ENDLESS ARENA  ALL MODIFIERS"})
	out.append({"kind": &"arena", "title": "BOSS RUSH AND ARENA", "items": ars})
	var shs: Array[Dictionary] = []
	for id: StringName in Safehouses.IDS:
		shs.append({"id": id, "label": "SAFEHOUSE  %s" % Safehouses.title(id)})
	out.append({"kind": &"safehouse", "title": "SAFEHOUSES", "items": shs})
	out.append({"kind": &"crafting", "title": "WORKBENCH", "items": [{"id": &"bench", "label": "OPEN THE WORKBENCH"}, {"id": &"parts", "label": "ADD PARTS AND BLUEPRINTS"},
		{"id": &"kit", "label": "CRAFT AND EQUIP A LEGENDARY KIT"}, {"id": &"drop", "label": "ROLL A MISSION DROP"}]})
	return out


## Runs one catalogue entry; returns a status line ("" when it could not run). The game must be in play (the menu closes first).
static func launch(kind: StringName, id: Variant) -> String:
	if not active or not is_instance_valid(Game.player):
		return ""
	match kind:
		&"chapter": return start_chapter(int(id))
		&"side": return start_side(StringName(id))
		&"activity": return start_activity(StringName(id))
		&"setpiece": return start_set_piece(StringName(id))
		&"sequel": return start_sequel(StringName(id))
		&"chase": return start_chase(StringName(id))
		&"companion": return start_companion(StringName(id))
		&"stealth": return start_stealth(StringName(id))
		&"heist": return start_heist(str(id))
		&"arena": return start_arena(str(id))
		&"safehouse": return start_safehouse(StringName(id))
		&"crafting": return start_crafting(StringName(id))
		&"boss":
			_prepare()
			return TestMode.start_contract(&"boss") if StringName(id) == &"contract" else TestMode.spawn_enemy(StringName(id))
		&"event": return start_event(StringName(id))
		&"contract":
			_prepare()
			return TestMode.start_contract(StringName(id))
		&"interior":
			_prepare(false)
			return InteriorTestActions.enter(StringName(id))
	return ""


## Stops what runs so a new launch starts clean: the interior (optional), the activity, the side mission, the contract and the campaign step.
static func _prepare(leave_interior := true) -> void:
	var ig := InteriorGameplay.instance
	if leave_interior and ig != null and ig.active:
		ig.leave(true)
	var acts := _activities()
	if acts != null and acts.active != &"":
		acts.stop()
	var m := Game.missions as Missions
	if m == null:
		return
	if m.sides != null and m.sides.active:
		m.sides.abort("DEMO")
	if m.contracts != null and bool(m.contracts.is_active()):
		m.contracts.abandon()
	if m.heists != null and m.heists.is_running():
		m.heists.abort("DEMO")
	if m.campaign != null and m.campaign.is_running():
		m.campaign.abort()
	if m.chases != null and m.chases.is_running():
		m.chases.abort("DEMO")
	if m.stealth != null and m.stealth.is_running():
		m.stealth.abort("DEMO")
	if m.arena != null and m.arena.is_running():
		m.arena.abort("DEMO")


static func _stop_everything() -> void:
	if Game.progress == null or not is_instance_valid(Game.world):
		return
	_prepare()
	if is_instance_valid(Game.enemies):
		(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0


static func start_chapter(index: int) -> String:
	var m := Game.missions as Missions
	index = clampi(index, 0, CampaignRunner.chapter_count() - 1)
	if m == null or m.campaign == null:
		return ""
	_prepare()
	TestMode.jump_to_chapter(index)
	return "CHAPTER %d" % (index + 1) if m.campaign.start_chapter(index, 0, true) else ""


static func start_side(id: StringName) -> String:
	var m := Game.missions as Missions
	if m == null or m.sides == null:
		return ""
	_prepare()
	return "SIDE MISSION  %s" % String(SideMissions.def(id).get("title", String(id))) if m.sides.start(id) else ""


## One of the sequel mechanics (rift hold, heist, convoy intercept) as a one-step sandbox chapter.
static func start_sequel(id: StringName) -> String:
	var m := Game.missions as Missions
	if m == null or m.campaign == null or not CampaignSteps.DEMO_IDS.has(id):
		return ""
	_prepare()
	return "SEQUEL  %s" % String(CampaignSteps.DEMO_TITLES[id]) if m.campaign.start_demo(id) else ""


## One of the six vehicle chase set pieces (ChaseScripts.IDS), started where the player stands.
static func start_chase(id: StringName) -> String:
	var m := Game.missions as Missions
	if m == null or m.chases == null or not ChaseScripts.DEFS.has(id):
		return ""
	_prepare()
	return "CHASE  %s" % ChaseScripts.title(id) if m.chases.start(id) else ""


## One of the four stealth missions (StealthScripts.IDS): enters the nearest door of its interior (or a test room) and begins.
static func start_stealth(id: StringName) -> String:
	var m := Game.missions as Missions
	if m == null or m.stealth == null or not StealthScripts.DEFS.has(id):
		return ""
	_prepare()
	if is_instance_valid(Game.enemies):
		(Game.enemies as EnemyManager).clear()          # hunters from an earlier alarm would follow through the door and spoil the run
	Game.heat = 0.0
	return "STEALTH  %s" % StealthScripts.title(id) if m.stealth.start(id) else ""


## One heist and approach ("vault:quantum"; no colon = stealth), started where the player stands. The companion joins for the run.
static func start_heist(key: String) -> String:
	var m := Game.missions as Missions
	var parts := key.split(":")
	var hid := StringName(parts[0])
	var ap := StringName(parts[1]) if parts.size() > 1 else &"stealth"
	if m == null or m.heists == null or not HeistScripts.DEFS.has(hid):
		return ""
	_prepare()
	if is_instance_valid(Game.enemies):
		(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	return "HEIST  %s  %s" % [HeistScripts.title(hid), HeistScripts.approach_title(ap)] if m.heists.start(hid, ap, true) else ""


## A boss rush ("rush:hard") or an endless arena ("endless:armoured,swarm"; empty = no modifiers), started where the player stands.
## A safehouse: moves the hero to its door and opens its screen (the house is owned in the demo already).
static func start_safehouse(id: StringName) -> String:
	var prog := Game.progress as Progress
	if prog == null or not Safehouses.DEFS.has(id) or not Safehouses.is_owned(prog, id):
		return ""
	_prepare()
	Safehouses.sel = id
	Safehouses.travel(prog, id)
	var hud := _hud()
	if hud == null:
		return ""
	Game.state = &"paused"
	return "SAFEHOUSE  %s" % Safehouses.title(id) if hud.press_button(&"sh_open") else ""


## The workbench entries: open the bench, refill parts and blueprints, craft and equip one legendary item per perk, or roll a contract drop.
static func start_crafting(what: StringName) -> String:
	var prog := Game.progress as Progress
	if prog == null:
		return ""
	match what:
		&"bench":
			_prepare()
			var hud := _hud()
			if hud == null:
				return ""
			Game.state = &"paused"
			return "WORKBENCH" if hud.press_button(&"cr_open") else ""
		&"parts":
			Crafting.grant_all(prog)
			return "PARTS AND BLUEPRINTS  ADDED"
		&"kit":
			var w := WeaponDefs.last_used
			var made := 0
			for bp: StringName in [&"mod_singularity", StringName("var_%s" % w)]:
				if Crafting.knows(bp):
					var it := Crafting.make_item(bp, 3, int(Time.get_ticks_usec()) & 0x7fffffff)
					Crafting.add_item(it)
					Crafting.equip(prog, int(it["uid"]), w)
					made += 1
			return "LEGENDARY KIT  %d EQUIPPED" % made if made > 0 else ""
		&"drop":
			var d := Crafting.award(&"contract")
			return Crafting.drop_text(d) if not Crafting.drop_text(d).is_empty() else "NO DROP THIS TIME"
	return ""


static func _hud() -> Hud:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var n := tree.root.find_children("*", "Hud", true, false)
	return n[0] as Hud if not n.is_empty() else null


static func start_arena(key: String) -> String:
	var m := Game.missions as Missions
	var parts := key.split(":")
	var mode := StringName(parts[0])
	if m == null or m.arena == null or not (mode == &"rush" or mode == &"endless"):
		return ""
	var diff: StringName = StringName(parts[1]) if mode == &"rush" and parts.size() > 1 else &"normal"
	var mods: Array = []
	if mode == &"endless" and parts.size() > 1 and parts[1] != "":
		for md in parts[1].split(","):
			mods.append(StringName(md))
	_prepare()
	Game.heat = 0.0
	return "ARENA  %s" % String(mode).to_upper() if m.arena.start(mode, diff, mods) else ""


## Index of a set piece's first step inside its chapter's spliced step list (-1 when it has none).
static func set_piece_step(id: StringName) -> int:
	var m := Game.missions as Missions
	if m == null or m.campaign == null or not SetPieces.DEFS.has(id):
		return -1
	var ch := int(SetPieces.DEFS[id]["chapter"])
	var steps := SetPieces.splice(CampaignSteps.normalize_chapter(m.campaign.chapter_data(ch), ch), ch)
	for i in steps.size():
		if StringName(str(steps[i].get("set_piece", ""))) == id:
			return i
	return -1


static func start_set_piece(id: StringName) -> String:
	var m := Game.missions as Missions
	var at := set_piece_step(id)
	if m == null or at < 0:
		return ""
	var ch := int(SetPieces.DEFS[id]["chapter"])
	_prepare()
	TestMode.jump_to_chapter(ch)
	return "SET PIECE  %s" % String(SetPieces.DEFS[id]["title"]) if m.campaign.start_chapter(ch, at, true) else ""


## Teleports to the activity's entry marker and starts it (the drift course without a car too).
static func start_activity(id: StringName) -> String:
	var acts := _activities()
	var p := Game.player as Player
	if acts == null or p == null or not Activities.entries().has(id):
		return ""
	_prepare()
	var e: Vector3 = Activities.entries()[id]
	p.teleport_to(PlayerUtil.safe_spot(Vector3(e.x, 0.0, e.z), Game.world if is_instance_valid(Game.world) else null, p.get_world_3d().direct_space_state) + Vector3(0.0, 0.1, 0.0))
	return "ACTIVITY  %s" % String(Activities.NAMES[id]) if acts.start(id, true) else ""


## Spawns a city event of `kind` near the player (running events are cleared first so the cap and the cooldown never refuse).
static func start_event(kind: StringName) -> String:
	var ev := Game.get_tree().get_first_node_in_group(&"city_events")
	var p := Game.player as Player
	if ev == null or p == null:
		return ""
	ev.call(&"reset")
	var e: Dictionary = ev.call(&"spawn_near", p.global_position, kind)
	return "EVENT  %s" % String(kind).to_upper() if not e.is_empty() else ""


## RECRUIT puts the Vael defector next to the hero (it stays until DISMISS, a new run or the title); DISMISS sends it away.
static func start_companion(id: StringName) -> String:
	var c := Companion.current
	if c == null:
		return ""
	if id == &"dismiss":
		c.dismiss()
		return "ALLY DISMISSED"
	if c.active:
		c.manual = true
		return "ALLY  ALREADY HERE"
	return "ALLY  VAEL DEFECTOR" if c.recruit("demo") else ""


static func set_difficulty(mode: int) -> String:
	Difficulty.set_mode(mode)
	return "DIFFICULTY  %s" % Difficulty.mode_name()


static func reveal_map() -> String:
	var maps := _maps()
	for map in maps:
		map.reveal_all()
	return "MAP REVEALED" if not maps.is_empty() else ""
