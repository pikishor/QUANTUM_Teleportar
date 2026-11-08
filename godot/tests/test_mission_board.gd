extends RefCounted
## The Mission Board and the easy loop (docs/DESIGN.md core loop) in the REAL scene (main.tscn): a new game starts its first mission within 10 s of PLAY with a "how to move" line in the first
## seconds; the board offers three missions near the hero drawn from all sixteen types, with pay by distance; a bot then finishes SIX DIFFERENT generated missions using the UI only (ESC, MISSIONS,
## the three cards, NEW OFFERS, the result card's NEXT: real taps on the Hud's own buttons) and real movement, shooting and driving (tests/mission_audit.gd). It also checks the instant retry
## after a failed step, the EASY / NORMAL / HARD switch, that no QUANTUM CORES line or duplicate objective is drawn, the 64 px touch targets and the pure rules (recipes validate, pay grows with
## distance, EASY is the default outside tools). Waits on state and counters, never on frame counts; user:// state is reset by the audit setup.
## Run: tools/test.sh tests/test_mission_board.gd   (about 100 s: it plays about 12 minutes of game time at 16x; the runner reads TIMEOUT_SECONDS)

const TIMEOUT_SECONDS := 140.0
const Audit := preload("res://tests/mission_audit.gd")
const K := 16
const TICK := 8.0
## The order the bot prefers when it picks a card (cheap and dependable kinds first); it still picks a type it has not finished yet.
const PREFER: Array[StringName] = [&"courier", &"patrol", &"demolition", &"stealth", &"hijack", &"bounty", &"hack", &"escort", &"rescue", &"defend", &"arena", &"vehicle", &"boss", &"chase", &"convoy", &"heist"]
const WANT := 6

var host: Node
var a: Audit
var hud: Hud
var board: MissionBoard
var done_types: Array[StringName] = []
var via_card := 0
var picks := 0
var new_offers := 0
var msgs: PackedStringArray = PackedStringArray()
var _idle_t := 0.0


func run(h: Node) -> void:
	host = h
	_pure_rules()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = int(TICK) * K
	Engine.max_physics_steps_per_frame = 64
	a = Audit.new()
	var ok := await a.setup(host)
	TestLib.check(ok, "the real scene has a player, a city, enemies, vehicles and missions")
	if not ok:
		_restore()
		return
	hud = host.get_tree().root.find_child("Hud", true, false) as Hud
	var m := Game.missions as Missions
	board = m.board
	TestLib.check(board != null and hud != null, "Missions owns the Mission Board and the Hud is there")
	if board == null or hud == null:
		_restore()
		return
	a.max_game_seconds = 6000.0
	var real0 := Time.get_ticks_msec()
	await _first_ten_seconds()
	await _board_screen_and_ui_rules()
	await _six_missions(real0)
	await _story_card()
	_final_checks()
	await a.teardown()
	_restore()


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	ResultCard.enabled = false
	Game.state = &"menu"


# --- pure rules ----------------------------------------------------------------------------------------------------------------------

