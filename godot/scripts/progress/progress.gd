class_name Progress
extends Node
## Campaign progress (Game.progress, child of Missions): the credit wallet, shop upgrades, reputation, the sector to resume, the best score and the tutorial flag,
## saved with ConfigFile in user://save.cfg (settings and the best score for the title live in user://settings.cfg, written by the HUD's UiSettings).
##
## Credits come from score gains (a kill or a core is worth 40 % of its score in credits) and from contract rewards (add_credits). The shop (buy) spends them on the
## six Upgrades; reputation (-25..100) moves the shop price and the contract payout. Autosave: when a sector is cleared, on pause, on death and when the tutorial ends
## (never under Game.autostart, i.e. tools / tests / bots, unless a test turns `autosave_enabled` on and points `path` at a temp file).
## Campaign extras (scripts/missions/campaign_runner.gd): `unlocked` (how many chapters the chapter select offers: kept through NEW GAME, saved as campaign/unlocked, older saves get sector + 1) and
## `checkpoint` (the scripted chapter's last checkpoint {chapter, step, pos, tp, goal?}, saved in the [checkpoint] section and cleared when the chapter ends). Both are new optional keys of
## SAVE_VERSION 1: files without them load as before, and builds that do not know them ignore them. start_chapter(i) (title / pause chapter select) replays an unlocked chapter keeping the wallet.
## Lifecycle: new_game starts a fresh campaign (credits, upgrades, reputation reset; the tutorial flag and the best score survive), continue_game() resumes the saved
## sector with its credits and upgrades. Upgrades go live through the static Upgrades class (also applied to the player's magazine on purchase).

signal changed
signal purchased(id: StringName, level: int)
signal saved
signal reputation_changed(rep: int)

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://save.cfg"
const SCORE_TO_CREDITS := 0.4
const REP_MIN := -25
const REP_MAX := 100
const REP_TIERS: Array[String] = ["SUSPECT", "UNKNOWN", "TRUSTED", "LEGEND"]

var path := DEFAULT_PATH
var autosave_enabled := false
var credits := 0
var levels := {}                        ## id -> level (mirrors Upgrades.levels)
var reputation := 0
var sector := 0                         ## chapter index "Continue" resumes at
var best := 0
var tutorial_done := false
var contracts_done := 0
var contracts_failed := 0
var bosses_cleared: Array[int] = []      ## chapters whose Vael Overseer is down (saved)
var unlocked := 1                       ## chapters the chapter select offers (>= 1, saved, never lowered by a new campaign)
var checkpoint: Dictionary = {}          ## the running scripted chapter's checkpoint (see CampaignRunner), {} when none
var last_save_ok := false

var _last_score := 0
var _frac := 0.0
var _continue_pending := false
var _select_pending := false            ## start_chapter() is starting a run that keeps the wallet (no continued flag: the saved interior is not resumed)
var continued := false                  ## the last new_game was a CONTINUE (scripts/interiors_gameplay/ resumes the saved interior)


func _ready() -> void:
	Game.progress = self
	add_to_group(&"progress")
	autosave_enabled = not Game.autostart
	if autosave_enabled:
		load_file()
	Game.new_game.connect(_on_new_game)
	Game.score_changed.connect(_on_score)
	Game.state_changed.connect(_on_state)
	Game.sector_cleared.connect(_on_cleared)
	Game.player_died.connect(_on_died)


func _exit_tree() -> void:
	if Game.progress == self:
		Game.progress = null
		Upgrades.reset()
		WeaponDefs.reset_unlocked()
		Attachments.reset()


# --- pure rules (static, tested) ------------------------------------------------------------------------------------

## 0 SUSPECT (< 0), 1 UNKNOWN (0..9), 2 TRUSTED (10..39), 3 LEGEND (40+).
static func rep_tier(rep: int) -> int:
	if rep < 0:
		return 0
	if rep < 10:
		return 1
	return 2 if rep < 40 else 3


static func rep_name(rep: int) -> String:
	return REP_TIERS[rep_tier(rep)]


## Shop price factor: SUSPECT pays 10 % more, TRUSTED gets 10 % off, LEGEND 20 % off.
static func rep_discount(rep: int) -> float:
	return [-0.10, 0.0, 0.10, 0.20][rep_tier(rep)]


