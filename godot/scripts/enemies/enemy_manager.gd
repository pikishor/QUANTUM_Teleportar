class_name EnemyManager
extends Node
## Spawns, pools and rules the enemies (Game.enemies): patrols, reinforcements by heat, heat decay, the shared bolt pool and the lifecycle resets.
##
## Caps (alive at once, EnemyTypes.CAPS by graphics tier): LOW 5, MED 8, HIGH 12. spawn() returns null at the cap, so reinforcements, patrols and
## explicit callers all respect it. Patrols are 7 groups of 2-3 (sentinels; a heavy leads far groups; every third group is a squad of operatives),
## at least 110 m from the spawn. Only as many start as the tier allows (cap minus 2 slots kept for reinforcements); the other groups wait as
## dormant spots and are spawned when the player comes within 150 m and there is room.
## Reinforcements: while heat >= 1, floor(2 + heat * 2.6) enemies alive within 110 m of the player, spawned 38-75 m away on a road, a heavy from
## heat 3, strikers about 10 % (more in the heavy tiers), operatives about a third of the rest; reinforcements more than 170 m away are released.
## Heat decay: no aware enemy within 70 m for 7 s (Game.quiet) lowers heat by 0.12 per second.
## Bolts: one MultiMesh (a single draw call) with 48 pooled energy bolts (26-30 m/s, dodgeable) that hurt the player, a driven vehicle or the clone.

const BOLT_POOL := 48
const GRENADE_GAP := 4.0                  ## seconds between two grenade throws of the whole squad
const BOLT_LIFE := 3.0
const BOLT_COLOR_BOOST := 1.6
const BOLT_SHADER := preload("res://assets/shaders/fx_bolt.gdshader")
const BOLT_LEN := 3.6             ## streak length of a bolt (metres), see fx_bolt.gdshader
const REINFORCE_EVERY := 1.4
const REINFORCE_MIN := 28.0                  ## reinforcements arrive 28-55 m away on the road grid (was 38-75: the fight never reached the hero on a phone screen)
const REINFORCE_MAX := 55.0
const REINFORCE_HEAT_SHARE := 0.5            ## their kills add this share of the usual heat
const NEAR_RADIUS := 110.0
const CALLOUT_RADIUS := 45.0
const DESPAWN_DIST := 170.0
const PATROL_GROUPS := 7                     ## in the core of the map (the original 8 x 8 city), awake from the start as far as the tier allows
const PATROL_OUTER_GROUPS := 36              ## in the outer districts of the big city: dormant until the player comes within PATROL_STREAM_DIST
const PATROL_MIN_SPAWN_DIST := 110.0
const PATROL_STREAM_DIST := 150.0
const PATROL_SLEEP_DIST := 260.0             ## an unaware patrol this far from the player goes back to sleep (pooled, its group waits for the player again): the cap is for the fights around the hero
const QUIET_BEFORE_DECAY := 7.0
const HEAT_DECAY := 0.12
const AWARE_NEAR := 70.0
const LOD_EVERY := 0.25                      ## seconds between the distance LOD passes over the enemies (Drone.update_lod)
## Effect budget: decorative particle bursts of hits and deaths spend tokens (each live emitter is one draw call); the tier refills them. A death blast uses one of the
## pooled explosion slots: at most DEATH_BLASTS of them run at once per tier (the rest die with one cheap burst), so four deaths at once cannot add dozens of draws.
const FX_RATE := [5.0, 8.0, 14.0]
const FX_CAPACITY := [3.0, 4.0, 8.0]
const DEATH_BLASTS := [1, 1, 2]
const DEATH_BLAST_LIFE := 0.9

var list: Array[Drone] = []          ## every active enemy, corpses included until they are released

var _pool := {}                      ## type -> Array[Drone] (inactive)
var _groups: Array = []              ## dormant / spawned patrol spots {pos, types, spawned}
var _spawn_t := 0.0
var _think_frame := -1
var _think_used := 0
var _call_cd := 0.0
var reinforcement_calls := 0
const THINKERS := [2, 3, 5]                   ## expensive tactical searches (cover) allowed per physics frame, by tier
const CALL_COOLDOWN := 15.0
var _stream_t := 0.0
var _patrols_built := false
var _clone: Node3D
var _clone_frame := -1
var _noise_t := 0.0
var marks: EnemyMarks                ## threat rings, attack telegraph, health bars (3 draws for everybody)
var grenades: EnemyGrenades          ## the thrown grenades (a ball, a landing ring): only visible while one is live
var grenades_thrown := 0             ## lifetime count of enemy grenades thrown (tests and bots)
var _gren_cd := 0.0
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _b_pos := PackedVector3Array()
var _b_vel := PackedVector3Array()
var _b_org := PackedVector3Array()
var _b_life := PackedFloat32Array()
var _b_wait := PackedFloat32Array()
var _b_dmg := PackedFloat32Array()
var _b_refl := PackedByteArray()      ## 1 = reflected by the PHASE SHIELD: flies back and hurts enemies
var _b_type: Array[StringName] = []   ## the shooter's type per bolt (the barrier lets a sniper's bolt through)
var _fx_tokens := 6.0
var _fx_clock := 0.0
var _death_ends := PackedFloat32Array()
var _lod_t := 0.0
var _hidden_xform := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))


