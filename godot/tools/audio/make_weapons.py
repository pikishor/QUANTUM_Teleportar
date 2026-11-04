#!/usr/bin/env python3
"""Wave 61 weapon sounds for Quantum Teleportar (numpy only, 16-bit mono WAV, same synthesis kit as make_audio.py).

  shot_mini    plasma minigun: a short, dry, rapid zap (pitch-jittered by the game, fired up to 18 times a second)
  shot_twin    twin pistols: a snappy double-layer crack
  shot_arc     arc caster: a buzzing electric discharge with a rising crackle
  shot_rev     spike revolver: a heavy, low crack with a long tail
  melee_whip   arc whip: a fast air crack that ends in a spark
  melee_blade  quantum blade: a rising hum swish with a bright ring
  overheat     minigun overheat: a hiss with a falling alarm tone
Run: python3 tools/audio/make_weapons.py [out_dir] [--only name ...]   (called by tools/build_assets.sh after make_depth.py)
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, band, expenv, saturate, sine_sweep, white, echo, reverb  # noqa: E402
import make_library as ml  # noqa: E402


def _n(sec):
    return int(sec * SR)


def shot_mini():
    n = _n(0.18)
    sw, _ = sine_sweep(0.12, 1400, 380)
    body = np.zeros(n)
    body[:len(sw)] = sw * expenv(len(sw), 0.03)
    x = body * 0.8 + band(white(n, 21), 2500, 9000) * expenv(n, 0.008) * 1.6 + band(white(n, 22), 300, 1800) * expenv(n, 0.02) * 0.6
    return ml.done(saturate(x, 1.5), -16.0, 150.0, fout=0.05)


def shot_twin():
    n = _n(0.5)
    sw, _ = sine_sweep(0.2, 520, 140)
    body = np.zeros(n)
    body[:len(sw)] = sw * expenv(len(sw), 0.05) * 0.8
    x = band(white(n, 31), 1800, 10000) * expenv(n, 0.003) * 2.6 + band(white(n, 32), 500, 3200) * expenv(n, 0.012) * 1.6 + body
    x += np.roll(x, _n(0.012)) * 0.45                       # the second hand, a hair later
    x = echo(saturate(x, 1.3), 0.11, 0.2, lp=2500, taps=1)
    return ml.done(x, -13.0, 120.0, fout=0.08, max_len=0.4)


def shot_arc():
    n = _n(0.45)
    t = np.arange(n) / SR
    buzz = np.sign(np.sin(2 * np.pi * (180 + 900 * t) * t)) * expenv(n, 0.1) * 0.5
    crackle = band(white(n, 41), 3000, 14000) * (np.sin(2 * np.pi * 70 * t) > 0.2) * expenv(n, 0.12) * 1.8
    zap, _ = sine_sweep(0.25, 3200, 300)
    z = np.zeros(n)
    z[:len(zap)] = zap * expenv(len(zap), 0.05)
    x = band(buzz + crackle + z * 0.9, 200, 11000)
    x = reverb(x, 0.5, wet=0.25, predelay=0.01, damp=0.5, seed=5)
    return ml.done(x, -13.0, 140.0, fout=0.1, max_len=0.5)


def shot_rev():
    n = _n(1.2)
    sw, _ = sine_sweep(0.5, 150, 55)
    body = np.zeros(n)
    body[:len(sw)] = sw * expenv(len(sw), 0.12) * 0.9
    x = band(white(n, 51), 800, 9000) * expenv(n, 0.004) * 2.6 + band(white(n, 52), 150, 1500) * expenv(n, 0.05) * 1.6 + body
    x = echo(saturate(x, 1.5), 0.2, 0.25, lp=1800, taps=2)
    x = reverb(x, 0.9, wet=0.4, predelay=0.012, damp=0.55, seed=9)
    return ml.done(x, -11.0, 50.0, fout=0.15, max_len=1.0)


def melee_whip():
    n = _n(0.5)
    t = np.arange(n) / SR
    air = band(white(n, 61), 1500, 9000) * np.exp(-((t - 0.07) / 0.05) ** 2) * 1.2
    crack = band(white(n, 62), 2500, 12000) * expenv(n, 0.006, 0.12) * 2.0
    zap, _ = sine_sweep(0.3, 2400, 500)
    z = np.zeros(n)
    z[_n(0.12):_n(0.12) + len(zap)] = zap * expenv(len(zap), 0.05) * 0.5
    return ml.done(air + crack + z, -15.0, 300.0, fout=0.08)


def melee_blade():
    n = _n(0.5)
    t = np.arange(n) / SR
    sw, _ = sine_sweep(0.4, 220, 900)
    hum = np.zeros(n)
    hum[:len(sw)] = sw * np.exp(-((t[:len(sw)] - 0.15) / 0.12) ** 2)
    air = band(white(n, 71), 800, 6000) * np.exp(-((t - 0.12) / 0.08) ** 2) * 0.8
    ring = np.sin(2 * np.pi * 1760 * t) * expenv(n, 0.12, 0.14) * 0.35 + np.sin(2 * np.pi * 2637 * t) * expenv(n, 0.08, 0.14) * 0.2
    return ml.done(hum * 0.7 + air + ring, -15.0, 150.0, fout=0.1)


def overheat():
    n = _n(0.9)
    t = np.arange(n) / SR
    hiss = band(white(n, 81), 3000, 12000) * expenv(n, 0.35) * 0.8
    tone = np.sin(2 * np.pi * np.cumsum(900 - 500 * t) / SR) * (np.sin(2 * np.pi * 9 * t) > 0) * expenv(n, 0.4) * 0.5
    return ml.done(hiss + tone, -17.0, 400.0, fout=0.15)


SOUNDS = {"shot_mini": shot_mini, "shot_twin": shot_twin, "shot_arc": shot_arc, "shot_rev": shot_rev, "melee_whip": melee_whip, "melee_blade": melee_blade, "overheat": overheat}


def build(out_dir, only=()):
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        x = fn()
        ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
        print("%-12s %5.2f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)


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
