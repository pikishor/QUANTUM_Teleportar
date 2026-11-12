class_name VehicleSpecs
extends RefCounted
## Numbers of the vehicles module: car specs (src/vehicles.js SPECS plus an SUV), the per-tier caps, colours, streaming distances and the traffic rules.
## Keep every tuning number here so the manager, the vehicle and the tests agree.

## Vehicles that feel like cars (owner round 3): top speeds 19-35 m/s (68-126 km/h, a sport car or interceptor 35, a bus 19) so the 1.3 km map takes 40-70 s, hit points are about
## 2.5x the old numbers (a normal crash does not wreck a car, see the CRASH_* constants), `acc` = first-gear acceleration of a CAR (cars use the gearbox + tyre model of
## Vehicle._drive_car, bikes and hover craft the arcade model); mu = optional tyre grip factor, steer = optional steering factor. Nitro adds NITRO_SPEED on top.
## max = top speed m/s, acc = acceleration m/s2, brake = braking m/s2, grip = lateral grip (1/s), hp, model = Game.load_model name,
## len / wid / hgt = the model's size in metres (assets contract), wheel = wheel radius, axle_z = axle offset from the centre (wheels sit at +-axle_z).
const SPECS := {
	&"sedan": {"cv2": "sedan", "rv": "sedan", "max": 22.0, "acc": 9.6, "brake": 40.0, "grip": 6.5, "hp": 300.0, "model": "car_sedan", "ov": "sedan", "len": 4.7, "wid": 1.85, "hgt": 1.42, "wheel": 0.35},
	&"sport": {"cv2": "sports", "rv": "sport", "max": 28.0, "acc": 12.0, "brake": 48.0, "grip": 5.2, "hp": 250.0, "model": "car_sport", "ov": "sport", "len": 4.5, "wid": 1.92, "hgt": 1.23, "wheel": 0.345, "mu": 1.25, "steer": 1.1},
	&"compact": {"cv2": "hatch", "rv": "compact", "shape": true, "max": 20.0, "acc": 8.6, "brake": 36.0, "grip": 6.2, "hp": 230.0, "mass": 1050.0, "seats": 4, "model": "car_compact", "ov": "hatch", "len": 3.9, "wid": 1.76, "hgt": 1.36, "wheel": 0.31, "mu": 1.0},
	&"suv": {"cv2": "suv", "rv": "suv", "max": 20.0, "acc": 7.4, "brake": 36.0, "grip": 6.8, "hp": 375.0, "model": "car_suv", "ov": "suv", "len": 4.7, "wid": 1.98, "hgt": 1.72, "wheel": 0.38, "mu": 1.05},
	# --- handling classes (optional keys, a spec without them is a plain car) ---
	# cls = "car" | "bike" | "hover"; alt = further Game.load_model names tried when `model` does not exist (the primitive fallback is used when none does);
	# bike: lean_max = body roll in rad at full lean, steer = steering rate factor; hover: hover_h = ride height of the model, bob = bob amplitude in m,
	# drift = extra sideways slide (grip stays low), coast = coast drag; far = look of the kind in the far traffic (tint, speed factor, see ambient_traffic.gd).
	&"bike": {"cls": "bike", "max": 26.0, "acc": 18.0, "brake": 38.0, "grip": 7.8, "hp": 140.0, "model": "bike_street", "alt": ["bike", "bike_sport"], "len": 2.1, "wid": 0.8, "hgt": 1.3,
		"wheel": 0.34, "lean_max": 0.62, "steer": 1.3, "far": {"tint": Color(1.0, 0.95, 0.82), "speed": 1.25}},
	&"hover": {"cv2": "hover", "cls": "hover", "max": 25.0, "acc": 14.0, "brake": 30.0, "grip": 2.2, "hp": 225.0, "model": "car_hover", "alt": ["hover_car", "hovercar"], "len": 4.6, "wid": 2.0, "hgt": 1.16,
		"wheel": 0.3, "hover_h": 0.55, "bob": 0.07, "drift": 1.0, "coast": 0.12, "steer": 1.15, "far": {"tint": Color(0.45, 0.95, 1.0), "speed": 1.1}},
	# Vael patrol vehicle: a hover chassis in the hive colours, chases the player from heat 3 (VehicleManager patrols), hp 400.
	&"vael_patrol": {"cls": "hover", "patrol": true, "max": 26.0, "acc": 16.0, "brake": 34.0, "grip": 3.0, "hp": 400.0, "model": "car_vael_patrol", "alt": ["vael_patrol", "hover_vael"],
		"len": 4.9, "wid": 2.1, "hgt": 1.3, "wheel": 0.3, "hover_h": 0.5, "bob": 0.05, "drift": 0.7, "coast": 0.14, "steer": 1.2, "far": {"tint": Color(0.75, 1.0, 0.45), "speed": 0.6}},
	# --- the Wave 14 art set (tools/blender/model_car_taxi.py ... ): sedan platform variants, a van and a truck. mass = kg, seats = driver included,
	# The paints of a kind are in PALETTES (taxis yellow, vans white and grey, the Vael patrol in hive tones).
	&"taxi": {"cv2": "taxi", "livery": 3, "rv": "taxi", "max": 21.0, "acc": 8.4, "brake": 38.0, "grip": 6.4, "hp": 325.0, "mass": 1500.0, "seats": 5, "model": "car_taxi", "ov": "taxi", "len": 4.7, "wid": 1.85, "hgt": 1.6, "wheel": 0.35},
	&"wagon": {"cv2": "wagon", "max": 21.0, "acc": 8.0, "brake": 38.0, "grip": 6.4, "hp": 340.0, "mass": 1600.0, "seats": 5, "model": "car_wagon", "len": 4.92, "wid": 1.9, "hgt": 1.55, "wheel": 0.35},
	&"van": {"cv2": "van", "rv": "van", "max": 19.0, "acc": 6.0, "brake": 32.0, "grip": 6.0, "hp": 440.0, "mass": 2300.0, "seats": 3, "model": "car_van", "ov": "van", "len": 5.2, "wid": 2.0, "hgt": 2.1, "wheel": 0.36, "mu": 0.98},
	&"truck": {"cv2": "boxtruck", "max": 17.0, "acc": 5.0, "brake": 28.0, "grip": 5.4, "hp": 650.0, "mass": 7500.0, "seats": 3, "model": "car_truck", "ov": "truck", "ov_low": true, "len": 6.4, "wid": 2.2, "hgt": 2.96, "wheel": 0.44, "mu": 0.95},
	# --- creature kit (tools/creature_kit.py, Quaternius space kit, CC0): a moon rover on four wheels and a hover skiff, both rare in the traffic mix.
	&"rover": {"parts": false, "max": 18.0, "acc": 7.0, "brake": 34.0, "grip": 6.2, "hp": 425.0, "mass": 1900.0, "seats": 2, "model": "car_rover", "len": 2.3, "wid": 1.9, "hgt": 2.03, "wheel": 0.3},
	&"skiff": {"cls": "hover", "max": 25.0, "acc": 14.0, "brake": 32.0, "grip": 2.0, "hp": 200.0, "mass": 900.0, "seats": 2, "model": "car_skiff", "len": 5.2, "wid": 1.85, "hgt": 1.4, "wheel": 0.3,
		"hover_h": 0.6, "bob": 0.09, "drift": 1.1, "coast": 0.12, "steer": 1.2, "far": {"tint": Color(0.7, 0.85, 1.0), "speed": 1.2}},
	# --- traffic and emergency set (primitive fallback until the art exists): a city bus, an interceptor and an ambulance (sirens: other traffic yields), a scooter-style quantum bike.
	&"bus": {"cv2": "bus", "rv": "bus", "shape": true, "max": 15.0, "acc": 4.2, "brake": 24.0, "grip": 5.0, "hp": 800.0, "mass": 11000.0, "seats": 4, "model": "car_bus", "alt": ["bus"], "len": 9.5, "wid": 2.5, "hgt": 3.2, "wheel": 0.46, "mu": 0.9},
	&"interceptor": {"cv2": "patrol", "livery": 4, "livery_color": Color(0.9, 0.91, 0.94), "rv": "police", "shape": true, "siren": true, "max": 28.0, "acc": 12.0, "brake": 46.0, "grip": 6.0, "hp": 350.0, "mass": 1500.0, "seats": 2, "model": "car_interceptor", "ov": "police", "alt": ["interceptor"], "len": 4.7, "wid": 1.95, "hgt": 1.52, "wheel": 0.35, "mu": 1.2},
	&"ambulance": {"cv2": "ambulance", "rv": "ambulance", "shape": true, "siren": true, "max": 21.0, "acc": 6.8, "brake": 34.0, "grip": 6.0, "hp": 475.0, "mass": 2800.0, "seats": 3, "model": "car_ambulance", "ov": "ambulance", "len": 5.4, "wid": 2.05, "hgt": 2.45, "wheel": 0.375, "mu": 1.0},
	&"qbike": {"shape": true, "cls": "bike", "max": 28.0, "acc": 19.0, "brake": 36.0, "grip": 8.0, "hp": 110.0, "mass": 140.0, "seats": 1, "model": "bike_quantum", "alt": ["scooter", "bike_street"], "len": 1.8, "wid": 0.6, "hgt": 1.15,
		"wheel": 0.26, "lean_max": 0.7, "steer": 1.4, "far": {"tint": Color(0.4, 0.95, 1.0), "speed": 1.3}},
	# --- open-source set (round 4, Kenney Car Kit CC0 via tools/open_models/convert_vehicles.py): five more street vehicles. "ov" = the converted model assets/models/ov_<ov>.glb, tried before `model` / `alt`.
	&"luxury": {"cv2": "limo", "rv": "luxury", "max": 21.0, "acc": 8.0, "brake": 38.0, "grip": 6.6, "hp": 420.0, "mass": 2300.0, "seats": 5, "model": "car_suv", "ov": "luxury", "len": 5.2, "wid": 1.95, "hgt": 1.55, "wheel": 0.37, "mu": 1.05},
	&"racer": {"cv2": "coupe", "rv": "racer", "max": 29.0, "acc": 13.5, "brake": 50.0, "grip": 5.0, "hp": 220.0, "mass": 1100.0, "seats": 1, "model": "car_sport", "ov": "race", "len": 4.3, "wid": 1.88, "hgt": 1.21, "wheel": 0.32, "mu": 1.3, "steer": 1.15},
	&"delivery": {"cv2": "delivery", "max": 17.0, "acc": 5.4, "brake": 30.0, "grip": 5.6, "hp": 560.0, "mass": 4200.0, "seats": 3, "model": "car_van", "ov": "delivery", "len": 5.8, "wid": 2.1, "hgt": 2.72, "wheel": 0.4, "mu": 0.96},
	&"garbage": {"cv2": "garbage", "max": 14.0, "acc": 4.2, "brake": 26.0, "grip": 5.0, "hp": 720.0, "mass": 9500.0, "seats": 3, "model": "car_truck", "ov": "garbage", "len": 6.7, "wid": 2.3, "hgt": 3.1, "wheel": 0.45, "mu": 0.9},
	&"firetruck": {"cv2": "firetruck", "siren": true, "max": 19.0, "acc": 5.0, "brake": 28.0, "grip": 5.2, "hp": 780.0, "mass": 11500.0, "seats": 3, "model": "car_truck", "ov": "firetruck", "len": 7.0, "wid": 2.3, "hgt": 2.9, "wheel": 0.46, "mu": 0.92},
	# --- round 4 (Rgsdev CC0 pack via tools/open_models/convert_rgs_vehicles.py): a muscle car and a pickup, more variety on the street.
	&"muscle": {"cv2": "muscle", "rv": "muscle", "max": 26.0, "acc": 11.0, "brake": 42.0, "grip": 5.6, "hp": 320.0, "mass": 1650.0, "seats": 2, "model": "car_sport", "len": 5.0, "wid": 1.9, "hgt": 1.33, "wheel": 0.345, "mu": 1.1},
	&"pickup": {"cv2": "pickup", "rv": "pickup", "max": 21.0, "acc": 7.4, "brake": 36.0, "grip": 6.0, "hp": 420.0, "mass": 2000.0, "seats": 3, "model": "car_suv", "len": 5.0, "wid": 1.95, "hgt": 1.8, "wheel": 0.41, "mu": 1.0},
	# --- open world freedom: the hero's HOVER-BIKE (CALL CAR with an empty garage, also a rare traffic kind): a bike chassis floating on a quantum cushion, fast and slidey, one seat.
	&"hoverbike": {"cls": "hover", "max": 28.0, "acc": 18.0, "brake": 34.0, "grip": 2.6, "hp": 150.0, "mass": 260.0, "seats": 1, "model": "bike_street", "alt": ["car_skiff"], "len": 2.1, "wid": 0.8, "hgt": 1.3,
		"wheel": 0.3, "hover_h": 0.75, "bob": 0.1, "drift": 1.0, "coast": 0.14, "steer": 1.35, "far": {"tint": Color(0.4, 1.0, 0.95), "speed": 1.3}},
	# --- round 5 roster (docs/DESIGN.md: any vehicle, GTA types): armoured truck, quad, scooter, helicopter, small plane, boat, tank. "craft" = a class with its own drive code (VehicleCraft: air / boat / tank);
	# "ceil" = flight ceiling m, "stall" = plane speed below which it sinks, "rotor_r" = rotor radius m, "span" = wing span m, "draft" = how deep a hull sits in the water m, "turret" = the model's rotating turret node.
	&"armoured": {"cv2": "armoured", "rv": "van", "armour": true, "max": 17.0, "acc": 6.2, "brake": 30.0, "grip": 5.6, "hp": 1250.0, "mass": 7200.0, "seats": 2, "model": "car_van", "len": 5.4, "wid": 2.2, "hgt": 2.65, "wheel": 0.4, "mu": 1.0},
	&"quad": {"cls": "quad", "procedural": "quad", "max": 22.0, "acc": 13.0, "brake": 30.0, "grip": 6.5, "hp": 190.0, "mass": 380.0, "seats": 2, "model": "car_quad", "len": 2.1, "wid": 1.25, "hgt": 1.25, "wheel": 0.34, "steer": 1.2},
	&"scooter": {"cls": "bike", "procedural": "scooter", "max": 19.0, "acc": 12.0, "brake": 28.0, "grip": 8.0, "hp": 90.0, "mass": 130.0, "seats": 2, "model": "bike_scooter", "len": 1.75, "wid": 0.65, "hgt": 1.15,
		"wheel": 0.22, "lean_max": 0.55, "steer": 1.5, "far": {"tint": Color(1.0, 0.9, 0.7), "speed": 0.85}},
	&"heli": {"cls": "heli", "craft": true, "max": 46.0, "acc": 15.0, "brake": 24.0, "grip": 2.0, "hp": 520.0, "mass": 2400.0, "seats": 3, "model": "xv_heli", "len": 11.0, "wid": 3.0, "hgt": 4.0, "wheel": 0.2, "rotor_r": 3.6, "ceil": 280.0, "cam_d": 19.0, "cam_h": 5.5, "exit_side": 4.2, "aim_cone": 0.5},
	&"plane": {"cls": "plane", "craft": true, "max": 64.0, "acc": 11.0, "brake": 18.0, "grip": 2.0, "hp": 420.0, "mass": 1500.0, "seats": 2, "model": "xv_plane", "len": 9.6, "wid": 3.0, "hgt": 3.4, "wheel": 0.45, "stall": 24.0, "span": 10.4, "ceil": 420.0, "cam_d": 20.0, "cam_h": 5.0, "exit_side": 5.8, "aim_cone": 0.3},
	# wave 106 (airport and aircraft): more flying kinds on the same craft physics (VehicleCraft -> AircraftFlight). "climb" = best climb m/s, "agile" = how fast the stick turns and rolls it (1 = the small plane),
	# "prop" = the model has a propeller (none: a jet, an afterburner node "Burner" glows with the throttle), "arms2" = the secondary weapon in ALT_WEAPONS (rockets / missiles on the AIM button).
	&"gunship": {"cls": "heli", "craft": true, "procedural": "gunship", "max": 62.0, "acc": 19.0, "brake": 26.0, "grip": 2.2, "hp": 950.0, "mass": 5200.0, "seats": 2, "model": "air_gunship", "len": 14.5, "wid": 5.2, "hgt": 4.0, "wheel": 0.2,
		"rotor_r": 6.6, "ceil": 420.0, "climb": 14.0, "agile": 1.25, "cam_d": 25.0, "cam_h": 6.8, "exit_side": 3.6, "aim_cone": 0.7, "arms2": true},
	&"hauler": {"cls": "heli", "craft": true, "procedural": "hauler", "max": 52.0, "acc": 14.0, "brake": 22.0, "grip": 2.0, "hp": 1250.0, "mass": 9000.0, "seats": 8, "model": "air_hauler", "len": 17.5, "wid": 3.9, "hgt": 5.2, "wheel": 0.3,
		"rotor_r": 8.4, "ceil": 380.0, "climb": 9.5, "agile": 0.8, "cam_d": 30.0, "cam_h": 8.0, "exit_side": 3.2, "aim_cone": 0.5},
	&"jet": {"cls": "plane", "craft": true, "max": 150.0, "acc": 30.0, "brake": 26.0, "grip": 2.0, "hp": 800.0, "mass": 6500.0, "seats": 1, "model": "xv_jet", "len": 14.0, "wid": 12.0, "hgt": 4.2, "wheel": 0.5, "stall": 42.0, "span": 12.0, "ceil": 1400.0,
		"climb": 34.0, "agile": 1.7, "jet": true, "burner": true, "cam_d": 27.0, "cam_h": 6.5, "exit_side": 4.4, "aim_cone": 0.35, "arms2": true},
	&"cargo": {"cls": "plane", "craft": true, "model": "xv_cargo", "max": 92.0, "acc": 10.0, "brake": 20.0, "grip": 2.0, "hp": 2200.0, "mass": 60000.0, "seats": 3, "len": 44.0, "wid": 37.0, "hgt": 11.5, "wheel": 0.9, "stall": 36.0, "span": 37.0, "ceil": 1100.0,
		"climb": 12.0, "agile": 0.55, "jet": true, "cam_d": 62.0, "cam_h": 15.0, "exit_side": 8.0, "aim_cone": 0.2},
	&"airliner": {"cls": "plane", "craft": true, "model": "xv_airliner", "max": 108.0, "acc": 12.0, "brake": 22.0, "grip": 2.0, "hp": 2000.0, "mass": 45000.0, "seats": 3, "len": 34.0, "wid": 30.0, "hgt": 10.0, "wheel": 0.9, "stall": 40.0, "span": 30.0, "ceil": 1200.0,
		"climb": 15.0, "agile": 0.6, "jet": true, "cam_d": 52.0, "cam_h": 13.0, "exit_side": 7.0, "aim_cone": 0.2},
	&"bizjet": {"cls": "plane", "craft": true, "model": "xv_bizjet", "max": 120.0, "acc": 18.0, "brake": 22.0, "grip": 2.0, "hp": 900.0, "mass": 12000.0, "seats": 3, "len": 19.0, "wid": 16.0, "hgt": 5.4, "wheel": 0.6, "stall": 36.0, "span": 16.0, "ceil": 1300.0,
		"climb": 22.0, "agile": 1.0, "jet": true, "cam_d": 34.0, "cam_h": 8.0, "exit_side": 5.2, "aim_cone": 0.25},
	&"boat": {"cls": "boat", "craft": true, "max": 27.0, "acc": 12.0, "brake": 16.0, "grip": 1.6, "hp": 330.0, "mass": 900.0, "seats": 4, "model": "xv_boat", "len": 5.2, "wid": 2.2, "hgt": 1.7, "wheel": 0.2, "draft": 0.35, "steer": 1.0, "cam_d": 10.5, "cam_h": 3.6, "exit_side": 2.6, "aim_cone": 0.6},
	# wave 105 (harbour): a JET SKI (fast, light, twitchy, one rider and a passenger) and the PATROL BOAT (a 9 m armed cruiser with a bow cannon); the SPEEDBOAT above is the middle one. Procedural bodies (VehicleCraftModels).
	&"jetski": {"cls": "boat", "craft": true, "procedural": "jetski", "max": 33.0, "acc": 17.0, "brake": 14.0, "grip": 2.4, "hp": 150.0, "mass": 320.0, "seats": 2, "model": "boat_jetski", "len": 3.0, "wid": 1.1, "hgt": 1.2, "wheel": 0.2,
		"draft": 0.2, "steer": 1.5, "cam_d": 7.5, "cam_h": 2.7, "exit_side": 1.7, "aim_cone": 0.5},
	&"patrol": {"cls": "boat", "craft": true, "procedural": "patrol", "max": 24.0, "acc": 9.0, "brake": 14.0, "grip": 1.3, "hp": 760.0, "mass": 4200.0, "seats": 4, "model": "boat_patrol", "len": 9.2, "wid": 3.2, "hgt": 3.0, "wheel": 0.2,
		"draft": 0.4, "steer": 0.8, "cam_d": 15.0, "cam_h": 5.2, "exit_side": 3.4, "aim_cone": 0.7},
	&"tank": {"cls": "tank", "craft": true, "max": 12.5, "acc": 5.5, "brake": 20.0, "grip": 8.0, "hp": 2000.0, "mass": 42000.0, "seats": 1, "model": "xv_tank", "len": 7.0, "wid": 3.3, "hgt": 2.7, "wheel": 0.5, "turret": "Turret", "steer": 0.8, "cam_d": 15.0, "cam_h": 5.6, "exit_side": 3.4, "arms2": true},
	# wave 108 (all weapon categories, tanks): the armoured family on the same tracked physics (VehicleCraft._tank). "gun_len" / "gun_h" = where the gun tip sits (m in front of the turret axis, share of the hull height),
	# "gun_max" = the highest the gun elevates (rad: 0.55 for a tank, artillery and anti-air go much higher), procedural bodies with a "Turret" node (VehicleCraftModels).
	&"ltank": {"cls": "tank", "craft": true, "procedural": "ltank", "max": 17.0, "acc": 8.0, "brake": 26.0, "grip": 8.0, "hp": 1100.0, "mass": 17000.0, "seats": 1, "model": "tank_light", "len": 5.8, "wid": 2.8, "hgt": 2.3,
		"wheel": 0.45, "turret": "Turret", "steer": 1.0, "cam_d": 13.0, "cam_h": 4.8, "exit_side": 3.0, "gun_len": 2.9, "gun_h": 0.86, "arms2": true},
	&"apc": {"cls": "tank", "craft": true, "procedural": "apc", "max": 22.0, "acc": 9.5, "brake": 26.0, "grip": 8.0, "hp": 1500.0, "mass": 14500.0, "seats": 6, "model": "tank_apc", "len": 6.8, "wid": 2.9, "hgt": 2.5,
		"wheel": 0.5, "turret": "Turret", "steer": 1.15, "cam_d": 14.5, "cam_h": 5.2, "exit_side": 3.2, "gun_len": 1.6, "gun_h": 0.95},
	&"artillery": {"cls": "tank", "craft": true, "procedural": "artillery", "max": 11.0, "acc": 4.5, "brake": 20.0, "grip": 8.0, "hp": 1000.0, "mass": 28000.0, "seats": 2, "model": "tank_artillery", "len": 7.6, "wid": 3.1, "hgt": 2.9,
		"wheel": 0.5, "turret": "Turret", "steer": 0.7, "cam_d": 17.0, "cam_h": 6.5, "exit_side": 3.4, "gun_len": 5.6, "gun_h": 0.8, "gun_max": 1.1},
	&"aatank": {"cls": "tank", "craft": true, "procedural": "aatank", "max": 17.0, "acc": 8.0, "brake": 24.0, "grip": 8.0, "hp": 900.0, "mass": 21000.0, "seats": 2, "model": "tank_aa", "len": 6.6, "wid": 3.1, "hgt": 3.1,
		"wheel": 0.5, "turret": "Turret", "steer": 0.95, "cam_d": 14.0, "cam_h": 5.8, "exit_side": 3.4, "gun_len": 2.6, "gun_h": 0.9, "gun_max": 1.35, "arms2": true},
}
## Paints of the kinds that do not wear the random street palette (VehicleVisual.set_paint maps the random COLORS pick to an entry; a husk keeps WRECK_COLOR).
const PALETTES := {
	&"taxi": [Color(0.86, 0.66, 0.16), Color(0.92, 0.74, 0.2), Color(0.8, 0.58, 0.12), Color(0.88, 0.7, 0.18)],
	&"van": [Color(0.84, 0.86, 0.88), Color(0.62, 0.66, 0.7), Color(0.3, 0.42, 0.56), Color(0.86, 0.87, 0.9), Color(0.4, 0.44, 0.48)],
	&"truck": [Color(0.56, 0.62, 0.66), Color(0.3, 0.42, 0.56), Color(0.68, 0.4, 0.26), Color(0.8, 0.82, 0.84)],
	&"bus": [Color(0.78, 0.5, 0.18), Color(0.28, 0.5, 0.62), Color(0.62, 0.66, 0.7), Color(0.3, 0.52, 0.48)],
	&"interceptor": [Color(0.22, 0.27, 0.40), Color(0.86, 0.87, 0.9), Color(0.24, 0.30, 0.50), Color(0.36, 0.39, 0.45)],
	&"ambulance": [Color(0.9, 0.91, 0.93), Color(0.86, 0.87, 0.9), Color(0.92, 0.93, 0.94), Color(0.88, 0.9, 0.92)],
	&"armoured": [Color(0.13, 0.16, 0.2), Color(0.1, 0.13, 0.11), Color(0.2, 0.19, 0.17), Color(0.14, 0.14, 0.16)],
	&"tank": [Color(0.24, 0.3, 0.2), Color(0.42, 0.36, 0.24), Color(0.2, 0.22, 0.24)],
	&"ltank": [Color(0.3, 0.34, 0.24), Color(0.46, 0.4, 0.28), Color(0.22, 0.26, 0.3)],
	&"apc": [Color(0.28, 0.32, 0.26), Color(0.5, 0.46, 0.34), Color(0.2, 0.24, 0.28)],
	&"artillery": [Color(0.32, 0.34, 0.26), Color(0.44, 0.38, 0.26), Color(0.22, 0.24, 0.26)],
	&"aatank": [Color(0.26, 0.3, 0.24), Color(0.38, 0.4, 0.3), Color(0.2, 0.22, 0.26)],
	&"heli": [Color(0.86, 0.87, 0.9), Color(0.14, 0.2, 0.34), Color(0.7, 0.12, 0.1), Color(0.18, 0.2, 0.22)],
	&"plane": [Color(0.86, 0.87, 0.9), Color(0.7, 0.12, 0.1), Color(0.12, 0.3, 0.6), Color(0.9, 0.7, 0.12)],
	&"gunship": [Color(0.2, 0.24, 0.2), Color(0.16, 0.18, 0.22), Color(0.3, 0.28, 0.2), Color(0.12, 0.13, 0.15)],
	&"hauler": [Color(0.3, 0.34, 0.26), Color(0.4, 0.38, 0.3), Color(0.24, 0.27, 0.3), Color(0.5, 0.52, 0.5)],
	&"jet": [Color(0.46, 0.5, 0.54), Color(0.3, 0.34, 0.4), Color(0.62, 0.64, 0.66), Color(0.26, 0.3, 0.26)],
	&"cargo": [Color(0.34, 0.38, 0.32), Color(0.78, 0.8, 0.82), Color(0.5, 0.52, 0.54), Color(0.7, 0.42, 0.14)],
	&"airliner": [Color(0.9, 0.91, 0.93), Color(0.88, 0.89, 0.92), Color(0.86, 0.9, 0.95), Color(0.92, 0.88, 0.86)],
	&"bizjet": [Color(0.9, 0.91, 0.93), Color(0.12, 0.13, 0.16), Color(0.7, 0.72, 0.76), Color(0.86, 0.82, 0.7)],
	&"boat": [Color(0.86, 0.87, 0.9), Color(0.12, 0.3, 0.6), Color(0.7, 0.12, 0.1), Color(0.1, 0.1, 0.12)],
	&"jetski": [Color(0.9, 0.38, 0.1), Color(0.12, 0.5, 0.7), Color(0.86, 0.87, 0.9), Color(0.7, 0.12, 0.3)],
	&"patrol": [Color(0.7, 0.74, 0.78), Color(0.22, 0.28, 0.4), Color(0.76, 0.78, 0.8)],
	&"muscle": [Color(0.78, 0.12, 0.1), Color(0.1, 0.1, 0.12), Color(0.9, 0.62, 0.1), Color(0.14, 0.3, 0.6)],
	&"pickup": [Color(0.2, 0.36, 0.26), Color(0.62, 0.64, 0.68), Color(0.7, 0.3, 0.16), Color(0.12, 0.14, 0.2)],
	&"luxury": [Color(0.1, 0.1, 0.12), Color(0.2, 0.22, 0.26), Color(0.55, 0.56, 0.6), Color(0.14, 0.16, 0.28)],
	&"racer": [Color(0.7, 0.12, 0.1), Color(0.9, 0.75, 0.12), Color(0.12, 0.4, 0.7), Color(0.9, 0.9, 0.92)],
	&"delivery": [Color(0.86, 0.87, 0.9), Color(0.84, 0.86, 0.88), Color(0.3, 0.42, 0.56), Color(0.8, 0.45, 0.15)],
	&"garbage": [Color(0.2, 0.45, 0.3), Color(0.25, 0.4, 0.6), Color(0.7, 0.4, 0.15)],
	&"firetruck": [Color(0.72, 0.1, 0.08), Color(0.76, 0.14, 0.1)],
	&"vael_patrol": [Color(0.3, 0.36, 0.26), Color(0.26, 0.2, 0.36), Color(0.2, 0.3, 0.32), Color(0.34, 0.26, 0.3)],
}
## mass (kg) and seats of the kinds that carry no inline "mass" / "seats" key (read them through mass_of() / seats_of()).
const BASE_STATS := {
	&"sedan": {"mass": 1450.0, "seats": 5}, &"sport": {"mass": 1250.0, "seats": 2}, &"suv": {"mass": 2100.0, "seats": 5},
	&"bike": {"mass": 220.0, "seats": 2}, &"hover": {"mass": 1100.0, "seats": 3}, &"vael_patrol": {"mass": 1900.0, "seats": 2},
}
## Cars of the original set (shader warm-up and legacy tests); streaming uses STREAM_KINDS.
const KINDS: Array[StringName] = [&"sedan", &"sport", &"suv"]
const KIND_WEIGHTS: Array[float] = [0.5, 0.25, 0.25]
## Spawn weights of a streamed vehicle (sedan, sport, suv, bike, hover, taxi, wagon, van, truck, rover, skiff, bus, interceptor, ambulance, qbike). Patrols (vael_patrol) are never streamed, the manager adds them from heat 3.
const STREAM_KINDS: Array[StringName] = [&"sedan", &"sport", &"suv", &"compact", &"bike", &"hover", &"taxi", &"wagon", &"van", &"truck", &"rover", &"skiff", &"bus", &"interceptor", &"ambulance", &"qbike", &"hoverbike",
	&"luxury", &"racer", &"delivery", &"garbage", &"firetruck", &"muscle", &"pickup", &"armoured", &"quad", &"scooter"]
