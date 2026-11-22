class_name SnakeBlasts
extends Node
## WAVE 119 SNAKE BLASTS (owner: "different types of snakes also blasting apart from the weapons we have"; round 7: "snake bombs ... not working properly").
## Six snake SPECIES, each with its own look (colour, skin pattern, head, size) and its own burst, thrown with ONE round button (action `snake_blast`, the on-foot context slot of
## w119-hud5: label "<SPECIES> <count>", the recharge is the arc round it). HOLD the button: a ring in the species colour lies on the street where the snake will burst (its radius IS the
## blast radius); LET GO: the snake leaps from the hand along an arc and bursts exactly at the ring. A quick tap throws at once. The species is picked on the ABILITY wheel (disc SNAKE TYPE,
## which opens a ring of the six). Three charges, one back every RECHARGE seconds; no snake energy is used (the rope keeps it).
##   FIRE SNAKE     bursts in flame (knock, lift) and leaves BURNING GROUND (BlastOps.fire_field via the table's `fire`), burns everyone hit
##   FROST SNAKE    a field of stillness: everyone and every car in the ring FREEZES (table status freeze + the hold zone), five ice vipers stand round it (SnakeBombs._freeze)
##   SHOCK SNAKE    a stun burst, then lightning CHAINS to three foes in a row (SnakeBombs._chain with 3 hops)
##   ACID SNAKE     eats armour and vehicles: a heavy hit on cars and tanks and a CORROSION that keeps eating everyone and everything in the ring for four seconds
##   SWARM SNAKE    splits into small biters that hunt the foes in reach (SnakeBombs._swarm_burst)
##   GRAVITY SNAKE  PULLS foes and cars into the knot for 1.4 s (the table's `pre` well), then the collapse throws them up (SnakeBombs._gravity draws the knot)
## Damage, falloff, statuses, knockback and the look of the bang: BlastTable (entries sp_* in the category `snake_species`) and BlastFx; the snakes: the one SnakeSwarm MultiMesh (no new draw);
## the aim ring: one MeshInstance3D shown only while the button is held. Hook: SnakeWar._ready (attach); TouchControls (the BLAST label, the arc, the SNAKE TYPE disc); SnakeUi (the disc state).
## Counters (tests): thrown, bursts, by_id[id], corroded, last {id pos radius res}; flying.size() and corrode.size() go back to 0.

