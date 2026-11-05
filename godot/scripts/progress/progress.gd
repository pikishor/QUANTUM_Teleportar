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
var cine_seen: Array[StringName] = []     ## one-time cinematics already shown (garage_reveal, teleporter_first); saved under [flags]
var contracts_done := 0
var contracts_failed := 0
var bosses_cleared: Array[int] = []      ## chapters whose Vael Overseer is down (saved)
var unlocked := 1                       ## chapters the chapter select offers (>= 1, saved, never lowered by a new campaign)
var checkpoint: Dictionary = {}          ## the running scripted chapter's checkpoint (see CampaignRunner), {} when none
var side_done := {}                      ## side mission id -> completions (saved in [side])
var side_best := {}                      ## side mission id -> best time in seconds (saved in [side])
var last_save_ok := false
var collectibles: Collectibles                  ## I2: the 30 shards (saved in [collectibles])
var hero := HeroLook.new()                      ## G2: suit, colour scheme and accent of the hero (saved in [hero])
var garage := Garage.new()                      ## E3 / E6: the player's own car (saved in [garage])
var achievements: Achievements                  ## I3: 25 achievements (saved in [achievements] and [ach_stats])

var _last_score := 0
var _frac := 0.0
var _in_score := false
var _continue_pending := false
var _select_pending := false            ## start_chapter() is starting a run that keeps the wallet (no continued flag: the saved interior is not resumed)
var continued := false                  ## the last new_game was a CONTINUE (scripts/interiors_gameplay/ resumes the saved interior)


func _init() -> void:
	collectibles = Collectibles.new()
	add_child(collectibles)
	achievements = Achievements.new()
	add_child(achievements)
	hero.changed.connect(_on_hero_look)
	achievements.unlocked.connect(_on_achievement_cosmetic)
	collectibles.changed.connect(func(_n: int) -> void: achievements.evaluate(); changed.emit())


func _ready() -> void:
	Game.progress = self
	add_to_group(&"progress")
	autosave_enabled = not Game.autostart
	achievements.enabled = not Game.autostart
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
		Gear.reset()
		SkillTree.reset()


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
		"hp": 1.0 + 0.10 * minf(c, 10.0),
		"extra": mini(int(c * 0.5), 3),
		"reward": (1.0 + 0.20 * minf(c, 10.0)) * Difficulty.mult("credits"),
		"time": maxf(0.7, 1.0 - 0.05 * c),
	}


## Enemy health factor of the current sector (EnemyManager.spawn applies it): 1.0 without a progress node.
static func enemy_hp_mult() -> float:
	var ch := 0
	if is_instance_valid(Game.story):
		ch = int(Game.story.get("chapter"))
	return float(difficulty(ch)["hp"]) * Difficulty.mult("hp")


## Boss health factor: the gentler boss curve times the difficulty setting.
static func boss_hp_mult() -> float:
	return Difficulty.boss_hp(Difficulty.story_chapter()) * Difficulty.mult("hp")


# --- hero look (G2) -------------------------------------------------------------------------------------------------

## An achievement's cosmetic is worn at once: the suit or colour scheme that waits for it is equipped (the look screen can change it back).
func _on_achievement_cosmetic(id: StringName) -> void:
	var cos := ""
	for d in Achievements.DEFS:
		if d[0] == id:
			cos = String(d[6])
	if cos == "":
		return
	var cl: Array = achievements.cosmetics
	for sid: StringName in HeroLook.SUIT_ORDER:
		if HeroLook.item_need("suit:%s" % sid) == cos:
			hero.equip_suit(sid, cl)
	for i in HeroLook.scheme_count():
		if HeroLook.item_need("scheme:%d" % i) == cos:
			hero.equip_scheme(i, cl)


func _on_hero_look() -> void:
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"body") is PlayerBody:
		(pl.get(&"body") as PlayerBody).apply_look(hero)
	changed.emit()
	if autosave_enabled:
		save_file()


## Buys an item ("suit:<id>", "scheme:<i>", "accent") with credits. False when it is free, earned by achievement, owned, unknown or too dear.
func buy_look(key: String) -> bool:
	var price := HeroLook.item_price(key)
	if price <= 0 or HeroLook.item_need(key) != "" or hero.owned.has(key) or not spend(price):
		return false
	hero.grant(key)
	purchased.emit(StringName(key), 1)
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


# --- wallet, shop ---------------------------------------------------------------------------------------------------

