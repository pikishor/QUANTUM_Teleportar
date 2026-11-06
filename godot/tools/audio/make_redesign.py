#!/usr/bin/env python3
"""Audio redesign, part 1: weapons, impacts and explosions of Quantum Teleportar (numpy only, 16-bit mono WAV; run AFTER make_combat.py, it replaces those files).

Every shot is built from the same five layers, with the balance set per weapon class (CLASSES below):
  click   1-3 ms of noise above 3 kHz plus a damped 2-5 kHz tick (the transient a phone speaker still reproduces)
  crack   mid noise burst, 0.8-6 kHz (the "hit you in the face" part)
  body    a pitched-down sine thump (f0 -> f1) driven into saturation so that its 2nd/3rd harmonics (150-500 Hz) carry the weight on a small speaker
  blast   low-mid noise, 150-1500 Hz, the muzzle gas
  tail    the same bus through a short room reverb and a slap-back, per class
Variants: close (the default files), far (shot_far_*: a lowpassed, late, reverberant copy for shots beyond 45 m), suppressed (shot_supp_*: no crack, a mechanical thump and a soft
puff) and overcharged (shot_oc_*: a long sub fall, a plasma zap sweep and a shimmering tail). Each variant draws its own random taus, pitches and gains, so no two files are alike,
and the game adds pitch jitter on top.
Mastering: soft squash and a look-ahead limiter to a per-class peak (-10 to -14 dBFS; the audio tests keep one-shots below -9 and a 20-shot firefight, summed from six overlapping
voices, below -1 dBFS) with a crest factor of about 6.5 dB: loud, not just tall.
Also here: impacts (flesh with an alien squelch, concrete, metal, asphalt-less), and explosions with a sub-bass (boom, boom_1..3, explosion_small_0/1; shrink_audio.py turns them into OGG).
Run: python3 tools/audio/make_redesign.py [out_dir] [--only glob ...]   (tools/build_assets.sh calls it after make_combat.py)
"""
import fnmatch
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, band, expenv, saturate, sine_sweep, white, echo, reverb, fade, fft_filter  # noqa: E402
import audio_metrics as am  # noqa: E402



def _n(sec):
    return int(sec * SR)


def R(seed):
    return np.random.default_rng(seed)


def lp(x, fc, order=2):
    return fft_filter(x, None, fc, order)


def hp(x, fc, order=2):
    return fft_filter(x, fc, None, order)


