#!/usr/bin/env python3
"""SUPERSEDED (music): the shipped music is composed as MIDI and rendered with a SoundFont by tools/music/compose.py (docs/AUDIO_SOURCES.md). This numpy generator would overwrite those
files with the old synthesised music, so do not run its music part any more (make_library.py --no-music); it stays for the beds, thunder and stings.

Ambience beds, thunder, sirens, the two stings and the adaptive music stems of Quantum Teleportar (numpy only).

Everything that loops is built from periodic signals (whole cycles per loop, random-phase spectra, circular reverbs/delays), so the seam is
inaudible; make_library.py's check_audio.py verifies the seam numerically on the committed OGG/WAV files.

Music: D minor, 96 BPM, 12 bars = 30 s loop, four chords of three bars (Dm9, Bbmaj7, Gm9, A7b9). Five stems, all stereo and all exactly the same length so
that Godot's AudioStreamSynchronized keeps them sample-locked: pad, pulse (FM arpeggio), bass, perc, lead. Sfx fades them by game state (explore, alert,
combat, driving...). The stems are balanced together (sum of all five peaks at MIX_PEAK_DB), so the loudest state never clips.
"""
import fnmatch
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, band, fft_filter, expenv, place, sine_sweep, saturate, make_ir, white  # noqa: E402
import make_library as ml  # noqa: E402
from make_library import R, db, conv, lp, tick, pn, pnoise, snap, wet  # noqa: E402

BPM = 96.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 12
LOOP = BARS * BAR                       # 30.0 s
N = int(round(LOOP * SR))
STEP = BEAT / 4.0                       # a sixteenth
SEG = 3 * BAR                           # one chord = 3 bars = 48 steps
MIX_PEAK_DB = -6.0
BED_SECONDS = 24.0


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def place_c(buf, sig, t0, gain=1.0):
    """Circular `place`: whatever runs past the end of the loop wraps around to its start (a tail across the seam)."""
    n = len(buf)
    i = int(round(t0 * SR)) % n
    k = min(len(sig), n - i)
    buf[i:i + k] += sig[:k] * gain
    rest = len(sig) - k
    while rest > 0:
        m = min(rest, n)
        buf[:m] += sig[len(sig) - rest:len(sig) - rest + m] * gain
        rest -= m


def circ_rev(x, rt60, mix, seed, predelay=0.02, damp=0.5):
    ir = make_ir(rt60, predelay, damp, seed, early=False)
    irp = np.zeros(len(x))
    k = min(len(ir), len(x))
    irp[:k] = ir[:k]
    y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irp), len(x))
    return x * (1.0 - mix * 0.5) + y * mix * 1.6


def pingpong(x, delay, fb, taps, lpf=2500.0):
    """Stereo dotted delay on a mono loop (circular): odd taps left, even taps right."""
    L = x.copy()
    R_ = x.copy()
    d = int(delay * SR)
    sig = x
    for k in range(1, taps + 1):
        sig = np.roll(lp(sig, lpf), d)
        (R_ if k % 2 == 1 else L)[:] += sig * fb ** k
    return L, R_


def kick_env(kicks, depth, tau=0.11):
    """Sidechain-style gain: 1 - depth right after every kick, recovering with time constant tau (circular)."""
    t = np.arange(N) / SR
    g = np.ones(N)
    for kt in kicks:
        dt = (t - kt) % LOOP
        g = np.minimum(g, 1.0 - depth * np.exp(-dt / tau))
    return g


CHORDS = [
    {"root": 38, "pad": [50, 53, 57, 60, 64], "arp": [50, 53, 57, 60, 62, 64]},      # Dm9
    {"root": 34, "pad": [46, 50, 53, 57, 62], "arp": [46, 50, 53, 57, 60, 62]},      # Bbmaj7
    {"root": 31, "pad": [43, 50, 53, 58, 62], "arp": [50, 53, 55, 58, 60, 62]},      # Gm9
    {"root": 33, "pad": [45, 52, 55, 58, 61], "arp": [49, 52, 55, 58, 61, 64]},      # A7b9
]