func _ready() -> void:
	Game.enemies = self
	DynamicFill.ensure_light(self)
	DynamicFill.set_quality(Game.quality)
	_build_bolts()
	marks = EnemyMarks.new()
	marks.name = "Marks"
	add_child(marks)
	grenades = EnemyGrenades.new()
	grenades.name = "Grenades"
	add_child(grenades)
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(_on_next_sector)
	Game.quality_changed.connect(_on_quality)
	_initial_patrols.call_deferred()


func _exit_tree() -> void:
	if Game.enemies == self:
		Game.enemies = null


func _initial_patrols() -> void:
	if not _patrols_built and is_inside_tree():
		init_patrols()


# --- API ------------------------------------------------------------------------------------------------------------

func cap() -> int:
	var n := LowPlus.scaled(EnemyTypes.CAPS[clampi(Game.quality, 0, 2)], LowPlus.ENEMY_SHARE, 2) if Game.quality == 0 else EnemyTypes.CAPS[clampi(Game.quality, 0, 2)]      # LOW+: 3 instead of 5
	return PerfTiers.cap_scale(n)      # Compatibility: 75 %


## Enemies that are alive (corpses do not count towards the cap).
func alive_count() -> int:
	var n := 0
	for e in list:
		if e.active and not e.dead:
			n += 1
	return n


## Activate an enemy of `type` (sentinel, striker, heavy, operative) at the ground position `pos`. Returns null at the cap.
## `look` >= 0 asks for a trooper of that roster look (HumanoidVariants.VAEL_CLASSES index): a pooled one is reused, else one is built (the encounter director's squads).
func spawn(type: StringName, pos: Vector3, aware := false, reinforce := false, want: StringName = &"", look := -1) -> Drone:
	if alive_count() >= cap():
		return null
	var d := _acquire(type, look)
	d.activate(pos, aware, reinforce)
	d.max_hp = float(d.cfg["hp"]) * (Progress.boss_hp_mult() if bool(d.cfg.get("boss", false)) else Progress.enemy_hp_mult())       # sector difficulty (1.0 in sector 1)
	if look >= 0 and d is Operative:
		d.max_hp *= (d as Operative).set_kit()                                               # the look decides the role: heavy, rusher, grenadier, marksman, commander
	d.hp = d.max_hp
	if not bool(d.cfg.get("boss", false)) and not InteriorGameplay.active:
		Factions.apply(d, Game.progress, Factions.assign(type, pos, want))             # camp, sight, speed and rim colour (scripts/enemies/factions.gd)
	if not list.has(d):
		list.append(d)
	return d


## Frees one slot of the tier's enemy cap for a mission: the enemy farthest from `from` that is not in `keep` goes back to the pool. A mission step, contract or side job has priority over the
## street's own patrols (found by the mission audit: "AREA CROWDED" forever when patrols filled the cap). False when nobody can go.
func make_room(keep: Array, from: Vector3) -> bool:
	var best: Drone = null
	var bd := -1.0
	for e in list:
		if not e.active or e.dead or keep.has(e):
			continue
		var d := Vector2(e.global_position.x - from.x, e.global_position.z - from.z).length() if from.is_finite() else 0.0
		if d > bd:
			bd = d
			best = e
	if best == null:
		return false
	release(best)
	return true


## Remove everybody (or only the reinforcements) and every flying bolt.
func clear(reinforcements_only := false) -> void:
	for e in list.duplicate():
		if not reinforcements_only or e.reinforce:
			release(e)
	for i in BOLT_POOL:
		_kill_bolt(i)
	if not reinforcements_only and grenades != null:
		grenades.clear()


## Back to the pool: the drone is hidden, out of the group and out of the simulation.
func release(d: Drone) -> void:
	if d.has_meta(&"patrol"):                                    # a patrol member: its group may go dormant again (see _sweep)
		var pg: Dictionary = d.get_meta(&"patrol")
		d.remove_meta(&"patrol")
		pg["live"] = maxi(0, int(pg.get("live", 1)) - 1)
		if bool(pg.get("sleeping", false)) and int(pg["live"]) == 0:
			pg["sleeping"] = false
			pg["spawned"] = false
	list.erase(d)
	d.deactivate()
	var arr: Array = _pool.get(d.type, [])
	if not arr.has(d):
		arr.append(d)
	_pool[d.type] = arr