## Contract payout factor: SUSPECT -10 %, TRUSTED +10 %, LEGEND +25 %.
static func rep_bonus(rep: int) -> float:
	return [-0.10, 0.0, 0.10, 0.25][rep_tier(rep)]


## Difficulty per sector (chapter index 0-based): enemy health, extra enemies per group, payout and time-limit factors.
static func difficulty(chapter: int) -> Dictionary:
	var c := float(maxi(chapter, 0))
	return {
		"hp": 1.0 + 0.10 * minf(c, 8.0),
		"extra": mini(int(c * 0.5), 3),
		"reward": 1.0 + 0.20 * minf(c, 8.0),
		"time": maxf(0.7, 1.0 - 0.05 * c),
	}


## Enemy health factor of the current sector (EnemyManager.spawn applies it): 1.0 without a progress node.
static func enemy_hp_mult() -> float:
	var ch := 0
	if is_instance_valid(Game.story):
		ch = int(Game.story.get("chapter"))
	return float(difficulty(ch)["hp"])


# --- wallet, shop ---------------------------------------------------------------------------------------------------

func add_credits(n: int) -> void:
	if n == 0:
		return
	credits = maxi(0, credits + n)
	changed.emit()


## Score that is not paid out in credits as well (a contract's bonus): the score-to-credits conversion skips it.
func bonus_score(n: int) -> void:
	_last_score += n
	Game.add_score(n)


func spend(n: int) -> bool:
	if n < 0 or n > credits:
		return false
	credits -= n
	changed.emit()
	return true


func level(id: StringName) -> int:
	return int(levels.get(id, 0))


func price(id: StringName) -> int:
	return Upgrades.price(id, level(id), rep_discount(reputation))


func can_buy(id: StringName) -> bool:
	if not id in Upgrades.IDS or level(id) >= Upgrades.MAX_LEVEL:
		return false
	return credits >= price(id)


## Buy the next level of an upgrade. Returns false at the top level, with too few credits or for an unknown id.
func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	credits -= price(id)
	_set_level(id, level(id) + 1)
	purchased.emit(id, level(id))
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


## A free level (contract reward). `id` empty = a random upgrade that is not maxed. Returns the id, or &"" when everything is maxed.
func grant_upgrade(id := &"", rng: RandomNumberGenerator = null) -> StringName:
	if id == &"" or level(id) >= Upgrades.MAX_LEVEL:
		var open: Array[StringName] = []
		for u: StringName in Upgrades.IDS:
			if level(u) < Upgrades.MAX_LEVEL:
				open.append(u)
		if open.is_empty():
			return &""
		var i := rng.randi() % open.size() if rng != null else randi() % open.size()
		id = open[i]
	_set_level(id, level(id) + 1)
	purchased.emit(id, level(id))
	changed.emit()
	return id


func _set_level(id: StringName, lvl: int) -> void:
	levels[id] = clampi(lvl, 0, Upgrades.MAX_LEVEL)
	levels = Upgrades.set_levels(levels)
	_apply_to_player(true)


## The magazine is the one upgrade that has to be pushed into live state (the others are read when used). `top_up` gives the new rounds at once (a purchase), otherwise the
## rounds are only clamped to the new size (a campaign reset).
func _apply_to_player(top_up := false) -> void:
	var p := Game.player
	if not is_instance_valid(p) or p.get(&"mag") == null:
		return
	var w: Variant = p.get(&"weapon")
	if w is PlayerWeapon:
		(w as PlayerWeapon).apply_upgrades(top_up)                 # every weapon's magazine follows its own base
		return
	var before := int(p.get(&"mag"))
	var size := Upgrades.mag_size()
	p.set(&"mag", size)
	var ammo := int(p.get(&"ammo"))
	p.set(&"ammo", ammo + maxi(size - before, 0) if top_up else mini(ammo, size))


## Weapons: the shop sells the three alien weapons (WeaponDefs.price, reputation discount); an owned weapon is saved with the campaign.
func weapon_price(id: StringName) -> int:
	return WeaponDefs.price(id, rep_discount(reputation))


## Attachments: bought with credits (reputation discount), equipped per weapon, saved in the "attachments" section.
func part_price(part: StringName) -> int:
	return Attachments.price(part, rep_discount(reputation))


func buy_part(part: StringName) -> bool:
	if not Attachments.PARTS.has(part) or Attachments.is_owned(part) or credits < part_price(part):
		return false
	credits -= part_price(part)
	Attachments.give(part)
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