func add_credits(n: int) -> void:
	if n == 0:
		return
	if n > 0 and not _in_score:
		SkillTree.add_xp(int(float(n) / SkillTree.CREDITS_PER_XP))      # mission, contract and activity payouts
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


## Skill tree (SkillTree): points come from levelling; the shop's respec refunds every rank for credits.
func buy_skill(id: StringName) -> bool:
	if not SkillTree.buy(id):
		return false
	changed.emit()
	return true


func respec_skills() -> bool:
	var price := SkillTree.respec_price()
	if SkillTree.spent() == 0 or credits < price:
		return false
	credits -= price
	SkillTree.respec()
	changed.emit()
	return true


## Throwables and gadgets (Gear): bought with credits (reputation discount), equipped into the two slots, four saved loadouts.
func gear_price(id: StringName) -> int:
	var base := Economy.gear_price(id)
	return 0 if base <= 0 else maxi(5, int(roundf(float(base) * (1.0 - rep_discount(reputation)) / 5.0)) * 5)


func buy_gear(id: StringName) -> bool:
	if not (Gear.is_throwable(id) or Gear.is_gadget(id)) or Gear.is_owned(id) or credits < gear_price(id):
		return false
	credits -= gear_price(id)
	Gear.give(id)
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


## Equips an owned throwable / gadget (an unowned one is bought first). id "" empties the gadget slot.
func equip_gear(id: StringName) -> bool:
	if id != &"" and not Gear.is_owned(id) and not buy_gear(id):
		return false
	if not Gear.equip(id):
		return false
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


func save_loadout(i: int) -> bool:
	if not Gear.save_loadout(i):
		return false
	if autosave_enabled:
		save_file()
	return true


func apply_loadout(i: int) -> bool:
	if not Gear.apply_loadout(i):
		return false
	changed.emit()
	if autosave_enabled:
		save_file()
	return true


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


## A side mission was finished: pay, reputation, tally and best time.
func complete_side(mid: StringName, pay: int, rep: int, time: float) -> void:
	side_done[mid] = int(side_done.get(mid, 0)) + 1
	if not side_best.has(mid) or time < float(side_best[mid]):
		side_best[mid] = snappedf(time, 0.1)
	add_credits(pay)
	add_reputation(rep)
	if autosave_enabled:
		save_file()


# --- lifecycle ------------------------------------------------------------------------------------------------------

func new_campaign() -> void:
	credits = 0
	levels = Upgrades.set_levels({})
	reputation = 0
	sector = 0
	contracts_done = 0
	contracts_failed = 0
	bosses_cleared.clear()
	side_done.clear()
	side_best.clear()
	checkpoint.clear()
	collectibles.reset()
	achievements.reset()
	garage.reset()
	hero.reset()
	WeaponDefs.reset_unlocked()
	Attachments.reset()
	Gear.reset()
	SkillTree.reset()
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
	_frac += float(delta) * SCORE_TO_CREDITS * Difficulty.mult("credits")
	var whole := int(_frac)
	if whole > 0:
		_frac -= float(whole)
		_in_score = true                                    # kills already pay XP through the hit signal: the score-to-credits payout does not
		add_credits(whole)
		_in_score = false
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


## DEMO MODE (scripts/demo/demo_mode.gd): starts a run that keeps the wallet, weapons and unlocks just granted (no new campaign, no scripted chapter).
func begin_sandbox_run() -> void:
	_select_pending = true
	_continue_pending = false
	Game.start_new_game()
	_select_pending = false
	sector = 0
	checkpoint.clear()
	_apply_to_player()


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
		"best": maxi(best, Game.score), "tutorial_done": tutorial_done, "cine_seen": cine_seen.duplicate(), "ammo_type": ammo_type, "contracts_done": contracts_done, "contracts_failed": contracts_failed,
		"unlocked": unlocked, "checkpoint": checkpoint.duplicate(), "weather": Weather.current,
	}


## A saved value as an Array whatever it was (a damaged file may hold a string, a number or nothing).
static func _arr(v: Variant) -> Array:
	if v is Array or v is PackedStringArray or v is PackedInt32Array or v is PackedInt64Array:
		return Array(v)
	return []


## A saved value as a finite int, `d` when it is not a number.
static func _num(v: Variant, d := 0) -> int:
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(v)
	return d