## 7 patrol groups in the core far from the spawn (as many as the tier allows start right away, the rest wait for the player, see the class comment) plus
## PATROL_OUTER_GROUPS in the outer districts of the big city that only wake when the player comes close.
func init_patrols() -> void:
	_patrols_built = true
	_groups.clear()
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"random_road_point"):
		return
	var core_call: StringName = &"random_core_road_point" if w.has_method(&"random_core_road_point") else &"random_road_point"
	for g in PATROL_GROUPS + PATROL_OUTER_GROUPS:
		var outer := g >= PATROL_GROUPS
		var p := Vector3.INF
		for tries in 40:
			var q: Vector3 = w.call(&"random_road_point" if outer else core_call)
			if outer and absf(q.x) <= CityLayout.CORE_HALF and absf(q.z) <= CityLayout.CORE_HALF:
				continue
			if Vector2(q.x - Game.SPAWN.x, q.z - Game.SPAWN.z).length() >= PATROL_MIN_SPAWN_DIST:
				p = q
				break
		if not p.is_finite():
			continue
		var far := Vector2(p.x, p.z).length() > 200.0
		var types: Array[StringName] = []
		var camp := Factions.camp_for(p, fposmod(float(g) * 0.382, 1.0))            # the district's primary camp, its secondary one for about a quarter of the groups
		for i in 2 + (g % 2):
			var t: StringName = &"sentinel"
			if g % 3 == 2:
				t = &"operative"
			elif far and i == 0 and g % 3 == 0:
				t = &"heavy"
			types.append(Factions.fit_type(t, camp, 0))
		_groups.append({"pos": p, "types": types, "spawned": false, "camp": camp, "outer": outer, "live": 0})
	var ref := Game.SPAWN
	if is_instance_valid(Game.player):
		ref = Game.player.global_position
	_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a["pos"].x - ref.x, a["pos"].z - ref.z).length() < Vector2(b["pos"].x - ref.x, b["pos"].z - ref.z).length())
	_stream_patrols(true)


func patrol_groups() -> Array:
	return _groups


## Wake up unaware enemies within `radius` (a hit enemy tells its neighbours).
func alert_near(pos: Vector3, radius: float, except: Drone = null) -> void:
	for e in list:
		if e == except or e.dead or not e.active or e.aware:
			continue
		if Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length() < radius:
			e.alert()


## The player's superposition clone (a Node3D in group "clone", exposed as player.quantum.clone), or null. Cached per physics frame.
func get_clone() -> Node3D:
	var f := Engine.get_physics_frames()
	if f != _clone_frame:
		_clone_frame = f
		_clone = null
		var q := _quantum()
		if q != null:
			var c: Variant = q.call(&"decoy_pick") if q.has_method(&"decoy_pick") else q.get(&"clone")
			if c is Node3D and is_instance_valid(c):
				_clone = c as Node3D
	return _clone


func hit_clone() -> void:
	var q := _quantum()
	if q != null and q.has_method(&"collapse"):
		q.call(&"collapse")


func _quantum() -> Node:
	var p := Game.player
	if not is_instance_valid(p):
		return null
	var q: Variant = p.get(&"quantum")
	return q as Node if q is Node and is_instance_valid(q) else null


## Fire an energy bolt from `from` toward `to` (small random spread), `delay` seconds after now (burst rounds).
func bolt(from: Vector3, to: Vector3, type: StringName, delay := 0.0) -> void:
	var slot := -1
	for i in BOLT_POOL:
		if _b_life[i] <= 0.0:
			slot = i
			break
	if slot < 0:
		return
	var cfg := EnemyTypes.get_cfg(type)
	var dir := (to - from).normalized()
	var err := 1.0
	var pl := Game.player as Player
	if pl != null and is_instance_valid(pl):
		err = Difficulty.hurt_aim(pl.hp / maxf(pl.max_hp, 1.0)) * sqrt(Difficulty.mult("spread"))       # a hurt player is missed more often (Difficulty.hurt_aim); STORY 1.2x, HARD 0.87x
	dir += Vector3(randf_range(-0.035, 0.035), randf_range(-0.02, 0.02), randf_range(-0.035, 0.035)) * err
	dir = dir.normalized()
	_b_pos[slot] = from
	_b_org[slot] = from
	_b_vel[slot] = dir * float(cfg["bolt"])
	_b_life[slot] = BOLT_LIFE
	_b_wait[slot] = delay
	_b_dmg[slot] = float(cfg["dmg"])
	_b_refl[slot] = 0
	_b_type[slot] = type
	var c: Color = cfg["color"]
	_mm.set_instance_color(slot, Color(c.r * BOLT_COLOR_BOOST, c.g * BOLT_COLOR_BOOST, c.b * BOLT_COLOR_BOOST, 1.0))
	if delay <= 0.0:
		_set_bolt(slot, from, dir)
	else:
		_mm.set_instance_transform(slot, _hidden_xform)


func active_bolts() -> int:
	var n := 0
	for i in BOLT_POOL:
		if _b_life[i] > 0.0:
			n += 1
	return n


# --- lifecycle ------------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	_reset_all()


func _on_next_sector() -> void:
	_reset_all()


func _on_respawn() -> void:
	clear(true)
	_spawn_t = 0.0


func _reset_all() -> void:
	_death_ends.clear()
	_fx_tokens = float(FX_CAPACITY[clampi(Game.quality, 0, 2)])
	clear(false)
	_spawn_t = 0.0
	init_patrols()


func _on_quality(level: int) -> void:
	DynamicFill.set_quality(level)


# --- simulation -----------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_process_body(delta)
	PerfTimers.stop(PerfTimers.ENEMY_MGR, t0)


