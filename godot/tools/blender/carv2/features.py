"""Surface details of Cars v2: lamps, grille, bumper intakes, mirrors, handles, shut lines, exhausts, roof gear.

Everything is built from thin patches and ribbons that are projected onto the lofted shell with ray casts (kit.Surface), so a lamp follows the curve of the nose
and the same code serves every archetype. Details are Mesh objects with material 'Details'; the Details shader reads uv.x as the material class (kit.D_*)
and the vertex colour as albedo.
"""
import math

import numpy as np

from . import kit
from .kit import (D_BLUE, D_CHROME, D_FABRIC, D_HEAD, D_IND, D_PAINTED, D_PLASTIC, D_PLATE, D_RED, D_REV, D_RUBBER, D_SIGN, D_TAIL, D_UNDER, D_WHITE_LAMP,
                  Mesh, unit)

BLACK = (0.018, 0.018, 0.020)
DARK = (0.008, 0.008, 0.010)
CHROME = (0.62, 0.64, 0.68)
HEAD_COL = (0.82, 0.86, 0.95)
TAIL_COL = (0.55, 0.015, 0.02)
IND_COL = (0.9, 0.38, 0.03)
REV_COL = (0.8, 0.8, 0.85)
WHITE = (0.78, 0.78, 0.80)


