class_name Toast
extends RefCounted
## THE one toast channel of the HUD (Game.say / Game.message land here). One line, at most MAX_TIME seconds, rate limited, important things only.
##   0 never   chatter the screen already says (verb names, radio station changes, ally orders, "contract available")
##   1 low     feedback shown only when nothing else is up and GAP seconds have passed since the last toast
##   2 important  pickups, credits, mission updates, wanted changes: shown at once (replacing a low toast); one waiting slot when another important toast is up
## Pure logic with an explicit clock, so tests drive it without frames.

const MAX_TIME := 2.0               ## seconds a toast stays, whatever the sender asked
const MIN_TIME := 1.0
const GAP := 1.2                    ## seconds after a toast started before a low one may follow
const DEDUPE := 3.0                 ## the same text again within this many seconds is dropped
const NEVER_EXACT: Array[String] = ["QUANTUM TELEPORT", "ENTANGLE", "WAVEFUNCTION COLLAPSE", "COLLAPSE", "SUPERPOSITION", "PHASE SHIELD", "TIME SLIP", "ARC", "RADIO OFF"]
const NEVER_PREFIX: Array[String] = ["RADIO", "ALLY FOLLOW", "ALLY HOLD", "ALLY ATTACK", "CONTRACT AVAILABLE", "GLOWING DOORS", "DEMO MODE", "ENTANGLED", "SUPERPOSITION ·", "TELEPORT MARKER"]
const IMPORTANT: Array[String] = ["+", "CREDIT", "CORE", "COMPLETE", "FAILED", "OBJECTIVE", "SECTOR", "WANTED", "ACHIEVEMENT", "SHARD", "LEVEL", "DOWN", "CHECKPOINT",
	"MISSION", "COMMANDEERED", "RESET", "WAVE", "BOSS", "RETRY", "TIME UP", "NEW BEST", "LOST SIGNAL", "RECOVERED", "TAKEN", "GETAWAY", "NEED"]

var text := ""                      ## the toast on screen ("" none)
var left := 0.0
var total := 1.0
var important := false
var pending := ""                   ## one important toast waiting for the current one to end
var pending_time := 0.0
var shown := 0                      ## toasts put on screen (tests)
var dropped := 0                    ## toasts refused (tests)
var _started := -100.0
var _last_text := ""
var _last_at := -100.0
var _clock := 0.0


static func priority(t: String) -> int:
	var u := t.strip_edges().to_upper()
	if NEVER_EXACT.has(u):
		return 0
	for p: String in NEVER_PREFIX:
		if u.begins_with(p):
			return 0
	for k: String in IMPORTANT:
		if u.contains(k):
			return 2
	return 1


## A sender's text trimmed to a single short line: the part before " · " when there is one.
static func one_line(t: String) -> String:
	var s := t.replace("\n", " ").strip_edges()
	var i := s.find(" · ")
	if i > 0:
		s = s.substr(0, i)
	return s


## Offers a message. Returns true when it is on screen now (the caller mirrors `text` / `left`).
func offer(t: String, seconds: float) -> bool:
	var line := one_line(t)
	var pr := priority(line)
	if line == "" or pr == 0 or (line == _last_text and _clock - _last_at < DEDUPE):
		dropped += 1
		return false
	var busy := left > 0.0
	if pr == 1 and (busy or _clock - _started < GAP):
		dropped += 1
		return false
	if pr == 2 and busy and important and _clock - _started < GAP:
		pending = line                                 # an important toast is up: this one waits (the newest wins)
		pending_time = seconds
		return false
	_show(line, seconds, pr == 2)
	return true


func _show(line: String, seconds: float, imp: bool) -> void:
	text = line
	total = clampf(seconds, MIN_TIME, MAX_TIME)
	left = total
	important = imp
	_started = _clock
	_last_text = line
	_last_at = _clock
	shown += 1


## Advances the clock. Returns true when a waiting toast has just come up.
func tick(dt: float) -> bool:
	_clock += dt
	left = maxf(left - dt, 0.0)
	if left <= 0.0:
		important = false
		if pending != "":
			var p := pending
			pending = ""
			_show(p, pending_time, true)
			return true
	return false


func clear() -> void:
	text = ""
	left = 0.0
	pending = ""
