#!/usr/bin/env python3
"""WAVE 126 AEROPLANE ROSTER: the one table of the 28 new aeroplane kinds (original names, own-made procedural models, PlaneModels).
Writes scripts/vehicles/plane_roster.gd (PlaneRoster: NEW, KINDS, DEFS, the PLANE LINE and the hangar places) and the generated blocks between the
"w126-planes BEGIN / END" markers of scripts/vehicles/vehicle_specs.gd (SPECS, PALETTES, NAMES, WEAPONS, ROSTER, AIRCRAFT_KINDS) and scripts/common/audio_director.gd (ENGINES).
It also simulates the take-off roll of every kind with the AircraftFlight.plane() ground formula and stops if one needs more than MAX_RUN m (the runway is 800 m).
Run: python3 tools/gen_plane_roster.py"""
import os, re, sys

MAX_RUN = 620.0
RUNWAY_GAP = 6.0                 # w126-critic: 8 -> 6 m (room for the two taxi lanes)

# id, name, role,
# flight (max m/s, stall m/s, acc, climb m/s, agile, roll 1/s, pitch rad/s), body (mass kg, hp, seats),
# engine (sound variant, pitch, dB, jet?, burner?), dims (len, span, hgt, wheel r, prop r or 0), gun or None, palette, place, model params (GDScript literal)
# place: "line" (the PLANE LINE east of the runway), "hangar_a" / "hangar_b" (airport hangars), "shelter_1" / "shelter_2" (ARMY AIRBASE shelters)
P = [
 ("p_cub", "MEADOWLARK", "light", (52, 20, 10, 9, 1.05, 3.0, 2.4), (600, 300, 2), ("prop", 1.25, 0, False, False), (7.0, 10.8, 2.3, 0.3, 0.95), None,
  ["(0.95, 0.78, 0.16)", "(0.86, 0.2, 0.14)", "(0.9, 0.9, 0.86)", "(0.2, 0.4, 0.7)"], "hangar_a",
  '{"f": [-3.4, 3.6, 0.5, 0.62, 1.35], "n": 2.4, "nose": "blunt", "cab": "cabin", "w": [-1.9, 5.4, 1.5, 1.3, 0.0, 0.15, 0.62, 0.16], "t": "conv", "tp": [1.3, 1.1, 1.6, 0.8], "e": {"type": "nose", "r": 0.42, "l": 0.3}, "g": "tail", "x": ["strut"]}'),
 ("p_trainer", "CADET TRAINER", "trainer", (62, 23, 12, 12, 1.2, 3.9, 2.8), (1100, 380, 2), ("prop", 1.12, 0, False, False), (8.2, 10.0, 2.8, 0.3, 1.0), None,
  ["(0.92, 0.92, 0.9)", "(0.12, 0.3, 0.7)", "(0.9, 0.4, 0.12)", "(0.2, 0.2, 0.22)"], "hangar_b",
  '{"f": [-4.0, 4.2, 0.55, 0.68, 1.45], "n": 2.2, "nose": "round", "cab": "bubble", "w": [-1.3, 5.0, 1.8, 1.0, 0.25, 0.45, -0.5, 0.22], "t": "conv", "tp": [1.4, 1.2, 1.7, 0.85], "e": {"type": "nose", "r": 0.46, "l": 0.4}, "g": "trike", "x": []}'),
 ("p_biplane", "TUMBLER AEROBATIC", "aerobatic", (60, 19, 13, 13, 1.6, 5.6, 3.6), (700, 320, 1), ("prop", 1.32, 1, False, False), (6.6, 7.4, 2.7, 0.32, 0.95), None,
  ["(0.86, 0.12, 0.1)", "(0.95, 0.85, 0.2)", "(0.1, 0.1, 0.12)", "(0.92, 0.92, 0.9)"], "hangar_a",
  '{"f": [-3.1, 3.5, 0.48, 0.6, 1.4], "n": 2.6, "nose": "blunt", "cab": "open", "w": [-1.7, 3.7, 1.25, 1.1, 0.15, 0.1, -0.55, 0.14], "w2": [1.55, -0.35], "t": "conv", "tp": [1.2, 1.0, 1.4, 0.75], "e": {"type": "nose", "r": 0.5, "l": 0.5}, "g": "tail", "x": ["istrut", "smoke"]}'),
 ("p_duster", "DUSTDEVIL CROP DUSTER", "crop duster", (55, 21, 11, 9, 1.15, 3.6, 2.6), (1900, 450, 1), ("prop", 0.95, 1, False, False), (9.0, 14.0, 3.1, 0.38, 1.3), None,
  ["(0.95, 0.8, 0.12)", "(0.2, 0.42, 0.24)", "(0.9, 0.9, 0.86)", "(0.86, 0.3, 0.12)"], "line",
  '{"f": [-4.3, 4.5, 0.55, 0.75, 1.6], "n": 2.8, "nose": "blunt", "cab": "bubble", "w": [-1.6, 7.0, 1.9, 1.5, 0.0, 0.35, -0.6, 0.22], "t": "conv", "tp": [1.6, 1.3, 2.1, 1.0], "e": {"type": "nose", "r": 0.55, "l": 0.9}, "g": "tail", "x": ["spray", "hopper"]}'),
 ("p_seaplane", "PELICAN FLOATPLANE", "seaplane", (50, 22, 10, 8, 0.95, 2.8, 2.2), (1400, 420, 4), ("prop", 1.02, 0, False, False), (9.2, 12.8, 3.8, 0.3, 1.15), None,
  ["(0.92, 0.92, 0.9)", "(0.86, 0.28, 0.1)", "(0.2, 0.32, 0.6)", "(0.9, 0.78, 0.2)"], "line",
  '{"f": [-4.4, 4.6, 0.62, 0.78, 2.6], "n": 2.6, "nose": "blunt", "cab": "cabin", "w": [-2.1, 6.4, 1.7, 1.4, 0.0, 0.12, 0.72, 0.18], "t": "conv", "tp": [1.5, 1.3, 1.9, 0.9], "e": {"type": "nose", "r": 0.5, "l": 0.45}, "g": "float", "x": ["strut"]}'),
 ("p_bush", "TUNDRA BUSH PLANE", "bush", (56, 18, 12, 11, 1.05, 3.1, 2.5), (1300, 460, 4), ("prop", 0.92, 1, False, False), (8.6, 13.6, 3.1, 0.48, 1.2), None,
  ["(0.86, 0.4, 0.12)", "(0.92, 0.92, 0.9)", "(0.24, 0.3, 0.22)", "(0.12, 0.2, 0.36)"], "line",
  '{"f": [-4.1, 4.5, 0.62, 0.78, 1.6], "n": 2.6, "nose": "blunt", "cab": "cabin", "w": [-2.0, 6.8, 1.8, 1.6, 0.0, 0.1, 0.75, 0.18], "t": "conv", "tp": [1.6, 1.4, 2.0, 0.95], "e": {"type": "nose", "r": 0.55, "l": 0.55}, "g": "tail", "x": ["strut", "tundra"]}'),
 ("p_twin", "TWINFINCH LIGHT TWIN", "light twin", (74, 26, 12, 12, 1.0, 3.0, 2.4), (2200, 520, 5), ("prop", 1.08, 1, False, False), (10.0, 12.0, 3.3, 0.32, 1.0), None,
  ["(0.92, 0.92, 0.9)", "(0.14, 0.22, 0.42)", "(0.62, 0.12, 0.12)", "(0.3, 0.32, 0.36)"], "line",
  '{"f": [-4.8, 5.2, 0.62, 0.72, 1.55], "n": 2.2, "nose": "point", "cab": "cabin", "w": [-1.2, 6.0, 2.0, 1.1, 0.35, 0.35, -0.55, 0.22], "t": "conv", "tp": [1.7, 1.5, 2.2, 1.0], "e": {"type": "wp", "at": [0.3], "r": 0.42, "l": 2.6}, "g": "trike", "x": []}'),
 ("p_regional", "SKYLINK REGIONAL", "regional", (82, 30, 12, 11, 0.75, 2.1, 1.9), (18000, 1300, 3), ("prop", 0.82, 2, False, False), (24.0, 26.0, 7.4, 0.55, 1.9), None,
  ["(0.92, 0.93, 0.95)", "(0.1, 0.42, 0.62)", "(0.92, 0.6, 0.1)", "(0.3, 0.3, 0.34)"], "line",
  '{"f": [-12.0, 12.0, 1.35, 1.45, 2.3], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-2.6, 13.0, 3.0, 1.6, 0.3, 0.2, 1.0, 0.32], "t": "t", "tp": [4.2, 3.4, 4.4, 1.8], "e": {"type": "wp", "at": [0.3], "r": 0.7, "l": 4.4}, "g": "heavy", "x": []}'),
 ("p_narrow", "CITYHOP NARROWBODY", "narrow-body", (112, 40, 13, 15, 0.6, 1.8, 1.8), (52000, 2100, 3), ("jet", 0.86, 3, True, False), (34.0, 34.0, 11.0, 0.8, 0.0), None,
  ["(0.93, 0.94, 0.96)", "(0.12, 0.3, 0.62)", "(0.86, 0.16, 0.2)", "(0.2, 0.52, 0.36)"], "line",
  '{"f": [-17.0, 17.0, 1.95, 2.05, 3.5], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-4.0, 17.0, 6.0, 1.6, 6.5, 1.2, -0.65, 0.5], "t": "conv", "tp": [6.0, 5.0, 6.4, 2.6], "e": {"type": "wj", "at": [0.34], "r": 1.05, "l": 4.2}, "g": "heavy", "x": ["winglet"]}'),
 ("p_wide", "OCEANIC WIDEBODY", "wide-body", (118, 42, 13, 14, 0.5, 1.5, 1.6), (180000, 3000, 3), ("jet", 0.72, 3, True, False), (44.0, 38.0, 14.6, 0.95, 0.0), None,
  ["(0.94, 0.95, 0.96)", "(0.1, 0.2, 0.42)", "(0.9, 0.7, 0.2)", "(0.62, 0.12, 0.14)"], "line",
  '{"f": [-22.0, 22.0, 2.7, 2.85, 4.4], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-5.5, 19.0, 8.0, 2.0, 8.5, 1.5, -0.65, 0.65], "t": "conv", "tp": [7.6, 6.0, 7.6, 3.2], "e": {"type": "wj", "at": [0.33], "r": 1.55, "l": 5.6}, "g": "heavy", "x": ["winglet"]}'),
 ("p_jumbo", "TITAN JUMBO", "jumbo", (116, 43, 13, 13, 0.45, 1.4, 1.5), (300000, 3400, 3), ("jet", 0.66, 4, True, False), (48.0, 38.0, 16.8, 1.0, 0.0), None,
  ["(0.94, 0.95, 0.96)", "(0.42, 0.1, 0.12)", "(0.12, 0.2, 0.36)", "(0.86, 0.62, 0.16)"], "line",
  '{"f": [-24.0, 24.0, 2.9, 3.0, 4.6], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-6.0, 19.0, 9.0, 2.2, 9.0, 1.6, -0.65, 0.7], "t": "conv", "tp": [8.4, 6.4, 8.0, 3.4], "e": {"type": "wj", "at": [0.3, 0.58], "r": 1.25, "l": 5.0}, "g": "heavy", "x": ["hump"]}'),
 ("p_freighter", "PACKHORSE FREIGHTER", "freighter", (80, 30, 11, 10, 0.6, 1.8, 1.7), (60000, 2600, 4), ("prop", 0.7, 3, False, False), (30.0, 36.0, 11.6, 0.8, 2.0), None,
  ["(0.42, 0.46, 0.4)", "(0.3, 0.34, 0.3)", "(0.52, 0.54, 0.56)", "(0.86, 0.88, 0.9)"], "line",
  '{"f": [-15.0, 15.0, 2.3, 2.4, 3.2], "n": 2.4, "nose": "round", "cab": "glazed", "w": [-3.6, 18.0, 4.6, 2.4, 0.4, -0.2, 1.0, 0.5], "t": "t", "tp": [6.2, 5.2, 7.0, 2.8], "e": {"type": "wp", "at": [0.28, 0.55], "r": 0.75, "l": 4.6}, "g": "heavy", "x": ["ramp", "sponson"]}'),
 ("p_fighter", "FALCO FIGHTER", "fighter", (160, 44, 32, 38, 1.9, 6.2, 3.9), (9000, 900, 1), ("jet", 1.12, 3, True, True), (15.0, 10.0, 4.8, 0.45, 0.0), ("CANNON", 22.0, 12.0, 900, 300.0),
  ["(0.5, 0.54, 0.58)", "(0.36, 0.4, 0.44)", "(0.6, 0.62, 0.64)", "(0.3, 0.34, 0.3)"], "shelter_1",
  '{"f": [-7.5, 7.5, 0.75, 0.82, 2.0], "n": 2.4, "nose": "point", "cab": "bubble", "w": [-1.0, 5.0, 4.6, 1.2, 3.6, -0.05, -0.1, 0.24], "t": "conv", "tp": [2.6, 2.6, 2.6, 1.8], "e": {"type": "int", "n": 1, "r": 0.55}, "g": "mil", "x": ["intake", "pods"]}'),
 ("p_interceptor", "LANCE INTERCEPTOR", "interceptor", (175, 50, 36, 44, 1.6, 5.2, 3.4), (14000, 1000, 1), ("jet", 1.05, 4, True, True), (18.0, 10.5, 5.4, 0.48, 0.0), ("CANNON", 20.0, 12.0, 700, 300.0),
  ["(0.62, 0.64, 0.68)", "(0.4, 0.42, 0.48)", "(0.26, 0.28, 0.32)", "(0.7, 0.72, 0.76)"], "line",
  '{"f": [-9.0, 9.0, 0.8, 0.9, 2.2], "n": 2.2, "nose": "point", "cab": "bubble", "w": [-3.4, 5.25, 9.0, 0.6, 8.0, -0.1, -0.2, 0.3], "t": "fin", "tp": [3.2, 3.6, 0.0, 0.0], "e": {"type": "int", "n": 2, "r": 0.5}, "g": "mil", "x": ["intake", "canard"]}'),
 ("p_attack", "BRUISER GROUND ATTACK", "ground attack", (100, 32, 18, 18, 1.3, 3.6, 2.8), (15000, 1800, 1), ("jet", 0.9, 3, True, False), (16.5, 17.5, 4.6, 0.5, 0.0), ("ROTARY GUN", 30.0, 9.0, 1200, 260.0),
  ["(0.36, 0.4, 0.34)", "(0.3, 0.32, 0.3)", "(0.46, 0.48, 0.5)", "(0.24, 0.26, 0.24)"], "line",
  '{"f": [-8.2, 8.3, 0.85, 0.95, 2.0], "n": 2.8, "nose": "blunt", "cab": "bubble", "w": [-1.6, 8.75, 3.0, 1.9, 0.2, 0.3, -0.5, 0.36], "t": "twin", "tp": [2.6, 2.2, 3.2, 1.8], "e": {"type": "tj", "r": 0.7, "l": 3.4}, "g": "mil", "x": ["pods", "gun"]}'),
 ("p_bomber", "THUNDERHEAD BOMBER", "bomber", (130, 42, 15, 14, 0.55, 1.6, 1.6), (120000, 3200, 3), ("jet", 0.7, 4, True, False), (40.0, 38.0, 10.8, 0.9, 0.0), None,
  ["(0.5, 0.52, 0.54)", "(0.3, 0.32, 0.34)", "(0.62, 0.64, 0.66)", "(0.2, 0.22, 0.24)"], "line",
  '{"f": [-20.0, 20.0, 1.8, 1.9, 3.4], "n": 2.2, "nose": "point", "cab": "glazed", "w": [-5.0, 19.0, 8.0, 2.4, 11.0, -0.4, 0.8, 0.6], "t": "conv", "tp": [6.6, 5.4, 6.8, 2.8], "e": {"type": "wj", "at": [0.32, 0.6], "r": 0.95, "l": 4.6}, "g": "heavy", "x": ["bays"]}'),
 ("p_wing", "NIGHTVEIL FLYING WING", "stealth bomber", (135, 40, 16, 16, 0.7, 2.0, 1.8), (70000, 2400, 2), ("jet", 0.78, -2, True, False), (20.0, 36.0, 5.4, 0.8, 0.0), None,
  ["(0.16, 0.17, 0.19)", "(0.22, 0.23, 0.26)", "(0.12, 0.12, 0.14)", "(0.26, 0.26, 0.3)"], "line",
  '{"f": [-10.0, 3.0, 2.2, 1.1, 2.6], "n": 4.0, "nose": "point", "cab": "slit", "w": [-9.0, 18.0, 17.0, 1.6, 12.5, 0.0, 0.0, 1.0], "t": "none", "tp": [0.0, 0.0, 0.0, 0.0], "e": {"type": "int", "n": 4, "r": 0.5}, "g": "heavy", "x": ["saw"]}'),
 ("p_stealthf", "WRAITH STEALTH FIGHTER", "stealth fighter", (165, 46, 33, 40, 1.8, 5.8, 3.7), (19000, 950, 1), ("jet", 1.0, 0, True, True), (17.5, 12.5, 4.8, 0.48, 0.0), ("CANNON", 20.0, 12.0, 600, 300.0),
  ["(0.2, 0.21, 0.24)", "(0.28, 0.3, 0.33)", "(0.14, 0.15, 0.17)", "(0.34, 0.34, 0.38)"], "shelter_2",
  '{"f": [-8.7, 8.8, 1.1, 0.75, 2.0], "n": 6.0, "nose": "point", "cab": "bubble", "w": [-2.6, 6.25, 7.4, 1.4, 5.2, -0.05, 0.0, 0.3], "t": "vcant", "tp": [2.6, 2.8, 2.6, 2.0], "e": {"type": "int", "n": 2, "r": 0.48}, "g": "mil", "x": ["intake"]}'),
 ("p_tanker", "OASIS TANKER", "tanker", (112, 41, 13, 13, 0.5, 1.5, 1.6), (140000, 2800, 3), ("jet", 0.74, 3, True, False), (42.0, 38.0, 13.0, 0.95, 0.0), None,
  ["(0.6, 0.62, 0.64)", "(0.46, 0.48, 0.5)", "(0.9, 0.9, 0.9)", "(0.3, 0.32, 0.36)"], "line",
  '{"f": [-21.0, 21.0, 2.4, 2.55, 4.0], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-5.0, 19.0, 7.5, 2.0, 8.0, 1.4, -0.65, 0.6], "t": "conv", "tp": [7.0, 5.6, 7.2, 3.0], "e": {"type": "wj", "at": [0.36], "r": 1.4, "l": 5.4}, "g": "heavy", "x": ["boom", "drogue"]}'),
 ("p_awacs", "WATCHTOWER AWACS", "AWACS", (108, 40, 13, 12, 0.5, 1.5, 1.5), (140000, 2600, 3), ("jet", 0.76, 3, True, False), (40.0, 38.0, 13.0, 0.95, 0.0), None,
  ["(0.66, 0.68, 0.7)", "(0.5, 0.52, 0.56)", "(0.86, 0.88, 0.9)", "(0.3, 0.34, 0.4)"], "line",
  '{"f": [-20.0, 20.0, 2.3, 2.45, 3.9], "n": 2.0, "nose": "round", "cab": "airliner", "w": [-5.0, 19.0, 7.0, 2.0, 7.6, 1.3, -0.65, 0.6], "t": "conv", "tp": [6.6, 5.4, 7.0, 2.8], "e": {"type": "wj", "at": [0.3, 0.56], "r": 0.95, "l": 4.4}, "g": "heavy", "x": ["rotodome"]}'),
 ("p_drone", "KESTREL RECON DRONE", "recon drone", (60, 22, 11, 10, 1.1, 2.8, 2.3), (1100, 260, 1), ("prop", 1.45, -2, False, False), (8.4, 16.0, 2.3, 0.26, 0.9), None,
  ["(0.62, 0.64, 0.66)", "(0.5, 0.52, 0.54)", "(0.4, 0.42, 0.46)", "(0.86, 0.88, 0.9)"], "line",
  '{"f": [-4.0, 4.4, 0.5, 0.55, 1.5], "n": 2.2, "nose": "round", "cab": "none", "w": [-0.6, 8.0, 1.2, 0.6, 0.3, 0.3, 0.3, 0.14], "t": "v", "tp": [1.5, 1.0, 1.6, 0.8], "e": {"type": "push", "r": 0.3, "l": 0.3}, "g": "trike", "x": ["dome", "sensor"]}'),
 ("p_ucav", "TALON COMBAT DRONE", "combat drone", (150, 44, 28, 30, 1.5, 4.6, 3.0), (7000, 600, 1), ("jet", 1.2, 0, True, False), (11.0, 14.0, 2.9, 0.4, 0.0), ("CANNON", 16.0, 10.0, 500, 260.0),
  ["(0.42, 0.44, 0.48)", "(0.3, 0.32, 0.36)", "(0.22, 0.24, 0.26)", "(0.56, 0.58, 0.6)"], "line",
  '{"f": [-5.5, 2.5, 1.1, 0.6, 1.4], "n": 4.0, "nose": "point", "cab": "none", "w": [-4.6, 7.0, 8.0, 0.9, 5.4, 0.0, 0.0, 0.5], "t": "none", "tp": [0.0, 0.0, 0.0, 0.0], "e": {"type": "int", "n": 1, "r": 0.45}, "g": "trike", "x": ["intake_top"]}'),
 ("p_glider", "WHISPER MOTOR GLIDER", "glider", (46, 17, 7, 6, 0.9, 2.2, 2.0), (450, 200, 2), ("prop", 1.6, -4, False, False), (7.6, 17.0, 1.9, 0.22, 0.7), None,
  ["(0.95, 0.95, 0.94)", "(0.86, 0.2, 0.14)", "(0.92, 0.92, 0.9)", "(0.2, 0.36, 0.7)"], "line",
  '{"f": [-3.6, 4.0, 0.36, 0.48, 0.85], "n": 2.0, "nose": "round", "cab": "bubble", "w": [-0.9, 8.5, 1.0, 0.45, 0.15, 0.45, 0.4, 0.1], "t": "t", "tp": [1.3, 0.9, 1.4, 0.55], "e": {"type": "mast", "r": 0.22, "l": 0.4}, "g": "skid", "x": []}'),
 ("p_racer", "REDLINE AIR RACER", "racer", (98, 28, 20, 18, 1.75, 6.5, 3.4), (900, 340, 1), ("prop", 1.5, 2, False, False), (7.4, 7.6, 2.5, 0.28, 1.05), None,
  ["(0.9, 0.14, 0.1)", "(0.95, 0.95, 0.94)", "(0.1, 0.1, 0.12)", "(0.12, 0.4, 0.86)"], "hangar_b",
  '{"f": [-3.5, 3.9, 0.48, 0.58, 1.3], "n": 2.2, "nose": "point", "cab": "bubble", "w": [-0.8, 3.8, 1.6, 0.8, 0.2, 0.2, -0.55, 0.16], "t": "conv", "tp": [1.2, 1.0, 1.3, 0.7], "e": {"type": "nose", "r": 0.46, "l": 0.5}, "g": "tail", "x": ["stripe"]}'),
 ("p_amphib", "MARLIN FLYING BOAT", "flying boat", (66, 26, 10, 8, 0.75, 2.2, 1.9), (16000, 1500, 4), ("prop", 0.85, 2, False, False), (22.0, 30.0, 7.6, 0.6, 1.7), None,
  ["(0.92, 0.92, 0.9)", "(0.2, 0.3, 0.5)", "(0.9, 0.42, 0.12)", "(0.86, 0.12, 0.1)"], "line",
  '{"f": [-11.0, 11.0, 1.3, 1.5, 2.4], "n": 2.6, "nose": "round", "cab": "airliner", "w": [-2.8, 15.0, 3.4, 2.0, 0.2, 0.2, 1.4, 0.36], "t": "conv", "tp": [4.0, 3.4, 4.4, 1.8], "e": {"type": "wt", "at": [0.24], "r": 0.7, "l": 4.0}, "g": "hull", "x": ["floats_tip"]}'),
 ("p_sst", "SONIC DART", "supersonic", (170, 48, 22, 22, 0.7, 2.2, 1.8), (90000, 2200, 3), ("jet", 0.92, 4, True, True), (46.0, 24.0, 10.0, 0.9, 0.0), None,
  ["(0.95, 0.95, 0.96)", "(0.12, 0.2, 0.4)", "(0.86, 0.14, 0.14)", "(0.7, 0.72, 0.76)"], "line",
  '{"f": [-23.0, 23.0, 1.5, 1.6, 3.2], "n": 2.0, "nose": "droop", "cab": "airliner", "w": [-6.0, 12.0, 26.0, 2.0, 22.0, 0.0, -0.6, 0.6], "t": "fin", "tp": [6.4, 7.0, 0.0, 0.0], "e": {"type": "wj", "at": [0.22, 0.42], "r": 0.8, "l": 6.0}, "g": "heavy", "x": []}'),
 ("p_quantum", "QUANTA ARROW", "sci-fi", (185, 34, 40, 45, 2.0, 6.0, 4.2), (6000, 1100, 2), ("jet", 1.5, 0, True, True), (14.0, 11.0, 3.7, 0.4, 0.0), ("PHASE BOLT", 9.0, 20.0, 300, 260.0),
  ["(0.9, 0.92, 0.95)", "(0.2, 0.2, 0.28)", "(0.36, 0.3, 0.6)", "(0.24, 0.5, 0.5)"], "line",
  '{"f": [-7.0, 7.0, 0.9, 0.7, 1.6], "n": 2.0, "nose": "point", "cab": "bubble", "w": [-2.0, 5.5, 6.0, 1.0, 4.6, 0.5, 0.0, 0.3], "t": "vcant", "tp": [1.8, 2.2, 2.0, 1.6], "e": {"type": "int", "n": 2, "r": 0.45}, "g": "skid", "x": ["glow", "ring"], "mark": Color(0.25, 0.95, 1.0)}'),
 ("p_manta", "PHASE MANTA", "sci-fi", (160, 30, 34, 40, 1.7, 5.0, 3.6), (8000, 1200, 2), ("jet", 1.7, 0, True, False), (16.0, 18.0, 3.5, 0.4, 0.0), ("PHASE BOLT", 8.0, 22.0, 300, 260.0),
  ["(0.18, 0.16, 0.24)", "(0.86, 0.87, 0.9)", "(0.12, 0.14, 0.18)", "(0.5, 0.2, 0.5)"], "line",
  '{"f": [-8.0, 6.0, 1.6, 0.8, 1.6], "n": 3.0, "nose": "round", "cab": "bubble", "w": [-6.0, 9.0, 12.0, 1.4, 9.5, 0.6, 0.0, 0.5], "t": "none", "tp": [0.0, 0.0, 0.0, 0.0], "e": {"type": "int", "n": 3, "r": 0.4}, "g": "skid", "x": ["glow", "ring2"], "mark": Color(1.0, 0.3, 0.95)}'),
]