func _pure_rules() -> void:
	TestLib.check(MissionBoard.TYPES.size() == 16 and MissionBoard.DEFS.size() == 16, "sixteen mission types")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var kinds := {}
	var all_valid := true
	var min_steps := 99
	for t: StringName in MissionBoard.TYPES:
		for tier in 4:
			var steps := MissionBoardSteps.steps(t, tier, rng)
			var why := CampaignSteps.validate_chapter({"steps": steps})
			if not why.is_empty():
				all_valid = false
				printerr("recipe %s tier %d: %s" % [t, tier, str(why)])
			min_steps = mini(min_steps, steps.size())
			for st: Dictionary in steps:
				kinds[StringName(st["kind"])] = true
				if str(st["text"]).length() > 40:
					all_valid = false
	TestLib.check(all_valid, "every recipe validates and its objective lines are short")
	TestLib.check(min_steps >= 2, "every mission has at least two steps, so a checkpoint at every step (%d)" % min_steps)
	for k: StringName in [&"kill_target", &"chase", &"escort", &"reach", &"heist", &"convoy_intercept", &"survive", &"defend", &"hack", &"smash", &"sneak"]:
		TestLib.check(kinds.has(k), "the recipes use the step kind %s" % k)
	TestLib.check(MissionBoard.pay_for(150.0, 400.0, 0) > MissionBoard.pay_for(150.0, 100.0, 0), "pay grows with the distance")
	TestLib.check(MissionBoard.pay_for(150.0, 200.0, 3) > MissionBoard.pay_for(150.0, 200.0, 0), "pay grows with the tier")
	TestLib.check(MissionBoard.pay_for(150.0, 200.0, 0) % 5 == 0, "pay is in whole fives")
	TestLib.check(Difficulty.NAMES[0] == "EASY" and Difficulty.mult("hp", 0) < Difficulty.mult("hp", 1) and Difficulty.mult("dmg", 0) < Difficulty.mult("dmg", 1), "EASY is the softest mode")
	var was := Game.autostart
	Game.autostart = false
	TestLib.check(Difficulty.default_mode() == 0, "outside tools a player who never chose plays EASY")
	Game.autostart = true
	TestLib.check(Difficulty.default_mode() == Difficulty.NORMAL, "tools and tests keep NORMAL")
	Game.autostart = was


# --- the first seconds of a new game ----------------------------------------------------------------------------------------------------

func _first_ten_seconds() -> void:
	board.set_take_over(true)
	board.auto_open = false
	Game.message.connect(func(t: String, _s: float) -> void: msgs.append(t))
	board.finished.connect(_on_finished)
	a.camp.step_completed.connect(a._on_step_done)
	a.camp.step_failed.connect(a._on_step_failed)
	a.camp.step_failed.connect(func(_c: int, i: int, k: StringName, why: String) -> void: print("STEP FAILED ", i, " ", k, " ", why, " t=%.0f" % a.game_clock))
	Game.start_new_game()
	var t0 := a.game_clock
	var started_at := -1.0
	var hint_at := -1.0
	while a.game_clock - t0 < 14.0:
		await a._frame()
		if a._globals():
			continue
		if started_at < 0.0 and board.is_running():
			started_at = a.game_clock - t0
		if hint_at < 0.0:
			for t in msgs:
				if t.contains("LEFT STICK") or t.contains("WASD"):
					hint_at = a.game_clock - t0
		if started_at >= 0.0 and hint_at >= 0.0:
			break
	TestLib.check(started_at >= 0.0 and started_at <= 10.0, "the first mission starts within 10 s of PLAY (%.1f s)" % started_at)
	TestLib.check(hint_at >= 0.0 and hint_at <= 20.0, "the first seconds say how to move (%.1f s)" % hint_at)
	TestLib.check(str(board.active.get("type", "")) == "first", "the first mission is the FIRST JOB")
	TestLib.check(Game.missions.total == 0 and Game.missions.cores.is_empty(), "no quantum cores stand in the city in board mode")
	await _scan_hud_once("first mission", true)


