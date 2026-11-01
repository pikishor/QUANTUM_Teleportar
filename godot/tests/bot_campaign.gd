extends RefCounted
## Campaign bot: plays the whole scripted campaign (all CampaignData chapters, then the endless aftermath) in the real game (scenes/main.tscn), start to finish.
##   tools/bot.sh res://tests/bot_campaign.gd /tmp/campaign 600 1          (playthrough; prints "BOT_CAMPAIGN PASS" or "BOT_CAMPAIGN FAIL ...")
##   BOT_CAMP_LOOK=<chapter 1..8> tools/bot.sh res://tests/bot_campaign.gd /tmp/look 70 4
##       look mode: starts that chapter, lets its first step run, takes no actions (screenshots from --every / --count show the objective line, the waypoint and the intro banner)
## How it plays: the runner is switched on (`CampaignRunner.enabled` is off under tools), a new game starts, and the bot lets the runner arm every chapter by itself. For each active step it
## does the natural thing with test-mode style helpers (invulnerable player, teleport into the goal ring, kill the target and its guards, wreck the chase car, clear the heat) and, when a
## step has a long hold (hack / defend / escort / interior / escape) or does not finish within NATURAL_SECONDS of game time, finishes it with CampaignRunner.skip_step() (the TEST menu's
## SKIP THE STEP). The summary says how many steps were done each way. After the last chapter it takes the win screen (NEXT SECTOR) and checks the endless sector runs the plain core hunt.
## Asserts: every chapter completes in order with all its steps, checkpoints are saved and cleared, the unlock count reaches the chapter count, the boss bar shows on the boss steps,
## the HUD line is never empty while a step is active, and no step fails.

const NATURAL_SECONDS := 5.0
const SKIP_KINDS: Array[StringName] = [&"hack", &"defend", &"escort", &"enter_interior", &"survive", &"escape"]
const MAX_FRAMES := 40000

var _camp: CampaignRunner
var _p: Player
var _look := -1
var _ready := false
var _done := false
var _phase := &"play"
var _age := 0.0                       ## game seconds the current step has been active
var _step_key := ""
var _expect_chapter := 0
var _frames := 0
var _wait := 0.0
var _errors: PackedStringArray = []
var _natural := 0
var _skipped := 0
var _chapters_done: Array[int] = []
var _steps_in_chapter := 0
var _kinds_seen := {}
var _boss_bars := 0
var _checkpoints := 0
var _empty_lines := 0
var _failed: Array = []
var _endless_checked := false
var _chapter_began := {}


func _init() -> void:
	var l := OS.get_environment("BOT_CAMP_LOOK")
	if l != "":
		_look = clampi(int(l), 1, CampaignData.count()) - 1


func _fail(msg: String) -> void:
	_errors.append(msg)
	printerr("BOT_CAMPAIGN problem: ", msg)


func step(_t: float, delta: float) -> bool:
	_frames += 1
	if Game.player == null or not (Game.missions is Missions):
		return false
	if not _ready:
		_setup()
		return false
	if _done:
		return true
	if _frames > MAX_FRAMES:
		_fail("gave up after %d frames at chapter %d step %d" % [MAX_FRAMES, _camp.chapter_index + 1, _camp.step_index + 1])
		_finish()
		return true
	_keep_alive()
	if _look >= 0:
		_look_mode()
		return false
	_wait = maxf(_wait - delta, 0.0)
	match _phase:
		&"play":
			_play(delta)
		&"win":
			_win_screen(delta)
	return _done


