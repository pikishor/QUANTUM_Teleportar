#!/usr/bin/env python3
"""The layers of a weapon sound (wave 114, scripts/audio/weapon_audio.gd): what a shot is made of, as separate files the game mixes at run time, so that a weapon is not one recording but a click,
a body, a tail and (indoors) a room.

  wm_*       MECHANISM clicks, 12 kinds x 2 takes (slide light / heavy, bolt, pump, revolver cylinder, energy charge-up, rotary spin-up, bow string, grenade pin, mine arming, strike beacon, trigger, cell)
  wt_*       TAILS, 8 kinds x 2 takes (small, medium, large, huge outdoors; room, hall indoors; canyon with echoes; dry): what the air does after the shot, played a few ms late on the Tail bus
  shot_v4_*  new BODIES for the classes that had too few: auto shotgun, slug gun, sawn-off, rocket, heavy rocket, grenade launcher, mortar, throw, mine, strike call (3 takes each)
  wr_*, we_* RELOAD sounds per class (pistol, smg, rifle, shotgun, sniper, lmg, launcher, energy, 2 takes) and EQUIP sounds (light, heavy, energy, melee)
  bm_*       EXPLOSIONS by size, 4 sizes x 3 takes: small (radius under 4 m), medium (4 to 9), large (9 to 18), huge (over 18); picked from the BlastTable radius
  impact_* / ricochet_*  materials that had no sound (wood, dirt, water, foliage, armour, shield) and two ricochets (metal, stone)
  hit_*      HIT and KILL markers (hit, head, armour, shield, crit, kill head, kill blast, kill streak): short, clean, never above -12 dBFS
Everything comes from the CC0 clips of art_sources/audio_*/clips (docs/AUDIO_SOURCES.md) plus our own synthesis (tones, noise, echoes); no new downloads.
Run: python3 tools/audio/make_weapons_v4.py [out_dir] [--only glob ...]      (numpy and ffmpeg; then tools/import.sh; the OGG files go to assets/audio)
"""
import fnmatch
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_real as mrl  # noqa: E402
import make_redesign as mr  # noqa: E402
import make_audio as ma  # noqa: E402

C = mrl.C
mix = mrl.mix
part = mrl.part
SR = mrl.SR


def n_(s):
    return int(s * SR)


def rs(seed):
    return np.random.default_rng(seed)


def noise_burst(seed, dur, lo, hi, decay, attack=0.004):
    n = n_(dur)
    t = np.arange(n) / SR
    x = mr.band(rs(seed).standard_normal(n), lo, hi)
    return x * np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t * decay)


def tone(f0, dur, decay=14.0, f1=None, harm=(1.0,), attack=0.002):
    n = n_(dur)
    t = np.arange(n) / SR
    f = np.full(n, f0) if f1 is None else f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = sum(h * np.sin(ph * (k + 1)) for k, h in enumerate(harm))
    return x * np.minimum(1.0, t / attack) * np.exp(-t * decay)


def sm(sigs, length):
    """Sum of signals of different lengths, all starting at 0."""
    return mix([(np.asarray(x, dtype=np.float64), 0.0) for x in sigs], length)


def seg(cid, length, **kw):
    """A clip cut or zero-padded to exactly `length` seconds."""
    x = C(cid, **kw)[0]
    n = n_(length)
    return x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])


def master_set(name, makers, peak, crest=8.0, hp=80.0, fade=0.05, max_len=None):
    for i, mk in enumerate(makers):
        nm = name if i == 0 else "%s_%d" % (name, i)
        if mrl.ONLY and not any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            continue
        x = mk()
        mrl.emit(nm, mr.master(x, peak, crest, hp, fade, max_len), ogg=True)