## Equip (or take off) an owned part and make the weapon in hand pick up the new numbers.
func equip_part(weapon: StringName, part: StringName) -> bool:
	if not Attachments.toggle(weapon, part):
		return false
	var p := Game.player
	if is_instance_valid(p) and p.get(&"weapon") is PlayerWeapon:
		(p.get(&"weapon") as PlayerWeapon).apply_upgrades(false)
	if autosave_enabled:
		save_file()
	return true


func can_buy_weapon(id: StringName) -> bool:
	return WeaponDefs.DEFS.has(id) and id != &"carbine" and not WeaponDefs.is_unlocked(id) and credits >= weapon_price(id)


func buy_weapon(id: StringName) -> bool:
	if not can_buy_weapon(id):
		return false
	credits -= weapon_price(id)
	_give_weapon(id)
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


## Unlock a weapon for free (a boss drop, a pickup, the shop after paying); the player's weapon node learns about it at once.
func _give_weapon(id: StringName) -> void:
	var p := Game.player
	if is_instance_valid(p) and p.get(&"weapon") is PlayerWeapon:
		(p.get(&"weapon") as PlayerWeapon).grant(id)
	else:
		WeaponDefs.unlock(id)
	purchased.emit(id, 1)


func grant_weapon(id: StringName) -> bool:
	if WeaponDefs.is_unlocked(id) or not WeaponDefs.DEFS.has(id):
		return false
	_give_weapon(id)
	changed.emit()
	return true


func add_reputation(n: int) -> void:
	var before := reputation
	reputation = clampi(reputation + n, REP_MIN, REP_MAX)
	if reputation != before:
		reputation_changed.emit(reputation)
		changed.emit()


# --- lifecycle ------------------------------------------------------------------------------------------------------

func new_campaign() -> void:
	credits = 0
	levels = Upgrades.set_levels({})
	reputation = 0
	sector = 0
	contracts_done = 0
	contracts_failed = 0
	bosses_cleared.clear()
	checkpoint.clear()
	WeaponDefs.reset_unlocked()
	Attachments.reset()
	_frac = 0.0
	_apply_to_player()
	changed.emit()


func _on_new_game() -> void:
	_last_score = 0
	_frac = 0.0
	continued = _continue_pending
	if _continue_pending:
		_continue_pending = false
	elif _select_pending:
		_select_pending = false
	else:
		new_campaign()
		if autosave_enabled:
			save_file()


func _on_score(score: int) -> void:
	var delta := score - _last_score
	_last_score = score
	if delta <= 0:
		return
	_frac += float(delta) * SCORE_TO_CREDITS
	var whole := int(_frac)
	if whole > 0:
		_frac -= float(whole)
		add_credits(whole)
	best = maxi(best, score)


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else sector


func _on_state(s: StringName) -> void:
	if s == &"paused" or s == &"dead":
		sector = _chapter()
		unlock(sector)
		_autosave()


func _on_cleared() -> void:
	sector = _chapter() + 1
	unlock(sector)
	checkpoint.clear()
	_autosave()


func _on_died() -> void:
	best = maxi(best, Game.score)


func _autosave() -> void:
	if autosave_enabled:
		save_file()


# --- chapters, checkpoint -------------------------------------------------------------------------------------------

## Chapter `index` (0-based) and everything before it are selectable from now on.
func unlock(index: int) -> void:
	if index + 1 > unlocked:
		unlocked = clampi(index + 1, 1, 99)
		changed.emit()


## How many chapters the chapter select offers: unlocked ones, at most the story's chapters.
func chapters_unlocked() -> int:
	return mini(unlocked, CampaignRunner.chapter_count())


## The chapter select is worth showing from the second unlocked chapter on.
func can_select_chapter() -> bool:
	return chapters_unlocked() >= 2


## Stores the scripted chapter's checkpoint (the runner calls it after every step) and autosaves when saving is on.
func set_checkpoint(cp: Dictionary) -> void:
	checkpoint = cp.duplicate()
	if autosave_enabled:
		save_file()


func clear_checkpoint() -> void:
	if checkpoint.is_empty():
		return
	checkpoint.clear()
	if autosave_enabled:
		save_file()


