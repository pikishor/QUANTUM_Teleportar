"""Sport: low 4.45 m two-seat coupe with a rear wing."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402


def extras(P, c):
    trim, T_black, T_dark, hw = c["trim"], c["T_black"], c["T_dark"], c["hw"]
    L, gc = c["L"], c["gc"]
    y = -L / 2 + 0.30
    zw = 1.03
    for sx in (1, -1):
        P.bar((sx * 0.5, y + 0.02, 0.86), (sx * 0.5, y, zw - 0.015), 0.045, 0.03, mat=trim, tint=T_black, bevel=0.004)
    P.box((1.66, 0.30, 0.03), (0, y, zw), mat=trim, tint=T_black, bevel=0.008, bsegs=1, rot=(-5, 0, 0))
    P.box((0.03, 0.34, 0.13), (0.84, y, zw + 0.03), mat=trim, tint=T_black, bevel=0.006, mirror=True)
    P.box((1.3, 0.34, 0.05), (0, -L / 2 + 0.2, gc + 0.12), mat=trim, tint=T_black, bevel=0.01)          # diffuser
    for x in (-0.4, -0.2, 0.0, 0.2, 0.4):
        P.box((0.012, 0.3, 0.08), (x, -L / 2 + 0.15, gc + 0.06), mat=trim, tint=T_dark)
    for sx in (1, -1):                                                                                # side intakes
        P.box((0.04, 0.5, 0.16), (sx * (hw(-1.15) * 0.972 - 0.005), -1.12, 0.52), mat=trim, tint=T_black, bevel=0.012, bsegs=2, rot=(0, 0, 0))
        P.box((0.4, 0.5, 0.012), (sx * 0.0 + (0.45 * sx), 1.35, 0.775), mat=trim, tint=T_black, rot=(-4, 0, 0))   # hood vents
    P.box((0.5, 0.5, 0.014), (0, 1.55, 0.805), mat=trim, tint=T_black, rot=(-6, 0, 0))                  # hood scoop vent
    P.box((0.9, 0.05, 0.045), (0, L / 2 - 0.04, gc + 0.07), mat=trim, tint=T_black, bevel=0.01)          # front splitter


SPEC = dict(
    name="car_sport", seed=9,
    L=4.45, W=1.92, WB=2.62, gc=0.11, R=0.335, tw=0.265, track=1.58, spokes=6,
    paint="#8a1f2c", rim="#6f757b", spoke="#b7bec6", underglow="#ff2fd6",
    belt=0.80,
    ztop=[(-2.225, 0.62), (-2.15, 0.74), (-1.95, 0.86), (-1.60, 0.92), (-1.30, 0.93), (-1.0, 0.88), (-0.6, 0.81), (0.55, 0.79),
          (0.85, 0.82), (1.3, 0.84), (1.8, 0.74), (2.1, 0.64), (2.225, 0.56)],
    rise=(0.08, 0.10), taper=0.5, taper_amt=0.2,
    gh=[(0.55, 0.83), (0.40, 0.93), (0.22, 1.03), (0.02, 1.12), (-0.2, 1.175), (-0.5, 1.19), (-0.8, 1.17), (-1.05, 1.10),
        (-1.30, 1.0), (-1.50, 0.92)],
    roof_front=0.0, roof_rear=-0.8, roof_w=0.70, z_roof=1.19,
    b_pillar=(-9.0, -9.0), side_glass=(-1.2, 0.18),
    door_lines=[0.3, -0.75], handles=[-0.1],
    seats=[(-0.2, True)],
    extras=[extras],
)

if __name__ == "__main__":
    build_car(SPEC)
