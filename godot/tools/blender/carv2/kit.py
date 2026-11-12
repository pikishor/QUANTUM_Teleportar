"""Geometry kit of the Cars v2 generator (numpy only, plus bpy/mathutils for the BVH and the final export).

Conventions (as every model of this project, see ../README.md): 1 unit = 1 m, origin on the ground in the middle of the car,
the nose points +Y in Blender (the glTF exporter turns that into -Z in Godot), +X is the car's right, +Z is up.

`Mesh` is a quad soup with shared vertices: faces are rows of four vertex indices (a triangle repeats its last index), every face has a
material name, every vertex has an RGBA colour and two UV sets. The primitives below return Meshes; `Mesh.weld()` merges coincident vertices,
`finalize()` triangulates, computes smooth normals with an angle threshold (hard edges split the vertices) and returns the per-material
buffers that `export.py` turns into Blender meshes.
"""
import math

import numpy as np


# Details shader material classes (uv.x of a Details vertex, read by assets/shaders/car_details.gdshader)
D_PLASTIC, D_CHROME, D_FABRIC, D_LEATHER, D_HEAD, D_TAIL, D_IND, D_REV, D_BLUE, D_RED, D_UNDER, D_PAINTED, D_PLATE, D_SCREEN, D_SIGN, D_RUBBER, D_GLOW, D_WHITE_LAMP = range(18)

# ---------------------------------------------------------------------------------------------------------------------------- maths
def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]], dtype=np.float64)


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s, 0], [0, 1, 0, 0], [-s, 0, c, 0], [0, 0, 0, 1]], dtype=np.float64)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0, 0], [s, c, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]], dtype=np.float64)


def trans(x, y=None, z=None):
    if y is None:
        x, y, z = x
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def scl(x, y=None, z=None):
    if y is None:
        y = z = x
    return np.diag([x, y, z, 1.0])


def apply(m, P):
    P = np.asarray(P, dtype=np.float64)
    return P @ m[:3, :3].T + m[:3, 3]


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def hexlin(h):
    """'#rrggbb' sRGB -> linear rgb tuple."""
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def pchip(xs, ys):
    """Monotone cubic interpolation through (xs, ys) (xs ascending). Returns f(x) (clamped at both ends)."""
    xs = np.asarray(xs, dtype=np.float64)
    ys = np.asarray(ys, dtype=np.float64)
    h = np.diff(xs)
    d = np.diff(ys) / h
    m = np.zeros(len(xs))
    if len(xs) == 2:
        m[:] = d[0]
    else:
        for i in range(1, len(xs) - 1):
            if d[i - 1] * d[i] <= 0.0:
                m[i] = 0.0
            else:
                w1 = 2.0 * h[i] + h[i - 1]
                w2 = h[i] + 2.0 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        m[0] = ((2.0 * h[0] + h[1]) * d[0] - h[0] * d[1]) / (h[0] + h[1])
        if m[0] * d[0] <= 0.0:
            m[0] = 0.0
        m[-1] = ((2.0 * h[-1] + h[-2]) * d[-1] - h[-1] * d[-2]) / (h[-1] + h[-2])
        if m[-1] * d[-1] <= 0.0:
            m[-1] = 0.0

    def f(x):
        x = np.asarray(x, dtype=np.float64)
        xc = np.clip(x, xs[0], xs[-1])
        i = np.clip(np.searchsorted(xs, xc, side="right") - 1, 0, len(xs) - 2)
        t = (xc - xs[i]) / h[i]
        t2, t3 = t * t, t * t * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1]
    return f