const STREAM_WEIGHTS: Array[float] = [0.05, 0.06, 0.06, 0.093, 0.06, 0.06, 0.08, 0.04, 0.06, 0.05, 0.01, 0.01, 0.04, 0.03, 0.02, 0.03, 0.02,
	0.03, 0.02, 0.03, 0.02, 0.02, 0.02, 0.02, 0.012, 0.025, 0.03]

## The whole roster, in the order of the vehicle picture sheet: every drivable kind (streamed traffic first, then the ones with fixed spawn points, see VehicleSpawns). Tests and the picture maker read it.
const ROSTER: Array[StringName] = [&"compact", &"sedan", &"sport", &"muscle", &"suv", &"van", &"pickup", &"bus", &"taxi", &"interceptor", &"ambulance", &"firetruck", &"armoured", &"bike", &"quad", &"scooter",
	&"hoverbike", &"heli", &"plane", &"gunship", &"hauler", &"jet", &"cargo", &"airliner", &"bizjet", &"boat", &"tank", &"ltank", &"apc", &"artillery", &"aatank", &"luxury", &"racer", &"wagon", &"truck", &"delivery", &"garbage", &"hover", &"qbike", &"skiff", &"rover"]
## The armoured family (tracked physics, a turret that slews to the crosshair, VehicleCraft._tank): main battle tank, light tank, personnel carrier, mobile artillery, anti-air.
const TANK_KINDS: Array[StringName] = [&"tank", &"ltank", &"apc", &"artillery", &"aatank"]
## The roster kinds that fly, float or crawl on tracks (spawned at fixed points, never as random traffic).
const CRAFT_KINDS: Array[StringName] = [&"heli", &"plane", &"boat", &"tank", &"ltank", &"apc", &"artillery", &"aatank"]
## Every kind that flies (VehicleCraft classes heli / plane): the airport spawns, the AI air traffic and the flight HUD read this.
const AIRCRAFT_KINDS: Array[StringName] = [&"heli", &"plane", &"gunship", &"hauler", &"jet", &"cargo", &"airliner", &"bizjet"]
## The kinds that float (VehicleCraft._boat): they ride the real water of the world (WaterWorld) and the flooded quarter.
const BOAT_KINDS: Array[StringName] = [&"boat", &"jetski", &"patrol"]
## Display names (the HUD toast on entering, the picture sheet).
const NAMES := {&"compact": "COMPACT", &"sedan": "SEDAN", &"sport": "SPORTS CAR", &"muscle": "MUSCLE CAR", &"suv": "SUV", &"van": "VAN", &"pickup": "PICKUP TRUCK", &"bus": "BUS", &"taxi": "TAXI",
	&"interceptor": "POLICE CAR", &"ambulance": "AMBULANCE", &"firetruck": "FIRE TRUCK", &"armoured": "ARMOURED TRUCK", &"bike": "MOTORBIKE", &"quad": "QUAD", &"scooter": "SCOOTER", &"hoverbike": "HOVER BIKE",
	&"heli": "HELICOPTER", &"plane": "SMALL PLANE", &"gunship": "GUNSHIP", &"hauler": "TRANSPORT HELICOPTER", &"jet": "JET FIGHTER", &"cargo": "CARGO PLANE", &"airliner": "AIRLINER", &"bizjet": "BUSINESS JET", &"boat": "SPEEDBOAT", &"jetski": "JET SKI", &"patrol": "PATROL BOAT", &"tank": "BATTLE TANK", &"ltank": "LIGHT TANK", &"apc": "ARMOURED CARRIER", &"artillery": "MOBILE ARTILLERY", &"aatank": "ANTI-AIR TANK", &"luxury": "LIMO", &"racer": "RACER", &"wagon": "WAGON", &"truck": "TRUCK", &"delivery": "DELIVERY VAN",
	&"garbage": "GARBAGE TRUCK", &"hover": "HOVER CAR", &"qbike": "QUANTUM SCOOTER", &"skiff": "HOVER SKIFF", &"rover": "MOON ROVER", &"vael_patrol": "VAEL PATROL"}