const SPECIES: Array[StringName] = [&"sp_fire", &"sp_frost", &"sp_shock", &"sp_acid", &"sp_swarm", &"sp_gravity"]
const CAT := &"snake_species"
const KIND_ACTION := &"snake_kind"                     ## the ABILITY wheel disc that opens the ring of species
const ACTION := &"snake_blast"
const RANGE := 30.0
const MIN_RANGE := 4.0
const CHARGES := 3
const RECHARGE := 5.0
const CORRODE_TIME := 4.0
## w119-critic: the fire species is BLAZE (its BLAST button read "FIRE 3" one thumb above the FIRE button).
const ROWS := {
	&"sp_fire": {"name": "BLAZE SNAKE", "short": "BLAZE", "color": Color(1.0, 0.36, 0.06), "pattern": 1, "thick": 0.12, "len": 2.6, "head": 1.25,
		"note": "BURSTS IN FLAME  THE GROUND BURNS FOR SIX SECONDS",
		"entry": {"name": "BLAZE SNAKE", "tag": "FIR", "radius": 5.5, "core": 1.5, "enemy": 70.0, "vehicle": 140.0, "element": &"fire", "knock": 5.0, "lift": 5.0, "curve": &"linear", "edge": 0.4,
			"status": {"k": &"burn", "t": 4.0, "p": 14.0}, "fire": [4.5, 6.0, 18.0], "fx": &"ember", "wave": &"flat", "crater": 0.3, "scorch": 1.4, "shake": 0.6, "level": 1, "snd": &"snw_burst"}},
	&"sp_frost": {"name": "FROST SNAKE", "short": "FROST", "color": Color(0.55, 0.9, 1.0), "pattern": 2, "thick": 0.085, "len": 3.2, "head": 1.0,
		"note": "EVERYONE AND EVERY CAR IN THE RING FREEZES FOR FIVE SECONDS",
		"entry": {"name": "FROST SNAKE", "tag": "FRS", "radius": 6.5, "core": 6.5, "enemy": 25.0, "vehicle": 20.0, "element": &"plasma", "knock": 0.0, "lift": 0.0, "curve": &"flat",
			"status": {"k": &"freeze", "t": 5.0, "p": 1.0}, "hold": 5.0, "fx": &"bubble", "wave": &"dome", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.4, "level": 0, "snd": &"shield_up",
			"snake": {"fangs": 5}}},
	&"sp_shock": {"name": "SHOCK SNAKE", "short": "SHOCK", "color": Color(1.0, 0.86, 0.2), "pattern": 3, "thick": 0.08, "len": 2.4, "head": 1.5,
		"note": "A STUN BURST  THEN LIGHTNING CHAINS TO THREE FOES",
		"entry": {"name": "SHOCK SNAKE", "tag": "SHK", "radius": 5.0, "core": 1.0, "enemy": 45.0, "vehicle": 60.0, "element": &"electric", "knock": 2.0, "lift": 2.0, "curve": &"linear", "edge": 0.4,
			"status": {"k": &"stun", "t": 1.6, "p": 1.0}, "fx": &"shock", "debris": &"sparks", "crater": 0.0, "scorch": 0.3, "shake": 0.6, "level": 0, "snd": &"snw_storm",
			"snake": {"hops": 3, "gap": 0.12, "hop_range": 10.0, "hop_dmg": 60.0}}},
	&"sp_acid": {"name": "ACID SNAKE", "short": "ACID", "color": Color(0.7, 1.0, 0.1), "pattern": 4, "thick": 0.14, "len": 2.2, "head": 1.1,
		"note": "EATS ARMOUR AND VEHICLES  KEEPS CORRODING FOR FOUR SECONDS",
		"entry": {"name": "ACID SNAKE", "tag": "ACD", "radius": 5.0, "core": 1.5, "enemy": 40.0, "vehicle": 320.0, "element": &"toxic", "knock": 1.0, "lift": 1.0, "curve": &"linear", "edge": 0.5,
			"fx": &"snake", "debris": &"none", "crater": 0.0, "scorch": 1.0, "shake": 0.4, "level": 0, "snd": &"snw_burst",
			"snake": {"dps_enemy": 16.0, "dps_vehicle": 90.0}}},
	&"sp_swarm": {"name": "SWARM SNAKE", "short": "SWARM", "color": Color(0.45, 1.0, 0.3), "pattern": 5, "thick": 0.065, "len": 1.5, "head": 0.8,
		"note": "SPLITS INTO SMALL BITERS THAT HUNT EVERYONE IN REACH",
		"entry": {"name": "SWARM SNAKE", "tag": "SWS", "radius": 8.0, "core": 0.0, "enemy": 20.0, "vehicle": 20.0, "element": &"toxic", "knock": 0.0, "lift": 0.0, "curve": &"linear", "edge": 0.4,
			"fx": &"snake", "debris": &"none", "crater": 0.0, "scorch": 0.0, "shake": 0.3, "level": 0, "snd": &"snw_burst",
			"snake": {"snakes": 8, "bite": 26.0, "speed": 13.0}}},
	&"sp_gravity": {"name": "GRAVITY SNAKE", "short": "GRAVITY", "color": Color(0.72, 0.38, 1.0), "pattern": 6, "thick": 0.15, "len": 3.0, "head": 1.6,
		"note": "PULLS FOES AND CARS INTO ONE KNOT  THEN BURSTS",
		"entry": {"name": "GRAVITY SNAKE", "tag": "GRS", "radius": 8.0, "core": 0.0, "enemy": 110.0, "vehicle": 140.0, "element": &"quantum", "knock": 3.0, "lift": 7.0, "curve": &"quad", "edge": 0.35,
			"status": {"k": &"pull", "t": 1.4, "p": 9.0}, "hold": 1.4, "fx": &"well", "wave": &"implode", "snd": &"collapse", "shake": 1.0, "level": 1, "snake": {"knots": 5}}},
}

