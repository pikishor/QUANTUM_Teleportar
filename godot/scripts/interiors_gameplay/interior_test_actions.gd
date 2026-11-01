class_name InteriorTestActions
extends RefCounted
## The TEST menu's INTERIORS page (scripts/ui/test_menu.gd): static actions that return a status line, so the menu needs no reference to the manager.


static func enter(type: StringName) -> String:
	var ig := InteriorGameplay.instance
	return ig.test_enter(type) if ig != null else "NO INTERIOR LAYER"


static func leave() -> String:
	var ig := InteriorGameplay.instance
	return ig.test_leave() if ig != null else "NO INTERIOR LAYER"


static func complete() -> String:
	var ig := InteriorGameplay.instance
	return ig.test_complete_mission() if ig != null else "NO INTERIOR LAYER"