## Live cars at once (starter car and a driven car included): LOW 3 / MED 5 / HIGH 8. Each legacy car costs about 10 draw calls.
const CAPS: Array[int] = [3, 5, 8]
const STREAM_RADIUS := 110.0           ## only cars within about this distance of the player exist as nodes (the starter car excepted)
const DESPAWN_RADIUS := 124.0          ## hysteresis: a car is released beyond this
const SPAWN_MIN := 40.0                ## streamed cars appear between SPAWN_MIN and SPAWN_MAX from the player
const SPAWN_MAX := 105.0
const STREAM_EVERY := 0.4              ## seconds between streaming passes
const MIRROR_NEAR := 25.0              ## MirrorProxy only for cars this close (released beyond MIRROR_NEAR + 8)
const WHEELS_NEAR := 50.0              ## wheels are hidden beyond this
const PARKED_SHARE := 0.55             ## fraction of streamed cars that are parked
const WRECK_COLOR := Color(0.15, 0.125, 0.11)   ## the charred paint of a husk (was 0.045: a pure black cut-out in the street; now soot-brown with a visible shape)
const MAX_WRECKS := 3                  ## husks standing at once (the oldest goes first)
const RESPAWN_TIME := 25.0             ## a destroyed car comes back as a parked car after this many seconds