static var instance: SnakeBlasts
static var _done := false
static var off := OS.get_environment("SNAKE_BLASTS_OFF") == "1"      ## the old behaviour (no species, no BLAST throw) for the fail-first run of tests/test_snake_blasts_w119.gd

var war: SnakeWar
var p: Player
var species: StringName = &"sp_fire"
var charges := CHARGES
var recharge_t := 0.0
var aiming := false
var aim_pt := Vector3.INF
var ring_radius := 0.0                                 ## the radius the ring shows (metres): the blast radius of the species with the hero's radius skill
var flying: Array[Dictionary] = []
var corrode: Array[Dictionary] = []
var thrown := 0
var bursts := 0
var corroded := 0
var denied := 0
var by_id: Dictionary = {}
var last: Dictionary = {}
var _was := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _rq := PhysicsRayQueryParameters3D.new()
var _puff_t := 0.0
var since_throw := 99.0                               ## seconds since the last throw (TouchControls keeps the context slot SNAKE BLAST for a while after it)


static func attach(w: SnakeWar) -> SnakeBlasts:
	if off:
		return null
	var b := SnakeBlasts.new()
	b.name = "SnakeBlasts"
	b.war = w
	w.add_child(b)
	return b


## Registers the six entries in the BlastTable (idempotent).
static func ensure() -> void:
	if _done and BlastTable.has_entry(&"sp_fire"):
		return
	_done = true
	for id: StringName in SPECIES:
		var e: Dictionary = ((ROWS[id] as Dictionary)["entry"] as Dictionary).duplicate(true)
		e["cat"] = CAT
		e["id"] = id
		e["friendly"] = false
		e["dmg"] = {"hero": 0.0, "civilian": 0.0}
		BlastTable.register(id, e)


static func row(id: StringName) -> Dictionary:
	return ROWS.get(id, {})


static func color_of(id: StringName) -> Color:
	return (ROWS.get(id, {}) as Dictionary).get("color", SnakeRows.CYAN)


func _ready() -> void:
	instance = self
	if war == null:
		war = get_parent() as SnakeWar
	p = war.p if war != null else null
	process_physics_priority = 7
	ensure()
	_rq.collision_mask = Game.L_WORLD
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func reset() -> void:
	flying.clear()
	corrode.clear()
	charges = CHARGES
	recharge_t = 0.0
	aiming = false
	_was = false
	_show_ring(false)


func select(id: StringName) -> bool:
	if not ROWS.has(id):
		return false
	species = id
	Sfx.play(&"ui_tap")
	return true


func radius_of(id: StringName) -> float:
	ensure()
	return float(BlastTable.entry(id).get("radius", 5.0)) * (war.radius_mult() if war != null else 1.0)


## The recharge share 0..1 of the next charge (0 = nothing to wait for).
func cd_fraction() -> float:
	return 0.0 if charges >= CHARGES or recharge_t <= 0.0 else clampf(recharge_t / RECHARGE, 0.0, 1.0)


# --- the tick ----------------------------------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if p == null or not is_instance_valid(p) or not Game.is_playing():
		_show_ring(false)
		return
	if charges < CHARGES:
		recharge_t -= dt
		if recharge_t <= 0.0:
			charges += 1
			recharge_t = RECHARGE if charges < CHARGES else 0.0
	since_throw += dt
	_step_flying(dt)
	_step_corrode(dt)
	var can := not p.is_dead() and p.vehicle == null
	var has := InputMap.has_action(ACTION)
	var down := can and has and Input.is_action_pressed(ACTION)
	var tapped := can and has and not down and Input.is_action_just_pressed(ACTION)      # pressed and let go inside one frame
	if down:
		aiming = true
		aim_pt = target_point()
		_show_ring(true)
	elif (_was and can) or tapped:
		aim_pt = target_point()
		throw()
		aiming = false
		_show_ring(false)
	else:
		aiming = false
		_show_ring(false)
	_was = down