func _process_body(delta: float) -> void:
	var cam := Game.camera
	if is_instance_valid(cam):
		DynamicFill.aim_light(cam.global_rotation.y)
	marks.refresh(list)
	var tier := clampi(Game.quality, 0, 2)
	_fx_clock += delta
	_fx_tokens = minf(float(FX_CAPACITY[tier]), _fx_tokens + float(FX_RATE[tier]) * delta)
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = LOD_EVERY
		lod_pass()


## Distance LOD of every active enemy from the camera (shadows, small parts, hidden when far): see Drone.update_lod.
func lod_pass() -> void:
	var cam := Game.camera
	if not is_instance_valid(cam):
		return
	var cp := cam.global_position
	for e in list:
		if e.active:
			e.update_lod(cp.distance_to(e.global_position))


## Pre-warm (ShaderWarmup, under the loading overlay): one enemy of every type, aware and with its marks lit, at `at`; their models, textures, materials and marks are
## drawn once so the first fight has no load or shader hitch. Hand the returned enemies back with warm_end().
func warm_begin(at: Vector3) -> Array[Drone]:
	var out: Array[Drone] = []
	var i := 0
	for t: StringName in EnemyTypes.TYPES:
		if bool(EnemyTypes.TYPES[t].get("boss", false)):
			continue                                  # the Overseer is warmed by its contract (it would start the boss music)
		var d := _acquire(t)
		d.activate(at + Vector3(2.5 * i - 4.0, 0.0, 0.0), true)
		d.warm_marks()
		if not list.has(d):
			list.append(d)
		out.append(d)
		i += 1
	return out


func warm_end(warmed: Array[Drone]) -> void:
	for d in warmed:
		if is_instance_valid(d):
			release(d)


## One decorative particle burst allowed right now (spends a token); the enemies call it before FX.burst.
func fx_token() -> bool:
	if _fx_tokens >= 1.0:
		_fx_tokens -= 1.0
		return true
	return false


## A death may play a full explosion slot (true) or must make do with a cheap burst (false): at most DEATH_BLASTS[tier] blasts of enemy deaths run at once.
func death_blast() -> bool:
	var i := _death_ends.size() - 1
	while i >= 0:
		if _death_ends[i] <= _fx_clock:
			_death_ends.remove_at(i)
		i -= 1
	if _death_ends.size() >= int(DEATH_BLASTS[clampi(Game.quality, 0, 2)]):
		return false
	_death_ends.append(_fx_clock + DEATH_BLAST_LIFE)
	return true


## Cap on simultaneous thinkers: true when this frame still has a tactical-search slot.
func try_think() -> bool:
	var f := Engine.get_physics_frames()
	if f != _think_frame:
		_think_frame = f
		_think_used = 0
	if _think_used >= int(THINKERS[clampi(Game.quality, 0, 2)]):
		return false
	_think_used += 1
	return true


## A wounded soldier radios for help: one aware operative joins 38-75 m away (cap and cool-down apply). Returns it, or null.
func call_reinforcement(caller: Drone) -> Drone:
	if _call_cd > 0.0 or alive_count() >= cap() or InteriorGameplay.active:
		return null
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return null
	var pt: Vector3 = w.call(&"road_point_near", caller.global_position, 38.0, 75.0)
	if not pt.is_finite():
		return null
	var d := spawn(&"operative", pt, true, true)
	if d != null:
		_call_cd = CALL_COOLDOWN
		reinforcement_calls += 1
	return d


func _physics_process(delta: float) -> void:
	var t0 := PerfTimers.start()
	_physics_process_body(delta)
	PerfTimers.stop(PerfTimers.ENEMY_MGR, t0)


func _physics_process_body(delta: float) -> void:
	_call_cd = maxf(0.0, _call_cd - delta)
	if not Game.is_playing():
		return
	var p := Game.player
	var ppos := p.global_position if is_instance_valid(p) else Vector3.INF
	_sweep(ppos)
	if is_instance_valid(p):
		_tick_heat(delta, ppos)
		_tick_noise(delta, p)
		_tick_reinforcements(delta, ppos)
		_tick_stream(delta, ppos)
	_tick_bolts(delta)
	_tick_tactics(delta)


func _sweep(ppos: Vector3) -> void:
	var i := list.size() - 1
	while i >= 0:
		var e := list[i]
		if e.remove:
			release(e)
		elif e.reinforce and not e.dead and ppos.is_finite() \
				and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() > DESPAWN_DIST:
			release(e)
		elif not e.reinforce and not e.dead and not e.aware and e.has_meta(&"patrol") and ppos.is_finite() \
				and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() > PATROL_SLEEP_DIST:
			(e.get_meta(&"patrol") as Dictionary)["sleeping"] = true         # the big city: a patrol the player left behind frees its slots and waits for them again
			release(e)
		i = mini(i - 1, list.size() - 1)


## Stealth noise from the player: sprinting footsteps, a loud vehicle, and the SUPERPOSITION clone as a decoy.
func _tick_noise(delta: float, p: Node3D) -> void:
	_noise_t -= delta
	if _noise_t > 0.0:
		return
	_noise_t = Stealth.t("sprint_every")
	if p.get(&"sprinting") == true:
		Stealth.noise(list, p.global_position, &"sprint")
	var v: Variant = p.get(&"vehicle")
	if v is Node3D and is_instance_valid(v):
		Stealth.noise(list, (v as Node3D).global_position, &"vehicle", absf(float((v as Node3D).get(&"speed"))))
	var c := get_clone()
	if c != null:
		Stealth.noise(list, c.global_position, &"decoy")


