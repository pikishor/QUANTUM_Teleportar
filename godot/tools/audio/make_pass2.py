#!/usr/bin/env python3
"""Wave audio pass 2 for Quantum Teleportar (numpy + ffmpeg/libvorbis only).

  * music_night (OGG, one 30 s loop on the stems' grid): slow detuned synth pads, the night colour layer
  * dawn_chirps (OGG loop, 12 s): alien bird-equivalents, rising FM chirps over a faint air bed
  * night_insects (OGG loop, 12 s): dry alien insect pulses for the night street
  * thunder_roll (OGG, one-shot): a long low rolling thunder for storms
  * ability one-shots (WAV): entangle_link, collapse, superpos_split, phase_step
  * ui_slide, ui_toggle (WAV)
Run: python3 tools/audio/make_pass2.py [out_dir] [--only glob ...]. Total added size stays under 1.2 MB.
"""
import fnmatch
import os
import shutil
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, band, expenv, saturate, fm_bell, sine_sweep, white  # noqa: E402
import make_library as ml  # noqa: E402
from make_library import R, lp, pnoise  # noqa: E402
import make_music as mm  # noqa: E402
from make_music import N, mtof  # noqa: E402
import make_depth as md  # noqa: E402


def _t(n):
    return np.arange(n) / SR


def music_night():
    dur = N / SR
    t = _t(N)
    L = np.zeros(N)
    Rr = np.zeros(N)
    chords = ((45, 52, 57, 64), (41, 48, 55, 60), (43, 50, 55, 62), (40, 47, 55, 59))   # Am, F, G, Em-ish open voicings
    seg = N // len(chords)
    for ci, ch in enumerate(chords):
        env = np.zeros(N)
        a, b = ci * seg, (ci + 1) * seg
        s = np.arange(seg) / seg
        env[a:b] = np.sin(np.pi * s) ** 2
        env += np.roll(env, 0) * 0.0
        for k, m in enumerate(ch):
            for det, pan in ((-0.07, 0.0), (0.0, 0.5), (0.07, 1.0)):
                f = ml.snap(mtof(m) * (1.0 + det * 0.01 * (k + 1)), dur)
                x = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * ml.snap(2 * f, dur) * t + 1.0) + 0.15 * np.sin(2 * np.pi * ml.snap(3 * f, dur) * t)
                x = x * env / (1 + k * 0.4)
                L += x * (1 - pan)
                Rr += x * pan
    sw = 0.8 + 0.2 * np.sin(2 * np.pi * ml.snap(0.2, dur) * t)
    L, Rr = lp(L * sw, 900, 2), lp(Rr * np.roll(sw, 5000), 900, 2)
    return md._fit(np.stack([L, Rr]))


def dawn_chirps():
    dur = 12.0
    n = int(dur * SR)
    r = R(1201)
    out = np.zeros(n)
    for _ in range(14):
        at = r.uniform(0.0, dur - 1.0)
        d = r.uniform(0.12, 0.35)
        f0 = r.uniform(1800, 3600)
        f1 = f0 * r.choice([1.5, 1.8, 0.6])
        m = int(d * SR)
        ph = np.cumsum(2 * np.pi * np.linspace(f0, f1, m) / SR)
        c = np.sin(ph + 2.0 * np.sin(ph * 0.5)) * np.sin(np.pi * np.arange(m) / m) ** 2
        for rep in range(r.integers(1, 4)):
            i = int((at + rep * (d + 0.07)) * SR)
            if i + m < n:
                out[i:i + m] += c * (0.8 ** rep)
    air = pnoise(n, 1202, lambda f: np.exp(-(((np.log(f) - np.log(2500.0)) / 0.7) ** 2)))
    out = out + air / (np.std(air) + 1e-9) * 0.05
    return ml.done_loop(out, -10.0, 900.0)


def night_insects():
    dur = 12.0
    n = int(dur * SR)
    t = _t(n)
    out = np.zeros(n)
    for k, (f, rate) in enumerate(((4300, 7.0), (5200, 5.0), (3500, 11.0))):
        rate = ml.snap(rate, dur)
        gate = np.clip(np.sin(2 * np.pi * rate * t + k) * 3.0, 0.0, 1.0) * (0.5 + 0.5 * np.sin(2 * np.pi * ml.snap(0.25 + 0.1 * k, dur) * t + k * 2))
        out += np.sin(2 * np.pi * ml.snap(f, dur) * t) * gate * (0.6 / (k + 1))
    return ml.done_loop(out, -10.0, 1500.0)


