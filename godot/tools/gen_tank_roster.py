#!/usr/bin/env python3
"""WAVE 127 TANKS AND MILITARY GROUND VEHICLES: the one table of the 20 new military ground vehicle kinds (original names, own-made procedural models, TankModels).
Writes scripts/vehicles/tank_roster.gd (TankRoster: NEW, KINDS, DEFS, the places) and the generated blocks between the "w127-tanks BEGIN / END" markers of
scripts/vehicles/vehicle_specs.gd (SPECS, PALETTES, NAMES, WEAPONS, ROSTER, TANK_KINDS) and scripts/common/audio_director.gd (ENGINES).
Every kind drives on the tracked physics of VehicleCraft._tank (cls "tank"); "wheeled" kinds turn with the speed (no pivot on the spot), "hover" floats.
Run: python3 tools/gen_tank_roster.py"""
import os, re, sys

# id, name, role, run (track / wheel / half / hover / legs),
# drive (max m/s, acc, brake, steer, mass kg, hp, plate = armour, mm of rolled steel at the front), body (len, wid, hgt, wheel r, seats),
# gun_max (rad), weapon class (WEAPON below), engine (variant, pitch, dB), palette, place, model params (GDScript literal; TankModels)
T = [
 ("t_heavy", "BASTION HEAVY TANK", "heavy tank", "track", (9.5, 4.0, 18.0, 0.62, 68000, 3200, 600), (8.6, 3.8, 3.0, 0.5, 1), 0.45, "heavy_cannon", ("heavy", 0.42, 4.0),
  ["(0.27, 0.3, 0.22)", "(0.44, 0.4, 0.3)", "(0.3, 0.31, 0.33)"], "base",
  '{"run": "track", "tt": 1.0, "tw": 0.72, "hull": "tank", "top": 1.65, "slope": 1.0, "x": ["skirts", "smoke", "stow"], "tur": ["wedge", 2.8, 0.95, 3.6], "ty": 1.65, "tz": 0.4, "tr": [0.45, -1.9], "gun": ["barrel", 5.0, 0.11, 0.15, true]}'),
 ("t_destroyer", "RAPIER TANK DESTROYER", "tank destroyer", "track", (15.0, 6.5, 22.0, 0.85, 32000, 1500, 120), (7.4, 3.2, 2.6, 0.5, 2), 0.35, "long_cannon", ("heavy", 0.6, 3.0),
  ["(0.36, 0.36, 0.26)", "(0.3, 0.33, 0.25)", "(0.42, 0.38, 0.3)"], "base",
  '{"run": "track", "tt": 0.85, "tw": 0.6, "hull": "tank", "top": 1.4, "slope": 1.25, "x": ["skirts"], "tur": ["open", 1.2, 0.8], "ty": 1.4, "tz": 0.5, "tr": [0.4, -1.2], "gun": ["barrel", 5.4, 0.09, 0.12, true]}'),
 ("t_spg", "THUNDER SELF-PROPELLED GUN", "self-propelled gun", "track", (12.0, 5.0, 20.0, 0.7, 38000, 1400, 60), (8.0, 3.4, 3.2, 0.5, 3), 1.1, "howitzer", ("heavy", 0.48, 3.0),
  ["(0.38, 0.37, 0.28)", "(0.3, 0.33, 0.25)", "(0.45, 0.42, 0.33)"], "base",
  '{"run": "track", "tt": 0.9, "tw": 0.64, "hull": "tank", "top": 1.5, "slope": 0.9, "x": ["spade", "stow"], "tur": ["box", 3.0, 1.35, 3.6], "ty": 1.5, "tz": 0.9, "tr": [0.7, -1.8], "gun": ["barrel", 6.2, 0.1, 0.15, true]}'),
 ("t_rocket", "STORMCHORUS ROCKET TRUCK", "rocket artillery", "wheel", (20.0, 7.0, 24.0, 0.9, 18000, 900, 15), (8.4, 2.7, 3.2, 0.62, 3), 0.95, "rockets", ("heavy", 0.78, 2.0),
  ["(0.32, 0.35, 0.27)", "(0.46, 0.42, 0.32)", "(0.3, 0.32, 0.34)"], "base",
  '{"run": "wheel", "axles": [-0.33, 0.08, 0.3], "steer_n": 1, "wr": 0.62, "hull": "truck", "top": 2.9, "cab": 2.4, "x": ["stab"], "tur": ["rack"], "ty": 1.95, "tz": 1.6, "tr": [0.75, 0.6], "gun": ["rack", 2.2, 1.0, 3.6, 3, 5]}'),
 ("t_apc8", "PANGOLIN 8X8 CARRIER", "wheeled carrier", "wheel", (26.0, 9.0, 26.0, 1.0, 22000, 1400, 40), (7.8, 2.9, 2.9, 0.58, 8), 0.7, "hmg", ("heavy", 0.86, 2.0),
  ["(0.34, 0.38, 0.3)", "(0.5, 0.46, 0.36)", "(0.24, 0.27, 0.3)"], "checkpoint_desert",
  '{"run": "wheel", "axles": [-0.36, -0.13, 0.13, 0.36], "steer_n": 2, "wr": 0.58, "hull": "wheeled", "top": 2.3, "x": ["smoke", "lights"], "tur": ["rws"], "ty": 2.3, "tz": -0.6, "tr": [0.42, -0.2], "gun": ["mg", 1.2]}'),
 ("t_apct", "MOLE TRACKED CARRIER", "tracked carrier", "track", (19.0, 8.0, 24.0, 1.05, 12500, 1100, 35), (5.8, 2.8, 2.6, 0.45, 8), 0.8, "hmg", ("heavy", 0.8, 2.0),
  ["(0.4, 0.4, 0.3)", "(0.3, 0.34, 0.27)", "(0.48, 0.44, 0.34)"], "depot",
  '{"run": "track", "tt": 0.85, "tw": 0.55, "hull": "box", "top": 2.0, "x": ["lights"], "tur": ["cupola", 0.45], "ty": 2.0, "tz": -0.9, "tr": [0.25, -0.35], "gun": ["mg", 1.1]}'),
 ("t_ifv", "WARDOG FIGHTING VEHICLE", "infantry fighting vehicle", "track", (18.0, 7.5, 24.0, 1.0, 27000, 1700, 90), (6.9, 3.3, 3.0, 0.5, 7), 0.75, "autocannon", ("heavy", 0.7, 2.0),
  ["(0.3, 0.34, 0.27)", "(0.47, 0.43, 0.32)", "(0.26, 0.28, 0.3)"], "checkpoint_forest",
  '{"run": "track", "tt": 0.9, "tw": 0.6, "hull": "box", "top": 1.9, "x": ["smoke", "atgm"], "tur": ["wedge", 2.0, 0.75, 2.2], "ty": 1.9, "tz": -0.3, "tr": [0.38, -1.1], "gun": ["barrel", 2.4, 0.05, 0.07, false]}'),
 ("t_scout", "WHIPPET SCOUT CAR", "scout car", "wheel", (30.0, 12.0, 28.0, 1.3, 7500, 600, 20), (5.0, 2.4, 2.3, 0.5, 3), 0.7, "light_auto", ("heavy", 1.15, 0.0),
  ["(0.42, 0.42, 0.32)", "(0.33, 0.37, 0.28)", "(0.52, 0.47, 0.36)"], "checkpoint_desert",
  '{"run": "wheel", "axles": [-0.3, 0.3], "steer_n": 1, "wr": 0.5, "hull": "wheeled", "top": 1.75, "x": ["lights"], "tur": ["round", 0.65, 0.45, 0.3], "ty": 1.75, "tz": 0.1, "tr": [0.22, -0.55], "gun": ["barrel", 1.4, 0.04, 0.05, false]}'),
 ("t_mrap", "BULWARK MRAP", "mine-resistant truck", "wheel", (27.0, 9.0, 26.0, 1.05, 14000, 1000, 30), (6.4, 2.6, 3.4, 0.62, 6), 0.7, "hmg", ("heavy", 1.0, 1.0),
  ["(0.5, 0.46, 0.36)", "(0.36, 0.38, 0.32)", "(0.3, 0.32, 0.34)"], "checkpoint_pass",
  '{"run": "wheel", "axles": [-0.3, 0.3], "steer_n": 1, "wr": 0.62, "hull": "mrap", "top": 2.8, "tur": ["rws"], "ty": 2.8, "tz": 0.6, "tr": [0.42, -0.2], "gun": ["mg", 1.0]}'),
 ("t_jeep", "RANGER ARMOURED JEEP", "armoured jeep", "wheel", (32.0, 13.0, 28.0, 1.35, 3800, 450, 10), (4.8, 2.2, 2.4, 0.45, 4), 0.7, "mg", ("heavy", 1.3, -1.0),
  ["(0.36, 0.39, 0.3)", "(0.52, 0.48, 0.38)", "(0.26, 0.28, 0.24)"], "checkpoint_pass",
  '{"run": "wheel", "axles": [-0.31, 0.31], "steer_n": 1, "wr": 0.45, "hull": "jeep", "top": 1.5, "tur": ["ring"], "ty": 1.55, "tz": 0.3, "tr": [0.45, -0.1], "gun": ["mg", 1.0]}'),
 ("t_truck", "OXEN CARGO TRUCK", "military truck", "wheel", (24.0, 7.0, 24.0, 0.95, 12000, 700, 5), (8.2, 2.6, 3.3, 0.6, 12), 0.7, "mg", ("heavy", 0.95, 1.0),
  ["(0.33, 0.37, 0.28)", "(0.46, 0.43, 0.33)", "(0.3, 0.3, 0.27)"], "depot",
  '{"run": "wheel", "axles": [-0.34, 0.14, 0.32], "steer_n": 1, "wr": 0.6, "hull": "truck", "top": 2.7, "cab": 2.3, "x": ["canvas"], "tur": ["ring"], "ty": 2.75, "tz": -2.85, "tr": [0.45, -0.1], "gun": ["mg", 1.0]}'),
 ("t_fuel", "CAMEL FUEL TRUCK", "fuel truck", "wheel", (22.0, 6.5, 22.0, 0.9, 16000, 650, 5), (8.4, 2.6, 3.0, 0.6, 2), 0.7, "mg", ("heavy", 0.9, 1.0),
  ["(0.4, 0.42, 0.33)", "(0.3, 0.34, 0.26)", "(0.5, 0.47, 0.36)"], "depot",
  '{"run": "wheel", "axles": [-0.34, 0.14, 0.32], "steer_n": 1, "wr": 0.6, "hull": "truck", "top": 2.7, "cab": 2.3, "x": ["fuel"], "tur": ["ring"], "ty": 2.75, "tz": -2.95, "tr": [0.45, -0.1], "gun": ["mg", 0.9]}'),
 ("t_recovery", "HAULMASTER RECOVERY VEHICLE", "recovery vehicle", "track", (13.0, 5.5, 20.0, 0.75, 50000, 2200, 200), (7.8, 3.5, 3.0, 0.5, 3), 0.9, "none", ("heavy", 0.5, 3.0),
  ["(0.42, 0.4, 0.3)", "(0.33, 0.35, 0.27)", "(0.5, 0.46, 0.34)"], "depot",
  '{"run": "track", "tt": 0.95, "tw": 0.68, "hull": "box", "top": 1.9, "x": ["dozer", "stow"], "tur": ["crane"], "ty": 1.9, "tz": 0.6, "tr": [0.6, 0.0], "gun": ["boom", 4.2]}'),
 ("t_bridge", "SPANNER BRIDGE LAYER", "bridge layer", "track", (12.0, 5.0, 20.0, 0.7, 46000, 1900, 150), (9.0, 3.6, 3.0, 0.5, 2), 0.6, "mg", ("heavy", 0.52, 3.0),
  ["(0.35, 0.37, 0.28)", "(0.45, 0.42, 0.32)", "(0.28, 0.3, 0.3)"], "depot",
  '{"run": "track", "tt": 0.9, "tw": 0.68, "hull": "tank", "top": 1.5, "slope": 0.9, "x": ["bridge"], "tur": ["cupola", 0.42], "ty": 2.24, "tz": -3.4, "tr": [0.25, -0.35], "gun": ["mg", 0.9]}'),
 ("t_mine", "THRESHER MINE CLEARER", "mine clearer", "track", (11.0, 4.8, 20.0, 0.75, 44000, 2000, 180), (7.6, 3.5, 2.8, 0.5, 2), 0.6, "mg", ("heavy", 0.55, 3.0),
  ["(0.5, 0.44, 0.3)", "(0.36, 0.37, 0.28)", "(0.3, 0.32, 0.3)"], "depot",
  '{"run": "track", "tt": 0.9, "tw": 0.68, "hull": "tank", "top": 1.5, "slope": 0.8, "x": ["flail", "skirts"], "tur": ["cupola", 0.5], "ty": 1.5, "tz": 0.6, "tr": [0.25, -0.4], "gun": ["mg", 1.0]}'),
 ("t_amphib", "MUDSKIPPER AMPHIBIOUS CARRIER", "amphibious carrier", "track", (20.0, 8.0, 24.0, 1.0, 26000, 1300, 40), (8.0, 3.3, 3.0, 0.45, 10), 0.8, "light_auto", ("heavy", 0.74, 2.0),
  ["(0.32, 0.4, 0.36)", "(0.42, 0.44, 0.38)", "(0.26, 0.3, 0.32)"], "depot",
  '{"run": "track", "tt": 0.8, "tw": 0.55, "hull": "boat", "top": 2.2, "x": ["lights"], "tur": ["round", 0.75, 0.5, 0.35], "ty": 2.2, "tz": -0.8, "tr": [0.25, -0.6], "gun": ["barrel", 1.3, 0.04, 0.05, false]}'),
 ("t_aa8", "SKYGUARD MISSILE CARRIER", "mobile anti-air", "wheel", (24.0, 8.0, 24.0, 0.95, 20000, 900, 20), (8.0, 2.8, 3.4, 0.6, 3), 1.3, "aa_missiles", ("heavy", 0.82, 2.0),
  ["(0.3, 0.33, 0.28)", "(0.44, 0.44, 0.36)", "(0.38, 0.4, 0.42)"], "base",
  '{"run": "wheel", "axles": [-0.35, -0.05, 0.3], "steer_n": 1, "wr": 0.6, "hull": "wheeled", "top": 2.1, "x": ["lights"], "tur": ["aa"], "ty": 2.1, "tz": 1.0, "tr": [0.4, -0.1], "gun": ["pods", 4]}'),
 ("t_hover", "PHANTOM HOVER TANK", "sci-fi hover tank", "hover", (26.0, 11.0, 26.0, 1.25, 20000, 1300, 80), (7.2, 3.4, 2.6, 0.4, 2), 0.6, "rail", ("hover", 0.62, 2.0),
  ["(0.2, 0.22, 0.27)", "(0.36, 0.38, 0.43)", "(0.3, 0.26, 0.4)"], "base",
  '{"run": "hover", "lift": 0.55, "hull": "hover", "top": 1.3, "tur": ["sci", 1.0, 0.6], "ty": 1.3, "tz": 0.4, "tr": [0.3, -1.0], "gun": ["rail", 3.6], "mark": Color(0.25, 0.95, 1.0)}'),
 ("t_walker", "QUANTUM STRIDER", "quantum walker", "legs", (9.0, 5.0, 20.0, 1.1, 18000, 1500, 70), (5.4, 3.4, 4.6, 0.3, 1), 0.7, "phase", ("hover", 0.45, 3.0),
  ["(0.42, 0.44, 0.5)", "(0.24, 0.24, 0.3)", "(0.36, 0.3, 0.6)"], "base",
  '{"run": "legs", "hip": 2.4, "hull": "walker", "tur": ["sci", 0.9, 0.55], "ty": 3.5, "tz": 0.2, "tr": [0.3, -0.9], "gun": ["rail", 2.8], "mark": Color(1.0, 0.3, 0.95)}'),
 ("t_halftrack", "MULE HALF-TRACK", "half-track", "half", (21.0, 8.0, 24.0, 1.0, 9000, 700, 15), (6.2, 2.3, 2.6, 0.5, 8), 0.7, "hmg", ("heavy", 0.92, 1.0),
  ["(0.4, 0.4, 0.3)", "(0.32, 0.35, 0.27)", "(0.5, 0.45, 0.34)"], "checkpoint_forest",
  '{"run": "half", "axles": [-0.34], "steer_n": 1, "wr": 0.5, "tt": 0.75, "tw": 0.4, "hull": "half", "top": 1.75, "tur": ["ring"], "ty": 1.8, "tz": 0.5, "tr": [0.45, -0.1], "gun": ["mg", 1.1]}'),
]

