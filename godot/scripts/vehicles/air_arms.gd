class_name AirArms
extends RefCounted
## AIRCRAFT WEAPONS BY CLASS (wave 126, w126-air). The guns stay the FIRE button (VehicleSpecs.WEAPONS, VehicleWeapons.tick); everything an aircraft carries besides its guns is here:
##   ROCKET   unguided rocket pod, a salvo from the pylons (blast `ord_air_rocket`)
##   MISSILE  air-to-air / air-to-ground missile with LOCK-ON: keep a target inside LOCK_CONE for LOCK_TIME and the button reads LOCKED; a locked missile homes, an unlocked one flies straight
##            (blast `ord_air_missile`)
##   BOMB     free-fall bomb from the belly, carries the aircraft's speed (blast `ord_bomb_dumb` of the wave 113 table); the flight HUD draws where it will land
##   DROP     a cargo crate on a parachute (no blast): AirRockets counts where it lands (cargo missions)
##   FLARE    countermeasure: a burst of flares; for FLARE_TIME every missile that homes on this aircraft loses it (AirRockets reads `flare_until`)
## The loadout comes from the class of the aircraft (LOADOUT, or `arms` in a VehicleSpecs row: w126-planes can name them per plane, or give a `role`). One AirArms per armed aircraft
## (VehicleWeapons.arms); the AIM button fires the selected arm, the ARMS chip (action ammo_type) picks the next one, the FLARE button (action flare) fires flares.
## Rockets, missiles, bombs and crates are AirRockets projectiles (one pool, no node per shot).
## W126A_OLD=1 (or AirArms.on = false): the wave 125 state (only the gunship's rockets and the jet's missiles of VehicleSpecs.ALT_WEAPONS, no lock, no bombs, no flares).

const LOCK_TIME := 0.8                   ## s a target must stay in the cone before a missile is LOCKED
const LOCK_CONE := 0.34                  ## rad around the aim line
const LOCK_KEEP := 0.55                  ## rad: a lock already made holds this far off the aim line
const FLARE_TIME := 2.8                  ## s missiles stay fooled after a burst
const ARMS := {
	&"rocket": {"name": "ROCKET POD", "short": "ROCKET", "blast_id": &"ord_air_rocket", "rate": 3.2, "salvo": 2, "dmg": 80.0, "blast": 7.5, "speed": 150.0, "life": 3.2, "ammo": 28, "reload": 2.2,
		"color": Color(1.0, 0.62, 0.2), "range": 420.0},
	&"missile": {"name": "MISSILES", "short": "MISSILE", "blast_id": &"ord_air_missile", "rate": 1.4, "salvo": 1, "dmg": 160.0, "blast": 9.0, "speed": 215.0, "life": 4.6, "ammo": 8, "reload": 4.0,
		"color": Color(1.0, 0.8, 0.4), "range": 900.0, "homing": 2.6, "lock": true},
	&"bomb": {"name": "BOMBS", "short": "BOMB", "blast_id": &"ord_bomb_dumb", "rate": 1.6, "salvo": 1, "dmg": 280.0, "blast": 12.0, "speed": 0.0, "life": 16.0, "ammo": 6, "reload": 7.0,
		"color": Color(1.0, 0.55, 0.2), "grav": 22.0, "inherit": 1.0, "look": &"bomb", "range": 0.0},
	&"drop": {"name": "CARGO DROP", "short": "DROP", "rate": 0.7, "salvo": 1, "dmg": 0.0, "blast": 0.0, "speed": 0.0, "life": 60.0, "ammo": 3, "reload": 18.0, "color": Color(0.9, 0.85, 0.6),
		"grav": 14.0, "inherit": 0.8, "chute": 7.0, "look": &"crate", "range": 0.0},
	&"flare": {"name": "FLARES", "short": "FLARE", "rate": 1.4, "ammo": 12, "burst": 3, "reload": 5.0, "color": Color(1.0, 0.95, 0.8)},
}
const ORDER: Array[StringName] = [&"rocket", &"missile", &"bomb", &"drop"]
## The arms of each class of aircraft (the guns are separate). Attack helicopters and fighters fight, transports drop, airliners carry nothing.
const LOADOUT := {
	&"gunship": [&"rocket", &"missile", &"flare"], &"h_attack": [&"rocket", &"missile", &"flare"], &"h_stealth": [&"missile", &"rocket", &"flare"], &"h_coax": [&"rocket", &"missile", &"flare"],
	&"heli": [&"rocket", &"flare"], &"h_naval": [&"missile", &"flare"], &"h_quantum": [&"missile", &"flare"], &"h_void": [&"missile", &"flare"], &"h_tilt": [&"rocket", &"drop", &"flare"],
	&"hauler": [&"drop", &"flare"], &"h_heavy": [&"drop", &"flare"], &"h_tandem": [&"drop", &"flare"], &"h_crane": [&"drop"], &"h_utility": [&"drop", &"flare"], &"h_police": [&"flare"],
	&"h_medic": [&"flare"], &"h_vip": [&"flare"], &"h_scout": [&"flare"], &"h_news": [], &"h_trainer": [], &"h_fire": [], &"h_gull": [], &"h_ultra": [&"flare"],
	&"jet": [&"missile", &"bomb", &"flare"], &"plane": [&"rocket", &"bomb", &"flare"], &"cargo": [&"drop", &"bomb", &"flare"], &"bizjet": [&"flare"], &"airliner": [],
}
## The role of a plane of the wave 126 roster (PlaneRoster.DEFS[kind].role, w126-planes) or a `role` in a VehicleSpecs row -> its arms.
const ROLES := {
	"fighter": [&"missile", &"bomb", &"flare"], "interceptor": [&"missile", &"flare"], "stealth fighter": [&"missile", &"bomb", &"flare"], "ground attack": [&"rocket", &"bomb", &"flare"],
	"bomber": [&"bomb", &"flare"], "stealth bomber": [&"bomb", &"flare"], "combat drone": [&"missile", &"bomb"], "recon drone": [], "sci-fi": [&"missile", &"rocket", &"flare"],
	"freighter": [&"drop", &"flare"], "tanker": [&"flare"], "AWACS": [&"flare"], "crop duster": [&"drop"], "bush": [&"drop"], "seaplane": [&"drop"], "flying boat": [&"drop", &"flare"],
	"trainer": [&"rocket"], "light": [], "aerobatic": [], "racer": [], "glider": [], "light twin": [], "regional": [], "narrow-body": [], "wide-body": [], "jumbo": [], "supersonic": [&"flare"],
}

