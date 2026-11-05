extends RefCounted
## Diagnostic bot of the tier-switch texture memory (tools: main.tscn -- --bot=res://tests/bot_tierswitch.gd --quality=0, real renderer). Prints TIERMEM lines per switch.
var _n := 0
var _plan := [0, 2, 0, 1, 0, 2, 0, 1, 0]
var _i := 0
func _mem() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0
func step(_t: float, _dt: float) -> bool:
	_n += 1
	if _n == 40:
		print("TIERMEM start q=%d mb=%.0f" % [Game.quality, _mem()])
	if _n > 40 and (_n - 40) % 45 == 0:
		_i += 1
		if _i >= _plan.size():
			OS.kill(OS.get_process_id())
			return true
		Game.set_quality(_plan[_i])
		print("TIERMEM switched q=%d mb(at switch)=%.0f" % [_plan[_i], _mem()])
	elif _n > 40 and (_n - 40) % 45 == 30:
		print("TIERMEM settled q=%d mb=%.0f" % [Game.quality, _mem()])
	return false
