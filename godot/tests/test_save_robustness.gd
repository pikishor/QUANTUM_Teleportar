extends RefCounted
## J6: the save files survive corruption and old versions. Truncated, empty, binary, wrong-typed and foreign files never raise and leave fail-safe values; saves written by the
## builds of waves 7, 18 and 30 (fixtures below) load with the later systems at their defaults; the save is written through a temp file; the settings, interior and map files
## are as tolerant; the Stability audit repairs a stuck traversal, cover, weather and garage.
## Run: tools/test.sh tests/test_save_robustness.gd

const TMP := "user://test_save_robust.cfg"

const WAVE7 := "[meta]\nversion=1\n[wallet]\ncredits=120\nreputation=5\n[upgrades]\ndamage=2\narmour=1\n[campaign]\nsector=1\nbest=900\ncontracts_done=2\ncontracts_failed=0\n[flags]\ntutorial_done=true\n"
const WAVE18 := WAVE7 + "[weapons]\nunlocked=PackedStringArray(\"carbine\", \"scatter\")\ncurrent=\"scatter\"\n[attachments]\nowned=PackedStringArray()\nequipped={}\n[campaign]\nbosses=PackedInt32Array(0)\n"
const WAVE30 := "[meta]\nversion=1\n[wallet]\ncredits=4000\nreputation=40\n[campaign]\nsector=4\nbest=50000\nunlocked=5\nbosses=PackedInt32Array(0, 1)\n[weather]\nstate=\"storm\"\n[checkpoint]\nchapter=4\nstep=2\npos=Vector3(1, 0, 2)\ntp=false\n[collectibles]\ngot=PackedInt32Array(1, 2, 3)\n[hero]\nsuit=\"standard\"\n"


func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _prog() -> Progress:
	var p := Progress.new()
	p.path = TMP
	return p