def put(buf, sig, t0=0.0, gain=1.0):
    i = int(t0 * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[:j - i] * gain


def master(x, peak_db, crest=6.5, hp_hz=60.0, fade_out=0.06, max_len=None, trim_db=-55.0, squash=2.0):
    """Trim the tail, high-pass, soft-squash the transient, then find the gain whose limited result has a short-term loudness of peak_db - crest (first 250 ms, K-weighted)
    with the peak at peak_db. A 20-shot firefight is summed from up to six overlapping voices and the audio tests keep that sum below -1 dBFS, so the peak of the fast weapons is
    low (-12 dBFS) and their loudness comes from the low crest factor, not from height."""
    if max_len:
        x = x[:_n(max_len)]
    thr = 10 ** (trim_db / 20.0) * np.max(np.abs(x))
    idx = np.nonzero(np.abs(x) > thr)[0]
    if len(idx):
        x = x[:min(len(x), idx[-1] + _n(0.04))]
    x = fade(x, 0.0004, fade_out)
    x = hp(x, hp_hz, 2) if hp_hz else x
    x = np.tanh(x / (np.max(np.abs(x)) + 1e-12) * squash)
    target_lu = peak_db - crest
    g = 1.0
    y = x
    for _ in range(8):
        y = am.limiter(x * g, peak_db, 0.003)
        lu = am.short_term(y, 250.0)
        if abs(lu - target_lu) < 0.3:
            break
        g *= 10 ** ((target_lu - lu) / 20.0 * 0.9)
    y = am.limiter(y, peak_db, 0.002)
    return y / (np.max(np.abs(y)) + 1e-12) * 10 ** (peak_db / 20.0)


# ------------------------------------------------------------------ the shot kit
def click(n, r, hi=3500.0, gain=1.0, tick_hz=3200.0):
    c = band(white(n, int(r.integers(1, 10 ** 6))), hi, 15000) * expenv(n, 0.0007) * 2.2
    t = np.arange(n) / SR
    c += np.sin(2 * np.pi * tick_hz * r.uniform(0.9, 1.15) * t) * expenv(n, 0.0016) * 0.6
    return c * gain


def crack(n, r, lo, hi, tau, gain=1.0):
    return band(white(n, int(r.integers(1, 10 ** 6))), lo, hi) * expenv(n, tau * r.uniform(0.85, 1.2)) * gain


def body(n, r, f0, f1, dur, tau, drive=2.4, gain=1.0):
    sw, _ = sine_sweep(dur, f0 * r.uniform(0.94, 1.07), f1 * r.uniform(0.94, 1.07))
    b = np.zeros(n)
    k = min(len(sw), n)
    b[:k] = sw[:k] * expenv(k, tau * r.uniform(0.85, 1.2))
    return saturate(b * drive, 1.0) * gain / max(np.tanh(drive), 1e-6) * 1.0


CLASSES = {
    # name: dict(len, peak dBFS, click hi, crack(lo,hi,tau,g), body(f0,f1,dur,tau,drive,g), blast(lo,hi,tau,g), tail(rt60,wet,slap delay, slap gain), click gain)
    "rifle": dict(length=0.9, pk=-12.0, ck=(3500, 1.0), cr=(700, 5500, 0.010, 2.0), bd=(260, 70, 0.12, 0.05, 2.6, 1.5), bl=(180, 1400, 0.045, 1.5), tl=(0.55, 0.28, 0.115, 0.22)),
    "pistol": dict(length=0.7, pk=-11.5, ck=(4000, 1.1), cr=(900, 6500, 0.007, 2.2), bd=(330, 95, 0.09, 0.035, 2.4, 1.2), bl=(250, 1800, 0.03, 1.2), tl=(0.45, 0.25, 0.09, 0.2)),
    "revolver": dict(length=1.1, pk=-10.5, ck=(3000, 1.0), cr=(500, 4500, 0.016, 2.1), bd=(190, 48, 0.2, 0.09, 2.9, 2.0), bl=(120, 1200, 0.07, 1.8), tl=(0.85, 0.35, 0.16, 0.28)),
    "shotgun": dict(length=1.0, pk=-10.5, ck=(2500, 1.0), cr=(400, 4000, 0.022, 2.3), bd=(150, 38, 0.24, 0.11, 3.0, 2.3), bl=(100, 1500, 0.1, 2.2), tl=(0.8, 0.35, 0.14, 0.3)),
    "minigun": dict(length=0.2, pk=-13.5, ck=(3800, 0.9), cr=(1200, 6000, 0.006, 1.6), bd=(280, 110, 0.06, 0.025, 2.2, 1.0), bl=(300, 2200, 0.02, 0.9), tl=(0.15, 0.04, 0.0, 0.0)),
    "burst": dict(length=0.4, pk=-12.5, ck=(4200, 1.0), cr=(1000, 7000, 0.007, 1.9), bd=(300, 90, 0.08, 0.03, 2.3, 1.1), bl=(250, 2000, 0.03, 1.1), tl=(0.3, 0.12, 0.07, 0.15)),
    "flux": dict(length=0.5, pk=-12.0, ck=(4500, 0.9), cr=(1500, 9000, 0.008, 1.5), bd=(420, 120, 0.14, 0.06, 2.0, 1.1), bl=(200, 1800, 0.03, 0.8), tl=(0.4, 0.22, 0.06, 0.18), zap=(3800, 380, 0.16, 1.4)),
    "enemy": dict(length=0.7, pk=-14.5, ck=(3000, 0.7), cr=(500, 4000, 0.012, 1.8), bd=(240, 80, 0.1, 0.04, 2.3, 1.3), bl=(150, 1200, 0.04, 1.2), tl=(0.5, 0.25, 0.1, 0.2), zap=(2600, 300, 0.2, 1.1)),
}


def synth_shot(cls, seed, variant="close"):
    c = CLASSES[cls]
    r = R(seed)
    n = _n(c["length"] + 0.9)
    ck_hi, ck_g = c["ck"]
    cr_lo, cr_hi, cr_tau, cr_g = c["cr"]
    f0, f1, bdur, btau, drv, bg = c["bd"]
    bl_lo, bl_hi, bl_tau, bl_g = c["bl"]
    rt, wetm, slap_d, slap_g = c["tl"]
    if variant == "supp":
        x = np.zeros(n)
        x += body(n, r, 180, 85, 0.05, 0.02, 2.0, 1.1)                                             # a mechanical thump, no supersonic crack
        x += band(white(n, seed + 1), 600, 4200) * expenv(n, 0.02) * 0.9                             # a soft puff
        x += click(n, r, 3000, 0.35, 2400)
        x += band(white(n, seed + 2), 150, 700) * expenv(n, 0.03) * 0.5
        x = reverb(lp(x, 5200), 0.25, wet=0.12, predelay=0.006, damp=0.7, seed=seed)
        return master(x, c["pk"] - 2.0, 7.0, 80.0, 0.04, 0.55)
    x = np.zeros(n)
    x += click(n, r, ck_hi, ck_g, 3200)
    x += crack(n, r, cr_lo, cr_hi, cr_tau, cr_g)
    x += body(n, r, f0, f1, bdur, btau, drv, bg)
    x += band(white(n, seed + 5), bl_lo, bl_hi) * expenv(n, bl_tau * r.uniform(0.85, 1.2)) * bl_g
    if "zap" in c:
        zf0, zf1, zd, zg = c["zap"]
        z, _ = sine_sweep(zd, zf0 * r.uniform(0.9, 1.1), zf1)
        zz = np.zeros(n)
        zz[:len(z)] = z * expenv(len(z), zd * 0.35)
        x += zz * zg
    x = saturate(x * 0.55, 1.6)
    if variant == "oc":
        sub, _ = sine_sweep(0.5, 120, 32)
        s = np.zeros(n)
        s[:len(sub)] = saturate(sub * 1.8, 1.0) * expenv(len(sub), 0.2)
        zap, _ = sine_sweep(0.35, 5200, 260)
        z = np.zeros(n)
        z[:len(zap)] = zap * expenv(len(zap), 0.1)
        x = x * 0.9 + s * 1.4 + z * 1.2
        shimmer = np.sin(2 * np.pi * 1760 * np.arange(n) / SR + 3.0 * np.sin(2 * np.pi * 7 * np.arange(n) / SR)) * expenv(n, 0.35) * 0.25
        x = reverb(x + shimmer, 1.3, wet=0.45, predelay=0.012, damp=0.4, seed=seed)
        return master(x, -10.0, 6.5, 40.0, 0.2, 1.4)
    if slap_g > 0:
        x = echo(x, slap_d, slap_g, lp=2200, taps=1)
    if rt > 0.2:
        x = reverb(x, rt, wet=wetm, predelay=0.008, damp=0.55, seed=seed)
    if variant == "far":
        x = lp(x, 2300, 2)
        d = np.zeros(n + _n(0.18))
        put(d, x, 0.14, 1.0)                                                                       # sound travels: late, dull, wide
        x = reverb(d, 1.5, wet=0.55, predelay=0.02, damp=0.7, seed=seed + 11)
        x = band(x, 80, 3000)
        return master(x, c["pk"] - 1.5, 10.0, 70.0, 0.25, 1.9)
    return master(x, c["pk"], 6.5, 55.0, c["length"] * 0.14 + 0.03, c["length"] + 0.25)


# ------------------------------------------------------------------ impacts
def flesh(seed, alien=False):
    r = R(seed)
    n = _n(0.45)
    x = body(n, r, 190, 62, 0.07, 0.03, 2.6, 1.4)                                                   # the thud
    x += crack(n, r, 300, 2800, 0.014, 1.9)                                                          # the wet slap
    t = np.arange(n) / SR
    sq = band(white(n, seed + 3), 400, 2200) * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(22, 34) * t)) * expenv(n, 0.07) * 1.1  # the squelch
    x += sq
    ch, _ = sine_sweep(0.05, r.uniform(280, 380), r.uniform(820, 1100))                              # a fluid bubble chirp, the alien part
    cz = np.zeros(n)
    cz[:len(ch)] = ch * expenv(len(ch), 0.02) * 0.7
    x += cz * (1.2 if alien else 0.6)
    x += click(n, r, 2500, 0.4, 1800)
    x = reverb(saturate(x * 0.6, 1.5), 0.2, wet=0.1, predelay=0.004, damp=0.7, seed=seed)
    return master(x, -14.0, 6.5, 70.0, 0.1, 0.4)


