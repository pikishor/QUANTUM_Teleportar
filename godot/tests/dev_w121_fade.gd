extends RefCounted
const TIMEOUT_SECONDS := 120
const Lib := preload("res://tests/w120_reach_lib.gd")
func run(h: Node) -> void:
	var L := Lib.new()
	await L.start(h)
	var p := L.p
	p.body.set_fade(0.9)
	for n in p.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if g.is_visible_in_tree():
			print("FADE ", p.get_path_to(g), " ", g.get_class(), " tr ", g.transparency, " top ", g.top_level)
	await L.finish()
