#!/usr/bin/env python3
"""WAVE 125 HELICOPTER ROSTER: the one table of the twenty new helicopter kinds (original names, own-made procedural models).
Writes scripts/vehicles/heli_roster.gd (HeliRoster.DEFS: name, role, model parameters, flight numbers) and prints the lines that were
pasted into VehicleSpecs (SPECS / PALETTES / NAMES / ROSTER / AIRCRAFT_KINDS / WEAPONS) and AudioDirector.ENGINES (with --lines).
Run: python3 tools/gen_heli_roster.py [--lines]"""
import sys, os

# id, name, role, stats (max m/s, acc, climb m/s, agile, mass kg, hp, seats, rotor pitch, dB), dims (len, wid, hgt, rotor_r), cam (d, h, exit_side),
# weapon (name, rate, dmg, ammo, range) or None, palette, model params (GDScript literal)
H = [
 ("h_scout", "SPARROW SCOUT", "light scout", (50, 18, 13, 1.45, 1100, 360, 2, 1.35, 0), (8.6, 2.0, 3.0, 4.2), (16, 4.8, 3.0), None,
  ["(0.92, 0.72, 0.16)", "(0.86, 0.87, 0.9)", "(0.2, 0.42, 0.3)", "(0.12, 0.14, 0.18)"],
  '{"cab": [-3.0, 0.6, 0.72, 0.78, 1.42], "n": 2.0, "nose": "bubble", "boom": [5.2, 1.85, 0.15], "rotor": [2.7, -0.6, 2, 0.26], "gear": "skids", "x": []}'),
 ("h_news", "SKYEYE NEWS", "news", (48, 16, 12, 1.25, 1600, 420, 3, 1.22, 0), (10.0, 2.2, 3.3, 4.8), (17, 5.0, 3.2), None,
  ["(0.86, 0.87, 0.9)", "(0.16, 0.3, 0.6)", "(0.9, 0.42, 0.1)", "(0.2, 0.2, 0.22)"],
  '{"cab": [-3.4, 1.0, 0.82, 0.86, 1.55], "n": 2.2, "nose": "glass", "boom": [6.0, 2.0, 0.19], "rotor": [2.95, -0.5, 3, 0.3], "gear": "skids", "x": ["camera", "mast", "stripe"], "mark": Color(1.0, 0.8, 0.2)}'),
 ("h_police", "WARDEN PATROL", "police", (54, 18, 13, 1.3, 1900, 520, 3, 1.18, 1), (10.6, 2.3, 3.4, 5.0), (18, 5.2, 3.3), ("SIDE GUN", 10.0, 6.0, 400, 150.0),
  ["(0.12, 0.16, 0.3)", "(0.86, 0.87, 0.9)", "(0.1, 0.1, 0.12)", "(0.2, 0.3, 0.5)"],
  '{"cab": [-3.6, 1.1, 0.86, 0.88, 1.6], "n": 2.4, "nose": "glass", "boom": [6.4, 2.05, 0.2], "rotor": [3.05, -0.5, 4, 0.3], "gear": "skids", "x": ["light", "bar", "steps"], "mark": Color(0.25, 0.5, 1.0)}'),
 ("h_medic", "MERCY AIR AMBULANCE", "air ambulance", (50, 15, 11, 1.0, 3200, 600, 4, 1.0, 1), (12.0, 2.6, 3.7, 5.4), (20, 5.6, 3.4), None,
  ["(0.92, 0.93, 0.94)", "(0.94, 0.86, 0.2)", "(0.86, 0.9, 0.92)", "(0.7, 0.12, 0.1)"],
  '{"cab": [-4.0, 2.0, 1.0, 1.0, 1.72], "n": 2.6, "nose": "glass", "boom": [6.8, 2.3, 0.24], "rotor": [3.35, -0.5, 4, 0.34], "tail": "fen", "gear": "wheels", "x": ["cross", "winch"], "mark": Color(0.95, 0.1, 0.1)}'),
 ("h_utility", "MULE UTILITY", "utility", (48, 14, 11, 0.95, 4200, 800, 8, 0.95, 1), (13.0, 2.7, 3.9, 6.4), (22, 6.0, 3.4), ("DOOR GUN", 12.0, 7.0, 500, 160.0),
  ["(0.32, 0.36, 0.28)", "(0.86, 0.6, 0.12)", "(0.5, 0.5, 0.52)", "(0.16, 0.2, 0.3)"],
  '{"cab": [-4.2, 2.4, 1.1, 1.1, 1.76], "n": 3.0, "nose": "point", "boom": [7.4, 2.4, 0.25], "rotor": [3.5, -0.6, 4, 0.4], "gear": "skids", "x": ["steps", "doorgun"]}'),
 ("h_tandem", "TWINBEAM CARGO", "tandem-rotor cargo", (46, 11, 9, 0.7, 11000, 1500, 10, 0.72, 3), (18.0, 3.4, 6.0, 7.2), (32, 8.5, 3.6), None,
  ["(0.34, 0.36, 0.3)", "(0.42, 0.4, 0.32)", "(0.26, 0.28, 0.32)", "(0.6, 0.6, 0.58)"],
  '{"cab": [-8.0, 8.0, 1.5, 1.5, 2.2], "n": 3.2, "nose": "glass", "lay": "tandem", "rotor": [4.5, 0.0, 3, 0.6], "tail": "none", "gear": "wheels", "x": ["ramp", "sponson"]}'),
 ("h_heavy", "ATLAS HEAVY LIFT", "heavy lift", (42, 9, 8, 0.55, 15000, 2000, 12, 0.6, 3), (22.0, 4.6, 6.4, 9.6), (36, 9.5, 3.8), None,
  ["(0.5, 0.52, 0.46)", "(0.3, 0.32, 0.26)", "(0.8, 0.5, 0.12)", "(0.2, 0.22, 0.26)"],
  '{"cab": [-8.5, 5.5, 1.9, 1.8, 2.6], "n": 3.0, "nose": "glass", "boom": [11.5, 4.2, 0.55], "rotor": [6.0, -1.0, 7, 0.6], "gear": "wheels", "x": ["sponson", "engines"], "fin": 2.6}'),
 ("h_attack", "HORNET ATTACK", "attack", (70, 22, 15, 1.5, 4800, 1000, 2, 1.25, 3), (13.5, 5.2, 3.8, 6.0), (24, 6.6, 3.4), ("CANNON", 18.0, 10.0, 800, 240.0),
  ["(0.24, 0.26, 0.22)", "(0.18, 0.2, 0.24)", "(0.36, 0.32, 0.24)", "(0.12, 0.13, 0.15)"],
  '{"cab": [-5.0, 1.8, 0.6, 0.85, 1.62], "n": 2.2, "nose": "tandem", "boom": [7.8, 2.0, 0.28], "rotor": [3.45, 0.0, 4, 0.32], "gear": "wheels", "x": ["wings", "pods", "chin"]}'),
 ("h_stealth", "SHADE STEALTH", "stealth", (74, 22, 15, 1.45, 5000, 900, 2, 1.4, -2), (13.0, 4.4, 3.6, 5.8), (24, 6.4, 3.4), ("CANNON", 18.0, 10.0, 700, 240.0),
  ["(0.16, 0.17, 0.19)", "(0.22, 0.24, 0.26)", "(0.1, 0.1, 0.12)", "(0.26, 0.24, 0.3)"],
  '{"cab": [-5.2, 1.6, 0.78, 0.82, 1.62], "n": 6.0, "nose": "facet", "boom": [7.4, 1.95, 0.32], "rotor": [3.25, 0.0, 5, 0.3], "tail": "fen", "gear": "wheels", "x": ["bays", "chin"]}'),
 ("h_coax", "DUOSPIN COAXIAL", "coaxial", (60, 19, 14, 1.6, 6000, 1000, 3, 1.05, 2), (11.5, 3.0, 4.6, 6.4), (22, 6.4, 3.4), ("CANNON", 16.0, 9.0, 700, 220.0),
  ["(0.3, 0.36, 0.34)", "(0.4, 0.38, 0.28)", "(0.2, 0.22, 0.26)", "(0.56, 0.58, 0.6)"],
  '{"cab": [-4.2, 1.8, 0.95, 1.0, 1.72], "n": 2.4, "nose": "glass", "boom": [5.8, 2.0, 0.3], "lay": "coax", "rotor": [3.4, -0.4, 3, 0.36], "tail": "none", "gear": "wheels", "x": ["fins2", "wings"]}'),
 ("h_tilt", "SWIFTWING TILTROTOR", "tilt-rotor", (85, 16, 12, 0.9, 14000, 1300, 8, 0.85, 3), (17.0, 15.0, 5.2, 4.8), (34, 8.0, 3.8), None,
  ["(0.5, 0.52, 0.5)", "(0.3, 0.34, 0.3)", "(0.86, 0.87, 0.9)", "(0.22, 0.24, 0.3)"],
  '{"cab": [-7.0, 5.0, 1.2, 1.2, 2.0], "n": 2.8, "nose": "glass", "boom": [8.6, 2.8, 0.45], "lay": "tilt", "span": 6.6, "rotor": [4.9, 0.4, 3, 0.4], "tail": "none", "gear": "wheels", "x": ["fins2"]}'),
 ("h_crane", "STORK SKYCRANE", "crane", (40, 9, 8, 0.55, 9500, 1400, 2, 0.65, 3), (20.0, 5.0, 6.0, 9.0), (34, 9.0, 3.4), None,
  ["(0.62, 0.62, 0.6)", "(0.86, 0.6, 0.14)", "(0.3, 0.34, 0.3)", "(0.2, 0.22, 0.26)"],
  '{"cab": [-8.0, -4.0, 1.0, 1.1, 3.0], "n": 2.6, "nose": "glass", "boom": [10.0, 3.6, 0.4], "rotor": [5.4, -1.0, 6, 0.56], "gear": "legs", "x": ["spine", "hook"], "fin": 2.2}'),
 ("h_fire", "EMBER FIREHAWK", "firefighting", (50, 14, 11, 0.95, 5600, 950, 4, 0.9, 2), (14.0, 2.8, 4.0, 6.8), (24, 6.4, 3.4), None,
  ["(0.78, 0.12, 0.08)", "(0.9, 0.7, 0.12)", "(0.86, 0.87, 0.9)", "(0.2, 0.2, 0.22)"],
  '{"cab": [-4.6, 2.6, 1.15, 1.1, 1.85], "n": 2.8, "nose": "glass", "boom": [8.0, 2.5, 0.28], "rotor": [3.6, -0.5, 4, 0.42], "gear": "wheels", "x": ["tank", "winch"], "mark": Color(1.0, 0.85, 0.2)}'),
 ("h_vip", "REGENT EXECUTIVE", "VIP", (64, 18, 13, 1.15, 4300, 650, 6, 1.1, 0), (13.0, 2.6, 3.8, 6.0), (22, 6.0, 3.4), None,
  ["(0.12, 0.12, 0.14)", "(0.86, 0.87, 0.9)", "(0.36, 0.1, 0.14)", "(0.2, 0.26, 0.4)"],
  '{"cab": [-4.8, 2.4, 1.05, 1.0, 1.75], "n": 2.2, "nose": "glass", "boom": [7.6, 2.3, 0.26], "rotor": [3.4, -0.4, 5, 0.32], "tail": "fen", "gear": "wheels", "x": ["stripe"], "mark": Color(0.95, 0.78, 0.4)}'),
 ("h_trainer", "PUPIL TRAINER", "trainer", (40, 15, 10, 1.35, 650, 260, 2, 1.5, -1), (7.6, 1.8, 2.7, 3.9), (15, 4.4, 2.8), None,
  ["(0.9, 0.9, 0.86)", "(0.86, 0.3, 0.12)", "(0.2, 0.5, 0.7)", "(0.3, 0.6, 0.3)"],
  '{"cab": [-2.6, 0.4, 0.62, 0.7, 1.35], "n": 2.0, "nose": "bubble", "boom": [4.6, 1.5, 0.09], "rotor": [2.45, -0.4, 2, 0.22], "gear": "skids", "x": ["truss", "engine_open"]}'),
 ("h_quantum", "QUANTA PHASE", "sci-fi quantum", (80, 26, 18, 1.7, 3000, 800, 2, 1.6, 0), (11.0, 2.4, 3.8, 5.2), (21, 6.0, 3.2), ("PHASE BOLT", 8.0, 18.0, 300, 220.0),
  ["(0.86, 0.87, 0.9)", "(0.2, 0.2, 0.26)", "(0.42, 0.38, 0.6)", "(0.3, 0.52, 0.48)"],
  '{"cab": [-4.4, 1.6, 0.9, 0.86, 1.6], "n": 2.0, "nose": "bubble", "boom": [5.0, 1.8, 0.3], "rotor": [3.2, 0.0, 6, 0.26], "tail": "none", "gear": "skids", "x": ["ring", "glow", "fins2"], "mark": Color(0.25, 0.95, 1.0)}'),
 ("h_void", "VOIDHOPPER", "sci-fi quantum coaxial", (76, 24, 20, 1.55, 3600, 900, 3, 1.75, 0), (10.0, 4.6, 4.2, 4.6), (21, 6.0, 3.6), ("PHASE BOLT", 8.0, 18.0, 300, 220.0),
  ["(0.18, 0.16, 0.24)", "(0.86, 0.87, 0.9)", "(0.12, 0.14, 0.18)", "(0.5, 0.2, 0.5)"],
  '{"cab": [-3.8, 2.2, 1.2, 0.9, 1.75], "n": 3.5, "nose": "facet", "lay": "coax", "rotor": [3.0, -0.6, 4, 0.3], "tail": "none", "gear": "legs", "x": ["ring", "glow"], "mark": Color(1.0, 0.3, 0.95)}'),
 ("h_gull", "GULL SEA RESCUE", "sea rescue", (52, 15, 11, 1.0, 4600, 800, 6, 0.95, 1), (13.0, 3.4, 4.0, 6.4), (22, 6.2, 3.6), None,
  ["(0.92, 0.42, 0.12)", "(0.86, 0.87, 0.9)", "(0.9, 0.78, 0.16)", "(0.2, 0.3, 0.5)"],
  '{"cab": [-4.6, 2.4, 1.05, 1.05, 1.85], "n": 2.6, "nose": "glass", "boom": [7.6, 2.4, 0.26], "rotor": [3.55, -0.4, 4, 0.4], "gear": "floats", "x": ["winch", "light"], "mark": Color(1.0, 0.95, 0.7)}'),
 ("h_ultra", "MOSQUITO ULTRALIGHT", "ultralight", (34, 16, 9, 1.6, 320, 180, 1, 1.8, -3), (6.0, 1.6, 2.6, 3.4), (13, 4.0, 2.4), None,
  ["(0.9, 0.86, 0.2)", "(0.86, 0.87, 0.9)", "(0.7, 0.12, 0.1)", "(0.2, 0.4, 0.7)"],
  '{"cab": [-1.8, 0.3, 0.42, 0.58, 1.2], "n": 2.0, "nose": "bubble", "boom": [3.6, 1.35, 0.07], "rotor": [2.35, 0.0, 2, 0.2], "gear": "skids", "x": ["truss", "engine_open"]}'),
 ("h_naval", "TRIDENT SEA HUNTER", "naval", (58, 16, 12, 1.0, 7600, 1200, 4, 0.88, 2), (15.0, 3.0, 4.3, 7.0), (25, 6.8, 3.6), ("DOOR GUN", 14.0, 8.0, 600, 180.0),
  ["(0.42, 0.46, 0.5)", "(0.3, 0.34, 0.4)", "(0.56, 0.58, 0.6)", "(0.2, 0.24, 0.3)"],
  '{"cab": [-5.2, 3.4, 1.2, 1.15, 1.9], "n": 2.9, "nose": "glass", "boom": [8.6, 2.6, 0.3], "rotor": [3.75, -0.4, 4, 0.42], "gear": "wheels", "x": ["sonar", "doorgun", "winch"]}'),
]