## Loads `p` into a ConfigFile; null for a missing, empty, truncated or foreign file (never raises).
static func _read(p: String) -> ConfigFile:
	var cf := ConfigFile.new()
	if cf.load(p) != OK:
		return null
	return cf


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
	var cs := PackedStringArray()
	for c: StringName in d["cine_seen"]:
		cs.append(String(c))
	cf.set_value("flags", "cine_seen", cs)
	cf.set_value("weapons", "ammo_type", int(d["ammo_type"]))
	cf.set_value("weather", "state", String(d["weather"]))
	var names := PackedStringArray()
	for id: StringName in WeaponDefs.unlocked:
		names.append(String(id))
	cf.set_value("weapons", "unlocked", names)
	cf.set_value("weapons", "current", String(WeaponDefs.last_used))
	var att := Attachments.to_save()
	cf.set_value("attachments", "owned", att["owned"])
	cf.set_value("attachments", "equipped", att["equipped"])
	var gd0 := Gear.to_save()
	for gk: String in gd0:
		cf.set_value("gear", gk, gd0[gk])
	var sk := SkillTree.to_save()
	for sk_k: String in sk:
		cf.set_value("skills", sk_k, sk[sk_k])
	cf.set_value("campaign", "bosses", PackedInt32Array(bosses_cleared))
	cf.set_value("campaign", "unlocked", unlocked)
	cf.set_value("collectibles", "got", collectibles.to_save())
	var hd := hero.to_save()
	for hk: String in hd:
		cf.set_value("hero", hk, hd[hk])
	var ad := achievements.to_save()
	cf.set_value("achievements", "done", ad["done"])
	cf.set_value("achievements", "cosmetics", ad["cosmetics"])
	for k: String in ad["stats"]:
		cf.set_value("ach_stats", k, ad["stats"][k])
	if garage.has_car():
		var gd := garage.to_save()
		cf.set_value("garage", "kind", gd["kind"])
		cf.set_value("garage", "paint", gd["paint"])
		for st in Garage.STATS:
			cf.set_value("garage", "lv_%s" % st, garage.level(st))
	for sid: StringName in side_done:
		cf.set_value("side", "done_%s" % sid, int(side_done[sid]))
		if side_best.has(sid):
			cf.set_value("side", "best_%s" % sid, float(side_best[sid]))
	if not checkpoint.is_empty():
		cf.set_value("checkpoint", "chapter", int(checkpoint.get("chapter", 0)))
		cf.set_value("checkpoint", "step", int(checkpoint.get("step", 0)))
		cf.set_value("checkpoint", "pos", checkpoint.get("pos", Vector3.ZERO))
		cf.set_value("checkpoint", "tp", bool(checkpoint.get("tp", false)))
		if checkpoint.get("goal", null) is Vector3:
			cf.set_value("checkpoint", "goal", checkpoint["goal"])
	var tmp := path + ".tmp"                                      # write beside, then swap in: a kill mid-write never leaves a half file as the save
	last_save_ok = cf.save(tmp) == OK
	if last_save_ok:
		var g_tmp := ProjectSettings.globalize_path(tmp)
		var g_dst := ProjectSettings.globalize_path(path)
		if DirAccess.rename_absolute(g_tmp, g_dst) != OK:
			last_save_ok = cf.save(path) == OK
			DirAccess.remove_absolute(g_tmp)
	if last_save_ok:
		saved.emit()
	return last_save_ok


## True when `path` holds a usable save of this version with progress worth continuing (a sector past 0, credits, upgrades or reputation).
func has_save() -> bool:
	var cf := _read(path)
	if cf == null or _num(cf.get_value("meta", "version", 0)) != SAVE_VERSION:
		return false
	if _num(cf.get_value("campaign", "sector", 0)) > 0 or _num(cf.get_value("wallet", "credits", 0)) > 0 or _num(cf.get_value("wallet", "reputation", 0)) != 0:
		return true
	if _num(cf.get_value("checkpoint", "step", 0)) > 0:
		return true
	for id: StringName in Upgrades.IDS:
		if _num(cf.get_value("upgrades", String(id), 0)) > 0:
			return true
	return _arr(cf.get_value("weapons", "unlocked", PackedStringArray(["carbine"]))).size() > 1


