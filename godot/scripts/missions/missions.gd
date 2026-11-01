class_name Missions
extends Node
## Sector objective and pickups. Port of ../src/missions.js.
##
## Quantum cores stand on distinct inner junctions (>= 140 m from the spawn, >= 110 m apart) and show a tall magenta beam that is visible from anywhere;
## walking or driving within 4 m collects one (+250 score, full energy). The last core calls Game.win(). Drones drop `health` (+30) and `energy` (+35)
## pickups through drop(kind, pos): pooled, 40 s life, bobbing, 2.2 m pickup radius (also for a driven vehicle).
##
## API: cores: Array (remaining cores, each {pos: Vector3, node: Node3D, got: bool}) · pickups: Array (active pickups, each {kind, pos, t, node}) ·
## got · total · rounds · new_round(total := 6) · drop(kind, pos) · nearest_core(pos) -> {pos, dist} ({} if none) · clear_pickups().
## Lifecycle: new_game -> rounds = 0 and a fresh round of 6; next_sector -> min(9, 6 + rounds) cores; respawn keeps the cores and drops the pickups.
## Contracts: `contracts` (Contracts) adds six procedural side-mission kinds chosen by the story chapter; `progress` (Progress, also Game.progress) holds the credit wallet,
## shop upgrades, reputation and the save file. See ARCHITECTURE.md "Gameplay depth as implemented".
## Cost: a core is one beam (1 draw), one ground ring (1 draw), and, within GEM_NEAR metres of the camera only, the gem model (4 draws) and an omni light.

const CORE_MIN_SPAWN := 140.0
const CORE_MIN_APART := 110.0
const CORE_RADIUS := 4.0
const CORE_SCORE := 250
const CORE_MAX := 9
const BEAM_HEIGHT := 420.0
const GEM_HOVER := 1.1                 ## the gem model (origin at ground contact) floats this far above the street
const GEM_NEAR := 110.0                ## gem model and light are shown within this camera distance (hysteresis +20 m)
const PICKUP_POOL := 8
const COLUMN_CAP := [1, 2, 8]               ## light columns of pickups drawn at once per tier (LOW, MED, HIGH): a 4-enemy wipe would add 4 draws (+4 more in the mirror)
const PICKUP_RADIUS := 2.2
const PICKUP_LIFE := 40.0
const PICKUP_HOVER := 0.5
const HEALTH_AMOUNT := 30.0
const ENERGY_AMOUNT := 35.0
const VERTICAL_REACH := 6.0            ## a player on a roof above a junction does not collect it
const KINDS: Array[StringName] = [&"health", &"energy", &"weapon"]     ## weapon pickups carry a weapon id (drop(&"weapon", pos, &"scatter")): a new weapon or an ammo pack

var cores: Array = []
var pickups: Array = []
var got := 0
var total := 6
var rounds := 0
## Procedural side missions (scripts/missions/contracts.gd) and the campaign state (scripts/progress/progress.gd): both are children of this node.
var contracts: Contracts
var progress: Progress
## Placement randomness: tests seed it for reproducible layouts.
var rng := RandomNumberGenerator.new()

var _root: Node3D
var _core_pool: Array[Dictionary] = []      ## the core entries themselves ({node, pos, got, gem, ring, beam, light}): built lazily, at most CORE_MAX
var _pickup_pool: Array[Dictionary] = []
var _mirror: MirrorProxy
var _mirror_list: Array[MeshInstance3D] = []
var _t := 0.0
var _auto_started := false
var _fill_script: Script


func _ready() -> void:
	Game.missions = self
	add_to_group(&"missions")
	rng.randomize()
	_root = Node3D.new()
	_root.name = "MissionNodes"
	add_child(_root)
	_mirror = MirrorProxy.new()
	add_child(_mirror)
	if ResourceLoader.exists("res://scripts/common/dynamic_fill.gd"):
		_fill_script = load("res://scripts/common/dynamic_fill.gd") as Script
		if _fill_script != null and _fill_script.has_method(&"ensure_light"):
			_fill_script.call(&"ensure_light", self)             # the shared character fill light (one for the whole game)
	_build_pickup_pool()
	progress = Progress.new()
	progress.name = "Progress"
	add_child(progress)
	contracts = Contracts.new()
	contracts.name = "Contracts"
	add_child(contracts)
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(_on_next_sector)
	Game.quality_changed.connect(_on_quality)
	_try_auto_start()


func _exit_tree() -> void:
	if Game.missions == self:
		Game.missions = null


# --- public API --------------------------------------------------------------------------------------------------

