"""Van: tall cab-forward delivery van (5.2 x 2.0 x 2.2 m): sliding door, roof vent, rear doors, a glowing Vael-script stripe along the flank (baked glow)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402
from vehlib import glow_mat, trim_line  # noqa: E402


def extras(P, c):
    trim, chrome, T_black, T_dark, T_chrome, hw = c["trim"], c["chrome"], c["T_black"], c["T_dark"], c["T_chrome"], c["hw"]
    L, gc, belt = c["L"], c["gc"], c["belt"]
    zr = c["spec"]["z_roof"]
    mag = glow_mat("#ff39c8")
    xs = hw(0.0) * 0.972 + 0.004
    trim_line(P, mag, xs, -2.35, 1.25, belt + 0.28, 0.018, 0.03)                                  # the flank stripe
    for k in range(5):                                                                              # glyph blocks inside the stripe (alien script)
        trim_line(P, mag, xs + 0.002, -2.2 + k * 0.62, -2.05 + k * 0.62, belt + 0.45, 0.016, 0.06)
    trim_line(P, mag, xs, -2.4, 1.3, gc + 0.2, 0.016, 0.012)
    P.box((0.55, 0.9, 0.09), (0.0, -0.9, zr + 0.04), mat=trim, tint=T_dark, bevel=0.015, bsegs=2, top=(0.9, 0.85))                  # roof vent
    for sx in (1, -1):
        P.bar((sx * 0.8, 1.0, zr + 0.01), (sx * 0.8, -2.4, zr + 0.01), 0.04, 0.02, mat=trim, tint=T_black)                           # roof ribs
        P.box((0.016, 1.15, 0.03), (sx * (xs - 0.002), -0.55, belt - 0.45), mat=trim, tint=T_black, mirror=False)                    # sliding door rail
    P.box((0.022, 1.3, 0.04), (-(xs), -0.55, belt - 0.15), mat=trim, tint=T_black)
    P.box((0.026, 0.4, 0.09), (-(xs), -0.9, belt - 0.12), mat=chrome, tint=T_chrome, bevel=0.004)                                    # sliding door handle
    P.box((0.012, 0.012, 1.2), (0.0, -L / 2 - 0.004, 0.85), mat=trim, tint=T_black)                                                 # rear door seam
    for sz in (0.55, 1.25):
        for sx in (1, -1):
            P.box((0.12, 0.02, 0.05), (sx * 0.62, -L / 2 - 0.004, sz), mat=chrome, tint=T_chrome, bevel=0.004)                       # hinges
    P.box((1.7, 0.12, 0.16), (0, -L / 2 + 0.03, gc + 0.14), mat=trim, tint=T_black, bevel=0.015, bsegs=2)                            # rear bumper step
    P.box((1.5, 0.1, 0.12), (0, L / 2 - 0.04, gc + 0.12), mat=trim, tint=T_black, bevel=0.015, bsegs=2)                              # front bumper


SPEC = dict(
    name="car_van", seed=41,
    L=5.2, W=2.0, WB=3.2, gc=0.2, R=0.37, tw=0.235, track=1.7, spokes=5,
    paint="#cfd3d6", rim="#8d959c", spoke="#c3cad1", underglow="#ff39c8", atlas_paint=512, atlas=512,
    belt=1.12, taper=0.7, taper_amt=0.2,
    ztop=[(-2.6, 0.95), (-2.5, 1.1), (-2.2, 1.12), (-1.0, 1.12), (0.8, 1.1), (1.4, 1.06), (1.9, 1.0), (2.25, 0.92), (2.5, 0.8), (2.6, 0.7)],
    rise=(0.14, 0.12),
    gh=[(1.7, 1.08), (1.5, 1.4), (1.3, 1.72), (1.05, 2.0), (0.7, 2.12), (0.0, 2.15), (-1.5, 2.16), (-2.3, 2.14), (-2.5, 2.0), (-2.56, 1.5)],
    roof_front=0.95, roof_rear=-9.0, roof_w=0.9, z_roof=2.16,
    b_pillar=(-9.0, -9.0), side_glass=(0.15, 1.45),
    door_lines=[1.45, 0.25, -0.7, -2.1], handles=[0.95],
    seats=[(1.1, True), (1.1, True), (0.4, False)],
    extras=[extras], lod1=0.3,
)

if __name__ == "__main__":
    build_car(SPEC)
