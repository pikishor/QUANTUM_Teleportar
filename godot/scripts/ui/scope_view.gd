class_name ScopeView
extends RefCounted
## The scope of a long-range weapon (wave 114 critic, LOOK: the aimed view of a sniper rifle was the plain world with the ordinary crosshair, the hero out of the picture and nothing that said "scope"):
## a round lens with a dark surround, a fine reticle with range ticks and a red centre dot, and the rim of the lens; it fades in with the aim zoom. A weapon is scoped when its aimed field of view is
## SCOPED_FOV degrees or less (20 sniper rifles, the lance, the railgun). Pure drawing on the HUD's canvas (a few polygons and lines, no texture, no node), no state.
##   ScopeView.amount(player)                        0..1, how far the scope is up
##   ScopeView.draw_mask(c, player, vp, s)           the dark surround (drawn first: the bars and plates stay on top of it)
##   ScopeView.draw_reticle(c, player, vp, s, col)   the reticle and the rim (drawn with the crosshair: `col` is the aim-assist colour, red on a target)
##   ScopeView.mask_polygons(vp)                     the four pieces of the surround (what draw_mask draws; tests measure them)

const SCOPED_FOV := 36.0              ## degrees: the aimed field of view of a scoped weapon
const LENS := 0.46                    ## the lens radius as a fraction of the screen height
const ARC_STEPS := 28                 ## segments of the lens edge per quarter
const SURROUND := 0.84                ## alpha of the dark surround at full zoom: the world stays faintly there, the bars and plates on top of it stay readable


## How far the scope is up for this player: 0 for any weapon that is not scoped or while not aiming, 1 at full zoom.
static func amount(p: Object) -> float:
	if p == null:
		return 0.0
	var rig: Object = p.get("camera_rig")
	if rig == null or float(rig.get("ads_fov")) > SCOPED_FOV or p.get("vehicle") != null:
		return 0.0
	return smoothstep(0.45, 0.9, float(rig.call(&"get_ads_amount")))


## The lens centre and radius for a screen.
static func lens(vp: Vector2) -> Dictionary:
	return {"centre": vp * 0.5, "radius": vp.y * LENS}


## The surround of the lens as four polygons (one per quarter of the screen: the corner of the screen, the two edges to the lens and the arc of the lens between them).
static func mask_polygons(vp: Vector2) -> Array[PackedVector2Array]:
	var mid := vp * 0.5
	var r := vp.y * LENS
	var out: Array[PackedVector2Array] = []
	for q in 4:
		var sx := -1.0 if q % 2 == 0 else 1.0                              # which side of the centre
		var sy := -1.0 if q < 2 else 1.0
		var pts := PackedVector2Array()
		pts.append(mid + Vector2(sx * mid.x, sy * mid.y))                  # the screen corner
		pts.append(mid + Vector2(0.0, sy * mid.y))                         # along the top (bottom) edge to the middle
		for k in range(ARC_STEPS + 1):                                     # the lens arc from the top (bottom) of the lens to its left (right) side
			var a := float(k) / float(ARC_STEPS) * PI * 0.5
			pts.append(mid + Vector2(sx * sin(a) * r, sy * cos(a) * r))
		pts.append(mid + Vector2(sx * mid.x, 0.0))                         # out to the side edge
		out.append(pts)
	return out


static func draw_mask(c: Control, p: Object, vp: Vector2, s: float) -> void:
	var a := amount(p)
	if a <= 0.01:
		return
	var dark := Color(0.0, 0.0, 0.01, SURROUND * a)
	for poly: PackedVector2Array in mask_polygons(vp):
		c.draw_colored_polygon(poly, dark)
	var mid := vp * 0.5
	var r := vp.y * LENS
	c.draw_arc(mid, r, 0.0, TAU, ARC_STEPS * 4, Color(0.0, 0.0, 0.0, 0.95 * a), 7.0 * s, true)                      # the black rim of the lens
	c.draw_arc(mid, r - 5.0 * s, 0.0, TAU, ARC_STEPS * 4, Color(0.55, 0.8, 1.0, 0.22 * a), 2.0 * s, true)            # a glint of the glass just inside it


static func draw_reticle(c: Control, p: Object, vp: Vector2, s: float, col: Color) -> void:
	var a := amount(p)
	if a <= 0.05:
		return
	var mid := vp * 0.5
	var r := vp.y * LENS
	var ink := Color(0.0, 0.0, 0.0, 0.88 * a)
	var halo := Color(1.0, 1.0, 1.0, 0.22 * a)
	var gap := 26.0 * s
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var thin_a := mid + dir * gap                                            # the fine cross: from the centre gap to the lens
		var thin_b := mid + dir * r * 0.97
		var thick_a := mid + dir * r * 0.52                                      # the heavy posts at the edge (a duplex reticle)
		c.draw_line(thin_a, thin_b, halo, 3.4 * s, true)
		c.draw_line(thin_a, thin_b, ink, 1.4 * s, true)
		c.draw_line(thick_a, thin_b, ink, 4.2 * s, true)
		for k in range(1, 5):                                                    # range ticks (mil dots) along the fine part
			var dp := mid + dir * (gap + float(k) * r * 0.1)
			var perp := Vector2(-dir.y, dir.x)
			c.draw_line(dp - perp * 5.0 * s, dp + perp * 5.0 * s, ink, 1.8 * s, true)
	var on_target := col.b < 0.9                                                 # the aim assist paints the crosshair red (gold on a head): the dot says the same
	c.draw_circle(mid, (3.4 if on_target else 2.4) * s, Color(col.r, col.g, col.b, 0.97 * a) if on_target else ink)