## Remove the current cores and place `n_cores` new ones (rounds += 1). Returns the number actually placed (`total`).
func new_round(n_cores := 6) -> int:
	for c: Dictionary in cores:
		_hide_core(c)
	cores.clear()
	got = 0
	rounds += 1
	var spots := _pick_spots(clampi(n_cores, 1, CORE_MAX))
	for i in spots.size():
		var c := _core_entry(i)
		c.pos = spots[i]
		c.got = false
		(c.node as Node3D).position = spots[i]
		(c.node as Node3D).visible = true
		_show_core_parts(c, true)
		cores.append(c)
	total = cores.size()
	return total


## Spawn a pickup of kind `health` or `energy` at a world position (it settles on the floor below). Reuses the oldest slot when all are in use.
func drop(kind: StringName, pos: Vector3, weapon_id := &"") -> void:
	if not kind in KINDS:
		return
	var slot: Dictionary = {}
	for s in _pickup_pool:
		if not s.active:
			slot = s
			break
	if slot.is_empty():
		slot = _pickup_pool[0]
		for s in _pickup_pool:
			if s.t < slot.t:
				slot = s
		pickups.erase(slot)
	var ground := pos
	if is_instance_valid(Game.world) and Game.world.has_method(&"ground_height"):
		ground.y = Game.world.call(&"ground_height", pos.x, pos.z, pos.y + 2.0)
	else:
		ground.y = 0.0
	slot.active = true
	slot.kind = kind
	slot.weapon = weapon_id if kind == &"weapon" else &""
	slot.pos = ground
	slot.t = PICKUP_LIFE
	slot.phase = rng.randf() * TAU
	var node: Node3D = slot.node
	node.position = ground + Vector3(0.0, PICKUP_HOVER, 0.0)
	for k: StringName in KINDS:
		(slot.models[k] as Node3D).visible = (k == kind)
	(slot.halo as MeshInstance3D).material_override = slot.halos[kind]
	(slot.column as MeshInstance3D).material_override = slot.columns[kind]
	(slot.halo as MeshInstance3D).visible = true
	var columns_on := 0                                  # the light column is a draw of its own: only the first few at once (tier cap), the rest keep halo + gem
	for o: Dictionary in pickups:
		if o != slot and (o.column as MeshInstance3D).visible:
			columns_on += 1
	(slot.column as MeshInstance3D).visible = columns_on < COLUMN_CAP[clampi(Game.quality, 0, 2)]
	node.visible = true
	pickups.append(slot)


## A weapon pickup (a new weapon or an ammo pack) of weapon id `id`.
func drop_weapon(id: StringName, pos: Vector3) -> void:
	drop(&"weapon", pos, id)