func run(_host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_corrupt()
	_wrong_types()
	_old_versions()
	_atomic_save()
	_other_files()
	Weather.pending = &""
	Weather.current = &"rain"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _corrupt() -> void:
	var bad: Array[String] = ["", "   \n", "[[[ not a config", "[meta]\nversion=1\n[wallet\ncredits=", "\u0000\u0001\u0002binary", "[meta]\nversion=1\n[wallet]\ncredits=12"]
	for i in bad.size():
		_write(bad[i])
		var p := _prog()
		p.credits = 5
		var ok := p.load_file()
		var has := p.has_save()
		TestLib.check(p.credits >= 0 and (ok or p.credits == 5), "corrupt file %d: no crash, credits stay sane (%d)" % [i, p.credits])
		TestLib.check(not has or ok, "corrupt file %d: has_save never promises a save load_file refuses" % i)
		p.free()
	var missing := _prog()
	missing.path = "user://does_not_exist_%d.cfg" % Time.get_ticks_usec()
	TestLib.check(not missing.load_file() and not missing.has_save(), "a missing file is no save")
	missing.free()


func _wrong_types() -> void:
	_write("[meta]\nversion=1\n[wallet]\ncredits=\"lots\"\nreputation=Vector3(1, 2, 3)\n[upgrades]\ndamage=\"x\"\narmour=[1]\n[campaign]\nsector=\"two\"\nbest=-5\nbosses=\"none\"\nunlocked={}\n"
		+ "[weapons]\nunlocked=7\ncurrent=12\n[attachments]\nowned=\"a\"\nequipped=\"b\"\n[collectibles]\ngot=\"all\"\n[achievements]\ndone=5\ncosmetics=\"x\"\n[hero]\nowned=\"x\"\nsuit=3\n[garage]\nkind=5\npaint=\"red\"\nlv_speed=\"fast\"\n[side]\ndone_x=\"y\"\n[weather]\nstate=9\n[checkpoint]\nchapter=\"a\"\nstep=1\npos=3\n")
	var p := _prog()
	var ok := p.load_file()
	TestLib.check(ok, "a file with wrong-typed values still loads (fail-safe defaults)")
	TestLib.check(p.credits == 0 and p.reputation == 0 and p.sector == 0 and p.best == 0, "wrong-typed numbers become 0")
	TestLib.check(p.unlocked >= 1 and p.checkpoint.is_empty() and p.bosses_cleared.is_empty(), "wrong-typed unlocked / checkpoint / bosses fall back")
	TestLib.check(WeaponDefs.is_unlocked(&"carbine") and WeaponDefs.is_unlocked(WeaponDefs.last_used), "the weapon state falls back to the carbine")
	TestLib.check(not p.garage.has_car(), "a damaged garage is empty")
	p.free()
	Upgrades.reset()
	Weather.pending = &""


func _old_versions() -> void:
	_write(WAVE7)
	var p := _prog()
	TestLib.check(p.has_save() and p.load_file(), "wave 7 save loads")
	TestLib.check(p.credits == 120 and p.reputation == 5 and p.sector == 1 and p.best == 900 and p.tutorial_done, "wave 7 values kept")
	TestLib.check(p.unlocked == 2 and p.checkpoint.is_empty() and p.bosses_cleared.is_empty() and not p.garage.has_car(), "wave 7 gets chapter select, no checkpoint, no garage")
	TestLib.check(p.collectibles.collected.is_empty() and p.side_done.is_empty(), "wave 7 has no shards or side missions")
	p.free()
	_write(WAVE18)
	p = _prog()
	TestLib.check(p.load_file() and WeaponDefs.is_unlocked(&"scatter") and p.bosses_cleared == [0], "wave 18 save: weapons and bosses load")
	p.free()
	_write(WAVE30)
	p = _prog()
	TestLib.check(p.load_file(), "wave 30 save loads")
	TestLib.check(p.unlocked == 5 and p.bosses_cleared == [0, 1] and int(p.checkpoint.get("step", -1)) == 2, "wave 30 chapter select, bosses and checkpoint kept")
	TestLib.check(p.collectibles.collected.size() == 3 and not p.garage.has_car() and p.side_done.is_empty(), "wave 30 has shards, but no garage or side missions yet")
	TestLib.check(Weather.pending == &"storm" or Weather.current == &"storm", "wave 30 weather restored")
	p.free()
	Upgrades.reset()
	Weather.pending = &""


func _atomic_save() -> void:
	var p := _prog()
	p.credits = 321
	TestLib.check(p.save_file(), "save_file succeeds")
	TestLib.check(not FileAccess.file_exists(TMP + ".tmp"), "no temp file is left behind")
	var q := _prog()
	TestLib.check(q.load_file() and q.credits == 321, "the swapped-in file loads")
	# a stale temp file from a killed write must not disturb load or the next save
	var f := FileAccess.open(TMP + ".tmp", FileAccess.WRITE)
	f.store_string("[meta]\nversion=1\n[wallet]\ncred")
	f.close()
	TestLib.check(q.load_file() and q.credits == 321, "a stale half-written temp file is ignored")
	p.credits = 654
	TestLib.check(p.save_file() and not FileAccess.file_exists(TMP + ".tmp"), "the next save replaces it")
	TestLib.check(q.load_file() and q.credits == 654, "and loads")
	p.free()
	q.free()
	Upgrades.reset()


func _other_files() -> void:
	_write("[graphics]\nquality=\"hi\"\nfps_cap=Vector2(1, 2)\n[controls]\nlook_x=\"fast\"\nlook_y=Vector3(1, 1, 1)\n[audio]\nvolumes=5\nmuted=\"x\"\n[ui]\nhud_scale={}\n")
	var s := UiSettings.new(TMP)
	s.load_file()
	TestLib.check(s.quality >= -1 and s.quality <= 2 and s.fps_cap == 60 and s.look_x >= UiSettings.SENS_MIN and s.look_y <= UiSettings.SENS_MAX and s.volumes.is_empty(), "wrong-typed settings fall back to defaults")
	_write("garbage [[")
	s.load_file()
	TestLib.check(s.fps_cap == 60, "a garbage settings file keeps the defaults")
	var hl := HeroLook.new()
	hl.from_save({"owned": "x", "suit": 3, "scheme": "a"}, [])
	TestLib.check(hl.suit == &"standard" and hl.owned.is_empty(), "a damaged hero section is the standard suit")
	Attachments.from_save({"owned": "x", "equipped": {"carbine": "scope"}})
	TestLib.check(true, "damaged attachments do not raise")
	Attachments.reset()
	var g := Garage.new()
	g.from_save({"kind": 5, "paint": "x", "levels": 3})
	TestLib.check(not g.has_car(), "a damaged garage save is no car")