func _setup() -> void:
	_p = Game.player as Player
	var m := Game.missions as Missions
	_camp = m.campaign
	var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
	if hud != null and hud.settings.path == UiSettings.DEFAULT_PATH:
		hud.settings = UiSettings.new("user://bot_campaign.cfg")
	var prog := Game.progress as Progress
	if prog != null:
		prog.autosave_enabled = false
		prog.path = "user://bot_campaign_save.cfg"
	_camp.enabled = true
	_camp.step_completed.connect(_on_step_done)
	_camp.step_failed.connect(_on_step_failed)
	_camp.chapter_completed.connect(_on_chapter_done)
	_camp.checkpoint_reached.connect(func(_cp: Dictionary) -> void: _checkpoints += 1)
	Game.start_new_game()
	if _look >= 0:
		_camp.start_chapter(_look, 0, true)
		var st := Game.story as Story
		if st != null:
			st.set_chapter(_look)
			st.skip_cards()
	_ready = true
	print("BOT_CAMPAIGN start: %d chapters in the data, runner enabled %s" % [CampaignData.count(), str(_camp.enabled)])


func _keep_alive() -> void:
	if is_instance_valid(_p):
		_p.invuln = 999.0
		_p.hp = _p.max_hp


## Look mode: never act, only make sure no card hides the screen and the first step has begun.
func _look_mode() -> void:
	var st := Game.story as Story
	if st != null and st.cards_active() and _frames % 20 == 0:
		st.skip_cards()


# --- the playthrough -------------------------------------------------------------------------------------------------

func _play(delta: float) -> void:
	if Game.state == &"win":
		_phase = &"win"
		_wait = 0.5
		return
	if Game.state == &"dead":
		Game.do_respawn()
		return
	if Game.state != &"play":
		return
	var st := Game.story as Story
	if st != null and st.cards_active():
		st.skip_cards()
		return
	if _camp.state == &"idle" and _expect_chapter >= CampaignData.count():
		_check_endless()
		return
	if _camp.state != &"active":
		_age = 0.0
		return
	if not _chapter_began.has(_camp.chapter_index):
		_chapter_began[_camp.chapter_index] = true
		if _camp.chapter_index != _expect_chapter:
			_fail("chapter %d began, expected %d" % [_camp.chapter_index + 1, _expect_chapter + 1])
		_steps_in_chapter = 0
	var key := "%d/%d" % [_camp.chapter_index, _camp.step_index]
	if key != _step_key:
		_step_key = key
		_age = 0.0
		_on_step_begin()
	_age += delta
	_act()


func _on_step_begin() -> void:
	_kinds_seen[_camp.kind] = true
	if _camp.hud_line() == "":
		_empty_lines += 1
	if _camp.waypoint().is_empty() and not InteriorGameplay.active and _camp.kind != &"escape":
		_fail("chapter %d step %d (%s) has no waypoint" % [_camp.chapter_index + 1, _camp.step_index + 1, _camp.kind])
	if not _camp.boss().is_empty():
		_boss_bars += 1


func _act() -> void:
	var k := _camp.kind
	var goal := _camp.pos
	match k:
		&"reach":
			if goal.is_finite() and not _natural_done():
				_goto(goal)
		&"kill_target":
			if _age > 1.0:
				for f: Variant in _camp.foes.duplicate():
					var d := f as Drone
					if d != null and is_instance_valid(d) and not d.dead:
						d.damage(1.0e6)
		&"chase":
			if _camp.car != null and is_instance_valid(_camp.car) and _age > 1.0 and not _camp.car.dead:
				_camp.car.damage(1.0e6)
		_:
			if goal.is_finite() and k != &"escape":
				_goto(goal)
	if k in SKIP_KINDS and _age > 1.5:
		_skip()
	elif _age > NATURAL_SECONDS and _camp.state == &"active":
		_skip()


func _natural_done() -> bool:
	return _camp.state != &"active"


func _goto(goal: Vector3) -> void:
	if InteriorGameplay.active:
		return
	var d := Vector2(_p.global_position.x - goal.x, _p.global_position.z - goal.z).length()
	if d > 3.0:
		_p.vehicle = null
		_p.teleport_to(Vector3(goal.x, goal.y + 0.4, goal.z))


func _skip() -> void:
	if _camp.skip_step():
		_skipped += 1
		_natural -= 1                     # _on_step_done counts every finished step as natural first


