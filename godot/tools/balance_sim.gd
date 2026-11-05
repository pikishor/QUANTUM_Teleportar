extends SceneTree
## Balance tables entry point. The model reads the game classes (WeaponDefs, Quantum, Companion ...), which need the autoloads, so a bare `-s` run cannot compile them:
## this script launches the headless test runner (tools/balance_sim.sh -> tests/balance_sim.gd) and prints its output. Run from godot/:
##   "$(tools/get_godot.sh)" --headless --path . -s res://tools/balance_sim.gd       or directly   tools/balance_sim.sh   (economy: tools/economy_sim.sh)
## Maths: scripts/progress/balance_model.gd, text: balance_report.gd / balance_economy.gd. Report: docs/BALANCE.md.


func _init() -> void:
	var out: Array = []
	OS.execute("bash", [ProjectSettings.globalize_path("res://tools/balance_sim.sh")], out, true)
	for chunk in out:
		print(str(chunk))
	quit()
