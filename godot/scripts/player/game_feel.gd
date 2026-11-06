class_name GameFeel
extends RefCounted
## Game feel in one table: per event a camera shake, an FOV kick, a hit-stop (real seconds of near-freeze), a haptic tick and a motion-blur-lite streak.
## `fire(event)` applies it to the live game (FX.shake, CameraRig.punch_fov / hit_stop / blur, UiSettings.buzz). Reduce-motion drops shake, FOV kick, hit-stop and
## blur; reduce-flash drops the blur streak and flattens the low-health pulse. Haptics follow the vibration setting only. `fired` counts events for tests.

## {shake 0..1, fov degrees, stop real seconds, buzz ms, blur 0..1}
const PROFILES := {
	&"hurt": {"shake": 0.3, "fov": 0.0, "stop": 0.0, "buzz": 40, "blur": 0.0},
	&"heavy_hurt": {"shake": 0.55, "fov": 2.0, "stop": 0.0, "buzz": 80, "blur": 0.0},
	&"die": {"shake": 0.8, "fov": 4.0, "stop": 0.0, "buzz": 220, "blur": 0.0},
	&"teleport": {"shake": 0.35, "fov": 9.0, "stop": 0.0, "buzz": 35, "blur": 1.0},
	&"slam": {"shake": 0.9, "fov": 5.0, "stop": 0.05, "buzz": 90, "blur": 0.0},
	&"explosion": {"shake": 0.6, "fov": 3.0, "stop": 0.0, "buzz": 70, "blur": 0.0},
	&"kill": {"shake": 0.0, "fov": 0.0, "stop": 0.0, "buzz": 15, "blur": 0.0},
	&"heavy_kill": {"shake": 0.2, "fov": 1.5, "stop": 0.06, "buzz": 45, "blur": 0.0},
	&"ability": {"shake": 0.0, "fov": 0.0, "stop": 0.0, "buzz": 30, "blur": 0.0},
	&"sprint": {"shake": 0.0, "fov": 0.0, "stop": 0.0, "buzz": 0, "blur": 0.0},
}
const HEAVY_WEAPONS: Array[StringName] = [&"lance", &"scatter", &"grenade", &"revolver", &"blade", &"marksman", &"breacher", &"rocket"]
const STOP_MAX := 0.12
const LOW_HP := 0.3

static var fired := 0
static var last: StringName = &""


## True when a kill earns the hit-stop: a critical, or a heavy weapon.
static func is_heavy_kill(crit: bool, weapon_id: StringName) -> bool:
	return crit or HEAVY_WEAPONS.has(weapon_id)


## The profile of an event with the accessibility settings applied (what fire() will actually do).
static func effective(event: StringName) -> Dictionary:
	var p: Dictionary = (PROFILES.get(event, PROFILES[&"kill"]) as Dictionary).duplicate()
	if UiSettings.s_reduce_motion:
		p["shake"] = 0.0
		p["fov"] = 0.0
		p["stop"] = 0.0
		p["blur"] = 0.0
	if UiSettings.s_reduce_flash:
		p["blur"] = 0.0
	p["stop"] = minf(float(p["stop"]), STOP_MAX)
	return p


static func fire(event: StringName) -> Dictionary:
	var p := effective(event)
	fired += 1
	last = event
	if float(p["shake"]) > 0.0:
		FX.shake(float(p["shake"]))
	var pl: Player = Game.player if is_instance_valid(Game.player) else null
	var rig: CameraRig = pl.camera_rig if pl != null and is_instance_valid(pl.camera_rig) else null
	if rig != null:
		if float(p["fov"]) > 0.0:
			rig.punch_fov(float(p["fov"]))
		if float(p["stop"]) > 0.0:
			rig.hit_stop(float(p["stop"]))
		if float(p["blur"]) > 0.0:
			rig.blur = maxf(rig.blur, float(p["blur"]))
	if int(p["buzz"]) > 0:
		UiSettings.buzz(int(p["buzz"]))
	return p


## Low-health haptic heartbeat period in seconds for a health fraction (0 = none above LOW_HP): faster the lower it gets.
static func heartbeat_period(hp_f: float) -> float:
	if hp_f >= LOW_HP or hp_f <= 0.0:
		return 0.0
	return lerpf(0.7, 1.4, hp_f / LOW_HP)
