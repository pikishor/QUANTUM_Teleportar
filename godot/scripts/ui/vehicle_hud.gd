class_name VehicleHud
extends RefCounted
## The vehicle readouts of the big world (wave 109b), one per family, built on the speedometer plate the HUD already draws (speed, gear, rev bar):
##   car (cars, bikes, hover, quad)  hull row (ten segments + SOUND / DAMAGED / SMOKING / BURNING, a flashing frame when critical) and the NITRO tank
##   boat    hull row, plus words: HDG, DEPTH, PLANING, SHALLOW warning (the hull is about to run aground)
##   tank    hull row, the TURRET DIAL (the hull points up, the turret and gun show where they aim relative to it; a ring fills while the main gun reloads) and the main gun's rounds
##   heli    hull row, ROTOR percent (lift needs 85 %), plus the flight instruments of FlightHud
##   plane   hull row, SPEED against the STALL speed, plus the flight instruments of FlightHud
## `family(veh)`, `panel(veh)` (the numbers as a Dictionary for the tests) and `extra_rows(veh)` (words for the readout plate beside the speedometer) are pure; `draw(hud, c, font, ab, veh, s, now)`
## paints with the Hud's queued primitives (the tank dial uses a handful of direct calls).

const SEGMENTS := 10
const CLASSES: Array[StringName] = [&"car", &"boat", &"tank", &"heli", &"plane"]


static func family(veh: Object) -> StringName:
	if veh == null:
		return &""
	var cls: Variant = veh.get("cls")
	return cls if cls in [&"heli", &"plane", &"boat", &"tank"] else &"car"


static func _wrap(a: float) -> float:
	return wrapf(a, -PI, PI)


## The numbers of the readout: {family, kmh, hull (0..1, -1 without a hull), state {word, col, critical}, ...per family}.
static func panel(veh: Object) -> Dictionary:
	var fam := family(veh)
	var out := {"family": fam, "kmh": roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6), "hull": -1.0, "state": {}}
	var hp := UiUtil.num(veh, &"hp", -1.0)
	if hp >= 0.0:
		out["hull"] = clampf(hp / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), 0.0, 1.0)
		out["state"] = DamageFeedback.hull_state(float(out["hull"]))
	var craft: Object = veh.get("craft")
	var spec: Dictionary = veh.get("spec") if veh.get("spec") is Dictionary else {}
	match fam:
		&"car":
			out["gear"] = int(UiUtil.num(veh, &"gear", 1.0))
			out["nitro"] = clampf(UiUtil.num(veh, &"nitro", 1.0), 0.0, 1.0)
			out["boosting"] = veh.get("boosting") == true
		&"boat":
			out["heading"] = FlightHud.compass(UiUtil.num(veh, &"heading", 0.0))
			var depth := UiUtil.num(craft, &"depth", 0.0) if craft != null else 0.0
			out["depth"] = depth
			out["shallow"] = craft != null and depth > 0.0 and depth < VehicleCraft.MIN_DEPTH * 2.2
			out["planing"] = craft != null and UiUtil.num(craft, &"planing", 0.0) > 0.5
			out["throttle"] = clampf(absf(UiUtil.num(veh, &"speed", 0.0)) / maxf(float(spec.get("max", 27.0)), 1.0), 0.0, 1.0)
		&"tank":
			var rel := 0.0
			var gun := 0.0
			if craft != null:
				rel = _wrap(UiUtil.num(craft, &"turret_yaw", 0.0) - UiUtil.num(veh, &"heading", 0.0))
				gun = UiUtil.num(craft, &"gun_pitch", 0.0)
			out["turret"] = rel                                  # + = the turret points to the left of the hull (Node3D yaw)
			out["gun_pitch"] = gun
			var w: Object = veh.get("weapons")
			out["ammo"] = int(UiUtil.num(w, &"ammo", 0.0)) if w != null else 0
			out["reload"] = float(w.call(&"ready_fraction")) if w != null and w.has_method(&"ready_fraction") else 1.0
		&"heli":
			out["rotor"] = clampf(UiUtil.num(craft, &"spool", 0.0), 0.0, 1.0) if craft != null else 0.0
		&"plane":
			var stall := float(spec.get("stall", 24.0))
			out["stall"] = stall
			out["speed_ratio"] = absf(UiUtil.num(veh, &"speed", 0.0)) / maxf(stall, 1.0)
	return out


## Extra words for the plate beside the speedometer: [{text, col}] (Hud.vehicle_rows appends them).
static func extra_rows(veh: Object) -> Array:
	var rows: Array = []
	var p := panel(veh)
	match p["family"]:
		&"boat":
			var line := "HDG %03d" % int(p["heading"])
			if float(p["depth"]) > 0.0:
				line += "    DEPTH %d M" % roundi(float(p["depth"]))
			rows.append({"text": line, "col": Color(UiUtil.CYAN, 0.97)})
			if bool(p["shallow"]):
				rows.append({"text": "SHALLOW  TURN BACK", "col": Color(UiUtil.RED, 0.97)})
			elif bool(p["planing"]):
				rows.append({"text": "PLANING", "col": Color(UiUtil.GREEN, 0.97)})
		&"heli":
			rows.append({"text": "ROTOR %d %%" % roundi(float(p["rotor"]) * 100.0), "col": Color(UiUtil.CYAN if float(p["rotor"]) >= VehicleCraft.SPOOL_READY else UiUtil.AMBER, 0.97)})
		&"plane":
			var r := float(p["speed_ratio"])
			var craft: Object = veh.get("craft")
			if craft != null and craft.get("airborne") == true and r < 1.3:               # the stall margin only when it matters
				rows.append({"text": "SPEED %d  STALL %d" % [roundi(float(p["kmh"])), roundi(float(p["stall"]) * 3.6)], "col": Color(UiUtil.RED if r < 1.0 else UiUtil.AMBER, 0.97)})
	return rows


