extends RefCounted
## Look-dev bot for THE LONG TOMORROW (docs/STORY.md): photographs the briefing and beat cutscenes, the radio plate with a portrait, the finale and the Mission Board's STORY card with the real
## game camera.   BOT_RES=2400x1080 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_story_acts.gd OUT 60 N        (one view per 60 frames, N views)
## env STORY_VIEWS = comma list (default: board,brief_act,brief_iris,beat_relay,beat_beacon,radio,portraits,end):
##   board        the Mission Board with the STORY card (mission 4)
##   brief_act    the briefing of CONTAINER 17 (first mission of act 2: the act title card), RIVET speaking
##   brief_iris   the briefing of THE OBSERVATORY, IRIS speaking
##   beat_relay   the twist beat of THE RELAY, the hive speaking
##   beat_beacon  the beat of THE OUTPOST, ORACLE speaking
##   radio        the radio plate in play with BASALT's portrait beside it
##   portraits    all seven portraits in a row (a debug overlay)
##   end          the finale credits over the city
const E := 60

var _n := 0
var _views: Array[String] = []
var _probe: Control


class Probe extends Control:
	func _draw() -> void:
		var vp := get_viewport_rect().size
		var s := minf(vp.x / 8.0, vp.y * 0.5)
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.06, 0.09))
		for i in StoryCast.ORDER.size():
			StoryCast.draw_portrait(self, Rect2(Vector2(s * 0.5 + float(i) * s * 1.05, vp.y * 0.3), Vector2(s, s)), StoryCast.ORDER[i], Time.get_ticks_msec() * 0.001)
		for i in StoryCast.ORDER.size():
			StoryCast.draw_portrait(self, Rect2(Vector2(s * 0.5 + float(i) * s * 1.05, vp.y * 0.72), Vector2(s * 0.5, s * 0.5)), StoryCast.ORDER[i], 1.0)


func _init() -> void:
	var v := OS.get_environment("STORY_VIEWS")
	for s in (v if v != "" else "board,brief_act,brief_iris,beat_relay,beat_beacon,radio,portraits,end").split(",", false):
		_views.append(s.strip_edges())


func step(_t: float, _d: float) -> bool:
	var p := Game.player as Player
	if p == null:
		return false
	_n += 1
	if _n == 1:
		Game.state = &"play"
		p.max_hp = 1.0e6
		p.hp = p.max_hp
		if Game.enemies != null:
			(Game.enemies as EnemyManager).clear()
		if is_instance_valid(Game.atmosphere):
			(Game.atmosphere as Atmosphere).set_weather(0.0, 0.15)
		if is_instance_valid(Game.world):
			(Game.world as City).day_night.set_hour(19.0)
		var m := Game.missions as Missions
		m.campaign.guide_enabled = false
		m.board.set_take_over(true)
		m.board.set_story_acts(true)
		m.board.first_pending = false
		m.board.auto_open = false
		var prog := Game.progress as Progress
		prog.story_done = {"landfall": 1, "borrowed_wheels": 1, "the_relay": 1}
		m.board.generate()
		var cin := Cinematics.instance
		if cin != null:
			cin.force = true
			cin.enabled = true
	var idx := (_n - 1) / E
	var k := (_n - 1) % E
	if idx >= _views.size():
		return true
	_view(p, _views[idx], k)
	return false


func _scene(id: StringName, ctx: Dictionary, at: float, k: int) -> void:
	var cin := Cinematics.instance
	if cin == null:
		return
	if k == 0:
		if cin.active:
			cin.skip()
		Game.state = &"play"
		cin.play(id, ctx)
	elif k == 3 and cin.active:
		cin.t = at


func _view(p: Player, v: String, k: int) -> void:
	var hud := p.get_tree().get_first_node_in_group(&"hud") as Hud
	if k == 0 and v != "board" and hud != null:
		hud._board_open = false
		Game.state = &"play"
	if k == 0 and _probe != null:
		_probe.queue_free()
		_probe = null
	match v:
		"board":
			if k == 10 and hud != null:
				hud.open_board()
		"brief_act":
			_scene(&"story_brief", {"index": 3}, 3.6, k)
		"brief_iris":
			_scene(&"story_brief", {"index": 6}, 3.2, k)
		"beat_relay":
			_scene(&"story_beat", {"index": 2, "beat": StoryActs.mission(2)["beats"][0]}, 4.4, k)
		"beat_beacon":
			_scene(&"story_beat", {"index": 10, "beat": StoryActs.mission(10)["beats"][0]}, 4.2, k)
		"radio":
			if k == 0:
				var cin := Cinematics.instance
				if cin != null and cin.active:
					cin.skip()
				Game.state = &"play"
				if is_instance_valid(Game.story):
					(Game.story as Story).say("BASALT", "That is her. Throttle up, pull back gently, she flies herself.", "bot.radio", 0.0, 2)
		"portraits":
			if k == 0:
				_probe = Probe.new()
				_probe.set_anchors_preset(Control.PRESET_FULL_RECT)
				var layer := CanvasLayer.new()
				layer.layer = 30
				layer.add_child(_probe)
				p.get_tree().root.add_child(layer)
				_probe.set_meta(&"layer", layer)
			elif _probe != null:
				_probe.queue_redraw()
		"end":
			if _probe != null and k == 0:
				var l := _probe.get_meta(&"layer") as Node
				if l != null:
					l.queue_free()
				_probe = null
			_scene(&"story_end", {}, 6.4, k)