# ------------------------------------------------------------------ stems
def stem_pad(seed):
    """Warm, slowly moving chord bed: detuned stacked voices, a closing/opening low-pass, long circular reverb. Stereo from independent voice phases."""
    chans = []
    for ch in range(2):
        r = R(seed + 31 * ch)
        buf = np.zeros(N)
        for ci, c in enumerate(CHORDS):
            dur = SEG + 2.6
            n = int(dur * SR)
            t = np.arange(n) / SR
            env = np.minimum(t / 1.4, 1.0) * np.minimum(np.maximum(dur - t, 0) / 2.2, 1.0)
            for m in c["pad"]:
                f = mtof(m)
                voice = np.zeros(n)
                for det in (-6.5, 0.0, 6.0):
                    fd = f * 2.0 ** ((det + r.uniform(-1.5, 1.5)) / 1200.0)
                    ph = r.uniform(0, 6.28)
                    for k in range(1, 9):
                        voice += np.sin(2 * np.pi * fd * k * t + ph * k) / k ** 1.25
                place_c(buf, voice * env * (0.5 if m < 48 else 0.38), ci * SEG)
        buf = lp(buf, 2300, 2)
        w1 = 0.65 + 0.35 * np.sin(2 * np.pi * (3 / LOOP) * np.arange(N) / SR + ch * 1.7)
        buf = buf * w1
        chans.append(circ_rev(buf, 3.4, 0.7, 70 + ch, predelay=0.03, damp=0.35))
    out = np.stack(chans)
    return out / np.max(np.abs(out))


def stem_bass():
    out = np.zeros(N)
    pattern = [(0, 3), (3, 3), (6, 2), (8, 3), (11, 2), (14, 2)]                           # (step in bar, length in steps)
    for ci, c in enumerate(CHORDS):
        for b in range(3):
            for k, (s0, ln) in enumerate(pattern):
                t0 = ci * SEG + b * BAR + s0 * STEP
                m = c["root"] + (12 if (k == 4 and b % 2 == 1) else 0)
                f = mtof(m)
                dur = ln * STEP * 0.92
                n = int((dur + 0.14) * SR)                                                     # 7 time constants of release: nothing is cut off while audible
                t = np.arange(n) / SR
                env = np.minimum(t / 0.006, 1.0) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.02))
                s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t + 0.5)
                s = saturate(s * 1.0, 3.2)
                saw = sum(np.sin(2 * np.pi * f * k2 * t) / k2 for k2 in range(1, 9))
                s += 0.16 * lp(saw, 700, 2)
                place_c(out, s * env, t0, 0.9 if (k % 3 == 0) else 0.65)
    out = saturate(out / np.max(np.abs(out)), 1.4)
    return np.stack([out, out])


KICKS = [(ci * 3 + b) * BAR + s * STEP for ci in range(4) for b in range(3) for s in ((0, 10) if b % 2 == 0 else (0, 7, 10))]