# ------------------------------------------------------------------------------------------------------------------------------------ mechanisms
def build_mech():
    P = -17.0
    master_set("wm_slide_l", [lambda i=i: mix([C("equip_click_a", hp=1500, semis=i), C("mi_clink1", db=-8, delay=0.045, semis=4 + i, hp=1800), C("ki_tick4", db=-14, delay=0.09, hp=2000)], 0.22) for i in range(2)], P, 9.0, 300.0, 0.05, 0.22)
    master_set("wm_slide_h", [lambda i=i: mix([C("mi_clink3", semis=-4 - i, lp=6000), C("qi_metal", db=-10, delay=0.05, semis=-5, lp=3000), C("equip_click_b", db=-6, delay=0.12, lp=3500)], 0.3) for i in range(2)], P, 8.0, 150.0, 0.08, 0.3)
    master_set("wm_bolt", [lambda i=i: mix([C("mi_clink2", semis=-2 + i), C("qi_metal", db=-8, delay=0.07, semis=-6, lp=2500), C("mi_clink1", db=-6, delay=0.2, semis=2)], 0.34) for i in range(2)], P, 8.0, 200.0, 0.08, 0.34)
    master_set("wm_pump", [lambda i=i: mix([C("shotgun_cock", length=0.34, semis=-2 * i), C("mi_clink3", db=-14, delay=0.2, semis=-3)], 0.36) for i in range(2)], P + 1.0, 7.0, 120.0, 0.08, 0.36)
    master_set("wm_cyl", [lambda i=i: mix([C("ki_tick2", hp=1800), C("mi_clink1", delay=0.03, semis=7 - i, hp=1500), C("ki_tick4", db=-6, delay=0.07)], 0.2) for i in range(2)], P, 9.0, 300.0, 0.05, 0.2)
    master_set("wm_charge", [lambda i=i: tone(260 + 40 * i, 0.26, decay=4.0, f1=1700 + 200 * i, harm=(1.0, 0.4, 0.2)) * 0.7 + noise_burst(40 + i, 0.26, 2000, 9000, 6.0) * 0.12 for i in range(2)], P, 8.0, 150.0, 0.06, 0.28)
    master_set("wm_spin", [lambda i=i: seg("veh_loop1", 0.4, semis=9 + 2 * i, lp=2600) * np.minimum(1.0, np.arange(n_(0.4)) / n_(0.3)) for i in range(2)], P - 1.0, 9.0, 200.0, 0.1, 0.4)
    master_set("wm_string", [lambda i=i: mrl.twang(500 + i, 520.0 + 60.0 * i, 160.0, 0.32, 14.0 + i) for i in range(2)], P - 2.0, 9.0, 100.0, 0.08, 0.34)
    master_set("wm_pin", [lambda i=i: mix([C("mi_clink1", semis=6 + i, hp=2000), C("st_metal_03", db=-6, delay=0.06, hp=900, lp=6000), C("sw_5", db=-16, lp=5000)], 0.3) for i in range(2)], P, 8.0, 300.0, 0.06, 0.3)
    master_set("wm_mine", [lambda i=i: mix([C("mi_thud2", db=-4, lp=900, semis=-2 * i), part(tone(1800 + 200 * i, 0.05, decay=60.0), -10.0, 0.14), part(tone(1800 + 200 * i, 0.05, decay=60.0), -10.0, 0.24)], 0.34) for i in range(2)], P, 8.0, 80.0, 0.06, 0.34)
    master_set("wm_beacon", [lambda i=i: mix([part(tone(880 * (1 + 0.06 * i), 0.18, decay=14.0, harm=(1.0, 0.3)), 0.0, 0.0), part(tone(1320 * (1 + 0.06 * i), 0.18, decay=14.0, harm=(1.0, 0.3)), -2.0, 0.12), part(tone(1760 * (1 + 0.06 * i), 0.22, decay=12.0, harm=(1.0, 0.3)), -3.0, 0.24)], 0.5) for i in range(2)], P, 8.0, 300.0, 0.08, 0.5)
    master_set("wm_trigger", [lambda i=i: mix([C("ki_tick2", hp=2000, length=0.05, semis=i), C("equip_click_a", db=-10, hp=2500, length=0.05, delay=0.012)], 0.09) for i in range(2)], P - 2.0, 9.0, 600.0, 0.02, 0.09)
    master_set("wm_cell", [lambda i=i: mix([C("kn_forcefield2", lp=5000, length=0.25, semis=5 + i), C("ki_click3", db=-4, delay=0.0, hp=1500)], 0.28) for i in range(2)], P - 1.0, 8.0, 150.0, 0.06, 0.28)