func _tick_heat(delta: float, ppos: Vector3) -> void:
	var seen := false
	for e in list:
		if not e.dead and e.active and e.aware \
				and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() < AWARE_NEAR:
			seen = true
			break
	Game.quiet = 0.0 if seen else Game.quiet + delta
	if Game.quiet > QUIET_BEFORE_DECAY and Game.heat > 0.0:
		Game.heat = maxf(0.0, Game.heat - HEAT_DECAY * delta)


func _tick_reinforcements(delta: float, ppos: Vector3) -> void:
	_spawn_t -= delta
	if InteriorGameplay.active:
		return                                                    # inside a building the hunters are the interior's own (InteriorActors): the street sends nobody through the walls
	var enc := Encounters.current
	if enc != null and enc.set_busy():
		return                                                    # the director's patrol is the Watch's answer for now (Encounters.set_busy)
	var heat := Game.heat
	var want := (int(floor(2.0 + heat * 2.6)) + Factions.extra_slots(Game.progress, ppos)) if heat >= 1.0 else 0       # a hostile camp on its own ground sends one more
	if _spawn_t > 0.0 or want <= 0:
		return
	_spawn_t = REINFORCE_EVERY
	var near := 0
	for e in list:
		if not e.dead and e.active and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() < NEAR_RADIUS:
			near += 1
	if near >= want or alive_count() >= cap():
		return
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return
	var pt: Vector3 = w.call(&"road_point_near", ppos, REINFORCE_MIN, REINFORCE_MAX)
	if not pt.is_finite():
		return
	var camp := Factions.camp_for(pt, randf())
	var type := Factions.fit_type(pick_type(heat, randf(), _chapter(), randf(), randf(), randf()), camp, _chapter())
	if count_type(type) >= EnemyTypes.tier_limit(type, Game.quality) or (EnemyTypes.is_elite(type) and elite_count() >= EnemyTypes.ELITE_CAPS[clampi(Game.quality, 0, 2)]):
		type = &"operative"                                          # a specialist is capped per type (draw budget): the slot becomes a plain operative
	var d := spawn(type, pt, true, true, camp)
	if d != null:
		d.heat_scale = REINFORCE_HEAT_SHARE                       # a fight that goes on must not push the wanted level to the top by itself
		if d is Operative:
			(d as Operative).rush = true                          # reinforcements come in, they do not sit behind a car
		FX.burst(pt + Vector3(0.0, 1.0, 0.0), d.cfg["color"], 25, 6.0, 0.6, 0.0)


## Reinforcement mix for a roll r in 0..1: heavy from heat 3 (25 %), strikers 10 % (35 % band from heat 3), then a third operatives, rest sentinels.
## The reinforcement of a roll: the classic mix (pick_reinforcement_type) with operative slots turned into specialists by chapter and heat (EnemyTypes.specialist_for).
## `r_var` (default 1.0 = none) rolls the variety types and elites over an operative slot (EnemyTypes.variety_for).
static func pick_type(heat: float, r: float, chapter: int, r_spec: float, r_pick: float, r_var := 1.0) -> StringName:
	var t := pick_reinforcement_type(heat, r)
	if t == &"operative":
		var v := EnemyTypes.variety_for(chapter, heat, r_var, r_pick)
		if v != &"":
			return v
		return EnemyTypes.specialist_for(chapter, heat, r_spec, r_pick)
	return t


## Elite minibosses alive.
func elite_count() -> int:
	var n := 0
	for e in list:
		if e.active and not e.dead and EnemyTypes.is_elite(e.type):
			n += 1
	return n


func count_type(type: StringName) -> int:
	var n := 0
	for e in list:
		if e.type == type and e.active and not e.dead:
			n += 1
	return n


func chapter_now() -> int:
	return _chapter()


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) and Game.story.get("chapter") != null else 0


## Squad callout of `caller` (an operative that just noticed the target at `target`): every neighbour within CALLOUT_RADIUS wakes up and the operatives among them get
## alternating flank sides (nearest first: left, right, left...) for 8 s, so a squad arrives from both sides. Returns how many were alerted (not counting the flank orders).
func squad_callout(caller: Drone, _target: Vector3) -> int:
	var alerted := 0
	var near: Array[Operative] = []
	for e in list:
		if e == caller or e.dead or not e.active:
			continue
		if Vector2(e.global_position.x - caller.global_position.x, e.global_position.z - caller.global_position.z).length() > CALLOUT_RADIUS:
			continue
		if not e.aware:
			e.alert()
			alerted += 1
		if e is Operative and (e as Operative).role_flanks():
			near.append(e as Operative)
	near.sort_custom(func(a: Operative, b: Operative) -> bool:
		return a.global_position.distance_to(caller.global_position) < b.global_position.distance_to(caller.global_position))
	var every := 3
	if caller is Operative:
		every = int((caller as Operative)._row("push_every"))
	var side := -1.0 if (caller is Operative and (caller as Operative).flank_side() > 0.0) else 1.0
	if caller is Operative and (caller as Operative).uses_tactics():
		(caller as Operative).tactic_role = &"anchor"             # the one who spotted the target holds the line
	var i := 0
	for o in near:
		if i % every == every - 1 and o.uses_tactics():
			o.tactic_role = &"pusher"                              # every third neighbour pushes straight in
		else:
			o.tactic_role = &"flanker"
			o.assign_flank(side)
			side = -side
		i += 1
	return alerted


