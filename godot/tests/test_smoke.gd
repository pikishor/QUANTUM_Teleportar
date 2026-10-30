extends RefCounted
## Boots the main scene and checks the shared singletons. Run: tools/test.sh tests/test_smoke.gd


func run(host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	TestLib.check(host.get_tree().root.has_node("Game"), "Game autoload present")
	TestLib.check(InputMap.has_action(&"fire") and InputMap.has_action(&"blink"), "input actions registered")
	FX.burst(Vector3.ZERO, Color.CYAN)
	FX.tracer(Vector3.ZERO, Vector3(0, 0, -5))
	FX.blast(Vector3.ZERO, 3.0)
	await TestLib.frames(host, 2)
	TestLib.check(Game.state == &"play", "game state is play")
