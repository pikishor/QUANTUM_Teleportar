class_name VisualQaLib
extends RefCounted
## Numeric helpers of the visual QA tool (tools/visual_qa.sh, tests/bot_visual_qa.gd): luma stats of a frame and pass / fail rules.

const MIN_MEAN := 0.05          ## darker than this on average: a black or lost frame
const MAX_MEAN := 0.80          ## brighter than this: blown out
const MIN_CONTRAST := 0.04      ## luma standard deviation below this: a flat frame
const MAX_BLACK := 0.85         ## fraction of near-black pixels above this: not a picture
const MIN_SEP := 0.02           ## hero vs background: luma gap or colour gap of the two means


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


## Returns "" when the frame passes, otherwise the reasons (a short list).
static func verdict(s: Dictionary, sep := -1.0) -> String:
	var why: PackedStringArray = []
	if float(s["mean"]) < MIN_MEAN:
		why.append("too dark")
	if float(s["mean"]) > MAX_MEAN:
		why.append("blown out")
	if float(s["contrast"]) < MIN_CONTRAST:
		why.append("flat")
	if float(s["black"]) > MAX_BLACK:
		why.append("black")
	if sep >= 0.0 and sep < MIN_SEP:
		why.append("hero blends in")
	return ", ".join(why)