## Where the snake bursts: what the crosshair is on (street, wall foot, enemy, car) within RANGE, put down on the ground under it. A crosshair on the sky or beyond the range lands
## at the range on the street ahead (the wave 115 quick cast threw at a point 3 m up in the air and its bomb went off 9 m above the street: nobody was hit).
func target_point() -> Vector3:
	var ar := SnakeAim.ray(p)
	var pt := SnakeAim.point(p, RANGE + 6.0)
	var hero := p.global_position
	var flat := Vector3(pt.x - hero.x, 0.0, pt.z - hero.z)
	var fwd := Vector3((ar[1] as Vector3).x, 0.0, (ar[1] as Vector3).z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else -p.global_basis.z
	if flat.length() > RANGE:
		flat = flat.normalized() * RANGE
	if flat.length() < MIN_RANGE:
		flat = fwd * MIN_RANGE
	var at := hero + flat
	return _ground(Vector3(at.x, maxf(pt.y, hero.y) + 1.5, at.z), hero.y)


func _ground(from: Vector3, floor_y: float) -> Vector3:
	_rq.from = from
	_rq.to = Vector3(from.x, floor_y - 25.0, from.z)
	_rq.exclude = [p.get_rid()]
	var r := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	return (r["position"] as Vector3) if not r.is_empty() else Vector3(from.x, floor_y, from.z)


# --- the throw and the flight --------------------------------------------------------------------------------------------------------------

## Sends the selected species to `aim_pt` (or the crosshair). False without a charge.
func throw(id: StringName = &"", at := Vector3.INF) -> bool:
	if id == &"":
		id = species
	if at == Vector3.INF:
		at = aim_pt if aim_pt != Vector3.INF else target_point()
	if charges <= 0:
		denied += 1
		Sfx.play(&"ui_deny", -4.0)
		UiSettings.buzz(10)
		return false
	ensure()
	charges -= 1
	if recharge_t <= 0.0:
		recharge_t = RECHARGE
	var from: Vector3 = p.snake.hand_pos(SnakeBombs.HERO_HAND) if p.snake != null else p.global_position + Vector3(0.0, 1.4, 0.0)
	var dist := from.distance_to(at)
	var secs := clampf(0.3 + dist / 40.0, 0.38, 1.05)
	var h := clampf(dist * 0.18, 1.2, 5.0)
	var f := {"id": id, "from": from, "to": at, "t": 0.0, "secs": secs, "h": h}
	flying.append(f)
	thrown += 1
	since_throw = 0.0
	var sw := war.swarm if war != null else null
	if sw != null:
		var r: Dictionary = ROWS[id]
		sw.spawn(&"crawl", from, {"color": r["color"], "thick": r["thick"], "len": r["len"], "head": r["head"], "pattern": int(r["pattern"]), "life": secs + 0.05, "prio": 3, "amp": 0.12, "rate": 2.2,
			"heading": (at - from).normalized(), "lift": 0.2,
			"tick": func(b: SnakeSwarm.Body, _dt: float) -> bool:
				var k := clampf(b.age / secs, 0.0, 1.0)
				var np := _arc(from, at, h, k)
				var d := np - b.pos
				if d.length() > 0.001:
					b.heading = d.normalized()
				b.pos = np
				return k < 1.0})
	Sfx.play(&"snw_bomb_throw", -3.0)
	UiSettings.buzz(20)
	p.camera_rig.kick(0.02)
	FX.burst(from, color_of(id), 6, 4.0, 0.3, 1.0, 1.0)
	return true


static func _arc(a: Vector3, b: Vector3, h: float, k: float) -> Vector3:
	return a.lerp(b + Vector3(0.0, 0.25, 0.0), k) + Vector3(0.0, sin(k * PI) * h, 0.0)


func _step_flying(dt: float) -> void:
	var i := flying.size() - 1
	while i >= 0:
		var f: Dictionary = flying[i]
		f["t"] = float(f["t"]) + dt
		if float(f["t"]) >= float(f["secs"]):
			flying.remove_at(i)
			burst(StringName(f["id"]), f["to"])
		i -= 1


# --- the bursts ------------------------------------------------------------------------------------------------------------------------

func burst(id: StringName, pos: Vector3) -> Dictionary:
	ensure()
	var rm := war.radius_mult()
	var radius := radius_of(id)
	var res := BlastTable.apply(id, pos + Vector3(0.0, 0.15, 0.0), p, {"by_hero": true, "dmg_mult": war.dmg_mult(), "radius_mult": rm})
	last = {"id": id, "pos": pos, "radius": radius, "res": res.duplicate()}
	bursts += 1
	by_id[id] = int(by_id.get(id, 0)) + 1
	var col := color_of(id)
	var bombs := war.bombs
	war.react.on_blast(id, pos, radius)
	match id:
		&"sp_fire":
			bombs._burst_snakes(pos, col, 6, radius, 0.55)
		&"sp_frost":
			bombs._freeze(id, pos)
		&"sp_shock":
			bombs._burst_snakes(pos, col, 4, radius * 0.6, 0.4)
			if BlastFx.shared() != null:
				BlastFx.shared().dome(pos, radius, col, 0.12, 0.08, 0.25, 0.7, 5.0)        # a crackling shell for a blink: the burst reads as electric at street distance
			bombs._chain(id, pos)
		&"sp_acid":
			bombs._burst_snakes(pos, col, 5, radius, 0.6)
			_start_corrode(id, pos, radius)
			if BlastFx.shared() != null:
				BlastFx.shared().dome(pos, radius, col, CORRODE_TIME - 0.5, 0.3, 0.5, 0.22, 2.0)   # a faint acid shell: where it keeps eating
		&"sp_swarm":
			bombs._swarm_burst(id, pos)
		&"sp_gravity":
			bombs._gravity(id, pos)
	return res


func _start_corrode(id: StringName, pos: Vector3, radius: float) -> void:
	var sn: Dictionary = BlastTable.entry(id).get("snake", {})
	corrode.append({"pos": pos, "radius": radius, "left": CORRODE_TIME, "tick": 0.0, "de": float(sn.get("dps_enemy", 16.0)) * war.dmg_mult(), "dv": float(sn.get("dps_vehicle", 90.0)) * war.dmg_mult(),
			"col": color_of(id)})


## The acid keeps eating: twice a second everyone and every car inside the ring takes its share; green fumes rise (BlastFx cloud puffs).
func _step_corrode(dt: float) -> void:
	var i := corrode.size() - 1
	while i >= 0:
		var z: Dictionary = corrode[i]
		z["left"] = float(z["left"]) - dt
		z["tick"] = float(z["tick"]) - dt
		if float(z["tick"]) <= 0.0:
			z["tick"] = 0.5
			var pos: Vector3 = z["pos"]
			var r := float(z["radius"])
			for en: Node3D in Gear.living_enemies(get_tree()):
				if en.global_position.distance_to(pos) <= r:
					var amt := TestMode.damage(float(z["de"]) * 0.5)
					en.call(&"damage", amt)
					BlastCredit.dealt(en, amt, Vector3.INF, false)
					corroded += 1
			for v: Node in get_tree().get_nodes_in_group(&"vehicle"):
				var vn := v as Node3D
				if vn == null or PlayerWeapon._is_dead(vn) or vn == p.vehicle:
					continue
				if vn.global_position.distance_to(pos) <= r + 1.0:
					vn.call(&"damage", float(z["dv"]) * 0.5)
					corroded += 1
			var fx := BlastFx.shared()
			if fx != null:
				var col: Color = z["col"]
				for k in (3 if Game.quality == 0 else 5):                                # a low haze that hugs the street (a puff that rose 2 m read as a green blob floating over the foes)
					var a := randf() * TAU
					var rr := sqrt(randf()) * r * 0.85
					fx.puff(pos + Vector3(cos(a) * rr, 0.15, sin(a) * rr), Vector3(cos(a) * 0.4, 0.25, sin(a) * 0.4), 1.0, 2.6, 1.2, Color(col.r * 0.55, col.g * 0.75, col.b * 0.2, 0.42))
		if float(z["left"]) <= 0.0:
			corrode.remove_at(i)
		i -= 1


# --- the aim ring ----------------------------------------------------------------------------------------------------------------------

func _show_ring(on: bool) -> void:
	if not on:
		if _ring != null:
			_ring.visible = false
		ring_radius = 0.0 if not aiming else ring_radius
		return
	if _ring == null:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.93
		tm.outer_radius = 1.0
		tm.rings = 48
		tm.ring_segments = 4
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.no_depth_test = false
		_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		tm.material = _ring_mat
		_ring = MeshInstance3D.new()
		_ring.name = "SnakeBlastRing"
		_ring.mesh = tm
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.top_level = true
		add_child(_ring)
	ring_radius = radius_of(species)
	var col := color_of(species)
	var pulse := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.012)
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, (0.9 if charges > 0 else 0.35) * pulse)
	_ring.global_transform = Transform3D(Basis.from_scale(Vector3(ring_radius, 1.5, ring_radius)), aim_pt + Vector3(0.0, 0.1, 0.0))
	_ring.visible = true


