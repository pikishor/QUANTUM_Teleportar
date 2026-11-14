class_name CrateReveal
extends Control
## The REVEAL of a new weapon (wave 114): a crate that opens, a weapon that is bought or handed out as a reward. About three seconds over whatever is on screen (the play HUD or the pause screen: it is its own
## overlay, it never pauses and never takes a touch): a wash of the class colour, a dim, light rays turning behind the card, the card popping in with a little overshoot (the rendered picture on its class
## backdrop, the name, the class badge, three key numbers), sparks flying out, then a quiet fade. Several weapons in a row (a crate and a reward together) queue and play one after the other.
## `request(id, source)` starts it (skipped under tests and bots unless `force`; `enabled` switches it off); PlayerWeapon.grant calls it when a weapon is unlocked, WeaponCrates / Progress name the source
## through `next_source`. The view is a child of the Hud, drawn in its own `_draw` (no Hud text queue: nothing here is a menu layout, nothing to scan).

const LIFE := 3.4
const POP := 0.5
const FADE := 0.45
const COMPACT_LIFE := 2.0                   ## seconds of the small card shown while a fight is on
const COMPACT_SCALE := 0.62
const COMBAT_RANGE := 50.0                  ## metres: an alerted enemy this close means the fight is on

static var enabled := true
static var next_source := ""                ## what the next reveal says it is ("CRATE OPENED", "PURCHASED", "MISSION REWARD"); read and cleared by request()
static var started := 0                     ## reveals that started (tests wait on it)
static var finished := 0
static var current: CrateReveal
static var _queue: Array[Dictionary] = []

var weapon: StringName = &""
var source := "NEW WEAPON"
var age := 0.0
var compact := false                         ## a fight is on: a small card at the side for a short time, no dim and no rays over the view the hero needs (wave 114 critic)
var _life := LIFE
var _card := {}


static var _quiet := -1                     ## 1 under a test, a bot or a shot run (no player to look at it), cached


## True under a test (headless or `--test=`), a bot or a shot run: nobody is looking, nothing must pop up over a layout scan.
static func suppressed() -> bool:
	if _quiet < 0:
		_quiet = 1 if (Game.autostart or DisplayServer.get_name() == "headless") else 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--test"):
				_quiet = 1
	return _quiet == 1


## Start the reveal of weapon `id`. Returns true when it started or was queued. `force` plays it under a test or a bot too and gives a card to a weapon whose source is not named
## (a weapon picked up in a fight gets its HUD line and no three-second card over the view).
static func request(id: StringName, src := "", force := false) -> bool:
	if src == "":
		src = next_source
	next_source = ""
	if src == "":
		if not force:
			return false
		src = "NEW WEAPON"
	if not WeaponDefs.DEFS.has(id) or not enabled:
		return false
	if suppressed() and not force:
		return false
	var hud := (Engine.get_main_loop() as SceneTree).get_first_node_in_group(&"hud")
	if hud == null:
		return false
	if is_instance_valid(current):
		_queue.append({"id": id, "src": src, "hud": hud})
		return true
	_start(hud, id, src)
	return true


static func _start(hud: Node, id: StringName, src: String) -> void:
	var v := CrateReveal.new()
	v.name = "CrateReveal"
	v.weapon = id
	v.source = src
	hud.add_child(v)
	current = v
	started += 1


static func is_showing() -> bool:
	return is_instance_valid(current)


## True while an alerted enemy is near the hero on foot or in a car, in the running game: the reveal then must not dim or cover the view (the crates stand in the streets where the fights are).
static func in_combat() -> bool:
	if Game.state != &"play" or not is_instance_valid(Game.player):
		return false
	var hero := (Game.player as Node3D).global_position
	for e: Node in (Engine.get_main_loop() as SceneTree).get_nodes_in_group(&"enemy"):
		if e is Node3D and is_instance_valid(e) and e.get(&"aware") == true and not PlayerWeapon._is_dead(e) and (e as Node3D).global_position.distance_to(hero) < COMBAT_RANGE:
			return true
	return false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 50
	_card = WeaponStats.card(weapon, WeaponDefs.def(weapon))
	compact = in_combat()
	_life = COMPACT_LIFE if compact else LIFE
	Sfx.play(&"ui_confirm", -2.0, 0.9)
	Sfx.play(&"pickup", -4.0, 0.8)
	WeaponAudio.haptic(&"reveal")


func _process(dt: float) -> void:
	age += dt / maxf(Engine.time_scale, 0.05)
	if age >= _life:
		_finish()
		return
	queue_redraw()


func _finish() -> void:
	finished += 1
	if current == self:
		current = null
	var hud := get_parent()
	if not _queue.is_empty() and hud != null:
		var nx: Dictionary = _queue.pop_front()
		_start(hud, nx["id"], nx["src"])
	queue_free()


static func _ease_back(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c1 := 1.9
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)


func _txt(font: Font, pos: Vector2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), text, align, width, size, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, pos, text, align, width, size, col)