# ------------------------------------------------------------------------------------------------------------------------------------ tails
def tail(seed, rt, lo, hi, predelay=0.03, rise=0.012):
    n = n_(rt * 1.15 + predelay)
    t = np.arange(n) / SR
    x = mr.band(rs(seed).standard_normal(n), lo, hi)
    env = np.minimum(1.0, np.maximum(t - predelay, 0.0) / rise) * np.exp(-6.91 * np.maximum(t - predelay, 0.0) / rt)
    return x * env


def canyon(seed, rt):
    out = np.zeros(n_(rt + 0.6))
    r = rs(seed)
    for k, d in enumerate((0.09, 0.19, 0.33, 0.52)):
        b = noise_burst(seed + k, 0.18, 300, 3200, 22.0, 0.006) * (0.7 ** k)
        i = n_(d + r.uniform(-0.01, 0.01))
        out[i:i + len(b)] += b[:len(out) - i]
    tl = tail(seed + 9, rt * 0.7, 200, 2400, 0.06) * 0.35
    out[:len(tl)] += tl[:len(out)]
    return out


def build_tails():
    P = -23.0
    specs = [("wt_small", 0.35, 250, 4500, 0.025), ("wt_medium", 0.7, 200, 3500, 0.03), ("wt_large", 1.3, 150, 2800, 0.04), ("wt_huge", 2.4, 90, 1800, 0.06),
             ("wt_room", 0.45, 300, 6000, 0.012), ("wt_hall", 1.2, 200, 4500, 0.02), ("wt_dry", 0.12, 800, 6000, 0.008)]
    for name, rt, lo, hi, pre in specs:
        master_set(name, [lambda i=i, rt=rt, lo=lo, hi=hi, pre=pre: tail(600 + i * 7 + int(rt * 100), rt, lo, hi, pre) for i in range(2)], P, 10.0, 60.0, rt * 0.3, rt * 1.4)
    master_set("wt_canyon", [lambda i=i: canyon(700 + i, 0.9) for i in range(2)], P, 10.0, 80.0, 0.4, 1.6)


# ------------------------------------------------------------------------------------------------------------------------------------ bodies
def body_set(name, cls, peak, length, takes, body=0.5, presence=0.8, tail_=None, body_f=None, seed=0, crest=7.0):
    for i, take in enumerate(takes):
        nm = name if i == 0 else "%s_%d" % (name, i)
        if mrl.ONLY and not any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            continue
        parts = [C(cid, **kw) for cid, kw in take]
        x = mrl.shot(nm, parts, cls, 13000 + seed + 7 * i, body=body, presence=presence, length=length, peak=peak, tail=tail_, body_f=body_f, crest=crest)
        mrl.emit(nm, x, ogg=True)