const BAY := 8.3                       ## parking bay centre offset from the road centre line (bays are 7.0-9.4 m)
const STARTER_DX := 9.0                ## the starter sport car stands at SPAWN.x + this, on the parking bay (z = BAY) of the main avenue, facing +X
const STARTER_COLOR := 2               ## index into COLORS: brass, so the starter car is easy to find
const STARTER_HEADING := -PI * 0.5

const COLORS: Array[Color] = [
	# desaturated lacquer palette (clear coat + flakes, see VehicleVisual.set_paint): oxblood, steel blue, brass (the starter), sage teal,
	# dusk violet, pearl, burnt copper, midnight. Nothing is a flat saturated primary any more.
	Color(0.56, 0.20, 0.24), Color(0.30, 0.42, 0.56), Color(0.78, 0.66, 0.44), Color(0.30, 0.52, 0.48),
	Color(0.42, 0.38, 0.60), Color(0.86, 0.87, 0.90), Color(0.68, 0.40, 0.26), Color(0.20, 0.25, 0.42),
	# round 6 (Cars v2): four more paints, each with its own finish in CarV2.FINISH: cobalt, racing red (gloss), gunmetal, sunset orange (pearl)
	Color(0.12, 0.24, 0.62), Color(0.66, 0.08, 0.09), Color(0.24, 0.27, 0.31), Color(0.86, 0.40, 0.10),
]
const PAINT_GAIN := 1.0
const GLOWS: Array[Color] = [Color(0.22, 0.96, 1.0), Color(1.0, 0.24, 0.94), Color(0.22, 1.0, 0.69), Color(0.61, 0.42, 1.0)]

