"""Wagon: long-roof estate (4.9 m) on the sedan platform: roof rails, a tailgate spoiler, a rear wash-wipe lens, violet-teal trim lines (baked glow)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402
from vehlib import glow_mat, trim_line  # noqa: E402


def extras(P, c):
    trim, chrome, T_black, T_dark, T_chrome, hw = c["trim"], c["chrome"], c["T_black"], c["T_dark"], c["T_chrome"], c["hw"]
    L, gc, belt = c["L"], c["gc"], c["belt"]
    zr = c["spec"]["z_roof"]
    tealg = glow_mat("#2cf0c8")
    for sx in (1, -1):                                                                  # roof rails with two cross bars
        P.bar((sx * 0.56, 0.0, zr + 0.035), (sx * 0.56, -2.0, zr + 0.035), 0.03, 0.026, mat=chrome, tint=T_chrome, bevel=0.004)
        for y in (-0.15, -1.85):
            P.bar((sx * 0.56, y, zr + 0.005), (sx * 0.56, y, zr + 0.03), 0.034, 0.026, mat=trim, tint=T_black)
    for y in (-0.55, -1.45):
        P.bar((-0.56, y, zr + 0.052), (0.56, y, zr + 0.052), 0.02, 0.016, mat=trim, tint=T_dark, bevel=0.003)
    P.box((1.3, 0.16, 0.035), (0, -L / 2 + 0.14, zr - 0.30), mat=trim, tint=T_black, bevel=0.01, rot=(8, 0, 0))                # tailgate lip spoiler
    for sx in (1, -1):
        trim_line(P, tealg, hw(0.0) * 0.972 + 0.004, -1.9, 1.9, gc + 0.2, 0.016, 0.012)
        trim_line(P, tealg, hw(0.0) * 0.972 + 0.004, -2.0, 0.6, belt - 0.07, 0.01, 0.01, mirror=False) if sx == 1 else None
    P.box((0.5, 0.012, 0.02), (0, -L / 2 - 0.0, c["ztop"](-L / 2 + 0.05) - 0.3), mat=tealg)                                        # light bar over the plate


SPEC = dict(
    name="car_wagon", seed=37,
    L=4.92, W=1.90, WB=2.9, gc=0.13, R=0.35, tw=0.24, track=1.66, spokes=6,
    paint="#7a6a9c", rim="#8d959c", spoke="#c3cad1", underglow="#2cf0c8", atlas_paint=512, atlas=512,
    belt=0.92, taper=0.55, taper_amt=0.2,
    ztop=[(-2.46, 0.78), (-2.38, 0.98), (-2.2, 1.04), (-1.6, 1.05), (-1.0, 1.0), (0.8, 0.92), (1.05, 0.935), (1.5, 0.9), (2.0, 0.83),
          (2.3, 0.74), (2.46, 0.66)],
    rise=(0.10, 0.12),
    gh=[(0.8, 0.95), (0.66, 1.04), (0.5, 1.17), (0.32, 1.3), (0.12, 1.41), (-0.2, 1.47), (-1.0, 1.49), (-1.7, 1.48), (-2.0, 1.44),
        (-2.18, 1.3), (-2.3, 1.1), (-2.36, 1.0)],
    roof_front=-0.05, roof_rear=-2.05, roof_w=0.76, z_roof=1.49,
    b_pillar=(-0.52, -0.40), side_glass=(-2.0, 0.1),
    door_lines=[0.45, -0.48, -1.35], handles=[0.0, -0.95, -1.7],
    seats=[(-0.05, True), (-1.05, True), (-1.8, False)],
    extras=[extras], lod1=0.3,
)

if __name__ == "__main__":
    build_car(SPEC)