def stem_pulse(seed):
    """Cyber-noir FM arpeggio, sixteenth notes, accents on the off-beats, dotted-eighth ping-pong echo."""
    r = R(seed)
    out = np.zeros(N)
    shape = [0, 2, 1, 3, 2, 4, 3, 5, 4, 2, 3, 1, 2, 0, 1, 3]
    accent = [1.0, 0.45, 0.6, 0.9, 0.5, 0.6, 1.0, 0.45, 0.7, 0.5, 0.95, 0.45, 0.8, 0.5, 0.65, 0.5]
    for ci, c in enumerate(CHORDS):
        notes = c["arp"]
        for st in range(48):
            if (st % 16) in (5, 13) and r.random() < 0.45:                                         # a few rests for air
                continue
            idx = shape[st % 16]
            m = notes[idx % len(notes)] + (12 if (st // 16) % 2 == 1 and idx > 2 else 12)
            f = mtof(m)
            dur = 1.0
            n = int(dur * SR)
            t = np.arange(n) / SR
            ind = 2.4 * np.exp(-t / 0.045) + 0.35
            s = np.sin(2 * np.pi * f * t + ind * np.sin(2 * np.pi * f * t)) * np.exp(-t / 0.13)
            place_c(out, s, ci * SEG + st * STEP, 0.5 * accent[st % 16])
    out = lp(out, 5200, 2)
    L, R_ = pingpong(out, STEP * 3, 0.5, 4, 3000.0)
    L, R_ = circ_rev(L, 1.4, 0.3, 80), circ_rev(R_, 1.4, 0.3, 81)
    s = np.stack([L, R_])
    return s


def stem_perc(seed):
    r = R(seed)
    out = np.zeros(N)
    snare_bus = np.zeros(N)
    nk, ns = int(0.9 * SR), int(0.6 * SR)
    sw, _ = sine_sweep(0.9, 170, 46)
    kick = np.zeros(nk)
    kick[:len(sw)] = sw * expenv(len(sw), 0.13)
    kick += band(white(nk, seed), 1500, 9000) * expenv(nk, 0.002) * 0.5
    kick = saturate(kick * 1.6, 2.0)
    sn = band(white(ns, seed + 1), 1300, 7500) * expenv(ns, 0.09) * 1.0
    sn += np.sin(2 * np.pi * 188 * np.arange(ns) / SR) * expenv(ns, 0.055) * 0.55
    sn += band(white(ns, seed + 2), 3500, 9000) * expenv(ns, 0.01) * 0.6
    hat_c = band(white(int(0.2 * SR), seed + 3), 6500, 16000) * expenv(int(0.2 * SR), 0.022)
    hat_o = band(white(int(0.5 * SR), seed + 4), 6000, 16000) * expenv(int(0.5 * SR), 0.16)
    for ci in range(4):
        for b in range(3):
            base = ci * SEG + b * BAR
            for s in ((0, 10) if b % 2 == 0 else (0, 7, 10)):
                place_c(out, kick, base + s * STEP, 1.0)
            for s in (4, 12):
                place_c(snare_bus, sn, base + s * STEP, 0.9)
            for s in range(0, 16, 2):
                place_c(out, hat_c, base + s * STEP + (STEP * 0.12 if s % 4 == 2 else 0.0), (0.38 if s % 4 == 0 else 0.26) * r.uniform(0.8, 1.0))
            for s in (7, 15):
                place_c(out, hat_c, base + s * STEP, 0.16 * r.uniform(0.7, 1.0))
            place_c(out, hat_o, base + 14 * STEP, 0.3)
            if b == 2:                                                                              # a tom fill at the end of every chord
                for k, f in enumerate((210.0, 170.0, 140.0, 110.0)):
                    ts, _ = sine_sweep(0.3, f * 1.4, f)
                    tom = ts * expenv(len(ts), 0.1) + band(white(len(ts), seed + 10 + k), 600, 3000)[:len(ts)] * expenv(len(ts), 0.01) * 0.3
                    place_c(out, saturate(tom * 1.4, 1.5), base + (12 + k) * STEP, 0.55)
    snare_bus = circ_rev(snare_bus, 0.9, 0.35, 90, predelay=0.012)
    mono = out + snare_bus
    mono = saturate(mono / np.max(np.abs(mono)), 1.25)
    L = mono + 0.0
    R_ = mono + 0.0
    return np.stack([L, R_])


def stem_lead(seed):
    """Sparse analog-ish lead: detuned FM-saw voice, delayed vibrato, call and response in the last two bars of every chord."""
    phrases = [
        [(18, 74, 3), (22, 77, 2), (25, 76, 4), (32, 72, 3), (36, 69, 9)],
        [(20, 77, 3), (24, 74, 2), (27, 72, 3), (32, 70, 4), (38, 74, 8)],
        [(18, 70, 3), (21, 74, 3), (26, 77, 4), (32, 79, 3), (36, 77, 2), (39, 74, 8)],
        [(16, 73, 4), (21, 76, 3), (25, 79, 3), (30, 74, 3), (34, 73, 6), (42, 69, 6)],
    ]
    out = np.zeros(N)
    for ci, ph in enumerate(phrases):
        for st, m, ln in ph:
            f = mtof(m)
            dur = ln * STEP
            n = int((dur + 0.9) * SR)
            t = np.arange(n) / SR
            vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.4 * t) * np.minimum(t / 0.35, 1.0)
            phs = 2 * np.pi * np.cumsum(f * vib) / SR
            v = np.zeros(n)
            for det in (-7.0, 0.0, 7.0):
                pd = phs * 2.0 ** (det / 1200.0)
                v += np.sin(pd + 1.1 * np.sin(pd) + 0.5 * np.sin(2 * pd))
            env = np.minimum(t / 0.03, 1.0) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.12)) * (0.8 + 0.2 * np.exp(-t / 0.2))
            place_c(out, v * env, ci * SEG + st * STEP, 0.4)
    out = lp(out, 3600, 2)
    L, R_ = pingpong(out, STEP * 3, 0.55, 5, 2600.0)
    return np.stack([circ_rev(L, 2.0, 0.4, 100), circ_rev(R_, 2.0, 0.4, 101)])


