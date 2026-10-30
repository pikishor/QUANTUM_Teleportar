"""Helpers for the drone models: ducted fans and rotor parts."""
import math

import bpy  # noqa: F401  (must be imported before mathutils)
from mathutils import Vector

from helpers import Part


def rotor_part(name, hub, radius, blades, mat, tint, seed=1, chord=0.05, pitch=14.0, hub_r=0.035, thickness=0.006):
    """Separate object (origin = hub) so the game can spin it about the up axis."""
    p = Part(name, origin=hub, seed=seed)
    hub = Vector(hub)
    p.cyl(hub_r, 0.03, hub + Vector((0, 0, 0.012)), mat=mat, tint=tint, segs=10, bevel=0.004)
    for k in range(blades):
        a = 2 * math.pi * k / blades
        d = Vector((math.cos(a), math.sin(a), 0))
        length = radius - hub_r * 0.6
        p.box((chord, length, thickness), hub + d * (hub_r * 0.6 + length / 2), rot=(0, pitch, math.degrees(a) - 90), mat=mat,
              tint=tint, top=(1.0, 1.0), bevel=0.0015, sharp=60.0)
    return p


def ducted_fan(body, c, radius, duct_mat, duct_tint, strut_mat, strut_tint, glow_mat=None, height=0.09, lip=0.022,
               segs=26, struts=3, hub_r=0.05, hub_mat=None, hub_tint=(1, 1, 1)):
    """Static part of a ducted fan: shroud ring, motor hub, stator struts, optional glow ring underneath."""
    c = Vector(c)
    body.torus(radius, lip, c, mat=duct_mat, tint=duct_tint, segs=segs, sides=6, rz=height / 2)
    hm = hub_mat or strut_mat
    body.cyl(hub_r, height * 0.9, c + Vector((0, 0, -0.005)), mat=hm, tint=hub_tint if hub_mat else strut_tint, segs=12, bevel=0.005)
    for k in range(struts):
        a = 2 * math.pi * k / struts + math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        body.bar(c + d * hub_r * 0.8, c + d * (radius - 0.01), 0.014, 0.02, mat=strut_mat, tint=strut_tint, up=(0, 0, 1))
    if glow_mat is not None:
        body.torus(radius - 0.012, 0.0075, c + Vector((0, 0, -height / 2 + 0.002)), mat=glow_mat, segs=segs, sides=4)
