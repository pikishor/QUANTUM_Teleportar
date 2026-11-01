"""Shared pieces of the new vehicle models (taxi, wagon, van, truck via carlib; bike, hover car, Vael patrol via the model scripts themselves).

* `glow_mat(hex)`   the baked emissive "Glow" kind: alien trim lines, roof signs, hover pads. It lives inside the shared Details atlas (no extra draw call)
                    and is baked into the `_emit` texture, so it glows without a flat material.
* `trim_line(...)`  a thin glowing strip laid on a body side (both sides).
* `wheel_part(...)` one wheel as its own object pivoted at the axle (cars use carlib's own; the bike uses this one: its tyres are narrower and it has a glowing rim ring).
* `lamp_rig(...)`   the readability lights every vehicle ships (headlight spot, underglow omni, own-model fill), same names and layout as the cars.
"""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Vector

from helpers import Part, hexc, light, make_material


def glow_mat(h="#18d6ff", name="Glow"):
    return make_material(name, tex="glow", color=hexc(h))


def trim_line(P, mat, x, y0, y1, z, w=0.016, h=0.014, mirror=True):
    """A glowing strip of length |y1 - y0| centred at y = (y0 + y1) / 2, on the side surface at |x| (box proud of the surface by a few mm)."""
    P.box((w, abs(y1 - y0), h), (x, (y0 + y1) * 0.5, z), mat=mat, bevel=0.003, mirror=mirror)


def wheel_part(name, cx, cy, zc, R, tw, mats, rim="#8d959c", spoke="#c3cad1", spokes=6, seed=70, ring=None, vis_end=60.0):
    """A wheel object pivoted at (cx, cy, zc): tyre, rim, spokes, hub, and an optional glowing ring (`ring` = Mat) on both faces."""
    w = Part(name, origin=(cx, cy, zc), seed=seed)
    w.tag(vis_end=vis_end, no_shadow=1)
    trim, chrome = mats["trim"], mats["chrome"]

    def pr(r, x):
        return (r, x)

    t_prof = [pr(0.60 * R, -0.46 * tw), pr(0.80 * R, -0.52 * tw), pr(0.95 * R, -0.49 * tw), pr(R, -0.32 * tw), pr(R, 0.32 * tw),
              pr(0.95 * R, 0.49 * tw), pr(0.80 * R, 0.52 * tw), pr(0.60 * R, 0.46 * tw)]
    w.revolve(t_prof, (cx, cy, zc), mat=trim, tint=hexc("#101113"), segs=28, closed=True)
    r_prof = [pr(0.025 * R, 0.47 * tw), pr(0.17 * R, 0.47 * tw), pr(0.21 * R, 0.37 * tw), pr(0.55 * R, 0.37 * tw), pr(0.62 * R, 0.46 * tw),
              pr(0.63 * R, 0.30 * tw), pr(0.58 * R, -0.3 * tw), pr(0.025 * R, -0.3 * tw)]
    w.revolve(r_prof, (cx, cy, zc), mat=chrome, tint=hexc(rim), segs=28, closed=True)
    for k in range(spokes):
        a = 2 * math.pi * k / spokes + 0.3
        d = Vector((0, math.cos(a), math.sin(a)))
        c0 = Vector((cx + 0.46 * tw, cy, zc))
        w.bar(c0 + d * 0.17 * R, c0 + d * 0.60 * R, 0.11 * R, 0.03, mat=chrome, tint=hexc(spoke), up=(1, 0, 0), bevel=0.003)
    if ring is not None:
        for sx in (-1, 1):
            w.torus(0.665 * R, 0.0085, (cx + sx * 0.47 * tw, cy, zc), rot=(0, 90, 0), mat=ring, segs=28, sides=4)
    return w


def lamp_rig(L, ze, underglow_rgb, head_x=0.0, head_z=None, fill_z=2.3, head_energy=2.4):
    """The lights a model ships (post_import.gd turns the empties into real Light3D): the headlight spot, the underglow pool and a fill that lights only the model."""
    rig = []
    hz = ze - 0.2 if head_z is None else head_z
    rig.append(light("Headlights", (head_x, L / 2 - 0.1, hz), "spot", (1.0, 0.93, 0.78), head_energy, 22.0, direction=(0, 1, -0.07), angle=36.0,
                     attenuation=1.1, spot_attenuation=1.0, fade=(32, 14), group="headlight"))
    ugc = tuple(min(1.0, c * 1.6 + 0.05) for c in underglow_rgb)
    rig.append(light("UnderglowLight", (0.0, 0.0, 0.10), "omni", ugc, 1.3, 4.6, attenuation=1.5, fade=(28, 12), group="underglow"))
    rig.append(light("Fill", (0.0, 0.1, fill_z), "omni", (0.7, 0.82, 1.0), 1.0, 6.5, mask="own", attenuation=1.1, fade=(36, 14)))
    return rig
