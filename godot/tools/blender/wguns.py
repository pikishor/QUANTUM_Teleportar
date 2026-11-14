"""Firearm recipes of the weapon kit: long guns (assault, battle, carbine, DMR, sniper, SMG, shotgun, LMG) and pistols / revolvers. A recipe takes the geometry accumulator `g`, the palette `pal` and the
spec dict `s` (weapon_specs.py) and returns the anchors of the weapon (marker positions are set with g.mark in the kit frame). Distances are metres behind the muzzle; z = 0 is the bore axis."""
import math

import numpy as np

import weaponlib as wl
import weapon_mats as M
from weaponlib import Style
import wparts as wp
from wparts import rbox, tube, lathe_d, side_w, side, screw, seam, serrate, vent_row, rail, mlok, grip_texture, muzzle_device, optic, stock, pistol_grip, trigger_group, magazine, underbarrel


def _hg(g, kind, d0, d1, pal, w=0.046, top=0.026, bot=-0.026, rails=True):
    """Handguard between d0 (front) and d1 (rear). Returns the underside z."""
    fr = pal["frame"]
    body = pal["body"]
    dk = pal["dark"]
    f = pal["furn"]
    mt = pal["metal"]
    L = d1 - d0
    if kind in (None, "none"):
        return -0.012
    if kind == "quad":                                  # free float rail: a tall box with rails on four sides and slots
        rbox(g, d0, d1, bot, top, w, body, r=0.007, ch=0.003, seg=2)
        if rails:
            rail(g, d0 + 0.004, d1, top + 0.0075, dk, w=0.021, pitch=0.012)
            for sx in (-1.0, 1.0):
                rbox(g, d0 + 0.02, d1 - 0.02, -0.004, 0.004, 0.008, dk, r=0.0015, x=sx * (w / 2 + 0.003))
            rbox(g, d0 + 0.02, d1 - 0.02, bot - 0.007, bot + 0.004, 0.014, dk, r=0.0015)
        for sx in (-1.0, 1.0):
            mlok(g, d0 + 0.03, d1 - 0.03, 0.012, w / 2, dk, n=max(3, int(L / 0.05)), side_x=sx)
            mlok(g, d0 + 0.03, d1 - 0.03, -0.012, w / 2, dk, n=max(3, int(L / 0.05)), side_x=sx)
        return bot - 0.007
    if kind == "round":                                  # round handguard with vents and a heat shield look
        r = 0.027
        tube(g, d0, d1, r, body, n=16, ch=0.003)
        tube(g, d0 + 0.0, d0 + 0.012, r * 1.06, dk, n=16)
        tube(g, d1 - 0.012, d1, r * 1.06, dk, n=16)
        if g.fine:
            for k in range(5):
                d = d0 + 0.03 + k * (L - 0.07) / 4
                tube(g, d, d + 0.004, r * 1.04, dk, n=16)
        if rails:
            rail(g, d0 + 0.01, d1 - 0.005, r + 0.0045, dk, w=0.02, h=0.007)
        return -r
    if kind == "slotted":                                # polymer handguard with long vent slots
        rbox(g, d0, d1, bot, top, w, fr, r=0.011, ch=0.004, seg=2)
        for sx in (-1.0, 1.0):
            vent_row(g, d0 + 0.03, d1 - 0.03, 0.002, w / 2 + 0.0005, dk, n=max(3, int(L / 0.045)), h=0.026, w=0.02, both=False) if sx > 0 else None
        if g.fine:
            for sx in (-1.0, 1.0):
                for k in range(max(2, int(L / 0.06))):
                    d = d0 + 0.035 + k * 0.058
                    if d + 0.03 > d1:
                        break
                    g.box((sx * (w / 2 + 0.0004), -(d + 0.015), 0.0), (0.001, 0.03, 0.026), dk)
        if rails:
            rail(g, d0 + 0.004, d1, top + 0.0075, dk, w=0.021, pitch=0.013)
        return bot
    if kind == "wood":
        side_w(g, [(d0, top - 0.003), (d1, top), (d1, bot + 0.005), (d0 + L * 0.35, bot - 0.007), (d0, bot + 0.002)], w * 0.98, f, ch=0.004)
        rbox(g, d0 + L * 0.35, d1 - 0.01, bot + 0.012, bot + 0.02, w * 0.5, mt, r=0.001)
        serrate(g, d0 + L * 0.2, d0 + L * 0.7, bot + 0.008, top - 0.008, w * 0.49, pal["dark"], n=5)
        serrate(g, d0 + L * 0.2, d0 + L * 0.7, bot + 0.008, top - 0.008, -w * 0.49, pal["dark"], n=5)
        return bot - 0.007
    if kind == "tube":                                   # simple pipe handguard
        tube(g, d0, d1, 0.0185, pal["metal"], n=14, ch=0.002)
        tube(g, d1 - 0.012, d1, 0.0215, dk, n=14)
        return -0.0185
    if kind == "shroud":                                 # vented barrel shroud (LMG / DMR)
        r = 0.026
        tube(g, d0, d1, r, mt, n=16, ch=0.003)
        tube(g, d0, d0 + 0.014, r * 1.1, dk, n=16)
        if g.fine:
            for k in range(int(L / 0.022)):
                d = d0 + 0.026 + k * 0.022
                if d + 0.012 > d1 - 0.01:
                    break
                for ang in (0.0, math.pi / 3, -math.pi / 3, math.pi, math.pi * 2 / 3, -math.pi * 2 / 3):
                    g.box((math.cos(ang) * r, -(d + 0.006), math.sin(ang) * r), (0.002 if abs(math.cos(ang)) > 0.5 else 0.008, 0.012, 0.002 if abs(math.sin(ang)) > 0.5 else 0.008), dk)
        if rails:
            rail(g, d0 + 0.02, d1 - 0.005, r + 0.0045, dk, w=0.02, h=0.007)
        return -r
    if kind == "short":                                  # a short polymer stub
        rbox(g, d0, d1, bot + 0.004, top - 0.002, w * 0.9, fr, r=0.009, ch=0.003, seg=2)
        if rails:
            rail(g, d0 + 0.004, d1, top + 0.0055, dk, w=0.021, pitch=0.014)
        return bot + 0.004
    if kind == "ribbed":                                 # a sleeve with deep cooling rings
        r = 0.0245
        for k in range(int(L / 0.018)):
            d = d0 + k * 0.018
            if d + 0.012 > d1:
                break
            tube(g, d, d + 0.011, r, body, n=16)
            tube(g, d + 0.011, d + 0.018, r * 0.82, dk, n=12)
        return -r
    return -0.012