func nearest_core(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for c: Dictionary in cores:
		var cp: Vector3 = c.pos
		var d := Vector2(cp.x - pos.x, cp.z - pos.z).length()
		if d < bd:
			bd = d
			best = c
	if best.is_empty():
		return {}
	return {pos = best.pos, dist = bd}


func clear_pickups() -> void:
	for s in _pickup_pool:
		s.active = false
		(s.node as Node3D).visible = false
	pickups.clear()


# --- lifecycle ---------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	clear_pickups()
	rounds = 0
	_auto_started = true
	new_round(6)


func _on_respawn() -> void:
	clear_pickups()


func _on_next_sector() -> void:
	clear_pickups()
	_auto_started = true
	new_round(mini(CORE_MAX, 6 + rounds))


func _try_auto_start() -> void:
	# Tools, tests and bots skip the menu (no new_game signal): the first round is built as soon as a world exists.
	if _auto_started or not cores.is_empty() or rounds > 0:
		return
	if is_instance_valid(Game.world) and "intersections" in Game.world and not Game.world.intersections.is_empty():
		_auto_started = true
		new_round(6)


# --- placement ---------------------------------------------------------------------------------------------------

## Choose up to n junction positions: >= CORE_MIN_SPAWN from the spawn, >= CORE_MIN_APART from each other. A greedy random pass can end short,
## so a few shuffles are tried and the best result is kept.
func _pick_spots(n: int) -> Array[Vector3]:
	var best: Array[Vector3] = []
	if not is_instance_valid(Game.world) or not "intersections" in Game.world:
		return best
	var candidates: Array[Vector3] = []
	for p: Vector3 in Game.world.intersections:
		if Vector2(p.x - Game.SPAWN.x, p.z - Game.SPAWN.z).length() >= CORE_MIN_SPAWN:
			candidates.append(p)
	for attempt in 24:
		_shuffle(candidates)
		var chosen: Array[Vector3] = []
		for s in candidates:
			if chosen.size() >= n:
				break
			var ok := true
			for c in chosen:
				if Vector2(c.x - s.x, c.z - s.z).length() < CORE_MIN_APART:
					ok = false
					break
			if ok:
				chosen.append(s)
		if chosen.size() > best.size():
			best = chosen
		if best.size() >= n:
			break
	return best


func _shuffle(a: Array[Vector3]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


# --- simulation --------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if not _auto_started:
		_try_auto_start()
	var player := Game.player
	if not is_instance_valid(player):
		return
	var ref := player.global_position
	var veh := player.get(&"vehicle") as Node3D
	if veh != null and is_instance_valid(veh):
		ref = veh.global_position
	var i := pickups.size() - 1
	while i >= 0:
		var s: Dictionary = pickups[i]
		s.t -= delta
		var pp: Vector3 = s.pos
		if s.t <= 0.0:
			_release_pickup(s, i)
		elif Vector2(pp.x - ref.x, pp.z - ref.z).length() < PICKUP_RADIUS and absf(pp.y - ref.y) < VERTICAL_REACH * 0.5:
			_collect_pickup(s, i, player)
		i -= 1
	i = cores.size() - 1
	while i >= 0:
		var c: Dictionary = cores[i]
		var cp: Vector3 = c.pos
		if Vector2(cp.x - ref.x, cp.z - ref.z).length() < CORE_RADIUS and absf(cp.y - ref.y) < VERTICAL_REACH:
			_collect_core(c, i, player)
		i -= 1
	if cores.is_empty() and total > 0 and Game.is_playing():
		Game.win()


func _collect_pickup(s: Dictionary, idx: int, player: Node3D) -> void:
	if s.kind == &"weapon":
		var w: Variant = player.get(&"weapon")
		if w is PlayerWeapon:
			Game.say((w as PlayerWeapon).grant(s.weapon), 2.0)
	elif s.kind == &"health":
		player.call(&"heal", HEALTH_AMOUNT)
		Game.say("+30 INTEGRITY", 1.2)
	else:
		player.call(&"add_energy", ENERGY_AMOUNT)
		Game.say("+35 COHERENCE", 1.2)
	var col := _kind_color(s.kind)
	var at: Vector3 = (s.node as Node3D).global_position
	FX.burst(at, col, 14, 4.0, 0.5, 4.0, 1.0)
	Sfx.play(&"pickup")
	_release_pickup(s, idx)


static func _kind_color(kind: StringName) -> Color:
	if kind == &"weapon":
		return WeaponDefs.COLOR_PICKUP
	return MissionVisuals.HEALTH_GREEN if kind == &"health" else MissionVisuals.ENERGY_CYAN


func _release_pickup(s: Dictionary, idx: int) -> void:
	s.active = false
	(s.node as Node3D).visible = false
	pickups.remove_at(idx)


func _collect_core(c: Dictionary, idx: int, player: Node3D) -> void:
	c.got = true
	got += 1
	Game.add_score(CORE_SCORE)
	var max_e: Variant = player.get(&"max_energy")
	player.call(&"add_energy", float(max_e) if max_e != null else 100.0)
	var at: Vector3 = c.pos
	at.y += GEM_HOVER + 0.95
	FX.burst(at, MissionVisuals.CORE_MAGENTA, 60, 10.0, 1.0, 1.0, 1.0)
	FX.blast(at, 7.0, MissionVisuals.CORE_MAGENTA, 0.6)
	Sfx.play(&"core")
	Game.say("QUANTUM CORE RECOVERED  %d/%d" % [got, total], 2.0)
	_hide_core(c)
	cores.remove_at(idx)


func _process(delta: float) -> void:
	_t += delta
	var cam_pos := Vector3.ZERO
	var have_cam := is_instance_valid(Game.camera)
	if have_cam:
		cam_pos = Game.camera.global_position
	for c: Dictionary in cores:
		var node: Node3D = c.node
		var gem: Node3D = c.gem
		var cp: Vector3 = c.pos
		var d := Vector2(cp.x - cam_pos.x, cp.z - cam_pos.z).length() if have_cam else 0.0
		var near: bool = d < (GEM_NEAR + 20.0 if gem.visible else GEM_NEAR)
		if near != gem.visible:
			gem.visible = near
			(c.light as OmniLight3D).visible = near and Game.quality > 0
		if near:
			gem.rotation.y += delta * 1.6
			gem.position.y = GEM_HOVER + sin(_t * 1.8 + cp.x) * 0.15
			(c.ring as Node3D).scale = Vector3(1.0, 0.05, 1.0) * (1.0 + 0.03 * sin(_t * 3.0))
			(c.light as OmniLight3D).light_energy = 2.2 + 0.4 * sin(_t * 3.0)
	for s: Dictionary in pickups:
		var node: Node3D = s.node
		var pp: Vector3 = s.pos
		var ph: float = s.phase
		node.position.y = pp.y + PICKUP_HOVER + sin(_t * 3.0 + ph) * 0.12
		node.rotation.y += delta * 2.0
		# the last 5 s of its life it blinks, like a timed pickup should
		var blink: bool = s.t < 5.0 and int(s.t * 6.0) % 2 == 0
		(s.halo as MeshInstance3D).visible = not blink


# --- nodes ---------------------------------------------------------------------------------------------------------

func _core_entry(i: int) -> Dictionary:
	while _core_pool.size() <= i:
		_core_pool.append(_build_core())
	return _core_pool[i]


func _build_core() -> Dictionary:
	var root := Node3D.new()
	root.name = "Core%d" % _core_pool.size()
	root.visible = false
	var model := Game.load_model("core_gem")
	if model == null:
		model = MissionVisuals.fallback_gem()
	else:
		_apply_fill(model, MissionVisuals.CORE_MAGENTA)       # first: the glow tints below replace its glow surfaces
		MissionVisuals.tint_glow(model, "core_gem", {
			&"Glow": [MissionVisuals.CORE_MAGENTA, 2.2],
			&"GlowRing": [MissionVisuals.CORE_CYAN, 1.8],
		})
	var gem := Node3D.new()                 # hover and spin pivot, so the model itself stays untouched
	gem.name = "Gem"
	gem.add_child(model)
	gem.position.y = GEM_HOVER
	root.add_child(gem)
	var beam := MissionVisuals.make_beam(MissionVisuals.CORE_MAGENTA, 1.1, BEAM_HEIGHT, 1.5, 0.4)
	beam.name = "Beam"
	beam.position.y = BEAM_HEIGHT * 0.5 + GEM_HOVER + 1.5     # the column rises out of the floating gem, so the crystal itself stays visible
	root.add_child(beam)
	var ring := MissionVisuals.make_ring(CORE_RADIUS)
	ring.name = "Ring"
	ring.position.y = 0.06
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(1.0, 0.45, 0.95)
	light.light_energy = 2.2
	light.omni_range = 24.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.position.y = 2.2
	light.visible = false
	root.add_child(light)
	_root.add_child(root)
	_mirror_list.append_array(MissionVisuals.meshes_of(model))
	_flush_mirror()
	return {node = root, pos = Vector3.ZERO, got = false, gem = gem, ring = ring, beam = beam, light = light}


func _show_core_parts(c: Dictionary, on: bool) -> void:
	(c.gem as Node3D).visible = on
	(c.ring as Node3D).visible = on
	(c.beam as Node3D).visible = on
	(c.light as OmniLight3D).visible = on and Game.quality > 0


func _hide_core(c: Dictionary) -> void:
	(c.node as Node3D).visible = false


func _build_pickup_pool() -> void:
	for i in PICKUP_POOL:
		var root := Node3D.new()
		root.name = "Pickup%d" % i
		root.visible = false
		var models := {}
		var halos := {}
		var columns := {}
		for kind: StringName in KINDS:
			var col := _kind_color(kind)
			var model := Game.load_model("pickup_%s" % kind)
			if model == null:
				model = MissionVisuals.fallback_pickup(col)
			else:
				_apply_fill(model, col)
				MissionVisuals.tint_glow(model, "pickup_%s" % kind, {&"Glow": [col, 2.0 if kind == &"health" else 2.3]})
			model.name = String(kind)
			root.add_child(model)
			models[kind] = model
			halos[kind] = MissionVisuals.make_halo(Color(col.r, col.g, col.b, 0.6), 2.6).material_override
			columns[kind] = MissionVisuals.make_beam(col, 0.22, 5.0, 1.1, 0.0).material_override
			_mirror_list.append_array(MissionVisuals.meshes_of(model))
		var halo := MissionVisuals.make_halo(Color.WHITE, 2.6)
		halo.name = "Halo"
		halo.position.y = 0.25
		root.add_child(halo)
		var column := MissionVisuals.make_beam(Color.WHITE, 0.22, 5.0, 1.1, 0.0)
		column.name = "Column"
		column.position.y = 2.5
		root.add_child(column)
		_root.add_child(root)
		_pickup_pool.append({node = root, models = models, halos = halos, columns = columns, halo = halo, column = column,
				active = false, kind = &"health", weapon = &"", pos = Vector3.ZERO, t = 0.0, phase = 0.0})
	_flush_mirror()


func _flush_mirror() -> void:
	if _mirror != null:
		_mirror.track(_mirror_list)


## DynamicFill (scripts/common/dynamic_fill.gd, built by the enemies module) lifts near-black legacy models; used only when present.
func _apply_fill(model: Node3D, tint: Color) -> void:
	if _fill_script != null and _fill_script.has_method(&"apply"):
		_fill_script.call(&"apply", model, tint)


func _on_quality(level: int) -> void:
	for c: Dictionary in _core_pool:
		var l := c.light as OmniLight3D
		l.visible = l.visible and level > 0
