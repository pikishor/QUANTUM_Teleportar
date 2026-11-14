extends RefCounted
## Look-dev bot of the blast previews (wave 113): the real game with the phone HUD, one frame per preview of BlastPreview / LaunchAim, saved as <BH_OUT>/hud_<name>.png.
##   grenade   a frag in hand: the arc, the landing ring of the TRUE radius, the line "FRAG POP  RADIUS 6 M" under the crosshair
##   launcher  the thermobaric launcher: the reticle ring (10 m)
##   mine      a proximity mine: the ring sits where the mine will stick
##   strike    a called-in airstrike: the footprint ring while aiming, then the beacon on the street and the diamond with its ring on the minimap
##   danger    a frag aimed at the hero's own feet on NORMAL: the red edge and DANGER
##   BH_OUT=/tmp/x BOT_USER_ARGS="--touch" BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_blast_hud.gd /tmp/x/seq 100000 1
## BH_SPOT="x,z,yaw" picks the street (as BX_SPOT of bot_blast_arsenal.gd).

const SHOTS := [
	{"name": "grenade", "id": &"gr_frag", "pitch": -0.16, "look": 20.0},
	{"name": "launcher", "id": &"la_thermo", "pitch": -0.1, "look": 30.0},
	{"name": "mine", "id": &"mn_prox", "pitch": -0.3, "look": 9.0},
	{"name": "strike_aim", "id": &"st_air_l", "pitch": -0.12, "look": 34.0},
	{"name": "strike_beacon", "id": &"st_air_l", "pitch": -0.12, "look": 34.0, "marker": true},
	{"name": "danger", "id": &"gr_frag", "pitch": -0.75, "look": 3.0, "danger": true},
]

var _p: Player
var _w: PlayerWeapon
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _out := ""
var _i := 0
var _t := 0.0
var _warm := 0.0
var _setup_done := false
var _armed := false
var _saved := false
var _cur: Dictionary = {}


func _init() -> void:
	_out = OS.get_environment("BH_OUT")


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_w = _p.weapon
	_mgr = Game.enemies as EnemyManager
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	_mgr.patrol_groups().clear()
	_mgr.clear()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	var forced := OS.get_environment("BH_SPOT")
	var fp := (forced if forced != "" else "-0.528632,-171.663,0.0").split(",")
	_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
	_yaw = float(fp[2])
	DirAccess.make_dir_recursive_absolute(_out)
	WeaponDefs.hero_mode = true
	TestMode.god = true
	print("BOTBH spot ", _spot)


func _equip(id: StringName) -> void:
	WeaponDefs.unlock(id)
	_w.switch_to(id, true)
	_w.ammo = _w.mag
	_w.reserve = 99
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 2.5:
		if _warm == 0.0:
			_p.teleport_to(_spot)
			_p.camera_rig.reset_view(_yaw, -0.06)
		_warm += delta
		RenderingServer.render_loop_enabled = false
		return false
	if _i >= SHOTS.size():
		RenderingServer.render_loop_enabled = true
		WeaponDefs.hero_mode = false
		print("BOTBH done")
		_p.get_tree().quit()
		return true
	if not _armed:
		_armed = true
		_cur = (SHOTS[_i] as Dictionary).duplicate()
		_saved = false
		_t = 0.0
		BlastOps.shared(_p.get_tree()).reset()
		_mgr.clear()
		_p.teleport_to(_spot)
		var danger := bool(_cur.get("danger", false))
		WeaponDefs.hero_mode = not danger                              # the danger frame needs a hero who can be hurt: NORMAL, no immunity
		TestMode.god = not danger
		Difficulty.set_mode(Difficulty.NORMAL if danger else Difficulty.EASY)
		_equip(StringName(_cur["id"]))
		_p.camera_rig.reset_view(_yaw, float(_cur["pitch"]))
	var s: Dictionary = _cur
	_t += delta
	# aim: the camera looks at a point `look` metres ahead on the street
	var at := _spot + _dir() * float(s["look"])
	if not bool(s.get("danger", false)):
		_p.camera_rig.aim_at(at + Vector3(0.0, 0.2, 0.0))
	else:
		_p.camera_rig.reset_view(_yaw, float(s["pitch"]))
	_w.fire_t = 0.0
	_w.tick(delta, false, false, false, false)
	if bool(s.get("marker", false)) and _t > 0.4 and not bool(s.get("fired", false)):
		s["fired"] = true
		_w.tick(delta, true, false, false, false)                       # the throw: the marker flies and lands, the strike counts down
		_w.tick(delta, false, false, false, false)
	var due := 0.6 if not bool(s.get("marker", false)) else 2.4
	RenderingServer.render_loop_enabled = _t >= due - delta * 3.0
	if _t >= due and not _saved:
		_saved = true
		var img := _p.get_viewport().get_texture().get_image()
		var path := "%s/hud_%s.png" % [_out, String(s["name"])]
		img.save_png(path)
		print("BOTBH ", s["name"], " radius_shown ", snappedf(BlastPreview.radius_shown, 0.1), " text '", BlastPreview.text_shown, "' inside ", BlastPreview.inside)
		RenderingServer.render_loop_enabled = false
		_i += 1
		_armed = false
		_w.tick(delta, false, false, false, false)
	return false