STEMS = ("pad", "pulse", "bass", "perc", "lead")
STEM_RMS_DB = {"pad": -21.0, "pulse": -25.0, "bass": -24.0, "perc": -24.0, "lead": -26.0}     # relative loudness of the stems before the joint peak scaling
SC_DEPTH = {"pad": 0.35, "pulse": 0.18, "bass": 0.7, "perc": 0.0, "lead": 0.12}


def build_stems():
    raw = {"pad": stem_pad(200), "pulse": stem_pulse(210), "bass": stem_bass(), "perc": stem_perc(220), "lead": stem_lead(230)}
    for k in raw:
        d = SC_DEPTH[k]
        if d > 0:
            raw[k] = raw[k] * kick_env(KICKS, d)[None, :]
        raw[k] = raw[k] / (np.sqrt(np.mean(raw[k] ** 2)) + 1e-9) * db(STEM_RMS_DB[k])
    total = sum(raw.values())
    gain = db(-19.5) / np.sqrt(np.mean(total ** 2))                                        # all five together: -19.5 dBFS RMS
    thr = db(-15.0)
    for k in raw:
        raw[k] = thr * np.tanh(raw[k] * gain / thr)                                         # each stem rounds its own rare peaks (the pad is spiky)
    total = sum(raw.values())
    scale = min(1.0, db(MIX_PEAK_DB) / np.max(np.abs(total)))
    out = {}
    for k in raw:
        out[k] = fft_filter_stereo(raw[k] * scale, 38.0)
    return out


def fft_filter_stereo(x, hp):
    return np.stack([fft_filter(c, lo=hp, order=4) for c in x])


# ------------------------------------------------------------------ ambience beds (24 s, periodic)
def soft_band(lo, hi, slope=0.0):
    return lambda f: (1.0 / np.sqrt(1.0 + (lo / f) ** 4)) / np.sqrt(1.0 + (f / hi) ** 4) / (f / 1000.0) ** slope


def gust(n, seed, cycles=(2, 3, 5), depth=0.25):
    t = np.arange(n) / SR
    r = R(seed)
    g = np.ones(n)
    for c in cycles:
        g += depth / len(cycles) * np.sin(2 * np.pi * (c / (n / SR)) * t + r.uniform(0, 6.28))
    return g


def rain_channel(kind, seed, n):
    r = R(seed)
    cfg = {
        "asphalt": dict(hiss=(1300, 9500, 0.5, 1.0), drops=(520, 1500, 6500, 0.004, 0.12), plinks=(7, 800, 2600, 0.012, 0.2), thud=None),
        "metal": dict(hiss=(2600, 11000, 0.2, 0.55), drops=(0, 0, 0, 0, 0), plinks=(0, 0, 0, 0, 0), thud=None, pings=(260, 900, 4800, 0.03, 0.09)),
        "awning": dict(hiss=(500, 6500, 0.7, 0.9), drops=(150, 900, 4500, 0.006, 0.1), plinks=(0, 0, 0, 0, 0), thud=(110, 220, 1400, 0.018, 0.2)),
    }[kind]
    lo, hi, slope, g = cfg["hiss"]
    out = pnoise(n, seed, soft_band(lo, hi, slope))
    out = out / np.std(out) * g * 0.3
    out *= gust(n, seed + 1)

    def scat(rate, flo, fhi, tau, gain, shape=None):
        buf = np.zeros(n)
        if rate <= 0:
            return buf
        pool = [tick(r, flo * r.uniform(0.8, 1.3), fhi * r.uniform(0.8, 1.2), tau * r.uniform(0.7, 1.4), 1.0) for _ in range(48)]
        cnt = int(rate * n / SR)
        for _ in range(cnt):
            tk = pool[r.integers(0, len(pool))]
            i = r.integers(0, n)
            k = min(len(tk), n - i)
            buf[i:i + k] += tk[:k] * gain * r.uniform(0.3, 1.0)
            if k < len(tk):
                buf[:len(tk) - k] += tk[k:] * gain
        return buf

    out += scat(*cfg["drops"])
    if cfg["thud"]:
        out += scat(*cfg["thud"])
    if cfg["plinks"][0] > 0:
        rate, flo, fhi, tau, gain = cfg["plinks"]
        for _ in range(int(rate * n / SR)):
            f = r.uniform(flo, fhi)
            m = int(0.08 * SR)
            tm = np.arange(m) / SR
            pl = np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 1.5, m)) / SR) * np.exp(-tm / tau) * gain * r.uniform(0.4, 1.0)
            i = r.integers(0, n)
            k = min(m, n - i)
            out[i:i + k] += pl[:k]
            if k < m:
                out[:m - k] += pl[k:]
    if "pings" in cfg:
        rate, flo, fhi, tau, gain = cfg["pings"]
        for _ in range(int(rate * n / SR)):
            f = r.uniform(flo, fhi)
            m = int(0.15 * SR)
            tm = np.arange(m) / SR
            pg = np.sin(2 * np.pi * f * tm) * np.exp(-tm / (tau * r.uniform(0.6, 1.6))) * gain * r.uniform(0.3, 1.0)
            i = r.integers(0, n)
            k = min(m, n - i)
            out[i:i + k] += pg[:k]
            if k < m:
                out[:m - k] += pg[k:]
    return out