LINE_X = 1307.0
LINE_Z0 = -935.0
# where the hangar planes stand (airport LOCAL frame) and their local heading: the airport hangars open to the east (local h -PI/2 = nose +x), the shelters to the south (h PI = nose +z)
PLACES = {
 "hangar_a": [(1138.0, -950.0), (1138.0, -929.0)], "hangar_b": [(1138.0, -886.0), (1138.0, -865.0)],
 "shelter_1": [(1360.0, -776.0)], "shelter_2": [(1360.0, -576.0)],
}
PLACE_H = {"hangar_a": "-PI * 0.5", "hangar_b": "-PI * 0.5", "shelter_1": "PI", "shelter_2": "PI"}


def takeoff_run(mx, stall, acc, jet):
    # AircraftFlight.plane() on the wheels: the lever comes up at LEVER_UP (0.7/s) with the stick forward, UP held: it leaves the ground at V > stall (ROTATE_AT 1.0)
    dt, V, x, lever = 1.0 / 120.0, 0.0, 0.0, 0.0
    for _ in range(120 * 120):
        lever = min(1.0, lever + 0.7 * dt)
        drag = 0.35 + V * V * (0.00028 if jet else 0.0004) * 11.0 / max(acc, 6.0)
        thrust = acc * lever * (1.0 - min(max(V / mx, 0.0), 1.3))
        V = max(V + (thrust - drag) * dt, 0.0)
        x += V * dt
        if V > stall:
            return x
    return 1e9