static func pick_reinforcement_type(heat: float, r: float) -> StringName:
	if heat >= 3.0 and r < 0.25:
		return &"heavy"
	var striker_to := 0.35 if heat >= 3.0 else 0.10
	if r < striker_to:
		return &"striker"
	if r < striker_to + 0.30:
		return &"operative"
	return &"sentinel"


func _tick_stream(delta: float, ppos: Vector3) -> void:
	if InteriorGameplay.active:
		return
	_stream_t -= delta
	if _stream_t > 0.0:
		return
	_stream_t = 1.0
	_stream_patrols(false, ppos)


func _stream_patrols(initial: bool, ppos := Vector3.INF) -> void:
	var patrol_cap := maxi(2, cap() - 2)
	for g: Dictionary in _groups:
		if g["spawned"]:
			continue
		var gp: Vector3 = g["pos"]
		if initial and bool(g.get("outer", false)):
			continue                                           # the outer districts wake when the player comes close
		if not initial and (not ppos.is_finite() or Vector2(gp.x - ppos.x, gp.z - ppos.z).length() > PATROL_STREAM_DIST):
			continue
		var types: Array = g["types"]
		var patrols := 0
		for e in list:
			if e.active and not e.dead and not e.reinforce:
				patrols += 1
		if patrols + types.size() > patrol_cap or alive_count() + types.size() > cap():
			if initial:
				continue
			return
		g["spawned"] = true
		g["sleeping"] = false
		for t: StringName in types:
			var pd: Drone = spawn(t, gp + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)), false, false, g.get("camp", &""))
			if pd != null:
				pd.set_meta(&"patrol", g)
				g["live"] = int(g.get("live", 0)) + 1


func _acquire(type: StringName, look := -1) -> Drone:
	if look >= 0 and not HumanoidVariants.available():
		look = -1                                            # no hero character files: the old model has no looks
	var arr: Array = _pool.get(type, [])
	if not arr.is_empty():
		if look >= 0:
			for i in range(arr.size() - 1, -1, -1):
				if (arr[i] as Drone).look_index() == look:
					return arr.pop_at(i) as Drone
		else:
			return arr.pop_back() as Drone
	var d: Drone
	if type == &"overseer":
		d = Overseer.new()
	elif EnemyTypes.TYPES.has(type) and EnemyTypes.TYPES[type].get("role", &"") == &"verb_boss":
		d = VerbBoss.new()
	elif EnemyTypes.is_specialist(type):
		d = Specialist.new()
	elif type == &"operative":
		d = Operative.new()
	else:
		d = Drone.new()
	if look >= 0 and EnemyTypes.TYPES.has(type) and EnemyTypes.TYPES[type].has("humanoid"):
		d.force_look = look
	add_child(d)
	d.setup(type)
	return d


# --- bolts ----------------------------------------------------------------------------------------------------------

func _build_bolts() -> void:
	_b_pos.resize(BOLT_POOL)
	_b_vel.resize(BOLT_POOL)
	_b_org.resize(BOLT_POOL)
	_b_life.resize(BOLT_POOL)
	_b_wait.resize(BOLT_POOL)
	_b_dmg.resize(BOLT_POOL)
	_b_refl.resize(BOLT_POOL)
	_b_type.resize(BOLT_POOL)
	_b_type.fill(&"")
	var sm := QuadMesh.new()                      # a glowing streak (white-hot head, coloured halo, tail), turned to the camera by the shader
	sm.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = BOLT_SHADER
	sm.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = sm
	_mm.instance_count = BOLT_POOL
	for i in BOLT_POOL:
		_mm.set_instance_transform(i, _hidden_xform)
		_mm.set_instance_color(i, Color.WHITE)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Bolts"
	_mmi.multimesh = _mm
	_mmi.custom_aabb = AABB(Vector3(-1300.0, -10.0, -1300.0), Vector3(2600.0, 200.0, 2600.0))
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Place one streak so that its head is at `pos` and it trails behind along `dir` (the shader turns it to face the camera around that axis).
func _set_bolt(i: int, pos: Vector3, dir: Vector3) -> void:
	var y := dir * BOLT_LEN
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var x := dir.cross(up).normalized() * 1.6          # width of the streak quad
	var z := x.cross(dir)
	_mm.set_instance_transform(i, Transform3D(Basis(x, y, z), pos - dir * (BOLT_LEN * 0.3)))


func _kill_bolt(i: int) -> void:
	_b_life[i] = 0.0
	_b_wait[i] = 0.0
	_mm.set_instance_transform(i, _hidden_xform)