# --- driving: bikes and hover craft keep the arcade model (src/vehicles.js drive()), cars use the gearbox + tyre model (Vehicle._drive_car) ---
const REVERSE_FRACTION := 0.3          ## top reverse speed as a fraction of max
const COAST_DRAG := 0.5                ## 1/s, no throttle (arcade classes)
const HANDBRAKE_DRAG := 1.2            ## 1/s longitudinal (arcade classes)
const HANDBRAKE_GRIP := 1.4            ## lateral grip with the handbrake (arcade classes)
const STEER_RATE := 2.3                ## rad/s at full authority (arcade classes)
const UNPOWERED_DRAG := 3.0            ## a car nobody drives slows down with this rate

# --- the car model: single-track (bicycle) tyres with a slip-angle curve, weight transfer, a 5 speed gearbox, speed sensitive steering ---
const G := 9.8
const GEAR_TOPS: Array[float] = [0.20, 0.38, 0.57, 0.77, 1.0]     ## top speed of each gear as a fraction of the car's top speed
const GEAR_ACC: Array[float] = [1.0, 0.8, 0.64, 0.52, 0.42]       ## acceleration of each gear relative to the first (the spec's `acc`)
const SHIFT_TIME := 0.2                ## s of torque cut at every gear change (the engine note drops, the car lurches a little)
const UPSHIFT_AT := 0.93               ## rpm fraction of the gear that changes up
const DOWNSHIFT_BELOW := 0.55          ## rpm fraction the LOWER gear would be at that makes the box change down
const IDLE_RPM := 0.16
const ENGINE_BRAKE := 2.4              ## m/s2 of deceleration with the throttle released
const AERO := 0.0016                   ## 1/m: aero + rolling drag decel = AERO * v^2
const BRAKE_K := 0.32                  ## spec["brake"] x this = braking deceleration in m/s2 (a sedan: 15 m/s2)
const CG_FRONT := 0.46                 ## centre of gravity distance from the front axle as a fraction of the wheel base
const WHEEL_BASE := 0.6                ## wheel base as a fraction of the car length (a bus and a van are longer, see wheelbase())
const CG_HEIGHT := 0.34                ## centre of gravity height as a fraction of the car height
const MU := 1.12                       ## tyre grip on dry asphalt (a spec may scale it with "mu"); wet streets take WET_GRIP_LOSS of it
const WET_GRIP_LOSS := 0.2
const PEAK_SLIP := 0.15                ## rad: the slip angle of the most lateral force; beyond it the tyre slides (grip falls to SLIDE_GRIP of the peak)
const SLIDE_GRIP := 0.66
const STEER_MAX := 0.6                 ## rad of front wheel angle at a standstill
const STEER_V0 := 11.0                 ## m/s at which the lock has fallen to about half
const STEER_RATE_CAR := 3.2            ## rad/s wheel speed turning in, STEER_RETURN turning back
const STEER_RETURN := 5.0
const COUNTER_STEER := 0.9             ## assist: the front wheels follow the slip angle of the body, a slide is caught instead of spinning the car
const YAW_DAMP := 0.5                  ## 1/s of extra yaw damping (inertia of the whole car)
const LOW_SPEED := 2.0                 ## m/s: below this the car turns kinematically (a tyre model has no meaning at a walking pace)
const HANDBRAKE_REAR := 0.34           ## rear tyre grip factor while the handbrake is held (it comes back over DRIFT_RECOVER s)
const BODY_PITCH := 0.0042             ## rad per m/s2 of longitudinal acceleration (nose dip under braking, squat under power)
const BODY_ROLL := 0.0055              ## rad per m/s2 of lateral acceleration
const BODY_PITCH_MAX := 0.075
const BODY_ROLL_MAX := 0.085

# --- drift (E1) ---
const DRIFT_RECOVER := 0.6             ## s: traction returns this slowly after the handbrake is released
const DRIFT_ASSIST := 1.1              ## rad/s of extra yaw when steering against a slide (arcade classes)
const SMOKE_SLIP := 3.5                ## lateral speed (m/s) above which the tyres smoke
const TYRE_SMOKE_EVERY := 0.09