def bed_rain(kind, base_seed):
    n = int(BED_SECONDS * SR)
    return np.stack([rain_channel(kind, base_seed + 7 * c, n) for c in range(2)])


def bed_traffic(seed):
    n = int(BED_SECONDS * SR)
    chans = []
    for c in range(2):
        r = R(seed + c)
        out = pnoise(n, seed + 3 * c, soft_band(45, 420, 0.0))
        out = out / np.std(out) * 0.25 * gust(n, seed + 5, (1, 2, 4), 0.3)
        hiss = pnoise(n, seed + 3 * c + 1, soft_band(1400, 5000, 0.3))
        out += hiss / np.std(hiss) * 0.05
        for _ in range(6):                                                                         # distant vehicles passing
            dur = r.uniform(3.5, 6.5)
            m = int(dur * SR)
            src = pnoise(m, int(r.integers(1, 10 ** 6)), soft_band(90, 1100, 0.2))
            src = ma.sweep_filter(src, 1400, 280, "lp") if False else src
            env = np.sin(np.pi * np.linspace(0, 1, m)) ** 2
            seg = src / np.std(src) * env * r.uniform(0.15, 0.4)
            i = r.integers(0, n)
            k = min(m, n - i)
            out[i:i + k] += seg[:k]
            if k < m:
                out[:m - k] += seg[k:]
        chans.append(out)
    return np.stack(chans)


def bed_wind(seed):
    n = int(BED_SECONDS * SR)
    chans = []
    for c in range(2):
        low = pnoise(n, seed + c, soft_band(110, 520, 0.0))
        low = low / np.std(low) * gust(n, seed + 2 + c, (1, 2, 3), 0.7)
        whistle = pnoise(n, seed + 9 + c, lambda f: np.exp(-0.5 * (np.log2(f / 1100.0) / 0.35) ** 2))
        whistle = whistle / np.std(whistle) * 0.25 * np.maximum(gust(n, seed + 7 + c, (2, 3, 5), 0.9) - 0.5, 0.0) ** 2
        chans.append(low * 0.6 + whistle)
    return np.stack(chans)


def bed_city_hum(seed):
    n = int(BED_SECONDS * SR)
    t = np.arange(n) / SR
    r = R(seed)
    out = np.zeros(n)
    for k, a in ((2, 1.0), (3, 0.55), (4, 0.7), (6, 0.35), (8, 0.25), (10, 0.12)):                  # a mains transformer: 100 Hz harmonics ...
        out += a * np.sin(2 * np.pi * snap(50.0 * k, BED_SECONDS) * t + r.uniform(0, 6.28)) * (0.8 + 0.2 * np.sin(2 * np.pi * (1 / BED_SECONDS) * t + k))
    out = saturate(out / np.max(np.abs(out)), 1.6) * 0.4
    hvac = pnoise(n, seed + 1, soft_band(130, 800, 0.0))
    out += hvac / np.std(hvac) * 0.12 * gust(n, seed + 2, (1, 3), 0.4)
    neon = np.sin(2 * np.pi * snap(2400.0, BED_SECONDS) * t) * 0.012 * (0.6 + 0.4 * np.sin(2 * np.pi * (6 / BED_SECONDS) * t))
    out += neon
    return np.stack([out, np.roll(out, int(0.011 * SR)) * 0.0 + out * 0.95 + hvac / np.std(hvac) * 0.015])


