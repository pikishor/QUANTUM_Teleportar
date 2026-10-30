"""SUV: tall 4.85 m crossover with roof rails."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402


def extras(P, c):
    trim, T_black, T_dark, T_chrome, hw = c["trim"], c["T_black"], c["T_dark"], c["T_chrome"], c["hw"]
    L, gc = c["L"], c["gc"]
    zr = c["spec"]["z_roof"]
    for sx in (1, -1):
        P.bar((sx * 0.6, 0.15, zr + 0.035), (sx * 0.6, -1.95, zr + 0.035), 0.035, 0.03, mat=trim, tint=T_chrome, bevel=0.005)
        for y in (0.1, -0.5, -1.1, -1.7):
            P.bar((sx * 0.6, y, zr + 0.005), (sx * 0.6, y, zr + 0.03), 0.04, 0.03, mat=trim, tint=T_black)
        P.box((0.1, 2.3, 0.05), (sx * (hw(-0.4) * 0.97 - 0.02), -0.4, gc + 0.12), mat=trim, tint=T_black, bevel=0.012, bsegs=2)   # side steps
    P.box((1.1, 0.06, 0.12), (0, L / 2 - 0.05, gc + 0.14), mat=trim, tint=T_chrome, bevel=0.01)                              # front skid
    P.box((1.1, 0.06, 0.12), (0, -L / 2 + 0.05, gc + 0.14), mat=trim, tint=T_chrome, bevel=0.01)
    P.box((1.6, 0.05, 0.05), (0, L / 2 - 0.04, gc + 0.62), mat=trim, tint=T_dark, bevel=0.01)


SPEC = dict(
    name="car_suv", seed=13,
    L=4.85, W=1.98, WB=2.9, gc=0.21, R=0.385, tw=0.255, track=1.68, spokes=5,
    paint="#2f3d44", rim="#8d959c", spoke="#c3cad1", underglow="#18ffb0",
    belt=1.12, taper=0.65,
    ztop=[(-2.425, 0.80), (-2.35, 1.00), (-2.2, 1.14), (-1.9, 1.15), (-1.5, 1.13), (-1.2, 1.12), (0.95, 1.12), (1.2, 1.12),
          (1.6, 1.05), (2.1, 0.95), (2.35, 0.84), (2.425, 0.70)],
    rise=(0.18, 0.16),
    gh=[(0.95, 1.15), (0.82, 1.28), (0.62, 1.46), (0.40, 1.62), (0.2, 1.72), (-0.1, 1.76), (-0.8, 1.78), (-1.5, 1.78), (-1.9, 1.76),
        (-2.05, 1.66), (-2.15, 1.42), (-2.22, 1.2)],
    roof_front=0.2, roof_rear=-1.9, roof_w=0.80, z_roof=1.78,
    b_pillar=(-0.46, -0.34), side_glass=(-2.0, 0.45),
    door_lines=[0.6, -0.4, -1.3], handles=[0.15, -0.85],
    seats=[(0.0, True), (-1.0, True), (-1.75, False)],
    extras=[extras],
)

if __name__ == "__main__":
    build_car(SPEC)