def concrete(seed):
    r = R(seed)
    n = _n(0.55)
    x = crack(n, r, 800, 7500, 0.007, 2.4) + body(n, r, 260, 90, 0.05, 0.02, 2.2, 1.1) + click(n, r, 3500, 0.8)
    t = np.arange(n) / SR
    x += band(white(n, seed + 4), 2000, 9000) * expenv(n, 0.09) * (np.sin(2 * np.pi * 90 * t) > 0.2) * 0.6    # grit raining down
    x = reverb(x, 0.35, wet=0.16, predelay=0.005, damp=0.6, seed=seed)
    return master(x, -14.0, 6.5, 90.0, 0.12, 0.55)


def metal(seed):
    r = R(seed)
    n = _n(0.8)
    t = np.arange(n) / SR
    x = click(n, r, 3000, 1.2, 4200) + crack(n, r, 1500, 9000, 0.004, 1.4)
    for f, dcy, a in ((r.uniform(620, 780), 0.13, 0.9), (r.uniform(1450, 1800), 0.09, 0.7), (r.uniform(2900, 3600), 0.06, 0.5), (r.uniform(4600, 5600), 0.04, 0.3)):
        x += np.sin(2 * np.pi * f * t) * np.exp(-t / dcy) * a                                          # the plate rings
    x += body(n, r, 300, 110, 0.04, 0.02, 2.0, 0.8)
    x = reverb(x, 0.5, wet=0.2, predelay=0.006, damp=0.4, seed=seed)
    return master(x, -14.0, 8.0, 110.0, 0.2, 0.8)


