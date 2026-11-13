"""Conformal armour builders: plates, bands and rings that hug the body (herosuit/body.py) because every vertex is found by casting a ray at it.

A SHELL is a rows x cols grid (rows run along t, columns along s, both 0..1). For every grid point a ray function gives (origin, direction); the first hit of the body along it is
the skin point H with the smooth outward normal N; the outer surface is H + N * off_out(s, t), the inner one H + N * off_in(s, t). The two sheets and a wall around the rim make a
closed solid that Part.raw() bevels. Outlines are not clipped out of a grid: the ray function itself returns the plate's own boundary (the extent of each row), so every outline
is exact and made of clean quads.
"""
import math

from mathutils import Matrix, Vector


def sm(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0 + 1e-12)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def bump(x, c, w):
    """A smooth bump 0..1 centred at c with half width w."""
    d = abs(x - c) / max(w, 1e-6)
    return 0.0 if d >= 1.0 else (1.0 - d * d) ** 2


MISSES = []                    # (s, t) of every ray that missed the body and fell back to the nearest point: the model script prints them (a clean fit has none)


def shell(body, rows, cols, rayfn, off_out, off_in, closed_s=False, maxd=1.6, miss_r=None):
    """A tray fitted to the body: rayfn(s, t) -> (origin, direction) is cast at the body (a ray that misses within `maxd` puts the point `miss_r` along the ray when given, else the
    nearest body point). See shell_fn for the rest."""
    def surf(s, t):
        o, d = rayfn(s, t)
        r = body.ray(o, d, maxd)
        if r is None and miss_r is not None:
            dd = Vector(d).normalized()
            return Vector(o) + dd * miss_r, dd
        if r is None:
            MISSES.append((round(s, 2), round(t, 2), tuple(round(c, 3) for c in o)))
            r = body.nearest(o)
        return r
    return shell_fn(rows, cols, surf, off_out, off_in, closed_s)


def shell_fn(rows, cols, surf, off_out, off_in, closed_s=False):
    """surf(s, t) -> (point, outward normal); off_out / off_in: floats or functions of (s, t). Returns (verts, faces) of a TRAY: the outer sheet and a wall from its rim down to the inner
    offset (the inner sheet would sit against the skin and never show, so it is not built: half the triangles). Winding is made outward-facing here."""
    fo = off_out if callable(off_out) else (lambda s, t, v=off_out: v)
    fi = off_in if callable(off_in) else (lambda s, t, v=off_in: v)
    ncols = cols if closed_s else cols + 1          # points per row
    outer, normals = [], []
    inner = {}
    last = None
    for i in range(rows + 1):
        t = i / rows
        for j in range(ncols):
            s = j / cols
            r = surf(s, t)
            if r is None:
                r = last
            if r is None:
                raise RuntimeError("shell: no surface at s=%.2f t=%.2f" % (s, t))
            last = r
            h, n = r
            outer.append(tuple(h + n * fo(s, t)))
            normals.append(n)
            rim = (i == 0 or i == rows) or (not closed_s and (j == 0 or j == cols))
            if rim:
                inner[(i, j)] = tuple(h + n * fi(s, t))
    verts = list(outer)
    iid = {}
    for k, pt in inner.items():
        iid[k] = len(verts)
        verts.append(pt)

    def oid(i, j):
        return i * ncols + (j % ncols)

    faces = []
    for i in range(rows):
        for j in range(cols):
            faces.append((oid(i, j), oid(i, j + 1), oid(i + 1, j + 1), oid(i + 1, j)))
    jj = lambda j: j % ncols if closed_s else j
    for j in range(cols):
        faces.append((oid(0, j + 1), oid(0, j), iid[(0, jj(j))], iid[(0, jj(j + 1))]))
        faces.append((oid(rows, j), oid(rows, j + 1), iid[(rows, jj(j + 1))], iid[(rows, jj(j))]))
    if not closed_s:
        for i in range(rows):
            faces.append((oid(i, 0), oid(i + 1, 0), iid[(i + 1, 0)], iid[(i, 0)]))
            faces.append((oid(i + 1, cols), oid(i, cols), iid[(i, cols)], iid[(i + 1, cols)]))
    # winding: the first outer quad must face along the smooth normal of its first vertex
    a, b, c = (Vector(verts[k]) for k in faces[0][:3])
    nf = (b - a).cross(c - b)
    if nf.dot(normals[faces[0][0]]) < 0.0:
        faces = [tuple(reversed(f)) for f in faces]
    return verts, faces


def ellipse_surf(cx, cy, rx, ry, z0, z1, th0, th1, flare=None):
    """An analytic surface for pieces that do not follow the body (a collar): points on an ellipse around the vertical axis through (cx, cy), theta 0 = forward (+y), turning toward +x.
    z runs z0..z1 with t, radii rx / ry (functions of t allowed), flare(t) adds to both radii."""
    rxf = rx if callable(rx) else (lambda t, v=rx: v)
    ryf = ry if callable(ry) else (lambda t, v=ry: v)

    def surf(s, t):
        th = lerp(th0, th1, s)
        z = lerp(z0, z1, t) if not callable(z0) else z0(s, t)
        f = flare(t) if flare else 0.0
        x = cx + (rxf(t) + f) * math.sin(th)
        y = cy + (ryf(t) + f) * math.cos(th)
        n = Vector((math.sin(th) * ryf(t), math.cos(th) * rxf(t), 0.0)).normalized()
        return Vector((x, y, z)), n
    return surf