def build_bodies():
    body_set("shot_v4_sg_auto", "shotgun", -11.5, 0.6, [[("fl_nova_near", dict(lp=7500, semis=2.0))], [("fl_mossberg_near", dict(lp=7500, semis=3.0))], [("fl_model12_near", dict(lp=7500, semis=1.0))]], body=0.4, presence=1.2, body_f=(230, 80), seed=1)
    body_set("shot_v4_sg_slug", "shotgun", -10.0, 1.0, [[("fl_model12_near", dict(lp=6500, semis=-3.0)), ("bang_cannon2", dict(db=-13.0, lp=1400, delay=0.002))], [("fl_nova_near", dict(lp=6500, semis=-4.0)), ("bang_cannon2", dict(db=-12.0, lp=1200, delay=0.002))],
                                                     [("fl_mossberg_near", dict(lp=6500, semis=-3.0)), ("bang_cannon4", dict(db=-14.0, lp=1000, delay=0.002))]], body=0.7, presence=1.1, tail_=(0.5, 0.15), body_f=(170, 55), seed=2)
    body_set("shot_v4_sg_sawn", "shotgun", -9.5, 1.1, [[("fl_mossberg_near", dict(lp=6000, semis=-6.0)), ("bang_cannon2", dict(db=-9.0, lp=1100, delay=0.001))], [("fl_nova_near", dict(lp=6000, semis=-7.0)), ("bang_cannon4", dict(db=-10.0, lp=1000, delay=0.001))],
                                                      [("fl_model12_near", dict(lp=5800, semis=-6.0)), ("bang_cannon2", dict(db=-9.0, lp=1000, delay=0.001))]], body=0.9, presence=0.9, tail_=(0.7, 0.18), body_f=(150, 45), seed=3)
    for i, mk in enumerate([lambda i=i: mix([C("sf50_rocket", semis=-2.0 * i, lp=8000), C("kn_lowexpl1", db=-8.0, lp=900, delay=0.01), C("sw_2", db=-12.0, delay=0.02, semis=-3.0, lp=4500)], 1.0) for i in range(3)]):
        nm = "shot_v4_rocket" if i == 0 else "shot_v4_rocket_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            mrl.emit(nm, mr.master(mk(), -10.5, 8.0, 70.0, 0.3, 1.0), ogg=True)
    for i in range(3):
        nm = "shot_v4_rocket_h" if i == 0 else "shot_v4_rocket_h_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("bang_cannon2", semis=-1.0 * i, lp=2500), C("sf50_rocket", db=-3.0, semis=-3.0, delay=0.02, lp=5000), C("kn_lowexpl0", db=-6.0, lp=700, delay=0.03)], 1.2)
            mrl.emit(nm, mr.master(x, -9.5, 8.0, 50.0, 0.4, 1.2), ogg=True)
    for i in range(3):
        nm = "shot_v4_gl" if i == 0 else "shot_v4_gl_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("bang_01", lp=1800, semis=-2.0 * i), C("mi_clink3", db=-10.0, delay=0.04, semis=-5.0, lp=3500), part(tone(520 - 40 * i, 0.12, decay=24.0, f1=190.0), -9.0, 0.0)], 0.6)
            mrl.emit(nm, mr.master(x, -11.0, 7.5, 70.0, 0.15, 0.6), ogg=True)
    for i in range(3):
        nm = "shot_v4_mortar" if i == 0 else "shot_v4_mortar_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("bang_cannon4", lp=1300, semis=-1.0 * i), part(tone(1500, 0.7, decay=3.0, f1=520.0, harm=(1.0, 0.2)), -17.0, 0.12)], 1.0)
            mrl.emit(nm, mr.master(x, -10.5, 8.0, 50.0, 0.3, 1.0), ogg=True)
    for i in range(3):
        nm = "shot_v4_throw" if i == 0 else "shot_v4_throw_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("sw_%d" % (3, 4, 5)[i], db=-4.0, lp=7000), C("mi_thud3", db=-9.0, delay=0.12, lp=900)], 0.4)
            mrl.emit(nm, mr.master(x, -14.0, 7.5, 80.0, 0.1, 0.4), ogg=True)
    for i in range(3):
        nm = "shot_v4_mine" if i == 0 else "shot_v4_mine_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("mi_thud2", db=-3.0, lp=1000, semis=-2.0 * i), C("equip_click_b", db=-8.0, delay=0.1, hp=1200), part(tone(1900 + 150 * i, 0.05, decay=60.0), -11.0, 0.22)], 0.4)
            mrl.emit(nm, mr.master(x, -14.5, 8.0, 80.0, 0.1, 0.4), ogg=True)
    for i in range(3):
        nm = "shot_v4_strike" if i == 0 else "shot_v4_strike_%d" % i
        if not mrl.ONLY or any(fnmatch.fnmatch(nm, p) for p in mrl.ONLY):
            x = mix([C("sf_term09", db=-4.0, semis=2.0 * i, lp=8000), part(tone(1320, 0.3, decay=10.0, harm=(1.0, 0.3)), -10.0, 0.1), part(tone(1760, 0.3, decay=10.0, harm=(1.0, 0.3)), -11.0, 0.22)], 0.6)
            mrl.emit(nm, mr.master(x, -13.0, 8.0, 150.0, 0.15, 0.6), ogg=True)


