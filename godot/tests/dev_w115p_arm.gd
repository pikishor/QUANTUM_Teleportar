extends RefCounted
## Dev probe (wave 115 PLAY critic): after a snake power is armed, how does the hero get his gun back? (swap button, number keys, wheel pick, death, vehicle)
const TIMEOUT_SECONDS := 100.0
var host: Node
var p: Player

func frames(n: int) -> void:
	await TestLib.frames(host, n)

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	TestMode.god = true
	var war := SnakeWar.of(p)
	var w := p.weapon
	print("ARM start weapon %s, unlocked %d, level %d" % [str(w.current), WeaponDefs.unlocked.size(), 0])
	war.arm(&"sv_pull")
	print("ARM armed %s, holding %s" % [str(war.armed), str(SnakeWar.holding())])
	# 1 the WEAPON button / swap action (cycle)
	Input.action_press(&"swap")
	await frames(4)
	Input.action_release(&"swap")
	await frames(4)
	print("ARM after SWAP tap: weapon %s, holding %s" % [str(w.current), str(SnakeWar.holding())])
	# 2 number keys
	Input.action_press(&"weapon_2")
	await frames(4)
	Input.action_release(&"weapon_2")
	await frames(4)
	print("ARM after key 2: weapon %s, holding %s" % [str(w.current), str(SnakeWar.holding())])
	# 3 the wheel: class pick
	var items := WeaponWheel.items()
	var picked := false
	for it: Dictionary in items:
		if StringName(it.get("type", &"class")) == &"class" and it.get("ready", true):
			var r := WeaponWheel.activate(it, w)
			picked = true
			print("ARM wheel pick of class %s -> %s ; weapon %s, holding %s" % [str(it.get("id")), str(r), str(w.current), str(SnakeWar.holding())])
			break
	# 4 FIRE with the gun in hand: does it shoot or cast?
	var shots0 := w.ammo
	var casts0 := war.casts
	Input.action_press(&"fire")
	await frames(20)
	Input.action_release(&"fire")
	print("ARM FIRE for 0.33 s: ammo %d -> %d, snake casts %d -> %d, whiffs %d, holding %s" % [shots0, w.ammo, casts0, war.casts, war.whiffs, str(SnakeWar.holding())])
	main.queue_free()
	await frames(3)
