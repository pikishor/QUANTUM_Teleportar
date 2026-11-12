class_name TrafficBrain
extends RefCounted
## The shared driving rules of every AI car (real Vehicles, the near traffic, the road traffic, the bridge cars): how fast may I go with the car in front of me (a safe-distance model that
## never lets two hulls touch), how much room do I leave, and how the speed follows what is allowed. Numbers live here so the cars of every layer behave alike.

const TAU_REACT := 0.55           ## s: the headway a driver keeps (about the gap he needs to see and brake)
const COMFORT := 6.5              ## m/s2: the braking a driver plans for (a hard stop in front of him is answered with more, see HARD)
const HARD := 15.0                ## m/s2: the braking a car can do in an emergency (a sedan: 15)
const STANDSTILL := 2.2           ## m between bumpers when stopped
const ACCEL_TO := 3.4             ## m/s2 of normal acceleration when the way is free
const ACCEL_REAL := 4.0           ## m/s2: a real traffic car pulling away
const ACCEL_SIREN := 8.0          ## m/s2: an emergency car
const LEAD_BRAKE := 12.0          ## m/s2: the hardest the car in front is assumed to brake (a follower plans for that, not for a gentle stop)
const CREEP := 0.7               ## m/s: below this allowance a car stops
const LOOK_BASE := 9.0            ## m of look-ahead at a standstill
const LOOK_HEADWAY := 1.9         ## s of travel added to the look-ahead


## The look-ahead distance (m beyond the bumper) at speed `v`.
static func look_for(v: float) -> float:
	return LOOK_BASE + maxf(v, 0.0) * LOOK_HEADWAY


## The highest speed (m/s) a car may drive with a leader `gap` m ahead (bumper to bumper) going `v_lead` m/s along the same line: the speed from which it can still stop short of the leader
## when the leader brakes as hard as `lead_decel` (Gipps: v * tau + v^2 / 2b <= gap + v_lead^2 / 2 lead_decel). 0 inside `s0`.
static func safe_speed(gap: float, v_lead: float, decel := COMFORT, tau := TAU_REACT, s0 := STANDSTILL, lead_decel := LEAD_BRAKE) -> float:
	var g := gap - s0
	if g <= 0.0:
		return 0.0
	var vl := maxf(v_lead, 0.0)
	var bt := decel * tau
	return maxf(0.0, -bt + sqrt(bt * bt + 2.0 * decel * g + decel * vl * vl / lead_decel))


## One step of a speed towards `want`: gentle acceleration, firm braking, and a hard brake when `want` is far below `v` (something appeared close).
static func approach(v: float, want: float, dt: float, accel := ACCEL_TO) -> float:
	if want < CREEP:
		want = 0.0                                              # a car that is allowed less than a walking pace stands still (no endless creeping towards the bumper in front)
	if want >= v:
		return minf(want, v + accel * dt)
	var drop := v - want
	var b := COMFORT if drop < 4.0 else minf(HARD, COMFORT + (drop - 4.0) * 1.6)
	return maxf(want, v - b * dt)
