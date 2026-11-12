"""The lofted car body of Cars v2: one watertight shell built from cross-section rings along the car's length.

A ring (cross-section) is a closed loop of points, right half then mirrored left half:
  upper path   a superellipse quadrant from the top centre (roof / hood / deck) down to the belt line (x = a cos^p t, z = zb + b sin t)
               b is the height of the greenhouse above the belt (a small constant b_hood on the bonnet and the boot, so the same formula gives
               a rounded bonnet edge there and a cabin with tumblehome in the middle)
  lower path   from the belt to the sill: a near vertical wall that tucks in at the bottom (x = xs + (a - xs)(1 - u^m)^(1/m))
  under path   the wheel house ceiling, the inner wall and the floor
The wheel arches are cut by raising the lower edge of the side wall (z_se(y)) along the arch circle, so no boolean is needed.
Windows are quads of the loft itself (windscreen, rear window, side lights) with their own material, so the interior can be seen through them.
The nose and the tail are closed with scaled copies of the last ring and a flat fan.
"""
import math

import numpy as np

from . import kit
from .kit import Mesh, fillet_profile, lerp, pchip, smoothstep

# ring resolution per level of detail
LODS = {
    0: dict(th=[90, 80, 70, 58, 46, 34, 22, 10, 0], tl=[0.14, 0.30, 0.48, 0.65, 0.80, 0.92, 1.0], step=0.34, arch=[-90, -62, -34, 0, 34, 62, 90],
            win=(3, 7), glass_top=2, cap=3),
    1: dict(th=[90, 66, 22, 0], tl=[0.5, 1.0], step=1.1, arch=[-90, 0, 90], win=(1, 2), glass_top=1, cap=2),
    2: dict(th=[90, 50, 0], tl=[1.0], step=1.4, arch=[], win=(1, 2), glass_top=1, cap=1, under=False),
    3: dict(th=[90, 62, 34, 0], tl=[1.0], step=0.95, arch=[], win=(1, 3), glass_top=1, cap=2, under=False),        # the near traffic car (about 500 triangles with its wheels)
}


class Profiles:
    """The longitudinal dimension functions of one car definition `d` (see archetypes.py)."""

    def __init__(self, d):
        self.d = d
        L = d["L"]
        self.Lh = L * 0.5
        pl = fillet_profile(d["top"], step=0.01)[::-1]           # keys run front -> rear, the lookup wants y ascending
        order = np.argsort(pl[:, 0], kind="stable")
        self._top = pl[order]
        belt = d["belt"]
        if isinstance(belt, (list, tuple)):
            belt = sorted(belt)                                   # the archetypes list the keys from the nose to the tail; the interpolation wants y ascending
            self._belt = pchip([k[0] for k in belt], [k[1] for k in belt])
        else:
            self._belt = lambda y, v=belt: np.full_like(np.asarray(y, dtype=float), v)
        self.b_hood = d.get("b_hood", 0.07)
        self.axles = [d["axle_f"], d["axle_r"]] + list(d.get("extra_axles", []))
        self.r_arch = [d["R"] + d.get("arch_gap", 0.06)] * 2
        if "R_r" in d:
            self.r_arch[1] = d["R_r"] + d.get("arch_gap", 0.06)
        self.zc = [d["R"], d.get("R_r", d["R"])]
        for _ in d.get("extra_axles", []):
            self.r_arch.append(self.r_arch[1])
            self.zc.append(self.zc[1])
        if not d.get("arches", True):
            self.axles, self.r_arch, self.zc = [], [], []
        self.flares = d.get("flare", (0.0, 0.0))
        hw = sorted(d.get("half_w_keys") or [])
        self._hw = pchip([k[0] for k in hw], [k[1] for k in hw]) if hw else None
        sk = sorted(d.get("sill_keys") or [])
        self._sill = pchip([k[0] for k in sk], [k[1] for k in sk]) if sk else None

    def ztop(self, y):
        return float(np.interp(y, self._top[:, 0], self._top[:, 1]))

    def belt_cabin(self, y):
        return float(self._belt(y))

    def zb(self, y):
        zt = self.ztop(y)
        return min(self.belt_cabin(y), zt - self.b_hood)

    def plan(self, y):
        """Plan view taper of the half width: 1 in the middle, `end_w` at the tips (squircle corners)."""
        d = self.d
        c = d.get("plan_len", 0.7)
        e = abs(y) - (self.Lh - c)
        if e <= 0.0:
            return 1.0
        u = min(e / c, 1.0)
        ew = d["end_w_f"] if y > 0 else d["end_w_r"]
        return 1.0 - (1.0 - ew) * (1.0 - math.sqrt(max(0.0, 1.0 - u ** 2.2))) ** 1.0

    def half_w(self, y):
        d = self.d
        a = float(self._hw(y)) if self._hw is not None else d["W"] * 0.5
        for i, yw in enumerate(self.axles[:2]):
            f = self.flares[i]
            if f:
                a += f * math.exp(-((y - yw) / 0.5) ** 2)
        return a * self.plan(y)

    def zfloor(self, y):
        d = self.d
        z = d["z_floor"]
        e = abs(y) - (self.Lh - d.get("rise_len", 0.8))
        if e > 0:
            z += d.get("rise", 0.5) * e * e
        return z

    def z_sill(self, y):
        d = self.d
        base = float(self._sill(y)) if self._sill is not None else d["z_sill"]
        return max(base, self.zfloor(y))

    def zse(self, y):
        """Lowest z of the side wall: the sill, or the wheel arch."""
        z = self.z_sill(y)
        for yw, ra, zc in zip(self.axles, self.r_arch, self.zc):
            dd = abs(y - yw)
            if dd < ra:
                z = max(z, zc + math.sqrt(max(ra * ra - dd * dd, 0.0)))
            elif dd < ra + 0.012:
                z = max(z, lerp(zc, self.z_sill(y), (dd - ra) / 0.012))
        return min(z, self.ztop(y) - 0.04)                   # never above the top surface: an arch that breaks through the hood would turn the shell inside out

    def crown(self, y):
        return self.d.get("crown", 0.035)