def _barrel(g, d_front_hg, d_rec, bbl_r, pal, muz, heavy=False, z=0.0):
    """Barrel from the muzzle (d=0) back into the handguard/receiver; gas block and front sight where the barrel leaves the handguard."""
    mt = pal["metal"]
    dk = pal["dark"]
    r = bbl_r
    g.cyl((0, 0.0, z), (0, -(d_rec), z), r, mt, n=12, chamfer=0.0015)
    ext = muzzle_device(g, muz, r, pal, z=z, d0=0.0)
    return ext


def _front_sight(g, d, z, pal, post=True, hood=True):
    dk = pal["dark"]
    if not post:
        return
    rbox(g, d - 0.012, d + 0.012, z, z + 0.012, 0.016, dk, r=0.002, ch=0.0015)                          # gas block / base
    rbox(g, d - 0.0015, d + 0.0015, z + 0.012, z + 0.036, 0.0035, dk, r=0.0008, ch=0.0005)                # post
    if hood:
        for sx in (-1.0, 1.0):
            rbox(g, d - 0.004, d + 0.004, z + 0.012, z + 0.036, 0.0025, dk, r=0.0005, x=sx * 0.0075)


def _rear_sight(g, d, z, pal):
    dk = pal["dark"]
    rbox(g, d - 0.01, d + 0.01, z, z + 0.012, 0.022, dk, r=0.002, ch=0.0015)
    for sx in (-1.0, 1.0):
        rbox(g, d - 0.005, d + 0.005, z + 0.012, z + 0.03, 0.0035, dk, r=0.0007, x=sx * 0.007)


