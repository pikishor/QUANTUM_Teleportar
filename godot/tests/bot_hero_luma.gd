extends RefCounted
## Rendered bot: the hero's pixels (difference of two frames, hero meshes shown / hidden) at graphics tiers 0, 1, 2 with the game camera.
## Numeric gate: the hero must read as a dark-armoured figure with a subtle rim, never a blown-out white blob.
##   BOT_TIERS=0,1,2 (default)   tools/bot.sh res://tests/bot_hero_luma.gd <prefix> 1 1   (prints HERO_LUMA lines; PNG crops saved as <prefix>_tier<N>.png)
## Exit gate: prints HERO_LUMA_OK / HERO_LUMA_FAIL. Thresholds: mean luma < 0.34 and highlight fraction (luma > 0.9) < 0.08 on every tier.

const MAX_MEAN := 0.34
const MAX_HI := 0.08
const SETTLE := 14

var tiers: Array[int] = []
var _i := 0
var _phase := 0
var _wait := 0
var _p: Player
var _shown: Image
var _results := {}
var _hidden_nodes: Array[MeshInstance3D] = []
var _prefix := ""


func _init() -> void:
	var t := OS.get_environment("BOT_TIERS")
	for part in (t if t != "" else "0,1,2").split(",", false):
		tiers.append(int(part))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-prefix="):
			_prefix = a.get_slice("=", 1)


func step(_t: float, _dt: float) -> bool:
	if _p == null:
		_p = Game.player as Player
		if _p == null:
			return false
		for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
			(n as AutoQuality).enabled = false
		for n in _p.get_tree().root.find_children("*", "Stability", true, false):
			n.set_process(false)
		_p.max_hp = 1.0e6
		Game.state = &"play"
		_begin_tier()
	if _wait > 0:
		_wait -= 1
		return false
	var vp := _p.get_viewport()
	if _phase == 0:
		_shown = vp.get_texture().get_image()
		_set_hero_visible(false)
		_phase = 1
		_wait = 4
		return false
	var hidden := vp.get_texture().get_image()
	_set_hero_visible(true)
	var r := measure(_shown, hidden)
	_results[tiers[_i]] = r
	print("HERO_LUMA tier=%d mean=%.3f hi=%.3f pixels=%d" % [tiers[_i], r.mean, r.hi, r.n])
	if _prefix != "":
		_shown.save_png("%s_tier%d.png" % [_prefix, tiers[_i]])
	_i += 1
	if _i >= tiers.size():
		var ok := true
		for t: int in _results:
			var rr: Dictionary = _results[t]
			if rr.n < 200 or rr.mean > MAX_MEAN or rr.hi > MAX_HI:
				ok = false
		print("HERO_LUMA_OK" if ok else "HERO_LUMA_FAIL")
		if OS.get_environment("BOT_FASTEXIT") != "":        # the software Vulkan / GL teardown can take minutes: tools may skip it
			OS.kill(OS.get_process_id())
		return true
	_begin_tier()
	return false


func _begin_tier() -> void:
	Game.set_quality(tiers[_i])
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	_phase = 0
	_wait = SETTLE


func _set_hero_visible(on: bool) -> void:
	if not on:
		_hidden_nodes.clear()
		for n in _p.body.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.visible and m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				m.visible = false
				_hidden_nodes.append(m)
	else:
		for m in _hidden_nodes:
			if is_instance_valid(m):
				m.visible = true
		_hidden_nodes.clear()


## Hero pixels = those that differ between the two frames; returns {mean, hi, n} over their luma (Rec. 709 on the displayed sRGB values).
static func measure(shown: Image, hidden: Image) -> Dictionary:
	var sum := 0.0
	var hi := 0
	var n := 0
	var w := mini(shown.get_width(), hidden.get_width())
	var h := mini(shown.get_height(), hidden.get_height())
	for y in range(0, h):
		for x in range(0, w):
			var a := shown.get_pixel(x, y)
			var b := hidden.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.09:
				var l := a.r * 0.2126 + a.g * 0.7152 + a.b * 0.0722
				sum += l
				n += 1
				if l > 0.9:
					hi += 1
	return {"mean": sum / maxf(float(n), 1.0), "hi": float(hi) / maxf(float(n), 1.0), "n": n}
