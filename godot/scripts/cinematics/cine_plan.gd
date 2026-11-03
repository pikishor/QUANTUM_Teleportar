class_name CinePlan
extends RefCounted
## One cutscene as data: camera shots (splines or orbits, in world space around anchors given at build time), flying drone props, subtitles, a title card, timed
## events and the grade / flash curves. Built once per scene (the only allocation); sampling it every frame allocates nothing. Pure maths, no nodes: the
## Cinematics node plays it (tests/test_cinematic.gd checks the plans without a renderer).

const UP := Vector3.UP
const SPLINE := 0
const ORBIT := 1

class Shot extends RefCounted:
	var t0 := 0.0
	var t1 := 1.0
	var kind := 0
	var pos := PackedVector3Array()          ## spline control points (camera)
	var look := PackedVector3Array()         ## spline control points (target)
	var center := Vector3.ZERO               ## orbit: centre, radius r0 -> r1, angle a0 -> a1 around UP (0 = behind the facing `face`), height h0 -> h1, look height
	var face := Vector3.FORWARD
	var r0 := 4.0
	var r1 := 4.0
	var a0 := 0.0
	var a1 := 1.0
	var h0 := 1.5
	var h1 := 1.5
	var look_h := 1.4
	var fov0 := 70.0
	var fov1 := 70.0
	var roll := 0.0                          ## radians of slow sway
	var dolly_k := 0.0                       ## > 0: dolly zoom, the fov follows 2*atan(k / distance to the look point) so the subject keeps its size while the room stretches
	var focus0 := 0.0                        ## rack focus: 0 sharp .. 1 soft at the start and end of the shot (drawn as grade softness by Cinematics)
	var focus1 := 0.0

var id: StringName = &""
var duration := 10.0
var shots: Array[Shot] = []
var drones: Array[Dictionary] = []           ## {model, p0, v, scale}: position = p0 + v * t, facing along v
var subs: Array[Dictionary] = []
var head := ""                               ## title card: head line, sub line, objective line; shown from title_t0 to title_t1 (seconds)
var sub_line := ""
var obj_line := ""
var tag_line := ""
var title_t0 := 0.0
var title_t1 := 0.0
var events: Array[Dictionary] = []           ## {t, name}, fired once each, in order
var flash_t := -1.0                          ## white flash peaks here (rift), rising for `flash_rise` and falling for `flash_fall`
var flash_rise := 0.8
var flash_fall := 1.2
var warm_t := -1.0                           ## the grade turns from cold to warm around this time (-1: constant warm_base)
var warm_base := 0.3
var bars := 0.10                             ## letterbox bar height, fraction of the screen height
var skippable := true
var slowmo := false                          ## the boss defeat: Stability slow motion while the scene plays
var credits: Array = []                      ## the credits scene: blocks {head, lines}, one after the other, each `credit_seconds` long (empty in every other scene)
var credit_seconds := 3.6
var glitches: Array[float] = []              ## quantum glitch transitions: times of the hard cuts (a short tear / chromatic burst around each)
const GLITCH_LEN := 0.45

# sampled by sample()
var cam_pos := Vector3.ZERO
var cam_look := Vector3.ZERO
var cam_fov := 70.0
var cam_roll := 0.0
var shot_index := 0
var cam_focus := 0.0                         ## rack focus softness 0..1 of the current shot


static func smooth(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## A slow move: mostly linear, soft at both ends.
static func ease_move(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return lerpf(c, c * c * (3.0 - 2.0 * c), 0.55)


static func spline(pts: PackedVector3Array, u: float) -> Vector3:
	var n := pts.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return pts[0]
	var s := clampf(u, 0.0, 1.0) * float(n - 1)
	var i := mini(int(s), n - 2)
	var f := s - float(i)
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n - 1)]
	var f2 := f * f
	var f3 := f2 * f
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)


## Direction `face` turned by `angle` radians around UP (positive turns left).
static func turned(face: Vector3, angle: float) -> Vector3:
	return face.rotated(UP, angle)