# ------------------------------------------------------------------------------------------------------------------------------------ reload and equip
def build_reload():
    P = -15.0
    master_set("wr_pistol", [lambda: mix([C("reload_pistol", lp=9000)], 1.4), lambda: mix([C("reload_clip2", lp=9000, semis=1.0)], 1.4)], P, 8.0, 150.0, 0.1, 1.4)
    master_set("wr_smg", [lambda: mix([C("reload_clip2", lp=9000, semis=2.0)], 1.5), lambda: mix([C("reload_ar", lp=9000, semis=3.0)], 1.5)], P, 8.0, 150.0, 0.1, 1.5)
    master_set("wr_rifle", [lambda: mix([C("reload_ar", lp=9000)], 1.8), lambda: mix([C("reload_starninjas", lp=9000)], 1.8)], P, 8.0, 120.0, 0.1, 1.8)
    master_set("wr_shotgun", [lambda i=i: mix([C("mi_clink1", db=-5.0, semis=-2.0, lp=5000), C("mi_clink2", db=-5.0, delay=0.28, semis=-3.0, lp=5000), C("mi_clink1", db=-5.0, delay=0.56, semis=-1.0, lp=5000), C("shotgun_cock", delay=0.9 + 0.05 * i)], 1.6) for i in range(2)], P, 8.0, 120.0, 0.1, 1.6)
    master_set("wr_sniper", [lambda i=i: mix([C("equip_click_b", db=-4.0, semis=-2.0), C("mi_clink3", delay=0.3, semis=-5.0 + i, lp=4000), C("qi_metal", db=-9.0, delay=0.62, semis=-6.0, lp=2800), C("mi_clink2", db=-4.0, delay=0.9, semis=-3.0)], 1.5) for i in range(2)], P, 8.0, 120.0, 0.1, 1.5)
    master_set("wr_lmg", [lambda i=i: mix([C("reload_ar", semis=-3.0 + i, lp=7000), C("mi_clink3", db=-6.0, delay=0.5, semis=-4.0), C("st_metal_05", db=-8.0, delay=0.85, hp=500, lp=5000)], 2.0) for i in range(2)], P, 8.0, 100.0, 0.12, 2.0)
    master_set("wr_launcher", [lambda i=i: mix([C("mi_thud2", db=-4.0, lp=900), C("st_metal_09", db=-7.0, delay=0.18, hp=400, lp=4000, semis=-2.0 + i), C("mi_clink3", db=-7.0, delay=0.6, semis=-5.0)], 1.5) for i in range(2)], P, 8.0, 100.0, 0.1, 1.5)
    master_set("wr_energy", [lambda i=i: mix([C("kn_forcefield2", lp=5000, length=0.45, semis=-2.0 + i), C("ki_click3", db=-4.0, delay=0.5), part(tone(300, 0.5, decay=2.5, f1=1500.0 + 100 * i, harm=(1.0, 0.3)), -16.0, 0.55)], 1.3) for i in range(2)], P, 8.0, 150.0, 0.1, 1.3)
    master_set("we_light", [lambda i=i: mix([C("equip_click_a", semis=i), C("sw_2", db=-10.0, lp=6000, semis=2.0)], 0.35) for i in range(2)], P - 1.0, 8.0, 200.0, 0.08, 0.35)
    master_set("we_heavy", [lambda i=i: mix([C("mi_thud2", db=-5.0, lp=1400), C("equip_click_b", delay=0.09, semis=-2.0 + i), C("sw_4", db=-12.0, lp=4500)], 0.4) for i in range(2)], P - 1.0, 8.0, 120.0, 0.08, 0.4)
    master_set("we_energy", [lambda i=i: mix([part(tone(260 + 30 * i, 0.3, decay=3.0, f1=900.0, harm=(1.0, 0.4)), -8.0, 0.0), C("ki_click3", db=-6.0, delay=0.02)], 0.4) for i in range(2)], P - 2.0, 8.0, 150.0, 0.1, 0.4)
    master_set("we_melee", [lambda i=i: mix([C("sw_%d" % (4, 7)[i], db=-4.0, lp=7000), C("mi_clink1", db=-9.0, delay=0.12, semis=-2.0)], 0.35) for i in range(2)], P - 1.0, 8.0, 150.0, 0.08, 0.35)