## Draws the HUD once with the text scan on and checks the objective is said once and there is no QUANTUM CORES line.
func _scan_hud_once(tag: String, require_line := false) -> void:
	var re := RegEx.new()
	re.compile("^(\\d+/\\d+|NEXT)\\s\\s")
	hud._text_t = 0.0
	for i in 60:                                         # the HUD refreshes its texts every 0.2 s: wait until the objective line has reached it
		if re.search(hud._camp_text) != null:
			break
		await TestLib.frames(host, 1)
	hud.scan_log.clear()
	hud.scan_hud = true
	hud.scan_text = true
	hud._text_t = 0.0
	hud._hud.queue_redraw()
	for i in 6:
		await TestLib.frames(host, 1)
		if not hud.scan_log.is_empty():
			break
	hud.scan_text = false
	hud.scan_hud = false
	var frame_log: Array[Dictionary] = []               # the scan may hold several draws of the HUD: only the last one counts
	var seen := {}
	for i in range(hud.scan_log.size() - 1, -1, -1):
		var tx := String(hud.scan_log[i]["text"])
		if seen.has(tx):
			break
		seen[tx] = true
		frame_log.append(hud.scan_log[i])
	var cores := 0
	var lines := 0
	var core := ""
	for e: Dictionary in frame_log:
		var t := String(e["text"]).to_upper()
		if t.contains("QUANTUM CORES"):
			cores += 1
		if re.search(t) != null:
			lines += 1
			var parts := t.split("  ")
			core = parts[1] if parts.size() > 1 else ""
	var echoes := 0
	if core != "":
		for e: Dictionary in frame_log:
			var t2 := String(e["text"]).to_upper()
			if t2.contains(core) and re.search(t2) == null:
				echoes += 1
	if lines != 1:
		print("SCAN ", tag, " ", frame_log.map(func(e: Dictionary) -> String: return "%s@%s" % [e["text"], str(e["rect"].position)]))
	TestLib.check(cores == 0, "%s: no QUANTUM CORES line on the HUD" % tag)
	TestLib.check(lines <= 1 and echoes == 0, "%s: the objective is on screen once (%d lines, %d echoes)" % [tag, lines, echoes])
	if require_line:
		TestLib.check(lines == 1, "%s: there is an objective line while a mission runs" % tag)


# --- the board screen ----------------------------------------------------------------------------------------------------------------------

func _tap_id(id: StringName) -> bool:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return hud.tap((b["rect"] as Rect2).get_center())
	return false


func _has_button(id: StringName) -> bool:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return true
	return false


func _board_screen_and_ui_rules() -> void:
	# let the first job finish by itself first (the bot plays it)
	await _play_until(func() -> bool: return not board.is_running(), 200.0)
	TestLib.check(not board.is_running() and board.done_count >= 1, "the first job was finished (%d done)" % board.done_count)
	await _settle_after_mission()
	TestLib.check(board.offers.size() == MissionBoard.OFFERS, "three missions are on offer the moment a mission ends")
	var types := {}
	for o: Dictionary in board.offers:
		types[o["type"]] = true
		TestLib.check(int(o["reward"]) > 0 and float(o["route_m"]) > 20.0 and str(o["title"]) != "", "offer %s has pay %d and a route %.0f m" % [o["title"], int(o["reward"]), float(o["route_m"])])
	TestLib.check(types.size() == 3, "the three offers are three different types")
	TestLib.check(not board.story_offer().is_empty(), "the story chapter is the highlighted card")
	# open it with the ESC path and the pause menu's MISSIONS card
	hud.toggle_pause()
	await TestLib.frames(host, 2)
	TestLib.check(Game.state == &"paused" and _has_button(&"board_open"), "the pause menu has a MISSIONS card")
	TestLib.check(_tap_id(&"board_open"), "tapping MISSIONS opens the board")
	await TestLib.frames(host, 2)
	TestLib.check(hud._board_open and _has_button(&"board_pick_0") and _has_button(&"board_pick_1") and _has_button(&"board_pick_2") and _has_button(&"board_story"), "the board shows STORY and three cards")
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var small := 0
	for b: Dictionary in hud.buttons:
		if (b["rect"] as Rect2).size.y < 63.5 * s:
			small += 1
	TestLib.check(small == 0, "every board button is at least 64 px tall (%d smaller)" % small)
	# the difficulty switch
	TestLib.check(_tap_id(&"board_diff_0") and Difficulty.current == 0, "EASY switches to the easy numbers")
	TestLib.check(_tap_id(&"board_diff_2") and Difficulty.current == 2, "HARD switches to the hard numbers")
	TestLib.check(_tap_id(&"board_diff_1") and Difficulty.current == 1, "NORMAL switches back")
	_tap_id(&"board_diff_0")
	var before_ids: Array = board.offers.map(func(o: Dictionary) -> int: return int(o["id"]))
	TestLib.check(_tap_id(&"board_new"), "NEW OFFERS is a button")
	var after_ids: Array = board.offers.map(func(o: Dictionary) -> int: return int(o["id"]))
	TestLib.check(before_ids != after_ids, "NEW OFFERS makes new missions")
	# the map has a MISSIONS button too
	TestLib.check(_tap_id(&"board_back") and Game.state == &"play", "FREE ROAM closes the board and the game runs again")
	var ms := host.get_tree().root.find_child("MapScreen", true, false) as MapScreen
	if ms != null:
		ms.open()
		await TestLib.frames(host, 2)
		var mb := ms._root.find_child("Missions", true, false) as Button
		TestLib.check(mb != null and mb.size.y >= 63.0 * s, "the map has a MISSIONS button of at least 64 px")
		if mb != null:
			mb.pressed.emit()
			await TestLib.frames(host, 3)
			TestLib.check(hud._board_open and Game.state == &"paused", "the map's MISSIONS opens the board")
			_tap_id(&"board_back")
			await TestLib.frames(host, 2)
	TestLib.check(Game.state == &"play", "back in the game")