static func flat_dir(v: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	var d := Vector3(v.x, 0.0, v.z)
	return d.normalized() if d.length() > 0.001 else fallback


func drone_pos(i: int, t: float) -> Vector3:
	var d := drones[i]
	var v: Vector3 = d["v"]
	return (d["p0"] as Vector3) + v * t + Vector3(0.0, sin(t * 1.3 + float(i)) * 0.35, 0.0)


## Camera pose at scene time t into cam_pos / cam_look / cam_fov / cam_roll.
func sample(t: float) -> void:
	var si := 0
	for i in shots.size():
		if t >= shots[i].t0:
			si = i
	shot_index = si
	var s := shots[si]
	var u := ease_move((t - s.t0) / maxf(s.t1 - s.t0, 0.001))
	if s.kind == ORBIT:
		var a := lerpf(s.a0, s.a1, u)
		var dir := turned(-s.face, a)
		var r := lerpf(s.r0, s.r1, u)
		cam_pos = s.center + dir * r + Vector3(0.0, lerpf(s.h0, s.h1, u), 0.0)
		cam_look = s.center + Vector3(0.0, s.look_h, 0.0)
	else:
		cam_pos = spline(s.pos, u)
		cam_look = spline(s.look, u)
	cam_fov = lerpf(s.fov0, s.fov1, u)
	if s.dolly_k > 0.0:
		cam_fov = clampf(rad_to_deg(2.0 * atan(s.dolly_k / maxf(cam_pos.distance_to(cam_look), 0.5))), 25.0, 100.0)
	cam_focus = lerpf(s.focus0, s.focus1, smooth((t - s.t0) / maxf(s.t1 - s.t0, 0.001)))
	cam_roll = s.roll * sin(t * 0.7)


func cam_transform() -> Transform3D:
	var dir := cam_look - cam_pos
	if dir.length() < 0.05:
		dir = Vector3.FORWARD
	if absf(dir.normalized().dot(UP)) > 0.995:
		return Transform3D(Basis.IDENTITY, cam_pos)
	var b := Basis.looking_at(dir.normalized(), UP)
	if cam_roll != 0.0:
		b = b * Basis(Vector3.BACK, cam_roll)
	return Transform3D(b, cam_pos)


## 0..1 white flash at scene time t.
func flash_at(t: float) -> float:
	if flash_t < 0.0:
		return 0.0
	if t < flash_t:
		return smooth((t - (flash_t - flash_rise)) / flash_rise)
	return 1.0 - smooth((t - flash_t) / flash_fall)


## 0 cold (rain-soaked teal) .. 1 warm (after the rift).
func warm_at(t: float) -> float:
	return warm_base if warm_t < 0.0 else smooth((t - warm_t) / 1.6)


## Weight of the cinematic grade (vignette, desaturation): eased in at the start, out at the end.
func grade_at(t: float) -> float:
	return smooth(t / 1.2) * (1.0 - smooth((t - (duration - 1.2)) / 1.2))


## Title card opacity 0..1.
func title_alpha(t: float) -> float:
	if title_t1 <= title_t0:
		return 0.0
	return smooth((t - title_t0) / 0.6) * (1.0 - smooth((t - (title_t1 - 0.6)) / 0.6))


## Index of the credits block shown at scene time t, -1 outside the blocks (or in a scene without credits).
func credit_index(t: float) -> int:
	if credits.is_empty() or t < 0.0:
		return -1
	var i := int(t / maxf(credit_seconds, 0.1))
	return i if i < credits.size() else -1


## Opacity 0..1 of the credits block shown at t: it fades in and out inside its own slot, so two blocks never overlap.
func credit_alpha(t: float) -> float:
	if credit_index(t) < 0:
		return 0.0
	var local := fposmod(t, maxf(credit_seconds, 0.1))
	var f := minf(0.6, credit_seconds * 0.25)
	return smooth(local / f) * (1.0 - smooth((local - (credit_seconds - f)) / f))


## 0..1 strength of the quantum glitch at t: a burst that peaks at each glitch time and dies within GLITCH_LEN seconds.
func glitch_at(t: float) -> float:
	var g := 0.0
	for gt in glitches:
		var d := absf(t - gt)
		if d < GLITCH_LEN:
			g = maxf(g, 1.0 - d / GLITCH_LEN)
	return g


## Problems with the subtitle timing (empty when fine): inside the scene, in order, no overlap, each readable (>= 0.9 s).
func sub_problems() -> Array[String]:
	var out: Array[String] = []
	var last := -1.0
	for s in subs:
		var a := float(s["t0"])
		var b := float(s["t1"])
		if a < last - 0.001:
			out.append("overlap at %.1f" % a)
		if b - a < 0.9:
			out.append("too short at %.1f" % a)
		if a < 0.0 or b > duration:
			out.append("outside the scene at %.1f" % a)
		last = b
	return out


func subtitle_at(t: float) -> Dictionary:
	for s in subs:
		if t >= float(s["t0"]) and t <= float(s["t1"]):
			return s
	return {}


# ---------------------------------------------------------------------------------------------------------------------
# the scenes
# ---------------------------------------------------------------------------------------------------------------------

static func _shot(t0: float, t1: float, fov0: float, fov1: float) -> Shot:
	var s := Shot.new()
	s.t0 = t0
	s.t1 = t1
	s.fov0 = fov0
	s.fov1 = fov1
	return s


static func _drone(model: String, p0: Vector3, v: Vector3, scale: float) -> Dictionary:
	return {"model": model, "p0": p0, "v": v, "scale": scale}


## The first DEPLOY, about 25 s. ctx: roof (a rooftop point), roof_face (horizontal direction the hero faces there), spawn (street position), spawn_face.
static func intro(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"intro"
	p.duration = 25.0
	var R: Vector3 = ctx["roof"]
	var F: Vector3 = flat_dir(ctx["roof_face"])
	var RR := F.cross(UP)
	var S: Vector3 = ctx["spawn"]
	var SF: Vector3 = flat_dir(ctx["spawn_face"])
	# A: fly over the skyline toward the city, under the drone formation
	var a := _shot(0.0, 8.0, 74.0, 84.0)
	a.pos = PackedVector3Array([R - F * 55.0 + UP * 48.0, R - F * 20.0 - RR * 6.0 + UP * 28.0, R + F * 12.0 + RR * 8.0 + UP * 17.0, R + F * 52.0 - RR * 6.0 + UP * 14.0, R + F * 100.0 + RR * 10.0 + UP * 19.0])
	a.look = PackedVector3Array([R + F * 70.0 + UP * 16.0, R + F * 95.0 + UP * 12.0, R + F * 120.0 + RR * 4.0 + UP * 11.0, R + F * 150.0 + UP * 14.0, R + F * 190.0 + UP * 16.0])
	a.roll = 0.03
	p.shots.append(a)
	# B: on the roof, looking up at a drone gliding over, then tilting down to the hero
	p.drones.append(_drone("drone_sentinel", R + RR * (-14.0 * 10.5) - F * 6.0 + UP * 16.0, RR * 14.0, 3.8))
	p.drones.append(_drone("drone_striker", R + RR * (-14.0 * 10.3) + F * 12.0 - RR * 14.0 + UP * 24.0, RR * 14.0, 3.4))
	p.drones.append(_drone("drone_sentinel", R + F * 85.0 + RR * 60.0 + UP * 30.0, -RR * 9.0, 4.0))
	p.drones.append(_drone("drone_heavy", R + F * 140.0 - RR * 50.0 + UP * 40.0, RR * 2.4, 5.5))
	var b := _shot(8.0, 13.5, 78.0, 66.0)
	b.pos = PackedVector3Array([R - F * 3.0 - RR * 4.0 + UP * 1.0, R - F * 2.6 - RR * 3.4 + UP * 1.15, R - F * 2.2 - RR * 3.0 + UP * 1.3])
	b.look = PackedVector3Array([p.drone_pos(0, 8.0), p.drone_pos(0, 10.4), p.drone_pos(0, 11.6) - UP * 1.0, R + UP * 1.7])
	p.shots.append(b)
	# C: slow arc behind the hero, silhouetted against the skyline, pushing in
	var c := _shot(13.5, 19.8, 70.0, 52.0)
	c.kind = ORBIT
	c.center = R
	c.face = F
	c.r0 = 5.4
	c.r1 = 3.5
	c.a0 = -0.6
	c.a1 = 0.45
	c.h0 = 1.0
	c.h1 = 1.6
	c.look_h = 1.5
	p.shots.append(c)
	# D: after the rift, in the street, in front of the hero
	var d := _shot(19.8, 25.0, 58.0, 64.0)
	d.kind = ORBIT
	d.center = S
	d.face = SF
	d.r0 = 3.9
	d.r1 = 5.6
	d.a0 = PI - 0.7
	d.a1 = PI + 0.25
	d.h0 = 0.8
	d.h1 = 1.7
	d.look_h = 2.5                          # aimed above the hero so Kestrel sits low in the frame and the title card clears the head
	p.shots.append(d)
	p.subs = CineData.INTRO_SUBS
	p.head = CineData.INTRO_TITLE
	p.tag_line = StoryData.TAGLINE
	p.title_t0 = 21.2
	p.title_t1 = 24.9
	p.flash_t = 19.8
	p.warm_t = 19.8
	p.events = [{"t": 19.8, "name": "teleport"}]
	p.glitches = [8.0, 13.5, 19.8]
	return p


## 5-8 s orbit around the hero with the chapter title and the next objective. ctx: hero, face, label, title, sub, obj.
static func chapter(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"chapter"
	p.duration = 6.5
	var s := _shot(0.0, p.duration, 72.0, 58.0)
	s.kind = ORBIT
	s.center = ctx["hero"]
	s.face = flat_dir(ctx["face"])
	s.r0 = 4.8
	s.r1 = 3.3
	s.a0 = 0.5
	s.a1 = 2.4
	s.h0 = 0.9
	s.h1 = 2.1
	s.look_h = 2.1
	p.shots.append(s)
	p.head = String(ctx.get("title", ""))
	p.sub_line = String(ctx.get("sub", ""))
	p.tag_line = String(ctx.get("label", ""))
	p.obj_line = String(ctx.get("obj", ""))
	p.title_t0 = 1.0
	p.title_t1 = 6.2
	p.warm_base = 0.45
	p.subs = CineData.CHAPTER_SUBS
	s.focus0 = 0.7                          # rack focus: the shot opens soft and pulls sharp on the hero
	s.focus1 = 0.0
	return p


## The Overseer introduced: a low push-in on the boss, then a hard cut to the hero. ctx: boss, hero, face.
static func boss_in(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"boss_in"
	p.duration = 4.8
	var O: Vector3 = ctx["boss"]
	var H: Vector3 = ctx["hero"]
	var to_p := flat_dir(H - O, Vector3.BACK)
	var side := to_p.cross(UP)
	var s := _shot(0.0, 3.6, 66.0, 48.0)
	s.pos = PackedVector3Array([O + to_p * 24.0 + UP * 1.6, O + to_p * 16.0 + side * 3.0 + UP * 3.5, O + to_p * 10.5 - side * 1.0 + UP * 5.0])
	s.look = PackedVector3Array([O + UP * 3.2, O + UP * 3.4, O + UP * 3.6])
	s.focus0 = 0.6
	p.shots.append(s)
	var f := flat_dir(ctx["face"])
	var h := _shot(3.6, 4.8, 62.0, 54.0)
	h.kind = ORBIT
	h.center = H
	h.face = f
	h.r0 = 3.2
	h.r1 = 2.8
	h.a0 = PI - 0.45
	h.a1 = PI - 0.25
	h.h0 = 0.6
	h.h1 = 0.8
	h.look_h = 1.4
	p.shots.append(h)
	p.glitches = [3.6]
	p.head = CineData.BOSS_IN_HEAD
	p.sub_line = CineData.BOSS_IN_SUB
	p.title_t0 = 0.7
	p.title_t1 = 4.2
	p.subs = CineData.BOSS_IN_SUBS
	p.warm_base = 0.1
	p.bars = 0.11
	return p


## The Overseer's last moment in slow motion: an orbit around where it fell. ctx: boss, hero.
static func boss_out(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"boss_out"
	p.duration = 4.4
	var O: Vector3 = ctx["boss"]
	var H: Vector3 = ctx["hero"]
	var s := _shot(0.0, p.duration, 64.0, 54.0)
	s.kind = ORBIT
	s.center = O
	s.face = flat_dir(O - H)
	s.r0 = 15.0
	s.r1 = 9.5
	s.a0 = 0.2
	s.a1 = 1.7
	s.h0 = 3.2
	s.h1 = 6.5
	s.look_h = 3.0
	p.shots.append(s)
	p.head = CineData.BOSS_OUT_HEAD
	p.sub_line = CineData.BOSS_OUT_SUB
	p.title_t0 = 1.0
	p.title_t1 = 4.0
	p.subs = CineData.BOSS_OUT_SUBS
	p.warm_base = 0.7
	p.slowmo = true
	return p


## The garage revealed: a slow dolly in through the door, a dolly zoom on the machine, an orbit. ctx: hero, face (the garage mouth is ahead of the hero).
static func garage_reveal(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"garage_reveal"
	p.duration = 9.0
	var H: Vector3 = ctx["hero"]
	var F: Vector3 = flat_dir(ctx["face"])
	var R := F.cross(UP)
	var a := _shot(0.0, 4.0, 62.0, 54.0)
	a.pos = PackedVector3Array([H - F * 4.0 + R * 1.5 + UP * 1.3, H + F * 0.5 + R * 0.8 + UP * 1.4, H + F * 4.0 + UP * 1.5])
	a.look = PackedVector3Array([H + F * 6.0 + UP * 1.4, H + F * 8.0 + UP * 1.5, H + F * 9.0 + UP * 1.6])
	a.focus0 = 0.8
	p.shots.append(a)
	var b := _shot(4.0, 6.6, 60.0, 60.0)
	b.pos = PackedVector3Array([H + F * 3.0 + R * 2.5 + UP * 1.2, H + F * 4.0 + R * 2.0 + UP * 1.2, H + F * 5.0 + R * 1.5 + UP * 1.2])
	b.look = PackedVector3Array([H + F * 9.0 + UP * 1.2, H + F * 9.0 + UP * 1.2, H + F * 9.0 + UP * 1.2])
	b.dolly_k = 3.4
	p.shots.append(b)
	var c := _shot(6.6, 9.0, 56.0, 50.0)
	c.kind = ORBIT
	c.center = H + F * 9.0
	c.face = F
	c.r0 = 6.0
	c.r1 = 4.6
	c.a0 = 0.3
	c.a1 = 1.1
	c.h0 = 1.2
	c.h1 = 2.0
	c.look_h = 1.3
	p.shots.append(c)
	p.glitches = [4.0, 6.6]
	p.head = CineData.GARAGE_HEAD
	p.sub_line = CineData.GARAGE_SUB
	p.title_t0 = 5.4
	p.title_t1 = 8.6
	p.subs = CineData.GARAGE_SUBS
	p.warm_base = 0.5
	return p


## The first QUANTUM TELEPORT through a pad: the camera orbits tight, a rack focus into the rift, the flash, a pull back out the other side. ctx: hero, face.
static func teleporter_first(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"teleporter_first"
	p.duration = 7.0
	var H: Vector3 = ctx["hero"]
	var F: Vector3 = flat_dir(ctx["face"])
	var a := _shot(0.0, 3.4, 64.0, 50.0)
	a.kind = ORBIT
	a.center = H
	a.face = F
	a.r0 = 5.0
	a.r1 = 3.0
	a.a0 = PI - 0.9
	a.a1 = PI - 0.1
	a.h0 = 0.9
	a.h1 = 1.4
	a.look_h = 1.3
	a.focus1 = 0.8
	p.shots.append(a)
	var b := _shot(3.4, 7.0, 46.0, 72.0)
	b.kind = ORBIT
	b.center = H
	b.face = F
	b.r0 = 2.6
	b.r1 = 7.0
	b.a0 = PI + 0.3
	b.a1 = PI + 1.3
	b.h0 = 1.2
	b.h1 = 2.8
	b.look_h = 1.4
	b.focus0 = 0.5
	p.shots.append(b)
	p.glitches = [3.4]
	p.flash_t = 3.4
	p.flash_rise = 0.6
	p.flash_fall = 1.0
	p.warm_t = 3.4
	p.warm_base = 0.3
	p.head = CineData.TELEPORT_HEAD
	p.sub_line = CineData.TELEPORT_SUB
	p.title_t0 = 4.4
	p.title_t1 = 6.6
	p.subs = CineData.TELEPORT_SUBS
	return p


## The ending: credits over a slow pull-away from Kestrel in the street (an orbit in front of the hero, a rise along the avenue, a wide high orbit over the rain), the radio
## lines of CampaignData.CREDITS_SUBS and the blocks of CampaignData.CREDITS. Lasts CREDITS_BLOCK_SECONDS * blocks. ctx: hero, face. Skippable by a tap like every scene.
static func credits_scene(ctx: Dictionary) -> CinePlan:
	var p := CinePlan.new()
	p.id = &"credits"
	p.credits = CampaignData.CREDITS
	p.credit_seconds = CampaignData.CREDITS_BLOCK_SECONDS
	p.duration = p.credit_seconds * float(maxi(p.credits.size(), 1))
	var H: Vector3 = ctx["hero"]
	var F: Vector3 = flat_dir(ctx["face"])
	var R := F.cross(UP)
	var d := p.duration
	var a := _shot(0.0, d * 0.36, 58.0, 50.0)                      # in front of Kestrel, a slow arc, the rain in the light
	a.kind = ORBIT
	a.center = H
	a.face = F
	a.r0 = 3.6
	a.r1 = 6.0
	a.a0 = PI - 0.6
	a.a1 = PI + 0.5
	a.h0 = 1.0
	a.h1 = 2.4
	a.look_h = 2.2
	p.shots.append(a)
	var b := _shot(d * 0.36, d * 0.68, 56.0, 68.0)                 # rising behind the hero, looking down the avenue at the sky
	b.pos = PackedVector3Array([H - F * 7.0 + R * 2.0 + UP * 2.6, H - F * 10.0 + R * 5.0 + UP * 8.0, H - F * 15.0 - R * 3.0 + UP * 17.0, H - F * 22.0 + UP * 30.0])
	b.look = PackedVector3Array([H + F * 6.0 + UP * 2.0, H + F * 24.0 + UP * 8.0, H + F * 44.0 + UP * 14.0, H + F * 70.0 + UP * 20.0])
	b.roll = 0.02
	p.shots.append(b)
	var c := _shot(d * 0.68, d, 62.0, 72.0)                        # a wide, high orbit over the city: the rain goes on
	c.kind = ORBIT
	c.center = H
	c.face = F
	c.r0 = 24.0
	c.r1 = 34.0
	c.a0 = 0.4
	c.a1 = 1.6
	c.h0 = 34.0
	c.h1 = 46.0
	c.look_h = 4.0
	p.shots.append(c)
	p.glitches = [d * 0.36, d * 0.68]
	p.drones.append(_drone("drone_sentinel", H + F * 70.0 + R * 40.0 + UP * 34.0, -R * 1.4, 4.0))     # the Observers hang silent
	p.drones.append(_drone("drone_heavy", H + F * 120.0 - R * 50.0 + UP * 46.0, R * 1.0, 5.5))
	p.subs = CampaignData.CREDITS_SUBS
	p.warm_base = 0.8
	p.bars = 0.11
	return p


# ---------------------------------------------------------------------------------------------------------------------
# live shots without a plan: the title screen and the shop close-up
# ---------------------------------------------------------------------------------------------------------------------

## Title backdrop: behind the hero, who stands to the left against the lit avenue, slow lateral parallax. Returns the transform, writes the fov to `fov_out[0]`.
static func title_pose(t: float, hero: Vector3, face: Vector3, fov_out: PackedFloat32Array) -> Transform3D:
	var f := flat_dir(face)
	var r := f.cross(UP)
	var sway := sin(t * 0.11)
	var pos := hero - f * (3.7 - cos(t * 0.07) * 0.5) + r * (0.35 + sway * 2.3) + UP * (1.05 + sin(t * 0.09) * 0.12)
	var look := hero + f * 16.0 + r * (6.2 - sway * 1.2) + UP * (3.4 + sin(t * 0.06) * 0.5)
	fov_out[0] = 66.0 - sin(t * 0.05) * 3.0
	return Transform3D(Basis.looking_at((look - pos).normalized(), UP), pos)


## Shop close-up: in front of the hero, who stands in the left part of the picture, a slow turntable sway.
static func closeup_pose(t: float, hero: Vector3, face: Vector3, fov_out: PackedFloat32Array) -> Transform3D:
	var f := flat_dir(face)
	var dir := turned(f, sin(t * 0.35) * 0.28 + 0.35)
	var pos := hero + dir * 4.3 + UP * 1.25
	var look := hero + UP * 0.95 + dir.cross(UP) * 1.45          # the hero stands in the right strip: the shop panel owns the middle
	fov_out[0] = 46.0
	return Transform3D(Basis.looking_at((look - pos).normalized(), UP), pos)


## A drone prop of the title screen: crosses the sky in a long loop (never visible at the wrap). Position at time t.
static func title_drone(i: int, t: float, hero: Vector3, face: Vector3) -> Vector3:
	var f := flat_dir(face)
	var r := f.cross(UP)
	var span := 220.0
	var along := fposmod(t * (3.2 + float(i) * 1.1) + float(i) * 77.0, span) - span * 0.5
	return hero + f * (58.0 + float(i) * 22.0) + r * along * (1.0 if i % 2 == 0 else -1.0) + UP * (24.0 + float(i) * 7.0)
