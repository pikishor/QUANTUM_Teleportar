"""Pickups and the quantum core: pickup_health (medkit), pickup_energy (quantum cell), core_gem (containment frame + crystal)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from helpers import (Part, bake_ao, empty, export_model, hexc, make_material, new_scene, paint, ring_se)  # noqa: E402


def medkit():
    new_scene()
    armor = make_material("Armor", tex="plating")
    fab = make_material("Fabric", tex="fabric")
    gun = make_material("Gunmetal", tex="steel")
    glow = make_material("Glow", emit=hexc("#27ff7a"), emit_strength=5.0, vcol=False)
    shell = paint("plating", "#aeb8bc")
    shell2 = paint("plating", "#7f8a8f")
    dark = paint("fabric", "#1c2124")
    gm = paint("steel", "#6c747a")
    p = Part("Body", seed=3)
    z0 = 0.0
    p.box((0.44, 0.28, 0.07), (0, 0, 0.035), mat=armor, tint=shell2, bevel=0.012, bsegs=2)                  # lower shell
    p.box((0.44, 0.28, 0.085), (0, 0, 0.1125), mat=armor, tint=shell, bevel=0.014, bsegs=2)                  # lid
    p.box((0.446, 0.286, 0.012), (0, 0, 0.07), mat=fab, tint=dark, bevel=0.003)                              # seal
    for x in (-0.15, 0.15):
        p.box((0.05, 0.02, 0.06), (x, 0.146, 0.075), mat=gun, tint=gm, bevel=0.004)                         # latches
        p.box((0.04, 0.012, 0.028), (x, 0.158, 0.09), mat=gun, tint=gm, bevel=0.003)
    p.box((0.2, 0.035, 0.03), (0, -0.115, 0.17), mat=fab, tint=dark, bevel=0.01, bsegs=2)                     # carry handle
    for x in (-0.1, 0.1):
        p.box((0.025, 0.04, 0.05), (x, -0.115, 0.155), mat=fab, tint=dark, bevel=0.004)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((0.05, 0.05, 0.19), (sx * 0.208, sy * 0.118, 0.095), mat=fab, tint=dark, bevel=0.008)       # corner guards
    p.box((0.105, 0.032, 0.012), (0, 0.0, 0.2), mat=glow)                                                    # the cross
    p.box((0.032, 0.105, 0.012), (0, 0.0, 0.2), mat=glow)
    p.box((0.16, 0.16, 0.006), (0, 0.0, 0.1955), mat=fab, tint=dark, bevel=0.004)
    p.box((0.34, 0.012, 0.03), (0, -0.0, 0.05), mat=fab, tint=dark)
    p.torus(0.30, 0.007, (0, 0, 0.012), mat=glow, segs=36, sides=4)                                          # ground marker ring
    bake_ao([p], samples=14, dist=0.12, strength=0.6)
    export_model("pickup_health", [p.build()])


def energy_cell():
    new_scene()
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    glass = make_material("Glass", tex="glass", color=(0.5, 0.7, 0.8), alpha=0.35, vcol=False)
    glow = make_material("Glow", emit=hexc("#18d6ff"), emit_strength=6.0, vcol=False)
    cap = paint("plating", "#3c464c")
    cap2 = paint("plating", "#59656b")
    gm = paint("steel", "#707880")
    gm2 = paint("steel", "#2c3135")
    p = Part("Body", seed=7)
    p.cyl(0.115, 0.07, (0, 0, 0.035), mat=armor, tint=cap, segs=16, bevel=0.01, bsegs=2)                    # base cap
    p.cyl(0.095, 0.03, (0, 0, 0.085), mat=gun, tint=gm2, segs=16, bevel=0.004)
    p.cyl(0.115, 0.07, (0, 0, 0.385), mat=armor, tint=cap, segs=16, bevel=0.01, bsegs=2)                    # top cap
    p.cyl(0.095, 0.03, (0, 0, 0.335), mat=gun, tint=gm2, segs=16, bevel=0.004)
    p.cyl(0.032, 0.05, (0, 0, 0.445), mat=gun, tint=gm, segs=12, bevel=0.004)                               # terminal
    p.cyl(0.05, 0.016, (0, 0, 0.476), mat=gun, tint=gm, segs=12, bevel=0.003)
    p.cyl(0.058, 0.25, (0, 0, 0.21), mat=glow, segs=14)                                                      # glowing core
    for k in range(4):
        a = math.radians(45 + 90 * k)
        p.bar((0.1 * math.cos(a), 0.1 * math.sin(a), 0.07), (0.1 * math.cos(a), 0.1 * math.sin(a), 0.4), 0.025, 0.025, mat=armor, tint=cap2, bevel=0.005,
              up=(0, 0, 1))
    p.cyl(0.092, 0.2, (0, 0, 0.21), mat=glass, segs=18, caps=(False, False), bevel=0.0)                     # glass sleeve
    for z in (0.12, 0.3):
        p.cyl(0.108, 0.022, (0, 0, z), mat=gun, tint=gm2, segs=18, bevel=0.003)
    p.torus(0.26, 0.007, (0, 0, 0.012), mat=glow, segs=36, sides=4)                                          # ground marker ring
    bake_ao([p], samples=14, dist=0.12, strength=0.55)
    export_model("pickup_energy", [p.build()])


def core_gem():
    new_scene()
    armor = make_material("Armor", tex="plating")
    gun = make_material("Gunmetal", tex="steel")
    glow = make_material("Glow", emit=hexc("#ff2ad0"), emit_strength=7.0, vcol=False)
    glow2 = make_material("GlowRing", emit=hexc("#38f5ff"), emit_strength=4.5, vcol=False)
    base = paint("plating", "#3a4248")
    base2 = paint("plating", "#566068")
    gm = paint("steel", "#7a828a")
    gm2 = paint("steel", "#30353a")
    p = Part("Body", seed=9)
    zc = 0.95
    p.cyl(0.46, 0.09, (0, 0, 0.045), mat=armor, tint=base, segs=8, bevel=0.012, bsegs=2)                    # plinth
    p.cyl(0.36, 0.06, (0, 0, 0.12), mat=armor, tint=base2, segs=8, bevel=0.01, bsegs=2)
    p.cyl(0.14, 0.12, (0, 0, 0.21), mat=gun, tint=gm2, segs=12, bevel=0.006)
    p.cyl(0.2, 0.02, (0, 0, 0.275), mat=glow2, segs=16)                                                      # emitter pad
    for k in range(4):                                                                                       # pylons + arcs
        a = math.radians(45 + 90 * k)
        c, s = math.cos(a), math.sin(a)
        p.bar((0.33 * c, 0.33 * s, 0.14), (0.27 * c, 0.27 * s, 1.55), 0.07, 0.05, mat=armor, tint=base2, bevel=0.01, bsegs=1, up=(-s, c, 0) if False else (0, 0, 1))
        p.box((0.05, 0.05, 0.4), (0.3 * c, 0.3 * s, 0.55), mat=gun, tint=gm2, bevel=0.006, rot=(0, 0, math.degrees(a)))
        p.box((0.012, 0.012, 0.5), (0.31 * c, 0.31 * s, 0.9), mat=glow2)
    p.torus(0.3, 0.025, (0, 0, 1.6), mat=armor, tint=base2, segs=24, sides=6)                               # top ring
    p.torus(0.3, 0.025, (0, 0, 0.42), mat=armor, tint=base, segs=24, sides=6)
    p.torus(0.42, 0.012, (0, 0, zc), rot=(72, 0, 0), mat=glow2, segs=36, sides=4)                          # orbit rings
    p.torus(0.46, 0.009, (0, 0, zc), rot=(-58, 0, 25), mat=glow2, segs=36, sides=4)
    # the crystal: faceted double pyramid with a bright inner core
    p.sphere((0.17, 0.17, 0.3), (0, 0, zc), mat=glow, segs=6, rings=4)
    p.sphere((0.07, 0.07, 0.12), (0, 0, zc), mat=glow2, segs=6, rings=3)
    ob = p.build()
    export_model("core_gem", [ob])


if __name__ == "__main__":
    medkit()
    energy_cell()
    core_gem()