# weapon classes (VehicleSpecs.WEAPONS rows; w127-arms adds the second arms by the main gun: indirect -> artillery kit, flak -> anti-air kit, dmg >= 50 -> tank kit, else carrier kit)
WEAPON = {
 "heavy_cannon": '{"name": "HEAVY CANNON", "rate": 0.55, "dmg": 130.0, "heat": 0.5, "cool": 0.28, "ammo": 30, "range": 240.0, "spread": 0.0, "blast": 8.5, "color": Color(1.0, 0.55, 0.18)}',
 "long_cannon": '{"name": "LONG CANNON", "rate": 0.7, "dmg": 115.0, "heat": 0.45, "cool": 0.28, "ammo": 34, "range": 260.0, "spread": 0.0, "blast": 6.0, "color": Color(1.0, 0.58, 0.2)}',
 "howitzer": '{"name": "HOWITZER", "rate": 0.25, "dmg": 200.0, "heat": 0.9, "cool": 0.3, "ammo": 20, "range": 560.0, "spread": 0.0, "blast": 12.0, "indirect": true, "delay": 1.5, "color": Color(1.0, 0.5, 0.15)}',
 "rockets": '{"name": "ROCKET BATTERY", "rate": 0.6, "dmg": 150.0, "heat": 0.6, "cool": 0.3, "ammo": 15, "range": 480.0, "spread": 0.0, "blast": 9.0, "indirect": true, "delay": 1.1, "color": Color(1.0, 0.6, 0.2)}',
 "autocannon": '{"name": "AUTOCANNON", "rate": 6.0, "dmg": 18.0, "heat": 0.08, "cool": 0.3, "ammo": 300, "range": 180.0, "spread": 0.015, "color": Color(1.0, 0.82, 0.35)}',
 "light_auto": '{"name": "LIGHT AUTOCANNON", "rate": 5.0, "dmg": 14.0, "heat": 0.07, "cool": 0.3, "ammo": 260, "range": 160.0, "spread": 0.018, "color": Color(1.0, 0.82, 0.35)}',
 "hmg": '{"name": "HEAVY MACHINE GUN", "rate": 10.0, "dmg": 9.0, "heat": 0.04, "cool": 0.3, "ammo": 600, "range": 150.0, "spread": 0.02, "color": Color(1.0, 0.85, 0.4)}',
 "mg": '{"name": "MACHINE GUN", "rate": 11.0, "dmg": 7.0, "heat": 0.035, "cool": 0.3, "ammo": 500, "range": 130.0, "spread": 0.022, "color": Color(1.0, 0.85, 0.4)}',
 "aa_missiles": '{"name": "AIR DEFENCE MISSILES", "rate": 1.2, "dmg": 70.0, "heat": 0.3, "cool": 0.3, "ammo": 16, "range": 400.0, "spread": 0.0, "blast": 4.0, "flak": true, "color": Color(1.0, 0.9, 0.5)}',
 "rail": '{"name": "RAIL CANNON", "rate": 1.0, "dmg": 110.0, "heat": 0.4, "cool": 0.32, "ammo": 40, "range": 260.0, "spread": 0.0, "blast": 4.0, "color": Color(0.3, 0.95, 1.0)}',
 "phase": '{"name": "PHASE CANNON", "rate": 1.6, "dmg": 70.0, "heat": 0.3, "cool": 0.32, "ammo": 60, "range": 220.0, "spread": 0.0, "blast": 3.5, "color": Color(1.0, 0.35, 0.95)}',
}

