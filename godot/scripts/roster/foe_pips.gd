class_name FoePips
extends Node3D
## FLOATING HEALTH PIPS and THREAT MARKERS of the roster enemies (wave 113, enemy look v3).
##  * PIPS: every damaged roster enemy (human, alien or walker) shows a row of five pips above its head, lit green, amber or red by what is left of its health, so the player reads who is nearly
##    dead at 40 m without a bar chart. The armoured humans also wear body pips (the kit: a strip on the vest); the row here is the same idea for the bodies that have none, readable at any distance.
##  * MARKERS: an AWARE enemy 30-95 m away is 20-60 px tall on a phone: a small diamond in its glow colour floats over its head so the player sees who is shooting and from where (the body takes over
##    from 30 m; a cloaked stalker gets none: it is meant to be hard to see).
## ONE MultiMesh holds every pip and marker of all enemies (one draw call, none while nobody is hurt or far and aware, no texture, no light: assets/shaders/foe_pips.gdshader), they keep a readable size
## on screen at any distance and face the camera, a wall in front hides them (depth test on). AlienFx owns one and calls refresh() every tick of the alien world.

const SHADER := preload("res://assets/shaders/foe_pips.gdshader")
const CAP := 12                           ## enemies with a row at the same time (the nearest ones win)
const MARKS := 12                         ## and with a marker
const PIPS := 5
const RANGE := 85.0                       ## no pips beyond this distance (metres)
const PITCH_MIN := 0.1                    ## metres between two pips next to the enemy ...
const PITCH_K := 0.0085                   ## ... and per metre of distance beyond 12 m (about half a degree of view), so the row stays readable
const PITCH_MAX := 0.55
const MARK_NEAR := 30.0                   ## markers of aware enemies between these distances
const MARK_FAR := 95.0
const MARK_K := 0.0125                    ## marker width per metre of distance (about 0.7 degrees of view)
const GREEN := Color(0.3, 1.0, 0.42)
const AMBER := Color(1.0, 0.78, 0.15)
const RED := Color(1.0, 0.2, 0.12)

var mm: MultiMesh
var shown := 0                            ## rows drawn by the last refresh (tests)
var marks := 0                            ## markers drawn by the last refresh (tests)
var lit_last := 0                         ## lit pips of the nearest row of the last refresh
var rows: Array[Dictionary] = []          ## the rows of the last refresh {foe, lit, anchor, pitch} (tests: the dummy renderer of the headless runs does not keep MultiMesh data)
var mark_rows: Array[Dictionary] = []     ## the markers of the last refresh {foe, pos, size}
var _node: MultiMeshInstance3D
var _cand: Array = []                     ## [dist, creature] of this refresh (rows)
var _mcand: Array = []                    ## ... and of the markers


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = CAP * PIPS + MARKS
	mm.visible_instance_count = 0
	_node = MultiMeshInstance3D.new()
	_node.name = "Pips"
	_node.multimesh = mm
	_node.material_override = mat
	_node.custom_aabb = AABB(Vector3(-1500.0, -20.0, -1500.0), Vector3(3000.0, 300.0, 3000.0))
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_node)


## The colour of the lit pips for a health fraction.
static func color_of(frac: float) -> Color:
	if frac > 0.6:
		return GREEN
	if frac > 0.3:
		return AMBER
	return RED


## How many of the five pips are lit for a health fraction (at least one while alive).
static func lit_of(frac: float) -> int:
	return clampi(ceili(frac * float(PIPS) - 0.001), 1, PIPS)


## The roster enemy behind a creature when it is alive, standing, shown and not cloaked; null otherwise.
static func standing(c: AlienCreature) -> RosterFoe:
	var rf := c as RosterFoe
	if rf == null or rf.dead or rf.downed or not rf.active or not rf.visible or rf.max_hp <= 0.0:
		return null
	if float(rf.spec.get("cloak", 0.0)) > 0.0 and rf.cloak_k > 0.4:
		return null
	return rf


## Does this creature get a row? A roster enemy that is standing and below full health.
static func wants(c: AlienCreature) -> bool:
	var rf := standing(c)
	return rf != null and rf.hp < rf.max_hp * 0.995


