"""Sedan: 4.75 m four-door saloon."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402

SPEC = dict(
    name="car_sedan", seed=5,
    L=4.75, W=1.86, WB=2.82, gc=0.14, R=0.335, tw=0.225, track=1.58, spokes=5,
    paint="#5a8798", rim="#8d959c", spoke="#c3cad1", underglow="#18d6ff", atlas_paint=1024, atlas=1024,
    belt=0.90,
    ztop=[(-2.375, 0.66), (-2.30, 0.78), (-2.12, 0.88), (-1.80, 0.945), (-1.45, 0.955), (-1.30, 0.93), (-1.0, 0.905), (0.80, 0.90),
          (1.05, 0.925), (1.5, 0.89), (2.0, 0.82), (2.28, 0.74), (2.375, 0.66)],
    rise=(0.10, 0.10), taper=0.55, taper_amt=0.2,
    gh=[(0.80, 0.93), (0.66, 1.02), (0.50, 1.15), (0.32, 1.28), (0.12, 1.39), (-0.10, 1.445), (-0.45, 1.465), (-0.80, 1.45),
        (-1.00, 1.40), (-1.18, 1.27), (-1.34, 1.10), (-1.45, 0.98)],
    roof_front=-0.10, roof_rear=-0.80, roof_w=0.74, z_roof=1.465,
    b_pillar=(-0.52, -0.40), side_glass=(-1.25, 0.08),
    door_lines=[0.45, -0.48, -1.22], handles=[0.0, -0.95],
    seats=[(-0.05, True), (-1.0, True)],
)

if __name__ == "__main__":
    build_car(SPEC)
