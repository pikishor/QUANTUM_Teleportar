extends RefCounted
## Save safety: version 2 header and migration of version 1 fixtures (waves 7, 18, 30, 50, 65), backup fallback, corrupt / partial files, atomic writes, first launch,
## a failed write keeping the old file, and RESET PROGRESS (two presses, title only).
## Run: tools/test.sh tests/test_save_migration2.gd

const TMP := "user://test_save_mig2.cfg"
const BAD := "user://test_save_mig2.cfg/sub/x.cfg"          # its parent is a file: no directory can be made

const W7 := "[meta]\nversion=1\n[wallet]\ncredits=120\nreputation=5\n[upgrades]\ndamage=2\n[campaign]\nsector=1\nbest=900\n[flags]\ntutorial_done=true\n"
const W18 := W7 + "[weapons]\nunlocked=PackedStringArray(\"carbine\", \"scatter\")\ncurrent=\"scatter\"\n"
const W30 := "[meta]\nversion=1\n[wallet]\ncredits=4000\nreputation=40\n[campaign]\nsector=4\nbest=50000\nunlocked=5\nbosses=PackedInt32Array(0, 1)\n[collectibles]\ngot=PackedInt32Array(1, 2, 3)\n"
## Waves 50 and 65 are REAL files: tests/fixtures/save_wave*.cfg were written by the actual Progress.save_file() checked out at git 645a3fb (wave 50) and b68e2a1 (wave 65)
## (a throw-away worktree, a script setting the same fields, see docs/QA.md "Save fixtures"). Sections of later waves (factions, companion, safehouses, heists, arena)
## did not exist at those revisions, so W_LATE stays hand-written: it is the only hand-written fixture left.
const F50 := "res://tests/fixtures/save_wave50.cfg"
const F65 := "res://tests/fixtures/save_wave65.cfg"
const W_LATE := W30 + "[side]\ndone_courier=3\nbest_courier=41.5\n[faction]\nrep_vael=-30.0\n[companion]\nmet=1\n[safehouse]\nown_loft=1\nlv_loft_bench=1\nsave_at=\"loft\"\n[heist]\ndone_vault=2\n[arena]\nclear_normal=1\nruns=4\nwave_best=9\n"