# --- the HUD and the wheel ----------------------------------------------------------------------------------------------------------------

## The BLAST button: "BLAZE 3" (the species and the charges left).
static func button_label() -> String:
	if not is_instance_valid(instance):
		return "BLAST"
	if TouchControls.CRITIC_OLD and instance.species == &"sp_fire":
		return "FIRE %d" % instance.charges                                                  # the old label, for the fail-first run only
	return "%s %d" % [String((ROWS[instance.species] as Dictionary)["short"]), instance.charges]


## The arcs of the BLAST button: the species colour as a ring; the recharge of the next charge as a growing arc. Rows in TouchControls' `arcs` list format [centre, radius, end angle, colour].
static func button_arcs(arcs: Array, centre: Vector2, r: float, s: float) -> void:
	if not is_instance_valid(instance):
		return
	var col := color_of(instance.species)
	var cdf := instance.cd_fraction()
	if instance.charges >= CHARGES or cdf <= 0.0:
		arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU, Color(col, 0.9)])
	else:
		arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * (1.0 - cdf), Color(col, 0.9 if instance.charges > 0 else 0.5)])


## The SNAKE TYPE disc of the ABILITY wheel.
static func kind_state() -> Dictionary:
	if not is_instance_valid(instance):
		return {"ready": false, "active": false, "cd": 0.0}
	return {"ready": true, "active": instance.aiming, "cd": instance.cd_fraction() if instance.charges == 0 else 0.0}


