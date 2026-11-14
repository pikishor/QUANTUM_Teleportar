#!/usr/bin/env python3
"""Sound sets of the roster of wave 113 (scripts/player/weapon_defs_v3.gd): one class sound set per family of weapons, every set with FOUR takes (the base file and _1, _2, _3, which Sfx.variants_of
picks from, never twice in a row) built from the CC0 clips of the library (art_sources/audio_*/clips, docs/AUDIO_SOURCES.md) with our own sub-bass thump under the real transient, plus two shared layer
sounds (wlayer_ring, wlayer_thump) that a def can play under its shot (def key `layer`, WeaponMech.on_shoot). Every weapon of the pack names one of these sets in its def `snd`; weapons of one set
differ by pitch, volume and layer (def pitch_lo / pitch_hi / vol / layer), so no weapon is silent and none sounds like its neighbour.
Sets: shot_v3_  pistol smg ar battle carbine dmr sniper shotgun lmg rotary bow flame blade blunt chain energy beam quantum exotic.
Run: python3 tools/audio/make_weapons_v3.py [out_dir]          (numpy and ffmpeg; the OGG files go to assets/audio, then tools/import.sh)
"""
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


def shot_set(name, cls, peak, length, takes, body=0.5, presence=0.8, tail=None, body_f=None, seed=0, crest=7.0):
    """takes: a list of part lists [(clip id, C keyword dict), ...]; one file per take."""
    for i, take in enumerate(takes):
        nm = name if i == 0 else "%s_%d" % (name, i)
        parts = [C(cid, **kw) for cid, kw in take]
        x = mrl.shot(nm, parts, cls, 12000 + seed + 7 * i, body=body, presence=presence, length=length, peak=peak, tail=tail, body_f=body_f, crest=crest)
        mrl.emit(nm, x, ogg=True)


def master_set(name, makers, peak, crest=7.0, hp=80.0, fade=0.05, max_len=0.8):
    for i, mk in enumerate(makers):
        nm = name if i == 0 else "%s_%d" % (name, i)
        x = mk()
        mrl.emit(nm, mr.master(x, peak, crest, hp, fade, max_len), ogg=True)


