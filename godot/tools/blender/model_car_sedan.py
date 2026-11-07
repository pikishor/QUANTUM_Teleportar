"""Sedan: 4.75 m four-door saloon."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402

def _stretch(pts, d, lo=1.0):
    """Longer nose and tail: ends beyond |y| > lo move outward by d (the cabin stays where it is)."""
    out = []
    for y, z in pts:
        if abs(y) > lo + 0.01:
            y += d if y > 0 else -d
        out.append((round(y, 3), z))
    return out


def _squash(pts, above, k):
    """Lower roof: z above `above` is compressed by k."""
    return [(y, round(above + (z - above) * k, 3) if z > above else z) for y, z in pts]


SPEC = dict(
    name="car_sedan", seed=5,
    L=4.95, W=1.90, WB=2.92, gc=0.12, R=0.35, tw=0.235, track=1.66, spokes=5,
    paint="#5a8798", rim="#8d959c", spoke="#c3cad1", underglow="#18d6ff", atlas_paint=1024, atlas=1024,
    belt=0.90,
    ztop=_stretch([(-2.375, 0.64), (-2.30, 0.75), (-2.12, 0.85), (-1.80, 0.915), (-1.45, 0.92), (-1.30, 0.915), (-1.0, 0.895), (0.80, 0.865),
                   (1.05, 0.885), (1.5, 0.845), (2.0, 0.775), (2.28, 0.70), (2.375, 0.63)], 0.10),
    rise=(0.10, 0.10), taper=0.55, taper_amt=0.2,
    gh=_squash([(0.80, 0.93), (0.66, 1.02), (0.50, 1.15), (0.32, 1.28), (0.12, 1.39), (-0.10, 1.445), (-0.45, 1.465), (-0.80, 1.45),
                (-1.00, 1.40), (-1.18, 1.27), (-1.34, 1.10), (-1.45, 0.98)], 0.93, 0.86),
    roof_front=-0.10, roof_rear=-0.80, roof_w=0.74, z_roof=1.40,
    b_pillar=(-0.52, -0.40), side_glass=(-1.25, 0.08),
    door_lines=[0.45, -0.48, -1.22], handles=[0.0, -0.95],
    seats=[(-0.05, True), (-1.0, True)],
)

if __name__ == "__main__":
    build_car(SPEC)