## Does it get a marker at this distance? A standing, aware enemy between MARK_NEAR and MARK_FAR.
static func wants_mark(c: AlienCreature, dist: float) -> bool:
	var rf := standing(c)
	return rf != null and rf.aggro and dist >= MARK_NEAR and dist <= MARK_FAR


## Height of the anchor of a row above the ground: the head (or the top of the machine) plus a hand.
static func top_of(rf: RosterFoe) -> float:
	var sp := rf.spec
	var h := maxf(float(sp.get("hy", 1.8)) + float(sp.get("hr", 0.25)), float(sp.get("cy", 1.0)) * 1.75)
	return h * rf.vis * (1.0 - 0.25 * rf.crouch) + rf.lift + 0.38


## The colour of the marker of an enemy: its glow colour, a little whitened.
static func mark_color(rf: RosterFoe) -> Color:
	var g: Color = rf.spec.get("glow", Color(1.0, 0.5, 0.2))
	return g.lerp(Color.WHITE, 0.25)


## Draws the rows and markers of the roster enemies of `creatures` that are within range of the camera.
func refresh(creatures: Array) -> void:
	if mm == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		mm.visible_instance_count = 0
		shown = 0
		marks = 0
		rows.clear()
		mark_rows.clear()
		return
	var cpos := cam.global_position
	_cand.clear()
	_mcand.clear()
	rows.clear()
	mark_rows.clear()
	for c in creatures:
		var ac := c as AlienCreature
		if ac == null or not is_instance_valid(ac):
			continue
		var d := cpos.distance_to(ac.global_position)
		if d < 1.5 or d > MARK_FAR:
			continue
		if d <= RANGE and wants(ac):
			_cand.append([d, ac])
		if wants_mark(ac, d):
			_mcand.append([d, ac])
	if _cand.size() > 1:
		_cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if _mcand.size() > 1:
		_mcand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var n := mini(_cand.size(), CAP)
	var right := cam.global_basis.x.normalized()
	var k := 0
	lit_last = 0
	var pitch_of := {}                                                 # creature -> pitch of its row (its marker floats above it)
	for e in n:
		var d2 := float(_cand[e][0])
		var rf := _cand[e][1] as RosterFoe
		var frac := clampf(rf.hp / rf.max_hp, 0.0, 1.0)
		var lit := lit_of(frac)
		if e == 0:
			lit_last = lit
		var col := color_of(frac)
		var pitch := clampf(PITCH_MIN + maxf(d2 - 12.0, 0.0) * PITCH_K, PITCH_MIN, PITCH_MAX)
		pitch_of[rf] = pitch
		var anchor := rf.global_position + Vector3(0.0, top_of(rf), 0.0)
		rows.append({"foe": rf, "lit": lit, "anchor": anchor, "pitch": pitch})
		for i in PIPS:
			var off := (float(i) - float(PIPS - 1) * 0.5) * pitch * 1.18
			var xf := Transform3D(Basis.from_scale(Vector3(pitch, pitch * 0.62, 1.0)), anchor + right * off)
			mm.set_instance_transform(k, xf)
			mm.set_instance_color(k, col)
			mm.set_instance_custom_data(k, Color(1.0 if i < lit else 0.0, 0.0, 0.0, 0.0))
			k += 1
	var m := mini(_mcand.size(), MARKS)
	for e in m:
		var d3 := float(_mcand[e][0])
		var rf2 := _mcand[e][1] as RosterFoe
		var sz := clampf(d3 * MARK_K, 0.25, 1.4)
		var lift := top_of(rf2) + (float(pitch_of[rf2]) * 1.5 if pitch_of.has(rf2) else 0.0) + sz * 0.7
		var pos := rf2.global_position + Vector3(0.0, lift, 0.0)
		mark_rows.append({"foe": rf2, "pos": pos, "size": sz})
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(sz, sz * 1.25, 1.0)), pos))
		mm.set_instance_color(k, mark_color(rf2))
		mm.set_instance_custom_data(k, Color(1.0, 1.0, 0.0, 0.0))
		k += 1
	mm.visible_instance_count = k
	shown = n
	marks = m
