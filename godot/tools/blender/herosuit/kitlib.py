"""Kit bookkeeping of the hero suit: parts with their bone, kind and glow zone, left / right splitting, and the preset sets.

A kit PART is one helpers.Part (one exported mesh node). Its custom properties (glTF extras, read by scripts/characters/hero_suit.gd):
  bone   the source skeleton bone it is rigidly weighted to (spine_02, upperarm_l, calf_r ...)  or  "chain:Sec1,Sec2,Sec3" for the cape (weights by height)
  kind   palette slot of the shader: 6 PLATE (neutral armour, tinted by the plate colour) 7 ACCENT (painted trim) 8 DARK (as baked) 9 FABRIC (suit cloth, tinted) 10 GLOW (emission only)
         11 CANVAS (warm khaki as baked) 12 GOLD (metal trim) 13 CLOTH (cape: double sided cloth with a glowing hem)
  zone   glow zone: 0 core, 1 arms, 2 hands, 3 legs, 4 wings, 5 head
  sets   comma separated suit sets the part belongs to (vanguard, stealth, assault, flight, gilded, phase)
Parts that exist on both sides are built once on the right (+x) with `mirror=True` primitives and split here by the sign of x into NAME_r and NAME_l.
"""
import os
import sys

import bmesh
import bpy  # noqa: F401
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import helpers  # noqa: E402
from helpers import Part  # noqa: E402

K_PLATE, K_ACCENT, K_DARK, K_FABRIC, K_GLOW, K_CANVAS, K_GOLD, K_CLOTH = 6, 7, 8, 9, 10, 11, 12, 13
Z_CORE, Z_ARMS, Z_HANDS, Z_LEGS, Z_WINGS, Z_HEAD = 0, 1, 2, 3, 4, 5
ALL_SETS = "vanguard,stealth,assault,flight"


class Kit:
    def __init__(self):
        self.parts = []                      # finished Parts (props set)
        self.mats = {}

    def mat(self, name, **kw):
        if name not in self.mats:
            self.mats[name] = helpers.make_material(name, **kw)
        return self.mats[name]

    def new(self, name):
        return Part(name, seed=1 + len(self.parts) * 7)

    def done(self, part, bone, kind, zone=0, sets=ALL_SETS, lr=False):
        """Registers `part`. lr=True: it was built on the right with mirror=True; the bone name must end in `_r` (the left twin gets `_l`)."""
        if part.vertex_count() == 0:
            return
        if lr:
            right, left = split_lr(part)
            for side, p in (("r", right), ("l", left)):
                if p.vertex_count() == 0:
                    continue
                self._finish(p, bone[:-2] + "_" + side if bone.endswith("_r") else bone, kind, zone, sets)
        else:
            self._finish(part, bone, kind, zone, sets)

    def _finish(self, p, bone, kind, zone, sets):
        p.props["bone"] = bone
        p.props["kind"] = int(kind)
        p.props["zone"] = int(zone)
        p.props["sets"] = sets
        self.parts.append(p)

    def tri_count(self, sets=None):
        n = 0
        for p in self.parts:
            if sets is None or any(s in p.props["sets"].split(",") for s in sets.split(",")):
                n += p.tri_count()
        return n


def split_lr(part):
    """Splits a part built with mirror=True into the +x half and the -x half (a face belongs to the side its centre lies on): two new Parts named NAME_r / NAME_l."""
    bm = part.bm
    bm.verts.index_update()
    bm.edges.index_update()
    out = []
    for side in (1.0, -1.0):
        p = Part(part.name + ("_r" if side > 0 else "_l"), seed=part.seed)
        p.slots = list(part.slots)
        p.props = dict(part.props)
        vmap = {}
        for f in bm.faces:
            c = f.calc_center_median()
            if (c.x >= 0.0) != (side > 0):
                continue
            vs = []
            for v in f.verts:
                if v.index not in vmap:
                    vmap[v.index] = p.bm.verts.new(v.co.copy())
                vs.append(vmap[v.index])
            try:
                nf = p.bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index = f.material_index
            nf.smooth = f.smooth
            for lo_src, lo_dst in zip(f.loops, nf.loops):
                lo_dst[p.col] = lo_src[part.col]
        for e in bm.edges:                                       # sharp edges stay sharp (the weighted normals keep them)
            if e.smooth:
                continue
            a, b = e.verts
            if a.index in vmap and b.index in vmap:
                ne = p.bm.edges.get((vmap[a.index], vmap[b.index]))
                if ne is not None:
                    ne.smooth = False
        out.append(p)
    bm.free()
    return out[0], out[1]