def thunder(seed):
    r = R(seed)
    d = 9.0
    n = int(d * SR)
    t = np.arange(n) / SR
    crack = ma.sweep_filter(white(n, seed) * 3.0, 6500, 350, "lp") * expenv(n, 0.35) * 1.4
    crack += band(white(n, seed + 1), 800, 9000) * expenv(n, 0.02) * 1.0
    rumble = pnoise(n, seed + 2, soft_band(35, 330, 0.0))
    rumble = rumble / np.std(rumble)
    env = np.zeros(n)
    for _ in range(int(r.integers(5, 9))):
        c = r.uniform(0.2, 5.0)
        env += np.exp(-0.5 * ((t - c) / r.uniform(0.25, 0.9)) ** 2) * r.uniform(0.3, 1.0) * np.exp(-c / 5.5)
    rumble = rumble * (env / np.max(env)) * 1.0 * np.minimum(t / 0.3, 1.0)
    out = crack * 0.6 + saturate(rumble * 1.2, 1.8) * 0.9
    out = wet(out, 3.0, mix=0.3, predelay=0.04, damp=0.6, seed=seed + 4, early=0.1)[:n]
    return ml.done(out, -12.0, 55.0, fout=1.5, max_len=d)


def siren(seed, kind):
    d = 2.6
    n = int(d * SR)
    t = np.arange(n) / SR
    if kind == 0:                                                                                   # two-tone, hi-lo
        f = np.where((t % 1.0) < 0.5, 660.0, 880.0)
        f = lp(f, 25.0, 2)
    else:                                                                                           # wail: a slow up-down sweep
        f = 600.0 + 700.0 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 1.3))
    ph = np.cumsum(f) / SR * 2 * np.pi
    x = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)
    x = saturate(x / np.max(np.abs(x)), 1.8)
    x = lp(x, 2800, 2) * np.minimum(t / 0.1, 1.0) * np.minimum((d - t) / 0.3, 1.0)
    out = wet(x, 1.8, mix=0.55, predelay=0.06, damp=0.7, seed=seed, early=0.2)
    return ml.done(out, -16.0, 350.0, fout=0.4, max_len=d + 0.4)


def sting_death(seed=300):
    d = 5.0
    n = int(d * SR)
    t = np.arange(n) / SR
    r = R(seed)
    out = np.zeros(n)
    s, _ = sine_sweep(1.6, 85, 26)
    out[:len(s)] += saturate(s * 1.5, 2.0) * expenv(len(s), 0.7)
    for k, m in enumerate((50, 53, 57, 60, 62)):                                                    # a Dm cluster whose pitch sags a semitone while a filter closes
        f = mtof(m) * 2.0 ** (-np.clip(t / 2.5, 0, 1) / 12.0)
        ph = np.cumsum(f) / SR * 2 * np.pi
        v = sum(np.sin(ph * kk + r.uniform(0, 6)) / kk for kk in range(1, 8))
        out += v * np.minimum(t / 0.05, 1.0) * np.exp(-t / 1.6) * 0.35
    out = ma.sweep_filter(out, 3500, 220, "lp", curve=0.7)
    for k, tt in enumerate((0.4, 1.35)):                                                            # two slowing heartbeats
        hb = ml.heartbeat()
        place(out, hb * 0.9, tt)
    out += ma.sweep_filter(white(n, seed + 1) * 3.0, 500, 9000, "lp") * (np.clip((t - 0.0) / 0.01, 0, 1) * expenv(n, 0.6)) * 0.35
    return ml.done(wet(out, 3.2, mix=0.35, predelay=0.03, damp=0.5, seed=seed), -10.0, 45.0, fout=1.2, max_len=d)


