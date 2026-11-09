class_name StoryScenes
extends RefCounted
## The cutscenes of THE LONG TOMORROW as CinePlans (the Cinematics node plays them, scripts/cinematics/cinematics.gd): `story_brief` (the briefing of a mission, camera work round the
## hero, the speakers' portraits beside the subtitles, the act title card on the first mission of an act), `story_beat` (a short set-piece moment in the middle of a mission) and the
## finale (`story_end` = CinePlan.credits_scene with StoryActs.CREDITS). Pure data: the shots are built from the hero's position and facing, so a scene never needs a place of its own
## to be loaded (the world around the hero is always streamed). Every subtitle is timed by its length (StoryActs.line_seconds), so a line is on screen as long as it takes to read it.

const FIRST_AT := 0.9
const GAP := 0.35
const MIN_DURATION := 5.0
const TITLE_END := 4.4


## Fills `p.subs` from `lines` ([{s, t}]) one after the other from `t0` and returns the time the last one ends.
static func place_lines(p: CinePlan, lines: Array, t0: float) -> float:
	var t := t0
	for l: Variant in lines:
		var d: Dictionary = l
		var sec := StoryActs.line_seconds(str(d["t"]))
		p.subs.append({"t0": t, "t1": t + sec, "s": str(d["s"]), "t": str(d["t"])})
		t += sec + GAP
	return t


static func lines_duration(lines: Array) -> float:
	var t := FIRST_AT
	for l: Variant in lines:
		t += StoryActs.line_seconds(str((l as Dictionary)["t"])) + GAP
	return maxf(t + 0.8 - GAP, MIN_DURATION)


## Three camera recipes round the hero (A orbit, rise and wide orbit; B low push-in, side orbit, high orbit; C shoulder spline, orbit): chosen by `variant` so neighbouring missions differ.
static func _shots(p: CinePlan, H: Vector3, F: Vector3, d: float, variant: int) -> void:
	var R := F.cross(CinePlan.UP)
	var UP := CinePlan.UP
	match variant % 3:
		0:
			var a := CinePlan._shot(0.0, d * 0.4, 58.0, 48.0)
			a.kind = CinePlan.ORBIT
			a.center = H
			a.face = F
			a.r0 = 4.6
			a.r1 = 5.6
			a.a0 = PI - 0.55
			a.a1 = PI + 0.15
			a.h0 = 1.2
			a.h1 = 1.9
			a.look_h = 1.1
			p.shots.append(a)
			var b := CinePlan._shot(d * 0.4, d * 0.72, 56.0, 66.0)
			b.pos = PackedVector3Array([H - F * 6.0 + R * 2.0 + UP * 2.4, H - F * 9.0 + R * 4.0 + UP * 6.0, H - F * 13.0 - R * 2.0 + UP * 12.0])
			b.look = PackedVector3Array([H + F * 5.0 + UP * 0.3, H + F * 20.0 + UP * 1.5, H + F * 40.0 + UP * 5.0])
			b.roll = 0.015
			p.shots.append(b)
			var c := CinePlan._shot(d * 0.72, d, 60.0, 68.0)
			c.kind = CinePlan.ORBIT
			c.center = H
			c.face = F
			c.r0 = 16.0
			c.r1 = 22.0
			c.a0 = 0.5
			c.a1 = 1.5
			c.h0 = 18.0
			c.h1 = 26.0
			c.look_h = 2.0
			p.shots.append(c)
			p.glitches = [d * 0.4]
		1:
			var a1 := CinePlan._shot(0.0, d * 0.34, 74.0, 52.0)
			a1.pos = PackedVector3Array([H + F * 7.0 + R * 1.5 + UP * 0.5, H + F * 5.0 + R * 1.0 + UP * 0.7, H + F * 3.4 + R * 0.4 + UP * 1.0])
			a1.look = PackedVector3Array([H + UP * 1.5, H + UP * 1.6, H + UP * 1.7])
			a1.focus0 = 0.5
			p.shots.append(a1)
			var b1 := CinePlan._shot(d * 0.34, d * 0.7, 54.0, 50.0)
			b1.kind = CinePlan.ORBIT
			b1.center = H
			b1.face = F
			b1.r0 = 4.4
			b1.r1 = 5.2
			b1.a0 = PI * 0.5
			b1.a1 = PI * 0.5 + 0.9
			b1.h0 = 1.4
			b1.h1 = 2.2
			b1.look_h = 1.1
			p.shots.append(b1)
			var c1 := CinePlan._shot(d * 0.7, d, 58.0, 70.0)
			c1.kind = CinePlan.ORBIT
			c1.center = H
			c1.face = F
			c1.r0 = 12.0
			c1.r1 = 20.0
			c1.a0 = PI - 0.4
			c1.a1 = PI + 0.8
			c1.h0 = 10.0
			c1.h1 = 24.0
			c1.look_h = 2.0
			p.shots.append(c1)
			p.glitches = [d * 0.34, d * 0.7]
		_:
			var a2 := CinePlan._shot(0.0, d * 0.5, 62.0, 50.0)
			a2.kind = CinePlan.ORBIT
			a2.center = H
			a2.face = F
			a2.r0 = 4.4
			a2.r1 = 5.4
			a2.a0 = PI * 0.62
			a2.a1 = PI * 0.92
			a2.h0 = 1.0
			a2.h1 = 1.6
			a2.look_h = 0.8
			p.shots.append(a2)
			var b2 := CinePlan._shot(d * 0.5, d, 56.0, 62.0)
			b2.kind = CinePlan.ORBIT
			b2.center = H
			b2.face = F
			b2.r0 = 3.6
			b2.r1 = 7.0
			b2.a0 = PI + 0.9
			b2.a1 = PI - 0.4
			b2.h0 = 1.1
			b2.h1 = 3.6
			b2.look_h = 1.2
			p.shots.append(b2)
			p.glitches = [d * 0.5]


