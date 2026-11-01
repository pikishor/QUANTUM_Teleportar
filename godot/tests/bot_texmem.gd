extends RefCounted
## Texture memory experiment of scripts/common/texture_budget.gd (tools: main.tscn -- --bot=res://tests/bot_texmem.gd --quality=0):
## every model scene is instantiated and kept (memory A), then TextureBudget.halve_models() runs (memory B). B well below A = the halving frees the full-size atlases.
var _n := 0
var _keep: Array[Node] = []

func _mem() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0

func step(_t: float, _dt: float) -> bool:
	_n += 1
	if _n == 40:
		for m in TextureBudget.MODELS:
			var inst := Game.load_model(m)
			if inst != null:
				Game.world.add_child(inst)
				inst.position = Vector3(0, -500, 0)
				_keep.append(inst)
	if _n == 60:
		var a := _mem()
		var cnt := TextureBudget.halve_models()
		print("TEXMEM_A mb=%.0f replaced=%d" % [a, cnt])
	if _n == 80:
		print("TEXMEM_B mb=%.0f saved_mb=%.0f" % [_mem(), float(TextureBudget.saved_bytes) / 1048576.0])
		OS.kill(OS.get_process_id())
	return false