def make_stations(d, P, lod):
    L = LODS[lod]
    Lh = P.Lh
    cf, cr = d["cap_f"], d["cap_r"]
    hi, lo = Lh - cf, -Lh + cr
    ys = set()
    n = max(2, int(round((hi - lo) / L["step"])))
    for y in np.linspace(lo, hi, n + 1):
        ys.add(round(float(y), 4))
    for yw, ra in zip(P.axles, P.r_arch):
        for ang in L["arch"]:
            ys.add(round(yw + ra * math.sin(math.radians(ang)), 4))
        if lod == 0:
            ys.add(round(yw + ra + 0.012, 4))
            ys.add(round(yw - ra - 0.012, 4))
    for key in ("ws", "rw"):
        if key in d:
            a, b = d[key]
            n2 = 5 if lod == 0 else (2 if lod == 1 else 1)
            for y in np.linspace(a, b, n2 + 1):
                ys.add(round(float(y), 4))
    for a, b in d["windows"]:
        ys.add(round(a, 4))
        ys.add(round(b, 4))
    if lod < 3:
        for a, b in d.get("fx", {}).get("doors", []):
            ys.add(round(a, 4))
            ys.add(round(b, 4))
        ys.add(round(Lh - d.get("bumper_f", 0.5), 4))
        ys.add(round(-Lh + d.get("bumper_r", 0.5), 4))
        if "ws" in d:
            ys.add(round(d["ws"][0], 4))
        if "rw" in d and d["rw"][1] > -8.0:
            ys.add(round(d["rw"][1], 4))
    for k in d["top"][1:-1]:
        if lod < 2:
            ys.add(round(float(k[0]), 4))
    ys = sorted(y for y in ys if lo - 1e-6 <= y <= hi + 1e-6)
    out = []
    for y in ys:
        if out and y - out[-1] < 0.0095 and not (lod == 0 and y - out[-1] > 0.0115):
            continue
        out.append(y)
    return out


def ring_half(d, P, y, lod):
    """Right half ring (x >= 0) at station y: array (K,3) from the top centre to the inner wall of the wheel house; also the slot roles."""
    L = LODS[lod]
    a = P.half_w(y)
    zt = P.ztop(y)
    zb = P.zb(y)
    b = max(zt - zb, 1e-4)
    zse = P.zse(y)
    zfl = P.zfloor(y)
    g = float(smoothstep(P.b_hood * 1.4, P.b_hood * 3.5, b))
    p = lerp(d.get("p_hood", 0.15), d.get("p_gh", 0.3), g)
    crown = P.crown(y)
    pts = []
    for th in L["th"]:
        t = math.radians(th)
        x = a * (max(math.cos(t), 0.0) ** p) if th < 90 else 0.0
        s = math.sin(t)
        z = zb + (b - crown * (x / a) ** 2) * s
        pts.append((x, z))
    xs = a - d.get("tuck", 0.075) - d.get("sill_in", 0.0)
    m = d.get("m_lo", 2.6)
    bulge = d.get("bulge", 0.006)
    for u in L["tl"]:
        x = xs + (a - xs) * (1.0 - u ** m) ** (1.0 / m) + bulge * math.sin(math.pi * min(u, 1.0))
        z = zb - (zb - zse) * u
        pts.append((x, z))
    if L.get("under", True):
        xi = d["track"] * 0.5 - d["tyre_w"] * 0.5 - 0.045
        pts.append((xi, zse))
        pts.append((xi, zfl))
    return np.array([(x, 0.0, z) for x, z in pts]), a


