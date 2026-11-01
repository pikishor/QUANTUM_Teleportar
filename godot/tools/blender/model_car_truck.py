"""Truck: cab-over box truck (6.4 x 2.1 x 3.0 m) with a ribbed cargo box, rear roll door, side underrun rails and glowing hazard trim (baked glow)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402
from vehlib import glow_mat, trim_line  # noqa: E402


def extras(P, c):
    trim, chrome, body, T_black, T_dark, T_chrome, hw = c["trim"], c["chrome"], c["body"], c["T_black"], c["T_dark"], c["T_chrome"], c["hw"]
    L, gc = c["L"], c["gc"]
    amber = glow_mat("#ffb21a")
    zdeck = 1.0
    bx_len, bx_h, bx_w = 4.3, 1.95, 2.12
    yc = -1.15
    P.box((bx_w, bx_len, bx_h), (0, yc, zdeck + bx_h * 0.5), mat=body, bevel=0.045, bsegs=2, top=(0.985, 0.99))              # cargo box
    P.box((bx_w + 0.03, bx_len + 0.02, 0.07), (0, yc, zdeck + 0.03), mat=trim, tint=T_dark, bevel=0.01)                      # floor frame
    P.box((bx_w + 0.02, bx_len + 0.02, 0.05), (0, yc, zdeck + bx_h), mat=trim, tint=T_dark, bevel=0.01)                      # roof cap
    for k in range(6):                                                                                                       # side ribs
        y = yc + bx_len * 0.5 - 0.35 - k * 0.72
        P.box((bx_w + 0.03, 0.045, bx_h - 0.15), (0, y, zdeck + bx_h * 0.5), mat=trim, tint=T_dark, bevel=0.006)
    xs = bx_w * 0.5 + 0.012
    trim_line(P, amber, xs, yc - bx_len * 0.5 + 0.2, yc + bx_len * 0.5 - 0.2, zdeck + 0.3, 0.016, 0.03)                       # hazard lines
    trim_line(P, amber, xs, yc - bx_len * 0.5 + 0.2, yc + bx_len * 0.5 - 0.2, zdeck + bx_h - 0.25, 0.016, 0.02)
    P.box((1.5, 0.014, 0.02), (0, yc - bx_len * 0.5 - 0.008, zdeck + bx_h - 0.4), mat=amber)                                  # rear glow bar
    P.box((1.9, 0.014, 1.5), (0, yc - bx_len * 0.5 - 0.004, zdeck + 0.95), mat=trim, tint=T_dark, bevel=0.003)                  # roll door panel
    for k in range(7):
        P.box((1.85, 0.012, 0.012), (0, yc - bx_len * 0.5 - 0.012, zdeck + 0.3 + k * 0.2), mat=trim, tint=T_black)
    for sx in (1, -1):                                                                                                       # side underrun rails, mud flaps
        P.bar((sx * 0.98, yc + 1.2, 0.5), (sx * 0.98, yc - 1.6, 0.5), 0.05, 0.06, mat=chrome, tint=T_chrome, bevel=0.008)
    P.box((2.0, 0.16, 0.3), (0, -L / 2 + 0.02, 0.62), mat=trim, tint=T_dark, bevel=0.015)                                    # rear bumper
    P.box((1.9, 0.1, 0.18), (0, L / 2 - 0.05, gc + 0.18), mat=trim, tint=T_dark, bevel=0.015)                                 # front bumper
    zr = c["spec"]["z_roof"]
    P.box((0.9, 0.5, 0.1), (0, 1.62, zr + 0.04), mat=trim, tint=T_dark, bevel=0.012, top=(0.9, 0.9))                         # cab air deflector
    for sx in (1, -1):                                                                                                       # tall mirrors, exhaust stack
        P.bar((sx * 1.18, 2.35, 1.7), (sx * 1.18, 2.35, 1.2), 0.04, 0.03, mat=trim, tint=T_black)
        P.box((0.06, 0.1, 0.34), (sx * 1.2, 2.3, 1.5), mat=trim, tint=T_black, bevel=0.01)
    P.cyl(0.05, 1.6, (1.0, 1.2, 1.6), mat=chrome, tint=T_chrome, segs=10)


SPEC = dict(
    name="car_truck", seed=43,
    L=6.4, W=2.1, WB=4.0, gc=0.32, R=0.42, tw=0.27, track=1.82, spokes=8,
    paint="#8f9ba3", rim="#7d858c", spoke="#b0b7be", underglow="#ffb21a", atlas_paint=512, atlas=512,
    belt=1.25, taper=0.7, taper_amt=0.2,
    ztop=[(-3.2, 1.0), (-3.1, 1.0), (-1.0, 1.0), (1.0, 1.0), (1.3, 1.1), (1.55, 1.18), (2.4, 1.18), (2.8, 1.08), (3.1, 0.95), (3.2, 0.85)],
    rise=(0.12, 0.10),
    gh=[(2.45, 1.18), (2.35, 1.5), (2.2, 1.88), (2.0, 2.12), (1.7, 2.22), (1.35, 2.24), (1.15, 2.2), (1.1, 1.9), (1.05, 1.2)],
    roof_front=1.75, roof_rear=-9.0, roof_w=0.88, z_roof=2.24,
    b_pillar=(-9.0, -9.0), side_glass=(1.15, 2.35),
    door_lines=[2.3, 1.45], handles=[1.7],
    seats=[(1.9, True), (1.9, True), (1.9, False)],
    extras=[extras], lod1=0.3,
)

if __name__ == "__main__":
    build_car(SPEC)