def build():
    # ------------------------------------------------------------------ firearms: the real recordings, our sub-bass under them
    shot_set("shot_v3_pistol", "pistol", -12.5, 0.55, [[("fl_1911_near", dict(lp=7500))], [("fl_ppq_near", dict(lp=7500, semis=1.0))], [("fl_bersa_near", dict(lp=7500, semis=-1.0))], [("fl_cg_single", dict(lp=7500, semis=2.0))]],
             body=0.55, presence=0.9, body_f=(330, 95), seed=1)
    shot_set("shot_v3_smg", "burst", -13.0, 0.3, [[("fl_ppsh_r0", dict(lp=7500, semis=2.0))], [("fl_ppsh_r1", dict(lp=7500, semis=3.0))], [("fl_cg_r2", dict(lp=7500, semis=1.0))], [("fl_cg_r3", dict(lp=7500, semis=2.5))]],
             body=0.5, presence=0.7, seed=2)
    shot_set("shot_v3_ar", "rifle", -12.0, 0.8, [[("fl_ar15_near", dict(lp=7500))], [("fl_ak_near", dict(lp=7500))], [("fl_ak_near2", dict(lp=7500, semis=-1.0))], [("fl_sks_near", dict(lp=7500, semis=1.0))]],
             body=0.35, presence=1.0, body_f=(260, 70), seed=3)
    shot_set("shot_v3_battle", "rifle", -11.5, 0.9, [[("fl_sks_near", dict(lp=7000, semis=-3.0))], [("fl_savage_near", dict(lp=7000, semis=-2.0))], [("fl_mosin_near", dict(lp=7000, semis=-1.0))], [("fl_ak_near", dict(lp=7000, semis=-4.0))]],
             body=0.45, presence=1.0, tail=(0.4, 0.15), body_f=(220, 65), seed=4)
    shot_set("shot_v3_carbine", "burst", -12.5, 0.45, [[("fl_cg_single", dict(lp=7500, semis=1.0))], [("fl_ar15_near", dict(lp=7500, semis=3.0))], [("fl_ak_near", dict(lp=7500, semis=2.0))], [("fl_bersa_near", dict(lp=7500, semis=3.0))]],
             body=0.4, presence=0.9, seed=5)
    shot_set("shot_v3_dmr", "rifle", -11.0, 1.0, [[("fl_marlin_near", dict(lp=7000, semis=-1.0))], [("fl_savage_near", dict(lp=7000))], [("fl_sks_near", dict(lp=7000, semis=-2.0))], [("fl_mosin_near", dict(lp=7000, semis=1.0))]],
             body=0.5, presence=1.2, tail=(0.6, 0.2), body_f=(200, 60), seed=6)
    shot_set("shot_v3_sniper", "rifle", -10.5, 1.3, [[("lark_blackpowder", dict(lp=6000)), ("fl_mosin_near", dict(db=-3.0, lp=5000, semis=-4.0))], [("fl_1917_near", dict(lp=6000, semis=-3.0)), ("lark_blackpowder", dict(db=-4.0, lp=3500))],
                                                    [("fl_mosin_near", dict(lp=6000, semis=-5.0)), ("bang_cannon2", dict(db=-14.0, lp=1500, delay=0.003))], [("lark_blackpowder", dict(lp=5500, semis=-3.0)), ("fl_savage_near", dict(db=-4.0, lp=4500, semis=-5.0))]],
             body=0.8, presence=1.3, tail=(1.0, 0.3), body_f=(170, 50), seed=7)
    shot_set("shot_v3_shotgun", "shotgun", -10.5, 1.0, [[("fl_mossberg_near", dict(lp=7500))], [("fl_nova_near", dict(lp=7500))], [("fl_model12_near", dict(lp=7500))], [("fl_mossberg_near", dict(lp=7000, semis=-3.0)), ("bang_cannon2", dict(db=-14.0, lp=1200, delay=0.002))]],
             body=0.45, presence=1.3, body_f=(210, 70), seed=8)
    shot_set("shot_v3_lmg", "minigun", -13.0, 0.25, [[("fl_ak_burst_mid", dict(lp=7000, semis=-1.0, length=0.25))], [("fl_ak_burst_mid2", dict(lp=7000, length=0.25))], [("fl_ppsh_burst_mid", dict(lp=7000, semis=-2.0, length=0.25))], [("fl_ak_burst_mid", dict(lp=6500, semis=-3.0, length=0.25))]],
             body=0.6, presence=0.4, seed=9)
    shot_set("shot_v3_rotary", "minigun", -14.0, 0.18, [[("fl_ppsh_r0", dict(lp=6500, semis=-5.0))], [("fl_ppsh_r1", dict(lp=6500, semis=-4.0))], [("fl_ppsh_r2", dict(lp=6500, semis=-6.0))], [("fl_ppsh_r3", dict(lp=6500, semis=-3.5))]],
             body=0.8, presence=0.2, body_f=(190, 55), seed=10)
    # ------------------------------------------------------------------ the suppressed weapons: the Hollywood silencer clip, a pistol crack deep under it on two takes
    def supp(i):
        parts = [C("silencer", semis=[0.0, -1.5, 1.0, -3.0][i], lp=1900)] + ([C(["fl_ppq_near", "fl_bersa_near"][i // 2], db=-14.0, lp=1200, delay=0.001)] if i % 2 == 1 else [])
        x = ma.reverb(mix(parts, 0.8), 0.25, wet=0.1, predelay=0.006, damp=0.7, seed=12400 + i)
        return x
    master_set("shot_v3_supp", [lambda i=i: supp(i) for i in range(4)], -14.5, crest=7.0, hp=80.0, fade=0.04, max_len=0.55)
    # ------------------------------------------------------------------ bow: a string and a swish
    master_set("shot_v3_bow", [lambda i=i: mix([part(mrl.twang(12100 + i, 520.0 + 60.0 * i, 160.0, 0.45, 12.0 + i), 0.0), C("sw_%d" % [2, 3, 5, 7][i], db=-7.0, lp=6000, delay=0.0)], 0.5) for i in range(4)], -16.0, crest=8.0)
    # ------------------------------------------------------------------ sprayers
    master_set("shot_v3_flame", [lambda i=i: mix([part(mrl.whoosh(12200 + i, 0.3, 200.0, 3600.0 - 300.0 * i, 0.02, 7.0 + i), 0.0), C("kn_lowexpl%d" % (i % 2), db=-12.0, lp=700, semis=-2.0), C("sw_%d" % [1, 2, 4, 5][i], db=-12.0, lp=5000)], 0.4) for i in range(4)], -14.0, crest=7.0, hp=120.0)
    # ------------------------------------------------------------------ melee: blades ring, blunt weapons thud, the chain buzzes
    master_set("shot_v3_blade", [lambda i=i: mix([C("sw_%d" % [2, 3, 4, 5][i], semis=-1.0 + i, lp=9000), C("kn_impact_metal4", db=-8.0, delay=0.07 + 0.02 * i, semis=4.0 + i, hp=800)], 0.6) for i in range(4)], -15.0, crest=8.0, max_len=0.6)
    master_set("shot_v3_blunt", [lambda i=i: mix([C("sw_%d" % [4, 1, 5, 7][i], semis=-5.0 - i, lp=4500), C(["qp_punch1", "qp_punch3", "qp_punch4", "qp_punch5"][i], db=-3.0, delay=0.08, semis=-6.0, lp=1600), C("mi_thud%d" % (2 + i % 2), db=-6.0, delay=0.09, lp=900)], 0.6) for i in range(4)], -13.5, crest=7.0, hp=60.0, max_len=0.6)
    master_set("shot_v3_chain", [lambda i=i: mix([C("veh_loop%d" % [0, 1, 3, 5][i], semis=7.0 + i, lp=3500, hp=200, length=0.4), C("sw_%d" % [3, 4, 5, 7][i], db=-5.0, lp=7000), C("st_metal_%02d" % [1, 3, 5, 7][i], db=-10.0, delay=0.02, hp=900)], 0.45) for i in range(4)], -14.5, crest=7.0, max_len=0.45)
    # ------------------------------------------------------------------ energy, beams, quantum, exotic: the Kenney / number99 lasers, force fields
    shot_set("shot_v3_energy", "flux", -12.5, 0.45, [[("kn_laser_s0", dict(lp=9000)), ("sf50_shoot1", dict(db=-8.0, lp=8000))], [("kn_laser_s1", dict(lp=9000, semis=1.0)), ("sf50_shoot2", dict(db=-8.0, lp=8000))],
                                                     [("kn_laser_s2", dict(lp=9000, semis=-1.0)), ("sf50_retro_laser1", dict(db=-9.0, lp=8000, semis=2.0))], [("kn_laser_s3", dict(lp=9000, semis=2.0)), ("sf50_shoot1", dict(db=-8.0, semis=-3.0, lp=8000))]],
             body=0.45, seed=11)
    shot_set("shot_v3_beam", "flux", -11.5, 0.9, [[("kn_laser_l0", dict(lp=8500, semis=-2.0)), ("kn_forcefield0", dict(db=-4.0, lp=5000, gl=(1.3, 0.8)))], [("kn_laser_l2", dict(lp=8500, semis=-3.0)), ("kn_forcefield2", dict(db=-4.0, lp=5000, gl=(1.2, 0.7)))],
                                                  [("kn_laser_l3", dict(lp=8500, semis=-4.0)), ("sf50_expl1", dict(db=-10.0, lp=2500, semis=-6.0))], [("kn_laser_l0", dict(lp=8000, semis=-5.0)), ("kn_forcefield0", dict(db=-5.0, lp=4500, semis=-4.0))]],
             body=0.8, tail=(0.8, 0.25), body_f=(150, 45), seed=12)
    shot_set("shot_v3_quantum", "flux", -12.5, 0.6, [[("sf60_21a", dict(lp=9000)), ("kn_forcefield2", dict(db=-6.0, lp=6000, gl=(0.9, 1.4)))], [("sf50_retro_laser1", dict(lp=9000, semis=-2.0)), ("kn_laser_r4", dict(db=-5.0, lp=8000, semis=3.0))],
                                                    [("kn_forcefield0", dict(lp=7000, gl=(1.5, 0.9))), ("kn_laser_r0", dict(db=-5.0, lp=8000, semis=5.0))], [("sf60_21a", dict(lp=8000, semis=-4.0)), ("kn_laser_s3", dict(db=-6.0, lp=9000, semis=7.0))]],
             body=0.4, tail=(0.6, 0.25), seed=13)
    shot_set("shot_v3_exotic", "revolver", -11.5, 0.9, [[("kn_forcefield0", dict(lp=5000, semis=-4.0)), ("kn_lowexpl1", dict(db=-4.0, lp=900))], [("kn_forcefield2", dict(lp=5000, semis=-5.0)), ("kn_lowexpl0", dict(db=-4.0, lp=900))],
                                                       [("kn_forcefield0", dict(lp=4500, semis=-7.0, gl=(1.4, 0.7))), ("sf50_expl1", dict(db=-8.0, lp=2000))], [("kn_forcefield2", dict(lp=4500, semis=-2.0, gl=(0.8, 1.3))), ("kn_expl_crunch0", dict(db=-9.0, lp=1800))]],
             body=1.0, tail=(0.7, 0.25), body_f=(150, 45), seed=14)
    # ------------------------------------------------------------------ the two shared layers
    master_set("wlayer_ring", [lambda i=i: mix([C("mi_clink%d" % (1 + i), semis=7.0 + 2.0 * i, hp=1800, lp=9000)], 0.7) for i in range(2)], -22.0, crest=9.0, hp=1500.0, max_len=0.7)
    master_set("wlayer_thump", [lambda i=i: mix([C(["bang_cannon2", "bang_cannon4"][i], semis=-5.0, lp=500, hp=40), part(mrl.sub_body(int(0.4 * SR), "revolver", 12300 + i, 1.0), -4.0)], 0.45) for i in range(2)], -17.0, crest=7.0, hp=35.0, max_len=0.45)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if args:
        mrl.OUT = args[0]
    os.makedirs(mrl.OUT, exist_ok=True)
    build()
    print("weapon sounds v3 written to", mrl.OUT)


if __name__ == "__main__":
    main()