# --- collisions and damage (owner round 3: a car survives normal crashes; damage grows with the impact speed along the contact normal) ---
const HIT_SPEED := 5.0                 ## wall impact (normal speed) above this is a collision with sound and sparks (arcade classes also hurt from here)
const HIT_DAMAGE := 2.2                ## arcade classes: hp per m/s of impact
const BOUNCE := 1.2                    ## arcade classes: vn restitution factor (vel -= BOUNCE * vn * n)
const RESTITUTION := 0.22              ## cars: bounce off a wall or another car
const WALL_FRICTION := 0.4             ## tangential speed lost per unit of normal impulse (a scrape)
const CRASH_SAFE := 8.0                ## m/s along the contact normal (18 km/h): below this a bump does nothing to the hull
const CRASH_WRECK := 28.5              ## m/s (103 km/h): a wall hit this hard takes the whole hull of a stock car (CRASH_REF_HP). 25 km/h costs about 2 %, 40 km/h 13 %, 60 km/h 35 %, 90 km/h 78 % (round 4: top speeds are 22-29 m/s, 90 km/h and more is reached with the nitro)
const CRASH_POWER := 1.8               ## damage fraction = ((v - SAFE) / (WRECK - SAFE)) ^ POWER
const CRASH_REF_HP := 300.0            ## hp that fraction is of (a sedan: the damage is absolute, a bus with 800 hp survives much more)
const CAR_SEPARATION := 3.6            ## circle distance of the car-to-car bump (legacy, the OBB test uses the real hull sizes)
const CAR_HIT_SPEED := 6.5             ## relative speed above which two cars hurt each other
const HERO_HURT_SPEED := 20.0          ## the driver is hurt only by hard impacts (m/s along the normal, 72 km/h): HERO_HURT_MAX hp x ((v - this) / (CRASH_WRECK - this))^2, so 90 km/h costs about 10 hp
const HERO_HURT_MAX := 30.0
const HERO_HURT_CAP := 0.3             ## one crash never takes more than this share of the driver's health (director review: 92 km/h cost the driver 67 %)
const CRASH_SURVIVE_V := 26.5          ## closing speed (m/s, about 95 km/h): a hull above CRASH_LIMP_FROM is never wrecked by ONE hit up to this speed, it limps home with CRASH_LIMP_HP left
const CRASH_LIMP_FROM := 0.3
const CRASH_LIMP_HP := 0.1
const CRASH_BUMP_MAX := 0.12           ## one bump at or below CRASH_BUMP_V never takes more than this share of the hull (director round 3: three 40-50 km/h bumps wrecked a car)
const CRASH_BUMP_V := 15.5             ## m/s (56 km/h)
const WEDGE_SPEED := 0.6              ## m/s: below this with the throttle held the car counts as wedged ...
const WEDGE_SPEED_CRASH := 1.4        ## ... and below this for WEDGE_AFTER_CRASH s after a crash (the wreck crawls at 1-4 km/h against a kerb: it used to sit there 2-4 s, director review 4 defect 12)
const WEDGE_AFTER_CRASH := 4.0
const NUDGE_SECS := 0.9               ## the automatic reverse
const WEDGE_SECS := 0.8                ## the driver holds the throttle and the car does not move for this long: the car backs out by itself (a nudge) and the HUD says REVERSE
const CRASH_REPEAT_GAP := 0.35         ## s: a scrape along a wall counts as one crash, not one per frame
const EXTERNAL_DAMAGE := 1.0           ## factor of damage() from bullets, blasts and fire (the callers' numbers did not change, the hit points did)
const RAM_SPEED := 8.0                 ## running over enemies needs this speed
const RAM_RADIUS := 2.4
const RAM_FACTOR := 3.5
const RAM_COOLDOWN := 0.6
const CARJACK_HEAT := 0.2
const GLASS_BREAK_AT := 0.35           ## hull damage fraction from which the windows crack (earlier on a hard frontal hit)
const DENT_MIN := 0.04                 ## damage fraction of one impact that dents the panels at all

# --- damage states, enter / exit ---
const WISP_BELOW := 0.7                ## hp fraction: a thin grey wisp from the bonnet (stage 1 of 4: wisp, smoke, fire; dents and cracked glass come with every hit)
const SMOKE_BELOW := 0.4               ## hp fraction: smoke
const FIRE_BELOW := 0.15               ## hp fraction: fire, the car burns down (BURN_DPS hp per second) and blows up
const BURN_DPS := 3.4
const FX_RANGE := 70.0                 ## smoke and fire are only spawned this close to the player
const SMOKE_EVERY := 0.34
const FIRE_EVERY := 0.2
const EXIT_SAFE_SPEED := 9.0           ## leaving a car faster than this hurts (EXIT_HURT hp per m/s over it)
const EXIT_HURT := 2.0
const CHAIN_RADIUS := 7.0              ## open world: a car that blows up sets every car within this of it alight ...
const CHAIN_DELAY := 1.4               ## ... and they follow after up to this many seconds (staggered by distance): a pile-up goes off one after the other
const ENTER_REACH := 1.9               ## metres from the hull edge a car can be entered or hijacked (the old 4.2 m from the middle still works); a moving car adds ENTER_MOVING per m/s
const ENTER_MOVING := 0.12
const ENTER_MOVING_MAX := 2.6
const EXIT_BRAKE := 0.6                ## a car the player leaves keeps this share of its speed (it rolls to a stop)