def longgun(g, pal, s):
    """The generic long gun. s keys: rec (ar slab smg bolt pump box bullpup semi), rec_len, rec_h, hg (kind), hg_len, bbl (exposed barrel in front of the handguard), bbl_r, muz, stock, stock_len,
    grip, mag, mag_len, optic, under, extras (list), tube (shotgun magazine tube length), sights (bool)."""
    rec = s.get("rec", "ar")
    rec_len = s.get("rec_len", 0.27)
    hg_len = s.get("hg_len", 0.25)
    bbl = s.get("bbl", 0.06)
    bbl_r = s.get("bbl_r", 0.0095)
    rec_w = s.get("rec_w", 0.042)
    ex = set(s.get("extras", []))
    fr = pal["frame"]
    body = pal["body"]
    dk = pal["dark"]
    mt = pal["metal"]
    d_rf = bbl + hg_len                              # receiver front
    d_rr = d_rf + rec_len                            # receiver rear
    top = 0.036
    out = {}
    # ---------------------------------------------------------------- receiver
    zb = -0.010
    if rec == "ar":
        rbox(g, d_rf, d_rr, zb, top, rec_w, body, r=0.006, ch=0.003, seg=2)                          # upper receiver
        rbox(g, d_rf + 0.012, d_rr - 0.01, -0.046, zb + 0.003, rec_w * 0.92, fr, r=0.005, ch=0.003)  # lower receiver
        mw_d = s.get("mag_d", d_rf + rec_len * 0.55)
        rbox(g, mw_d - 0.026, mw_d + 0.028, -0.07, -0.04, rec_w * 0.88, fr, r=0.005, ch=0.003)       # magwell
        rbox(g, d_rr - 0.012, d_rr + 0.026, zb - 0.006, top - 0.006, rec_w * 0.7, dk, r=0.005)         # buffer tube base
        # ejection port with the bolt carrier (slide part)
        pd0, pd1 = d_rf + rec_len * 0.28, d_rf + rec_len * 0.62
        g.box((rec_w / 2 + 0.0004, -(pd0 + pd1) / 2, 0.016), (0.0014, pd1 - pd0, 0.02), dk)
        with g.in_part(wl.P_SLIDE):
            g.box((rec_w / 2 + 0.0008, -(pd0 + 0.012), 0.016), (0.0016, 0.02, 0.016), pal["bright"].k(0.8))
            rbox(g, d_rr - 0.04, d_rr - 0.016, top - 0.001, top + 0.01, 0.016, dk, r=0.002, ch=0.0015)   # charging handle (moves back with the bolt)
        seam(g, d_rf + 0.002, d_rr - 0.02, zb, zb + 0.0015, rec_w / 2, dk)
        seam(g, d_rf + 0.002, d_rr - 0.02, zb, zb + 0.0015, -rec_w / 2, dk)
        rail(g, d_rf + 0.004, d_rr - 0.004, top + 0.0075, dk, w=0.021)
        screw(g, (rec_w / 2, -(d_rf + 0.03), 0.026), pal["bright"], axis="x")
        screw(g, (rec_w / 2, -(d_rr - 0.04), 0.026), pal["bright"], axis="x")
        top_rail = top + 0.0075
        grip_front = d_rr - 0.075
        trig_z = -0.046
    elif rec == "slab":                                  # stamped slab receiver with a dust cover and a curved top
        pts = [(d_rf, top - 0.004), (d_rf + rec_len * 0.2, top + 0.003), (d_rf + rec_len * 0.8, top + 0.001), (d_rr, top - 0.006), (d_rr, zb - 0.002), (d_rf + rec_len * 0.55, zb - 0.002),
               (d_rf + rec_len * 0.48, -0.04), (d_rf + 0.01, -0.04), (d_rf, zb)]
        side_w(g, pts, rec_w, body, ch=0.003)
        mw_d = s.get("mag_d", d_rf + rec_len * 0.45)
        rbox(g, mw_d - 0.025, mw_d + 0.03, -0.06, -0.036, rec_w * 0.86, body, r=0.004, ch=0.002)
        pd0, pd1 = d_rf + rec_len * 0.3, d_rf + rec_len * 0.66
        g.box((rec_w / 2 + 0.0004, -(pd0 + pd1) / 2, 0.012), (0.0014, pd1 - pd0, 0.018), dk)
        with g.in_part(wl.P_SLIDE):
            rbox(g, pd0 - 0.01, pd0 + 0.014, 0.006, 0.02, rec_w * 1.02, pal["bright"].k(0.8), r=0.002, ch=0.001)
            g.box((rec_w / 2 + 0.0012, -(pd0 + 0.05), 0.0), (0.012, 0.012, 0.012), dk)                    # the cocking knob rides with the bolt
        # gas tube above the barrel
        g.cyl((0, -(d_rf - 0.01), 0.026), (0, -(bbl + 0.03), 0.026), 0.0085, dk, n=10)
        rbox(g, d_rf + rec_len * 0.5, d_rf + rec_len * 0.5 + 0.045, top, top + 0.01, 0.024, dk, r=0.002)       # rear sight base
        _rear_sight(g, d_rf + rec_len * 0.52 + 0.02, top + 0.01, pal)
        seam(g, d_rf, d_rr, top - 0.003, top, rec_w / 2, dk)
        top_rail = top + 0.003
        grip_front = d_rr - 0.065
        trig_z = -0.04
    elif rec == "smg":                                   # boxy blowback body
        rbox(g, d_rf, d_rr, -0.026, 0.034, rec_w, body, r=0.006, ch=0.003, seg=2)
        rbox(g, d_rf + 0.01, d_rr - 0.02, -0.045, -0.02, rec_w * 0.9, fr, r=0.004, ch=0.002)
        pd0, pd1 = d_rf + rec_len * 0.3, d_rf + rec_len * 0.62
        g.box((rec_w / 2 + 0.0004, -(pd0 + pd1) / 2, 0.012), (0.0014, pd1 - pd0, 0.016), dk)
        vent_row(g, d_rf + 0.02, d_rf + rec_len * 0.8, 0.0, rec_w / 2 + 0.0003, dk, n=int(rec_len / 0.04) + 1, h=0.02, w=0.012, both=False)
        with g.in_part(wl.P_SLIDE):
            g.box((rec_w / 2 + 0.0012, -(pd0 + 0.012), 0.012), (0.011, 0.018, 0.012), pal["bright"].k(0.7))
        rail(g, d_rf + 0.004, d_rr - 0.006, 0.0415, dk, w=0.02, h=0.0075)
        top_rail = 0.0415
        grip_front = d_rr - 0.06
        trig_z = -0.044
        zb = -0.026
        top = 0.034
    elif rec == "bolt":                                  # tubular action with a bolt handle
        rbox(g, d_rf, d_rr, zb, top, rec_w * 0.9, body, r=0.011, ch=0.004, seg=2)
        g.cyl((0, -(d_rf - 0.005), 0.004), (0, -(d_rf + rec_len * 0.55), 0.004), 0.021, mt, n=14, chamfer=0.002)
        with g.in_part(wl.P_SLIDE):
            hd = d_rf + rec_len * 0.56
            g.cyl((rec_w / 2, -hd, 0.012), (rec_w / 2 + 0.05, -hd, 0.002), 0.004, dk, n=8)               # bolt handle (travels back when cycled)
            g.sphere((rec_w / 2 + 0.054, -hd, 0.0), 0.0085, pal["bright"].k(0.5), n=8)
            rbox(g, hd - 0.012, hd + 0.012, 0.004, 0.022, 0.014, mt, r=0.002, x=rec_w * 0.4)
        rbox(g, d_rf + rec_len * 0.2, d_rf + rec_len * 0.5, 0.034, 0.041, 0.02, dk, r=0.002)
        rail(g, d_rf + 0.004, d_rr - 0.004, 0.0455, dk, w=0.021, h=0.0075)
        top_rail = 0.0455
        grip_front = d_rr - 0.07
        trig_z = -0.012
    elif rec == "pump":                                  # shotgun receiver with a loading port and a tube
        pts = [(d_rf, top), (d_rr, top - 0.004), (d_rr, -0.032), (d_rf + rec_len * 0.55, -0.04), (d_rf, -0.032)]
        side_w(g, pts, rec_w, body, ch=0.003)
        g.box((rec_w / 2 + 0.0004, -(d_rf + rec_len * 0.35), 0.012), (0.0014, rec_len * 0.3, 0.02), dk)
        g.box((0, -(d_rf + rec_len * 0.5), -0.04), (0.02, 0.05, 0.006), dk)                            # loading gate
        with g.in_part(wl.P_SLIDE):
            g.box((rec_w / 2 + 0.0012, -(d_rf + rec_len * 0.4), 0.016), (0.01, 0.02, 0.014), pal["bright"].k(0.6))
        rail(g, d_rf + 0.004, d_rr - 0.004, top + 0.0075, dk, w=0.021, pitch=0.014)
        top_rail = top + 0.0075
        grip_front = d_rr - 0.07
        trig_z = -0.032
        zb = -0.032
    elif rec == "box":                                   # machine gun body: fat box with a feed cover
        pts = [(d_rf, 0.046), (d_rr, 0.044), (d_rr, -0.024), (d_rf + rec_len * 0.5, -0.04), (d_rf, -0.034)]
        side_w(g, pts, rec_w * 1.35, body, ch=0.004)
        rbox(g, d_rf + 0.02, d_rf + rec_len * 0.7, 0.046, 0.06, rec_w * 1.0, dk, r=0.005, ch=0.003)     # feed cover
        with g.in_part(wl.P_SLIDE):
            g.box((rec_w * 0.7 + 0.0012, -(d_rf + rec_len * 0.55), 0.02), (0.012, 0.03, 0.014), pal["bright"].k(0.6))
        g.box((rec_w * 0.68 + 0.0004, -(d_rf + rec_len * 0.55), 0.02), (0.0014, 0.08, 0.026), dk)
        rail(g, d_rf + 0.04, d_rr - 0.02, 0.0675, dk, w=0.022, h=0.0075)
        top_rail = 0.0675
        grip_front = d_rr - 0.075
        trig_z = -0.034
        zb = -0.03
        top = 0.05
    elif rec == "bullpup":                               # the receiver runs back to the shoulder: a long body
        L2 = rec_len + s.get("stock_len", 0.2)
        pts = [(d_rf, top), (d_rf + L2 * 0.3, top + 0.006), (d_rf + L2 * 0.78, top - 0.0), (d_rf + L2, top - 0.022), (d_rf + L2, -0.082), (d_rf + L2 * 0.8, -0.082), (d_rf + L2 * 0.7, -0.05),
               (d_rf + L2 * 0.45, -0.044), (d_rf + L2 * 0.33, -0.058), (d_rf + 0.006, -0.058), (d_rf, -0.02)]
        side_w(g, pts, rec_w * 1.12, body, ch=0.004)
        rbox(g, d_rf + L2 - 0.014, d_rf + L2 + 0.003, -0.088, top - 0.024, rec_w * 1.12, pal["rub"], r=0.003)   # shoulder pad
        pd0 = d_rf + L2 * 0.22
        g.box((rec_w * 0.56 + 0.0004, -(pd0 + 0.04), 0.012), (0.0014, 0.06, 0.02), dk)
        rail(g, d_rf + 0.004, d_rf + L2 * 0.78, top + 0.0105, dk, w=0.021)
        top_rail = top + 0.0105
        d_rr = d_rf + L2
        grip_front = d_rf + L2 * 0.4
        trig_z = -0.046
        zb = -0.04
    else:                                                # "semi": a slim modern receiver
        side_w(g, [(d_rf, top), (d_rr, top - 0.002), (d_rr, zb), (d_rf + rec_len * 0.7, zb - 0.002), (d_rf + rec_len * 0.62, -0.04), (d_rf + 0.005, -0.04), (d_rf, zb)], rec_w, body, ch=0.003)
        rail(g, d_rf + 0.004, d_rr - 0.004, top + 0.0075, dk, w=0.021)
        pd0, pd1 = d_rf + rec_len * 0.3, d_rf + rec_len * 0.6
        g.box((rec_w / 2 + 0.0004, -(pd0 + pd1) / 2, 0.014), (0.0014, pd1 - pd0, 0.018), dk)
        with g.in_part(wl.P_SLIDE):
            g.box((rec_w / 2 + 0.001, -(pd0 + 0.01), 0.014), (0.0016, 0.018, 0.014), pal["bright"].k(0.7))
        top_rail = top + 0.0075
        grip_front = d_rr - 0.07
        trig_z = -0.04
    out["top_rail"] = top_rail
    # ---------------------------------------------------------------- handguard, barrel, muzzle
    hg_kind = s.get("hg", "quad")
    hg_under = _hg(g, hg_kind, bbl, d_rf, pal, w=s.get("hg_w", 0.046), rails=s.get("hg_rails", True))
    ext = _barrel(g, bbl, d_rf, bbl_r, pal, s.get("muz", "flash"), z=0.0)
    if s.get("sights", True) and hg_kind not in ("none",) and not ("scope" in s.get("optic", "") or s.get("optic") in ("thermal",)):
        _front_sight(g, bbl + 0.02, 0.026 if hg_kind in ("quad", "slotted", "short", "tube") else 0.0305 if hg_kind in ("round", "shroud") else 0.026, pal, hood=True)
    elif s.get("sights", True):
        _front_sight(g, bbl + 0.02, 0.026, pal, hood=False)
    if rec == "pump" or s.get("tube"):                   # tube magazine below the barrel
        tl = s.get("tube", hg_len + 0.1)
        g.cyl((0, -(bbl + 0.01), -0.027), (0, -(bbl + tl), -0.027), 0.0105, dk, n=10)
        tube(g, bbl + 0.0, bbl + 0.012, 0.0125, mt, z=-0.027, n=10)
        if rec == "pump":                                # the pump forend slides along the tube
            with g.in_part(wl.P_PUMP):
                pd = bbl + hg_len * 0.55
                rbox(g, pd - 0.07, pd + 0.07, -0.056, -0.002, 0.052, pal["furn"], r=0.012, ch=0.004, seg=2)
                serrate(g, pd - 0.05, pd + 0.05, -0.05, -0.012, 0.0265, dk, n=7)
                serrate(g, pd - 0.05, pd + 0.05, -0.05, -0.012, -0.0265, dk, n=7)
            hg_under = -0.056
    # ---------------------------------------------------------------- stock and grip
    st_kind = s.get("stock", "fixed")
    butt = d_rr
    if rec != "bullpup":
        butt = stock(g, st_kind, d_rr, pal, top=0.034, drop=zb + 0.0, w=s.get("stock_w", 0.036), length=s.get("stock_len", 0.26))
    grip_kind = s.get("grip", "std")
    gpos = pistol_grip(g, "slim" if grip_kind == "slim" else ("finger" if grip_kind == "finger" else "std"), grip_front, trig_z, pal, w=s.get("grip_w", 0.034), h=s.get("grip_h", 0.1), rake=s.get("rake", 0.3)) \
        if grip_kind != "none" else (grip_front, trig_z - 0.04)
    if grip_kind != "none":
        trigger_group(g, grip_front, trig_z, pal, guard_len=s.get("guard", 0.065))
    # ---------------------------------------------------------------- magazine
    mkind = s.get("mag", "box")
    mag_d = s.get("mag_d", d_rf + rec_len * (0.5 if rec != "bullpup" else 0.0) if rec != "bullpup" else grip_front + 0.095)
    if mkind != "none":
        zt = {"ar": -0.07, "slab": -0.06, "smg": -0.045, "bolt": -0.04, "pump": -0.04, "box": -0.04, "bullpup": -0.05, "semi": -0.04}.get(rec, -0.05)
        if mkind in ("box", "curved", "banana", "short", "long", "stick", "pistol"):
            magazine(g, mkind, mag_d, zt, pal, length=s.get("mag_len", 0.14), curve=s.get("mag_curve", 0.0))
        else:
            magazine(g, mkind, mag_d, zt, pal, length=s.get("mag_len", 0.14))
    # ---------------------------------------------------------------- optic on the top rail
    o = s.get("optic", "iron")
    lens = None
    if o != "none":
        opt_d = s.get("optic_d", d_rf + rec_len * 0.5)
        lens = optic(g, o, opt_d, top_rail, pal)
        if o != "iron" and s.get("backup_iron") and g.fine:
            _front_sight(g, bbl + 0.02, 0.026, pal)
    elif rec not in ("bullpup",) and s.get("sights", True):
        _rear_sight(g, d_rr - 0.04, top_rail, pal)
    # ---------------------------------------------------------------- underbarrel
    uh = underbarrel(g, s.get("under", "none"), s.get("under_d", bbl + hg_len * 0.55), hg_under, pal)
    # ---------------------------------------------------------------- extras
    if "carry" in ex:                                   # carry handle on top of the receiver
        ch_d0, ch_d1 = d_rf + 0.02, d_rr - 0.02
        for sx in (-1.0, 1.0):
            rbox(g, ch_d0, ch_d1, top_rail, top_rail + 0.03, 0.006, dk, r=0.002, x=sx * 0.012)
        rbox(g, ch_d0, ch_d1, top_rail + 0.026, top_rail + 0.034, 0.03, dk, r=0.003)
    if "side_laser" in ex:
        wp.side_laser(g, bbl + hg_len * 0.5, 0.0, pal, x=0.0, side_x=1.0)
    if "sling" in ex:
        rbox(g, d_rr - 0.03, d_rr - 0.012, -0.024, -0.008, 0.008, dk, r=0.002)
        rbox(g, bbl + 0.01, bbl + 0.024, -0.02, -0.004, 0.008, dk, r=0.002, x=0.0)
    if "cheek" in ex:
        rbox(g, d_rr + 0.01, d_rr + 0.11, 0.032, 0.05, 0.032, pal["rub"], r=0.005)
    if "ejection_chute" in ex:
        rbox(g, d_rf + 0.14, d_rf + 0.2, -0.008, 0.012, 0.012, dk, r=0.002, x=0.03)
    if "foregrip_rail" in ex:
        rbox(g, bbl + 0.04, bbl + 0.09, hg_under - 0.008, hg_under + 0.002, 0.03, dk, r=0.003)
    if "monopod" in ex:
        g.cyl((0, -(d_rr + 0.06), -0.05), (0, -(d_rr + 0.06), -0.14), 0.004, dk, n=8)
        rbox(g, d_rr + 0.05, d_rr + 0.07, -0.145, -0.138, 0.016, pal["rub"], r=0.002)
    # ---------------------------------------------------------------- markers and anchors
    g.mark("gr", (0.0, -(gpos[0]), gpos[1]))
    gl_d = s.get("gl_d", bbl + hg_len * 0.55)
    gl_z = (uh[1] if isinstance(uh, tuple) else hg_under) + 0.012 if s.get("under", "none") != "none" else hg_under + 0.014
    g.mark("gl", (0.0, -gl_d, gl_z))
    g.mark("eject", (0.02, -(d_rf + rec_len * 0.45), 0.015))
    g.mark("mag", (0.0, -mag_d, -0.06))
    g.mark("aim", (0.0, -(s.get("optic_d", d_rf + rec_len * 0.5)), top_rail + 0.03))
    g.mark("optic", lens["lens"] if lens else (0.0, -(d_rr - 0.04), top_rail + 0.02))
    g.mark("laser", (0.0, -(bbl + 0.01), -0.016))
    out.update({"butt": butt, "grip_d": gpos[0], "d_rr": d_rr, "d_rf": d_rf, "mag_d": mag_d, "length": butt + ext, "muz_ext": ext})
    return out


