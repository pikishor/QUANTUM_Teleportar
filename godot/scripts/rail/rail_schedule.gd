class_name RailSchedule
extends RefCounted
## The timetable of a line: every train shuttles over the whole line (ping-pong), stopping at every station, with a trapezoid speed profile between stops. The position of a train is a pure
## function of the clock (`at(t)`), so trains run on schedule whether anybody watches them or not, and a test can ask where a train is at any time.
## Stops are station centres (metres along the route). A train of `phase` (0..1 of the period) is that far through the cycle at t = 0.

const ACCEL := 0.9
const MAGLEV_ACCEL := 1.5
const DWELL := 24.0
const DWELL_TERMINAL := 45.0

var route_id: StringName
var stops := PackedFloat32Array()
var names: Array[String] = []
var cyc := PackedInt32Array()                      ## the cycle of stop indices
var seg_t0 := PackedFloat32Array()                 ## start time of every segment (dwell then move)
var seg_dwell := PackedFloat32Array()
var seg_move := PackedFloat32Array()
var seg_peak := PackedFloat32Array()               ## peak speed of the leg
var period := 1.0
var vmax := 30.0
var accel := ACCEL


func _init(r: Dictionary) -> void:
	route_id = r["id"]
	vmax = float(r["speed"])
	accel = MAGLEV_ACCEL if r["style"] == &"maglev" else ACCEL
	var sts: Array = r["stations"]
	for st: Dictionary in sts:
		stops.append(float(st["s"]))
		names.append(String(st["name"]))
	var n := stops.size()
	for i in n:
		cyc.append(i)
	for i in range(n - 2, 0, -1):
		cyc.append(i)
	var t := 0.0
	for k in cyc.size():
		var a := stops[cyc[k]]
		var b := stops[cyc[(k + 1) % cyc.size()]]
		var term: bool = bool((sts[cyc[k]] as Dictionary)["terminal"])
		var dw := DWELL_TERMINAL if term else DWELL
		var l := absf(b - a)
		var v := vmax
		var mt := 0.0
		var dacc := vmax * vmax / (2.0 * accel)
		if l >= 2.0 * dacc:
			mt = 2.0 * vmax / accel + (l - 2.0 * dacc) / vmax
		else:
			v = sqrt(l * accel)
			mt = 2.0 * v / accel
		seg_t0.append(t)
		seg_dwell.append(dw)
		seg_move.append(mt)
		seg_peak.append(v)
		t += dw + mt
	period = t


## The state at clock time `t` (seconds) for a train `phase` of the period ahead: {u (centre, metres along the route), dir (+1 / -1, the way it is heading or last went), v (m/s, >= 0),
## stop (index of the station it is standing at, -1 while moving), dwell_left (s), next (index of the next stop)}.
func at(t: float, phase: float) -> Dictionary:
	var tt := fposmod(t + phase * period, period)
	for k in cyc.size():
		var t0 := seg_t0[k]
		var dw := seg_dwell[k]
		var mt := seg_move[k]
		if tt >= t0 + dw + mt:
			continue
		var a := stops[cyc[k]]
		var b := stops[cyc[(k + 1) % cyc.size()]]
		var dir := 1 if b > a else -1
		var pk := (k - 1 + cyc.size()) % cyc.size()
		if tt < t0 + dw:
			var prev_a := stops[cyc[pk]]
			var d0 := 1 if a > prev_a else -1
			return {"u": a, "dir": dir if tt > t0 + dw * 0.5 else d0, "v": 0.0, "stop": cyc[k], "dwell_left": t0 + dw - tt, "next": cyc[(k + 1) % cyc.size()], "leg": k}
		var tau := tt - (t0 + dw)
		var v := seg_peak[k]
		var ta := v / accel
		var da := 0.5 * accel * ta * ta
		var l := absf(b - a)
		var dist := 0.0
		var speed := 0.0
		if tau < ta:
			dist = 0.5 * accel * tau * tau
			speed = accel * tau
		elif tau < mt - ta:
			dist = da + v * (tau - ta)
			speed = v
		else:
			var rem := mt - tau
			dist = l - 0.5 * accel * rem * rem
			speed = accel * rem
		return {"u": a + float(dir) * dist, "dir": dir, "v": speed, "stop": -1, "dwell_left": 0.0, "next": cyc[(k + 1) % cyc.size()], "leg": k}
	return {"u": stops[0], "dir": 1, "v": 0.0, "stop": 0, "dwell_left": 0.0, "next": 1 % stops.size(), "leg": 0}