# THE PLACES (world x, z unless said otherwise; h = heading, 0 = nose north / -z, PI/2 = nose west / -x):
#  base   ARMY BASE: the east strip of EASTFIELD's ARMY AIRBASE (airport LOCAL frame: x 1362, z -690 .. -609, between the first taxi lane and ARMY SHELTER 2), nose west to the runway
#  depot  VEHICLE DEPOT: the free east headland of the HARBOUR apron (world z 1575, x 230 .. 314, behind the tank farm), nose north to the quay road
#  checkpoint_*  three road CHECKPOINTS on the outskirts highways, one vehicle on each shoulder (the flat road bench), parallel to the road
BASE_X, BASE_Z0, BASE_DZ = 1362.0, -690.0, 13.5
DEPOT_X0, DEPOT_DX, DEPOT_Z = 230.0, 14.0, 1575.0
CHECKPOINTS = [("checkpoint_pass", "PASS ROAD", 420.0, "PASS ROAD CHECKPOINT"), ("checkpoint_desert", "DESERT ROAD", 380.0, "DESERT ROAD CHECKPOINT"),
               ("checkpoint_forest", "FOREST ROAD", 420.0, "FOREST ROAD CHECKPOINT")]


def info(t):
    i, nm, role, run, dr, bd, gmax, wcls, en, pal, place, m = t
    return dict(id=i, name=nm, role=role, run=run, max=dr[0], acc=dr[1], brake=dr[2], steer=dr[3], mass=dr[4], hp=dr[5], plate=dr[6], len=bd[0], wid=bd[1], hgt=bd[2],
                wheel=bd[3], seats=bd[4], gmax=gmax, wcls=wcls, en=en, pal=pal, place=place, m=m)


