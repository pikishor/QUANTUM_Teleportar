"""Taxi: the sedan platform as a cab (4.74 m): roof sign, amber trim lines along the sills, a chequer band, brighter underglow. Alien sci-fi: the sign and the trim are baked glow."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from carlib import build_car  # noqa: E402
from model_car_sedan import SPEC as SEDAN  # noqa: E402
from vehlib import glow_mat, trim_line  # noqa: E402


def extras(P, c):
    trim, T_black, T_dark, hw = c["trim"], c["T_black"], c["T_dark"], c["hw"]
    gc, belt, W = c["gc"], c["belt"], c["W"]
    zr = c["spec"]["z_roof"]
    amber = glow_mat("#ffb21a")
    # roof sign: a dark base, a glowing lens, two end caps
    P.box((0.62, 0.24, 0.035), (0, -0.45, zr + 0.015), mat=trim, tint=T_black, bevel=0.006)
    P.box((0.56, 0.2, 0.10), (0, -0.45, zr + 0.085), mat=amber, bevel=0.012, bsegs=2, top=(0.92, 0.9))
    P.box((0.6, 0.012, 0.05), (0, -0.325, zr + 0.06), mat=trim, tint=T_black)
    P.box((0.6, 0.012, 0.05), (0, -0.575, zr + 0.06), mat=trim, tint=T_black)
    # trim lines along the sills and the beltline, a thin line over the hood
    for y0, y1, z, w in ((-1.85, 1.85, gc + 0.19, 0.016), (-1.7, 1.7, belt - 0.2, 0.012)):
        trim_line(P, amber, hw(0.0) * 0.972 + 0.004, y0, y1, z, w, 0.012)
    P.box((0.012, 1.2, 0.01), (0.34, 1.5, 0.78), mat=amber, mirror=True)
    # roof aerial and a dash of "meter" on the rear window shelf
    P.rod((0.5, -1.15, zr), (0.55, -1.30, zr + 0.2), 0.006, mat=trim, tint=T_black, segs=5)


SPEC = dict(SEDAN, name="car_taxi", seed=31, paint="#d8a728", rim="#a8aeb4", spoke="#d2d8dd", underglow="#ffb21a", atlas_paint=512, atlas=512,
            spokes=7, extras=[extras], lod1=0.3, seats=[(-0.05, True), (-1.0, True)])

if __name__ == "__main__":
    build_car(SPEC)