func _tick_bolts(delta: float) -> void:
	var p := Game.player
	var player_ok := is_instance_valid(p)
	var ppos := p.global_position if player_ok else Vector3.ZERO
	var veh: Node3D = null
	if player_ok:
		var v: Variant = p.get(&"vehicle")
		if v is Node3D and is_instance_valid(v):
			veh = v as Node3D
	var clone := get_clone()
	var city := Game.world as City
	for i in BOLT_POOL:
		if _b_life[i] <= 0.0:
			continue
		if _b_wait[i] > 0.0:
			_b_wait[i] -= delta
			if _b_wait[i] <= 0.0:
				_set_bolt(i, _b_pos[i], _b_vel[i].normalized())
			continue
		var bd := delta * QuantumVerbs.slip_bolt(_b_pos[i]) if QuantumVerbs.slip_on else delta    # TIME SLIP slows bolts inside the bubble
		_b_life[i] -= bd
		var prev := _b_pos[i]
		var pos := prev + _b_vel[i] * bd
		_b_pos[i] = pos
		if QuantumVerbs.shield_on and _b_refl[i] == 0 and QuantumVerbs.shield_hit(prev, pos) and player_ok:
			var qv := p.get(&"qverbs") as QuantumVerbs
			var res := qv.shield_block(_b_type[i], _b_dmg[i]) if qv != null else 0
			if res == 1:
				_kill_bolt(i)
				FX.burst(pos, Color(0.4, 0.85, 1.0), 8, 5.0, 0.3, 4.0, 1.6)
				continue
			if res == 2:
				_b_refl[i] = 1
				var back := (_b_org[i] + Vector3(0, 1.0, 0) - pos).normalized()
				_b_vel[i] = back * maxf(_b_vel[i].length(), 20.0)
				_b_life[i] = maxf(_b_life[i], 1.2)
				FX.burst(pos, Color(0.4, 0.85, 1.0), 8, 5.0, 0.3, 4.0, 1.6)
				_set_bolt(i, pos, back)
				continue
		if _b_refl[i] == 1:
			var hit: Drone = null
			for d: Drone in list:
				if d.active and not d.dead and d.center().distance_to(pos) < d.radius + 0.5:
					hit = d
					break
			var spent := _b_life[i] <= 0.0 or pos.y < 0.0
			if hit != null:
				var rp := p.get(&"qverbs") as QuantumVerbs if player_ok else null
				if rp != null:
					rp.reflect_hits += 1
				hit.damage(maxf(_b_dmg[i] * QuantumVerbs.REFLECT_MULT, QuantumVerbs.REFLECT_MIN), false)
				spent = true
			if spent:
				_kill_bolt(i)
				FX.burst(pos, Color(0.4, 0.85, 1.0), 8, 5.0, 0.3, 4.0, 1.6)
			else:
				_set_bolt(i, pos, _b_vel[i].normalized())
			continue
		var gone := _b_life[i] <= 0.0 or pos.y < 0.0
		if not gone and city != null:
			gone = city.is_inside_building(pos)
		if not gone and clone != null:
			var cp := clone.global_position
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < 0.9 and pos.y < cp.y + 1.9 and pos.y > cp.y:
				gone = true
				hit_clone()
		if not gone and Companion.current != null and Companion.current.bolt_hit(pos, _b_dmg[i], _b_org[i]):
			gone = true
		if not gone and player_ok:
			if veh != null:
				var vp := veh.global_position
				if Vector2(pos.x - vp.x, pos.z - vp.z).length() < 2.1 and pos.y < vp.y + 2.0:
					gone = true
					p.call(&"damage", _b_dmg[i], _b_org[i])
			elif Vector2(pos.x - ppos.x, pos.z - ppos.z).length() < 0.6 and pos.y > ppos.y and pos.y < ppos.y + 1.9:
				gone = true
				p.call(&"damage", _b_dmg[i], _b_org[i])
		if gone:
			_kill_bolt(i)
			FX.burst(pos, Color(1.0, 0.5, 0.6), 8, 5.0, 0.3, 4.0, 1.6)
		else:
			_set_bolt(i, pos, _b_vel[i].normalized())


# --- tactics v2 (TacticsTable): hero hold, leapfrog slots, flush grenades, medics, commander buffs ----------------------

var hero_hold_t := 0.0                       ## seconds the hero has held cover
var force_hold := false                      ## tests: pretend the hero holds cover
var flush_throws := 0
var buffed_count := 0                        ## allies under a commander aura at the last refresh
var _flush_cd := 0.0
var _flush_live := 0
var _buff_t := 0.0


## The hero has held cover for at least `min_s` seconds.
func hero_holding(min_s := 3.0) -> bool:
	return hero_hold_t >= min_s


func _hero_in_cover() -> bool:
	var p := Game.player
	if not is_instance_valid(p):
		return false
	var c: Variant = p.get(&"cover")
	return c != null and bool((c as Object).get(&"in_cover"))


func _tick_tactics(delta: float) -> void:
	_flush_cd = maxf(0.0, _flush_cd - delta)
	_gren_cd = maxf(0.0, _gren_cd - delta)
	if force_hold or _hero_in_cover():
		hero_hold_t += delta
	else:
		hero_hold_t = 0.0
	_buff_t -= delta
	if _buff_t <= 0.0:
		_buff_t = TacticsTable.BUFF_EVERY
		_refresh_buffs()


