#!/usr/bin/env python3
"""Numpy-synthesised game audio for Quantum Teleportar (no samples, no scipy): 44.1 kHz, mono, 16-bit PCM WAV.

Every effect is layered (transient + body + tail) and run through a synthetic convolution reverb; everything is normalised to
-3 dBFS peak with short fades. The music loop is built so every oscillator completes whole cycles in the loop length and the
reverb is applied circularly, which makes it seamless (the WAV also carries a `smpl` loop chunk so Godot loops it by default).

Usage: python3 make_audio.py [--out DIR] [--only shot,boom] [--preview FILE.png]
"""
import argparse
import os
import struct
import sys
import time

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PEAK = 10 ** (-3.0 / 20.0)          # -3 dBFS


# ------------------------------------------------------------------ basics
def tvec(dur):
    return np.arange(int(round(dur * SR))) / SR


def white(n, seed):
    return np.random.default_rng(seed).standard_normal(n) / 3.0


def fft_filter(x, lo=None, hi=None, order=2):
    """Zero-phase Butterworth-magnitude filter by FFT (lo = high-pass corner, hi = low-pass corner)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if hi:
        g /= np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def band(x, lo, hi, order=2):
    return fft_filter(x, lo, hi, order)


def sweep_filter(x, f0, f1, kind="lp", frame=2048, order=2, curve=1.0):
    """Time-varying low/high-pass by overlap-add FFT blocks (cutoff moves geometrically f0 -> f1 over the signal)."""
    n = len(x)
    hop = frame // 2
    win = np.hanning(frame)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    out = np.zeros_like(pad)
    nblocks = (len(pad) - frame) // hop
    f = np.fft.rfftfreq(frame, 1.0 / SR)
    for b in range(nblocks):
        i = b * hop
        t = np.clip((i - frame) / max(n, 1), 0.0, 1.0) ** curve
        fc = f0 * (f1 / f0) ** t
        if kind == "lp":
            g = 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
        else:
            g = 1.0 / np.sqrt(1.0 + (fc / np.maximum(f, 1e-9)) ** (2 * order))
        out[i:i + frame] += np.fft.irfft(np.fft.rfft(pad[i:i + frame] * win) * g, frame)     # Hann at 50% overlap sums to 1
    return out[frame:frame + n]


def expenv(n, tau, start=0.0):
    t = np.arange(n) / SR - start
    return np.where(t >= 0, np.exp(-np.maximum(t, 0) / tau), 0.0)


def ahd(n, a, hold, tau):
    """Attack (linear), hold, exponential decay (all seconds)."""
    t = np.arange(n) / SR
    env = np.where(t < a, t / max(a, 1e-6), 1.0)
    env = np.where(t > a + hold, np.exp(-(t - a - hold) / tau), env)
    return env


def fade(x, fin=0.0005, fout=0.02):
    x = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b) ** 1.5
    return x


def place(buf, sig, t0, gain=1.0):
    i = int(t0 * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[:j - i] * gain


def sine_sweep(dur, f0, f1, curve="exp"):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if curve == "exp":
        f = f0 * (f1 / f0) ** (t / dur)
    else:
        f = f0 + (f1 - f0) * (t / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR), f


def fm_bell(dur, fc, ratio=2.76, index=2.0, tau=0.3, itau=0.15, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = index * np.exp(-t / itau)
    return np.sin(2 * np.pi * fc * t + idx * np.sin(2 * np.pi * fc * ratio * t)) * np.exp(-t / tau)


def saturate(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def make_ir(rt60, predelay=0.012, damp=0.5, seed=7, early=True):
    n = int((rt60 + predelay + 0.05) * SR)
    t = np.arange(n) / SR
    w = np.random.default_rng(seed).standard_normal(n)
    ir = np.zeros(n)
    for lo, hi, mult, gain in ((20, 450, 1.0, 1.0), (450, 2600, 0.72, 0.85), (2600, 9000, 0.42 * (1 - damp) + 0.12, 0.55)):
        ir += band(w, lo, hi) * gain * np.exp(-6.91 * np.maximum(t - predelay, 0) / (rt60 * mult))
    ir[: int(predelay * SR)] = 0.0
    if early:
        r = np.random.default_rng(seed + 1)
        for d in r.uniform(0.006, 0.07, 9):
            ir[int((predelay + d) * SR)] += r.uniform(0.5, 1.4) * (1 if r.random() > 0.3 else -1) * np.exp(-d / (rt60 * 0.2)) * 2.2
    return ir / np.sqrt(np.sum(ir ** 2) + 1e-12)


def reverb(x, rt60, wet=0.3, predelay=0.012, damp=0.5, seed=7, tail=True):
    ir = make_ir(rt60, predelay, damp, seed)
    n = len(x) + (len(ir) if tail else 0)
    size = 1 << int(np.ceil(np.log2(n + len(ir))))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]
    d = np.concatenate([x, np.zeros(n - len(x))])
    return d * (1.0 - wet * 0.5) + y * wet * 1.6


def echo(x, delay, gain, lp=None, taps=1, extra_len=0.0):
    n = len(x) + int((delay * taps + extra_len) * SR)
    y = np.zeros(n)
    y[:len(x)] += x
    sig = x
    for k in range(1, taps + 1):
        s = fft_filter(sig, None, lp) if lp else sig
        place(y, s, delay * k, gain ** k)
    return y


def finalize(x, fin=0.0005, fout=0.03, trim_db=-55.0, drive=1.15, max_len=None):
    """Soft limit, trim the silent tail, cap the length, fade, normalise to -3 dBFS."""
    x = saturate(x / (np.max(np.abs(x)) + 1e-9), drive)
    if max_len:
        x = x[: int(max_len * SR)]
    thr = 10 ** (trim_db / 20.0) * np.max(np.abs(x))
    idx = np.nonzero(np.abs(x) > thr)[0]
    if len(idx):
        x = x[: min(len(x), idx[-1] + int(0.05 * SR))]
    x = fade(x, fin, fout)
    return x / (np.max(np.abs(x)) + 1e-9) * PEAK


# ------------------------------------------------------------------ the sound effects
def sfx_shot():
    """Player carbine: sharp crack, chest-thump body, slap-back and a cavernous night-street tail."""
    n = int(1.6 * SR)
    out = np.zeros(n)
    crack = band(white(n, 1), 1500, 11000) * expenv(n, 0.0018) * 3.2
    crack += band(white(n, 2), 400, 3500) * expenv(n, 0.006) * 2.4
    crack += band(white(n, 6), 3000, 14000) * expenv(n, 0.0008) * 1.6                 # the very first ms: air-pressure click
    body_s, _ = sine_sweep(0.4, 190, 58)
    body = np.zeros(n)
    body[:len(body_s)] = body_s * expenv(len(body_s), 0.05) * 0.55
    blast = band(white(n, 3), 100, 1600) * expenv(n, 0.04) * 1.3
    mid = band(white(n, 4), 250, 2600) * expenv(n, 0.02) * 1.5
    out += crack + body + blast + mid
    tick = band(white(n, 5), 2500, 7000) * expenv(n, 0.006, 0.075) * 0.35        # bolt carrier movement
    out += tick
    out = saturate(out, 1.4)
    out = echo(out, 0.19, 0.3, lp=2200, taps=2)                                   # slap-back from the buildings
    out = reverb(out, 0.7, wet=0.42, predelay=0.014, damp=0.5, seed=11)
    return finalize(out, fout=0.12, max_len=1.05)


def sfx_enemy_shot():
    """Observer carbine / drone bolt: thinner and harder, with a falling tonal energy component and a short flanged tail."""
    n = int(1.2 * SR)
    out = np.zeros(n)
    crack = band(white(n, 21), 2500, 10000) * expenv(n, 0.0018) * 1.0
    snap = band(white(n, 22), 900, 5000) * expenv(n, 0.008) * 0.8
    zap_s, f = sine_sweep(0.28, 1400, 190)
    saw = np.zeros(len(zap_s))
    ph = np.cumsum(f) / SR
    for k in range(1, 7):
        saw += np.sin(2 * np.pi * ph * k) / k
    zap = np.zeros(n)
    zap[:len(saw)] = saw * expenv(len(saw), 0.075) * 0.55
    zap = fft_filter(zap, 150, 5200)
    thump_s, _ = sine_sweep(0.2, 130, 62)
    thump = np.zeros(n)
    thump[:len(thump_s)] = thump_s * expenv(len(thump_s), 0.05) * 0.5
    body = band(white(n, 23), 300, 1800) * expenv(n, 0.016) * 1.4
    out += crack * 1.4 + snap + zap + thump + body
    out = saturate(out, 1.8)
    d = int(0.0016 * SR)                                                           # short comb for a hard metallic edge
    out[d:] += out[:-d] * 0.35
    out = echo(out, 0.12, 0.25, lp=3000, taps=2)
    out = reverb(out, 0.45, wet=0.3, predelay=0.008, damp=0.4, seed=12)
    return finalize(out, fout=0.08, max_len=0.8)


def sfx_hit():
    """Bullet strike on armour: dull thud, brittle crack and a short inharmonic ring."""
    n = int(0.6 * SR)
    out = np.zeros(n)
    thud_s, _ = sine_sweep(0.2, 150, 62)
    thud = np.zeros(n)
    thud[:len(thud_s)] = thud_s * expenv(len(thud_s), 0.03) * 0.9
    crack = band(white(n, 31), 900, 7500) * expenv(n, 0.008) * 2.4
    t = np.arange(n) / SR
    ring = (np.sin(2 * np.pi * 1480 * t) * 0.5 + np.sin(2 * np.pi * 2310 * t) * 0.35 + np.sin(2 * np.pi * 3720 * t) * 0.2) * expenv(n, 0.045) * 0.28
    out = thud + crack + ring + band(white(n, 32), 3000, 9000) * expenv(n, 0.003) * 0.6
    out = reverb(saturate(out, 1.4), 0.35, wet=0.25, predelay=0.006, damp=0.5, seed=13)
    return finalize(out, fout=0.06, max_len=0.42)


def sfx_hurt():
    """Player takes damage: heavy body impact, muffled breath of air, a short tinnitus whine and a stumbling heartbeat."""
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    th_s, _ = sine_sweep(0.45, 105, 40)
    th = np.zeros(n)
    th[:len(th_s)] = th_s * expenv(len(th_s), 0.11) * 1.0
    air = band(white(n, 41), 60, 800) * ahd(n, 0.004, 0.0, 0.09) * 1.0
    snap = band(white(n, 42), 300, 3500) * expenv(n, 0.03) * 1.5
    grunt = np.zeros(n)
    saw = np.zeros(n)
    ph = 2 * np.pi * np.cumsum(120 * (0.85 + 0.15 * np.exp(-t / 0.2))) / SR
    for k in range(1, 9):
        saw += np.sin(ph * k) / k
    grunt = fft_filter(saw, 80, 900) * ahd(n, 0.01, 0.04, 0.12) * 0.55
    whine = np.sin(2 * np.pi * 3400 * t) * np.clip((t - 0.08) / 0.35, 0, 1) * np.exp(-np.maximum(t - 0.45, 0) / 0.35) * 0.05
    for hb_t, amp in ((0.34, 0.5), (0.52, 0.35)):
        hb_s, _ = sine_sweep(0.14, 70, 38)
        place(out, hb_s * expenv(len(hb_s), 0.04) * amp, hb_t)
    out += th + air + snap + grunt + whine
    out = reverb(saturate(out, 1.3), 0.6, wet=0.3, predelay=0.01, damp=0.7, seed=14)
    return finalize(out, fout=0.15, max_len=1.15)


def sfx_boom():
    """Explosion: crack, sub drop, sweeping rumble, falling debris and a huge reverb tail."""
    n = int(4.2 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    crack = band(white(n, 51), 400, 10000) * expenv(n, 0.014) * 2.6
    crack += band(white(n, 52), 100, 1500) * expenv(n, 0.05) * 1.4
    crack += band(white(n, 56), 120, 2200) * ahd(n, 0.004, 0.03, 0.32) * 1.5
    sub_s, _ = sine_sweep(1.2, 78, 24)
    sub = np.zeros(n)
    sub[:len(sub_s)] = sub_s * expenv(len(sub_s), 0.38) * 1.7
    brown = np.cumsum(white(n, 53))
    brown -= np.linspace(brown[0], brown[-1], n)
    brown /= np.max(np.abs(brown))
    rumble = sweep_filter(brown + white(n, 54) * 0.4, 1500, 90, "lp", curve=0.6) * (ahd(n, 0.006, 0.05, 0.55)) * 2.0
    deb = np.zeros(n)
    r = np.random.default_rng(55)
    for _ in range(140):
        t0 = r.exponential(0.5) + 0.06
        if t0 > 2.6:
            continue
        ln = int(r.uniform(0.004, 0.02) * SR)
        burst = band(white(ln, int(r.integers(1, 1 << 30))), r.uniform(800, 3500), r.uniform(4500, 9000)) * np.exp(-np.arange(ln) / (ln * 0.3))
        place(deb, burst, t0, r.uniform(0.08, 0.3) * np.exp(-t0 / 1.4))
    out += crack + sub + rumble + deb
    out = saturate(out, 1.5)
    out = reverb(out, 2.0, wet=0.45, predelay=0.02, damp=0.35, seed=15)
    return finalize(out, fout=0.45, drive=1.05, max_len=3.4)


def sfx_blink():
    """Quantum blink: reversed-reverb swell and rising shimmer into a hard phase snap, sub thump and glassy decay."""
    n = int(1.5 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    snap_t = 0.42
    # swell: reversed reverb of a click, so the energy builds into the snap
    seed_sig = np.zeros(int(1.4 * SR))
    seed_sig[0] = 1.0
    seed_sig += band(white(len(seed_sig), 61), 600, 7000) * expenv(len(seed_sig), 0.01) * 0.7
    wash = reverb(seed_sig, 0.9, wet=1.0, predelay=0.0, damp=0.1, seed=17)[: int(0.9 * SR)]
    wash = wash[::-1] * np.linspace(0.2, 1, len(wash)) ** 2
    wash = wash[-int((snap_t + 0.02) * SR):]                       # keep the part that builds up to the snap
    place(out, wash / np.max(np.abs(wash)) * 0.85, 0.0)
    # rising chirp (phase-modulated) under the swell
    ch_s, f = sine_sweep(snap_t, 300, 3200)
    ch = ch_s * (np.linspace(0, 1, len(ch_s)) ** 2.2) * 0.35
    ch += np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * (np.linspace(0, 1, len(ch_s)) ** 3) * 0.12
    place(out, ch, 0.0)
    nz = sweep_filter(band(white(int(snap_t * SR), 62), 200, 9000), 400, 5500, "lp") * (np.linspace(0, 1, int(snap_t * SR)) ** 2.5) * 0.5
    place(out, nz, 0.0)
    # snap + sub + glassy shimmer
    place(out, band(white(int(0.2 * SR), 63), 500, 12000) * expenv(int(0.2 * SR), 0.006) * 2.0, snap_t)
    sub_s, _ = sine_sweep(0.5, 95, 38)
    place(out, sub_s * expenv(len(sub_s), 0.12) * 0.9, snap_t)
    sh = np.zeros(int(1.0 * SR))
    tt = np.arange(len(sh)) / SR
    for fr, am in ((1318.5, 1.0), (1760.0, 0.8), (2217.5, 0.6), (2793.0, 0.45), (3520.0, 0.3)):
        sh += np.sin(2 * np.pi * fr * tt + 2.0 * np.sin(2 * np.pi * 5.5 * tt)) * am * (0.6 + 0.4 * np.sin(2 * np.pi * 17 * tt))
    place(out, sh * expenv(len(sh), 0.16) * 0.34, snap_t + 0.004)
    out = reverb(saturate(out, 1.3), 0.9, wet=0.36, predelay=0.012, damp=0.4, seed=18)
    return finalize(out, fout=0.2, max_len=1.35)


def sfx_link():
    """Entanglement link: a beating pair of FM tones locking together, crystalline partials, static crackle, low hum."""
    n = int(1.3 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    f_sweep, _ = sine_sweep(0.14, 380, 1046)
    place(out, f_sweep * np.linspace(0.2, 1, len(f_sweep)) * 0.5, 0.0)
    env = ahd(n, 0.03, 0.18, 0.32)
    for f0, a in ((523.25, 1.0), (527.2, 1.0)):
        out += np.sin(2 * np.pi * f0 * t + 0.9 * np.sin(2 * np.pi * f0 * 2.0 * t) * np.exp(-t / 0.25)) * env * 0.28 * a
    out += np.sin(2 * np.pi * 261.6 * t) * env * 0.22 + np.sin(2 * np.pi * 110 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 7 * t)) * env * 0.18
    place(out, fm_bell(1.0, 1568.0, 3.5, 1.6, 0.42, 0.18), 0.06, 0.20)
    place(out, fm_bell(1.0, 2093.0, 3.5, 1.2, 0.3, 0.12), 0.16, 0.12)
    r = np.random.default_rng(71)
    for _ in range(46):
        t0 = r.uniform(0.0, 0.95)
        ln = int(r.uniform(0.0008, 0.004) * SR)
        place(out, band(white(ln, int(r.integers(1, 1 << 30))), 2500, 9000) * np.exp(-np.arange(ln) / (ln * 0.4)), t0, r.uniform(0.04, 0.16) * (1 - t0 / 1.2))
    lock_s, _ = sine_sweep(0.12, 150, 70)
    place(out, lock_s * expenv(len(lock_s), 0.04) * 0.9, 0.14)
    out = reverb(saturate(out, 1.2), 0.8, wet=0.33, predelay=0.012, damp=0.45, seed=19)
    return finalize(out, fout=0.2, max_len=1.4)


def _polysaw(freqs, dur, detune=(-9, 0, 9), nh=9, seed=1):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    r = np.random.default_rng(seed)
    for f in freqs:
        for d in detune:
            ff = f * 2 ** (d / 1200.0)
            ph = r.uniform(0, 2 * np.pi)
            for k in range(1, nh + 1):
                if ff * k > 9000:
                    break
                out += np.sin(2 * np.pi * ff * k * t + ph * k) / k
    return out / (len(freqs) * len(detune))


def sfx_superpos():
    """Superposition: a detuned minor chord swells and phases against itself, with a low pulse as the clone splits off."""
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    chord = _polysaw([110.0, 164.81, 220.0, 261.63, 329.63], 1.6, nh=10, seed=3)
    swell = np.clip(t / 0.35, 0, 1) ** 1.5 * np.exp(-np.maximum(t - 0.55, 0) / 0.5)
    pad = sweep_filter(chord, 350, 3600, "lp", curve=0.5) * swell * 0.9
    # flanged copy: comb filter swept slowly -> the "two states at once" shimmer
    d0 = (0.0035 + 0.0025 * np.sin(2 * np.pi * 1.3 * t) + 0.003 * (1 - t / 1.6))
    idx = np.clip((np.arange(n) - d0 * SR).astype(int), 0, n - 1)
    pad2 = pad + pad[idx] * 0.85
    sub_s, _ = sine_sweep(0.6, 82, 41)
    sub = np.zeros(n)
    sub[:len(sub_s)] = sub_s * expenv(len(sub_s), 0.17) * 1.2
    hi = np.zeros(n)
    for fr, a in ((880.0, 1.0), (880.0 * 2 ** (11 / 1200.0), 1.0), (1318.5, 0.6)):
        hi += np.sin(2 * np.pi * fr * t) * a
    hi *= np.clip((t - 0.1) / 0.3, 0, 1) * np.exp(-np.maximum(t - 0.4, 0) / 0.45) * 0.06 * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * t))
    out = pad2 * 0.8 + sub + hi + band(white(n, 81), 1500, 8000) * expenv(n, 0.015) * 0.3
    out = reverb(saturate(out, 1.25), 1.2, wet=0.4, predelay=0.015, damp=0.45, seed=20)
    return finalize(out, fout=0.3, max_len=1.9)


def sfx_pickup():
    """Pick-up: weighted dull click, then a restrained two-note FM chime (a data-link acknowledgement, not an arcade jingle)."""
    n = int(1.0 * SR)
    out = np.zeros(n)
    th_s, _ = sine_sweep(0.09, 170, 85)
    out[:len(th_s)] += th_s * expenv(len(th_s), 0.03) * 1.3
    out += band(white(n, 91), 1500, 7000) * expenv(n, 0.003) * 0.5
    place(out, fm_bell(0.8, 659.3, 2.0, 1.4, 0.16, 0.09), 0.03, 0.55)
    place(out, fm_bell(0.8, 987.8, 2.0, 1.2, 0.2, 0.09), 0.115, 0.45)
    place(out, fm_bell(0.8, 1975.5, 3.0, 0.8, 0.12, 0.05), 0.115, 0.14)
    out = reverb(saturate(out, 1.2), 0.6, wet=0.3, predelay=0.01, damp=0.5, seed=21)
    return finalize(out, fout=0.15, max_len=0.9)


def _click(freq_body, tau, hi_lo, hi_hi, dur=0.08, seed=0, gain=1.0, ring=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = band(white(n, seed), hi_lo, hi_hi) * expenv(n, tau * 0.35)
    s += np.sin(2 * np.pi * freq_body * t) * expenv(n, tau) * 0.5
    if ring:
        for fr, a in ring:
            s += np.sin(2 * np.pi * fr * t) * expenv(n, tau * 1.6) * a
    return s * gain


def sfx_reload():
    """Magazine out, magazine in, charging handle: four mechanical events with real metal resonances."""
    n = int(1.45 * SR)
    out = np.zeros(n)
    place(out, _click(900, 0.01, 2000, 8000, seed=101, gain=0.7, ring=[(2400, 0.2)]), 0.04)                    # release
    slide = band(white(int(0.09 * SR), 102), 1200, 5000) * np.hanning(int(0.09 * SR)) * 0.3
    place(out, slide, 0.17)
    place(out, _click(180, 0.03, 600, 5000, seed=103, gain=0.8), 0.27)                                         # mag drops out
    place(out, band(white(int(0.12 * SR), 104), 800, 4500) * np.hanning(int(0.12 * SR)) * 0.25, 0.58)         # new mag slides in
    place(out, _click(140, 0.04, 1200, 9000, seed=105, gain=1.3, ring=[(1180, 0.35), (2330, 0.22)]), 0.72)    # seated
    rack = sweep_filter(band(white(int(0.09 * SR), 106), 400, 9000), 600, 5000, "lp") * np.hanning(int(0.09 * SR)) * 0.5
    place(out, rack, 1.0)                                                                                      # charging handle back
    place(out, _click(120, 0.05, 1500, 9000, seed=107, gain=1.6, ring=[(1500, 0.3), (3100, 0.18)]), 1.1)       # forward: clack
    spring = np.sin(2 * np.pi * 3300 * np.arange(int(0.08 * SR)) / SR) * expenv(int(0.08 * SR), 0.015) * 0.06
    place(out, spring, 1.12)
    out = reverb(saturate(out, 1.2), 0.3, wet=0.22, predelay=0.006, damp=0.6, seed=22)
    return finalize(out, fout=0.1, max_len=1.45)


def sfx_core():
    """Quantum core collected: harmonic swell and riser into a sub impact, a bell cluster and a long cinematic tail."""
    n = int(4.2 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    hit_t = 1.0
    sw = np.zeros(n)
    for k, a in enumerate((1.0, 0.7, 0.55, 0.4, 0.3, 0.22)):
        sw += np.sin(2 * np.pi * 110.0 * (k + 1) * t + 0.4 * k) * a * (np.clip(t / hit_t, 0, 1) ** (1.5 + 0.4 * k))
    sw *= np.where(t < hit_t, 1.0, np.exp(-(t - hit_t) / 0.6))
    out += sw * 0.45
    nz = sweep_filter(band(white(int(hit_t * SR), 111), 150, 9000), 300, 7000, "lp", curve=1.4) * (np.linspace(0, 1, int(hit_t * SR)) ** 2.2) * 0.55
    place(out, nz, 0.0)
    place(out, band(white(int(0.3 * SR), 112), 300, 11000) * expenv(int(0.3 * SR), 0.015) * 1.2, hit_t)
    sub_s, _ = sine_sweep(1.4, 70, 30)
    place(out, sub_s * expenv(len(sub_s), 0.4) * 1.0, hit_t)
    for fr, a, tau, dt in ((523.25, 0.5, 0.9, 0.0), (783.99, 0.42, 1.0, 0.03), (1046.5, 0.36, 0.9, 0.06), (1568.0, 0.25, 0.8, 0.09), (2093.0, 0.16, 0.7, 0.12)):
        place(out, fm_bell(3.0, fr, 2.76, 1.8, tau, 0.25), hit_t + dt, a * 0.8)
    out = reverb(saturate(out, 1.2), 2.6, wet=0.5, predelay=0.02, damp=0.3, seed=23)
    return finalize(out, fout=0.5, drive=1.1, max_len=3.9)


# ------------------------------------------------------------------ the music loop
def music_ambient(duration=30.0):
    """Dark cinematic bed: detuned pad chords, sub drone, slow heartbeat pulses with a circular delay, rain hiss, far bells.
    64 BPM x 32 beats = 30.0 s; every oscillator uses a frequency that is a multiple of 1/30 Hz so the loop closes exactly."""
    N = int(duration * SR)
    tail = int(4.0 * SR)
    T = np.arange(N + tail) / SR
    rng_ = np.random.default_rng(2024)
    beat = duration / 32.0

    def snap(f):
        return round(f * duration) / duration

    def fold(sig):
        out = sig[:N].copy()
        out[: len(sig) - N] += sig[N:]
        return out

    # wavetable saw (soft, 11 harmonics)
    wt_n = 4096
    ph = np.arange(wt_n) / wt_n * 2 * np.pi
    wt = sum(np.sin(k * ph) / k for k in range(1, 12))
    wt /= np.max(np.abs(wt))

    def osc(f, seed_phase=0.0, vib=0.0, vib_cycles=3):
        fr = snap(f) * (1.0 + vib * np.sin(2 * np.pi * vib_cycles * T / duration + seed_phase))
        phase = np.cumsum(fr) / SR + seed_phase
        idx = (phase % 1.0) * wt_n
        i0 = idx.astype(int) % wt_n
        a = idx - np.floor(idx)
        return wt[i0] * (1 - a) + wt[(i0 + 1) % wt_n] * a

    chords = [  # (root Hz, semitone offsets)
        (110.0, (0, 7, 12, 15, 19)),     # A minor
        (87.31, (0, 7, 12, 16, 19)),     # F major
        (73.42, (0, 7, 12, 15, 17)),     # D minor (add 11)
        (82.41, (0, 7, 12, 16, 22)),     # E7
    ]
    seg = duration / 4.0
    pad = np.zeros(N)
    for ci, (root, offs) in enumerate(chords):
        t0 = ci * seg
        env = np.clip((T - t0) / 2.2, 0, 1) ** 1.6 * np.clip(1.0 - np.maximum(T - (t0 + seg), 0) / 2.4, 0, 1)
        env = np.where(T < t0, 0.0, env)
        voice = np.zeros(N + tail)
        for oi, o in enumerate(offs):
            f = root * 2 ** (o / 12.0) * (2 if o < 12 and oi == 0 else 1)
            for d in (-7, 0, 7):
                voice += osc(f * 2 ** (d / 1200.0), seed_phase=0.7 * oi + 0.3 * d, vib=0.0012, vib_cycles=2 + oi) * (0.5 if d else 0.8) / (1.0 + 0.25 * oi)
        pad += fold(voice * env)
    pad /= np.max(np.abs(pad))
    p1, p2, p3 = (fft_filter(pad, None, 420, 3), fft_filter(pad, None, 1100, 3), fft_filter(pad, None, 3200, 2))
    tN = np.arange(N) / duration
    w1 = 0.5 + 0.5 * np.sin(2 * np.pi * 2 * tN + 0.3)
    w2 = 0.5 + 0.5 * np.sin(2 * np.pi * 3 * tN + 2.0)
    w3 = (0.5 + 0.5 * np.sin(2 * np.pi * 1 * tN + 4.2)) ** 2
    pad = (p1 * (0.35 + 0.3 * w1) + p2 * 0.85 * w2 + p3 * 0.6 * w3) * 0.6

    # sub drone following the chord roots (+ saturation so phone speakers still hear it)
    sub = np.zeros(N + tail)
    for ci, (root, _) in enumerate(chords):
        t0 = ci * seg
        env = np.clip((T - t0) / 1.6, 0, 1) * np.clip(1.0 - np.maximum(T - (t0 + seg), 0) / 1.8, 0, 1)
        env = np.where(T < t0, 0.0, env)
        sub += np.sin(2 * np.pi * snap(root / 2) * T) * env
    sub = fold(sub)
    sub = saturate(sub * 1.2, 2.2) * 0.22

    # heartbeat pulses on beats 0 and 2 of each bar + a quiet tick on every beat, then a circular dotted delay
    pulse = np.zeros(N)
    for b in range(32):
        t0 = b * beat
        if b % 4 in (0, 2):
            ps, _ = sine_sweep(0.5, 118, 52)
            seg_p = ps * expenv(len(ps), 0.13) * (1.0 if b % 4 == 0 else 0.6)
            idx = int(t0 * SR)
            end = min(N, idx + len(seg_p))
            pulse[idx:end] += seg_p[: end - idx] * 0.55
        tick = band(white(int(0.03 * SR), 300 + b), 2500, 8000) * expenv(int(0.03 * SR), 0.006) * 0.07
        idx = int(t0 * SR)
        end = min(N, idx + len(tick))
        pulse[idx:end] += tick[: end - idx]
    d = int(beat * 0.75 * SR)
    dl = np.roll(fft_filter(pulse, None, 900, 2), d) * 0.5 + np.roll(fft_filter(pulse, None, 600, 2), 2 * d) * 0.28 + np.roll(fft_filter(pulse, None, 450, 2), 3 * d) * 0.14
    pulse = pulse + dl

    # rain / city hiss bed (periodic noise from random-phase spectra), far bells
    spec = np.fft.rfft(rng_.standard_normal(N))
    fq = np.fft.rfftfreq(N, 1.0 / SR)
    hiss_spec = spec / np.maximum(fq, 40.0) ** 0.5
    hiss = fft_filter(np.fft.irfft(hiss_spec, N), 1500, 9000, 2)
    hiss = hiss / np.max(np.abs(hiss)) * 0.07 * (0.6 + 0.4 * np.sin(2 * np.pi * 2 * tN))
    bells = np.zeros(N + tail)
    for t0, f in ((3.6, 880.0), (12.9, 1318.5), (21.8, 987.8), (27.3, 1174.7)):
        b = fm_bell(5.0, snap(f), 2.76, 1.6, 1.4, 0.5)
        idx = int(t0 * SR)
        bells[idx:idx + len(b)] += b[: len(bells) - idx] * 0.10
    bells = fold(bells)

    dry = pad + sub + pulse * 0.55 + hiss * 1.3 + bells * 1.3
    # circular reverb: multiply spectra at the full loop length so the tail wraps around the loop point
    ir = make_ir(3.6, predelay=0.03, damp=0.35, seed=77, early=False)
    irp = np.zeros(N)
    irp[: len(ir)] = ir
    wet = np.fft.irfft(np.fft.rfft(dry) * np.fft.rfft(irp), N)
    mix = dry * 0.62 + wet * 0.9
    mix = saturate(mix / np.max(np.abs(mix)), 1.1)
    return mix / np.max(np.abs(mix)) * PEAK


SOUNDS = {
    "shot": sfx_shot, "enemy_shot": sfx_enemy_shot, "hit": sfx_hit, "hurt": sfx_hurt, "boom": sfx_boom, "blink": sfx_blink,
    "link": sfx_link, "superpos": sfx_superpos, "pickup": sfx_pickup, "reload": sfx_reload, "core": sfx_core,
}


# ------------------------------------------------------------------ output
def write_wav(path, x, loop=False):
    """16-bit mono PCM WAV; `loop=True` appends a `smpl` chunk with a forward loop over the whole file (Godot picks it up)."""
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, 1, SR, SR * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    if len(pcm) % 2:
        chunks += b"\x00"
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0) + struct.pack("<IIIIII", 0, 0, 0, len(x) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)


def preview(path, items):
    """Waveform + spectrogram strips (one row per sound) for a quick visual check."""
    sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
    from make_textures import write_png  # noqa: E402
    rows = []
    for name, x in items:
        w = 1100
        env = np.array([np.max(np.abs(x[int(i * len(x) / w):max(int((i + 1) * len(x) / w), int(i * len(x) / w) + 1)])) for i in range(w)])
        wave = np.zeros((60, w))
        h = (env * 29).astype(int)
        for i in range(w):
            wave[30 - h[i]:30 + h[i] + 1, i] = 1.0
        hop = max(len(x) // w, 1)
        spec = np.zeros((60, w))
        win = np.hanning(1024)
        for i in range(w):
            seg = x[i * hop:i * hop + 1024]
            if len(seg) < 1024:
                break
            m = np.abs(np.fft.rfft(seg * win))[:512]
            m = np.log10(m + 1e-6)
            m = np.interp(np.linspace(0, 511, 60) ** 1.0, np.arange(512), m)
            spec[:, i] = (m[::-1] + 4) / 5
        rows.append(np.concatenate([wave * 255, np.clip(spec, 0, 1) * 255], axis=0))
    write_png(path, np.concatenate(rows, axis=0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "audio"))
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    only = [s for s in args.only.split(",") if s]
    items = []
    for name, fn in list(SOUNDS.items()) + [("music_ambient", music_ambient)]:
        if only and name not in only:
            continue
        t0 = time.time()
        x = fn()
        write_wav(os.path.join(args.out, name + ".wav"), x, loop=(name == "music_ambient"))
        items.append((name, x))
        print("%-14s %6.2f s  peak %.1f dBFS  rms %.1f dBFS  (%.1fs)" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(np.sqrt(np.mean(x ** 2))), time.time() - t0))
    if args.preview and items:
        preview(args.preview, items)
        print("preview", args.preview)


if __name__ == "__main__":
    sys.exit(main())