static func _text(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _rm(p: String) -> void:
	for f: String in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _prog() -> Progress:
	var p := Progress.new()
	p.path = TMP
	return p


func run(host: Node) -> void:
	_rm(TMP)
	_migrate()
	_backup()
	_partial()
	_failed_write()
	_first_launch()
	_low_storage(host)
	_reset(host)
	_rm(TMP)
	Upgrades.reset()
	Weather.pending = &""
	Weather.current = &"rain"


func _migrate() -> void:
	TestLib.check(Progress.SAVE_VERSION >= 2, "save version is 2 or later")
	for fx: Array in [["w7", W7], ["w18", W18], ["w30", W30], ["w50", _text(F50)], ["w65", _text(F65)]]:
		_write(TMP, fx[1])
		var p := _prog()
		TestLib.check(p.has_save() and p.load_file(), "%s fixture loads" % fx[0])
		TestLib.check(p.credits > 0 and p.unlocked >= p.sector + 1, "%s keeps credits and chapter select" % fx[0])
		p.save_file()
		var cf := ConfigFile.new()
		cf.load(TMP)
		TestLib.check(int(cf.get_value("meta", "version", 0)) == Progress.SAVE_VERSION, "%s is rewritten at the current version" % fx[0])
		var q := _prog()
		TestLib.check(q.load_file() and q.credits == p.credits and q.sector == p.sector, "%s survives a second round trip" % fx[0])
		p.free()
		q.free()
		_rm(TMP)
	TestLib.check(_text(F50).contains("credits=4000") and _text(F65).contains("[gear]"), "the real wave 50 / 65 fixtures are present")
	_write(TMP, W_LATE)
	var p65 := _prog()
	p65.load_file()
	TestLib.check(p65.side_done.get(&"courier", 0) == 3 and p65.companion_met and p65.safehouses_owned.has(&"loft") and int(p65.heist_done.get(&"vault", 0)) == 2, "later sections load")
	TestLib.check(float(p65.faction_rep.get(&"vael", 0.0)) < 0.0 and int(p65.arena.get("clear_normal", 0)) == 1 and int(p65.arena.get("runs", 0)) == 4, "later factions and arena load")
	p65.free()
	_write(TMP, "[meta]\nversion=99\n[wallet]\ncredits=5\n")
	var pn := _prog()
	TestLib.check(not pn.load_file() and not pn.has_save(), "a save from a newer build is not loaded (and not guessed at)")
	pn.free()
	_write(TMP, "[meta]\nversion=0\n[wallet]\ncredits=5\n")
	pn = _prog()
	TestLib.check(not pn.load_file(), "a headerless save is foreign")
	pn.free()
	_rm(TMP)
	Upgrades.reset()
	Weather.pending = &""


func _backup() -> void:
	var p := _prog()
	p.credits = 111
	TestLib.check(p.save_file() and not FileAccess.file_exists(TMP + ".bak"), "first save has no backup yet")
	p.credits = 222
	TestLib.check(p.save_file() and FileAccess.file_exists(TMP + ".bak"), "second save keeps the previous file as .bak")
	_write(TMP, "[[ garbage")
	var q := _prog()
	TestLib.check(q.has_save() and q.load_file() and q.credits == 111, "a damaged main file falls back to the backup")
	q.credits = 333
	TestLib.check(q.save_file(), "saving after a fallback works")
	var cf := ConfigFile.new()
	TestLib.check(cf.load(TMP + ".bak") == OK and int(cf.get_value("wallet", "credits", 0)) == 111, "a damaged main file never replaces a good backup")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var r := _prog()
	TestLib.check(r.load_file() and r.credits == 111, "a deleted main file also falls back")
	p.free()
	q.free()
	r.free()
	_rm(TMP)
	Upgrades.reset()


func _partial() -> void:
	var cuts: Array[String] = [W_LATE.substr(0, 40), W_LATE.substr(0, W_LATE.length() / 2), W_LATE.substr(0, W_LATE.length() - 7), W_LATE + "\n[arena\nruns="]
	for i in cuts.size():
		_write(TMP, cuts[i])
		var p := _prog()
		p.credits = 7
		var ok := p.load_file()
		TestLib.check(p.credits >= 0 and (ok or p.credits == 7) and (not p.has_save() or ok), "partial file %d: no crash, sane state" % i)
		p.free()
	_rm(TMP)
	Upgrades.reset()


func _failed_write() -> void:
	var p := _prog()
	p.credits = 50
	p.save_file()
	var before := FileAccess.get_file_as_string(TMP)
	p.path = "user://no_such_dir_mig2/x/save.cfg"                    # the directory is created on the fly (first launch)
	TestLib.check(p.save_file(), "a missing directory is created")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://no_such_dir_mig2/x/save.cfg"))
	p.path = BAD                                 # not writable: the save fails cleanly
	var failed := [false]
	p.save_failed.connect(func() -> void: failed[0] = true)
	TestLib.check(not p.save_file() and not p.last_save_ok and failed[0], "an unwritable target fails cleanly and signals")
	TestLib.check(FileAccess.get_file_as_string(TMP) == before, "the old file is untouched")
	var cf := ConfigFile.new()
	TestLib.check(not Progress.write_atomic(cf, BAD), "write_atomic reports failure")
	TestLib.check(not FileAccess.file_exists(TMP + ".tmp"), "no temp left behind")
	p.free()
	_rm(TMP)
	Upgrades.reset()


func _low_storage(host: Node) -> void:
	var p := _prog()
	p.credits = 10
	TestLib.check(p.save_file(), "first write")
	p.credits = 20
	Progress.inject_full = 1                      # the first temp write fails like a full disk
	TestLib.check(p.save_file() and not FileAccess.file_exists(TMP + ".bak") and not FileAccess.file_exists(TMP + ".tmp"), "a full disk drops the backup and retries once")
	var q := _prog()
	TestLib.check(q.load_file() and q.credits == 20, "the retried save is the new one")
	p.credits = 30
	Progress.inject_full = 2                      # both attempts fail: the live file stays, no partial files
	var failed := [0]
	p.save_failed.connect(func() -> void: failed[0] += 1)
	TestLib.check(not p.save_file(), "no space at all fails")
	TestLib.check(not FileAccess.file_exists(TMP + ".tmp") and not FileAccess.file_exists(TMP + ".bak.tmp"), "no partial file is left")
	Progress.inject_full = 0
	var r := _prog()
	TestLib.check(r.load_file() and r.credits == 20, "the live file survived")
	# a failure streak toasts once, not for every pickup
	Progress.inject_full = 5
	p.save_file()
	p.save_file()
	p.save_file()
	Progress.inject_full = 0
	TestLib.check(failed[0] == 1, "one failure notice per streak (%d)" % failed[0])
	TestLib.check(p.save_file() and p._fail_streak == 0, "a good write ends the streak")
	# the backup rotates at most every bak_gap_s
	_rm(TMP)
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", Progress.SAVE_VERSION)
	cf.set_value("wallet", "credits", 1)
	TestLib.check(Progress.write_atomic(cf, TMP, 60) and not FileAccess.file_exists(TMP + ".bak"), "first write has nothing to back up")
	cf.set_value("wallet", "credits", 2)
	Progress.write_atomic(cf, TMP, 60)
	cf.set_value("wallet", "credits", 3)
	Progress.write_atomic(cf, TMP, 60)
	var bk := ConfigFile.new()
	bk.load(TMP + ".bak")
	TestLib.check(int(bk.get_value("wallet", "credits", 0)) == 1, "a fresh backup is kept for the gap (not rewritten every save)")
	cf.set_value("wallet", "credits", 4)
	Progress.write_atomic(cf, TMP, 0)
	bk.load(TMP + ".bak")
	TestLib.check(int(bk.get_value("wallet", "credits", 0)) == 3, "gap 0 rotates every write")
	# soft saves coalesce in the live game and flush on exit
	_rm(TMP)
	var s := _prog()
	host.add_child(s)
	s.autosave_enabled = true
	s.save_gap_ms = 60000
	s.credits = 5
	s.soft_save()
	TestLib.check(FileAccess.file_exists(TMP), "the first soft save writes at once")
	s.credits = 6
	s.soft_save()
	s.soft_save()
	TestLib.check(s._save_pending, "later soft saves inside the gap are queued")
	var t := _prog()
	TestLib.check(t.load_file() and t.credits == 5, "nothing was written inside the gap")
	host.remove_child(s)
	var u := _prog()
	TestLib.check(u.load_file() and u.credits == 6, "the queued save is flushed when the node leaves the tree")
	s.free()
	t.free()
	u.free()
	p.free()
	q.free()
	r.free()
	_rm(TMP)
	Upgrades.reset()


func _first_launch() -> void:
	var p := Progress.new()
	p.path = "user://first_launch_%d.cfg" % Time.get_ticks_usec()
	TestLib.check(not p.has_save() and not p.load_file(), "first launch: no save, no error")
	TestLib.check(p.credits == 0 and p.unlocked >= 1, "first launch keeps the defaults")
	p.free()


func _reset(host: Node) -> void:
	var p := _prog()
	host.add_child(p)
	var old_state: StringName = Game.state
	p.credits = 900
	p.sector = 3
	p.unlocked = 4
	p.tutorial_done = true
	p.best = 1234
	p.companion_met = true
	p.safehouses_owned.append(&"loft")
	p.faction_rep[&"vael"] = -50.0
	p.heist_done[&"vault"] = 1
	p.arena["runs"] = 3
	p.side_done[&"courier"] = 2
	p.save_file()
	p.save_file()
	var side := "user://map.cfg"
	var had_map := FileAccess.file_exists(side)
	TestLib.check(OptionsScreen.PAGE2.has(&"opt_reset") and OptionsScreen.PAGE2.size() <= OptionsScreen.PAGE_CELL and OptionsScreen.is_option(&"opt_reset"), "RESET PROGRESS sits on options page 2")
	var st := UiSettings.new("user://test_mig2_settings.cfg")
	Game.state = &"play"
	TestLib.check(not OptionsScreen.press(st, &"opt_reset") and p.credits == 900, "not allowed during play")
	Game.state = &"menu"
	TestLib.check(OptionsScreen.press(st, &"opt_reset") and OptionsScreen.reset_armed and p.credits == 900, "first press only arms it")
	TestLib.check(OptionsScreen.label(st, &"opt_reset").begins_with("TAP AGAIN") or Tr.t("TAP AGAIN: ERASE ALL") != "", "the label asks for a confirm")
	OptionsScreen.press(st, &"opt_lang")
	st.language = "en"
	TestLib.check(not OptionsScreen.reset_armed, "any other press disarms it")
	OptionsScreen.press(st, &"opt_reset")
	OptionsScreen.press(st, &"opt_reset")
	TestLib.check(not OptionsScreen.reset_armed and p.credits == 0 and p.sector == 0 and p.unlocked == 1 and not p.tutorial_done and p.best == 0, "second press wipes the wallet and flags")
	TestLib.check(not p.companion_met and p.safehouses_owned.is_empty() and p.faction_rep.is_empty() and p.heist_done.is_empty() and p.arena.is_empty() and p.side_done.is_empty(), "and every later section")
	TestLib.check(not FileAccess.file_exists(TMP) and not FileAccess.file_exists(TMP + ".bak") and not p.has_save(), "the save and its backup are gone")
	if not had_map:
		TestLib.check(not FileAccess.file_exists(side), "no map file")
	Game.state = old_state
	OptionsScreen.reset_armed = false
	host.remove_child(p)
	p.free()
	_rm("user://test_mig2_settings.cfg")
	Upgrades.reset()
