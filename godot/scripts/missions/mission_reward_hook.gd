class_name MissionRewardHook
extends Node
## Connects every mission system's completion signal to MissionRewards.complete (scripts/progress/mission_rewards.gd): contracts, side jobs, campaign chapters, chases, stealth jobs, heists,
## the arena and interior jobs. Child of Missions (built in Missions._ready). One mission = one completion, whoever runs it (the future Mission Board wraps these same runners, so it needs
## no call of its own). Starts only mark the wallet (the card shows what the mission earned). Rewards are off in DEMO mode (everything is owned there) and for failed runs.

var hooked := 0                  ## signals connected (tests)
var completions := 0             ## missions this hook has paid out
var _interior_done := false


func _ready() -> void:
	name = "MissionRewardHook"
	var m := get_parent() as Missions
	if m == null:
		return
	if m.contracts != null:
		_link(m.contracts.started, _on_start)
		_link(m.contracts.completed, func(kind: StringName, _r: Dictionary) -> void: _done(&"contract", _pretty(kind)))
	if m.sides != null:
		_link(m.sides.started, _on_start)
		_link(m.sides.finished, func(id: StringName, ok: bool, _why: String) -> void:
			if ok:
				_done(&"side", String(SideMissions.def(id).get("title", _pretty(id)))))
	if m.campaign != null:
		_link(m.campaign.chapter_started, _on_start)
		_link(m.campaign.chapter_completed, func(ch: int) -> void: _done(&"chapter", CampaignRunner.chapter_title(ch)))
	if m.chases != null:
		_link(m.chases.started, _on_start)
		_link(m.chases.finished, func(id: StringName, ok: bool) -> void:
			if ok:
				_done(&"chase", _pretty(id)))
	if m.stealth != null:
		_link(m.stealth.started, _on_start)
		_link(m.stealth.finished, func(id: StringName, ok: bool, _why: String) -> void:
			if ok:
				_done(&"stealth", _pretty(id)))
	if m.heists != null:
		_link(m.heists.started, func(_id: StringName, _ap: StringName) -> void: MissionRewards.mark_start())
		_link(m.heists.finished, func(id: StringName, ok: bool, _why: String) -> void:
			if ok:
				_done(&"heist", _pretty(id)))
	if m.arena != null:
		_link(m.arena.started, func(_mode: StringName, _diff: StringName) -> void: MissionRewards.mark_start())
		_link(m.arena.finished, func(mode: StringName, ok: bool, _why: String) -> void:
			if ok:
				_done(&"arena", _pretty(mode)))


func _process(_dt: float) -> void:
	if _interior_done:
		set_process(false)
		return
	var ig := InteriorGameplay.instance
	if ig != null and ig.missions != null:
		_interior_done = true
		_link(ig.missions.completed, func(kind: StringName, _door: int, _r: Dictionary) -> void: _done(&"interior", _pretty(kind)))


func _link(sig: Signal, fn: Callable) -> void:
	if not sig.is_connected(fn):
		sig.connect(fn)
		hooked += 1


func _on_start(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	MissionRewards.mark_start()


func _done(kind: StringName, title: String) -> void:
	if DemoMode.active or Game.progress == null:
		return
	completions += 1
	MissionRewards.complete(kind, title)


static func _pretty(id: StringName) -> String:
	return String(id).replace("_", " ").to_upper()
