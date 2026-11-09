class_name RideUse
extends RefCounted
## The one contextual USE of the railway and the ships (wave 106): "CLIMB TO ROOF", "SIT", "STAND UP", "TAKE HELM", "LEAVE HELM", "MAN GUN", "LEAVE GUN", "BOARD". The HUD hint and the touch USE
## button ask `prompt()`; the worlds (RailWorld, ShipWorld) handle the press themselves in their physics tick. "" when nothing is in reach (or a car is: the car's ENTER comes first).


static func prompt() -> String:
	if not Game.is_playing() or not is_instance_valid(Game.player):
		return ""
	if is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"nearest") and Game.player.get("vehicle") == null:
		if Game.vehicles.call(&"nearest", Game.player.global_position, 4.0) != null:
			return ""
	var rw := RailWorld.instance
	if rw != null:
		var s := rw.use_prompt()
		if s != "":
			return s
	var sw := ShipWorld.instance
	if sw != null:
		var s2 := sw.use_prompt()
		if s2 != "":
			return s2
	return ""