# --- mounted weapons (E2): rate = shots/s, dmg per hit, heat per shot (1.0 locks), cool = heat/s, ammo = rounds, range m, spread rad, blast = radius (0 none) ---
const WEAPONS := {
	&"sport": {"name": "RAIL GUN", "rate": 9.0, "dmg": 9.0, "heat": 0.07, "cool": 0.35, "ammo": 240, "range": 90.0, "spread": 0.025, "color": Color(0.3, 0.95, 1.0)},
	&"suv": {"name": "CANNON", "rate": 1.4, "dmg": 55.0, "heat": 0.4, "cool": 0.3, "ammo": 30, "range": 110.0, "spread": 0.0, "blast": 3.5, "color": Color(1.0, 0.6, 0.2)},
	&"heli": {"name": "MINIGUN", "rate": 16.0, "dmg": 8.0, "heat": 0.035, "cool": 0.3, "ammo": 700, "range": 170.0, "spread": 0.03, "color": Color(1.0, 0.82, 0.3)},
	&"plane": {"name": "WING GUNS", "rate": 12.0, "dmg": 10.0, "heat": 0.05, "cool": 0.3, "ammo": 500, "range": 190.0, "spread": 0.02, "color": Color(1.0, 0.9, 0.5)},
	&"gunship": {"name": "CHAIN GUN", "rate": 20.0, "dmg": 9.0, "heat": 0.03, "cool": 0.32, "ammo": 900, "range": 230.0, "spread": 0.022, "color": Color(1.0, 0.78, 0.3)},
	&"hauler": {"name": "DOOR GUN", "rate": 14.0, "dmg": 7.0, "heat": 0.035, "cool": 0.3, "ammo": 600, "range": 170.0, "spread": 0.035, "color": Color(1.0, 0.82, 0.3)},
	&"jet": {"name": "CANNON", "rate": 22.0, "dmg": 12.0, "heat": 0.03, "cool": 0.3, "ammo": 700, "range": 320.0, "spread": 0.012, "color": Color(1.0, 0.9, 0.55)},
	&"patrol": {"name": "BOW CANNON", "rate": 2.2, "dmg": 34.0, "heat": 0.16, "cool": 0.3, "ammo": 120, "range": 150.0, "spread": 0.012, "blast": 3.0, "color": Color(1.0, 0.7, 0.3)},
	&"boat": {"name": "DECK GUN", "rate": 6.0, "dmg": 13.0, "heat": 0.1, "cool": 0.3, "ammo": 240, "range": 100.0, "spread": 0.02, "color": Color(0.6, 0.9, 1.0)},
	&"tank": {"name": "TANK CANNON", "rate": 0.8, "dmg": 95.0, "heat": 0.42, "cool": 0.28, "ammo": 40, "range": 220.0, "spread": 0.0, "blast": 7.0, "color": Color(1.0, 0.55, 0.18)},
	&"ltank": {"name": "LIGHT CANNON", "rate": 1.5, "dmg": 60.0, "heat": 0.3, "cool": 0.3, "ammo": 60, "range": 200.0, "spread": 0.0, "blast": 4.5, "color": Color(1.0, 0.6, 0.2)},
	&"apc": {"name": "AUTOCANNON", "rate": 8.0, "dmg": 16.0, "heat": 0.07, "cool": 0.3, "ammo": 400, "range": 170.0, "spread": 0.015, "color": Color(1.0, 0.82, 0.35)},
	&"artillery": {"name": "HOWITZER", "rate": 0.28, "dmg": 190.0, "heat": 0.9, "cool": 0.3, "ammo": 24, "range": 520.0, "spread": 0.0, "blast": 11.0, "indirect": true, "delay": 1.4, "color": Color(1.0, 0.5, 0.15)},
	&"aatank": {"name": "FLAK CANNON", "rate": 10.0, "dmg": 11.0, "heat": 0.05, "cool": 0.3, "ammo": 600, "range": 320.0, "spread": 0.02, "blast": 3.5, "flak": true, "color": Color(1.0, 0.9, 0.5)},
	&"hover": {"name": "BOLT GUN", "rate": 5.0, "dmg": 16.0, "heat": 0.14, "cool": 0.3, "ammo": 120, "range": 100.0, "spread": 0.01, "color": Color(0.8, 0.4, 1.0)},
}
## The secondary weapon of the aircraft with "arms2" (the AIM button while flying): unguided ROCKETS and homing-lite MISSILES that fly a real distance (AircraftArms): rate = shots/s (a salvo fires `salvo` rockets),
## dmg = direct hit, blast = radius m, speed = m/s, life = s in flight, reload = s for one round back.
const ALT_WEAPONS := {
	&"gunship": {"name": "ROCKET POD", "short": "ROCKET", "rate": 3.2, "salvo": 2, "dmg": 80.0, "blast": 7.5, "speed": 150.0, "life": 3.2, "ammo": 28, "reload": 2.2, "color": Color(1.0, 0.62, 0.2), "range": 420.0},
	&"tank": {"name": "COAX MACHINE GUN", "short": "COAX", "kind": "gun", "rate": 14.0, "dmg": 11.0, "ammo": 300, "reload": 0.12, "range": 160.0, "spread": 0.02, "color": Color(1.0, 0.85, 0.4)},
	&"ltank": {"name": "COAX MACHINE GUN", "short": "COAX", "kind": "gun", "rate": 12.0, "dmg": 9.0, "ammo": 240, "reload": 0.12, "range": 150.0, "spread": 0.022, "color": Color(1.0, 0.85, 0.4)},
	&"aatank": {"name": "SEEKER MISSILES", "short": "MISSILE", "rate": 1.6, "salvo": 1, "dmg": 130.0, "blast": 8.0, "speed": 200.0, "life": 3.5, "ammo": 8, "reload": 3.0, "color": Color(1.0, 0.8, 0.4), "range": 600.0, "homing": 1.8},
	&"jet": {"name": "MISSILES", "short": "MISSILE", "rate": 2.0, "salvo": 1, "dmg": 130.0, "blast": 10.0, "speed": 230.0, "life": 3.8, "ammo": 14, "reload": 3.0, "color": Color(1.0, 0.8, 0.4), "range": 800.0, "homing": 1.6},
}
const WEAPON_LOCK_RESUME := 0.4        ## an overheated weapon fires again below this heat

# --- nitro (E4): sprint while driving ---
const ROAD_KICK := 0.7                ## m/s of heave velocity a road seam gives the body at 20 m/s (Vehicle._sync_body: the suspension bounces over the street)
const NITRO_SPEED := 1.3               ## top speed factor
const NITRO_ACC := 1.9                 ## acceleration factor
const NITRO_DRAIN := 0.33              ## tank (0..1) per second
const NITRO_REGEN := 0.12
const NITRO_DELAY := 1.2               ## s after boosting before the tank refills
const NITRO_MIN := 0.08                ## tank needed to start a boost
const NITRO_COOL := 12.0               ## m/s2 the extra speed bleeds off after a boost

# --- Vael pursuit tactics (E4): ram, boxin (hold station beside him, squeeze), block (get ahead and sit across the road) ---
const TACTICS: Array[StringName] = [&"ram", &"boxin", &"block"]
const BOXIN_SIDE := 4.2                ## m beside the target
const BLOCK_AHEAD := 38.0              ## m ahead of the target (scaled by his speed, see Vehicle.chase_goal)
const BLOCK_STOP := 7.0                ## within this of the road block point the patrol stops and turns broadside

# --- Vael patrols (chase from heat PATROL_HEAT) ---
const PATROL_HEAT := 3.0
const PATROL_CAPS: Array[int] = [1, 1, 2]       ## patrol vehicles at once per tier (they use the car cap)
const PATROL_EVERY := 6.0              ## seconds between spawn attempts
const PATROL_MIN := 55.0
const PATROL_MAX := 100.0
const PATROL_STAND_DOWN := 2.0         ## heat below this: patrols stop chasing and are released once 45 m away
const PATROL_RAM_DAMAGE := 9.0         ## hp of the player (or the driven car x 0.6) per ram, PATROL_RAM_COOLDOWN apart
const PATROL_RAM_COOLDOWN := 1.1
const PATROL_SIREN := [Color(1.0, 0.1, 0.1), Color(0.2, 0.4, 1.0)]

# --- police pursuit ladder (VehicleManager._tick_cops) ---
const COP_HEAT := 0.5                  ## heat from which an interceptor tails the hero
const COP_RAM_HEAT := 2.0              ## below: it shadows him with the siren on, from here it rams
const COP_RAM_FACTOR := 0.7            ## a police ram hurts a little less than a Vael patrol's
const COP_SPIKE_HEAT := 3.0            ## from here the police lay spike strips ahead of a driving hero
const COP_CAPS: Array[int] = [2, 3, 4]    ## interceptors at once per tier
const COP_EVERY := 5.0
const COP_MIN := 50.0
const COP_MAX := 95.0
const COP_STAND_DOWN := 0.3
const SPIKE_EVERY := 12.0              ## s between strips
const SPIKE_AHEAD := 60.0              ## m ahead of the hero's motion
const SPIKE_HALF_WIDTH := 4.6
const SPIKE_HALF_DEPTH := 1.0
const SPIKE_LIFE := 25.0
const TIRES_TIME := 9.0
const TIRES_SPEED := 0.55
const TIRES_GRIP := 0.55
const TIRES_DAMAGE := 12.0

# --- traffic (right-hand lanes on Game.LANE, junction turns, stops for obstacles) ---
const AI_LOOK := 11.0                  ## obstacle check distance ahead
const AI_SIDE := 2.6                   ## obstacle check half width
const AI_CRUISE_MIN := 9.0
const AI_CRUISE_MAX := 14.0
const AI_TURN_COOLDOWN := 14.0         ## metres before the next junction may turn again
const AI_STRAIGHT_CHANCE := 0.55
# --- traffic rules (wave 53): lights at every junction, yielding to sirens, reactions to horn / gunfire / crashes ---
const SIGNAL_CYCLE := 18.0             ## s: axis 0 is green for 7.5 s, amber 1.5 s, then red while axis 1 runs (offset by half a cycle)
const SIGNAL_GREEN := 7.5
const SIGNAL_AMBER := 1.5
const LIGHT_LOOK := 22.0               ## a car starts braking for a red this many metres before the junction centre
const LIGHT_COMMIT := 4.5              ## closer than this it is committed and drives through
const AMBER_STOP := 11.0               ## on amber it stops only when farther than this
const SIREN_SPEED := 1.35              ## emergency cars cruise this much faster
const YIELD_RANGE := 45.0              ## a siren this close behind makes traffic pull over
const YIELD_SHIFT := 2.2               ## m towards the kerb while yielding (the siren car passes beside it without touching: 1.9 m is the two half widths)
const SIREN_PASS := 2.0                ## m a siren car moves towards the middle of the road to pass a slower car (with the yielding car's own shift to the kerb the two clear each other)
const YIELD_SPEED := 4.0               ## m/s while yielding
const PANIC_TIME := 4.0                ## s of flight after gunfire
const PANIC_SPEED := 1.5
const GUN_HEAR := 45.0
const HORN_HEAR := 16.0
const HORN_NUDGE := 1.5                ## s a car ahead of a horn hurries on
const CRASH_HEAR := 20.0
const STUN_TIME := 1.4                 ## s traffic near a crash stops