def num(m, key, default):
    r = re.search(r'"%s": (-?[0-9.]+)' % key, m)
    return float(r.group(1)) if r else default


def arr(m, key):
    r = re.search(r'"%s": \[([^\]]*)\]' % key, m)
    return [x.strip().strip('"') for x in r.group(1).split(",")] if r else []


def spec_line(t):
    d = info(t)
    m = d["m"]
    ty, tz = num(m, "ty", 1.5), num(m, "tz", 0.0)
    tr = [float(x) for x in arr(m, "tr")] or [0.3, -0.8]
    g = arr(m, "gun")
    blen = {"barrel": lambda: float(g[1]), "mg": lambda: float(g[1]), "rail": lambda: float(g[1]), "boom": lambda: float(g[1]), "rack": lambda: float(g[3]) * 0.85,
            "pods": lambda: 1.0}.get(g[0], lambda: 0.5)()
    gun_len = max(blen - tr[1] - tz, 0.8)
    lift = num(m, "lift", 0.0)
    gun_h = (ty + tr[0] + lift) / d["hgt"]
    extra = ""
    if d["run"] in ("wheel", "half"):
        extra += ', "wheeled": true'
    if d["run"] == "hover":
        extra += ', "hover": true'
    if d["run"] == "legs":
        extra += ', "legs": true'
    cam_d = max(13.0, d["len"] * 1.7 + 2.0)
    cam_h = max(4.6, d["hgt"] * 1.6 + 0.8)
    return ('\t&"%s": {"cls": "tank", "craft": true, "procedural": "%s", "max": %.1f, "acc": %.1f, "brake": %.1f, "grip": 8.0, "hp": %.1f, "mass": %.1f, "seats": %d, "model": "mv_%s", '
            '"len": %.1f, "wid": %.1f, "hgt": %.1f, "wheel": %.2f, "turret": "Turret", "steer": %.2f, "plate": %d%s, "cam_d": %.1f, "cam_h": %.1f, "exit_side": %.1f, '
            '"gun_len": %.2f, "gun_h": %.3f, "gun_max": %.2f%s},'
            % (d["id"], d["id"], d["max"], d["acc"], d["brake"], d["hp"], d["mass"], d["seats"], d["id"][2:], d["len"], d["wid"], d["hgt"], d["wheel"], d["steer"], d["plate"],
               extra, cam_d, cam_h, d["wid"] * 0.5 + 1.4, gun_len, gun_h, d["gmax"], ', "arms2": true' if d["wcls"] in ("heavy_cannon", "long_cannon", "autocannon", "aa_missiles") else ""))