# --- six different missions through the UI ----------------------------------------------------------------------------------------------

func _on_finished(o: Dictionary, ok: bool, _r: int) -> void:
	_idle_t = 0.0
	print("FINISHED ", o["type"], " ok ", ok, " ", board.last_result, " t=%.0f" % a.game_clock)
	if ok and StringName(o["type"]) != &"first" and not done_types.has(StringName(o["type"])):
		done_types.append(StringName(o["type"]))


func _six_missions(real0: int) -> void:
	ResultCard.enabled = true                          # the real flow: the card opens after a mission, NEXT opens the board
	var budget_real := 128.0
	var retried := false
	while done_types.size() < WANT and float(Time.get_ticks_msec() - real0) / 1000.0 < budget_real and a.game_clock < 5000.0:
		await a._frame()
		if Game.state == &"paused":
			_ui_step()
			continue
		if a._globals():
			continue
		a.heal_up()
		if board.is_running():
			_idle_t = 0.0
			a._tick_campaign()
			if not retried and board.is_running() and a.camp.state == &"active" and a.camp.step_index >= 1 and String(board.active.get("type", "")) != "first":
				retried = true
				await _instant_retry()
				await _scan_hud_once("running mission", true)
		elif board.state == &"idle":
			a.stop_walking()
			a.hold(&"fire", false)
			_idle_t += a.dt
			var rc := host.get_tree().get_first_node_in_group(&"result_card") as ResultCard
			var card_coming := rc != null and ResultCard.enabled and (rc.is_open or not rc.queue.is_empty())
			if _idle_t > 4.0 and not card_coming:                    # no result card (it never came): the pause menu's MISSIONS is the way
				_idle_t = 0.0
				hud.toggle_pause()


## The card's NEXT, the board's cards and NEW OFFERS: what a player taps when the game is paused.
func _ui_step() -> void:
	var rc := host.get_tree().get_first_node_in_group(&"result_card") as ResultCard
	if rc != null and rc.is_open:
		if rc.tap(rc.next_rect().get_center()):
			via_card += 1
		return
	if hud._board_open and board.state == &"idle":
		_pick_card()
		return
	if hud._board_open:
		_tap_id(&"board_back")
		return
	if _has_button(&"board_open"):
		_tap_id(&"board_open")
	else:
		hud.toggle_pause()


func _pick_card() -> void:
	# the best-ranked card of a type not finished yet; NEW OFFERS while only expensive ones are there
	var best := -1
	var best_rank := 999
	for i in board.offers.size():
		var t := StringName(board.offers[i]["type"])
		if done_types.has(t):
			continue
		var rank := PREFER.find(t)
		if rank < 0:
			rank = 50
		if rank < best_rank:
			best_rank = rank
			best = i
	if best < 0 or (best_rank > 11 and new_offers < 30):
		if new_offers < 40:
			new_offers += 1
			_tap_id(&"board_new")
			return
		best = maxi(best, 0)
	if _tap_id(StringName("board_pick_%d" % best)):
		picks += 1