static func kind_label() -> String:
	if not is_instance_valid(instance):
		return "SNAKE TYPE"
	return "SNAKE %s" % String((ROWS[instance.species] as Dictionary)["short"])           # "SNAKE FIRE": the snake discs of the wheel all start with SNAKE


## The ring of the six species (ABILITY wheel format).
static func ring_items() -> Array:
	var out: Array = []
	for id: StringName in SPECIES:
		out.append({"id": id, "label": String((ROWS[id] as Dictionary)["short"]), "ready": true, "active": is_instance_valid(instance) and instance.species == id, "cd": 0.0,
				"current": is_instance_valid(instance) and instance.species == id})
	return out


## TouchControls._wheel_pick on the ABILITY wheel: SNAKE TYPE opens the ring of species; a species disc picks it. Returns 0 = not ours, 1 = handled (close), 2 = a ring opened (stay open).
static func wheel_pick(tc: Node, id: StringName) -> int:
	if off:
		return 0
	if id == KIND_ACTION:
		var wh: Variant = tc.get("wheel")
		if wh == null:
			return 1
		wh.call(&"open_at", &"ability", ring_items(), wh.get("centre"), wh.get("scale"), true, tc.call(&"wheel_bounds"))
		Sfx.play(&"ui_tap")
		return 2 if bool(wh.get("is_open")) else 1
	if ROWS.has(id):
		if is_instance_valid(instance):
			instance.select(id)
		return 1
	return 0