func _on_step_done(chapter: int, _index: int, _kind: StringName) -> void:
	_steps_in_chapter += 1
	_natural += 1
	var prog := Game.progress as Progress
	if prog != null and _steps_in_chapter < CampaignData.steps(chapter).size() and prog.checkpoint.is_empty():
		_fail("no checkpoint saved after step %d of chapter %d" % [_steps_in_chapter, chapter + 1])


func _on_step_failed(chapter: int, index: int, kind: StringName, why: String) -> void:
	_failed.append("chapter %d step %d %s: %s" % [chapter + 1, index + 1, kind, why])
	_fail("step failed: %s" % _failed.back())


func _on_chapter_done(chapter: int) -> void:
	var want := CampaignData.steps(chapter).size()
	if _steps_in_chapter != want:
		_fail("chapter %d finished with %d steps done, data has %d" % [chapter + 1, _steps_in_chapter, want])
	if chapter != _expect_chapter:
		_fail("chapter %d finished, expected %d" % [chapter + 1, _expect_chapter + 1])
	var prog := Game.progress as Progress
	if prog != null and not prog.checkpoint.is_empty():
		_fail("checkpoint not cleared after chapter %d" % (chapter + 1))
	_chapters_done.append(chapter)
	_expect_chapter = chapter + 1
	print("BOT_CAMPAIGN chapter %d '%s' done: %d steps, natural so far %d, skipped %d" % [chapter + 1, CampaignData.CAMPAIGN[chapter]["id"], _steps_in_chapter, _natural, _skipped])


func _win_screen(_delta: float) -> void:
	if _wait > 0.0:
		return
	if Game.state != &"win":
		_phase = &"play"
		return
	if _expect_chapter > CampaignData.count():
		_finish()
		return
	Game.do_next_sector()
	_phase = &"play"
	_age = 0.0
	_step_key = ""
	var st := Game.story as Story
	if st != null:
		st.skip_cards()


## The aftermath chapter has no scripted steps: the runner stays idle and the core hunt is the objective.
func _check_endless() -> void:
	if _endless_checked:
		return
	_wait = 0.0
	_endless_checked = true
	var m := Game.missions as Missions
	if _camp.state != &"idle":
		_fail("the runner is %s in the endless sector" % _camp.state)
	if not m.win_on_cores or m.cores.is_empty():
		_fail("the endless sector has no plain core hunt (win_on_cores %s, cores %d)" % [str(m.win_on_cores), m.cores.size()])
	_expect_chapter = CampaignData.count() + 1
	print("BOT_CAMPAIGN endless sector: runner idle, %d cores to hunt" % m.cores.size())
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var prog := Game.progress as Progress
	if _chapters_done.size() != CampaignData.count():
		_fail("only %d of %d chapters completed" % [_chapters_done.size(), CampaignData.count()])
	if prog != null and prog.unlocked < CampaignData.count():
		_fail("chapter select unlocked %d, expected at least %d" % [prog.unlocked, CampaignData.count()])
	for kind: StringName in [&"reach", &"enter_interior", &"escort", &"defend", &"hack", &"kill_target", &"chase", &"escape"]:
		if not _kinds_seen.has(kind):
			_fail("step kind %s never played" % kind)
	if _boss_bars < 3:
		_fail("boss bar shown on %d steps, expected the 3 boss steps" % _boss_bars)
	if _empty_lines > 0:
		_fail("HUD line was empty on %d step starts" % _empty_lines)
	if _checkpoints < 8:
		_fail("only %d checkpoints saved" % _checkpoints)
	print("BOT_CAMPAIGN summary: chapters %d/%d, steps natural %d + skipped %d, failures %d, boss bars %d, checkpoints %d, kinds %s, frames %d" % [
			_chapters_done.size(), CampaignData.count(), _natural, _skipped, _failed.size(), _boss_bars, _checkpoints, str(_kinds_seen.keys()), _frames])
	print("BOT_CAMPAIGN %s" % ("PASS" if _errors.is_empty() else "FAIL: " + "; ".join(_errors)))