def spec_line(p):
    i, nm, role, fl, bd, en, dm, gun, pal, place, m = p
    mx, stall, acc, climb, agile, roll, pitch = fl
    mass, hp, seats = bd
    var, ep, db, jet, burner = en
    ln, span, hgt, wheel, prop_r = dm
    wid = min(span, max(3.0, span * 0.6))
    run = takeoff_run(mx, stall, acc, jet)
    cam_d = max(14.0, ln * 1.25 + span * 0.35)
    cam_h = max(4.4, hgt * 0.9 + 2.0)
    extra = ""
    if prop_r > 0.0:
        extra += ', "prop_r": %.2f' % prop_r
    if jet:
        extra += ', "jet": true'
    if burner:
        extra += ', "burner": true'
    return ('\t&"%s": {"cls": "plane", "craft": true, "procedural": "%s", "max": %.1f, "acc": %.1f, "brake": 20.0, "grip": 2.0, "hp": %.1f, "mass": %.1f, "seats": %d, "model": "pl_%s", '
            '"len": %.1f, "wid": %.1f, "hgt": %.1f, "wheel": %.2f, "stall": %.1f, "span": %.1f, "ceil": 1400.0, "climb": %.1f, "agile": %.2f, "roll": %.2f, "pitch": %.2f, "run": %.0f%s, '
            '"cam_d": %.1f, "cam_h": %.1f, "exit_side": %.1f, "aim_cone": 0.3},'
            % (i, i, mx, acc, hp, mass, seats, i[2:], ln, wid, hgt, wheel, stall, span, climb, agile, roll, pitch, run, extra, cam_d, cam_h, wid * 0.5 + 1.6))


