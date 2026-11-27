class_name TankArmour
extends RefCounted
## ARMOUR, HIT ZONES AND TRACKS of the armoured family (wave 127, w127-arms; plan line 127). Pure functions over a Vehicle (state in two metas), no node, no draw call.
## A DIRECT hit on a tank (the main gun's round, an ATGM, a rocket, a machine gun burst; area blasts keep the old flat damage) lands on one ZONE, read from where it struck the hull:
##   FRONT   the thick glacis: x0.55 (an AP round x0.8)            TURRET  x0.75
##   SIDE    x1.0                                                   REAR    the engine deck: x1.6, and below 50 % hull a rear hit sets the engine on FIRE (it burns, then blows up: Vehicle.ignite)
##   TRACKS  the low band of a flank: x0.5 to the hull, the rest of the round goes into that side's track (TRACK_HP). A track below half SLOWS the tank (TRACK_SLOW), a broken track
##           STOPS it (it can still turn its turret and fire); the crew fixes a broken track in TRACK_FIX s (back to a damaged one); a repair bay, the garage or a recycle restores both.
## Machine-gun rounds (`light`) barely scratch armour (x0.12) and never break a track. AP shells crack armour (x1.25 on every zone but the tracks), HE splashes off it (x0.7 front / turret).
## W127A_OLD=1 (or TankArmour.on = false): the wave 126 rule (every hit the same, no tracks).

const ZONES: Array[StringName] = [&"front", &"side", &"rear", &"turret", &"tracks"]
const MULT := {&"front": 0.55, &"side": 1.0, &"rear": 1.6, &"turret": 0.75, &"tracks": 0.5}
const LIGHT_MULT := 0.12                ## machine-gun rounds against armour
const AP_MULT := 1.25
const HE_ARMOUR := 0.7                  ## HE on the front or the turret
const TRACK_HP := 240.0                 ## each side
const TRACK_SLOW := 0.5                 ## speed share with a track below half
const TRACK_FIX := 12.0                 ## s until the crew has a broken track running again (damaged)
const FIRE_BELOW := 0.5                 ## hull share under which a rear hit starts an engine fire
const ENGINE_FUSE := 9.0                ## s an engine fire burns before the tank blows up
const SHOW_FAR := 560.0                 ## m: tanks and convoy trucks are drawn this far (Vehicle.update_lod; other cars vanish at 140 m)

static var on := OS.get_environment("W127A_OLD") != "1"
static var zone_hits := {}               ## zone -> hits, lifetime (tests)
static var last_zone: StringName = &""
static var last_victim := ""             ## the node name of the tank hit last (tests)
static var tracks_broken := 0
static var engine_fires := 0


static func is_armour(v: Object) -> bool:
	return on and v is Vehicle and (v as Vehicle).cls == &"tank"


## The zone of the hull a round travelling along `dir` struck at world point `at`.
static func zone_of(v: Vehicle, at: Vector3, dir: Vector3) -> StringName:
	var T := v.spec
	var d := at - v.global_position
	var hgt := float(T.get("hgt", 2.6))
	var hl := float(T.get("len", 7.0)) * 0.5
	var hw := float(T.get("wid", 3.2)) * 0.5
	var fz := d.dot(v.forward())
	var rx := d.dot(v.right())
	if d.y > hgt * 0.62:
		return &"turret"
	var nz := fz / maxf(hl, 0.5)
	var nx := rx / maxf(hw, 0.5)
	if absf(nz) < 0.98 and absf(nx) >= absf(nz) * 0.75:          # the flank: a low hit there is the track band
		return &"tracks" if d.y < hgt * 0.36 else &"side"
	if absf(nz) >= 0.98 or absf(nz) > absf(nx):
		return &"front" if nz > 0.0 else &"rear"
	var inc := -dir.normalized()                                   # nothing clear from the point: the side the round came from
	var f := inc.dot(v.forward())
	if f > 0.6:
		return &"front"
	if f < -0.6:
		return &"rear"
	return &"side"