## 0 green, 1 amber, 2 red for traffic travelling along `axis` at signal clock `clock` (s). The two axes are never green together.
static func signal_state(axis: int, clock: float) -> int:
	var t := fposmod(clock + (0.0 if axis == 0 else SIGNAL_CYCLE * 0.5), SIGNAL_CYCLE)
	if t < SIGNAL_GREEN:
		return 0
	return 1 if t < SIGNAL_GREEN + SIGNAL_AMBER else 2


static func name_of(kind: StringName) -> String:
	return String(NAMES.get(kind, String(kind).to_upper()))


static func is_siren(kind: StringName) -> bool:
	return SPECS.has(kind) and bool(SPECS[kind].get("siren", false))


static func starter_pos() -> Vector3:
	return Vector3(Game.SPAWN.x + STARTER_DX, 0.0, BAY)


static func pick_kind(r: float) -> StringName:
	var acc := 0.0
	for i in STREAM_KINDS.size():
		acc += STREAM_WEIGHTS[i]
		if r < acc:
			return STREAM_KINDS[i]
	return STREAM_KINDS[STREAM_KINDS.size() - 1]


## Handling class of a kind: &"car", &"bike" or &"hover".
static func cls_of(kind: StringName) -> StringName:
	return StringName(SPECS[kind].get("cls", &"car")) if SPECS.has(kind) else &"car"


## Every Game.load_model name of a kind, best first.
static func model_names(kind: StringName) -> Array[String]:
	var out: Array[String] = []
	if not SPECS.has(kind):
		return out
	var v2 := CarV2.model_of(kind)                        # round 6: the Blender-built high-detail set leads when it exists (QT_CARS_V2=0 brings the older art back)
	if v2 != "":
		out.append(v2)
	if SPECS[kind].has("rv") and OS.get_environment("QT_OPEN_MODELS") != "0" and OS.get_environment("QT_RV_MODELS") != "0":       # QT_RV_MODELS=0: the Kenney / older art (before captures, test_open_models). Round 4: the Rgsdev pack (real proportions, small wheels, window glass) leads on every tier
		out.append("rv_" + String(SPECS[kind]["rv"]))
	if SPECS[kind].has("ov") and OS.get_environment("QT_OPEN_MODELS") != "0":     # QT_OPEN_MODELS=0: the older art only (before / after captures, the legacy model tests)
		if not SPECS[kind].has("ov_low") or Game.quality <= 0:                  # "ov_low": the older art (5-12k triangles, smoother) stays first above LOW, the 1-2k triangle open model serves LOW
			out.append("ov_" + String(SPECS[kind]["ov"]))
		else:
			out.append(String(SPECS[kind]["model"]))
			for a: String in SPECS[kind].get("alt", []):
				out.append(a)
			out.append("ov_" + String(SPECS[kind]["ov"]))
			return out
	out.append(String(SPECS[kind]["model"]))
	for a: String in SPECS[kind].get("alt", []):
		out.append(a)
	return out


## Mass in kg (the inline "mass" key, else BASE_STATS, else a sedan's).
static func mass_of(kind: StringName) -> float:
	if SPECS.has(kind) and SPECS[kind].has("mass"):
		return float(SPECS[kind]["mass"])
	return float(BASE_STATS.get(kind, BASE_STATS[&"sedan"])["mass"])


## Wheel base in metres: WHEEL_BASE x the length (a bus, a truck and a van carry their wheels nearer the ends).
static func wheelbase(kind: StringName) -> float:
	var ln := float(SPECS[kind]["len"]) if SPECS.has(kind) else 4.75
	var k := WHEEL_BASE + (0.06 if ln > 5.0 else 0.0)
	return ln * k


## Tyre grip factor of a kind on dry asphalt (MU x the spec's "mu").
## Cars that are built for rough ground: the rover, SUV, trucks and the quad keep most of their grip off the road; the rest slide on dirt, sand and snow.
const OFFROAD: Dictionary = {&"rover": 1.0, &"suv": 0.88, &"luxury": 0.7, &"truck": 0.85, &"van": 0.6, &"delivery": 0.6, &"quad": 1.0, &"tank": 1.0, &"ltank": 1.0, &"apc": 1.0, &"artillery": 0.9, &"aatank": 1.0}
## Grip multiplier by surface for a full off-road build (k = 1) and for a street car (k = 0): lerp of the two columns by the kind's off-road rating.
const SURFACE_GRIP: Dictionary = {&"city": [1.0, 1.0], &"asphalt": [1.0, 1.0], &"dirt": [0.9, 0.6], &"grass": [0.82, 0.48], &"sand": [0.74, 0.42], &"rock": [0.86, 0.6], &"snow": [0.6, 0.36], &"water": [0.5, 0.3]}
const SURFACE_SPEED: Dictionary = {&"city": [1.0, 1.0], &"asphalt": [1.0, 1.0], &"dirt": [0.95, 0.78], &"grass": [0.9, 0.62], &"sand": [0.85, 0.55], &"rock": [0.85, 0.6], &"snow": [0.75, 0.5], &"water": [0.6, 0.35]}


static func offroad_rating(kind: StringName) -> float:
	return float(OFFROAD.get(kind, 0.35))


static func surface_grip(kind: StringName, surface: StringName) -> float:
	var row: Array = SURFACE_GRIP.get(surface, [1.0, 1.0])
	return lerpf(float(row[1]), float(row[0]), offroad_rating(kind))


static func surface_speed(kind: StringName, surface: StringName) -> float:
	var row: Array = SURFACE_SPEED.get(surface, [1.0, 1.0])
	return lerpf(float(row[1]), float(row[0]), offroad_rating(kind))


static func mu_of(kind: StringName) -> float:
	return MU * (float(SPECS[kind].get("mu", 1.0)) if SPECS.has(kind) else 1.0)


## Seats, driver included (the inline "seats" key, else BASE_STATS, else 4).
static func seats_of(kind: StringName) -> int:
	if SPECS.has(kind) and SPECS[kind].has("seats"):
		return int(SPECS[kind]["seats"])
	return int(BASE_STATS.get(kind, {"seats": 4})["seats"])


## The paint a kind wears for the random COLORS entry `c`: its own palette (taxis are yellow, vans white and grey ...) when it has one in PALETTES and `c` is one of COLORS, else `c` itself
## (a husk's WRECK_COLOR and every kind without a palette are untouched).
static func paint_for(kind: StringName, c: Color) -> Color:
	if not PALETTES.has(kind):
		return c
	var i := COLORS.find(c)
	if i < 0:
		return c
	var pal: Array = PALETTES[kind]
	return pal[i % pal.size()]


## The first model of the kind that exists as an asset ("" when none does: the primitive fallback is drawn).
static func available_model(kind: StringName) -> String:
	for m in model_names(kind):
		if ResourceLoader.exists("res://assets/models/%s.glb" % m):
			return m
	return ""


## The look of a kind in the far traffic, falling back to the sedan's when the kind is unknown or its model is not built yet.
static func far_look(kind: StringName) -> Dictionary:
	if SPECS.has(kind) and SPECS[kind].has("far") and (available_model(kind) != "" or cls_of(kind) == &"car"):
		return SPECS[kind]["far"]
	return {"tint": Color(1.0, 0.92, 0.78), "speed": 1.0}


static func cap_for(quality: int) -> int:
	var n: int = CAPS[clampi(quality, 0, 2)]
	if quality == 0:
		n = LowPlus.scaled(n, LowPlus.CAR_SHARE, 2)               # LOW+: 2 live cars
	return PerfTiers.cap_scale(n)        # the Compatibility renderer spawns fewer


## Vehicle heading (Node3D.rotation.y, forward = -Z) for travelling along `axis` (0 = +-X, 1 = +-Z) in direction `dir` (+1 / -1).
static func heading_for(axis: int, dir: int) -> float:
	if axis == 0:
		return -PI * 0.5 if dir > 0 else PI * 0.5
	return PI if dir > 0 else 0.0


## Signed offset from a road's centre line of the right-hand lane (or bay, with dist = BAY) for travel direction `dir` along `axis`. Facing +X the right
## hand is +Z, facing +Z it is -X, so axis 0 gives +dist * dir and axis 1 gives -dist * dir (src/vehicles.js used +dist * dir on both: left-hand traffic on Z roads).
static func lane_offset(axis: int, dir: int, dist: float) -> float:
	return dist * dir if axis == 0 else -dist * dir


## Road centre line coordinate of road `i` (0..N).
static func road_center(i: int) -> float:
	return -Game.HALF + i * Game.PITCH


## Index of the road centre line nearest to v.
static func road_index(v: float) -> int:
	return clampi(roundi((v + Game.HALF) / Game.PITCH), 0, Game.N)
