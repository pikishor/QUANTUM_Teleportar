"""Pickups and the quantum core, built as BEACONS: they must read from 30 m away in the night city, so every one has a large floating
silhouette, a thick glowing ground ring, and a real coloured light that paints the street around it.

  pickup_health  green medical cache hovering in a four-pylon cage (glowing cross on all five visible faces)
  pickup_energy  cyan quantum cell with orbiting rings in a three-pylon cage
  core_gem       containment frame with a magenta crystal (1.62 m tall, crystal centred at 0.95 m)

Emission is kept near 1.0-1.3 x a saturated colour (ACES turns anything much hotter into white, which is what made the old pickups
indistinguishable); the colour code comes from the glowing parts AND the light. Each model is ONE draw call: one baked material named
"Glow" (the missions module may duplicate it and change `emission` to retint).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import Part, export_model, hexc, light, make_material, new_scene, paint  # noqa: E402

GREEN = hexc("#14ff6c")
CYAN = hexc("#12d6ff")
MAGENTA = hexc("#ff1ac8")
WHITE = (1.0, 0.92, 0.96)


def cage(p, glow, gun, gm2, count, radius, top, phase=45.0):
    """Pylons around the pickup: slim posts with glowing caps, so the beacon has a tall silhouette."""
    for k in range(count):
        a = math.radians(phase + 360.0 / count * k)
        px, py = radius * math.cos(a), radius * math.sin(a)
        p.bar((px, py, 0.03), (px, py, top), 0.04, 0.04, mat=gun, tint=gm2, bevel=0.006)
        p.box((0.075, 0.075, 0.05), (px, py, top + 0.03), mat=glow, bevel=0.006)


def medkit():
    new_scene()
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    glow = make_material("Glow", tex="glow", color=GREEN)
    shell = paint("plating", "#d0d7da")
    shell2 = paint("plating", "#98a3a8")
    dark = paint("plating", "#262b2e")
    gm = paint("steel", "#7c858b")
    gm2 = paint("steel", "#30353a")
    p = Part("Body", seed=3)
    zc = 0.86
    p.cyl(0.50, 0.03, (0, 0, 0.015), mat=armor, tint=dark, segs=28, bevel=0.004)                       # ground pad
    p.torus(0.55, 0.024, (0, 0, 0.032), mat=glow, segs=36, sides=6)                                     # thick marker ring
    cage(p, glow, gun, gm2, 4, 0.48, 0.92)
    p.box((0.46, 0.30, 0.10), (0, 0, zc - 0.07), mat=armor, tint=shell2, bevel=0.015, bsegs=2)           # lower shell
    p.box((0.46, 0.30, 0.12), (0, 0, zc + 0.05), mat=armor, tint=shell, bevel=0.018, bsegs=2)            # lid
    p.box((0.47, 0.31, 0.012), (0, 0, zc - 0.012), mat=gun, tint=gm2)                                    # seal
    for x in (-0.15, 0.15):
        p.box((0.05, 0.02, 0.07), (x, 0.157, zc - 0.012), mat=gun, tint=gm, bevel=0.004)                 # latches
    p.box((0.2, 0.035, 0.03), (0, 0, zc + 0.137), mat=gun, tint=dark, bevel=0.01, bsegs=2)               # carry handle
    for x in (-0.1, 0.1):
        p.box((0.025, 0.04, 0.05), (x, 0, zc + 0.12), mat=gun, tint=dark, bevel=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.05, 0.05, 0.25), (sx * 0.225, sy * 0.145, zc - 0.01), mat=armor, tint=dark, bevel=0.008)    # corner guards
    # the cross, on top and on the four sides
    p.box((0.17, 0.05, 0.016), (0, 0, zc + 0.115), mat=glow)
    p.box((0.05, 0.17, 0.016), (0, 0, zc + 0.115), mat=glow)
    for sy in (-1, 1):
        p.box((0.15, 0.014, 0.045), (0, sy * 0.155, zc + 0.01), mat=glow)
        p.box((0.045, 0.014, 0.15), (0, sy * 0.155, zc + 0.01), mat=glow)
    for sx in (-1, 1):
        p.box((0.014, 0.15, 0.045), (sx * 0.233, 0, zc + 0.01), mat=glow)
        p.box((0.014, 0.045, 0.15), (sx * 0.233, 0, zc + 0.01), mat=glow)
    p.cyl(0.05, 0.2, (0, 0, zc - 0.23), r2=0.13, mat=gun, tint=gm2, segs=16, bevel=0.004)                # hover emitter
    p.cyl(0.09, 0.012, (0, 0, zc - 0.335), mat=glow, segs=16)
    lt = light("GlowLight", (0.0, 0.0, 0.9), "omni", (0.25, 1.0, 0.45), 1.5, 5.0, attenuation=1.5, fade=(40, 15), group="pickup")
    export_model("pickup_health", [p], extras=[lt], groups={"atlas": dict(base="pickup_health", material="Glow")}, size=512,
                 ao_dist=0.12, ao_strength=0.7, emit_strength=1.3)


def energy_cell():
    new_scene()
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    glow = make_material("Glow", tex="glow", color=CYAN)
    cap = paint("plating", "#454f55")
    cap2 = paint("plating", "#66727a")
    gm = paint("steel", "#7d868e")
    gm2 = paint("steel", "#2f353a")
    p = Part("Body", seed=7)
    zc = 0.9
    p.cyl(0.50, 0.03, (0, 0, 0.015), mat=armor, tint=cap, segs=28, bevel=0.004)
    p.torus(0.55, 0.024, (0, 0, 0.032), mat=glow, segs=36, sides=6)
    cage(p, glow, gun, gm2, 3, 0.48, 0.95, 90.0)
    p.cyl(0.12, 0.46, (0, 0, zc), mat=gun, tint=gm2, segs=16, bevel=0.006)                              # cell body
    for k in range(4):                                                                                    # glowing slits
        a = math.radians(45 + 90 * k)
        p.box((0.02, 0.04, 0.34), (0.118 * math.cos(a), 0.118 * math.sin(a), zc), rot=(0, 0, math.degrees(a)), mat=glow)
    for dz in (-0.255, 0.255):                                                                            # end caps with glow discs
        p.cyl(0.155, 0.05, (0, 0, zc + dz), mat=armor, tint=cap2, segs=16, bevel=0.008, bsegs=2)
        p.cyl(0.16, 0.012, (0, 0, zc + dz * 1.07), mat=glow, segs=20)
    p.cyl(0.04, 0.07, (0, 0, zc + 0.31), mat=gun, tint=gm, segs=12, bevel=0.004)                         # terminals
    p.cyl(0.04, 0.07, (0, 0, zc - 0.31), mat=gun, tint=gm, segs=12, bevel=0.004)
    p.torus(0.30, 0.017, (0, 0, zc), rot=(68, 0, 0), mat=glow, segs=24, sides=5)                         # orbiting rings
    p.torus(0.34, 0.013, (0, 0, zc), rot=(-52, 0, 28), mat=glow, segs=24, sides=5)
    p.cyl(0.07, 0.2, (0, 0, zc - 0.43), r2=0.05, mat=gun, tint=gm2, segs=12)
    lt = light("GlowLight", (0.0, 0.0, 0.9), "omni", (0.1, 0.85, 1.0), 1.5, 5.0, attenuation=1.5, fade=(40, 15), group="pickup")
    export_model("pickup_energy", [p], extras=[lt], groups={"atlas": dict(base="pickup_energy", material="Glow")}, size=512,
                 ao_dist=0.12, ao_strength=0.7, emit_strength=1.3)


def core_gem():
    new_scene()
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    glow = make_material("Glow", tex="glow", color=MAGENTA)
    ring = make_material("GlowRing", tex="glow", color=CYAN)
    hot = make_material("GlowCore", tex="glow", color=WHITE)
    base = paint("plating", "#434c53")
    base2 = paint("plating", "#5d6870")
    gm = paint("steel", "#808992")
    gm2 = paint("steel", "#363c42")
    p = Part("Body", seed=9)
    zc = 0.95
    p.cyl(0.46, 0.09, (0, 0, 0.045), mat=armor, tint=base, segs=8, bevel=0.012, bsegs=2)                  # plinth
    p.cyl(0.36, 0.06, (0, 0, 0.12), mat=armor, tint=base2, segs=8, bevel=0.01, bsegs=2)
    p.cyl(0.14, 0.12, (0, 0, 0.21), mat=gun, tint=gm2, segs=12, bevel=0.006)
    p.cyl(0.2, 0.02, (0, 0, 0.275), mat=ring, segs=12)                                                    # emitter pad
    for k in range(4):                                                                                    # pylons + arcs
        a = math.radians(45 + 90 * k)
        c, s = math.cos(a), math.sin(a)
        p.bar((0.33 * c, 0.33 * s, 0.14), (0.27 * c, 0.27 * s, 1.55), 0.07, 0.05, mat=armor, tint=base2, bevel=0.01, bsegs=1, up=(0, 0, 1))
        p.box((0.05, 0.05, 0.4), (0.3 * c, 0.3 * s, 0.55), mat=gun, tint=gm2, bevel=0.006, rot=(0, 0, math.degrees(a)))
        p.box((0.014, 0.014, 0.5), (0.31 * c, 0.31 * s, 0.9), mat=ring)
    p.torus(0.3, 0.028, (0, 0, 1.6), mat=armor, tint=base2, segs=20, sides=6)                             # top ring
    p.torus(0.3, 0.028, (0, 0, 0.42), mat=armor, tint=base, segs=20, sides=6)
    p.torus(0.42, 0.016, (0, 0, zc), rot=(72, 0, 0), mat=ring, segs=24, sides=5)                          # orbit rings
    p.torus(0.46, 0.012, (0, 0, zc), rot=(-58, 0, 25), mat=ring, segs=24, sides=5)
    p.sphere((0.17, 0.17, 0.3), (0, 0, zc), mat=glow, segs=6, rings=4)                                     # the crystal
    p.cyl(0.022, 0.78, (0, 0, zc), mat=hot, segs=8)                                                        # white-hot axis through it
    lt = light("GlowLight", (0.0, 0.0, 0.95), "omni", (1.0, 0.2, 0.8), 2.4, 11.0, attenuation=1.4, fade=(60, 20), group="core")
    export_model("core_gem", [p], extras=[lt], groups={"atlas": dict(base="core_gem", material="Glow")}, size=512,
                 ao_dist=0.15, ao_strength=0.7, emit_strength=1.3)


if __name__ == "__main__":
    medkit()
    energy_cell()
    core_gem()