# ------------------------------------------------------------------------------------------------------------------------------------ explosions by size
def build_blasts():
    sizes = {
        "bm_small": (-8.5, 1.3, lambda i: mix([C("bang_01", semis=-1.0 * i, lp=6000), C("kn_expl_crunch0", db=-6.0, delay=0.005, lp=5000, semis=-2.0 * i), part(mrl.sub_body(n_(0.9), "revolver", 800 + i, 1.0, 140, 50), -4.0, 0.0)], 1.3)),
        "bm_medium": (-7.0, 1.4, lambda i: mix([C("expl_chunky", semis=-1.0 * i, lp=7000), C("kn_lowexpl0", db=-6.0, delay=0.01, lp=1200), part(mrl.sub_body(n_(1.05), "minigun", 810 + i, 1.0, 110, 38), -3.0, 0.0)], 1.4)),
        "bm_large": (-6.0, 3.0, lambda i: mix([C("expl_n99", semis=-2.0 * i, lp=6500), C("bang_cannon2", db=-6.0, delay=0.01, lp=1400, semis=-3.0), C("kn_expl_crunch3", db=-9.0, delay=0.15, lp=3000), part(mrl.sub_body(n_(2.2), "minigun", 820 + i, 1.0, 90, 30), -2.0, 0.0)], 3.0)),
        "bm_huge": (-5.5, 4.2, lambda i: mix([C("expl_muffled", semis=-1.0 * i, lp=3500), C("expl_far", db=-4.0, delay=0.08, lp=2500), C("bang_cannon4", db=-4.0, semis=-8.0, lp=1200), part(mrl.sub_body(n_(3.4), "minigun", 830 + i, 1.0, 70, 24), -1.0, 0.0)], 4.2)),
    }
    for name, (peak, ln, mk) in sizes.items():
        master_set(name, [lambda i=i, mk=mk: mk(i) for i in range(3)], peak, 6.5, 30.0, ln * 0.4, ln)


# ------------------------------------------------------------------------------------------------------------------------------------ impacts
def build_impacts():
    P = -13.0
    master_set("impact_wood", [lambda i=i: mix([C(("st_c2_wood1", "st_c2_wood3", "st_c2_wood4")[i], semis=-1.0, lp=6500), C("mi_thud3", db=-7.0, lp=900)], 0.4) for i in range(3)], P, 8.0, 120.0, 0.1, 0.4)
    master_set("impact_dirt", [lambda i=i: mix([C(("c2_stones1", "c2_stones2", "c2_stones3")[i], semis=-4.0, lp=2200), C("mi_thud2", db=-5.0, lp=700)], 0.4) for i in range(3)], P - 1.0, 8.0, 80.0, 0.1, 0.4)
    master_set("impact_foliage", [lambda i=i: sm([noise_burst(900 + i, 0.3, 1200, 7000, 9.0, 0.02), noise_burst(910 + i, 0.2, 300, 1200, 14.0, 0.01) * 0.4], 0.32) for i in range(3)], P - 3.0, 8.0, 200.0, 0.1, 0.32)
    master_set("impact_water", [lambda i=i: sm([noise_burst(920 + i, 0.35, 400, 5000, 10.0, 0.006), tone(900 + 200 * i, 0.12, decay=30.0, f1=300.0) * 0.5], 0.36) for i in range(3)], P - 2.0, 8.0, 150.0, 0.1, 0.35)
    master_set("impact_armor", [lambda i=i: mix([C("qi_metal", semis=-3.0 + i, lp=5000), C("mi_bing", db=-12.0, delay=0.01, semis=-6.0, lp=3500), C("mi_thud3", db=-6.0, lp=800)], 0.45) for i in range(3)], P, 8.0, 100.0, 0.1, 0.45)
    master_set("impact_shield", [lambda i=i: mix([C("kn_forcefield0", lp=6000, length=0.4, semis=2.0 * i), part(tone(1400, 0.3, decay=12.0, f1=900.0, harm=(1.0, 0.3)), -12.0, 0.0)], 0.5) for i in range(3)], P - 1.0, 8.0, 150.0, 0.1, 0.5)
    master_set("ricochet_metal", [lambda i=i: sm([mrl.glide(C("mi_bing", semis=4.0 * i, hp=1200)[0], 1.5, 0.6) * 0.8, noise_burst(930 + i, 0.15, 3000, 9000, 18.0) * 0.1], 0.9) for i in range(3)], P - 3.0, 8.0, 300.0, 0.1, 0.9)
    master_set("ricochet_stone", [lambda i=i: mrl.glide(C(("c2_stones1", "c2_stones2", "c2_stones3")[i], hp=1200, lp=7000)[0], 1.3, 0.7) for i in range(3)], P - 3.0, 8.0, 300.0, 0.1, 0.7)


