extends SceneTree
## Headless balance estimate (no scene, no autoloads): time-to-kill and player survivability per chapter and difficulty from the constants.
## Run from godot/:  "$(tools/get_godot.sh)" --headless --path . -s res://tools/balance_sim.gd
## Model: the player lands HIT_RATE of the carbine's damage, gains PLAYER_GROWTH per chapter (weapons / upgrades), faces FOES operatives plus one boss in chapters 2, 5, 8.

const HIT_RATE := 0.45                  ## share of the player's rounds that land
const ENEMY_HIT := 0.35                 ## share of an operative's rounds that land
const FOES := 3
const PLAYER_GROWTH := 0.09             ## weapon and upgrade damage growth per chapter
const ARMOUR_GROWTH := 0.04             ## health / armour growth per chapter
const BOSS_CHAPTERS := {1: &"overseer", 4: &"overseer", 7: &"overseer"}
const CARBINE_DAMAGE := 14.0              ## RIFT CARBINE (weapon_defs.gd; not loaded here because it needs the autoloads)
const CARBINE_INTERVAL := 0.105
const CHAPTERS := 12                    ## 8 story chapters then 4 endless sectors


static func player_dps(ch: int) -> float:
	return CARBINE_DAMAGE / CARBINE_INTERVAL * HIT_RATE * (1.0 + PLAYER_GROWTH * minf(ch, 8))


static func enemy_dps(m: int, ch: int) -> float:
	var c: Dictionary = EnemyTypes.get_cfg(&"operative")
	var f: Vector2 = c["fire"]
	var cycle := (f.x + f.y) * 0.5 / Difficulty.mult("aggr", m) + float(c["aim_time"]) + float(c["burst"]) * float(c["burst_gap"])
	var spread_hit := ENEMY_HIT / maxf(Difficulty.mult("spread", m), 0.1) ** 0.5
	return float(c["dmg"]) * float(c["burst"]) / cycle * minf(spread_hit, 0.9) * Difficulty.damage_taken(ch, m)


func _init() -> void:
	var prev := {}
	var worst_jump := 0.0
	print("chapter  mode      ttk_op(s)  ttk_boss(s)  survive(s, %d foes)  heat/kill  credits" % FOES)
	for m in Difficulty.NAMES.size():
		for ch in CHAPTERS:
			var op_hp: float = float(EnemyTypes.get_cfg(&"operative")["hp"]) * Difficulty.chapter_hp(ch) * Difficulty.mult("hp", m)
			var ttk := op_hp / player_dps(ch)
			var boss_ttk := 0.0
			if BOSS_CHAPTERS.has(ch):
				var b: Dictionary = EnemyTypes.get_cfg(BOSS_CHAPTERS[ch])
				boss_ttk = float(b["hp"]) * Difficulty.boss_hp(ch) * Difficulty.mult("hp", m) / player_dps(ch)
			var hp := 100.0 * (1.0 + ARMOUR_GROWTH * ch)
			var surv := hp / (enemy_dps(m, ch) * FOES)
			var heat := float(EnemyTypes.get_cfg(&"operative")["heat"]) * Difficulty.mult("heat", m)
			var cred := (1.0 + 0.2 * minf(ch, 8)) * Difficulty.mult("credits", m)
			print("%7d  %-8s  %9.2f  %11.1f  %19.1f  %9.2f  x%.2f" % [ch + 1, Difficulty.NAMES[m], ttk, boss_ttk, surv, heat, cred])
			if prev.has(m):
				worst_jump = maxf(worst_jump, absf(ttk / float(prev[m][0]) - 1.0))
				worst_jump = maxf(worst_jump, absf(surv / float(prev[m][1]) - 1.0))
			prev[m] = [ttk, surv]
	print("largest chapter-to-chapter change: %.1f %%" % (worst_jump * 100.0))
	quit()