## A failed step restarts by itself within a couple of seconds ("instant retry"), with the step's own line.
func _instant_retry() -> void:
	var k := a.camp
	var idx := k.step_index
	k._fail("TEST")
	var t0 := a.game_clock
	var again := false
	while a.game_clock - t0 < 6.0:
		await a._frame()
		if a._globals():
			continue
		if k.state == &"active" and k.step_index == idx:
			again = true
			break
	TestLib.check(again, "a failed step starts again by itself within %.1f s (retry pause %.1f s)" % [a.game_clock - t0, k.retry_pause])
	TestLib.check(a.game_clock - t0 < 4.0, "the retry is quick (%.1f s)" % (a.game_clock - t0))


func _play_until(cond: Callable, max_game: float) -> void:
	var t0 := a.game_clock
	var real0 := Time.get_ticks_msec()
	while not cond.call() and a.game_clock - t0 < max_game and float(Time.get_ticks_msec() - real0) / 1000.0 < 60.0:
		await a._frame()
		if Game.state == &"paused":
			if ResultCard.enabled:
				_ui_step()
			else:
				Game.state = &"play"
			continue
		if a._globals():
			continue
		a.heal_up()
		if board.is_running():
			a._tick_campaign()


func _settle_after_mission() -> void:
	a.stop_walking()
	a.hold(&"fire", false)
	await TestLib.frames(host, 3)


# --- the verdict -------------------------------------------------------------------------------------------------------------------------

## The highlighted STORY card starts the campaign chapter through the same board; abandoning it leaves free roam.
func _story_card() -> void:
	TestLib.check(not (Game.missions as Missions).contracts.enabled, "the random contract offers are off in board mode (the board is the source of jobs)")
	ResultCard.enabled = false
	if Game.state != &"play":
		Game.state = &"play"
	for i in 30:
		if board.state == &"idle":
			break
		await a._frame()
	hud.toggle_pause()
	await TestLib.frames(host, 2)
	_tap_id(&"board_open")
	await TestLib.frames(host, 2)
	TestLib.check(hud._board_open and _has_button(&"board_story"), "the board shows the STORY card")
	TestLib.check(_tap_id(&"board_story"), "tapping STORY starts the chapter")
	await TestLib.frames(host, 2)
	TestLib.check(board.state == &"story" and a.camp.is_running() and Game.state == &"play", "the story chapter runs through the campaign runner")
	board.abandon()
	await TestLib.frames(host, 2)
	TestLib.check(board.state == &"idle" and not a.camp.is_running(), "abandoning the story leaves free roam")


func _final_checks() -> void:
	print("MISSION BOARD done %s via_card %d picks %d new_offers %d done_count %d failed %d" % [str(done_types), via_card, picks, new_offers, board.done_count, board.failed_count])
	print("  bot stats ", a.stats)
	for line in a.trace:
		print("  TRACE ", line)
	TestLib.check(done_types.size() >= WANT, "the bot finished %d different generated missions through the UI (%s)" % [done_types.size(), str(done_types)])
	TestLib.check(board.done_count >= WANT + 1, "the board counts the first job and six more (%d)" % board.done_count)
	var rc := host.get_tree().get_first_node_in_group(&"result_card") as ResultCard
	TestLib.check(rc == null or rc.shown == 0 or via_card >= 1, "the result card's NEXT opened the board at least once (%d cards, %d NEXT taps)" % [rc.shown if rc != null else 0, via_card])
	var prog := Game.progress as Progress
	TestLib.check(prog != null and prog.contracts_done >= WANT, "every finished mission was paid (%d)" % (prog.contracts_done if prog != null else -1))
	var bad: Array[Dictionary] = a.stuck_findings()
	for f in bad:
		printerr("  FINDING ", f)
	TestLib.check(bad.size() <= 2, "the bot hit at most two stuck findings (%d)" % bad.size())