## Title / pause chapter select: starts unlocked chapter `index` from its first step, keeping credits, upgrades, weapons and reputation. Only on the title or pause screen. False otherwise.
func start_chapter(index: int) -> bool:
	if Game.state != &"menu" and Game.state != &"paused":
		return false
	if index < 0 or index >= chapters_unlocked():
		return false
	_select_pending = true
	_continue_pending = false
	Game.start_new_game()
	_select_pending = false
	sector = index
	checkpoint.clear()
	_begin_chapter_run(index)
	if autosave_enabled:
		save_file()
	return true


## Shared by CONTINUE and the chapter select after the run has started: the story, the cores and the scripted steps go to chapter `chapter`.
func _begin_chapter_run(chapter: int, cp := {}) -> void:
	if is_instance_valid(Game.story) and Game.story.has_method(&"set_chapter"):
		Game.story.call(&"set_chapter", chapter)
	var m := Game.missions as Missions
	if m != null:
		m.rounds = chapter
		m.new_round(mini(Missions.CORE_MAX, 6 + chapter))
		if m.campaign != null and m.campaign.enabled:                 # off under tools / tests / bots (Game.autostart): they keep the plain core hunt
			if cp.is_empty() or not m.campaign.resume(cp):
				m.campaign.start_chapter(chapter)
	_apply_to_player()


# --- save / load ----------------------------------------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"version": SAVE_VERSION, "credits": credits, "levels": levels.duplicate(), "reputation": reputation, "sector": sector,
		"weapons": WeaponDefs.unlocked.duplicate(), "weapon": WeaponDefs.last_used, "attachments": Attachments.to_save(), "bosses": bosses_cleared.duplicate(),
		"best": maxi(best, Game.score), "tutorial_done": tutorial_done, "contracts_done": contracts_done, "contracts_failed": contracts_failed,
		"unlocked": unlocked, "checkpoint": checkpoint.duplicate(), "weather": Weather.current,
	}


func save_file() -> bool:
	var cf := ConfigFile.new()
	var d := snapshot()
	cf.set_value("meta", "version", SAVE_VERSION)
	cf.set_value("wallet", "credits", d["credits"])
	cf.set_value("wallet", "reputation", d["reputation"])
	for id: StringName in Upgrades.IDS:
		cf.set_value("upgrades", String(id), level(id))
	cf.set_value("campaign", "sector", d["sector"])
	cf.set_value("campaign", "best", d["best"])
	cf.set_value("campaign", "contracts_done", d["contracts_done"])
	cf.set_value("campaign", "contracts_failed", d["contracts_failed"])
	cf.set_value("flags", "tutorial_done", d["tutorial_done"])
	cf.set_value("weather", "state", String(d["weather"]))
	var names := PackedStringArray()
	for id: StringName in WeaponDefs.unlocked:
		names.append(String(id))
	cf.set_value("weapons", "unlocked", names)
	cf.set_value("weapons", "current", String(WeaponDefs.last_used))
	var att := Attachments.to_save()
	cf.set_value("attachments", "owned", att["owned"])
	cf.set_value("attachments", "equipped", att["equipped"])
	cf.set_value("campaign", "bosses", PackedInt32Array(bosses_cleared))
	cf.set_value("campaign", "unlocked", unlocked)
	if not checkpoint.is_empty():
		cf.set_value("checkpoint", "chapter", int(checkpoint.get("chapter", 0)))
		cf.set_value("checkpoint", "step", int(checkpoint.get("step", 0)))
		cf.set_value("checkpoint", "pos", checkpoint.get("pos", Vector3.ZERO))
		cf.set_value("checkpoint", "tp", bool(checkpoint.get("tp", false)))
		if checkpoint.get("goal", null) is Vector3:
			cf.set_value("checkpoint", "goal", checkpoint["goal"])
	last_save_ok = cf.save(path) == OK
	if last_save_ok:
		saved.emit()
	return last_save_ok


## True when `path` holds a usable save of this version with progress worth continuing (a sector past 0, credits, upgrades or reputation).
func has_save() -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK or int(cf.get_value("meta", "version", 0)) != SAVE_VERSION:
		return false
	if int(cf.get_value("campaign", "sector", 0)) > 0 or int(cf.get_value("wallet", "credits", 0)) > 0 or int(cf.get_value("wallet", "reputation", 0)) != 0:
		return true
	if int(cf.get_value("checkpoint", "step", 0)) > 0:
		return true
	for id: StringName in Upgrades.IDS:
		if int(cf.get_value("upgrades", String(id), 0)) > 0:
			return true
	return Array(cf.get_value("weapons", "unlocked", PackedStringArray(["carbine"]))).size() > 1


