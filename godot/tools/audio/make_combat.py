#!/usr/bin/env python3
"""Combat-feel weapon sounds for Quantum Teleportar (numpy only, 16-bit mono WAV, same kit as make_audio.py).

The owner's phone test said the weapons sound weak. The old carbine shot (shot.wav, shot_1..3) measured: spectral centroid 4.4-5.3 kHz (hiss), 10-14 % of its energy under 300 Hz,
RMS of the first 250 ms at -24 to -26 dBFS: a thin "tss" that a phone speaker barely reproduces. These are rebuilt around what a small speaker CAN play: a hard mid crack (500-3000 Hz),
a fast pitched-down thump (260 -> 70 Hz) that saturates into its own harmonics at 150-500 Hz, a short low-mid blast, a tight slap-back and a SHORT tail (0.5 s, not 0.8 s of reverb).
Louder where it counts: peak -9.5 dBFS and RMS(250 ms) about -17 dBFS (was -12 / -25).

  shot, shot_1 .. shot_3   rift carbine, four variants (the game rotates them and jitters the pitch)
  shot_scatter             shard scatter: a deep boom, wide blast, long slap (a shotgun, not a pitched-down rifle)
  hit_kill                 kill confirm: a dull thock and a rising glassy tick
  civ_dissolve             a citizen dissolving into quantum light: a soft falling shimmer, no gore
Run: python3 tools/audio/make_combat.py [out_dir] [--only name ...]   (called by tools/build_assets.sh after make_weapons.py)
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


def _carbine(seed, f0, f1, crack_lo, body_gain, slap):
    n = _n(1.0)
    click = band(white(n, seed), 2500, 9000) * expenv(n, 0.0012) * 1.1
    crack = band(white(n, seed + 1), crack_lo, 3200) * expenv(n, 0.011) * 3.0
    sw, _ = sine_sweep(0.22, f0, f1)
    thump = np.zeros(n)
    thump[:len(sw)] = sw * expenv(len(sw), 0.07) * body_gain
    blast = band(white(n, seed + 2), 110, 900) * expenv(n, 0.05) * 2.0
    x = click + crack + thump * 1.6 + blast
    x = saturate(x, 2.4)                                          # dense and loud: the harmonics of the thump fill 150-600 Hz
    x = echo(x, 0.085, slap, lp=2000, taps=2)                    # a tight slap off the buildings
    x = reverb(x, 0.5, wet=0.2, predelay=0.01, damp=0.55, seed=seed)
    return ml.done(x, -9.5, 75.0, fout=0.07, max_len=0.55, drive=1.4)


def shot():
    return _carbine(101, 260, 70, 500, 1.0, 0.22)


def shot_1():
    return _carbine(111, 240, 66, 600, 0.9, 0.2)


def shot_2():
    return _carbine(121, 280, 74, 450, 1.1, 0.24)


def shot_3():
    return _carbine(131, 250, 62, 550, 1.0, 0.18)


def shot_scatter():
    n = _n(1.2)
    sw, _ = sine_sweep(0.35, 150, 38)
    boom = np.zeros(n)
    boom[:len(sw)] = sw * expenv(len(sw), 0.1) * 1.3
    blast = band(white(n, 141), 80, 2200) * expenv(n, 0.07) * 2.6
    crack = band(white(n, 142), 700, 5000) * expenv(n, 0.01) * 2.4
    x = saturate(boom * 1.8 + blast + crack, 2.6)
    x = echo(x, 0.16, 0.28, lp=1600, taps=2)
    x = reverb(x, 0.8, wet=0.3, predelay=0.012, damp=0.5, seed=14)
    return ml.done(x, -9.5, 50.0, fout=0.1, max_len=0.9, drive=1.4)


def hit_kill():
    n = _n(0.4)
    t = np.arange(n) / SR
    thock, _ = sine_sweep(0.12, 320, 90)
    th = np.zeros(n)
    th[:len(thock)] = thock * expenv(len(thock), 0.035) * 1.0
    tick = np.sin(2 * np.pi * (1800 + 3200 * np.minimum(t, 0.12) / 0.12) * t) * expenv(n, 0.05) * 0.35
    crack = band(white(n, 151), 1200, 7000) * expenv(n, 0.006) * 1.4
    x = saturate(th * 1.3 + tick + crack, 1.8)
    return ml.done(x, -10.0, 110.0, fout=0.08, max_len=0.35)


def civ_dissolve():
    n = _n(0.9)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, f in enumerate((1200.0, 1810.0, 2630.0, 3510.0)):      # four glassy partials sliding down, each a little later
        d = 0.05 * k
        m = np.clip(t - d, 0.0, None)
        fr = f * (1.0 - 0.45 * np.minimum(m / 0.7, 1.0))
        out += np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-m / 0.22) * (t >= d) * (0.5 / (1 + k))
    out += band(white(n, 161), 2500, 9000) * expenv(n, 0.12) * 0.25
    out = reverb(out, 0.9, wet=0.4, predelay=0.01, damp=0.5, seed=15)
    return ml.done(out, -15.0, 500.0, fout=0.2, max_len=0.85)


SOUNDS = {"shot": shot, "shot_1": shot_1, "shot_2": shot_2, "shot_3": shot_3, "shot_scatter": shot_scatter, "hit_kill": hit_kill, "civ_dissolve": civ_dissolve}


def build(out_dir, only=()):
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        x = fn()
        ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
        seg = x[:_n(0.25)]
        spec = np.abs(np.fft.rfft(x))
        f = np.fft.rfftfreq(len(x), 1.0 / SR)
        print("%-13s %5.2f s  peak %6.1f dBFS  rms250 %6.1f  centroid %5.0f Hz" % (
            name, len(x) / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9), (spec * f).sum() / spec.sum()), flush=True)


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