def fillet_profile(keys, step=0.01):
    """A polyline with rounded corners. keys = [(a, b, radius), ...]; returns an (n, 2) array of dense points (quadratic Bezier fillets)."""
    pts = [np.array(k[:2], dtype=np.float64) for k in keys]
    rad = [float(k[2]) if len(k) > 2 else 0.0 for k in keys]
    out = [pts[0]]
    for i in range(1, len(pts) - 1):
        p0, p1, p2 = pts[i - 1], pts[i], pts[i + 1]
        r = rad[i]
        d0 = p0 - p1
        d1 = p2 - p1
        l0, l1 = np.linalg.norm(d0), np.linalg.norm(d1)
        if r <= 1e-6 or l0 < 1e-9 or l1 < 1e-9:
            out.append(p1)
            continue
        u0, u1 = d0 / l0, d1 / l1
        ang = math.acos(np.clip(np.dot(u0, u1), -1.0, 1.0))
        if ang > math.pi - 1e-3:
            out.append(p1)
            continue
        t = min(r / max(math.tan(ang * 0.5), 1e-6), 0.48 * l0, 0.48 * l1)
        a = p1 + u0 * t
        b = p1 + u1 * t
        n = max(4, int(abs(math.pi - ang) * t / step * 1.5))
        for s in np.linspace(0.0, 1.0, n):
            out.append((1 - s) ** 2 * a + 2 * s * (1 - s) * p1 + s * s * b)
    out.append(pts[-1])
    return np.array(out)


def resample_profile(pts, step=0.01):
    """Resample a polyline to evenly spaced points (for lookups)."""
    pts = np.asarray(pts, dtype=np.float64)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n = max(2, int(s[-1] / step))
    t = np.linspace(0.0, s[-1], n)
    return np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], axis=1)