# ------------------------------------------------------------------ explosions
def explosion(seed, big=True):
    r = R(seed)
    d = 3.2 if big else 1.8
    n = _n(d + 1.0)
    t = np.arange(n) / SR
    x = np.zeros(n)
    sub, _ = sine_sweep(1.6 if big else 0.9, 78 if big else 95, 26 if big else 34)                 # the sub-bass fall
    s = np.zeros(n)
    s[:len(sub)] = sub * expenv(len(sub), 0.55 if big else 0.28)
    x += saturate(s * 1.8, 1.0) * 1.25
    th, _ = sine_sweep(0.5, 180, 55)                                                                 # a mid thump that survives on a phone
    tz = np.zeros(n)
    tz[:len(th)] = th * expenv(len(th), 0.16)
    x += saturate(tz * 2.4, 1.0) * 1.1
    blast = lp(white(n, seed + 1) * 3.0, 6000, 1) * expenv(n, 0.05)
    blast = ma.sweep_filter(blast, 7000, 300, "lp") * 1.6 if hasattr(ma, "sweep_filter") else blast
    x += blast
    x += band(white(n, seed + 2), 1500, 9000) * expenv(n, 0.004) * 2.2                               # the crack
    deb = np.zeros(n)
    for _ in range(26 if big else 12):                                                               # debris and crackle
        at = r.uniform(0.08, 1.8 if big else 0.9)
        tk = band(r.standard_normal(_n(0.06)), r.uniform(900, 2500), r.uniform(4500, 9000)) * np.exp(-np.arange(_n(0.06)) / SR / r.uniform(0.006, 0.02))
        put(deb, tk, at, r.uniform(0.25, 0.8) * np.exp(-at / 1.2))
    x += deb * 1.2
    rum = band(white(n, seed + 3), 35, 220) * expenv(n, 0.9 if big else 0.4) * np.minimum(t / 0.05, 1.0) * 2.5
    x += saturate(rum, 1.5)
    x = saturate(x * 0.45, 1.8)
    x = reverb(x, 2.4 if big else 1.2, wet=0.32, predelay=0.02, damp=0.55, seed=seed + 7)
    return master(x, -12.0 if big else -12.5, 6.5, 30.0, 0.5, d + 0.4)