def inject(path, anchor_fn, block_lines, tag):
    src = open(path).read().split("\n")
    b = "\t# w127-tanks BEGIN %s (generated by tools/gen_tank_roster.py)" % tag
    e = "\t# w127-tanks END %s" % tag
    if b in src:
        i0 = src.index(b)
        i1 = src.index(e)
        src[i0:i1 + 1] = [b] + block_lines + [e]
    else:
        at = anchor_fn(src)
        src[at:at] = [b] + block_lines + [e]
    open(path, "w").write("\n".join(src))


def anchor_after(prefix):
    def f(src):
        for k, l in enumerate(src):
            if l.startswith(prefix):
                j = k
                while not src[j].rstrip().endswith("},") and not src[j].rstrip().endswith("],"):
                    j += 1
                return j + 1
        sys.exit("anchor not found: " + prefix)
    return f


def anchor_before(prefix):
    def f(src):
        for k, l in enumerate(src):
            if l.startswith(prefix):
                return k
        sys.exit("anchor not found: " + prefix)
    return f


def anchor_dict_end(head):
    def f(src):
        k = next(k for k, l in enumerate(src) if l.startswith(head))
        while src[k] != "}":
            k += 1
        return k
    return f


def add_to_array(path, head, ids):
    src = open(path).read().split("\n")
    k = next(k for k, l in enumerate(src) if l.startswith(head))
    j = k
    while not src[j].rstrip().endswith("]"):
        j += 1
    text = "\n".join(src[k:j + 1])
    text = re.sub(r', &"t_[a-z0-9_]+"', "", text)
    text = text[:text.rstrip().rfind("]")] + ", " + ", ".join('&"%s"' % i for i in ids) + "]"
    src[k:j + 1] = text.split("\n")
    open(path, "w").write("\n".join(src))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    D = [info(t) for t in T]
    ids = [d["id"] for d in D]
    if len(set(ids)) != len(ids):
        sys.exit("duplicate id")
    out = ['class_name TankRoster', 'extends RefCounted',
           '## WAVE 127 TANKS AND MILITARY GROUND VEHICLES (plan line 127): the five older armoured kinds (tank, ltank, apc, artillery, aatank) and the 20 of this table, each with its own',
           '## procedural model (TankModels: tracks / tyres / legs that move, a turret that turns), its own driving numbers (VehicleSpecs.SPECS: max, acc, steer, mass, hp, plate = front armour),',
           '## engine sound (AudioDirector.ENGINES), main gun (VehicleSpecs.WEAPONS; w127-arms adds the second arms by class) and icon (assets/icons/v_<kind>.png).',
           '## GENERATED by tools/gen_tank_roster.py (the source of the table): edit there and run it again.',
           '##   KINDS          every military ground kind (25); NEW the 20 of wave 127',
           '##   DEFS[kind]     {name, role, run (track / wheel / half / hover / legs), wclass (main gun class), place, m: model parameters (TankModels)}',
           '##   spawn_points() where they wait (VehicleSpawns.all_points appends them): ARMY BASE (EASTFIELD ARMY AIRBASE east strip), VEHICLE DEPOT (harbour east headland) and three',
           '##                  road CHECKPOINTS on the outskirts highways: FIXED vehicles (ArmourSites.is_fixed), outside the live car cap, standing only while the hero is near', '']
    out.append('const NEW: Array[StringName] = [%s]' % ", ".join('&"%s"' % i for i in ids))
    out.append('const KINDS: Array[StringName] = [&"tank", &"ltank", &"apc", &"artillery", &"aatank", %s]' % ", ".join('&"%s"' % i for i in ids))
    out.append('static var on := OS.get_environment("W127_TANKS_OLD") != "1"      ## false: the wave 126 state (no new kind stands anywhere), for the old-behaviour run of tests/test_tanks_w127.gd')
    out.append('')
    out.append('const DEFS := {')
    for d in D:
        out.append('\t&"%s": {"name": "%s", "role": "%s", "run": &"%s", "wclass": &"%s", "place": &"%s", "m": %s},' % (d["id"], d["name"], d["role"], d["run"], d["wcls"], d["place"], d["m"]))
    out.append('}')
    out.append('## The places: id -> {name, kind of place, kinds (in order)}. ARMY BASE in the airport LOCAL frame (Airport.to_world), the depot in world metres, the checkpoints on a road at a distance.')
    out.append('const BASE_LOCAL := Vector3(%.1f, 0.0, %.1f)' % (BASE_X, BASE_Z0))
    out.append('const BASE_DZ := %.1f' % BASE_DZ)
    out.append('const DEPOT := Vector3(%.1f, 0.0, %.1f)' % (DEPOT_X0, DEPOT_Z))
    out.append('const DEPOT_DX := %.1f' % DEPOT_DX)
    out.append('const CHECKPOINTS: Array[Dictionary] = [')
    for cid, road, at, label in CHECKPOINTS:
        out.append('\t{"id": &"%s", "road": "%s", "at": %.1f, "name": "%s"},' % (cid, road, at, label))
    out.append(']')
    out.append(r'''

static var _points: Array[Dictionary] = []
static var _sites: Array[Dictionary] = []


## The kinds that wait at a place, in table order.
static func kinds_at(place: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in NEW:
		if DEFS[k]["place"] == place:
			out.append(k)
	return out


## Where every new kind waits: [{id ("mv_<kind>"), kind, pos, h, label}]. The checkpoints need the outskirts roads (TerrainRoads): until they exist the list holds the base and the depot only
## and is not cached.
static func spawn_points() -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if not on:
		return none
	if not _points.is_empty():
		return _points
	var out: Array[Dictionary] = []
	var sites: Array[Dictionary] = []
	var base := kinds_at(&"base")
	for i in base.size():
		var lp := BASE_LOCAL + Vector3(0.0, 0.0, BASE_DZ * float(i))
		out.append({"id": StringName("mv_" + String(base[i])), "kind": base[i], "pos": Airport.to_world(lp), "h": Airport.heading_world(PI * 0.5), "label": "ARMY BASE: " + String(DEFS[base[i]]["name"])})
	sites.append({"id": &"army_base", "name": "ARMY BASE", "pos": Airport.to_world(BASE_LOCAL + Vector3(0.0, 0.0, BASE_DZ * float(base.size() - 1) * 0.5))})
	var dep := kinds_at(&"depot")
	for i in dep.size():
		var p := DEPOT + Vector3(DEPOT_DX * float(i), Harbour.QUAY_Y, 0.0)
		out.append({"id": StringName("mv_" + String(dep[i])), "kind": dep[i], "pos": p, "h": 0.0, "label": "VEHICLE DEPOT: " + String(DEFS[dep[i]]["name"])})
	sites.append({"id": &"vehicle_depot", "name": "VEHICLE DEPOT", "pos": DEPOT + Vector3(DEPOT_DX * float(dep.size() - 1) * 0.5, Harbour.QUAY_Y, 0.0)})
	var roads_ok := TerrainRoads.built
	if roads_ok:
		for cp: Dictionary in CHECKPOINTS:
			var at := road_spot(String(cp["road"]), float(cp["at"]))
			if at.is_empty():
				continue
			var ks := kinds_at(cp["id"])
			for i in mini(ks.size(), 2):
				var side := -1.0 if i == 0 else 1.0
				var c: Vector2 = at["pos"]
				var nrm: Vector2 = at["nrm"]
				var off := float(at["w"]) * 0.5 + float(VehicleSpecs.SPECS[ks[i]]["wid"]) * 0.5 + 1.6
				var p2: Vector2 = c + nrm * side * off + (at["dir"] as Vector2) * (float(i) * 6.0 - 3.0)
				var dd: Vector2 = at["dir"] if i == 0 else -(at["dir"] as Vector2)
				p2 = clear_spot(p2, at["dir"], dd, float(VehicleSpecs.SPECS[ks[i]]["len"]), float(VehicleSpecs.SPECS[ks[i]]["wid"]))     # w127-critic: not nose to a tree
				var y := TerrainHeight.height_at(p2.x, p2.y)
				var d: Vector2 = at["dir"] if i == 0 else -(at["dir"] as Vector2)              # one faces out of the city, the other back in
				out.append({"id": StringName("mv_" + String(ks[i])), "kind": ks[i], "pos": Vector3(p2.x, y, p2.y), "h": atan2(-d.x, -d.y), "label": String(cp["name"]) + ": " + String(DEFS[ks[i]]["name"])})
			var c2: Vector2 = at["pos"]
			sites.append({"id": cp["id"], "name": cp["name"], "pos": Vector3(c2.x, TerrainHeight.height_at(c2.x, c2.y), c2.y)})
		_points = out
		_sites = sites
	return out


## The places for the map (a tank glyph each): [{id, name, pos}].
static func sites() -> Array[Dictionary]:
	if _sites.is_empty():
		spawn_points()
	return _sites


## A flat spot on the road `road_name` `at` metres from its start (not on a bridge): {pos, dir, nrm, w}; {} when the road is missing.
static func road_spot(road_name: String, at: float) -> Dictionary:
	for r: Dictionary in TerrainRoads.roads():
		if String(r["name"]) != road_name:
			continue
		var pts: PackedVector2Array = r["pos"]
		var acc := 0.0
		for i in range(1, pts.size() - 1):
			acc += pts[i].distance_to(pts[i - 1])
			if acc < at:
				continue
			var dir := (pts[i + 1] - pts[i - 1]).normalized()
			if TerrainRoads.in_span(pts[i].x, pts[i].y):
				continue
			return {"pos": pts[i], "dir": dir, "nrm": Vector2(-dir.y, dir.x), "w": float(r["w"])}
	return {}


## A point id of spawn_points(): a FIXED vehicle (ArmourSites.is_fixed), outside the live car cap, kept while the hero is near.
## w127-critic: a parking spot on the shoulder at `p`, moved along the road (`road_dir`) until no tree trunk or big rock stands in the parked box or within NOSE_CLEAR m ahead of the
## nose (`face`): the FOREST ROAD half-track stood nose against a trunk 4.8 m ahead and could not be driven out forwards. VegScatter's tree cells are pure data (no scene needed).
const NOSE_CLEAR := 16.0
static var clear_on := OS.get_environment("W127C_OLD") != "1"

static func clear_spot(p: Vector2, road_dir: Vector2, face: Vector2, ln: float, wd: float) -> Vector2:
	if not clear_on:
		return p
	for shift: float in [0.0, 10.0, -10.0, 20.0, -20.0, 30.0, -30.0, 40.0, -40.0]:
		var q := p + road_dir * shift
		if not _blocked(q, face, ln, wd):
			return q
	return p


static func _blocked(p: Vector2, face: Vector2, ln: float, wd: float) -> bool:
	var nrm := Vector2(-face.y, face.x)
	var reach := ln * 0.5 + NOSE_CLEAR + 4.0
	for layer: int in [VegScatter.T_TREES, VegScatter.T_LINES, VegScatter.T_ROCKS]:
		for ci in range(int(floor((p.x - reach) / VegScatter.CELL)), int(floor((p.x + reach) / VegScatter.CELL)) + 1):
			for cj in range(int(floor((p.y - reach) / VegScatter.CELL)), int(floor((p.y + reach) / VegScatter.CELL)) + 1):
				var arr := VegScatter.cell(layer, ci, cj)
				for o in range(0, arr.size(), VegScatter.STRIDE):
					var sp := int(arr[o + 5])
					var sc := arr[o + 4]
					var rock := sp == VegScatter.ROCK
					if not (VegetationWorld.TREE_NAMES.has(sp) or (rock and sc > 0.9)):
						continue
					var q := Vector2(arr[o], arr[o + 2]) - p
					var along := q.dot(face)
					var lat := absf(q.dot(nrm))
					var rad := (1.15 * sc if rock else 0.6)
					if along > -ln * 0.5 - 2.0 and along < ln * 0.5 + NOSE_CLEAR and lat < wd * 0.5 + 1.0 + rad:
						return true
	return false


static func owns(id: StringName) -> bool:
	return on and String(id).begins_with("mv_t_")


## The places as map markers (kind armour, a tank glyph, never fogged).
static func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not on:
		return out
	for s: Dictionary in sites():
		out.append({"kind": &"armour", "pos": s["pos"], "fog": false, "label": String(s["name"]), "glyph": &"tank"})
	return out


static func is_military(kind: StringName) -> bool:
	return KINDS.has(kind)
''')
    open(os.path.join(root, "scripts/vehicles/tank_roster.gd"), "w").write("\n".join(out))
    vs = os.path.join(root, "scripts/vehicles/vehicle_specs.gd")
    inject(vs, anchor_after('\t&"aatank": {'), ["\t# wave 127 TANKS AND MILITARY GROUND VEHICLES (TankRoster): 20 more kinds on the tracked physics, procedural models (TankModels)."] + [spec_line(t) for t in T], "SPECS")
    inject(vs, anchor_after('\t&"aatank": [Color'), ['\t&"%s": [%s],' % (d["id"], ", ".join("Color" + c for c in d["pal"])) for d in D], "PALETTES")
    inject(vs, anchor_before('\t&"garbage": "GARBAGE TRUCK"'), ["\t" + ", ".join('&"%s": "%s"' % (d["id"], d["name"]) for d in D) + ","], "NAMES")
    inject(vs, anchor_dict_end("const WEAPONS := {"), ['\t&"%s": %s,' % (d["id"], WEAPON[d["wcls"]]) for d in D if d["wcls"] != "none"], "WEAPONS")
    add_to_array(vs, "const ROSTER: Array[StringName]", ids)
    add_to_array(vs, "const TANK_KINDS: Array[StringName]", ids)
    ad = os.path.join(root, "scripts/common/audio_director.gd")
    inject(ad, anchor_before('\t&"quad": [&"bike"'), ["\t" + ", ".join('&"%s": [&"%s", %.2f, %.1f]' % (d["id"], d["en"][0], d["en"][1], d["en"][2]) for d in D) + ","], "ENGINES")
    for d in D:
        print("%-12s %-30s %-6s max %4.1f mass %6d plate %3d" % (d["id"], d["name"], d["run"], d["max"], d["mass"], d["plate"]))


main()