# w126-critic: two TAXI LANES cross the line (and the HELI LINE gaps between its helicopters at z -740 / -702 and -550 / -512): the fighters of the ARMY SHELTERS roll out
# south and turn west through them to the runway. Before, the line was a wall from z -935 to -249 and both shelter fighters were boxed in.
LANES = [(-737.0, -705.0), (-547.0, -515.0)]


def line_places():
    out, z = {}, LINE_Z0
    todo = [p for p in P if p[9] == "line"]
    while todo:
        lane = next(((lo, hi) for lo, hi in LANES if hi > z), None)
        pick = None
        for p in todo:                                          # the first plane (in table order) that fits before the next lane
            if lane is None or z + p[6][0] <= lane[0] or z >= lane[1]:
                pick = p
                break
        if pick is None:
            z = lane[1] + 2.0                                   # nothing fits: jump over the lane
            continue
        todo.remove(pick)
        ln = pick[6][0]
        out[pick[0]] = (LINE_X, z + ln * 0.5)
        z += ln + RUNWAY_GAP
    if z > -196.0:
        sys.exit("the PLANE LINE runs past z -196 (%.0f): shorten it" % z)
    return out


def inject(path, begin_anchor_fn, block_lines, tag):
    src = open(path).read().split("\n")
    b = "\t# w126-planes BEGIN %s (generated by tools/gen_plane_roster.py)" % tag
    e = "\t# w126-planes END %s" % tag
    if b in src:
        i0 = src.index(b)
        i1 = src.index(e)
        src[i0:i1 + 1] = [b] + block_lines + [e]
    else:
        at = begin_anchor_fn(src)
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
    text = re.sub(r', &"p_[a-z_]+"', "", text)
    text = text[:text.rstrip().rfind("]")] + ", " + ", ".join('&"%s"' % i for i in ids) + "]"
    src[k:j + 1] = text.split("\n")
    open(path, "w").write("\n".join(src))


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    for p in P:
        r = takeoff_run(p[3][0], p[3][1], p[3][2], p[5][3])
        if r > MAX_RUN:
            sys.exit("%s needs %.0f m of runway (over %.0f)" % (p[0], r, MAX_RUN))
    lp = line_places()
    ids = [p[0] for p in P]
    out = ['class_name PlaneRoster', 'extends RefCounted',
           '## WAVE 126 AEROPLANE ROSTER (plan line 126: "30+ kinds"): the five older aeroplanes (plane, jet, cargo, airliner, bizjet) and the 28 of this table, each with its own procedural',
           '## model (PlaneModels), its own flight numbers (VehicleSpecs.SPECS: max, stall, acc, climb, agile, roll, pitch, run = the take-off run in m), engine sound (AudioDirector.ENGINES)',
           '## and icon (assets/icons/v_<kind>.png).',
           '## GENERATED by tools/gen_plane_roster.py (the source of the table): edit there and run it again.',
           '##   KINDS          every aeroplane kind (33); NEW the 28 of wave 126',
           '##   DEFS[kind]     {name, role, place, m: model parameters (PlaneModels)}',
           '##   spawn_points() where they wait (VehicleSpawns.all_points appends them): the PLANE LINE east of the runway (nose north, between the runway and the HELI LINE),',
           '##                  two planes in each airport hangar (hangar_a / hangar_b) and one fighter in each ARMY AIRBASE shelter (Hangars): FIXED vehicles, outside the live car cap', '']
    out.append('const NEW: Array[StringName] = [%s]' % ", ".join('&"%s"' % i for i in ids))
    out.append('const KINDS: Array[StringName] = [&"plane", &"jet", &"cargo", &"airliner", &"bizjet", %s]' % ", ".join('&"%s"' % i for i in ids))
    out.append('const LINE_X := %.1f' % LINE_X)
    out.append('static var line_on := OS.get_environment("W126_PLANES_OLD") != "1"      ## false: the wave 125 state (no new kind stands anywhere), for the old-behaviour run of tests/test_planes_w126.gd')
    out.append('')
    out.append('const DEFS := {')
    for p in P:
        out.append('\t&"%s": {"name": "%s", "role": "%s", "place": &"%s", "m": %s},' % (p[0], p[1], p[2], p[9], p[10]))
    out.append('}')
    out.append('## Where each new kind waits (airport LOCAL frame, Airport.to_world) and its local heading (0 = nose north along the runway, -PI/2 = nose east, PI = nose south).')
    out.append('const PLACES := {')
    used = {k: 0 for k in PLACES}
    for p in P:
        if p[9] == "line":
            x, z = lp[p[0]]
            out.append('\t&"%s": [Vector3(%.1f, 0.0, %.1f), 0.0],' % (p[0], x, z))
        else:
            x, z = PLACES[p[9]][used[p[9]]]
            used[p[9]] += 1
            out.append('\t&"%s": [Vector3(%.1f, 0.0, %.1f), %s],' % (p[0], x, z, PLACE_H[p[9]]))
    out.append('}')
    out.append('''

static func spawn_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not line_on:
		return out
	for k: StringName in NEW:
		var pl: Array = PLACES[k]
		var d: Dictionary = DEFS[k]
		var line: bool = d["place"] == &"line"
		var lbl := ("PLANE LINE: " if line else "HANGAR: ") + String(d["name"])
		out.append({"id": StringName(("pl_" if line else "hg_") + String(k)), "kind": k, "pos": Airport.to_world(pl[0]), "h": Airport.heading_world(float(pl[1])), "label": lbl})
	return out


## A point id of spawn_points(): a FIXED vehicle (ArmourSites.is_fixed), outside the live car cap, kept while the hero is near.
static func owns(id: StringName) -> bool:
	if not line_on:
		return false
	var s := String(id)
	return s.begins_with("pl_p_") or s.begins_with("hg_p_")


static func is_plane(kind: StringName) -> bool:
	return KINDS.has(kind)
''')
    open(os.path.join(root, "scripts/vehicles/plane_roster.gd"), "w").write("\n".join(out))
    vs = os.path.join(root, "scripts/vehicles/vehicle_specs.gd")
    inject(vs, anchor_after('\t&"bizjet": {'), ["\t# wave 126 AEROPLANE ROSTER (PlaneRoster): 28 more aeroplanes on the same craft physics, procedural models (PlaneModels)."] + [spec_line(p) for p in P], "SPECS")
    inject(vs, anchor_after('\t&"bizjet": [Color'), ['\t&"%s": [%s],' % (p[0], ", ".join("Color" + c for c in p[8])) for p in P], "PALETTES")
    inject(vs, anchor_before('\t&"garbage": "GARBAGE TRUCK"'), ["\t" + ", ".join('&"%s": "%s"' % (p[0], p[1]) for p in P) + ","], "NAMES")
    wl = []
    for p in P:
        if p[7]:
            n, rate, dmg, ammo, rng = p[7]
            col = "Color(0.4, 0.95, 1.0)" if n == "PHASE BOLT" else "Color(1.0, 0.82, 0.3)"
            wl.append('\t&"%s": {"name": "%s", "rate": %.1f, "dmg": %.1f, "heat": 0.03, "cool": 0.3, "ammo": %d, "range": %.1f, "spread": 0.025, "color": %s},' % (p[0], n, rate, dmg, ammo, rng, col))
    inject(vs, anchor_dict_end("const WEAPONS := {"), wl, "WEAPONS")
    add_to_array(vs, "const ROSTER: Array[StringName]", ids)
    add_to_array(vs, "const AIRCRAFT_KINDS: Array[StringName]", ids)
    ad = os.path.join(root, "scripts/common/audio_director.gd")
    inject(ad, anchor_before('\t&"quad": [&"bike"'), ["\t" + ", ".join('&"%s": [&"%s", %.2f, %.1f]' % (p[0], p[5][0], p[5][1], p[5][2]) for p in P) + ","], "ENGINES")
    for p in P:
        print("%-14s run %4.0f m  stall %3d  max %3d" % (p[0], takeoff_run(p[3][0], p[3][1], p[3][2], p[5][3]), p[3][1], p[3][0]))


main()