## Loads the file into this node (and the static Upgrades state). Returns false (and changes nothing) for a missing, foreign or damaged file.
func load_file() -> bool:
	var cf := _read(path)
	if cf == null or _num(cf.get_value("meta", "version", 0)) != SAVE_VERSION:
		return false
	credits = maxi(0, _num(cf.get_value("wallet", "credits", 0)))
	reputation = clampi(_num(cf.get_value("wallet", "reputation", 0)), REP_MIN, REP_MAX)
	var lv := {}
	for id: StringName in Upgrades.IDS:
		lv[id] = _num(cf.get_value("upgrades", String(id), 0))
	levels = Upgrades.set_levels(lv)
	sector = clampi(_num(cf.get_value("campaign", "sector", 0)), 0, 99)
	best = maxi(0, _num(cf.get_value("campaign", "best", 0)))
	contracts_done = maxi(0, _num(cf.get_value("campaign", "contracts_done", 0)))
	contracts_failed = maxi(0, _num(cf.get_value("campaign", "contracts_failed", 0)))
	tutorial_done = bool(cf.get_value("flags", "tutorial_done", false))
	cine_seen.clear()
	for c in _arr(cf.get_value("flags", "cine_seen", PackedStringArray())):
		cine_seen.append(StringName(str(c)))
	ammo_type = clampi(_num(cf.get_value("weapons", "ammo_type", 0)), 0, WeaponDefs.AMMO_TYPES.size() - 1)
	WeaponDefs.set_unlocked(_arr(cf.get_value("weapons", "unlocked", PackedStringArray(["carbine"]))))
	var cur := StringName(str(cf.get_value("weapons", "current", "carbine")))
	WeaponDefs.last_used = cur if WeaponDefs.is_unlocked(cur) else &"carbine"
	Attachments.from_save({"owned": _arr(cf.get_value("attachments", "owned", PackedStringArray())), "equipped": cf.get_value("attachments", "equipped", {}) if cf.get_value("attachments", "equipped", {}) is Dictionary else {}})
	var gear_d := {}
	if cf.has_section("gear"):
		for gk in cf.get_section_keys("gear"):
			gear_d[gk] = cf.get_value("gear", gk)
	Gear.from_save(gear_d)                                  # older saves have no [gear] section: defaults
	var skill_d := {}
	if cf.has_section("skills"):
		for sk_k in cf.get_section_keys("skills"):
			skill_d[sk_k] = cf.get_value("skills", sk_k)
	SkillTree.from_save(skill_d)                            # older saves have no [skills] section: level 1, no ranks
	bosses_cleared.clear()
	for b: Variant in _arr(cf.get_value("campaign", "bosses", PackedInt32Array())):
		if b is int and int(b) >= 0 and int(b) < 99 and not bosses_cleared.has(int(b)):
			bosses_cleared.append(int(b))
	unlocked = clampi(maxi(_num(cf.get_value("campaign", "unlocked", 1)), sector + 1), 1, 99)     # a save from before the chapter select has no key: every chapter up to the saved sector
	checkpoint = _load_checkpoint(cf)
	collectibles.from_save(cf.get_value("collectibles", "got", PackedInt32Array()))
	var ast := {}
	if cf.has_section("ach_stats"):
		for k in cf.get_section_keys("ach_stats"):
			ast[k] = cf.get_value("ach_stats", k, 0)
	achievements.from_save({"done": _arr(cf.get_value("achievements", "done", PackedStringArray())), "cosmetics": _arr(cf.get_value("achievements", "cosmetics", PackedStringArray())), "stats": ast})
	var hd := {}
	if cf.has_section("hero"):
		for hk in cf.get_section_keys("hero"):
			hd[hk] = cf.get_value("hero", hk)
	hero.from_save(hd, achievements.cosmetics)
	var gd := {"kind": str(cf.get_value("garage", "kind", "")), "paint": cf.get_value("garage", "paint", Garage.DEFAULT_PAINT), "levels": {}}
	for st in Garage.STATS:
		gd["levels"][String(st)] = cf.get_value("garage", "lv_%s" % st, 0)
	garage.from_save(gd)
	side_done.clear()
	side_best.clear()
	for sid: StringName in SideMissions.ORDER:
		var n: Variant = cf.get_value("side", "done_%s" % sid, 0)
		if n is int and int(n) > 0:
			side_done[sid] = mini(int(n), 9999)
			var b: Variant = cf.get_value("side", "best_%s" % sid, 0.0)
			if (b is float or b is int) and float(b) > 0.0 and is_finite(float(b)):
				side_best[sid] = float(b)
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


## The saved ammo type index (PlayerWeapon.ammo_type reads it on spawn and writes it back through set_ammo_type).
var ammo_type := 0


func set_ammo_type(i: int) -> void:
	i = clampi(i, 0, WeaponDefs.AMMO_TYPES.size() - 1)
	if i != ammo_type:
		ammo_type = i
		_autosave()


## True once for each one-time cinematic id (and records it); false when it was already shown.
func mark_cine(id: StringName) -> bool:
	if cine_seen.has(id):
		return false
	cine_seen.append(id)
	_autosave()
	return true


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