## A direct hit of `dmg` on tank `v` at `at` (round flying along `dir`); `kind` = &"ap", &"he", &"light" (machine gun) or &"" (a rocket, an ATGM, a cannon round). Applies the hull damage
## (through Vehicle.damage) and the track damage. Returns the zone (&"" when `v` is not armour or the rule is off: then the caller deals the plain damage itself).
static func hit(v: Object, at: Vector3, dir: Vector3, dmg: float, kind: StringName = &"") -> StringName:
	if not is_armour(v):
		return &""
	var t := v as Vehicle
	if t.dead or not t.active:
		return &""
	var z := zone_of(t, at, dir)
	var m := float(MULT[z])
	if kind == &"light":
		m *= LIGHT_MULT
	elif kind == &"ap" and z != &"tracks":
		m *= AP_MULT
	elif kind == &"he" and (z == &"front" or z == &"turret"):
		m *= HE_ARMOUR
	zone_hits[z] = int(zone_hits.get(z, 0)) + 1
	last_zone = z
	last_victim = "%s#%d at %s" % [t.name, t.get_instance_id(), t.global_position.snapped(Vector3.ONE)]
	t.set_meta(&"last_zone", z)
	if z == &"tracks" and kind != &"light":
		var side := &"trk_r" if (at - t.global_position).dot(t.right()) > 0.0 else &"trk_l"
		hurt_track(t, side, dmg)
	t.damage(dmg * m)
	if z == &"rear" and kind != &"light" and not t.dead and t.hp < t.max_hp * FIRE_BELOW and t.fuse < 0.0:
		engine_fires += 1
		t.ignite(ENGINE_FUSE)                                         # below 40 % the armour guard of ignite lets it burn; between 40 and 50 % the next rear hit will
		if t.driver_is_player:
			Game.say("ENGINE FIRE  GET OUT OR REPAIR", 2.0)
	return z


static func track_hp(v: Vehicle, side: StringName) -> float:
	return float(v.get_meta(side, TRACK_HP)) if v.has_meta(side) else TRACK_HP


static func hurt_track(v: Vehicle, side: StringName, amount: float) -> void:
	var was := track_hp(v, side)
	var now := maxf(was - amount, 0.0)
	v.set_meta(side, now)
	if was > 0.0 and now <= 0.0:
		tracks_broken += 1
		v.set_meta(&"trk_fix", TRACK_FIX)
		FX.burst(v.global_position + v.right() * (1.0 if side == &"trk_r" else -1.0) * float(v.spec.get("wid", 3.0)) * 0.5 + Vector3(0.0, 0.5, 0.0), Color(0.3, 0.28, 0.25), 12, 5.0, 0.6, 4.0, 0.8)
		if v.driver_is_player:
			Game.say("TRACK BROKEN  THE CREW IS ON IT", 2.0)


## 0..1: the share of its top speed the tank can drive with its tracks as they are (1 intact, TRACK_SLOW damaged, 0 broken). Also runs the crew's track fix (call once a tick: dt).
static func speed_factor(v: Vehicle, dt := 0.0) -> float:
	if not on or not (v.has_meta(&"trk_l") or v.has_meta(&"trk_r")):
		return 1.0
	var l := track_hp(v, &"trk_l")
	var r := track_hp(v, &"trk_r")
	if (l <= 0.0 or r <= 0.0) and dt > 0.0 and v.has_meta(&"trk_fix"):
		var f := float(v.get_meta(&"trk_fix")) - dt
		v.set_meta(&"trk_fix", f)
		if f <= 0.0:
			v.remove_meta(&"trk_fix")
			if l <= 0.0:
				v.set_meta(&"trk_l", TRACK_HP * 0.3)
			if r <= 0.0:
				v.set_meta(&"trk_r", TRACK_HP * 0.3)
			if v.driver_is_player:
				Game.say("TRACK FIXED  DRIVE SLOWLY", 1.5)
			l = track_hp(v, &"trk_l")
			r = track_hp(v, &"trk_r")
	if l <= 0.0 or r <= 0.0:
		return 0.0
	if l < TRACK_HP * 0.5 or r < TRACK_HP * 0.5:
		return TRACK_SLOW
	return 1.0


static func track_state(v: Vehicle) -> StringName:
	var f := speed_factor(v)
	return &"broken" if f <= 0.0 else (&"damaged" if f < 1.0 else &"ok")


## Fresh tracks (Vehicle.activate on a recycle, Vehicle.repair).
static func reset(v: Vehicle) -> void:
	for m: StringName in [&"trk_l", &"trk_r", &"trk_fix", &"last_zone"]:
		if v.has_meta(m):
			v.remove_meta(m)
