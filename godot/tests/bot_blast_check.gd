extends RefCounted
## Orchestrator check: one street explosion 7 m ahead of the player, so the VFX can be looked at (tools/bot.sh res://tests/bot_blast_check.gd out 10 4).
var _fired := false
func step(t: float, _d: float) -> bool:
	if not _fired and t > 1.2 and is_instance_valid(Game.player):
		_fired = true
		var p: Node3D = Game.player
		var fwd := -p.global_transform.basis.z
		Game.explode(p.global_position + fwd * 7.0 + Vector3(0, 0.5, 0), 6.0, {"player_dmg": 0.0})
	return t > 4.0
