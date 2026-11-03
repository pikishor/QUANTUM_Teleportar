extends RefCounted
## HUD follow-ups: ability labels fit at 1280x720 and 844x390, OPTIONS clears the title, keys 5-8 exist, ENTANGLE active state.
## Run: tools/test.sh tests/test_hud_followups.gd

class StubQ extends Node:
	var links: Array = []
	var _swap_left := 0.0
	var cd_link := 0.0


class StubP extends Node:
	var energy := 100.0
	var quantum: Node


func run(host: Node) -> void:
	var font := UiUtil.font()
	for vp: Vector2 in [Vector2(1280, 720), Vector2(844, 390)]:
		var s := UiUtil.ui_scale(vp)
		var w := 152.0 * s - 8.0 * s
		var ok := true
		for info: Dictionary in UiUtil.ABILITIES:
			var label := UiUtil.ability_label(info, "  9", s)
			var fs := UiUtil.fit_size(font, label, w * 0.9, int(UiUtil.BAR_LABEL * s))
			## Fit with a 10 % margin (font metrics differ between machines: CI's wide fallback font lands on fit_size's 8 px floor where Inter gets 9);
			## the label must always fit its plate and never fall below that floor.
			ok = ok and fs >= 8 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x <= w * 0.9
		TestLib.check(ok, "ability labels fit at %s" % str(vp))
		var hud := Hud.new()
		var btn := hud._options_btn(vp, s)
		var title_top := (196.0 - 76.0) * s
		TestLib.check(btn.end.y <= title_top and btn.size.y >= 63.9 * s, "OPTIONS clears the title at %s" % str(vp))
		hud.free()
	for i in range(5, 9):
		TestLib.check(InputMap.has_action(StringName("weapon_%d" % i)), "weapon_%d bound" % i)
	TestLib.check(WeaponDefs.IDS.size() == 8, "8 weapons")
	var p := StubP.new()
	var q := StubQ.new()
	p.quantum = q
	host.add_child(p)
	host.add_child(q)
	var info: Dictionary = UiUtil.ABILITIES[1]
	TestLib.check(not UiUtil.ability_state(p, info)["active"], "ENTANGLE idle")
	q._swap_left = 0.2
	TestLib.check(UiUtil.ability_state(p, info)["active"], "ENTANGLE active during the swap")
	q._swap_left = 0.0
	q.links = [{"t": 5.0}]
	var st := UiUtil.ability_state(p, info)
	TestLib.check(st["active"] and float(st["left"]) == 5.0, "ENTANGLE active with a link")
