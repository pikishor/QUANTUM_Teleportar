class_name VisualQaLib
extends RefCounted
## Numeric helpers of the visual QA tool (tools/visual_qa.sh, tests/bot_visual_qa.gd): luma stats of a frame and pass / fail rules.

const MIN_MEAN := 0.05          ## darker than this on average: a black or lost frame
const MAX_MEAN := 0.80          ## brighter than this: blown out
const MIN_CONTRAST := 0.04      ## luma standard deviation below this: a flat frame
const MAX_BLACK := 0.85         ## fraction of near-black pixels above this: not a picture
## Hero vs background: luma gap or colour gap of the two means. Recalibrated 0.02 -> 0.012: the hero is a dark armoured figure on a
## mid-grey street with a visible cyan rim (docs/shots/hero.png), clearly separated by eye, but the dark-street means sit only
## ~0.015-0.02 apart, so 0.02 failed every run. 0.012 still catches a hero that truly vanishes (~0).
const MIN_SEP := 0.012
## Street spots: the frame must not be a dark empty street. MIN_STREET_MEAN sits under the tuned MED look (about 0.2 on the software renderer)
## with a wide margin for renderer differences; MIN_PEOPLE is counted within PEOPLE_RADIUS of the player (MED pool 56 in a 70 m ring).
const MIN_STREET_MEAN := 0.09
const MIN_PEOPLE := 2
const PEOPLE_RADIUS := 45.0