# ---------------------------------------------------------------------------------------------------------------------------------------- pistols
def _pistol_one(g, pal, s, x=0.0):
    """One semi-automatic pistol at lateral offset x. s: slide_len, slide_h, slide_w, grip_h, rake, muz, optic, mag ('flush', 'ext', 'drum', 'long'), brace, comp_cut, rail, style ('std','tac','heavy','match','compact')."""
    L = s.get("slide_len", 0.17)
    H = s.get("slide_h", 0.032)
    W = s.get("slide_w", 0.028)
    body = pal["metal"] if pal["_faction"] in ("service", "tactical", "desert", "arctic", "sport", "heritage", "industrial", "ordnance", "chrome", "gold", "toxic", "riot") else pal["body"]
    fr = pal["frame"]
    dk = pal["dark"]
    mt = pal["metal"]
    br = pal["bright"]
    style = s.get("style", "std")
    zt = 0.004 + H            # slide top
    r_top = 0.0075 if style in ("tac", "match") else 0.0055
    # slide as a side profile (front bevel, rear step) with rounded top via the box primitive underneath
    if style == "tac":
        pts = [(0.0, 0.004), (0.0, zt - 0.012), (0.014, zt), (L - 0.012, zt), (L, zt - 0.008), (L, 0.004)]
    elif style == "heavy":
        pts = [(0.0, 0.002), (0.0, zt - 0.006), (0.008, zt), (L - 0.008, zt + 0.002), (L, zt - 0.004), (L, 0.002)]
    else:
        pts = [(0.0, 0.004), (0.0, zt - 0.004), (0.006, zt), (L - 0.006, zt), (L, zt - 0.004), (L, 0.004)]
    with g.in_part(wl.P_SLIDE):
        side_w(g, pts, W, body, ch=0.0035, x=x)
        # round the top: a narrower upper strip
        rbox(g, 0.008, L - 0.008, zt - 0.006, zt + 0.0006, W * 0.62, body, r=0.0045, ch=0.002, x=x)
        # ejection port and its dark floor, serrations
        g.box((x + W / 2 + 0.0004, -(L * 0.5), zt - 0.016), (0.0014, L * 0.3, H * 0.4), dk)
        serrate(g, L - 0.046, L - 0.012, 0.01, zt - 0.006, x + W / 2 + 0.0002, dk, n=6, t=0.0016)
        serrate(g, L - 0.046, L - 0.012, 0.01, zt - 0.006, x - W / 2 - 0.0002, dk, n=6, t=0.0016)
        if style in ("tac", "match") and g.fine:
            serrate(g, 0.016, 0.04, 0.01, zt - 0.006, x + W / 2 + 0.0002, dk, n=4, t=0.0016)
            serrate(g, 0.016, 0.04, 0.01, zt - 0.006, x - W / 2 - 0.0002, dk, n=4, t=0.0016)
        if s.get("cuts"):                                     # lightening cuts / ports through the slide top
            for k in range(3):
                g.box((x, -(0.045 + k * 0.012), zt + 0.0004), (W * 0.45, 0.006, 0.0012), dk)
        if s.get("optic") in (None, "none", "iron"):
            rbox(g, 0.006, 0.014, zt, zt + 0.009, 0.0045, dk, r=0.0008, x=x)                  # front sight
            for sx in (-1.0, 1.0):
                rbox(g, L - 0.019, L - 0.012, zt, zt + 0.008, 0.005, dk, r=0.0008, x=x + sx * 0.0045)
    # barrel tip + muzzle device
    brr = 0.0058 if style != "heavy" else 0.0085
    g.cyl((x, 0.004, 0.0), (x, -0.04, 0.0), brr, mt, n=12)
    muzzle_device(g, s.get("muz", "none"), brr, pal, z=0.0, x=x, d0=0.004)
    # frame: dust cover and rail, trigger guard, grip
    fh = 0.014
    rbox(g, 0.004, L + 0.004, 0.004 - fh, 0.0045, W * 0.86, fr, r=0.004, ch=0.003, x=x)
    if s.get("rail", style in ("tac", "heavy", "match")):
        rail(g, 0.018, 0.08, 0.004 - fh + 0.0005, dk, w=0.0185, h=0.006, pitch=0.01, x=x, teeth=True)
    gh = s.get("grip_h", 0.098)
    gd = L - 0.075
    gpos = pistol_grip(g, "finger" if style == "heavy" else "std", gd, 0.004 - fh * 0.5, pal, w=s.get("grip_w", 0.032), h=gh, rake=s.get("rake", 0.2), x=x)
    trigger_group(g, gd, 0.004 - fh, pal, x=x, guard_len=0.06 if style != "compact" else 0.05, guard_drop=0.034)
    # hammer / spur
    g.box((x, -(L + 0.004), zt - 0.01), (0.008, 0.012, 0.014), dk)
    # magazine extension
    mk = s.get("mag", "flush")
    if mk in ("ext", "long"):
        magazine(g, "pistol", gd + 0.03 + gh * 0.2 * math.tan(0.2), 0.004 - fh * 0.5 - gh + 0.004, pal, w=0.027, length=0.06 if mk == "ext" else 0.12, x=x)
    elif mk == "drum":
        magazine(g, "drum", gd + 0.04, 0.004 - fh - gh + 0.01, pal, x=x)
    # optic on the slide (mini reflex) or a laser under the dust cover
    o = s.get("optic", "iron")
    lens = None
    if o not in ("iron", "none", None):
        lens = optic(g, o, L * 0.55, zt, pal, x=x)
    if s.get("laser"):
        rbox(g, 0.02, 0.05, -0.016, -0.007, 0.016, dk, r=0.002, x=x)
        tube(g, 0.012, 0.022, 0.0055, dk, z=-0.011, x=x, n=8)
        tube(g, 0.0118, 0.0124, 0.0035, pal["lens_glow"], z=-0.011, x=x, n=8)
    if s.get("brace"):
        stock(g, "brace", L + 0.004, pal, top=zt - 0.02, drop=-0.02, w=0.03, x=x)
    return {"gr": (x, gd + 0.016, gpos[1]), "L": L, "gd": gd, "gh": gh, "zt": zt, "lens": lens}


