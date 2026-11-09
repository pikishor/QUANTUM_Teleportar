class_name DamageFeedback
extends RefCounted
## Health feedback of the status bars (wave 109b): when a bar loses health the lost part stays as a bright GHOST segment for GHOST_HOLD seconds, then drains away (so the size of the hit
## reads at once), the bar flashes white for FLASH seconds and a low bar pulses. Vehicle hulls get a state word (SOUND / SMOKING / BURNING) and a critical flag. Pure logic with an explicit clock.
##   track(key, frac, now) -> {frac, ghost, flash, low}: one per bar key ("hero", "hull"); `ghost` >= frac is the lost part's far end.
##   hull_state(frac) -> {word, col, critical}.

const GHOST_HOLD := 0.35
const GHOST_RATE := 0.55               ## fraction per second the ghost drains at after the hold
const FLASH := 0.22
const LOW := 0.3
const CRITICAL := 0.25

var _s := {}


func track(key: StringName, frac: float, now: float) -> Dictionary:
	frac = clampf(frac, 0.0, 1.0)
	var st: Dictionary = _s.get(key, {"last": frac, "ghost": frac, "hit": -100.0, "now": now})
	var dt := clampf(now - float(st["now"]), 0.0, 0.5)
	st["now"] = now
	if frac < float(st["last"]) - 0.004:
		st["hit"] = now
		st["ghost"] = maxf(float(st["ghost"]), float(st["last"]))
	elif frac > float(st["last"]):
		st["ghost"] = maxf(float(st["ghost"]), frac) if now - float(st["hit"]) < GHOST_HOLD else frac       # healing: the ghost never sticks above
	st["last"] = frac
	if now - float(st["hit"]) > GHOST_HOLD:
		st["ghost"] = maxf(frac, float(st["ghost"]) - GHOST_RATE * dt)
	_s[key] = st
	var age := now - float(st["hit"])
	return {"frac": frac, "ghost": maxf(float(st["ghost"]), frac), "flash": clampf(1.0 - age / FLASH, 0.0, 1.0), "low": frac < LOW}


func reset() -> void:
	_s.clear()


static func hull_state(frac: float) -> Dictionary:
	if frac < CRITICAL:
		return {"word": "BURNING", "col": UiUtil.RED, "critical": true}
	if frac < 0.4:
		return {"word": "SMOKING", "col": UiUtil.AMBER, "critical": false}
	if frac < 0.75:
		return {"word": "DAMAGED", "col": Color(1.0, 0.85, 0.4), "critical": false}
	return {"word": "SOUND", "col": UiUtil.GREEN, "critical": false}