def spec_line(h):
    i, nm, role, s, d, cam, w, pal, m = h
    mx, acc, climb, agile, mass, hp, seats, pitch, db = s
    ln, wid, hgt, rr = d
    wheel = 0.3 if '"wheels"' in m else 0.2
    return ('\t&"%s": {"cls": "heli", "craft": true, "procedural": "%s", "max": %.1f, "acc": %.1f, "brake": 22.0, "grip": 2.0, "hp": %.1f, "mass": %.1f, "seats": %d, "model": "air_%s", '
            '"len": %.1f, "wid": %.1f, "hgt": %.1f, "wheel": %.1f, "rotor_r": %.1f, "ceil": 900.0, "climb": %.1f, "agile": %.2f, "cam_d": %.1f, "cam_h": %.1f, "exit_side": %.1f, "aim_cone": 0.5},'
            % (i, i, mx, acc, hp, mass, seats, i[2:], ln, wid, hgt, wheel, rr, climb, agile, cam[0], cam[1], cam[2]))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out = ['class_name HeliRoster', 'extends RefCounted',
           '## WAVE 125 HELICOPTER ROSTER (plan line 125: "22+ kinds"): the three older helicopters (heli, gunship, hauler) and the twenty of this table, each with its own procedural',
           '## model (HeliModels), its own flight numbers (VehicleSpecs.SPECS: max, acc, climb, agile, mass, rotor_r), rotor sound pitch (AudioDirector.ENGINES) and icon (assets/icons/v_<kind>.png).',
           '## GENERATED by tools/gen_heli_roster.py (the source of the table): edit there and run it again.',
           '##   KINDS          every helicopter kind (23); NEW the twenty of wave 125',
           '##   DEFS[kind]     {name, role, m: model parameters (HeliModels)}',
           '##   spawn_points() the HELI LINE of EASTFIELD AIRPORT: one of every new kind parked east of the runway (VehicleSpawns.all_points appends them)', '']
    out.append('const NEW: Array[StringName] = [%s]' % ", ".join('&"%s"' % h[0] for h in H))
    out.append('const KINDS: Array[StringName] = [&"heli", &"gunship", &"hauler", %s]' % ", ".join('&"%s"' % h[0] for h in H))
    out.append('## The HELI LINE (airport LOCAL frame, see Airport.to_world): a row east of the runway, nose west (to the runway), LINE_STEP m apart.')
    out.append('const LINE_X := 1334.0')
    out.append('const LINE_Z0 := -930.0')
    out.append('const LINE_STEP := 38.0')
    out.append('static var line_on := true                 ## tests/test_helis_w125.gd HELIS_OLD=1 switches the line off (the wave 124 state: none of the new kinds can be found)')
    out.append('')
    out.append('const DEFS := {')
    for h in H:
        out.append('\t&"%s": {"name": "%s", "role": "%s", "m": %s},' % (h[0], h[1], h[2], h[8]))
    out.append('}')
    out.append('''

static func spawn_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not line_on:
		return out
	for i in NEW.size():
		var k: StringName = NEW[i]
		out.append({"id": StringName("hl_" + String(k)), "kind": k, "pos": Airport.to_world(Vector3(LINE_X, 0.0, LINE_Z0 + LINE_STEP * float(i))), "h": Airport.heading_world(PI * 0.5), "label": "HELI LINE: " + String(DEFS[k]["name"])})
	return out


static func is_heli(kind: StringName) -> bool:
	return KINDS.has(kind)


## The flight HUD badge (FlightHud.draw): the kind's icon (assets/icons/v_<kind>.png) and its name on a dark plate, centred on `bottom_mid`.
static func draw_badge(c: Control, font: Font, bottom_mid: Vector2, s: float, kind: StringName) -> void:
	var nm := VehicleSpecs.name_of(kind)
	var fs := int(18.0 * s)
	var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var iw := 64.0 * s
	var ih := 32.0 * s
	var w := iw + tw + 18.0 * s
	var r := Rect2(bottom_mid.x - w * 0.5, bottom_mid.y - ih - 6.0 * s, w, ih + 6.0 * s)
	c.draw_rect(r, Color(0.02, 0.04, 0.07, 0.6))
	var tex := ItemIcons.vehicle(kind)
	if tex != null:
		ItemIcons.draw_tex(c, tex, Rect2(r.position + Vector2(4.0 * s, 3.0 * s), Vector2(iw, ih)))
	c.draw_string(font, Vector2(r.position.x + iw + 10.0 * s, r.position.y + r.size.y * 0.5 + float(fs) * 0.36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.95, 1.0))
''')
    open(os.path.join(root, "scripts/vehicles/heli_roster.gd"), "w").write("\n".join(out))
    if "--lines" in sys.argv:
        print("# SPECS"); [print(spec_line(h)) for h in H]
        print("# PALETTES"); [print('\t&"%s": [%s],' % (h[0], ", ".join("Color" + c for c in h[7]))) for h in H]
        print("# NAMES"); print(", ".join('&"%s": "%s"' % (h[0], h[1]) for h in H))
        print("# KINDS"); print(", ".join('&"%s"' % h[0] for h in H))
        print("# WEAPONS")
        for h in H:
            if h[6]:
                n, rate, dmg, ammo, rng = h[6]
                col = "Color(0.4, 0.95, 1.0)" if n == "PHASE BOLT" else "Color(1.0, 0.82, 0.3)"
                print('\t&"%s": {"name": "%s", "rate": %.1f, "dmg": %.1f, "heat": 0.035, "cool": 0.3, "ammo": %d, "range": %.1f, "spread": 0.03, "color": %s},' % (h[0], n, rate, dmg, ammo, rng, col))
        print("# ENGINES"); print(", ".join('&"%s": [&"rotor", %.2f, %.1f]' % (h[0], h[3][7], h[3][8]) for h in H))


main()