static var on := OS.get_environment("W126A_OLD") != "1"
static var flares_fired := 0             ## counters for the tests
static var decoyed := 0                  ## missiles a flare pulled off their target
static var _blasts_done := false

var car: Vehicle
var list: Array[StringName] = []         ## the selectable arms (no flare)
var has_flare := false
var idx := 0
var ammo := {}                           ## arm -> rounds
var shots := {}                          ## arm -> rounds fired
var _rl := {}                            ## arm -> reload clock
var _cd := 0.0
var _flare_cd := 0.0
var _side := 1.0
var lock_target: Node3D = null           ## what the missile seeker looks at
var lock_t := 0.0
var _scan_t := 0.0


## The arms of `kind` (with the flare), [] when it carries none.
static func loadout(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var sp: Dictionary = VehicleSpecs.SPECS.get(kind, {})
	var src: Variant = null
	if sp.has("arms"):
		src = sp["arms"]
	elif LOADOUT.has(kind):
		src = LOADOUT[kind]
	elif PlaneRoster.DEFS.has(kind) and ROLES.has(str(PlaneRoster.DEFS[kind].get("role", ""))):
		src = ROLES[str(PlaneRoster.DEFS[kind]["role"])]
	elif sp.has("role") and ROLES.has(str(sp["role"])):
		src = ROLES[str(sp["role"])]
	elif not sp.is_empty() and str(sp.get("cls", "")) in ["plane", "heli"]:
		if VehicleSpecs.WEAPONS.has(kind):                                     # an armed aircraft nobody classed: a fighter's kit
			src = [&"rocket", &"missile", &"flare"]
		elif float(sp.get("mass", 0.0)) > 20000.0:
			src = [&"drop", &"flare"]
		else:
			src = [&"flare"]
	if src is Array:
		for a: Variant in src as Array:
			if ARMS.has(StringName(str(a))):
				out.append(StringName(str(a)))
	return out


static func has_arms(kind: StringName) -> bool:
	return on and not loadout(kind).is_empty()


## A new AirArms for vehicle `c`, or null (an old build, a car, an aircraft with nothing to carry).
static func make(c: Vehicle) -> AirArms:
	if not on or c == null or not (c.cls == &"heli" or c.cls == &"plane"):
		return null
	var lo := loadout(c.kind)
	if lo.is_empty():
		return null
	_ensure_blasts()
	ensure_actions()
	var a := AirArms.new()
	a.car = c
	for k in lo:
		if k == &"flare":
			a.has_flare = true
		else:
			a.list.append(k)
	a.reload_full()
	return a


## The two aircraft blasts of the table (category `aircraft`, so the 65-entry arsenal and its ordnance list stay as they are).
static func _ensure_blasts() -> void:
	if _blasts_done:
		return
	_blasts_done = true
	if not BlastTable.has_entry(&"ord_air_rocket"):
		BlastTable.register(&"ord_air_rocket", {"cat": &"aircraft", "name": "AIR ROCKET", "radius": 7.5, "core": 1.5, "enemy": 120.0, "vehicle": 150.0, "element": &"fire", "tag": "ARK", "tier": 3,
				"note": "A SALVO FROM THE ROCKET POD  FLATTENS A CAR", "knock": 10.0, "lift": 9.6})
	if not BlastTable.has_entry(&"ord_air_missile"):
		BlastTable.register(&"ord_air_missile", {"cat": &"aircraft", "name": "AIR MISSILE", "radius": 9.0, "core": 2.0, "enemy": 170.0, "vehicle": 320.0, "element": &"fire", "tag": "AMS", "tier": 4,
				"note": "LOCKS ON  HOMES ON AIRCRAFT AND VEHICLES", "knock": 12.0, "lift": 11.0})


## The FLARE action exists (keyboard F) for the touch button and a controller.
static func ensure_actions() -> void:
	if InputMap.has_action(&"flare"):
		return
	InputMap.add_action(&"flare")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	InputMap.action_add_event(&"flare", k)


func reload_full() -> void:
	for k in list:
		ammo[k] = int(ARMS[k]["ammo"])
		shots[k] = 0
		_rl[k] = 0.0
	if has_flare:
		ammo[&"flare"] = int(ARMS[&"flare"]["ammo"])
		shots[&"flare"] = 0
		_rl[&"flare"] = 0.0
	_cd = 0.0
	_flare_cd = 0.0
	lock_target = null
	lock_t = 0.0


func current() -> StringName:
	return list[idx] if idx < list.size() else &""


func def() -> Dictionary:
	var k := current()
	return ARMS[k] if k != &"" else {}


func cycle() -> void:
	if list.size() < 2:
		return
	idx = (idx + 1) % list.size()
	_cd = minf(_cd, 0.15)
	lock_target = null
	lock_t = 0.0
	Game.say(String(ARMS[current()]["name"]), 0.9)
	Sfx.play(&"ui_tap")


func select(k: StringName) -> bool:
	var i := list.find(k)
	if i < 0:
		return false
	idx = i
	return true


func locked() -> bool:
	return current() == &"missile" and is_instance_valid(lock_target) and lock_t >= LOCK_TIME


## The words on the AIM button: "MISSILE 8", "LOCKED 8", "BOMB 6" (two words: the touch HUD draws them on two lines).
func label() -> String:
	var k := current()
	if k == &"":
		return ""
	var n := int(ammo.get(k, 0))
	if k == &"missile" and is_instance_valid(lock_target):
		return ("LOCKED %d" if locked() else "LOCK %d") % n
	return "%s %d" % [String(ARMS[k]["short"]), n]


func flare_label() -> String:
	return "FLARE %d" % int(ammo.get(&"flare", 0))


## One physics tick from VehicleWeapons.tick_alt: reloads, the seeker, the ARMS / FLARE presses of the pilot, and a shot while `fire` is held. True when something left the rails.
func tick(dt: float, fire: bool) -> bool:
	_cd -= dt
	_flare_cd -= dt
	for k: StringName in _rl.keys():
		var full := int(ARMS[k]["ammo"])
		if int(ammo[k]) < full:
			_rl[k] = float(_rl[k]) + dt
			if float(_rl[k]) >= float(ARMS[k]["reload"]):
				_rl[k] = 0.0
				ammo[k] = int(ammo[k]) + 1
		else:
			_rl[k] = 0.0
	if car.driver_is_player:
		if InputMap.has_action(&"ammo_type") and Input.is_action_just_pressed(&"ammo_type"):
			cycle()
		if has_flare and InputMap.has_action(&"flare") and Input.is_action_just_pressed(&"flare"):
			fire_flares()
	if current() == &"missile":
		_seek(dt)
	if fire and _cd <= 0.0 and int(ammo.get(current(), 0)) > 0:
		return fire_now()
	return false


## Fire the selected arm now (a salvo of rockets, one missile, one bomb, one crate).
func fire_now() -> bool:
	var k := current()
	if k == &"" or int(ammo.get(k, 0)) <= 0 or _cd > 0.0:
		return false
	var d: Dictionary = ARMS[k]
	_cd = 1.0 / float(d["rate"])
	var fired := false
	match k:
		&"rocket":
			var origin := car.muzzle_pos()
			var dir := car.aim_dir()
			var right := dir.cross(Vector3.UP)
			right = right.normalized() if right.length() > 0.01 else car.right()
			for i in int(d["salvo"]):
				if int(ammo[k]) <= 0:
					break
				_side = -_side
				var o := origin + right * _side * (float(car.spec["wid"]) * 0.3) + Vector3(0.0, -0.5, 0.0)
				if AirRockets.launch(car, d, o, dir.rotated(Vector3.UP, _side * 0.012), null):
					ammo[k] = int(ammo[k]) - 1
					shots[k] = int(shots[k]) + 1
					fired = true
		&"missile":
			var tgt: Node3D = lock_target if locked() else null
			_side = -_side
			var o2 := car.muzzle_pos() + car.right() * _side * (float(car.spec["wid"]) * 0.25) + Vector3(0.0, -0.6, 0.0)
			var aim := car.aim_dir()
			if tgt == null:                                                          # not locked: straight at the crosshair from the rail (a rail is metres off the nose line)
				var to := VehicleCraft.aim_point(car) - o2
				if to.length() > 20.0 and to.normalized().angle_to(aim) < 0.3:
					aim = to.normalized()
			if AirRockets.launch(car, d, o2, aim, tgt):
				ammo[k] = int(ammo[k]) - 1
				shots[k] = int(shots[k]) + 1
				fired = true
		&"bomb", &"drop":
			var belly := car.global_position + Vector3(0.0, maxf(float(car.spec["hgt"]) * 0.15, 0.4) - 1.2, 0.0)
			if AirRockets.launch(car, d, belly, car.forward(), null):
				ammo[k] = int(ammo[k]) - 1
				shots[k] = int(shots[k]) + 1
				fired = true
				if k == &"drop":
					Game.say("CARGO AWAY", 1.0)
	return fired


## A burst of flares behind and under the aircraft: for FLARE_TIME every missile homing on it is fooled (AirRockets.fooled).
func fire_flares() -> bool:
	if not has_flare or int(ammo.get(&"flare", 0)) <= 0 or _flare_cd > 0.0:
		return false
	_flare_cd = 1.0 / float(ARMS[&"flare"]["rate"])
	ammo[&"flare"] = int(ammo[&"flare"]) - 1
	shots[&"flare"] = int(shots[&"flare"]) + 1
	flares_fired += 1
	car.set_meta(&"flare_until", Time.get_ticks_msec() + int(FLARE_TIME * 1000.0 / maxf(Engine.time_scale, 0.01)))
	var back := -car.forward()
	for i in int(ARMS[&"flare"]["burst"]):
		var side := car.right() * (float(i) - 1.0) * 2.2
		var at := car.global_position + back * (float(car.spec["len"]) * 0.5 + 1.0) + side + Vector3(0.0, -1.0, 0.0)
		FX.burst(at, Color(1.0, 0.95, 0.75), 6, 6.0, 0.9, 6.0, 0.9)
	Sfx.play_at(&"shot_flux", car.global_position, -6.0, 1.6)
	return true


## True while the aircraft `v` hides behind its flares.
static func flaring(v: Node) -> bool:
	return v != null and is_instance_valid(v) and v.has_meta(&"flare_until") and int(v.get_meta(&"flare_until")) > Time.get_ticks_msec()


# --- the missile seeker -------------------------------------------------------------------------------------------------------------------

func _seek(dt: float) -> void:
	var dir := car.aim_dir()
	if is_instance_valid(lock_target) and _valid_target(lock_target):
		var to := lock_target.global_position - car.global_position
		var rng := float(ARMS[&"missile"]["range"])
		if to.length() <= rng and to.normalized().angle_to(dir) <= (LOCK_KEEP if lock_t >= LOCK_TIME else LOCK_CONE):
			var was := lock_t >= LOCK_TIME
			lock_t += dt
			if not was and lock_t >= LOCK_TIME and car.driver_is_player:
				Sfx.play(&"ui_contract_accept")
			return
	lock_target = null
	lock_t = 0.0
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.1
	lock_target = find_target(dir)


func _valid_target(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree() or t == car:
		return false
	if t is Vehicle:
		var v := t as Vehicle
		return v.active and not v.dead and not v.wreck and not v.driver_is_player
	return not bool(t.get(&"dead")) if t.get(&"dead") != null else true


## The best target in the seeker's cone: hostile aircraft first (AirSteps bandits), then enemies and armed vehicles, nearest to the aim line.
func find_target(dir: Vector3) -> Node3D:
	var best: Node3D = null
	var bs := INF
	var o := car.global_position
	var rng := float(ARMS[&"missile"]["range"])
	for grp in [&"vehicle", &"enemy"]:
		for n: Node in car.get_tree().get_nodes_in_group(grp):
			var t := n as Node3D
			if not _valid_target(t):
				continue
			var d := t.global_position - o
			var dist := d.length()
			if dist < 15.0 or dist > rng:
				continue
			var ang := d.normalized().angle_to(dir)
			if ang > LOCK_CONE:
				continue
			var score := ang * 400.0 + dist * 0.1
			if t.has_meta(&"air_bandit"):
				score -= 1000.0
			if score < bs:
				bs = score
				best = t
	return best


# --- the HUD -----------------------------------------------------------------------------------------------------------------------------------

## Where a bomb dropped now lands (a few steps of the fall), Vector3.INF when it would not land within 20 s.
func bomb_impact() -> Vector3:
	var p := car.global_position + Vector3(0.0, -1.0, 0.0)
	var v := car.vel * float(ARMS[&"bomb"]["inherit"]) + Vector3(0.0, car.craft.vy if car.craft != null else 0.0, 0.0)
	var g := float(ARMS[&"bomb"]["grav"])
	for i in 200:
		var dt := 0.1
		v.y -= g * dt
		var n := p + v * dt
		var gy := TerrainHeight.height_at(n.x, n.z) if (absf(n.x) > TerrainHeight.CITY_HALF or absf(n.z) > TerrainHeight.CITY_HALF) else 0.0
		if n.y <= gy:
			return Vector3(n.x, gy, n.z)
		p = n
	return Vector3.INF


## The seeker box around the target and the bomb's landing ring, drawn over the world by FlightHud (two shapes, no node).
static func draw_hud(c: Control, v: Vehicle, s: float) -> void:
	if v == null or v.weapons == null or v.weapons.arms == null:
		return
	var a := v.weapons.arms as AirArms
	var cam := c.get_viewport().get_camera_3d()
	if cam == null:
		return
	if a.current() == &"missile" and is_instance_valid(a.lock_target):
		var tp := a.lock_target.global_position + Vector3(0.0, 1.0, 0.0)
		if not cam.is_position_behind(tp):
			var sp := cam.unproject_position(tp)
			var hs := 34.0 * s
			var col := Color(1.0, 0.3, 0.25, 0.95) if a.locked() else Color(1.0, 0.85, 0.3, 0.9)
			var k := clampf(a.lock_t / LOCK_TIME, 0.0, 1.0)
			var box := hs * (1.8 - 0.8 * k)
			var w := 3.0 * s
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := sp + Vector2(sx, sy) * box
					c.draw_line(corner, corner - Vector2(sx, 0.0) * box * 0.5, col, w)
					c.draw_line(corner, corner - Vector2(0.0, sy) * box * 0.5, col, w)
	elif a.current() == &"bomb" and v.craft != null and v.craft.airborne:
		var ip := a.bomb_impact()
		if ip.is_finite() and not cam.is_position_behind(ip):
			var sp2 := cam.unproject_position(ip)
			var vp := c.get_viewport_rect().size
			var m := 40.0 * s
			var inside := Rect2(Vector2(m, m), vp - Vector2(m, m) * 2.0)
			var lane := Rect2(Vector2(vp.x * 0.32, vp.y * 0.16), Vector2(vp.x * 0.36, vp.y * 0.64))      # the chevron keeps to the middle of the view, off the button clusters
			var col2 := Color(1.0, 0.55, 0.2, 0.92)
			if inside.has_point(sp2):
				c.draw_arc(sp2, 22.0 * s, 0.0, TAU, 28, col2, 3.0 * s, false)
				c.draw_line(sp2 - Vector2(8.0, 0.0) * s, sp2 + Vector2(8.0, 0.0) * s, col2, 2.0 * s)
			else:                                                                    # off the screen (below the nose): a chevron on the edge points to where it lands
				var e := Vector2(clampf(sp2.x, lane.position.x, lane.end.x), clampf(sp2.y, lane.position.y, lane.end.y))
				var dir := (sp2 - e).normalized() if sp2.distance_to(e) > 0.5 else Vector2.DOWN
				var side := Vector2(-dir.y, dir.x)
				c.draw_colored_polygon(PackedVector2Array([e + dir * 16.0 * s, e - dir * 8.0 * s + side * 13.0 * s, e - dir * 8.0 * s - side * 13.0 * s]), col2)