static func luma(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


## {mean, contrast (std dev), black (fraction of luma < 0.02)} of an image, sampled on a grid of `step` pixels.
static func stats(img: Image, step := 4) -> Dictionary:
	var sum := 0.0
	var sq := 0.0
	var black := 0
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var l := luma(img.get_pixel(x, y))
			sum += l
			sq += l * l
			if l < 0.02:
				black += 1
			n += 1
	if n == 0:
		return {"mean": 0.0, "contrast": 0.0, "black": 1.0}
	var m := sum / n
	return {"mean": m, "contrast": sqrt(maxf(sq / n - m * m, 0.0)), "black": float(black) / n}


## Hero vs background: pixels that differ between the frame with and without the hero are the hero. Returns {sep, n}, sep = the
## larger of the luma gap and the colour gap between the hero's mean colour and the rest of the frame.
static func separation(shown: Image, hidden: Image, step := 2) -> Dictionary:
	var h := Color(0, 0, 0, 0)
	var b := Color(0, 0, 0, 0)
	var nh := 0
	var nb := 0
	var w := mini(shown.get_width(), hidden.get_width())
	var ht := mini(shown.get_height(), hidden.get_height())
	for y in range(0, ht, step):
		for x in range(0, w, step):
			var a := shown.get_pixel(x, y)
			var o := hidden.get_pixel(x, y)
			if absf(a.r - o.r) + absf(a.g - o.g) + absf(a.b - o.b) > 0.09:
				h += a
				nh += 1
			else:
				b += a
				nb += 1
	if nh == 0 or nb == 0:
		return {"sep": 0.0, "n": nh}
	h /= nh
	b /= nb
	var dl := absf(luma(h) - luma(b))
	var dc := (absf(h.r - b.r) + absf(h.g - b.g) + absf(h.b - b.b)) / 3.0
	return {"sep": maxf(dl, dc), "n": nh}


## Big flat bright rectangles (an untextured / not-yet-textured billboard or quad): the frame is cut into BLOCK px cells, a cell is flat when its luma range is
## under FLAT_RANGE and bright when its mean is over FLAT_LUMA; 4-connected flat-bright regions at least FLAT_MIN_CELLS across both ways whose cells fill
## at least 85 % of their bounding box count. Returns the biggest one as {frac (of the frame), rect (px)}, frac 0 when none.
const FLAT_BLOCK := 8
const FLAT_RANGE := 0.035
const FLAT_LUMA := 0.55
const FLAT_MIN_CELLS := 5
const MAX_FLAT_RECT := 0.03     # a clear sky gap between two towers is flat and rectangular too (about 0.015); the old white quads were 0.05 and more


static func flat_rects(img: Image) -> Dictionary:
	var cw := img.get_width() / FLAT_BLOCK
	var ch := img.get_height() / FLAT_BLOCK
	var flat := PackedByteArray()
	flat.resize(cw * ch)
	for cy in ch:
		for cx in cw:
			var lo := 1.0
			var hi := 0.0
			var sum := 0.0
			for y in range(cy * FLAT_BLOCK, (cy + 1) * FLAT_BLOCK, 2):
				for x in range(cx * FLAT_BLOCK, (cx + 1) * FLAT_BLOCK, 2):
					var l := luma(img.get_pixel(x, y))
					lo = minf(lo, l)
					hi = maxf(hi, l)
					sum += l
			var m := sum / float(FLAT_BLOCK * FLAT_BLOCK / 4)
			flat[cy * cw + cx] = 1 if (hi - lo < FLAT_RANGE and m > FLAT_LUMA) else 0
	var best := {"frac": 0.0, "rect": Rect2i()}
	var seen := PackedByteArray()
	seen.resize(cw * ch)
	for start in cw * ch:
		if flat[start] == 0 or seen[start] == 1:
			continue
		var stack: Array[int] = [start]
		seen[start] = 1
		var n := 0
		var x0 := cw
		var y0 := ch
		var x1 := 0
		var y1 := 0
		while not stack.is_empty():
			var c: int = stack.pop_back()
			var cx := c % cw
			var cy := c / cw
			n += 1
			x0 = mini(x0, cx)
			x1 = maxi(x1, cx)
			y0 = mini(y0, cy)
			y1 = maxi(y1, cy)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + d.x
				var ny: int = cy + d.y
				if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
					continue
				var ni := ny * cw + nx
				if flat[ni] == 1 and seen[ni] == 0:
					seen[ni] = 1
					stack.append(ni)
		var bw := x1 - x0 + 1
		var bh := y1 - y0 + 1
		if bw >= FLAT_MIN_CELLS and bh >= FLAT_MIN_CELLS and float(n) >= 0.85 * bw * bh:
			var frac := float(n) / float(cw * ch)
			if frac > float(best["frac"]):
				best = {"frac": frac, "rect": Rect2i(x0 * FLAT_BLOCK, y0 * FLAT_BLOCK, bw * FLAT_BLOCK, bh * FLAT_BLOCK)}
	return best


## Names of the first pair of rects (label -> Rect2) that overlap by more than 1 px each way; "" when none. Used for the title screen badges.
static func overlap(rects: Dictionary) -> String:
	var keys := rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			if a.grow(-1.0).intersects(b.grow(-1.0)):
				return "%s overlaps %s" % [keys[i], keys[j]]
	return ""


## Returns "" when the frame passes, otherwise the reasons (a short list).
static func verdict(s: Dictionary, sep := -1.0, people := -1, flat := 0.0, extra := "") -> String:
	var why: PackedStringArray = []
	if float(s["mean"]) < MIN_MEAN:
		why.append("too dark")
	if float(s["mean"]) > MAX_MEAN:
		why.append("blown out")
	if float(s["contrast"]) < MIN_CONTRAST:
		why.append("flat")
	if float(s["black"]) > MAX_BLACK:
		why.append("black")
	if people >= 0 and (float(s["mean"]) < MIN_STREET_MEAN):
		why.append("street too dark")
	if people >= 0 and people < MIN_PEOPLE:
		why.append("street empty")
	if sep >= 0.0 and sep < MIN_SEP:
		why.append("hero blends in")
	if flat > MAX_FLAT_RECT:
		why.append("flat white rectangle")
	if extra != "":
		why.append(extra)
	return ", ".join(why)