def axis_frame(axis):
    """Two unit vectors perpendicular to `axis` (and to each other)."""
    a = Vector(axis).normalized()
    ref = Vector((0, 1, 0)) if abs(a.y) < 0.9 else Vector((0, 0, 1))
    e1 = (ref - a * ref.dot(a)).normalized()
    e2 = a.cross(e1).normalized()
    return a, e1, e2


class Limb:
    """A segment of the body to wrap: rows of slice centres between a and b and a radial frame. theta 0 = `up` (a vector), turning toward `fwd`."""

    def __init__(self, body, a, b, n_rows=12, up=(0, 0, 1), fwd=(0, 1, 0), radius=0.16, refine=True):
        self.body = body
        self.a, self.b = Vector(a), Vector(b)
        self.axis = (self.b - self.a).normalized()
        up = Vector(up)
        up = (up - self.axis * up.dot(self.axis)).normalized()
        self.up = up
        self.fwd = self.axis.cross(up).normalized()
        if self.fwd.dot(Vector(fwd)) < 0.0:
            self.fwd = -self.fwd
        self.centres = []
        for i in range(n_rows + 1):
            p = self.a.lerp(self.b, i / n_rows)
            if refine:
                p = body.slice_center(p, self.axis, radius)
            self.centres.append(p)
        self.n_rows = n_rows

    def centre(self, t):
        if t < 0.0:                                      # beyond the ends: the end segment's direction continues
            d = self.centres[1] - self.centres[0]
            return self.centres[0] + d * (t * self.n_rows)
        if t > 1.0:
            d = self.centres[-1] - self.centres[-2]
            return self.centres[-1] + d * ((t - 1.0) * self.n_rows)
        x = t * self.n_rows
        i = min(int(x), self.n_rows - 1)
        return self.centres[i].lerp(self.centres[i + 1], x - i)

    def radial(self, theta):
        return self.up * math.cos(theta) + self.fwd * math.sin(theta)

    def ray(self, theta, t):
        """(origin, direction) for the surface point at angle theta and axis position t (0 = a, 1 = b)."""
        c = self.centre(t)
        return c, self.radial(theta)

    def span(self, t0, t1, th0, th1):
        """A rayfn(s, t) over axis range [t0, t1] and angle range [th0, th1] (radians)."""
        return lambda s, t: self.ray(lerp(th0, th1, s), lerp(t0, t1, t))


def planar(body, origin, d, u, v, extent):
    """rayfn for a plate seen from the direction -d (the rays travel along `d`, from `origin` + the (u, v) point in the plane). extent(s, t) -> (x, y) in metres on the plane."""
    o = Vector(origin)
    d = Vector(d).normalized()
    u = Vector(u).normalized()
    v = Vector(v).normalized()

    def fn(s, t):
        x, y = extent(s, t)
        return o + u * x + v * y, d
    return fn


def spans(rows_fn, s, t):
    return rows_fn(s, t)


def sheet(rows, cols, point_fn, face_dir):
    """A plain sheet (cloth: no thickness, drawn double sided by the shader) of rows x cols quads. point_fn(s, t) -> Vector; the winding is made to face `face_dir` (the side that is the outside)."""
    verts = []
    for i in range(rows + 1):
        for j in range(cols + 1):
            verts.append(tuple(point_fn(j / cols, i / rows)))
    faces = []
    for i in range(rows):
        for j in range(cols):
            a = i * (cols + 1) + j
            faces.append((a, a + 1, a + cols + 2, a + cols + 1))
    a, b, c = (Vector(verts[k]) for k in faces[0][:3])
    if (b - a).cross(c - b).dot(Vector(face_dir)) < 0.0:
        faces = [tuple(reversed(f)) for f in faces]
    return verts, faces


def dome_surf(center, axis, radius, phi0, phi1, scallop=None):
    """A spherical shell around a joint (a pauldron): theta runs around `axis` (s = 0..1 = a full turn), phi from the pole (t = 0 -> phi0) to phi1. Because it is a sphere about the joint
    centre, rotating it with the arm bone never makes it cut the skin (unlike a plate that follows the arm's length). scallop(theta) shortens the rim of phi1 (a notched edge)."""
    a, e1, e2 = axis_frame(axis)
    c = Vector(center)

    def surf(s, t):
        th = 2.0 * math.pi * s
        ph1 = phi1 - (scallop(th) if scallop else 0.0)
        ph = lerp(phi0, ph1, t)
        d = e1 * (math.sin(ph) * math.cos(th)) + e2 * (math.sin(ph) * math.sin(th)) + a * math.cos(ph)
        return c + d * radius, d
    return surf