def thunder_roll():
    dur = 6.0
    n = int(dur * SR)
    t = _t(n)
    x = band(white(n, 1210), 30, 220) * expenv(n, 1.8) + band(white(n, 1211), 80, 600) * expenv(n, 0.5) * 0.4
    mod = 0.6 + 0.4 * np.sin(2 * np.pi * 2.3 * t + 6 * np.sin(2 * np.pi * 0.4 * t))
    x = saturate(x * mod / (np.max(np.abs(x)) + 1e-9), 1.4)
    return ml.done(x, -8.0, 25.0, fout=1.2, max_len=5.5)


def entangle_link():
    n = int(0.55 * SR)
    t = _t(n)
    a = np.sin(2 * np.pi * 880 * t) * expenv(n, 0.2)
    b = np.sin(2 * np.pi * 1320.0 * t) * expenv(n, 0.2) * np.minimum(t / 0.12, 1.0)
    x = (a + 0.8 * b) * (0.7 + 0.3 * np.sin(2 * np.pi * 14 * t)) + band(white(n, 1220), 4000, 9000) * expenv(n, 0.03) * 0.2
    return ml.done(ml.wet(x, 0.5, mix=0.2, seed=1221), -13.0, 300.0, fout=0.12, max_len=0.7)


def collapse():
    n = int(0.9 * SR)
    t = _t(n)
    x = sine_sweep(0.9, 1800, 60)[0] * expenv(n, 0.35)
    x += band(white(n, 1230), 200, 5000) * expenv(n, 0.05) * 0.8
    x += np.sin(2 * np.pi * 48 * t) * expenv(n, 0.3, 0.0) * 0.9
    return ml.done(saturate(x, 1.6), -9.0, 35.0, fout=0.2, max_len=1.0)


def superpos_split():
    n = int(0.7 * SR)
    t = _t(n)
    f = 330 * np.exp(0.9 * t / 0.7)
    ph = np.cumsum(2 * np.pi * f / SR)
    x = (np.sin(ph) + np.sin(ph * 1.0149)) * np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.3)
    x += fm_bell(0.7, 1320, 2.0, 1.2, 0.2, 0.1)[:n] * 0.4
    return ml.done(x, -13.0, 200.0, fout=0.15, max_len=0.8)


def phase_step():
    n = int(0.28 * SR)
    t = _t(n)
    x = sine_sweep(0.28, 300, 2400)[0] * np.minimum(t / 0.01, 1.0) * np.exp(-t / 0.1)
    x += band(white(n, 1240), 1500, 8000) * expenv(n, 0.05) * 0.4
    return ml.done(x, -14.0, 200.0, fout=0.06, max_len=0.3)


def ui_slide():
    n = int(0.06 * SR)
    t = _t(n)
    x = np.sin(2 * np.pi * 1500 * t) * expenv(n, 0.015) * 0.7 + band(white(n, 1250), 2500, 7000) * expenv(n, 0.01) * 0.3
    return ml.done(x, -26.0, 600.0, fout=0.015)


def ui_toggle():
    n = int(0.12 * SR)
    t = _t(n)
    x = np.sin(2 * np.pi * 1100 * t) * expenv(n, 0.03) + np.sin(2 * np.pi * 1650 * t) * expenv(n, 0.03) * np.minimum(np.maximum(t - 0.03, 0) / 0.005, 1.0)
    return ml.done(x, -20.0, 500.0, fout=0.04)


def build(out_dir, only=()):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    tmp = tempfile.mkdtemp(prefix="qt_pass2_")
    try:
        for name, fn, mono in (("music_night", music_night, False), ("dawn_chirps", dawn_chirps, True), ("night_insects", night_insects, True), ("thunder_roll", thunder_roll, True)):
            if want(name):
                x = fn()
                mm.to_ogg(x[None, :] if mono else x, os.path.join(out_dir, name + ".ogg"), 2, tmp)
                print("%-16s %5.1f s" % (name, (x.shape[-1]) / SR), flush=True)
        for name, fn in (("entangle_link", entangle_link), ("collapse", collapse), ("superpos_split", superpos_split), ("phase_step", phase_step), ("ui_slide", ui_slide), ("ui_toggle", ui_toggle)):
            if want(name):
                x = fn()
                ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
                print("%-16s %5.2f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