# ---------------------------------------------------------------------------------------------------------------------------- mesh
class Mesh:
    """Quad soup. P (n,3) positions, C (n,4) RGBA, U (n,2) uv0, U2 (n,2) uv1; F (m,4) faces, Fm (m,) material index into `mats`."""

    def __init__(self):
        self._P, self._C, self._U, self._U2, self._F, self._Fm, self._Fp = [], [], [], [], [], [], []
        self.mats = []
        self.n = 0

    def mat_id(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    @property
    def P(self):
        return np.concatenate(self._P) if self._P else np.zeros((0, 3))

    @property
    def C(self):
        return np.concatenate(self._C) if self._C else np.zeros((0, 4))

    @property
    def U(self):
        return np.concatenate(self._U) if self._U else np.zeros((0, 2))

    @property
    def U2(self):
        return np.concatenate(self._U2) if self._U2 else np.zeros((0, 2))

    @property
    def F(self):
        return np.concatenate(self._F) if self._F else np.zeros((0, 4), np.int64)

    @property
    def Fm(self):
        return np.concatenate(self._Fm) if self._Fm else np.zeros((0,), np.int64)

    @property
    def Fp(self):
        return np.concatenate(self._Fp) if self._Fp else np.zeros((0,), np.int64)

    def add(self, P, F, mat, col=None, uv=None, uv2=None, fmat=None, part=0, fpart=None):
        """Append vertices P (k,3) and faces F (j,4 or j,3; indices local to P). `mat` a material name, or `fmat` a list of names per face.
        `part` / `fpart`: body part id of the faces (0 = the shell; 1 front bumper, 2 rear bumper, 3 hood, 4 trunk, 5 / 6 front doors left / right, 7 / 8 rear doors): a part
        is a separate vertex group on export (uv2.x = id / 32), so the shader can move it away."""
        P = np.asarray(P, dtype=np.float64).reshape(-1, 3)
        F = np.asarray(F, dtype=np.int64)
        if F.ndim == 1:
            F = F.reshape(1, -1)
        if F.shape[1] == 3:
            F = np.concatenate([F, F[:, 2:3]], axis=1)
        k = len(P)
        if col is None:
            col = np.tile(np.array([1.0, 1.0, 1.0, 1.0]), (k, 1))
        else:
            col = np.asarray(col, dtype=np.float64)
            if col.ndim == 1:
                col = np.tile(col, (k, 1))
            if col.shape[1] == 3:
                col = np.concatenate([col, np.ones((k, 1))], axis=1)
        uv = np.zeros((k, 2)) if uv is None else np.asarray(uv, dtype=np.float64)
        uv2 = np.zeros((k, 2)) if uv2 is None else np.asarray(uv2, dtype=np.float64)
        if uv.ndim == 1:
            uv = np.tile(uv, (k, 1))
        if uv2.ndim == 1:
            uv2 = np.tile(uv2, (k, 1))
        self._P.append(P)
        self._C.append(col)
        self._U.append(uv)
        self._U2.append(uv2)
        self._F.append(F + self.n)
        if fmat is None:
            self._Fm.append(np.full(len(F), self.mat_id(mat), dtype=np.int64))
        else:
            self._Fm.append(np.array([self.mat_id(m) for m in fmat], dtype=np.int64))
        if fpart is None:
            self._Fp.append(np.full(len(F), int(part), dtype=np.int64))
        else:
            self._Fp.append(np.asarray(fpart, dtype=np.int64))
        self.n += k
        return self

    def add_grid(self, G, mat, wrap_u=False, wrap_v=False, flip=False, col=None, uv=None, uv2=None, fmat=None, fpart=None, part=0):
        """G (nu, nv, 3) points of a grid -> quads. wrap_* closes the grid in that direction. `fmat` (nu-1 [+1], nv-1 [+1]) names per cell."""
        G = np.asarray(G, dtype=np.float64)
        nu, nv = G.shape[:2]
        idx = np.arange(nu * nv).reshape(nu, nv)
        us = list(range(nu - (0 if wrap_u else 1)))
        vs = list(range(nv - (0 if wrap_v else 1)))
        faces = []
        pf = [] if fmat is not None else None
        pp = [] if fpart is not None else None
        fm = np.asarray(fmat, dtype=object) if fmat is not None else None
        fpa = np.asarray(fpart) if fpart is not None else None
        for i in us:
            i1 = (i + 1) % nu
            for j in vs:
                if fm is not None and fm[i, j] == "None":
                    continue
                j1 = (j + 1) % nv
                q = [idx[i, j], idx[i1, j], idx[i1, j1], idx[i, j1]]
                faces.append(q[::-1] if flip else q)
                if pf is not None:
                    pf.append(fm[i, j])
                if pp is not None:
                    pp.append(int(fpa[i, j]))
        sel = lambda a: None if a is None else np.asarray(a, dtype=np.float64).reshape(nu * nv, -1)
        return self.add(G.reshape(-1, 3), np.array(faces), mat, col=sel(col) if col is not None and np.ndim(col) > 1 else col,
                        uv=sel(uv) if uv is not None and np.ndim(uv) > 2 else uv, uv2=sel(uv2) if uv2 is not None and np.ndim(uv2) > 2 else uv2, fmat=pf, fpart=pp, part=part)

    def add_mesh(self, o, xf=None, mat=None):
        P = o.P
        if xf is not None:
            P = apply(xf, P)
        names = [o.mats[i] for i in o.Fm] if mat is None else [mat] * len(o.F)
        return self.add(P, o.F.copy(), None, col=o.C.copy(), uv=o.U.copy(), uv2=o.U2.copy(), fmat=names, fpart=o.Fp.copy())

    # ------------------------------------------------------------------ whole-mesh edits
    def copy(self):
        m = Mesh()
        return m.add_mesh(self)

    def xformed(self, xf):
        m = Mesh()
        return m.add_mesh(self, xf)

    def mirrored_x(self):
        m = Mesh()
        names = [self.mats[i] for i in self.Fm]
        P = self.P.copy()
        P[:, 0] = -P[:, 0]
        F = self.F[:, ::-1].copy()
        return m.add(P, F, None, col=self.C.copy(), uv=self.U.copy(), uv2=self.U2.copy(), fmat=names, fpart=self.Fp.copy())

    def sym(self):
        """The mesh plus its mirror image across x = 0."""
        m = self.copy()
        m.add_mesh(self.mirrored_x())
        return m

    def flipped(self):
        m = Mesh()
        names = [self.mats[i] for i in self.Fm]
        return m.add(self.P.copy(), self.F[:, ::-1].copy(), None, col=self.C.copy(), uv=self.U.copy(), uv2=self.U2.copy(), fmat=names, fpart=self.Fp.copy())

    def recolor(self, col, cols=(0, 1, 2, 3)):
        """Set the vertex colour of every vertex (c: rgb or rgba; `cols` which channels to overwrite)."""
        c = np.asarray(col, dtype=np.float64)
        for blk in self._C:
            for k, ch in enumerate(cols):
                if k < len(c):
                    blk[:, ch] = c[k]
        return self

    def style(self, code=None, color=None, uv2=None):
        """Tag every vertex: `code` -> uv.x (the Details shader's material class), `color` -> rgb colour (alpha untouched), uv2 -> uv2.x (part id)."""
        for blk in self._U:
            if code is not None:
                blk[:, 0] = code
        if color is not None:
            c = np.asarray(color, dtype=np.float64)
            for blk in self._C:
                blk[:, :3] = c[:3]
                if len(c) > 3:
                    blk[:, 3] = c[3]
        if uv2 is not None:
            for blk in self._U2:
                blk[:, 0] = uv2
        return self

    def set_part(self, part):
        """Tag every face with a body part id (see Mesh.add)."""
        self._Fp = [np.full(len(f), int(part), dtype=np.int64) for f in self._F]
        return self

    def remat(self, name):
        i = self.mat_id(name)
        self._Fm = [np.full(len(f), i, dtype=np.int64) for f in self._F]
        return self

    def tri_count(self):
        F = self.F
        if len(F) == 0:
            return 0
        quad = F[:, 3] != F[:, 2]
        return int(len(F) + quad.sum())

    def bounds(self):
        P = self.P
        return P.min(axis=0), P.max(axis=0)

    def weld(self, tol=1e-5):
        """Merge coincident vertices (the first one's attributes win); drops degenerate faces."""
        P = self.P
        key = np.round(P / tol).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inv = inv.reshape(-1)
        m = Mesh()
        F = inv[self.F]
        keep = []
        for f in F:
            u = []
            for v in f:
                if not u or u[-1] != v:
                    u.append(v)
            if len(u) > 1 and u[0] == u[-1]:
                u.pop()
            keep.append(len(u) >= 3 and len(set(u)) >= 3)
        keep = np.array(keep, dtype=bool)
        F = F[keep]
        names = [self.mats[i] for i in self.Fm[keep]]
        return m.add(P[first], F, None, col=self.C[first], uv=self.U[first], uv2=self.U2[first], fmat=names, fpart=self.Fp[keep])


# ---------------------------------------------------------------------------------------------------------------------------- primitives
def quad(a, b, c, d, mat="Details", col=None):
    """One quad (counter-clockwise seen from the side the normal points to)."""
    return Mesh().add(np.array([a, b, c, d]), [[0, 1, 2, 3]], mat, col=col)


def tri(a, b, c, mat="Details", col=None):
    return Mesh().add(np.array([a, b, c]), [[0, 1, 2]], mat, col=col)


def poly_fan(pts, mat="Details", col=None, center=None, flip=False):
    """A convex (or star shaped) polygon as a fan around its centre."""
    pts = np.asarray(pts, dtype=np.float64)
    c = pts.mean(axis=0) if center is None else np.asarray(center)
    P = np.vstack([c, pts])
    n = len(pts)
    F = [[0, 1 + i, 1 + (i + 1) % n] for i in range(n)]
    if flip:
        F = [f[::-1] for f in F]
    return Mesh().add(P, np.array(F), mat, col=col)


def box(c, s, mat="Details", col=None):
    """Axis aligned box centred on c with full size s = (sx, sy, sz)."""
    return rbox(c, s, 0.0, 1, mat, col)


def rbox(c, s, r=0.02, seg=1, mat="Details", col=None):
    """Rounded box: centre c, full size s, edge radius r, `seg` segments in each rounded edge (seg 1 = a chamfer)."""
    h = np.asarray(s, dtype=np.float64) * 0.5
    r = min(r, float(h.min()) * 0.99)

    def coords(hh):
        if r <= 0.0:
            return np.array([-hh, hh])
        a = [-hh + i * r / seg for i in range(seg + 1)]
        b = [hh - r + i * r / seg for i in range(seg + 1)]
        return np.array(a + b)

    cx, cy, cz = coords(h[0]), coords(h[1]), coords(h[2])
    m = Mesh()
    inner = h - r

    def rnd(p):
        if r <= 0.0:
            return p
        q = np.clip(p, -inner, inner)
        d = p - q
        ln = np.linalg.norm(d, axis=-1, keepdims=True)
        return np.where(ln > 1e-12, q + d / np.maximum(ln, 1e-12) * r, p)

    for axis in range(3):
        for sgn in (-1.0, 1.0):
            ax1, ax2 = [(1, 2), (2, 0), (0, 1)][axis]
            c1 = [cx, cy, cz][ax1]
            c2 = [cx, cy, cz][ax2]
            G = np.zeros((len(c1), len(c2), 3))
            for i, u in enumerate(c1):
                for j, v in enumerate(c2):
                    p = np.zeros(3)
                    p[axis] = sgn * h[axis]
                    p[ax1] = u
                    p[ax2] = v
                    G[i, j] = rnd(p)
            m.add_grid(G + np.asarray(c, dtype=np.float64), mat, flip=(sgn < 0.0), col=col)
    return m


def cylinder(p0, p1, r0, r1=None, seg=12, mat="Details", col=None, caps=(True, True), up=None):
    """A (truncated) cone from p0 to p1."""
    r1 = r0 if r1 is None else r1
    p0 = np.asarray(p0, dtype=np.float64)
    p1 = np.asarray(p1, dtype=np.float64)
    ax = unit(p1 - p0)
    ref = np.array([0.0, 0.0, 1.0]) if abs(ax[2]) < 0.95 else np.array([1.0, 0.0, 0.0])
    if up is not None:
        ref = np.asarray(up, dtype=np.float64)
    u = unit(np.cross(ax, ref))
    v = np.cross(ax, u)
    ang = np.linspace(0.0, 2 * math.pi, seg, endpoint=False)
    ring = np.stack([np.cos(ang)[:, None] * u + np.sin(ang)[:, None] * v][0])
    G = np.stack([p0 + ring * r0, p1 + ring * r1])
    m = Mesh().add_grid(G, mat, wrap_v=True, flip=True, col=col)
    if caps[0] and r0 > 0:
        m.add_mesh(poly_fan(p0 + ring * r0, mat, col, center=p0, flip=True))
    if caps[1] and r1 > 0:
        m.add_mesh(poly_fan(p1 + ring * r1, mat, col, center=p1))
    return m


def revolve(profile, seg=24, axis="x", center=(0, 0, 0), mat="Details", col=None, start=0.0, sweep=2 * math.pi, flip=False, uv_fn=None, seam=False):
    """Surface of revolution. profile = [(t, radius), ...] (t along the axis); the axis is X (wheels), Y or Z.
    Returns a Mesh; vertex uv = (angle fraction, profile index fraction) unless uv_fn(i, j, n_prof, seg) is given."""
    prof = np.asarray(profile, dtype=np.float64)
    wrap = abs(sweep - 2 * math.pi) < 1e-6 and not seam           # seam = a duplicated column at the end so a texture can run 0 .. 1 round the wheel
    n_a = seg if wrap else seg + 1
    ang = start + np.arange(n_a) * (sweep / seg)
    G = np.zeros((len(prof), n_a, 3))
    uvs = np.zeros((len(prof), n_a, 2))
    for i, (t, r) in enumerate(prof):
        for j, a in enumerate(ang):
            if axis == "x":
                p = (t, r * math.cos(a), r * math.sin(a))
            elif axis == "y":
                p = (r * math.cos(a), t, r * math.sin(a))
            else:
                p = (r * math.cos(a), r * math.sin(a), t)
            G[i, j] = p
            uvs[i, j] = (j / seg, i / max(len(prof) - 1, 1)) if uv_fn is None else uv_fn(i, j, len(prof), seg)
    G = G + np.asarray(center, dtype=np.float64)
    return Mesh().add_grid(G, mat, wrap_v=wrap, flip=flip, col=col, uv=uvs)


def sphere(c, r, seg=10, rings=6, mat="Details", col=None, squash=(1.0, 1.0, 1.0)):
    """UV sphere / ellipsoid (radii r * squash)."""
    sq = np.asarray(squash, dtype=np.float64)
    G = np.zeros((rings + 1, seg, 3))
    for i in range(rings + 1):
        phi = -math.pi / 2 + math.pi * i / rings
        for j in range(seg):
            th = 2 * math.pi * j / seg
            G[i, j] = (math.cos(phi) * math.cos(th), math.cos(phi) * math.sin(th), math.sin(phi))
    G = G * (r * sq) + np.asarray(c, dtype=np.float64)
    return Mesh().add_grid(G, mat, wrap_v=True, col=col, flip=True)


def torus(c, R, r, seg=16, sides=6, axis="y", mat="Details", col=None):
    """Ring of tube radius r on a circle of radius R (steering wheel). axis = the ring's normal."""
    G = np.zeros((seg, sides, 3))
    for i in range(seg):
        a = 2 * math.pi * i / seg
        for j in range(sides):
            b = 2 * math.pi * j / sides
            rr = R + r * math.cos(b)
            p = np.array([rr * math.cos(a), rr * math.sin(a), r * math.sin(b)])      # ring in XY, normal Z
            G[i, j] = p
    if axis == "y":
        G = G[..., [0, 2, 1]]
        G[..., 1] *= -1
    elif axis == "x":
        G = G[..., [2, 0, 1]]
    return Mesh().add_grid(G + np.asarray(c, dtype=np.float64), mat, wrap_u=True, wrap_v=True, col=col, flip=True)


def tube(path, radii, sides=8, mat="Details", col=None, caps=True, closed=False, up=(0, 0, 1)):
    """Sweep a circle (radius per path point) along a polyline."""
    path = np.asarray(path, dtype=np.float64)
    n = len(path)
    radii = np.full(n, radii, dtype=np.float64) if np.isscalar(radii) else np.asarray(radii, dtype=np.float64)
    tang = np.zeros_like(path)
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        tang[i] = unit(b - a)
    ref = np.asarray(up, dtype=np.float64)
    G = np.zeros((n, sides, 3))
    u_prev = None
    for i in range(n):
        t = tang[i]
        if u_prev is None:
            r = ref if abs(np.dot(t, ref)) < 0.95 else np.array([1.0, 0.0, 0.0])
            u = unit(np.cross(t, r))
        else:
            u = unit(u_prev - t * np.dot(u_prev, t))
        v = np.cross(t, u)
        u_prev = u
        for j in range(sides):
            a = 2 * math.pi * j / sides
            G[i, j] = path[i] + (math.cos(a) * u + math.sin(a) * v) * radii[i]
    m = Mesh().add_grid(G, mat, wrap_v=True, wrap_u=closed, col=col, flip=True)
    if caps and not closed:
        m.add_mesh(poly_fan(G[0], mat, col, center=path[0]))
        m.add_mesh(poly_fan(G[-1], mat, col, center=path[-1], flip=True))
    return m


def prism(poly, z0, z1, mat="Details", col=None, plane="xy"):
    """Extrude a convex polygon (list of 2D points) between two offsets along the plane's normal. plane = 'xy' (extrude along Z), 'xz' (along Y), 'yz' (along X)."""
    poly = np.asarray(poly, dtype=np.float64)
    n = len(poly)

    def lift(pts, h):
        if plane == "xy":
            return np.column_stack([pts[:, 0], pts[:, 1], np.full(len(pts), h)])
        if plane == "xz":
            return np.column_stack([pts[:, 0], np.full(len(pts), h), pts[:, 1]])
        return np.column_stack([np.full(len(pts), h), pts[:, 0], pts[:, 1]])

    a, b = lift(poly, z0), lift(poly, z1)
    G = np.stack([a, b])
    m = Mesh().add_grid(G, mat, wrap_v=True, col=col)
    m.add_mesh(poly_fan(a, mat, col))
    m.add_mesh(poly_fan(b, mat, col, flip=True))
    # winding is fixed by `orient` below (the caller does not know the polygon's direction)
    return orient_closed(m)


def orient_closed(m):
    """Flip the faces of a closed convex-ish solid so that every normal points away from its centroid."""
    P = m.P
    c = P.mean(axis=0)
    F = m.F.copy()
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    nrm = np.cross(B - A, C - A)
    mid = (A + B + C) / 3.0
    flip = (nrm * (mid - c)).sum(axis=1) < 0.0
    F[flip] = F[flip][:, ::-1]
    out = Mesh()
    return out.add(P, F, None, col=m.C, uv=m.U, uv2=m.U2, fmat=[m.mats[i] for i in m.Fm], fpart=m.Fp)


# ---------------------------------------------------------------------------------------------------------------------------- finalize
def triangulate(m):
    """Mesh -> (T (k,3) vertex ids, Tm (k,) material ids), splitting quads along the shorter diagonal, dropping zero area faces."""
    P = m.P
    F = m.F
    Fm = m.Fm
    Fp = m.Fp
    tris, tm, tp = [], [], []
    for f, mid, part in zip(F, Fm, Fp):
        a, b, c, d = f
        if c == d or a == d:
            cand = [(a, b, c)]
        else:
            if np.linalg.norm(P[a] - P[c]) <= np.linalg.norm(P[b] - P[d]):
                cand = [(a, b, c), (a, c, d)]
            else:
                cand = [(a, b, d), (b, c, d)]
        for t in cand:
            if len(set(t)) < 3:
                continue
            area = np.linalg.norm(np.cross(P[t[1]] - P[t[0]], P[t[2]] - P[t[0]]))
            if area < 1e-9:
                continue
            tris.append(t)
            tm.append(mid)
            tp.append(part)
    return np.array(tris, dtype=np.int64).reshape(-1, 3), np.array(tm, dtype=np.int64), np.array(tp, dtype=np.int64)


def corner_normals(P, T, thr_deg=38.0, area_pow=0.6):
    """Per triangle corner smooth normals: the angle x area^area_pow weighted mean of the incident faces within `thr_deg` of this face's own normal.
    The area weight keeps a big flat panel flat (a bus side next to a small rounded corner) instead of pillow shading across the whole panel."""
    A, B, C = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    fn = np.cross(B - A, C - A)
    ln = np.linalg.norm(fn, axis=1, keepdims=True)
    fn = fn / np.maximum(ln, 1e-12)

    def ang(p, q, r):
        u, v = unit(q - p), unit(r - p)
        return np.arccos(np.clip((u * v).sum(axis=1), -1.0, 1.0))
    wts = np.stack([ang(A, B, C), ang(B, C, A), ang(C, A, B)], axis=1) * (np.maximum(ln, 1e-12) ** area_pow)      # the angle at each corner, scaled by the face size
    cosT = math.cos(math.radians(thr_deg))
    key = np.round(P / 1e-5).astype(np.int64)
    _, vid = np.unique(key, axis=0, return_inverse=True)           # vertices at the same place share their smoothing group (uv seams stay smooth)
    vid = vid.reshape(-1)
    inc = {}
    for t in range(len(T)):
        for k in range(3):
            inc.setdefault(int(vid[T[t, k]]), []).append((t, k))
    N = np.zeros((len(T), 3, 3))
    for v, lst in inc.items():
        ts = np.array([x[0] for x in lst])
        ks = np.array([x[1] for x in lst])
        nf = fn[ts]
        w = wts[ts, ks]
        dots = nf @ nf.T
        mask = dots >= cosT
        acc = (mask * w[None, :]) @ nf
        acc = unit(acc)
        for i, (t, k) in enumerate(lst):
            N[t, k] = acc[i]
    return N


def finalize(m, thr_deg=38.0, smooth=True):
    """Triangulate + smooth normals. Returns {material name: dict(V, N, C, U, U2, I)} with vertices split where normals differ."""
    P = m.P
    T, Tm, Tp = triangulate(m)
    if len(T) == 0:
        return {}
    if smooth:
        N = corner_normals(P, T, thr_deg)
    else:
        A, B, C_ = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
        fn = unit(np.cross(B - A, C_ - A))
        N = np.repeat(fn[:, None, :], 3, axis=1)
    C, U, U2 = m.C, m.U, m.U2
    has_parts = bool((Tp > 0).any())
    out = {}
    for mid in np.unique(Tm):
        sel = np.where(Tm == mid)[0]
        cache = {}
        V, Ns, Cs, Us, U2s, I = [], [], [], [], [], []
        for t in sel:
            ids = []
            for k in range(3):
                v = int(T[t, k])
                n = N[t, k]
                part = int(Tp[t])
                key = (v, int(round(n[0] * 600)), int(round(n[1] * 600)), int(round(n[2] * 600)), part)
                j = cache.get(key)
                if j is None:
                    j = len(V)
                    cache[key] = j
                    V.append(P[v])
                    Ns.append(n)
                    Cs.append(C[v])
                    Us.append(U[v])
                    u2 = np.array(U2[v], dtype=np.float64)
                    if has_parts and part != 0:                        # part 0 (the shell) keeps its own uv2.x: the tread u of a wheel, the plate u of a number plate
                        u2[0] = part / 32.0
                    U2s.append(u2)
                ids.append(j)
            I.append(ids)
        out[m.mats[mid]] = dict(V=np.array(V), N=np.array(Ns), C=np.array(Cs), U=np.array(Us), U2=np.array(U2s), I=np.array(I, dtype=np.int64))
    return out


def merge_groups(groups):
    """Concatenate finalize() results of several meshes (same material names are appended)."""
    out = {}
    for g in groups:
        for name, d in g.items():
            if name not in out:
                out[name] = {k: v.copy() for k, v in d.items()}
            else:
                o = out[name]
                off = len(o["V"])
                for k in ("V", "N", "C", "U", "U2"):
                    o[k] = np.concatenate([o[k], d[k]])
                o["I"] = np.concatenate([o["I"], d["I"] + off])
    return out


def group_tris(g):
    return sum(len(d["I"]) for d in g.values())


def bake_vertex_ao(groups, occluders, rays=20, dist=0.9, bias=0.012, channel=0, seed=3, strength=1.0):
    """Vertex ambient occlusion by ray casting (mathutils BVH) against `occluders` (a list of Mesh objects). Writes into colour channel `channel`
    (1 = open, lower = occluded) of every vertex of `groups` (finalize() results)."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    P_all, F_all = [], []
    off = 0
    for om in occluders:
        P = om.P
        for f in om.F:
            u = list(dict.fromkeys(int(x) for x in f))
            if len(u) >= 3:
                F_all.append(tuple(off + x for x in u[:3]))
                if len(u) == 4:
                    F_all.append((off + u[0], off + u[2], off + u[3]))
        P_all.append(P)
        off += len(P)
    P_all = np.concatenate(P_all)
    bvh = BVHTree.FromPolygons([tuple(p) for p in P_all], F_all)
    rng = np.random.RandomState(seed)
    # cosine weighted hemisphere samples in tangent space
    u1 = (np.arange(rays) + rng.rand(rays)) / rays
    u2 = rng.rand(rays)
    r = np.sqrt(u1)
    th = 2 * math.pi * u2
    dirs = np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(np.maximum(0.0, 1.0 - u1))], axis=1)
    for name, d in groups.items():
        V, N = d["V"], d["N"]
        for i in range(len(V)):
            n = N[i]
            t = unit(np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0]))
            b = np.cross(n, t)
            hit = 0
            o = Vector(V[i] + n * bias)
            for dv in dirs:
                w = t * dv[0] + b * dv[1] + n * dv[2]
                if bvh.ray_cast(o, Vector(w), dist)[0] is not None:
                    hit += 1
            d["C"][i, channel] = 1.0 - strength * hit / rays
    return bvh


class Surface:
    """Ray queries against a mesh (the car body) to place details on it: BVH of the quads."""

    def __init__(self, mesh):
        from mathutils.bvhtree import BVHTree
        P = mesh.P
        F = []
        for f in mesh.F:
            u = list(dict.fromkeys(int(x) for x in f))
            if len(u) >= 3:
                F.append(tuple(u[:3]))
                if len(u) == 4:
                    F.append((u[0], u[2], u[3]))
        self.bvh = BVHTree.FromPolygons([tuple(p) for p in P], F)
        # the rays start outside the car whatever its size (a bus is 9.5 m long and 3.2 m tall)
        self.ext = np.abs(P).max(axis=0) + 0.6

    def hit(self, origin, direction, dist=10.0):
        """(point, normal) or None. Normals are the face normals of the hit triangle."""
        from mathutils import Vector
        loc, nrm, idx, d = self.bvh.ray_cast(Vector(origin), Vector(direction), dist)
        if loc is None:
            return None
        return np.array(loc), np.array(nrm)

    def side(self, y, z, sign=1.0, x0=None):
        """The body surface on the +x (sign 1) or -x side at height z, station y: shoot along -x from outside."""
        x0 = max(3.0, self.ext[0]) if x0 is None else x0
        return self.hit((sign * x0, y, z), (-sign, 0.0, 0.0), x0 * 2)

    def top(self, x, y, z0=None):
        z0 = max(3.0, self.ext[2]) if z0 is None else z0
        return self.hit((x, y, z0), (0.0, 0.0, -1.0), z0 * 2)

    def front(self, x, z, y0=None):
        y0 = max(4.0, self.ext[1]) if y0 is None else y0
        return self.hit((x, y0, z), (0.0, -1.0, 0.0), y0 * 2)

    def rear(self, x, z, y0=None):
        y0 = -max(4.0, self.ext[1]) if y0 is None else y0
        return self.hit((x, y0, z), (0.0, 1.0, 0.0), -y0 * 2)
