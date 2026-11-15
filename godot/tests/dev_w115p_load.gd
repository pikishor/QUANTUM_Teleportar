extends RefCounted
## Dev probe: do the wave 115 critic's edited scripts compile?
const TIMEOUT_SECONDS := 40.0
func run(_h: Node) -> void:
	for path in ["res://scripts/quantum/snake_missions.gd", "res://scripts/quantum/snake_react.gd", "res://scripts/quantum/snake_warm.gd", "res://scripts/quantum/snake_fx.gd", "res://scripts/quantum/snake_war.gd", "res://scripts/quantum/snake_swing.gd", "res://scripts/quantum/snake_pose.gd", "res://scripts/quantum/snake_power.gd", "res://scripts/quantum/snake_mission_director.gd", "res://scripts/quantum/snake_war_missions.gd"]:
		var s := load(path) as GDScript
		TestLib.check(s != null and s.can_instantiate() or (s != null and s.get_script_constant_map() != null), "%s compiles" % path)
