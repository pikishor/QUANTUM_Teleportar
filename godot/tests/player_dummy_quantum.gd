extends Node
## Stand-in for scripts/quantum/quantum.gd in the player tests: a Node that records the node it was added to (the Player, like the real module expects).

var player_at_ready: Node


func _ready() -> void:
	player_at_ready = get_parent()
