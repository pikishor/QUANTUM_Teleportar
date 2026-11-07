class_name LifeCensus
extends RefCounted
## What is alive around a point (tests, the life bot): civilians by state, moving cars, vendors, fauna.

static func take(center: Vector3, r := 40.0) -> Dictionary:
	var out := {"civ": 0, "civ_walk": 0, "civ_talk": 0, "civ_shop": 0, "civ_flee": 0, "cars": 0, "cars_moving": 0, "near_cars": 0, "vendors": 0, "events": 0, "fauna": 0}
	var w := Game.world as City
	if w == null or w.ambient == null:
		return out
	var cr = w.ambient.crowd
	out["vendors"] = cr.vendors_near(center, r)
	out["events"] = w.ambient.beats.active_near(center, r)
	for i in cr.count:
		if not cr.is_alive(i):
			continue
		var d: Vector3 = cr.person_position(i) - center
		if d.x * d.x + d.z * d.z > r * r:
			continue
		out["civ"] += 1
		match cr.state_of(i):
			&"walk":
				out["civ_walk"] += 1
			&"idle":
				out["civ_talk"] += 1
			&"linger":
				out["civ_shop"] += 1
			&"flee", &"cower":
				out["civ_flee"] += 1
	if Game.vehicles != null:
		for v in Game.vehicles.list:
			var dv: Vector3 = v.global_position - center
			if dv.x * dv.x + dv.z * dv.z > r * r:
				continue
			out["cars"] += 1
			if absf(v.speed) > 3.0:
				out["cars_moving"] += 1
	var nt: NearTraffic = w.ambient.near_traffic
	for i in nt.count:
		if nt.car_alive(i):
			var dn: Vector3 = nt.car_position(i) - center
			if dn.x * dn.x + dn.z * dn.z <= r * r:
				out["cars"] += 1
				out["near_cars"] += 1
				if nt.car_speed(i) > 3.0:
					out["cars_moving"] += 1
	var f = w.ambient.fauna
	for i in f.count:
		if f.active[i] != 0:
			var df: Vector3 = f.pos[i] - center
			if df.x * df.x + df.z * df.z <= r * r:
				out["fauna"] += 1
	return out