def pistol(g, pal, s):
    """A pistol (or twin pistols: s['twin'] puts one at x = +0.075 and one at x = -0.075)."""
    xs = (0.075, -0.075) if s.get("twin") else (0.0,)
    infos = []
    for i, x in enumerate(xs):
        infos.append(_pistol_one(g, pal, s, x=x))
    inf = infos[0]
    gr = inf["gr"]
    g.mark("gr", (gr[0], -gr[1], gr[2]))
    if s.get("twin"):
        gl = infos[1]["gr"]
        g.mark("gl", (gl[0], -gl[1], gl[2]))
    else:
        g.mark("gl", (-0.022, -(inf["gd"] + 0.004), gr[2] - 0.012))
    g.mark("eject", (xs[0] + 0.016, -inf["L"] * 0.5, inf["zt"] - 0.016))
    g.mark("mag", (xs[0], -(inf["gd"] + 0.03), -0.09))
    g.mark("aim", (xs[0], -inf["L"] * 0.55, inf["zt"] + 0.03))
    g.mark("optic", inf["lens"]["lens"] if inf["lens"] else (xs[0], -inf["L"] + 0.012, inf["zt"] + 0.008))
    g.mark("laser", (xs[0], -0.02, -0.011))
    return {"length": inf["L"] + 0.01, "butt": inf["L"], "muz_ext": 0.0}