func _refresh_buffs() -> void:
	buffed_count = 0
	var commanders: Array[Drone] = []
	for e in list:
		e.buff_dmg = 1.0
		e.buff_speed = 1.0
		if e.active and not e.dead and bool(e.cfg.get("commander", false)):
			commanders.append(e)
	if commanders.is_empty():
		return
	for e in list:
		if not e.active or e.dead or bool(e.cfg.get("commander", false)):
			continue
		for c in commanders:
			if c.global_position.distance_to(e.global_position) <= TacticsTable.BUFF_RADIUS:
				e.buff_dmg = TacticsTable.BUFF_DMG
				e.buff_speed = TacticsTable.BUFF_SPEED
				buffed_count += 1
				break


func leaping_near(who: Operative) -> int:
	var n := 0
	for e in list:
		if e != who and e.active and not e.dead and e is Operative and (e as Operative).is_leaping() \
				and e.global_position.distance_to(who.global_position) < TacticsTable.LEAP_SQUAD_RADIUS:
			n += 1
	return n


func flanking_near(who: Operative) -> int:
	var n := 0
	for e in list:
		if e != who and e.active and not e.dead and e is Operative and (e as Operative).tactic_role == &"flanker" and (e as Operative)._assigned_t > 0.0 \
				and e.global_position.distance_to(who.global_position) < TacticsTable.LEAP_SQUAD_RADIUS:
			n += 1
	return n


## Living allies of `who` within `radius` that are not retreating.
func allies_near(who: Drone, radius: float) -> int:
	var n := 0
	for e in list:
		if e == who or not e.active or e.dead or not e.aware:
			continue
		if e is Operative and (e as Operative).is_retreating():
			continue
		if e.global_position.distance_to(who.global_position) <= radius:
			n += 1
	return n


## The nearest living mender within MEDIC_CALL of `who`, or null.
func medic_for(who: Drone) -> Drone:
	var best: Drone = null
	var best_d := TacticsTable.MEDIC_CALL
	for e in list:
		if e == who or not e.active or e.dead or e.cfg.get("role", &"") != &"mender":
			continue
		var d := e.global_position.distance_to(who.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## The most wounded ally of a mender (lowest health share below PATIENT_BELOW, within PATIENT_RADIUS), or null.
func patient_for(medic: Drone) -> Drone:
	var best: Drone = null
	var best_f := TacticsTable.PATIENT_BELOW
	for e in list:
		if e == medic or not e.active or e.dead:
			continue
		var f := e.hp / maxf(e.max_hp, 1.0)
		if f < best_f and e.global_position.distance_to(medic.global_position) <= TacticsTable.PATIENT_RADIUS:
			best_f = f
			best = e
	return best


## Flush grenade at `at` from `who`: allowed after the hero has held cover long enough, with the squad cooldown and the per-tier cap on grenades in flight.
func try_flush(who: Operative, at: Vector3) -> bool:
	if _flush_cd > 0.0 or _flush_live >= TacticsTable.tier_cap(TacticsTable.FLUSH_ACTIVE, Game.quality) or not hero_holding(float(who._row("flush_hold"))):
		return false
	_flush_cd = TacticsTable.FLUSH_COOLDOWN
	_flush_live += 1
	flush_throws += 1
	FX.tracer(who.muzzle_world(), at + Vector3(0.0, 0.6, 0.0), Color(1.0, 0.7, 0.2))
	FX.burst(at + Vector3(0.0, 0.2, 0.0), Color(1.0, 0.6, 0.2), 4, 2.0, 0.3, 0.0)
	Sfx.play_at(&"enemy_shot", at, -6.0)
	get_tree().create_timer(TacticsTable.FLUSH_FUSE, false).timeout.connect(_flush_blast.bind(at))
	return true


func grenade_ready() -> bool:
	return grenades != null and _gren_cd <= 0.0 and grenades.live_count() < EnemyGrenades.max_live(Game.quality)


## A trooper throws a grenade at the hero: `who` must be allowed (squad cooldown GRENADE_GAP, the tier's limit in flight). The ball arcs from his hand to where the hero is walking.
func try_grenade(who: Operative) -> bool:
	if grenades == null or _gren_cd > 0.0 or not is_instance_valid(Game.player):
		return false
	var p := Game.player as Player
	var to := EnemyGrenades.lead_point(p.global_position, p.velocity, EnemyGrenades.flight_time(who.global_position.distance_to(p.global_position)))
	if not grenades.throw(who.muzzle_world(), to):
		return false
	_gren_cd = GRENADE_GAP
	grenades_thrown += 1
	return true


func _flush_blast(at: Vector3) -> void:
	_flush_live = maxi(0, _flush_live - 1)
	if not is_inside_tree():
		return
	Game.explode(at, TacticsTable.FLUSH_RADIUS, {"enemy_dmg": 0.0, "car_dmg": 10.0, "player_dmg": TacticsTable.FLUSH_DAMAGE, "color": Color(1.0, 0.6, 0.2)})