## The briefing of story mission `ctx["index"]`. ctx: hero (Vector3), face (Vector3), index.
static func brief(ctx: Dictionary) -> CinePlan:
	var idx := int(ctx.get("index", 0))
	var m := StoryActs.mission(idx)
	var p := CinePlan.new()
	p.id = &"story_brief"
	var lines: Array = m.get("brief", [])
	p.duration = lines_duration(lines)
	var H: Vector3 = ctx["hero"]
	var F := CinePlan.flat_dir(ctx["face"])
	_shots(p, H, F, p.duration, idx)
	var end := place_lines(p, lines, FIRST_AT)
	p.duration = maxf(p.duration, end + 0.5)
	p.head = str(m.get("title", ""))
	p.sub_line = str(m.get("place", ""))
	var act := StoryActs.act(int(m.get("act", 1)))
	if StoryActs.first_of_act(idx):
		p.tag_line = "ACT %d  %s" % [int(act.get("n", 1)), str(act.get("title", ""))]
	else:
		p.tag_line = StoryActs.progress_text(idx)
	p.title_t0 = 0.5
	p.title_t1 = minf(TITLE_END, p.duration - 0.8)
	p.warm_base = 0.35
	p.bars = 0.11
	return p


## A beat in the middle of mission ctx["index"]: ctx also has `beat` (the dictionary of StoryActs: head, sub, lines). ctx: hero, face, index, beat.
static func beat(ctx: Dictionary) -> CinePlan:
	var idx := int(ctx.get("index", 0))
	var b: Dictionary = ctx.get("beat", {})
	var p := CinePlan.new()
	p.id = &"story_beat"
	var lines: Array = b.get("lines", [])
	p.duration = lines_duration(lines)
	var H: Vector3 = ctx["hero"]
	var F := CinePlan.flat_dir(ctx["face"])
	_shots(p, H, F, p.duration, idx + 1)
	var end := place_lines(p, lines, FIRST_AT)
	p.duration = maxf(p.duration, end + 0.5)
	p.head = str(b.get("head", ""))
	p.sub_line = str(b.get("sub", ""))
	p.title_t0 = 0.4
	p.title_t1 = minf(3.6, p.duration - 0.8)
	p.warm_base = 0.2
	p.bars = 0.11
	return p


## Problems of a plan's timing and text (empty when fine), for the test.
static func problems(p: CinePlan) -> Array[String]:
	var out: Array[String] = []
	out.append_array(p.sub_problems())
	if p.shots.is_empty():
		out.append("no shots")
	if p.duration > 40.0:
		out.append("longer than 40 s")
	for s: Dictionary in p.subs:
		if not StoryCast.has(str(s["s"])) and not StoryData.SPEAKERS.has(str(s["s"])):
			out.append("unknown speaker %s" % str(s["s"]))
	return out