class Detailer:
    def __init__(self, d, surf, lod=0):
        self.d = d
        self.surf = surf
        self.lod = lod
        self.mesh = Mesh()
        self.anchors = {}          # name -> (x, y, z, rot_euler (x, y, z) in Blender axes)

    # ------------------------------------------------------------------------------------------------------------------ projection
    def _ray(self, plane, u, v):
        s = self.surf
        if plane == "front":
            return s.front(u, v)
        if plane == "rear":
            return s.rear(u, v)
        if plane == "right":
            return s.side(u, v, 1.0)
        if plane == "left":
            return s.side(u, v, -1.0)
        if plane == "top":
            return s.top(u, v)
        raise ValueError(plane)

    def patch(self, outline, plane, code, color, offset=0.004, rings=2, flat=False):
        """A conforming patch inside the 2D outline (a convex loop in the plane's (u, v) frame): a fan with `rings` concentric rings, every vertex on the shell + offset."""
        pts = np.asarray(outline, dtype=np.float64)
        c = pts.mean(axis=0)
        n = len(pts)
        rings = 1 if self.lod >= 1 else rings
        levels = [c[None, :]] + [c + (pts - c) * (k / rings) for k in range(1, rings + 1)]
        P, N = [], []
        ok = True
        for lv in levels:
            for u, v in lv:
                h = self._ray(plane, float(u), float(v))
                if h is None:
                    ok = False
                    break
                P.append(h[0] + h[1] * offset)
                N.append(h[1])
            if not ok:
                break
        if not ok:
            return None
        P = np.array(P)
        N = np.array(N)
        F = []
        for j in range(n):
            F.append([0, 1 + j, 1 + (j + 1) % n, 1 + (j + 1) % n])
        for k in range(1, rings):
            a0 = 1 + (k - 1) * n
            b0 = 1 + k * n
            for j in range(n):
                j1 = (j + 1) % n
                F.append([a0 + j, b0 + j, b0 + j1, a0 + j1])
        m = Mesh().add(P, np.array(F), "Details", col=(*color, 1.0), uv=np.tile([code, 0.0], (len(P), 1)))
        # face the way the shell faces
        Pm = m.P
        Fm = m.F.copy()
        A, B, C = Pm[Fm[:, 0]], Pm[Fm[:, 1]], Pm[Fm[:, 2]]
        fn = np.cross(B - A, C - A)
        nm = N[Fm[:, 0]]
        flip = (fn * nm).sum(axis=1) < 0
        Fm[flip] = Fm[flip][:, ::-1]
        out = Mesh().add(Pm, Fm, "Details", col=m.C, uv=m.U)
        self.mesh.add_mesh(out)
        return out

    def ribbon(self, pts2d, plane, width, code, color, offset=0.003, closed=False):
        """A thin strip along a polyline given in the plane's (u, v) frame, projected onto the shell."""
        if self.lod >= 2:
            return None
        P, N = [], []
        for u, v in pts2d:
            h = self._ray(plane, float(u), float(v))
            if h is None:
                continue
            P.append(h[0] + h[1] * offset)
            N.append(h[1])
        if len(P) < 2:
            return None
        P = np.array(P)
        N = np.array(N)
        L, R = [], []
        n = len(P)
        for i in range(n):
            a = P[max(i - 1, 0)]
            b = P[min(i + 1, n - 1)]
            t = unit(b - a)
            side = unit(np.cross(t, N[i]))
            L.append(P[i] - side * width * 0.5)
            R.append(P[i] + side * width * 0.5)
        G = np.stack([np.array(L), np.array(R)], axis=1)           # (n, 2, 3)
        m = Mesh().add_grid(G, "Details", col=(*color, 1.0), uv=np.tile([code, 0.0], (n * 2, 1)).reshape(n, 2, 2))
        Pm = m.P
        Fm = m.F.copy()
        A, B, C = Pm[Fm[:, 0]], Pm[Fm[:, 1]], Pm[Fm[:, 2]]
        fn = np.cross(B - A, C - A)
        nm = np.repeat(N, 2, axis=0)[Fm[:, 0]]
        flip = (fn * nm).sum(axis=1) < 0
        Fm[flip] = Fm[flip][:, ::-1]
        out = Mesh().add(Pm, Fm, "Details", col=m.C, uv=m.U)
        self.mesh.add_mesh(out)
        return out

    def add(self, mesh, code=None, color=None):
        if code is not None or color is not None:
            mesh.style(code, color)
        self.mesh.add_mesh(mesh)
        return mesh

    def face_range(self, plane):
        """(z_low, z_high) of the nose ('front') or tail ('rear') face at the centre line: the heights whose ray from the end hits the end cap, not the bonnet or the boot."""
        key = ("face", plane)
        if key in self.__dict__:
            return self.__dict__[key]
        Lh = self.d["L"] * 0.5
        zs = []
        z = 0.06
        top = max(k[1] for k in self.d["top"]) + 0.2
        while z < top:
            h = self._ray(plane, 0.0, z)
            if h is not None and abs(h[0][1]) > Lh - 0.16:
                zs.append(z)
            z += 0.02
        rng = (min(zs), max(zs)) if zs else (0.3, 0.7)
        self.__dict__[key] = rng
        return rng

    def face_half_width(self, plane):
        """Half width of the flat part of the nose / tail face at mid height (where a ray from the end still hits the end cap, not the flank)."""
        key = ("fhw", plane)
        if key in self.__dict__:
            return self.__dict__[key]
        Lh = self.d["L"] * 0.5
        z = self.fz(plane, 0.5)
        hw = 0.3
        x = 0.0
        while x < self.d["W"] * 0.6:
            h = self._ray(plane, x, z)
            if h is not None and abs(h[0][1]) > Lh - 0.16:
                hw = x
            x += 0.02
        self.__dict__[key] = hw
        return hw

    def fit_x(self, outline, plane, margin=0.96):
        """Squeeze an outline's x coordinates (for the +x side) so that it stays on the flat end face."""
        hw = self.face_half_width(plane)
        mx = max(abs(p[0]) for p in outline)
        k = min(1.0, hw * margin / max(mx, 1e-6))
        return [(p[0] * k, p[1]) for p in outline]

    def roof_line(self, x, y0, y1, lift=0.03, n=12):
        """Points along the roof surface at lateral position x from y0 to y1 (a rail, a rack), lifted by `lift`."""
        pts = []
        for i in range(n + 1):
            y = y0 + (y1 - y0) * i / n
            h = self.surf.top(x, y)
            if h is not None:
                pts.append(h[0] + np.array([0.0, 0.0, lift]))
        return pts

    def fz(self, plane, f):
        lo, hi = self.face_range(plane)
        return lo + (hi - lo) * f

    def anchor(self, name, pos, rot=(0, 0, 0)):
        self.anchors[name] = (tuple(float(x) for x in pos), tuple(float(x) for x in rot))

    # ------------------------------------------------------------------------------------------------------------------ lamps
    def lamp(self, outline, plane, kind="head", mirror=True, bezel=True, detail=True):
        """A lamp: a dark bezel patch with a lit lens on top. kind = head | tail | ind | rev | blue | red. `outline` is for the +x side (mirrored when `mirror`)."""
        code, col = {"head": (D_HEAD, HEAD_COL), "tail": (D_TAIL, TAIL_COL), "ind": (D_IND, IND_COL), "rev": (D_REV, REV_COL), "blue": (D_BLUE, (0.05, 0.15, 0.95)),
                     "red": (D_RED, (0.9, 0.04, 0.03)), "white": (D_WHITE_LAMP, (0.8, 0.8, 0.8))}[kind]
        sides = [1.0, -1.0] if mirror and plane in ("front", "rear") else [1.0]
        for sgn in sides:
            ol = np.array(outline, dtype=np.float64)
            if sgn < 0:
                ol = ol.copy()
                ol[:, 0] *= -1.0
                ol = ol[::-1]
            if bezel and self.lod == 0:
                c = ol.mean(axis=0)
                self.patch(c + (ol - c) * 1.1, plane, D_PLASTIC, DARK, offset=0.003, rings=1)
            self.patch(ol, plane, code, col, offset=0.006, rings=2)
            if self.lod == 0 and detail and kind in ("head", "tail"):
                c = ol.mean(axis=0)
                if kind == "head":                                 # a dark reflector bowl inside the lens and a bright strip along the top edge
                    self.patch(c + (ol - c) * 0.5, plane, D_PLASTIC, (0.01, 0.01, 0.014), offset=0.0085, rings=1)
                    top = ol[np.argsort(ol[:, 1])[-3:]]
                    top = top[np.argsort(top[:, 0])]
                    self.ribbon([tuple(p) for p in top], plane, 0.012, kit.D_WHITE_LAMP, (0.9, 0.95, 1.0), offset=0.0095)
                else:                                              # a deeper red inner lens, an amber indicator corner and a white reverse corner
                    self.patch(c + (ol - c) * 0.55, plane, D_TAIL, (0.22, 0.004, 0.006), offset=0.0085, rings=1)
                    ci = ol[np.argmax(ol[:, 0])]
                    self.patch([tuple(c + (ci - c) * 0.9 + np.array(o)) for o in ((-0.05, 0.0), (0.0, 0.03), (0.04, 0.0), (0.0, -0.03))], plane, D_IND, IND_COL, offset=0.0095, rings=1)
                    cr = ol[np.argmin(ol[:, 0])]                         # the reverse lamp is the inner corner of the cluster
                    self.patch([tuple(c + (cr - c) * 0.72 + np.array(o)) for o in ((-0.05, -0.035), (0.05, -0.035), (0.05, 0.035), (-0.05, 0.035))], plane, kit.D_REV, REV_COL, offset=0.0095, rings=1)

    def grille(self, x0, x1, z0, z1, bars=3, plane="front", chrome=True, curve=0.0):
        """A dark grille panel with `bars` horizontal slats."""
        ol = [(x0, z0), (x1, z0 + curve), (x1, z1), (x0, z1 - curve)] if False else [(-x1, z0), (x1, z0), (x1 * 0.96, z1), (-x1 * 0.96, z1)]
        self.patch(ol, plane, D_PLASTIC, DARK, offset=0.004, rings=2)
        if self.lod == 0:
            for k in range(bars):
                zz = z0 + (z1 - z0) * (k + 1) / (bars + 1)
                self.ribbon([(-x1 * 0.94, zz), (x1 * 0.94, zz)], plane, 0.012, D_CHROME if chrome else D_PLASTIC, CHROME if chrome else BLACK, offset=0.008)
            self.ribbon([(-x1, z0), (x1, z0), (x1 * 0.96, z1), (-x1 * 0.96, z1), (-x1, z0)], plane, 0.012, D_CHROME, CHROME, offset=0.007)

    def intake(self, x1, z0, z1, plane="front", slats=2):
        ol = [(-x1, z0), (x1, z0), (x1 * 0.93, z1), (-x1 * 0.93, z1)]
        self.patch(ol, plane, D_PLASTIC, DARK, offset=0.004, rings=2)
        if self.lod == 0:
            for k in range(slats):
                zz = z0 + (z1 - z0) * (k + 1) / (slats + 1)
                self.ribbon([(-x1 * 0.9, zz), (x1 * 0.9, zz)], plane, 0.012, D_PLASTIC, BLACK, offset=0.007)

    # ------------------------------------------------------------------------------------------------------------------ side details
    def mirrors(self, y, z, off=0.10, color=None, scale=1.0):
        """Door mirrors: a painted housing on a stalk, a glass face looking back."""
        if self.lod >= 2:
            return
        a = self.d["W"] * 0.5
        for sgn in (1.0, -1.0):
            x = sgn * (a + off)
            hou = kit.rbox((x, y, z), (0.12 * scale, 0.20 * scale, 0.10 * scale), 0.035 * scale, 1, "Details")
            hou.style(D_PAINTED, (0.5, 0.5, 0.5))
            self.mesh.add_mesh(hou)
            if self.lod == 0:
                stalk = kit.cylinder((sgn * (a - 0.03), y + 0.06, z - 0.03), (sgn * (a + off - 0.05), y + 0.03, z - 0.01), 0.018, 0.016, seg=6, mat="Details")
                stalk.style(D_PLASTIC, BLACK)
                self.mesh.add_mesh(stalk)
                glass = kit.quad((x - sgn * 0.05, y - 0.101, z - 0.04), (x - sgn * 0.05, y - 0.101, z + 0.04), (x + sgn * 0.05, y - 0.101, z + 0.04), (x + sgn * 0.05, y - 0.101, z - 0.04), "Details")
                if sgn < 0:
                    glass = glass.flipped()
                glass.style(D_CHROME, (0.5, 0.55, 0.6))
                self.mesh.add_mesh(glass)

    def handles(self, ys, z, color=CHROME, painted=False):
        """Door handles at the station ys (a list), height z, both sides."""
        if self.lod > 0:
            return
        for y in ys:
            for sgn in (1.0, -1.0):
                h = self.surf.side(y, z, sgn)
                if h is None:
                    continue
                p, n = h
                hd = kit.rbox((0, 0, 0), (0.026, 0.15, 0.028), 0.01, 1, "Details")
                hd.style(D_PAINTED if painted else D_CHROME, (0.5, 0.5, 0.5) if painted else color)
                hd = hd.xformed(kit.trans(*(p + n * 0.012)))
                hd.set_part((6 if sgn > 0 else 5) if y > -0.2 else (8 if sgn > 0 else 7))        # the handle goes with its door
                self.mesh.add_mesh(hd)

    def side_lines(self, doors, z_belt, z_sill, color=DARK, width=0.007):
        """Door shut lines (front edge, rear edge, along the sill and the belt) for the doors [(y_front, y_rear), ...], both sides."""
        if self.lod > 0:
            return
        for sgn in (1.0, -1.0):
            plane = "right" if sgn > 0 else "left"
            for (yf, yr) in doors:
                pts = [(yf, z_sill), (yf, z_belt)]
                self.ribbon(pts, plane, width, D_PLASTIC, color, offset=0.0025)
                pts = [(yr, z_sill), (yr, z_belt)]
                self.ribbon(pts, plane, width, D_PLASTIC, color, offset=0.0025)
                self.ribbon([(yf, z_sill), (yr, z_sill)], plane, width, D_PLASTIC, color, offset=0.0025)

    def exhaust(self, xs, y, z, r=0.04, length=0.14, count=1, spread=0.1, color=CHROME):
        if self.lod >= 2:
            return
        for x in xs:
            for k in range(count):
                xx = x + (k - (count - 1) * 0.5) * spread
                h = self.surf.rear(xx, z)
                if h is not None:
                    y = h[0][1] + 0.01
                tip = kit.cylinder((xx, y + length * 0.3, z), (xx, y - length * 0.75, z), r, r * 0.95, seg=10 if self.lod == 0 else 6, mat="Details", caps=(False, False))
                tip.style(D_CHROME, color)
                self.mesh.add_mesh(tip)
                inner = kit.poly_fan([(xx + r * 0.85 * math.cos(2 * math.pi * i / 8), y - length * 0.75 + 0.002, z + r * 0.85 * math.sin(2 * math.pi * i / 8)) for i in range(8)], "Details")
                inner = inner.flipped() if False else inner
                inner.style(D_UNDER, DARK)
                self.mesh.add_mesh(inner)