# ------------------------------------------------------------------------------------------------------------------------------------ markers
def build_markers():
    P = -13.0

    def click_tone(f, dur, decay, harm=(1.0, 0.3)):
        return tone(f, dur, decay=decay, harm=harm, attack=0.0008)

    master_set("hit_marker", [lambda i=i: sm([click_tone(2600 + 150 * i, 0.07, 55.0), noise_burst(940 + i, 0.03, 3000, 9000, 90.0) * 0.3], 0.1) for i in range(2)], P, 8.0, 600.0, 0.02, 0.1)
    master_set("hit_head", [lambda i=i: mix([part(click_tone(3300 + 100 * i, 0.08, 45.0), 0.0, 0.0), part(click_tone(4200 + 100 * i, 0.08, 45.0), -2.0, 0.045)], 0.16) for i in range(2)], P + 1.0, 8.0, 800.0, 0.03, 0.18)
    master_set("hit_armor", [lambda i=i: mix([C("mi_bing", semis=-2.0 + i, hp=1500, lp=7000, length=0.12), part(click_tone(1500, 0.05, 60.0), -6.0, 0.0)], 0.2) for i in range(2)], P, 8.0, 800.0, 0.04, 0.2)
    master_set("hit_shield", [lambda i=i: tone(900 + 80 * i, 0.16, decay=18.0, f1=1700.0, harm=(1.0, 0.5)) for i in range(2)], P, 8.0, 500.0, 0.05, 0.18)
    master_set("hit_crit", [lambda i=i: mix([part(click_tone(2000, 0.08, 40.0), 0.0, 0.0), part(click_tone(3000, 0.1, 35.0), -1.0, 0.03), part(click_tone(4000, 0.12, 30.0), -2.0, 0.06)], 0.22) for i in range(2)], P + 1.0, 8.0, 700.0, 0.04, 0.22)
    master_set("hit_kill_head", [lambda i=i: mix([part(tone(180, 0.12, decay=30.0, f1=70.0), 0.0, 0.0), part(click_tone(3500 + 150 * i, 0.12, 30.0, (1.0, 0.5)), -3.0, 0.02), C("ki_glass1", db=-9.0, delay=0.03, hp=1500, length=0.2)], 0.3) for i in range(2)], P + 1.0, 8.0, 60.0, 0.05, 0.3)
    master_set("hit_kill_blast", [lambda i=i: mix([part(tone(120, 0.25, decay=14.0, f1=48.0, harm=(1.0, 0.4)), 0.0, 0.0), part(noise_burst(950 + i, 0.2, 200, 2500, 16.0), -9.0, 0.0), part(click_tone(1800, 0.1, 35.0), -7.0, 0.04)], 0.35) for i in range(2)], P + 1.0, 8.0, 40.0, 0.08, 0.35)
    master_set("hit_kill_streak", [lambda i=i: mix([part(click_tone(f * (1 + 0.04 * i), 0.14, 20.0, (1.0, 0.4)), -k, k * 0.09) for k, f in enumerate((1200, 1600, 2000, 2600))], 0.5) for i in range(2)], P, 8.0, 500.0, 0.08, 0.5)


BUILDERS = {"mech": build_mech, "tails": build_tails, "bodies": build_bodies, "reload": build_reload, "blasts": build_blasts, "impacts": build_impacts, "markers": build_markers}


def main():
    args = [a for a in sys.argv[1:]]
    only = []
    if "--only" in args:
        i = args.index("--only")
        only = args[i + 1:]
        args = args[:i]
    mrl.ONLY[:] = only
    if args:
        mrl.OUT = args[0]
    os.makedirs(mrl.OUT, exist_ok=True)
    for name, fn in BUILDERS.items():
        fn()
    if not mrl.ONLY:                                            # the level table tests/test_weapon_audio_v3.gd checks (a full build only): peak and short-term loudness of every file of this wave
        import json
        import audio_metrics as am
        lv = {n: {"peak": round(float(am.peak_db(x)), 1), "lu": round(float(am.short_term(x, 250.0)), 1), "len": round(len(x) / SR, 2)} for n, x in sorted(mrl.BUILT.items())}
        with open(os.path.join(HERE, "weapons_v4_levels.json"), "w") as f:
            json.dump(lv, f, indent=0)
    print("weapon sounds v4 written to", mrl.OUT)


if __name__ == "__main__":
    main()