## Loads the file into this node (and the static Upgrades state). Returns false (and changes nothing) for a missing, foreign or damaged file.
func load_file() -> bool:
	var cf := ConfigFile.new()
	if cf.load(path) != OK or int(cf.get_value("meta", "version", 0)) != SAVE_VERSION:
		return false
	credits = maxi(0, int(cf.get_value("wallet", "credits", 0)))
	reputation = clampi(int(cf.get_value("wallet", "reputation", 0)), REP_MIN, REP_MAX)
	var lv := {}
	for id: StringName in Upgrades.IDS:
		lv[id] = int(cf.get_value("upgrades", String(id), 0))
	levels = Upgrades.set_levels(lv)
	sector = clampi(int(cf.get_value("campaign", "sector", 0)), 0, 99)
	best = maxi(0, int(cf.get_value("campaign", "best", 0)))
	contracts_done = maxi(0, int(cf.get_value("campaign", "contracts_done", 0)))
	contracts_failed = maxi(0, int(cf.get_value("campaign", "contracts_failed", 0)))
	tutorial_done = bool(cf.get_value("flags", "tutorial_done", false))
	WeaponDefs.set_unlocked(Array(cf.get_value("weapons", "unlocked", PackedStringArray(["carbine"]))))
	var cur := StringName(str(cf.get_value("weapons", "current", "carbine")))
	WeaponDefs.last_used = cur if WeaponDefs.is_unlocked(cur) else &"carbine"
	Attachments.from_save({"owned": Array(cf.get_value("attachments", "owned", PackedStringArray())), "equipped": cf.get_value("attachments", "equipped", {})})
	bosses_cleared.clear()
	for b: int in Array(cf.get_value("campaign", "bosses", PackedInt32Array())):
		bosses_cleared.append(b)
	unlocked = clampi(maxi(int(cf.get_value("campaign", "unlocked", 1)), sector + 1), 1, 99)     # a save from before the chapter select has no key: every chapter up to the saved sector
	checkpoint = _load_checkpoint(cf)
	var ws := StringName(str(cf.get_value("weather", "state", "rain")))
	if Weather.PRESETS.has(ws):
		var wn: Weather = Game.atmosphere.get(&"weather") if is_instance_valid(Game.atmosphere) else null
		if wn:
			wn.set_state(ws, true)
		else:
			Weather.pending = ws
	changed.emit()
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		var w := pl.get(&"weapon") as PlayerWeapon
		w.switch_to(WeaponDefs.last_used, true)
	return true


## The [checkpoint] section as a dictionary, {} when absent or damaged (wrong types or negative numbers).
static func _load_checkpoint(cf: ConfigFile) -> Dictionary:
	if not cf.has_section("checkpoint"):
		return {}
	var ch: Variant = cf.get_value("checkpoint", "chapter", -1)
	var st: Variant = cf.get_value("checkpoint", "step", -1)
	var at: Variant = cf.get_value("checkpoint", "pos", Vector2.ZERO)        # (a Vector2 default is no valid position: a missing key damages the section)
	if not (ch is int) or not (st is int) or int(ch) < 0 or int(st) < 0 or not (at is Vector3) or not (at as Vector3).is_finite():
		return {}
	var cp := {"chapter": int(ch), "step": int(st), "pos": at, "tp": bool(cf.get_value("checkpoint", "tp", false))}
	var g: Variant = cf.get_value("checkpoint", "goal", Vector2.ZERO)
	if g is Vector3 and (g as Vector3).is_finite():
		cp["goal"] = g
	return cp


func mark_tutorial_done() -> void:
	if not tutorial_done:
		tutorial_done = true
		_autosave()


## CONTINUE on the title screen: starts a run at the saved sector with the saved credits, upgrades and reputation. Returns false without a save.
func continue_game() -> bool:
	if Game.state != &"menu":
		return false
	if not load_file() and autosave_enabled:
		return false
	_continue_pending = true
	var cp := checkpoint.duplicate()
	Game.start_new_game()
	_continue_pending = false
	var chapter := sector
	checkpoint = cp if int(cp.get("chapter", -1)) == chapter else {}          # a checkpoint of another chapter is stale (the chapter select replayed one)
	_begin_chapter_run(chapter, checkpoint)
	return true