## Paints the hull row above the speedometer plate `ab` (and the nitro tank / the tank's dial). Returns the top y of everything it drew.
static func draw(hud: Hud, c: Control, font: Font, ab: Rect2, veh: Object, s: float, now: float) -> float:
	var p := panel(veh)
	var top := ab.position.y
	var hull := float(p["hull"])
	if hull >= 0.0:
		var row := Rect2(ab.position.x, ab.position.y - 32.0 * s, ab.size.x, 28.0 * s)
		var st: Dictionary = p["state"]
		var crit := bool(st["critical"])
		var blink := crit and not UiSettings.s_reduce_flash and int(now * 5.0) % 2 == 0
		hud._rect(c, row, Color(UiUtil.PLATE, 0.8))
		if crit:
			hud._frame(c, row, Color(UiUtil.RED, 0.95 if blink else 0.5), 2.0 * s)
		var sw := 14.0 * s
		var gap := 2.5 * s
		var lit := ceili(hull * SEGMENTS - 0.001)
		var col: Color = st["col"]
		for i in SEGMENTS:
			hud._rect(c, Rect2(row.position.x + 8.0 * s + i * (sw + gap), row.position.y + 7.0 * s, sw, 14.0 * s), Color(col, 0.95) if i < lit else Color(1, 1, 1, 0.14))
		hud._text(c, font, Vector2(row.position.x + 8.0 * s + SEGMENTS * (sw + gap) + 6.0 * s, row.end.y - 6.0 * s), String(st["word"]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - SEGMENTS * (sw + gap) - 12.0 * s, int(UiUtil.BAR_LABEL * s * 0.8), Color(col, 1.0), 1.0 * s)
		top = row.position.y
	match p["family"]:
		&"car":
			var nitro := float(p["nitro"])
			if nitro < 0.999 or bool(p["boosting"]):
				var nr := Rect2(ab.position.x, top - 14.0 * s, ab.size.x, 9.0 * s)
				hud._rect(c, nr, Color(UiUtil.PLATE, 0.8))
				hud._rect(c, Rect2(nr.position.x + 2.0 * s, nr.position.y + 2.0 * s, (nr.size.x - 4.0 * s) * nitro, nr.size.y - 4.0 * s), Color(UiUtil.CYAN if not bool(p["boosting"]) else UiUtil.MAGENTA, 0.95))
				top = nr.position.y
		&"tank":
			top = _tank_dial(hud, c, font, Vector2(ab.position.x + 46.0 * s, top - 52.0 * s), 40.0 * s, p, s) - 6.0 * s
	return top


## The tank's turret dial centred at `at`, radius `r`: a ring that fills as the main gun reloads, the hull outline (fixed, nose up), the turret line and the gun's elevation. Returns the top.
static func _tank_dial(hud: Hud, c: Control, font: Font, at: Vector2, r: float, p: Dictionary, s: float) -> float:
	var ready := float(p["reload"])
	c.draw_circle(at, r + 4.0 * s, Color(UiUtil.PLATE, 0.85))
	c.draw_arc(at, r, -PI * 0.5, -PI * 0.5 + TAU * ready, 40, Color(UiUtil.GREEN if ready >= 0.999 else UiUtil.AMBER, 0.95), 4.0 * s)
	c.draw_arc(at, r - 8.0 * s, 0.0, TAU, 28, Color(1, 1, 1, 0.16), 1.5 * s)
	var hull_pts := PackedVector2Array([at + Vector2(-9.0, -16.0) * s, at + Vector2(9.0, -16.0) * s, at + Vector2(9.0, 16.0) * s, at + Vector2(-9.0, 16.0) * s])
	c.draw_colored_polygon(hull_pts, Color(0.45, 0.55, 0.6, 0.9))
	var rel := float(p["turret"])                                # + = left: on screen that is anticlockwise from "up"
	var dir := Vector2(-sin(rel), -cos(rel))
	c.draw_line(at, at + dir * (r - 4.0 * s), Color(UiUtil.AMBER, 0.98), 4.0 * s)
	c.draw_circle(at, 7.0 * s, Color(UiUtil.AMBER, 0.98))
	hud._text(c, font, Vector2(at.x + r + 12.0 * s, at.y + 8.0 * s), "GUN %d\u00b0" % roundi(rad_to_deg(float(p["gun_pitch"]))), HORIZONTAL_ALIGNMENT_LEFT, 120.0 * s, int(UiUtil.BAR_LABEL * s * 0.8), Color(1, 1, 1, 0.85), 1.0 * s)
	return at.y - r - 4.0 * s