func _draw() -> void:
	var vp := size
	if vp.x < 8.0:
		return
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var cls := WeaponDefs.class_of(weapon)
	var tint := UiKit.class_tint(cls)
	var fade := clampf(age / 0.2, 0.0, 1.0) * (1.0 - clampf((age - (_life - FADE)) / FADE, 0.0, 1.0))
	if not compact:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.02, 0.05, 0.5 * fade))
		if age < 0.4:
			draw_rect(Rect2(Vector2.ZERO, vp), Color(tint.lerp(Color.WHITE, 0.3), 0.55 * (1.0 - age / 0.4)))
	var centre := vp * 0.5 + Vector2(0.0, 6.0 * s)
	if compact:
		centre = Vector2(vp.x * 0.2, vp.y * 0.46)                                 # beside the middle of the view, over the free side of the street (the hero, the touch controls and the crosshair stay clear)
	# light rays turning behind the card
	for i in (0 if compact else 14):
		var a := float(i) * TAU / 14.0 + age * 0.35
		var half := 0.055
		var rad := maxf(vp.x, vp.y) * 0.9
		var p1 := centre + Vector2.from_angle(a - half) * rad
		var p2 := centre + Vector2.from_angle(a + half) * rad
		draw_polygon(PackedVector2Array([centre, p1, p2]), PackedColorArray([Color(tint, 0.26 * fade), Color(tint, 0.0), Color(tint, 0.0)]))
	# the card pops in with an overshoot, a few degrees of turn that settle
	var k := _ease_back(age / POP) if age < POP else 1.0
	var k2 := 1.0 + 0.012 * sin(age * 3.0) if age >= POP else 1.0
	var card := Vector2(560.0, 366.0) * s
	var csc := COMPACT_SCALE if compact else 1.0
	draw_set_transform(centre, (1.0 - clampf(age / POP, 0.0, 1.0)) * 0.1, Vector2(k * k2 * csc, k * k2 * csc))
	var r := Rect2(-card * 0.5, card)
	UiKit.panel(self, r, s, tint, true, 16.0, true)
	var art := Rect2(r.position + Vector2(10.0, 62.0) * s, Vector2(card.x - 20.0 * s, 170.0 * s))
	WeaponPics.draw_backdrop(self, art, cls, age, 1.0)
	WeaponPics.draw_fit(self, weapon, art.grow_individual(-24.0 * s, -8.0 * s, -24.0 * s, -10.0 * s), true, Color(1, 1, 1, fade), 2.4)
	_txt(font, Vector2(r.position.x + 18.0 * s, r.position.y + 40.0 * s), source, int(UiKit.T_LABEL * s), Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.35), fade), HORIZONTAL_ALIGNMENT_LEFT, card.x - 160.0 * s)
	var cname := String(WeaponDefs.CLASS_NAMES.get(cls, ""))
	var bw := font.get_string_size(cname, HORIZONTAL_ALIGNMENT_LEFT, -1, int(UiKit.T_CAP * s)).x + 22.0 * s
	var br := Rect2(r.end.x - bw - 16.0 * s, r.position.y + 18.0 * s, bw, 30.0 * s)
	draw_rect(br, Color(tint, 0.55 * fade))
	draw_rect(br, Color(tint, 0.95 * fade), false, 1.5 * s)
	_txt(font, Vector2(br.position.x, br.position.y + 21.0 * s), cname, int(UiKit.T_CAP * s), Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_CENTER, bw)
	var nm := WeaponDefs.title(weapon)
	var nsz := UiUtil.fit_size(font, nm, card.x - 36.0 * s, int(UiKit.T_HERO * 0.8 * s))
	_txt(font, Vector2(r.position.x + 18.0 * s, art.end.y + 34.0 * s), nm, nsz, Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_LEFT, card.x - 36.0 * s)
	# three key numbers
	var chips: Array = [["DAMAGE", WeaponStats.bar_text(_card, &"damage")], ["RANGE", WeaponStats.bar_text(_card, &"range")], ["FIRE RATE", WeaponStats.bar_text(_card, &"rate")]]
	if float(_card["blast"]) > 0.0:
		chips[1] = ["BLAST", WeaponStats.bar_text(_card, &"blast")]
	var cw := (card.x - 36.0 * s - 2.0 * 10.0 * s) / 3.0
	for i in 3:
		var cr := Rect2(r.position.x + 18.0 * s + float(i) * (cw + 10.0 * s), r.end.y - 68.0 * s, cw, 52.0 * s)
		draw_rect(cr, Color(0.03, 0.04, 0.08, 0.85 * fade))
		draw_rect(Rect2(cr.position.x, cr.end.y - 3.0 * s, cr.size.x, 3.0 * s), Color(tint, 0.9 * fade))
		_txt(font, Vector2(cr.position.x, cr.position.y + 20.0 * s), String(chips[i][1]), int(UiKit.T_LABEL * s), Color(1, 1, 1, fade), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		_txt(font, Vector2(cr.position.x, cr.end.y - 8.0 * s), String(chips[i][0]), int(UiKit.T_CAP * s), Color(tint.lerp(Color.WHITE, 0.5), 0.95 * fade), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	draw_set_transform(Vector2.ZERO)
	# sparks flying out of the card
	for i in (0 if compact else 30):
		var h := float(i) * 2.399963
		var sp := 0.55 + 0.45 * fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var t := clampf((age - 0.12) / 1.5, 0.0, 1.0)
		if t <= 0.0 or t >= 1.0:
			continue
		var pos := centre + Vector2.from_angle(h) * (60.0 + 420.0 * sp * (1.0 - pow(1.0 - t, 2.0))) * s
		var sz := (7.0 - 5.0 * t) * s
		var col := Color(tint.lerp(Color.WHITE, 0.55), (1.0 - t) * 0.9 * fade)
		draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -sz), pos + Vector2(sz * 0.6, 0), pos + Vector2(0, sz), pos + Vector2(-sz * 0.6, 0)]), col)