# ------------------------------------------------------------------ build
def build(out_dir, only):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    jobs = []
    for i, name in enumerate(("shot", "shot_1", "shot_2", "shot_3")):
        jobs.append((name, lambda i=i: synth_shot("rifle", 9100 + 17 * i)))
    for i in range(2):
        jobs.append(("shot_far_%d" % i, lambda i=i: synth_shot("rifle", 9200 + 13 * i, "far")))
        jobs.append(("enemy_shot_far_%d" % i, lambda i=i: synth_shot("enemy", 9250 + 13 * i, "far")))
    for i, name in enumerate(("enemy_shot", "enemy_shot_1", "enemy_shot_2")):
        jobs.append((name, lambda i=i: synth_shot("enemy", 9300 + 19 * i)))
    jobs += [("shot_twin", lambda: synth_shot("pistol", 9400)), ("shot_rev", lambda: synth_shot("revolver", 9410)), ("shot_scatter", lambda: synth_shot("shotgun", 9420)),
             ("shot_mini", lambda: synth_shot("minigun", 9430)), ("shot_burst", lambda: synth_shot("burst", 9440)), ("shot_flux", lambda: synth_shot("flux", 9450))]
    for i in range(2):
        jobs.append(("shot_supp_%d" % i, lambda i=i: synth_shot("rifle", 9500 + 7 * i, "supp")))
        jobs.append(("shot_oc_%d" % i, lambda i=i: synth_shot("revolver", 9550 + 7 * i, "oc")))
    for i in range(4):
        jobs.append(("impact_flesh_%d" % i, lambda i=i: flesh(9600 + 11 * i, alien=(i % 2 == 1))))
        jobs.append(("impact_concrete_%d" % i, lambda i=i: concrete(9700 + 11 * i)))
        jobs.append(("impact_metal_%d" % i, lambda i=i: metal(9800 + 11 * i)))
    for i, name in enumerate(("boom", "boom_1", "boom_2", "boom_3")):
        jobs.append((name, lambda i=i: explosion(9900 + 23 * i, True)))
    for i in range(2):
        jobs.append(("explosion_small_%d" % i, lambda i=i: explosion(9950 + 23 * i, False)))
    for name, fn in jobs:
        if not want(name):
            continue
        x = fn()
        ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
        print("%-18s %4.2f s  peak %6.1f  short-term %6.1f LU  crest %4.1f dB  centroid %5.0f Hz" % (name, len(x) / SR, am.peak_db(x), am.short_term(x), am.crest_db(x), am.centroid_hz(x, 250.0)), flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    only = []
    if "--only" in args:
        i = args.index("--only")
        only = args[i + 1:]
        args = args[:i]
    out = args[0] if args else os.path.join(ma.ROOT, "assets", "audio")
    os.makedirs(out, exist_ok=True)
    build(out, only)