def sting_win(seed=310):
    d = 6.0
    n = int(d * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    notes = (62, 66, 69, 73, 76, 78, 81)                                                            # D Lydian rising
    for k, m in enumerate(notes):
        place(out, ma.fm_bell(3.5, mtof(m), 2.0, 1.1, 1.3, 0.35), 0.12 + k * 0.17, 0.5)
        place(out, ma.fm_bell(2.5, mtof(m + 12), 3.0, 0.9, 0.5, 0.2), 0.12 + k * 0.17, 0.18)
    for m in (50, 57, 62, 66, 69):
        f = mtof(m)
        v = sum(np.sin(2 * np.pi * f * kk * t + kk) / kk ** 1.3 for kk in range(1, 7))
        out += v * np.minimum(t / 0.8, 1.0) * np.exp(-np.maximum(t - 1.2, 0) / 1.8) * 0.12
    out += ml.shimmer(n, 587.33, seed, 8, 1.4) * np.exp(-t / 2.0) * np.minimum(t / 0.5, 1.0) * 0.4
    s, _ = sine_sweep(0.5, 140, 55)
    out[:len(s)] += s * expenv(len(s), 0.15) * 0.8
    return ml.done(wet(out, 3.0, mix=0.3, predelay=0.03, damp=0.3, seed=seed), -11.0, 60.0, fout=1.5, max_len=d)


# ------------------------------------------------------------------ output
def write_stereo_wav(path, x):
    pcm = np.clip(np.round(x.T * 32767.0), -32768, 32767).astype("<i2").tobytes()
    import struct
    fmt = struct.pack("<HHIIHH", 1, 2, SR, SR * 4, 4, 16)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(pcm)) + pcm
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)


def to_ogg(x, out_path, quality, tmp):
    """x: (channels, n) float. Encodes through ffmpeg/libvorbis."""
    wav = os.path.join(tmp, os.path.basename(out_path) + ".wav")
    if x.shape[0] == 1:
        ma.write_wav(wav, x[0])
    else:
        write_stereo_wav(wav, x)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", "-fflags", "+bitexact", out_path], check=True)
    os.remove(wav)


def bed_level(x, rms_db, peak_cap_db=-9.0):
    rms = np.sqrt(np.mean(x ** 2))
    g = db(rms_db) / (rms + 1e-12)
    g = min(g, db(peak_cap_db) / (np.max(np.abs(x)) + 1e-12))
    return x * g


def seam_ratio(x):
    """Jump across the loop seam relative to the steepest sample-to-sample step anywhere in the loop (at most about 1 = the seam is as smooth as the
    loop itself; a click would be many times that)."""
    d = np.abs(np.diff(x, axis=-1))
    seam = np.abs(x[..., 0] - x[..., -1])
    return float(np.max(seam / (np.max(d, axis=-1) + 1e-9)))


def build(out_dir, only):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    tmp = tempfile.mkdtemp(prefix="qt_audio_")
    try:
        beds = {
            "rain_asphalt": (lambda: bed_rain("asphalt", 400), -27.0),
            "rain_metal": (lambda: bed_rain("metal", 410), -28.0),
            "rain_awning": (lambda: bed_rain("awning", 420), -28.0),
            "traffic_far": (lambda: bed_traffic(430), -31.0),
            "wind": (lambda: bed_wind(440), -32.0),
            "city_hum": (lambda: bed_city_hum(450), -34.0),
        }
        for name, (fn, lvl) in beds.items():
            if want(name):
                x = bed_level(fft_filter_stereo(fn(), 60.0), lvl)
                to_ogg(x, os.path.join(out_dir, name + ".ogg"), 3, tmp)
                print("%-14s %5.1f s  peak %6.1f  rms %6.1f dBFS  seam %.2f" % (name, x.shape[1] / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(np.sqrt(np.mean(x ** 2))), seam_ratio(x)), flush=True)
        for i in range(3):
            name = "thunder_%d" % i
            if want(name):
                x = thunder(500 + 17 * i)
                to_ogg(x[None, :], os.path.join(out_dir, name + ".ogg"), 4, tmp)
                print("%-14s %5.1f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)
        for name, fn in (("siren", lambda: siren(600, 0)), ("siren_1", lambda: siren(610, 1)), ("sting_death", sting_death), ("sting_win", sting_win)):
            if want(name):
                x = fn()
                ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
                print("%-14s %5.1f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)
        if any(want("music_" + s) for s in STEMS):
            stems = build_stems()
            for s, x in stems.items():
                to_ogg(x, os.path.join(out_dir, "music_%s.ogg" % s), 5, tmp)
                print("music_%-8s %5.1f s  peak %6.1f  rms %6.1f dBFS  seam %.2f" % (s, x.shape[1] / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(np.sqrt(np.mean(x ** 2))), seam_ratio(x)), flush=True)
            tot = sum(stems.values())
            print("all five stems summed: peak %.1f dBFS, rms %.1f dBFS" % (20 * np.log10(np.max(np.abs(tot))), 20 * np.log10(np.sqrt(np.mean(tot ** 2)))))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ma.ROOT, "assets", "audio")
    os.makedirs(out, exist_ok=True)
    build(out, [])