def build_body(d, lod=0, with_glass=True):
    """The shell as a Mesh with face materials 'Paint', 'Glass', 'Under', 'Trim'. Also returns the info dict (station list, ring size, slot indices)."""
    P = Profiles(d)
    L = LODS[lod]
    ys = make_stations(d, P, lod)
    halves = []
    for y in ys:
        h, a = ring_half(d, P, y, lod)
        h[:, 1] = y
        halves.append(h)
    halves = np.array(halves)                    # (S, K, 3)
    S, K = halves.shape[:2]

    def full(h):                                 # right half down, then the left half back up (the top centre appears once)
        left = h[::-1][:-1].copy()
        left[:, 0] *= -1.0
        return np.vstack([h, left])

    rings = [full(h) for h in halves]
    # end caps: scaled copies of the first / last ring, closed with a flat fan
    nc = L["cap"]
    cap_rings_f, cap_rings_r = [], []
    n_caps_f = nc
    for ring_end, depth, sign, out, cap_s in ((rings[-1], d["cap_f"], 1.0, cap_rings_f, d.get("cap_s_f", d.get("cap_s", (0.78, 0.82)))),
                                              (rings[0], d["cap_r"], -1.0, cap_rings_r, d.get("cap_s_r", d.get("cap_s", (0.78, 0.82))))):
        c = ring_end.mean(axis=0)
        for i in range(1, nc + 1):
            u = i / nc
            e = 1.0 - math.sqrt(max(0.0, 1.0 - u * u))
            sx = lerp(1.0, cap_s[0], e)
            sz = lerp(1.0, cap_s[1], e)
            r = ring_end.copy()
            r[:, 0] = c[0] + (r[:, 0] - c[0]) * sx
            r[:, 2] = c[2] + (r[:, 2] - c[2]) * sz
            r[:, 1] = ring_end[:, 1] + sign * depth * math.sin(u * math.pi * 0.5)
            out.append(r)
    all_rings = cap_rings_r[::-1] + rings + cap_rings_f
    G = np.array(all_rings)                       # (S+caps, N, 3)
    n_r = len(all_rings[0])
    # materials per quad: (station interval i, ring slot j)
    y_all = [r[0, 1] for r in all_rings]
    kt = L["glass_top"]
    w0, w1 = L["win"]
    ws = d.get("ws", (9.0, 9.0))
    rw = d.get("rw", (9.0, 9.0))
    wins = d["windows"]
    n_cap_r = len(cap_rings_r)
    trim_slot = d.get("trim_slot", 0)          # lower wall slots from this one on (counted from the belt) are black plastic cladding: a clean line that follows the wheel arches
    fm = np.empty((len(all_rings) - 1, n_r), dtype=object)

    def interval_in(ya, yb, lo_, hi_):
        return min(ya, yb) >= min(lo_, hi_) - 1e-4 and max(ya, yb) <= max(lo_, hi_) + 1e-4

    for i in range(len(all_rings) - 1):
        ya, yb = y_all[i], y_all[i + 1]
        in_ws = interval_in(ya, yb, ws[0], ws[1])
        in_rw = interval_in(ya, yb, rw[0], rw[1])
        in_win = any(interval_in(ya, yb, a_, b_) for a_, b_ in wins)
        zmid = 0.5 * (all_rings[i][:, 2] + all_rings[i + 1][:, 2])
        for j in range(n_r):
            jj = j if j < K else (2 * K - 2 - j)          # slot on the right half this quad mirrors
            # the quad between ring point j and j+1 (the loop wraps); on the left half slot jj-1
            if j >= K - 1 and j < 2 * K - 2:
                s0 = 2 * K - 2 - j - 1
            elif j >= 2 * K - 2:
                s0 = 0
            else:
                s0 = j
            mat = "Paint"
            if with_glass:
                if s0 < kt and (in_ws or in_rw):
                    mat = "Glass"
                elif w0 <= s0 < w1 and in_win:
                    mat = "Glass"
            if "bed" in d and s0 < kt + 1 and interval_in(ya, yb, d["bed"][0], d["bed"][1]):
                mat = "None"                                   # the open load bed of a pickup: the top of the shell is left out
            n_th = len(L["th"])
            n_lo = len(L["tl"])
            if s0 >= n_th - 1 + n_lo:                    # arch ceiling, inner wall: dark
                mat = "Under"
            elif trim_slot > 0 and s0 >= n_th - 1 + (n_lo - trim_slot) and s0 < n_th - 1 + n_lo:
                mat = "Trim"
            fm[i, j] = mat
    # body parts (uv2 of the vertices; the shader collapses a lost part): 1 front bumper, 2 rear bumper, 3 hood, 4 trunk lid, 5 / 6 front doors (left / right), 7 / 8 rear doors
    fp = np.zeros((len(all_rings) - 1, n_r), dtype=int)
    Lh = P.Lh
    bf, br = d.get("bumper_f", 0.5), d.get("bumper_r", 0.5)
    th = L["th"]
    low_slot = next((k for k, t_ in enumerate(th) if t_ < 50), len(th) - 1)          # slots below the hood edge belong to the bumper (and the doors)
    hood_y = (Lh - bf, d["ws"][0] if "ws" in d else Lh - bf - 1.0)
    trunk_y = (-Lh + br, d["rw"][1] if ("rw" in d and d["rw"][1] > -8.0 and "bed" not in d) else -Lh + br)
    doors = d.get("fx", {}).get("doors", [])
    for i in range(len(all_rings) - 1):
        ym = 0.5 * (y_all[i] + y_all[i + 1])
        for j in range(n_r):
            if j >= K - 1 and j < 2 * K - 2:
                s0 = 2 * K - 3 - j
                right = False
            elif j >= 2 * K - 2:
                s0 = 0
                right = False
            else:
                s0 = j
                right = True
            if j == K - 1:
                right = True
            part = 0
            if s0 < low_slot:
                if hood_y[0] > ym > hood_y[1]:
                    part = 3
                elif trunk_y[1] > ym > trunk_y[0]:
                    part = 4
            if ym > Lh - bf and s0 >= low_slot:
                part = 1
            if ym > Lh - bf and s0 < low_slot and i >= len(all_rings) - 1 - n_caps_f:
                part = 1
            if ym < -Lh + br and s0 >= low_slot:
                part = 2
            if ym < -Lh + br and s0 < low_slot and i < n_cap_r:
                part = 2
            if lod < 2 and fm[i, j] in ("Paint", "Glass", "Trim") and w0 <= s0 < len(th) - 1 + len(L["tl"]) - 1 + 0:
                for di, (yf_, yr_) in enumerate(doors[:2]):
                    if min(yf_, yr_) < ym < max(yf_, yr_):
                        part = (6 if right else 5) if di == 0 else (8 if right else 7)
            fp[i, j] = part
    # bottom closing quad between the two inner wall bottoms is part of the wrap (slot K-1 -> K): marked Under above
    def build_shell(flip_grid):
        m = Mesh()
        m.add_grid(G, "Paint", wrap_v=True, flip=flip_grid, fmat=fm, fpart=fp)
        return m

    def face_dir(mm):
        Pm_, F_ = mm.P, mm.F
        nn = np.cross(Pm_[F_[:, 1]] - Pm_[F_[:, 0]], Pm_[F_[:, 2]] - Pm_[F_[:, 0]])
        return nn, F_, Pm_

    mesh = build_shell(False)
    nn, Fq, Pm = face_dir(mesh)
    top_i = int(np.argmax(Pm[Fq[:, 0]][:, 2]))
    if nn[top_i, 2] < 0:                                     # the roof must face up
        mesh = build_shell(True)
    # nose and tail faces: flat fans whose normals must point out of the car (+Y at the nose, -Y at the tail)
    for ring_end, want in ((all_rings[-1], 1.0), (all_rings[0], -1.0)):
        c = ring_end.mean(axis=0)
        ring_fan = ring_end.copy()
        ring_fan[:, 1] += want * 4e-5          # its own smoothing group (the welded position key is 1e-5): the end face stays flat instead of showing a pinched X of shared corner normals
        c = c + np.array([0.0, want * 4e-5, 0.0])
        fan = kit.poly_fan(ring_fan, "Paint", center=c)
        Pf, Ff = fan.P, fan.F
        nf = np.cross(Pf[Ff[:, 1]] - Pf[Ff[:, 0]], Pf[Ff[:, 2]] - Pf[Ff[:, 0]])
        if (nf[:, 1] * want).sum() < 0:
            fan = kit.poly_fan(ring_fan, "Paint", center=c, flip=True)
        fan.set_part(1 if want > 0 else 2)
        mesh.add_mesh(fan)
    info = dict(P=P, ys=ys, K=K, n_ring=n_r, rings=G, lod=lod, n_cap_r=n_cap_r, n_up=len(L["th"]), n_lo=len(L["tl"]))
    return mesh, info