def revolver(g, pal, s):
    """A revolver: frame with a fluted cylinder (rotor part), a barrel with a rib and shroud, a hammer (hammer part), wood or rubber grip."""
    mt = pal["metal"]
    dk = pal["dark"]
    br = pal["bright"]
    fr = pal["frame"]
    bl = s.get("bbl_len", 0.1)
    cyl_r = s.get("cyl_r", 0.026)
    cl = s.get("cyl_len", 0.056)
    cd0 = bl                                           # cylinder front
    cd1 = bl + cl
    # barrel with a rib on top and an underlug
    g.cyl((0, 0.0, 0.0), (0, -(bl + 0.02), 0.0), 0.0075, mt, n=14, chamfer=0.001)
    muzzle_device(g, s.get("muz", "crown"), 0.0075, pal, z=0.0, d0=0.0)
    rbox(g, 0.0, bl + 0.01, 0.0075, 0.0125, 0.007, mt, r=0.001, ch=0.001)                         # rib
    rbox(g, 0.0, bl * 0.9, -0.0185, -0.0065, 0.016, mt, r=0.003, ch=0.002)                         # underlug
    rbox(g, 0.01, 0.019, 0.0125, 0.02, 0.006, dk, r=0.0008)                                         # front sight
    # frame: a top strap over the cylinder, a body below and behind it, a solid standing breech
    rbox(g, bl - 0.012, cd1 + 0.05, 0.0155, 0.034, 0.022, mt, r=0.005, ch=0.003, seg=2)
    side_w(g, [(cd1 - 0.004, 0.0155), (cd1 + 0.05, 0.0155), (cd1 + 0.05, 0.004), (cd1 + 0.02, -0.03), (cd1 - 0.006, -0.034), (cd1 - 0.004, -0.01)], 0.024, mt, ch=0.003)
    rbox(g, bl - 0.012, cd1 - 0.004, -0.034, -0.012, 0.02, mt, r=0.004, ch=0.002)
    for sx in (-1.0, 1.0):
        g.cyl((sx * 0.012, -(bl - 0.012), 0.0), (sx * 0.012, -(cd0 - 0.002), 0.0), 0.0035, dk, n=6)
    # cylinder (rotor): a lathe with flutes
    with g.in_part(wl.P_ROTOR):
        lathe_d(g, [(cd0, cyl_r * 0.9), (cd0 + 0.004, cyl_r), (cd1 - 0.004, cyl_r), (cd1, cyl_r * 0.9)], br.t(tint=tuple(c * 0.6 for c in br.tint)), z=0.0, n=18, hard=(1, 2))
        if g.fine:
            for k in range(6):
                a = 2 * math.pi * k / 6
                g.box((math.cos(a) * cyl_r, -(cd0 + cl * 0.5), math.sin(a) * cyl_r), (0.006 if abs(math.cos(a)) > 0.5 else 0.01, cl * 0.55, 0.006 if abs(math.sin(a)) > 0.5 else 0.01), dk)
    g.mark("rotor", (0.0, -(cd0 + cl * 0.5), 0.0))
    # hammer and trigger
    with g.in_part(wl.P_HAMMER):
        side_w(g, [(cd1 + 0.036, 0.034), (cd1 + 0.056, 0.044), (cd1 + 0.062, 0.036), (cd1 + 0.05, 0.026), (cd1 + 0.036, 0.026)], 0.008, dk, ch=0.001)
    g.mark("hinge", (0.0, -(cd1 + 0.05), 0.03))
    gd = cd1 + 0.015
    gpos = pistol_grip(g, "palm", gd, -0.026, pal, w=0.034, h=s.get("grip_h", 0.105), rake=0.32)
    # wooden grip panels
    for sx in (-1.0, 1.0):
        side_w(g, [(gd + 0.008, -0.034), (gd + 0.05, -0.034), (gd + 0.07, -0.12), (gd + 0.026, -0.125)], 0.004, pal["wood"] if pal["_faction"] in ("sport", "heritage", "chrome", "gold") else pal["rub"], ch=0.001, x=sx * 0.018)
    trigger_group(g, gd, -0.03, pal, guard_len=0.07, guard_drop=0.04)
    o = s.get("optic", "iron")
    lens = None
    if o not in ("iron", "none", None):
        lens = optic(g, o, bl * 0.9, 0.0125, pal)
    g.mark("gr", (0.0, -(gpos[0] + 0.01), gpos[1]))
    g.mark("gl", (-0.024, -(gd + 0.01), gpos[1] - 0.012))
    g.mark("eject", (0.0, -(cd1 + 0.02), 0.0))
    g.mark("mag", (0.0, -(cd0 + cl * 0.5), -0.03))
    g.mark("aim", (0.0, -(cd1 + 0.04), 0.045))
    g.mark("optic", lens["lens"] if lens else (0.0, -(cd1 + 0.045), 0.04))
    g.mark("laser", (0.0, -0.02, -0.0185))
    return {"length": cd1 + 0.07, "butt": cd1 + 0.07, "muz_ext": 0.0}
