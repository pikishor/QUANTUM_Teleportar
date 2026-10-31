#!/usr/bin/env python3
"""The Quantum Teleportar sound library (numpy only, reproducible): everything the game plays except the 11 original effects and the
ambient loop of make_audio.py (those files are kept as they are and act as variant 0 of their groups).

Outputs, all into assets/audio/:
  * one-shots as 16-bit mono 44.1 kHz WAV (variants are <group>_0.wav .. <group>_N.wav; the engine picks one at random),
  * seamless loops (engine, tyres, drone hum, radio static, quantum drones, traffic) as WAV with a `smpl` loop chunk,
  * the ambience beds, thunder and the adaptive music stems as OGG Vorbis (make_music.py), through ffmpeg.

Usage: python3 make_library.py [--out DIR] [--only 'step_*,impact_*'] [--no-music] [--list]
Every sound has its own mix level (LEVEL) and high-pass corner (HP); tools/audio/check_audio.py verifies them on the committed files.
"""
import argparse
import fnmatch
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, band, fft_filter, expenv, fade, place, sine_sweep, saturate, make_ir, finalize, white, write_wav, highpass  # noqa: E402

ROOT = ma.ROOT
OUT_DEFAULT = os.path.join(ROOT, "assets", "audio")


def R(seed):
    return np.random.default_rng(seed)


def db(x):
    return 10 ** (x / 20.0)


def conv(x, ir):
    size = 1 << int(np.ceil(np.log2(len(x) + len(ir))))
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x) + len(ir) - 1]


def wet(x, rt60, mix=0.3, predelay=0.01, damp=0.5, seed=5, early=0.4):
    """Dry + convolution reverb tail (the output is longer than the input by the tail)."""
    ir = make_ir(rt60, predelay, damp, seed, early_gain=early)
    y = conv(x, ir)
    d = np.concatenate([x, np.zeros(len(y) - len(x))])
    return d * (1.0 - mix * 0.5) + y * mix * 1.6


def tick(rng, lo, hi, tau, gain=1.0):
    m = max(int(tau * 7 * SR), 64)
    return band(rng.standard_normal(m) / 3.0, lo, hi) * np.exp(-np.arange(m) / SR / tau) * gain


def scatter(n, rng, count, t0, t1, lo, hi, tau, gain=1.0, jitter=0.5, shape=1.0):
    """Many tiny noise ticks at random times in [t0, t1] (debris, droplets, crackle). shape > 1 packs them towards t0."""
    out = np.zeros(n)
    for _ in range(count):
        t = t0 + (t1 - t0) * rng.random() ** shape
        g = gain * (1.0 - jitter + jitter * rng.random())
        f = rng.uniform(0.8, 1.25)
        place(out, tick(rng, lo * f, hi * f, tau * rng.uniform(0.6, 1.5), g), t)
    return out


def modal(n, freqs, decays, amps, t0=0.0):
    t = np.arange(n) / SR - t0
    out = np.zeros(n)
    m = t >= 0
    for f, d, a in zip(freqs, decays, amps):
        out[m] += a * np.sin(2 * np.pi * f * t[m]) * np.exp(-t[m] / d)
    return out


def snap(f, dur):
    """The nearest frequency that completes a whole number of cycles in `dur` seconds (so a loop stays seamless)."""
    return max(1.0, round(f * dur)) / dur


def lp(x, fc, order=2):
    return fft_filter(x, None, fc, order)


def done(x, level_db, hp, fout=0.04, max_len=None, drive=1.1, trim_db=-58.0):
    return finalize(x, level_db, hp, fout=fout, max_len=max_len, drive=drive, trim_db=trim_db)


def done_loop(x, level_db, hp):
    """Loops: circular high-pass (no padding, so the seam survives) and a peak normalisation. No fades, no trim."""
    x = fft_filter(x, lo=hp, order=4) if hp else x
    x = x - np.mean(x)
    return x / (np.max(np.abs(x)) + 1e-9) * db(level_db)


def pn(n, seed, shape, rms):
    """Periodic noise scaled to an exact RMS."""
    x = pnoise(n, seed, shape)
    return x / (np.std(x) + 1e-12) * rms


def pnoise(n, seed, shape):
    """Periodic noise: a random-phase spectrum weighted by shape(f); exactly n samples and seamless when looped."""
    spec = np.fft.rfft(R(seed).standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(spec * shape(np.maximum(f, 1.0)), n)


# ------------------------------------------------------------------ footsteps (the hero is a digitigrade alien: a claw tick over the foot)
def step_asphalt(seed):
    r = R(seed)
    n = int(0.5 * SR)
    j = r.uniform(0.85, 1.25)
    out = np.zeros(n)
    out += band(white(n, seed), 2400 * j, 7000, 2) * expenv(n, 0.0025) * 0.55                    # claw tick
    out += band(white(n, seed + 1), 500 * j, 3200 * j, 2) * expenv(n, 0.014) * 1.0               # slap on the film of water
    splash = band(white(n, seed + 2), 3000, 10000) * expenv(n, 0.05, 0.008) * 0.45
    out += splash
    s, _ = sine_sweep(0.18, 190 * j, 85)
    out[: len(s)] += s * expenv(len(s), 0.035) * 0.55
    out += scatter(n, r, r.integers(2, 5), 0.04, 0.22, 2500, 8000, 0.004, 0.18)                  # droplets thrown off the heel
    out = wet(saturate(out, 1.2), 0.3, mix=0.12, seed=seed)
    return done(out, -22.0, 120.0, fout=0.1, max_len=0.5)


def step_metal(seed):
    r = R(seed)
    n = int(0.6 * SR)
    j = r.uniform(0.9, 1.12)
    out = band(white(n, seed), 1800, 9000) * expenv(n, 0.002) * 0.6
    out += band(white(n, seed + 1), 300, 2500) * expenv(n, 0.01) * 0.6
    base = np.array([410, 780, 1240, 1870, 2760]) * j * r.uniform(0.9, 1.1, 5)
    out += modal(n, base, [0.13, 0.1, 0.075, 0.05, 0.04], [0.5, 0.45, 0.3, 0.2, 0.12])
    s, _ = sine_sweep(0.12, 160, 90)
    out[: len(s)] += s * expenv(len(s), 0.03) * 0.5
    out = wet(saturate(out, 1.3), 0.5, mix=0.2, seed=seed)
    return done(out, -21.0, 140.0, fout=0.12, max_len=0.6)


def step_stairs(seed):
    """Steel grating stairs: heel, then the toe a moment later, with a rattle of the grating."""
    r = R(seed)
    n = int(0.7 * SR)
    out = np.zeros(n)
    for k, (t0, g) in enumerate(((0.0, 1.0), (r.uniform(0.055, 0.085), 0.55))):
        hit = band(white(n, seed + k), 700, 6000) * expenv(n, 0.006) * 0.8
        hit += modal(n, r.uniform(500, 900, 3) * [1, 1.9, 3.1], [0.09, 0.07, 0.05], [0.5, 0.35, 0.2])
        s, _ = sine_sweep(0.1, 175, 95)
        hit[: len(s)] += s * expenv(len(s), 0.03) * 0.6
        place(out, hit[: int(0.4 * SR)], t0, g)
    rattle = band(white(n, seed + 7), 1000, 5200) * expenv(n, 0.07, 0.03) * (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(34, 52) * np.arange(n) / SR)) * 0.3
    out += rattle
    out = wet(saturate(out, 1.3), 0.6, mix=0.2, seed=seed)
    return done(out, -20.0, 120.0, fout=0.15, max_len=0.7)


def land(seed, surface):
    f = step_metal if surface == "metal" else step_asphalt
    x = f(seed + 900)
    s, _ = sine_sweep(0.22, 140, 55)
    pad = np.zeros(len(x))
    k = min(len(s), len(pad))
    pad[:k] = s[:k] * expenv(k, 0.06) * 0.6
    return done(x / np.max(np.abs(x)) * 0.9 + highpass(pad, 70.0), -17.0, 90.0, fout=0.12, max_len=0.6)


# ------------------------------------------------------------------ weapons (layers: crack, body, mechanical, tail)
def gun_layers(seed, kind="rifle"):
    r = R(seed)
    n = int(1.4 * SR)
    j = r.uniform(0.9, 1.12)
    L = {}
    crack = band(white(n, seed), 1500 * j, 11000, 2) * expenv(n, 0.0018) * 3.0
    crack += band(white(n, seed + 1), 400, 3500) * expenv(n, 0.006) * 2.2
    crack += band(white(n, seed + 2), 3000, 14000) * expenv(n, 0.0008) * 1.5
    L["crack"] = crack
    s, _ = sine_sweep(0.4, 215 * j, 82)
    body = band(white(n, seed + 3), 140, 1800) * expenv(n, 0.04) * 1.2
    body += band(white(n, seed + 4), 250, 2600) * expenv(n, 0.02) * 1.4
    body[: len(s)] += s * expenv(len(s), 0.05) * 0.32
    L["body"] = body
    mech = band(white(n, seed + 5), 2500, 7500) * expenv(n, 0.005, 0.07) * 0.5
    mech += modal(n, [1150 * j, 2310 * j, 3600], [0.03, 0.02, 0.012], [0.25, 0.18, 0.1], 0.072)
    L["mech"] = mech
    if kind == "enemy":                                   # Vael bio-plasma: a falling zap instead of a muzzle blast
        z, _ = sine_sweep(0.28, 2600 * j, 260)
        zz = np.zeros(n)
        zz[: len(z)] = np.sin(2 * np.pi * np.cumsum(2600 * j * (260 / (2600 * j)) ** (np.arange(len(z)) / len(z)) / SR) + 3.0 * np.sin(2 * np.pi * 90 * np.arange(len(z)) / SR)) * expenv(len(z), 0.08)
        L["crack"] = band(white(n, seed), 900, 9000) * expenv(n, 0.004) * 1.6 + zz * 1.6
        L["body"] = body * 0.55
        L["mech"] = mech * 0.2
    return L, n


def gun(seed, kind="rifle", with_layers=False):
    L, n = gun_layers(seed, kind)
    dry = saturate(L["crack"] + L["body"] + L["mech"], 1.4)
    tail_src = L["crack"] * 0.8 + L["body"]
    ir = make_ir(1.0 if kind == "rifle" else 0.8, 0.014, 0.5, seed + 30, early_gain=0.3)
    tail = conv(lp(tail_src, 5200), ir)[: n + len(ir) - 1]
    comp = np.zeros(len(tail))
    comp[: len(dry)] += dry
    for k, (d, g) in enumerate(((0.19, 0.2), (0.4, 0.09))):                       # slap-back from the buildings
        place(comp, lp(dry, 2200), d, g)
    comp += tail * 0.22
    lvl = -12.0 if kind == "rifle" else -13.0
    out = done(comp, lvl, 60.0 if kind == "rifle" else 90.0, fout=0.12, max_len=1.0 if kind == "rifle" else 0.9)
    if with_layers:
        return out, done(tail * 4.0 + np.pad(lp(L["body"], 900) * 0.2, (0, len(tail) - n)), -20.0, 80.0, fout=0.3, max_len=1.8), \
            done(L["mech"] * 2.0, -22.0, 400.0, fout=0.05, max_len=0.3)
    return out


def shot_far(seed, kind="rifle"):
    """A shot heard from far away: the crack is gone, the body is dull, the buildings answer late."""
    L, n = gun_layers(seed, kind)
    src = lp(L["body"] + L["crack"] * 0.2, 1500, 3)
    ir = make_ir(1.8, 0.05, 0.8, seed + 8, early_gain=0.5)
    y = conv(src, ir)
    out = np.zeros(len(y) + int(0.12 * SR))
    place(out, y, 0.12, 1.0)
    return done(out, -19.0, 100.0, fout=0.5, max_len=1.8)


def dry_fire(seed):
    n = int(0.25 * SR)
    out = band(white(n, seed), 2500, 8000) * expenv(n, 0.003) * 0.8
    out += modal(n, [820, 1640, 2900], [0.025, 0.018, 0.01], [0.5, 0.3, 0.2], 0.0)
    out += modal(n, [310], [0.05], [0.35], 0.012)
    return done(wet(out, 0.2, mix=0.12, seed=seed), -17.0, 200.0, fout=0.06, max_len=0.25)


def _click(n, seed, body, tau, lo, hi, g=1.0, ring=None, t0=0.0):
    out = np.zeros(n)
    sig = band(white(n, seed), lo, hi) * expenv(n, tau * 0.35, t0) * g
    sig += modal(n, [body], [tau], [0.45 * g], t0)
    if ring:
        sig += modal(n, [f for f, _ in ring], [tau * 1.6] * len(ring), [a * g for _, a in ring], t0)
    return out + sig


def reload_full(seed):
    r = R(seed)
    j = r.uniform(0.92, 1.1)
    n = int(1.7 * SR)
    out = np.zeros(n)
    out += _click(n, seed, 900, 0.01, 2000, 8000, 0.7, [(2400 * j, 0.2)], 0.04)
    out += band(white(n, seed + 1), 1200, 5000) * np.interp(np.arange(n) / SR, [0.17, 0.2, 0.26, 0.27], [0, 1, 1, 0]) * 0.28
    out += _click(n, seed + 2, 180, 0.03, 600, 5000, 0.8, None, 0.27 + r.uniform(0, 0.03))
    out += band(white(n, seed + 3), 800, 4500) * np.interp(np.arange(n) / SR, [0.58, 0.62, 0.7, 0.71], [0, 1, 1, 0]) * 0.25
    out += _click(n, seed + 4, 140, 0.04, 1200, 9000, 1.3, [(1180 * j, 0.35), (2330 * j, 0.22)], 0.74)
    rack = sweep_rack(n, seed + 5, 1.02)
    out += rack
    out += _click(n, seed + 6, 120, 0.05, 1500, 9000, 1.6, [(1500 * j, 0.3), (3100 * j, 0.18)], 1.13)
    return done(wet(saturate(out, 1.2), 0.3, mix=0.2, seed=seed), -14.0, 90.0, fout=0.12, max_len=1.7)


def sweep_rack(n, seed, t0):
    m = int(0.1 * SR)
    s = ma.sweep_filter(band(white(m, seed), 400, 9000), 600, 5000, "lp") * np.hanning(m) * 0.5
    out = np.zeros(n)
    place(out, s, t0)
    return out


# ------------------------------------------------------------------ impacts, ricochets, whizz-bys
def impact_concrete(seed):
    r = R(seed)
    n = int(0.6 * SR)
    out = band(white(n, seed), 800, 5500) * expenv(n, 0.016) * 1.0
    out += band(white(n, seed + 1), 200, 900) * expenv(n, 0.03) * 0.8
    s, _ = sine_sweep(0.12, r.uniform(150, 230), 70)
    out[: len(s)] += s * expenv(len(s), 0.025) * 0.7
    out += scatter(n, r, r.integers(6, 12), 0.03, 0.4, 2500, 7000, 0.005, 0.28, shape=1.6)       # chips
    out += band(white(n, seed + 2), 4000, 9000) * expenv(n, 0.1, 0.01) * 0.12                    # dust
    return done(wet(saturate(out, 1.3), 0.3, mix=0.15, seed=seed), -17.0, 90.0, fout=0.15, max_len=0.6)


def impact_metal(seed):
    r = R(seed)
    n = int(0.9 * SR)
    j = r.uniform(0.85, 1.3)
    out = band(white(n, seed), 2000, 10000) * expenv(n, 0.002) * 0.9
    out += modal(n, np.array([720, 1330, 2040, 2980, 4210]) * j, [0.28, 0.2, 0.15, 0.1, 0.07], [0.55, 0.45, 0.35, 0.25, 0.15])
    out += band(white(n, seed + 1), 300, 1800) * expenv(n, 0.008) * 0.6
    out += scatter(n, r, 3, 0.02, 0.2, 4000, 9000, 0.003, 0.2)                                   # sparks
    return done(wet(saturate(out, 1.4), 0.5, mix=0.22, seed=seed), -17.0, 150.0, fout=0.25, max_len=0.9)


def impact_glass(seed):
    r = R(seed)
    n = int(1.0 * SR)
    out = band(white(n, seed), 2500, 12000) * expenv(n, 0.004) * 1.0
    out += band(white(n, seed + 1), 600, 3000) * expenv(n, 0.012) * 0.5
    for _ in range(r.integers(16, 26)):                                                           # shards: tiny bright pings falling about
        t = 0.015 + 0.55 * r.random() ** 1.7
        f = r.uniform(3200, 9500)
        m = int(0.16 * SR)
        ping = np.sin(2 * np.pi * f * np.arange(m) / SR) * np.exp(-np.arange(m) / SR / r.uniform(0.012, 0.05)) * r.uniform(0.08, 0.3)
        place(out, ping, t)
    out += scatter(n, r, 8, 0.03, 0.5, 4500, 11000, 0.004, 0.18, shape=1.4)
    return done(wet(out, 0.4, mix=0.18, seed=seed), -17.0, 500.0, fout=0.3, max_len=1.0)


def impact_flesh(seed):
    """Alien flesh and ichor: a heavy wet thump, a squelch and a few bubbles."""
    r = R(seed)
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    s, _ = sine_sweep(0.16, r.uniform(140, 190), 62)
    out = np.zeros(n)
    out[: len(s)] += s * expenv(len(s), 0.04) * 0.9
    out += band(white(n, seed), 250, 1600) * expenv(n, 0.05) * (0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(28, 55) * t)) * 1.0
    out += band(white(n, seed + 1), 1500, 6000) * expenv(n, 0.01) * 0.5
    for _ in range(r.integers(3, 7)):                                                             # bubbles
        tb = 0.06 + 0.4 * r.random()
        m = int(0.05 * SR)
        f0 = r.uniform(300, 900)
        sw = np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f0 * 2.2, m)) / SR) * np.exp(-np.arange(m) / SR / 0.012) * r.uniform(0.08, 0.2)
        place(out, sw, tb)
    return done(wet(saturate(out, 1.3), 0.35, mix=0.12, seed=seed), -16.0, 90.0, fout=0.2, max_len=0.7)


def impact_asphalt(seed):
    r = R(seed)
    n = int(0.5 * SR)
    out = band(white(n, seed), 1000, 6500) * expenv(n, 0.03) * 0.9
    out += band(white(n, seed + 1), 3500, 11000) * expenv(n, 0.07, 0.006) * 0.4
    s, _ = sine_sweep(0.1, 170, 80)
    out[: len(s)] += s * expenv(len(s), 0.025) * 0.6
    out += scatter(n, r, r.integers(4, 8), 0.04, 0.3, 2800, 8000, 0.004, 0.2, shape=1.3)
    return done(wet(out, 0.25, mix=0.1, seed=seed), -18.0, 110.0, fout=0.15, max_len=0.5)


def ricochet(seed):
    r = R(seed)
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f0, f1 = r.uniform(2600, 3600), r.uniform(900, 1500)
    f = f0 * (f1 / f0) ** np.clip(t / 0.45, 0, 1)
    ph = 2 * np.pi * np.cumsum(f) / SR
    out = np.sin(ph + 1.8 * np.sin(ph * 0.5)) * np.exp(-t / 0.13) * 0.8
    out += band(white(n, seed), 2200, 9000) * expenv(n, 0.012) * 0.7                              # the strike
    out += band(white(n, seed + 1), 1400, 6000) * expenv(n, 0.2) * 0.08
    return done(wet(out, 0.5, mix=0.2, seed=seed), -18.0, 400.0, fout=0.25, max_len=0.6)


def whizz(seed):
    """A bullet passing close: band-passed noise whose centre falls (the Doppler of a supersonic pass) over a bell-shaped envelope."""
    r = R(seed)
    d = r.uniform(0.2, 0.3)
    n = int(d * SR)
    x = ma.sweep_filter(white(n, seed) * 3.0, r.uniform(5500, 7500), r.uniform(1300, 2000), "lp", order=3)
    x = highpass(x, 900.0, order=2)
    env = np.sin(np.pi * np.linspace(0, 1, n) ** 0.8) ** 2
    return done(wet(x * env, 0.25, mix=0.12, seed=seed), -20.0, 900.0, fout=0.05, max_len=0.35)


# ------------------------------------------------------------------ explosions
def explosion(seed, big=True):
    r = R(seed)
    d = 3.6 if big else 2.0
    n = int(d * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    s, _ = sine_sweep(0.9 if big else 0.5, r.uniform(90, 110) if big else 130, 34 if big else 48)
    out[: len(s)] += s * expenv(len(s), 0.32 if big else 0.16) * 1.2                              # the thump
    out += band(white(n, seed), 50, 1200) * expenv(n, 0.35 if big else 0.18) * 1.6               # blast
    out += band(white(n, seed + 1), 800, 6000) * expenv(n, 0.06) * 1.2                           # the crack of the fireball
    cr = np.zeros(n)                                                                              # crackle: fire popping, thinning out
    for _ in range(int(150 if big else 70)):
        tt = 0.05 + (1.8 if big else 1.0) * r.random() ** 2.2
        place(cr, tick(r, 1200, 9000, r.uniform(0.002, 0.008), r.uniform(0.15, 0.6)), tt)
    out += cr * 0.7
    deb = np.zeros(n)                                                                             # debris rain: heavier pieces early, grit later
    for _ in range(int(120 if big else 50)):
        tt = (0.5 if big else 0.3) + (2.6 if big else 1.3) * r.random() ** 1.4
        lo = r.uniform(900, 2500)
        place(deb, tick(r, lo, lo * 3.4, r.uniform(0.004, 0.02), r.uniform(0.1, 0.5) * (1.2 - 0.6 * tt / d)), tt)
    out += deb * 0.55
    out = saturate(out, 1.5)
    out = wet(out, 2.2 if big else 1.2, mix=0.3, predelay=0.03, damp=0.6, seed=seed, early=0.2)
    return done(out, -10.0, 42.0, fout=0.8, max_len=d + 0.4, drive=1.2)


def distant_boom(seed):
    r = R(seed)
    n = int(3.5 * SR)
    src = band(white(n, seed), 40, 500) * expenv(n, 0.3) * 1.5
    s, _ = sine_sweep(0.6, 80, 40)
    src[: len(s)] += s * expenv(len(s), 0.2)
    out = lp(wet(src, 2.5, mix=0.5, predelay=0.1, damp=0.8, seed=seed), 700, 3)
    return done(saturate(out, 1.4), -17.0, 55.0, fout=1.0, max_len=3.5)


def distant_gunfire(seed):
    r = R(seed)
    n = int(2.8 * SR)
    out = np.zeros(n)
    t = r.uniform(0.0, 0.2)
    while t < 2.2:
        for _ in range(r.integers(2, 6)):
            place(out, tick(r, 600, 3000, 0.012, r.uniform(0.5, 1.0)), t)
            t += r.uniform(0.09, 0.14)
        t += r.uniform(0.2, 0.7)
    out = lp(wet(out, 1.6, mix=0.5, predelay=0.08, damp=0.8, seed=seed), 1800, 3)
    return done(out, -22.0, 200.0, fout=0.6, max_len=2.8)


# ------------------------------------------------------------------ formant synthesis for alien voices
def formant_filter(x, tracks, frame=1024):
    """tracks: list of (f_start, f_end, width_in_octaves, gain). Time-varying spectral envelope by overlap-add FFT blocks."""
    n = len(x)
    hop = frame // 2
    win = np.hanning(frame)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    out = np.zeros_like(pad)
    f = np.maximum(np.fft.rfftfreq(frame, 1.0 / SR), 20.0)
    for b in range((len(pad) - frame) // hop):
        i = b * hop
        u = np.clip((i - frame) / max(n, 1), 0.0, 1.0)
        g = np.full_like(f, 0.04)
        for f0, f1, w, gain in tracks:
            fc = f0 * (f1 / f0) ** u
            g += gain * np.exp(-0.5 * (np.log2(f / fc) / w) ** 2)
        out[i:i + frame] += np.fft.irfft(np.fft.rfft(pad[i:i + frame] * win) * g, frame)
    return out[frame:frame + n]


def glottal(f0, rough, rough_hz, noise, seed, jitter=0.012, tilt=0.9):
    n = len(f0)
    r = R(seed)
    t = np.arange(n) / SR
    jit = lp(r.standard_normal(n), 45.0, 2)
    jit = jit / (np.std(jit) + 1e-9) * jitter
    ph = np.cumsum(f0 * (1.0 + jit)) / SR
    nh = int(max(4, min(36, 9500.0 / max(np.max(f0), 1.0))))
    x = np.zeros(n)
    for k in range(1, nh + 1):
        x += np.sin(2 * np.pi * k * ph + r.uniform(0, 6.28)) / k ** tilt
    rough = rough if np.ndim(rough) else np.full(n, rough)
    x *= (1.0 - rough) + rough * (0.5 + 0.5 * np.sin(2 * np.pi * rough_hz * t + r.uniform(0, 6.28)))
    return x + noise * white(n, seed + 99) * 3.0


def chatter(n, seed, t0, t1, hz, lo=1800, hi=6500, g=1.0):
    """Mandible clicking: a train of clicks at `hz` between t0 and t1."""
    r = R(seed)
    out = np.zeros(n)
    t = t0
    while t < t1:
        place(out, tick(r, lo, hi, 0.0035, g * r.uniform(0.6, 1.0)), t)
        t += (1.0 / hz) * r.uniform(0.8, 1.2)
    return out


def trooper_voice(kind, seed):
    r = R(seed)
    j = r.uniform(0.92, 1.12)
    if kind == "alert":
        d = r.uniform(0.7, 0.85)
        n = int(d * SR)
        u = np.linspace(0, 1, n)
        f0 = (620 * j) * (1500 * j / (620 * j)) ** (u ** 0.8) * (1 + 0.03 * np.sin(2 * np.pi * 7 * u * d))
        x = glottal(f0, 0.35, 55, 0.1, seed)
        x = formant_filter(x, [(900, 1300, 0.28, 1.0), (2300 * j, 3100, 0.25, 0.9), (3900, 4300, 0.25, 0.6)])
        env = np.minimum(u / 0.05, 1.0) * np.where(u > 0.65, np.exp(-(u - 0.65) * 7.0), 1.0)
        x = x * env + chatter(n, seed + 3, d * 0.62, d * 0.97, r.uniform(26, 38), g=0.7) * 0.8
    elif kind == "attack":
        d = r.uniform(0.5, 0.62)
        n = int(d * SR)
        u = np.linspace(0, 1, n)
        f0 = (185 * j) + 90 * u * j
        x = glottal(f0, 0.75, r.uniform(55, 68), 0.4, seed, jitter=0.03)
        x = formant_filter(x, [(520, 760, 0.3, 1.0), (1300, 1550 * j, 0.3, 0.9), (2700, 3000, 0.3, 0.5)])
        x += band(white(n, seed + 4), 1800, 7500) * (0.15 + 0.5 * np.exp(-u * 3.0))
        env = np.minimum(u / 0.012, 1.0) * np.exp(-np.maximum(u - 0.3, 0) * 3.8)
        x = saturate(x * env, 1.8)
    elif kind == "pain":
        d = r.uniform(0.36, 0.46)
        n = int(d * SR)
        u = np.linspace(0, 1, n)
        f0 = (950 * j) * (400 / (950 * j)) ** u * (1 + 0.05 * np.sin(2 * np.pi * 9 * u * d))
        x = glottal(f0, 0.2, 48, 0.08, seed)
        x = formant_filter(x, [(1150, 720, 0.3, 1.0), (2700, 2000, 0.28, 0.8), (3800, 3300, 0.3, 0.4)])
        env = np.minimum(u / 0.02, 1.0) * np.exp(-np.maximum(u - 0.4, 0) * 4.0)
        x = x * env
    else:  # death
        d = r.uniform(1.3, 1.6)
        n = int(d * SR)
        u = np.linspace(0, 1, n)
        f0 = (540 * j) * (85 / (540 * j)) ** (u ** 0.7)
        f0 = f0 * (1 + 0.03 * np.sin(2 * np.pi * 6 * u * d)) * (1 + 0.06 * (lp(r.standard_normal(n), 14.0) / 0.3) * u)
        x = glottal(f0, 0.2 + 0.6 * u, 52, 0.12 + 0.2 * u, seed, jitter=0.02 + 0.03 * u[0])
        x = formant_filter(x, [(1050, 380, 0.3, 1.0), (2300, 900, 0.28, 0.8), (3600, 1800, 0.3, 0.4)])
        gurgle = 0.55 + 0.45 * np.sin(2 * np.pi * 13 * np.arange(n) / SR)
        x = x * np.where(u > 0.5, gurgle ** (u - 0.4) * 1.0, 1.0)
        env = np.minimum(u / 0.03, 1.0) * np.exp(-np.maximum(u - 0.25, 0) * 3.2)
        x = x * env + chatter(n, seed + 5, 0.15, d * 0.7, 18, g=0.4) * 0.6
    x = saturate(x / (np.max(np.abs(x)) + 1e-9), 1.6)
    x = wet(x, 0.5, mix=0.2, seed=seed)
    return done(x, -15.0, 150.0, fout=0.1, max_len=2.0)


def hero_voice(kind, seed):
    """Kestrel's own grunts: lower, closer to a human effort, with a faint alien overtone."""
    r = R(seed)
    j = r.uniform(0.93, 1.08)
    if kind == "pain":
        d, f_a, f_b = 0.3, 210 * j, 120 * j
    elif kind == "effort":
        d, f_a, f_b = 0.22, 150 * j, 190 * j
    else:
        d, f_a, f_b = 1.1, 190 * j, 70
    n = int(d * SR)
    u = np.linspace(0, 1, n)
    f0 = f_a * (f_b / f_a) ** u
    x = glottal(f0, 0.12, 40, 0.25 if kind != "death" else 0.35, seed)
    x = formant_filter(x, [(700, 500 if kind == "death" else 850, 0.3, 1.0), (1500, 1100, 0.3, 0.8), (2600, 2200, 0.3, 0.4)])
    env = np.minimum(u / 0.03, 1.0) * np.exp(-np.maximum(u - 0.25, 0) * (4.0 if kind != "death" else 2.6))
    x = saturate(x * env / (np.max(np.abs(x * env)) + 1e-9), 1.4)
    return done(wet(x, 0.3, mix=0.12, seed=seed), -15.0, 110.0, fout=0.1, max_len=1.2)


# ------------------------------------------------------------------ drones
def drone_hum():
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = R(31)
    out = np.zeros(n)
    for k, (f, a) in enumerate(((snap(92, dur), 0.9), (snap(184.5, dur), 0.8), (snap(277, dur), 0.5), (snap(371, dur), 0.35), (snap(556, dur), 0.2), (snap(97, dur), 0.5))):
        out += a * np.sin(2 * np.pi * f * t + r.uniform(0, 6.28))
    out *= 0.75 + 0.25 * np.sin(2 * np.pi * 7 * t)                                              # servo flutter (integer cycles)
    out += pn(n, 32, lambda f: ((f > 400) & (f < 3000)).astype(float) / np.sqrt(f), 0.12 * np.std(out))
    out = saturate(out / np.max(np.abs(out)), 1.8)
    return done_loop(out, -18.0, 90.0)


def drone_charge():
    n = int(1.1 * SR)
    t = np.arange(n) / SR
    u = t / 1.1
    f = 180 * (2600 / 180) ** (u ** 1.5)
    ph = np.cumsum(f) / SR * 2 * np.pi
    out = np.sin(ph + 2.0 * u * np.sin(ph * 2.0)) * (0.25 + 0.75 * u)
    out += band(white(n, 41), 1500, 9000) * (u ** 2) * 0.3
    out *= np.minimum(u / 0.04, 1.0) * np.where(u > 0.93, (1 - u) / 0.07, 1.0)
    return done(wet(saturate(out, 1.3), 0.4, mix=0.15, seed=42), -17.0, 120.0, fout=0.04, max_len=1.1)


def drone_alert():
    n = int(0.6 * SR)
    out = np.zeros(n)
    for k, f in enumerate((1400, 2100, 1750)):
        m = int(0.1 * SR)
        tt = np.arange(m) / SR
        b = np.sign(np.sin(2 * np.pi * f * tt)) * 0.3 + np.sin(2 * np.pi * f * tt + 3 * np.sin(2 * np.pi * 70 * tt))
        place(out, b * np.minimum(tt / 0.004, 1.0) * np.exp(-tt / 0.08), k * 0.14)
    return done(wet(out, 0.4, mix=0.15, seed=44), -17.0, 500.0, fout=0.1, max_len=0.6)


def drone_death():
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    u = t / 1.4
    f = 900 * (60 / 900) ** (u ** 0.6)
    ph = np.cumsum(f) / SR * 2 * np.pi
    out = np.sin(ph + 3.5 * np.sin(ph * 0.5)) * np.exp(-u * 3.5)
    out += scatter(n, R(46), 60, 0.0, 1.0, 1500, 8000, 0.004, 0.4, shape=1.2)
    out += band(white(n, 47), 200, 3000) * expenv(n, 0.25) * 0.5
    return done(wet(saturate(out, 1.5), 0.8, mix=0.2, seed=45), -13.0, 80.0, fout=0.3, max_len=1.4)


# ------------------------------------------------------------------ quantum: a shimmering tonal signature (a pentatonic cluster that beats and sparkles)
PENTA = [1.0, 9 / 8, 5 / 4, 3 / 2, 5 / 3, 2.0, 9 / 4, 5 / 2, 3.0]


def shimmer(n, root, seed, notes=7, sparkle=1.0):
    r = R(seed)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for i in range(notes):
        f = root * PENTA[r.integers(0, len(PENTA))] * (1 + 0.003 * r.standard_normal())
        for d in (-1.3, 1.1):
            out += np.sin(2 * np.pi * (f + d * r.uniform(0.6, 2.4)) * t + r.uniform(0, 6.28)) * 0.25 * (0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(2, 7) * t + r.uniform(0, 6.28)))
    for _ in range(int(14 * sparkle)):
        tt = r.uniform(0, n / SR * 0.85)
        f = root * PENTA[r.integers(3, len(PENTA))] * r.choice([2, 4])
        m = int(0.3 * SR)
        tm = np.arange(m) / SR
        place(out, np.sin(2 * np.pi * f * tm + 1.6 * np.sin(2 * np.pi * f * 2.76 * tm)) * np.exp(-tm / 0.07) * r.uniform(0.05, 0.16), tt)
    return out


def blink_sfx(seed):
    """Out: a swelling pull and a sub-bass drop; in: a bright burst, then the shimmering tail of the Bell pair settling."""
    r = R(seed)
    root = r.choice([293.66, 329.63, 349.23])
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    pull = shimmer(int(0.4 * SR), root * 0.5, seed, 6, 0.4)
    pull *= np.linspace(0, 1, len(pull)) ** 2
    place(out, pull, 0.0)
    s = ma.sweep_filter(white(int(0.4 * SR), seed + 1) * 3, 300, 7000, "lp") * np.linspace(0, 1, int(0.4 * SR)) ** 2.5 * 0.5
    place(out, s, 0.0)
    arrive = shimmer(int(1.2 * SR), root, seed + 2, 8, 1.2) * np.exp(-np.arange(int(1.2 * SR)) / SR / 0.55)
    place(out, arrive, 0.4)
    place(out, band(white(int(0.25 * SR), seed + 3), 1500, 11000) * expenv(int(0.25 * SR), 0.03) * 1.4, 0.4)
    ss, _ = sine_sweep(0.3, 180, 70)
    place(out, ss * expenv(len(ss), 0.07) * 0.9, 0.4)
    return done(wet(saturate(out, 1.1), 1.2, mix=0.3, damp=0.3, seed=seed), -12.0, 80.0, fout=0.4, max_len=1.8)


def link_sfx(seed):
    r = R(seed)
    root = r.choice([440.0, 392.0, 523.25])
    n = int(1.4 * SR)
    out = np.zeros(n)
    for k in range(4):                                                                              # two entangled pings answering each other
        f = root * PENTA[(k * 2) % 5] * (1.0 if k % 2 == 0 else 1.5)
        m = int(0.7 * SR)
        tm = np.arange(m) / SR
        place(out, np.sin(2 * np.pi * f * tm + 1.2 * np.sin(2 * np.pi * f * 2.0 * tm) * np.exp(-tm / 0.1)) * np.exp(-tm / 0.18) * 0.7, k * 0.11)
    out += shimmer(n, root * 0.5, seed, 5, 0.6) * np.exp(-np.arange(n) / SR / 0.6) * 0.5
    return done(wet(out, 0.9, mix=0.3, damp=0.3, seed=seed), -13.0, 90.0, fout=0.3, max_len=1.4)


def superpos_enter(seed):
    r = R(seed)
    n = int(1.8 * SR)
    t = np.arange(n) / SR
    out = shimmer(n, 261.63, seed, 9, 1.0) * np.minimum(t / 0.15, 1.0) * np.exp(-t / 0.9)
    for off in (0.0, 0.06):                                                                         # the split: one tone becomes two
        f0 = 330.0
        f = f0 * (1.0 + (0.5 if off else -0.0) * np.clip(t / 0.5, 0, 1))
        ph = np.cumsum(f) / SR * 2 * np.pi
        out += np.sin(ph) * np.exp(-t / 0.5) * 0.4
    return done(wet(out, 1.2, mix=0.3, damp=0.3, seed=seed), -13.0, 80.0, fout=0.4, max_len=1.8)


def superpos_loop():
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = R(51)
    out = np.zeros(n)
    for ratio in (1.0, 1.5, 2.0, 3.0):
        f = snap(220 * ratio, dur)
        for beat in (-2, 2):                                                                          # beating pairs (integer beat cycles per loop)
            out += np.sin(2 * np.pi * (f + beat / dur) * t + r.uniform(0, 6.28)) * 0.3 / ratio ** 0.4
    out *= 0.7 + 0.3 * np.sin(2 * np.pi * (4 / dur) * t)
    for k in range(8):                                                                              # a sparkle every quarter of a second, wrapped
        f = snap(880 * PENTA[(k * 3) % len(PENTA)], 0.25)
        m = int(0.25 * SR)
        tm = np.arange(m) / SR
        s = np.sin(2 * np.pi * f * tm) * np.exp(-tm / 0.05) * 0.14
        place(out, s, k * 0.25)
    return done_loop(out, -22.0, 120.0)


def entangle_loop():
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = snap(330, dur)
    g = snap(495, dur)
    a = 0.5 + 0.5 * np.sin(2 * np.pi * (3 / dur) * t)
    out = np.sin(2 * np.pi * f * t) * a + np.sin(2 * np.pi * g * t) * (1 - a)                        # two tones trading amplitude: complementary
    out += np.sin(2 * np.pi * snap(660, dur) * t + 2.0 * np.sin(2 * np.pi * (6 / dur) * t)) * 0.2
    out += pn(n, 52, lambda x: ((x > 2000) & (x < 9000)).astype(float) / np.sqrt(x), 0.1 * np.std(out)) * (0.5 + 0.5 * np.sin(2 * np.pi * (6 / dur) * t))
    return done_loop(out, -23.0, 120.0)


def quantum_ready():
    n = int(0.7 * SR)
    out = np.zeros(n)
    for k, f in enumerate((880.0, 1318.5, 1760.0)):
        m = int(0.5 * SR)
        tm = np.arange(m) / SR
        place(out, ma.fm_bell(0.5, f, 2.76, 1.2, 0.2, 0.08), k * 0.07, 0.6)
    return done(wet(out, 0.6, mix=0.2, damp=0.3, seed=60), -16.0, 300.0, fout=0.2, max_len=0.7)


def quantum_fail():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = 300 * (110 / 300) ** (t / 0.5)
    ph = np.cumsum(f) / SR * 2 * np.pi
    out = (np.sign(np.sin(ph)) * 0.4 + np.sin(ph)) * np.exp(-t / 0.15) * np.minimum(t / 0.005, 1.0)
    return done(wet(out, 0.3, mix=0.1, seed=61), -16.0, 100.0, fout=0.1, max_len=0.5)


# ------------------------------------------------------------------ vehicles
def engine(f, bright, seed, rough=0.35, noise=0.12):
    dur = 1.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = R(seed)
    f = 2.0 * round(f * dur / 2.0) / dur                                                              # an even number of cycles per loop (the firing lump runs at f / 2)
    out = np.zeros(n)
    for k in range(1, 31):
        out += np.sin(2 * np.pi * k * f * t + r.uniform(0, 6.28)) * k ** -0.85 * (1 + 0.5 * r.random())
    lump = 1 + rough * np.sin(2 * np.pi * (f / 2) * t + 0.4) + 0.15 * np.sin(2 * np.pi * 3 * t)
    out = saturate(out * lump / np.max(np.abs(out * lump)), 2.0)
    out = lp(out, bright, 2)
    out += pn(n, seed + 5, lambda x: ((x > 250) & (x < 2600)).astype(float) / np.sqrt(x), noise * 0.9 * np.std(out)) * (1 + 0.8 * np.sin(2 * np.pi * f * t))
    out += np.sin(2 * np.pi * snap(f * 11.5, dur) * t) * 0.03                                         # a turbo-ish whine
    return out


def engine_low():
    return done_loop(engine(52.0, 1700, 70), -17.0, 70.0)


def engine_high():
    return done_loop(engine(138.0, 3600, 71, rough=0.2, noise=0.2), -18.0, 100.0)


def engine_start():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    f = 7.0 + 5.0 * np.clip(t / 0.9, 0, 1)                                                          # cranking: a stuttering starter
    crank = band(white(n, 72), 80, 1500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f * t))) * np.where(t < 1.0, 1.0, 0.0)
    out += crank * 0.7
    e = engine(52.0, 1700, 70)
    e = np.tile(e, 2)[:n] * np.clip((t - 0.95) / 0.12, 0, 1) * (1.0 + 1.0 * np.exp(-np.maximum(t - 1.0, 0) / 0.15))
    out += e * 0.5
    return done(wet(out, 0.4, mix=0.1, seed=73), -15.0, 80.0, fout=0.3, max_len=1.6)


def tyre_squeal():
    dur = 1.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    r = R(80)
    out = np.zeros(n)
    wob = 1 + 0.04 * np.sin(2 * np.pi * (2 / dur) * t) + 0.02 * np.sin(2 * np.pi * (7 / dur) * t)
    ph = np.cumsum(snap(1750, dur) * wob) / SR * 2 * np.pi
    for k, a in ((1, 1.0), (2, 0.5), (3, 0.35), (5, 0.15)):
        out += np.sin(k * ph + r.uniform(0, 6.28)) * a
    out += pn(n, 81, lambda x: ((x > 1300) & (x < 5500)).astype(float) / np.sqrt(x), 0.6 * np.std(out))
    out *= 0.8 + 0.2 * np.sin(2 * np.pi * (11 / dur) * t)
    return done_loop(saturate(out / np.max(np.abs(out)), 1.6), -21.0, 600.0)


def car_crash(seed):
    r = R(seed)
    n = int(2.0 * SR)
    out = np.zeros(n)
    s, _ = sine_sweep(0.35, 140, 45)
    out[: len(s)] += s * expenv(len(s), 0.09) * 1.4
    out += band(white(n, seed), 120, 3500) * expenv(n, 0.07) * 1.6
    out += band(white(n, seed + 1), 1200, 9000) * expenv(n, 0.03) * 1.0
    for _ in range(14):                                                                              # crumpling steel
        tt = r.uniform(0.0, 0.5) ** 1.2
        f0 = r.uniform(150, 700)
        m = int(0.18 * SR)
        place(out, modal(m, f0 * np.array([1, 2.2, 3.7]), [0.07, 0.05, 0.035], [0.4, 0.3, 0.2]), tt, r.uniform(0.3, 0.8))
    for _ in range(26):                                                                              # glass and trim
        tt = 0.04 + 1.3 * r.random() ** 1.6
        place(out, tick(r, 3000, 11000, r.uniform(0.004, 0.02), r.uniform(0.1, 0.45)), tt)
    out += modal(n, [95, 188], [0.5, 0.3], [0.4, 0.2], 0.05)                                         # the body of the car booming
    return done(wet(saturate(out, 1.5), 1.2, mix=0.25, seed=seed), -11.0, 55.0, fout=0.6, max_len=2.0)


def car_bump(seed):
    r = R(seed)
    n = int(0.6 * SR)
    out = band(white(n, seed), 100, 2500) * expenv(n, 0.04) * 1.2
    s, _ = sine_sweep(0.2, 150, 55)
    out[: len(s)] += s * expenv(len(s), 0.06) * 1.0
    out += modal(n, [210 * r.uniform(0.9, 1.2), 560], [0.12, 0.06], [0.35, 0.2])
    return done(wet(out, 0.4, mix=0.15, seed=seed), -15.0, 70.0, fout=0.2, max_len=0.6)


def horn(seed):
    r = R(seed)
    dur = 0.85
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for f in (415.3 * r.uniform(0.97, 1.05), 523.25 * r.uniform(0.97, 1.05)):                        # a minor-third horn pair
        for k in range(1, 9):
            out += np.sin(2 * np.pi * f * k * t + r.uniform(0, 6.28)) / k ** 1.1
    out = saturate(out / np.max(np.abs(out)), 2.2)
    out *= np.minimum(t / 0.02, 1.0) * np.minimum((dur - t) / 0.06, 1.0)
    return done(wet(out, 0.4, mix=0.1, seed=seed), -14.0, 250.0, fout=0.04, max_len=dur)


def car_door(seed):
    n = int(0.45 * SR)
    out = band(white(n, seed), 200, 3000) * expenv(n, 0.02) * 1.2
    s, _ = sine_sweep(0.12, 140, 60)
    out[: len(s)] += s * expenv(len(s), 0.04)
    out += modal(n, [820, 1760], [0.03, 0.02], [0.35, 0.2], 0.01)
    place(out, _click(n, seed + 1, 600, 0.01, 1500, 7000, 0.5), 0.09)
    return done(wet(out, 0.3, mix=0.12, seed=seed), -17.0, 120.0, fout=0.15, max_len=0.45)


def traffic_loop():
    """Heard from the cars of the city's traffic (follow emitters): engine murmur and wet-road tyre hiss, pitched by speed."""
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = np.tile(engine(60.0, 1100, 90, rough=0.25), 2)[:n]
    hiss = pn(n, 91, lambda x: ((x > 900) & (x < 6500)).astype(float) / np.sqrt(x), 0.5 * np.std(e))
    out = e * 0.7 + hiss * (0.8 + 0.2 * np.sin(2 * np.pi * (3 / dur) * t))
    return done_loop(out, -20.0, 100.0)


# ------------------------------------------------------------------ UI and pickups
def beep(freqs, step, tau, n_dur, bell=True, seed=0, hp=300.0, level=-16.0, damp=0.3, rt=0.4):
    n = int(n_dur * SR)
    out = np.zeros(n)
    for k, f in enumerate(freqs):
        place(out, ma.fm_bell(min(0.9, n_dur), f, 2.0 if bell else 1.0, 1.0, tau, tau * 0.4), k * step, 0.7)
    return done(wet(out, rt, mix=0.15, damp=damp, seed=seed), level, hp, fout=0.1, max_len=n_dur)


def ui_click():
    n = int(0.12 * SR)
    out = band(white(n, 120), 2000, 8000) * expenv(n, 0.003) * 0.6 + modal(n, [1400, 2800], [0.015, 0.01], [0.5, 0.2])
    return done(out, -19.0, 500.0, fout=0.04, max_len=0.12)


def ui_tick():
    n = int(0.08 * SR)
    out = modal(n, [2400, 3600], [0.008, 0.005], [0.5, 0.25]) + band(white(n, 121), 3000, 9000) * expenv(n, 0.002) * 0.25
    return done(out, -23.0, 800.0, fout=0.03, max_len=0.08)


def ui_error():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, f in enumerate((220.0, 196.0)):
        m = int(0.16 * SR)
        tm = np.arange(m) / SR
        place(out, (np.sign(np.sin(2 * np.pi * f * tm)) * 0.3 + np.sin(2 * np.pi * f * tm)) * np.exp(-tm / 0.09), k * 0.14)
    return done(out, -18.0, 120.0, fout=0.08, max_len=0.35)


def heartbeat():
    n = int(0.95 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for t0, f0, g in ((0.0, 118.0, 1.0), (0.3, 104.0, 0.7)):                                        # lub ... dub
        s, _ = sine_sweep(0.22, f0, f0 * 0.55)
        e = np.minimum(np.arange(len(s)) / SR / 0.012, 1.0) * np.exp(-np.arange(len(s)) / SR / 0.05)
        place(out, saturate(s * e * 1.6, 1.5), t0, g)
        place(out, band(white(int(0.1 * SR), 130), 150, 900) * expenv(int(0.1 * SR), 0.02) * 0.6, t0, g)
    return done(wet(out, 0.3, mix=0.1, seed=131), -17.0, 80.0, fout=0.2, max_len=0.95)


def breath(kind, seed):
    r = R(seed)
    d = r.uniform(0.55, 0.75)
    n = int(d * SR)
    u = np.linspace(0, 1, n)
    x = white(n, seed) * 3.0
    x = formant_filter(x, [(620, 800 if kind == "in" else 520, 0.35, 1.0), (1500, 1900 if kind == "in" else 1200, 0.4, 0.7), (3200, 3800, 0.5, 0.35)])
    env = np.sin(np.pi * u ** (0.8 if kind == "in" else 1.25)) ** 1.5
    x *= env * (1 + 0.15 * np.sin(2 * np.pi * 9 * u * d))
    return done(wet(x, 0.3, mix=0.1, seed=seed), -22.0, 250.0, fout=0.2, max_len=0.75)


def gasp(seed):
    n = int(0.45 * SR)
    u = np.linspace(0, 1, n)
    x = formant_filter(white(n, seed) * 3.0, [(700, 1100, 0.35, 1.0), (1700, 2400, 0.4, 0.8), (3500, 4200, 0.5, 0.4)])
    x *= np.minimum(u / 0.12, 1.0) * np.exp(-np.maximum(u - 0.3, 0) * 5.0)
    return done(x, -18.0, 250.0, fout=0.1, max_len=0.45)


# ------------------------------------------------------------------ radio: squelch, static and a speech-like babble
VOWELS = {"a": (800, 1250), "e": (520, 1900), "i": (320, 2300), "o": (520, 920), "u": (360, 760)}


def radio_filter(x, seed, hiss=0.02):
    x = band(x, 380, 3300, 3)
    x = saturate(x / (np.max(np.abs(x)) + 1e-9), 2.2)
    return x + band(white(len(x), seed), 800, 5000) * hiss * 3.0


def babble(seed):
    """One syllable of ORACLE's synthesised, half-corrupted radio voice (consonant burst + gliding vowel). The engine plays one per few typed letters."""
    r = R(seed)
    d = r.uniform(0.07, 0.13)
    n = int(d * SR)
    v1, v2 = r.choice(list(VOWELS)), r.choice(list(VOWELS))
    u = np.linspace(0, 1, n)
    f0 = r.uniform(105, 175) * (1.0 - 0.1 * u)
    x = glottal(f0, 0.1, 45, 0.04, seed, jitter=0.02)
    x = formant_filter(x, [(VOWELS[v1][0], VOWELS[v2][0], 0.2, 1.0), (VOWELS[v1][1], VOWELS[v2][1], 0.2, 0.7), (2700, 2800, 0.25, 0.25)], frame=512)
    x *= np.minimum(u / 0.12, 1.0) * np.minimum((1 - u) / 0.25, 1.0)
    c = band(white(n, seed + 5), r.uniform(1800, 4200), 7000) * expenv(n, 0.012) * r.uniform(0.0, 0.7)
    x = radio_filter((x + c) * 1.0, seed + 6)
    return done(x, -19.0, 350.0, fout=0.02, max_len=0.14, drive=1.0)


def radio_open(seed=140):
    n = int(0.35 * SR)
    out = band(white(n, seed), 600, 6000) * (expenv(n, 0.045) * 1.0) + band(white(n, seed + 1), 2000, 8000) * expenv(n, 0.004) * 1.2
    tt = np.arange(int(0.07 * SR)) / SR
    place(out, np.sin(2 * np.pi * 1850 * tt) * np.minimum(tt / 0.004, 1) * np.minimum((0.07 - tt) / 0.01, 1) * 0.35, 0.12)
    return done(radio_filter(out, seed + 2, 0.0), -18.0, 400.0, fout=0.1, max_len=0.35)


def radio_close(seed=142):
    n = int(0.25 * SR)
    out = band(white(n, seed), 500, 5000) * expenv(n, 0.03) * 0.9
    out += band(white(n, seed + 1), 2500, 9000) * expenv(n, 0.003) * 1.0
    return done(radio_filter(out, seed + 2, 0.0), -20.0, 400.0, fout=0.08, max_len=0.25)


def radio_static():
    dur = 2.0
    n = int(dur * SR)
    r = R(145)
    out = pn(n, 146, lambda x: ((x > 500) & (x < 4800)).astype(float) / x ** 0.2, 0.12)
    for _ in range(40):
        place(out, tick(r, 1200, 7000, 0.0025, r.uniform(0.15, 0.6)), r.uniform(0, dur - 0.05))
    out *= 1 + 0.4 * np.sin(2 * np.pi * (5 / dur) * np.arange(n) / SR + 1.0)
    return done_loop(out, -27.0, 350.0)


def radio_glitch(seed):
    r = R(seed)
    n = int(0.4 * SR)
    out = np.zeros(n)
    t = 0.0
    while t < 0.3:
        m = int(r.uniform(0.01, 0.04) * SR)
        place(out, band(white(m, seed + int(t * 1000)), r.uniform(500, 2500), r.uniform(3000, 6000)) * np.hanning(m) * r.uniform(0.3, 1.0), t)
        t += m / SR * r.uniform(0.8, 2.0)
    return done(radio_filter(out, seed + 3, 0.0), -22.0, 400.0, fout=0.05, max_len=0.4)


# ------------------------------------------------------------------ pickups, mission cues, heat
def pickup_health():
    return beep((523.25, 659.25, 783.99), 0.07, 0.25, 0.8, seed=150, level=-15.0)


def pickup_energy():
    n = int(0.7 * SR)
    out = np.zeros(n)
    for k, f in enumerate((660, 990, 1320, 1980)):
        place(out, ma.fm_bell(0.4, f, 3.0, 1.5, 0.12, 0.05), k * 0.05, 0.6)
    s, _ = sine_sweep(0.3, 300, 1500)
    place(out, s * np.linspace(0, 1, len(s)) * np.exp(-np.arange(len(s)) / SR / 0.15) * 0.3, 0.0)
    return done(wet(out, 0.5, mix=0.2, damp=0.3, seed=151), -15.0, 250.0, fout=0.2, max_len=0.7)


def pickup_ammo():
    n = int(0.5 * SR)
    out = _click(n, 152, 420, 0.03, 1500, 7000, 1.0, [(1900, 0.3)])
    place(out, _click(n, 153, 520, 0.03, 1500, 7000, 0.7, [(2400, 0.25)]), 0.07)
    place(out, ma.fm_bell(0.4, 1568.0, 2.0, 0.8, 0.12, 0.05), 0.12, 0.35)
    return done(wet(out, 0.3, mix=0.12, seed=152), -16.0, 200.0, fout=0.15, max_len=0.5)


def credit():
    return beep((1318.5, 1760.0), 0.09, 0.3, 0.8, seed=154, level=-17.0, hp=500.0)


def mission_start():
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    out = shimmer(n, 146.83, 160, 6, 0.4) * np.minimum(t / 0.4, 1.0) * np.exp(-t / 0.8)
    for k, f in enumerate((293.66, 440.0, 587.33)):
        place(out, ma.fm_bell(1.0, f, 2.0, 1.0, 0.5, 0.2), 0.2 + k * 0.12, 0.5)
    return done(wet(out, 1.2, mix=0.3, damp=0.3, seed=160), -14.0, 80.0, fout=0.4, max_len=1.6)


def mission_complete():
    n = int(2.2 * SR)
    out = np.zeros(n)
    for k, f in enumerate((293.66, 369.99, 440.0, 587.33, 739.99)):
        place(out, ma.fm_bell(1.4, f, 2.0, 1.1, 0.6, 0.2), k * 0.11, 0.55)
        place(out, ma.fm_bell(1.4, f * 2, 3.0, 0.8, 0.25, 0.1), k * 0.11, 0.2)
    return done(wet(out, 1.4, mix=0.3, damp=0.3, seed=161), -13.0, 100.0, fout=0.5, max_len=2.2)


def objective_ping():
    return beep((987.77, 1479.98), 0.12, 0.35, 0.9, seed=162, level=-18.0, hp=400.0, rt=0.6)


def heat_up():
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    s, _ = sine_sweep(0.6, 90, 55)
    out = np.zeros(n)
    out[: len(s)] += s * expenv(len(s), 0.2)
    for k, f in enumerate((220.0, 233.08)):                                                         # a minor second: tension
        out += (np.sign(np.sin(2 * np.pi * f * t)) * 0.25 + np.sin(2 * np.pi * f * t)) * expenv(n, 0.35) * 0.35
    out += band(white(n, 170), 400, 6000) * np.linspace(0, 1, n) ** 3 * np.exp(-np.maximum(t - 0.4, 0) / 0.15) * 0.4
    return done(wet(out, 0.8, mix=0.2, seed=170), -14.0, 70.0, fout=0.3, max_len=1.2)


def heat_down():
    n = int(1.0 * SR)
    out = np.zeros(n)
    for k, f in enumerate((440.0, 329.63, 293.66)):
        place(out, ma.fm_bell(0.7, f, 2.0, 0.6, 0.35, 0.15), k * 0.14, 0.5)
    return done(wet(out, 0.7, mix=0.25, damp=0.3, seed=171), -19.0, 150.0, fout=0.3, max_len=1.0)


# ------------------------------------------------------------------ the registry
def variants(fn, count, base_seed=1, **kw):
    return [(lambda s=base_seed + 17 * i: fn(s, **kw)) for i in range(count)]


# name -> list of generator callables (one per variant). Base names whose .wav already exists in make_audio.py keep it as variant 0.
# Files: a single entry -> name.wav, several -> name_0.wav .. name_N.wav. The set of loops is LOOPS.
SFX = {}
LOOPS = {"drone_hum", "radio_static", "superpos_loop", "entangle_loop", "engine_low", "engine_high", "tyre_squeal", "traffic_loop"}


def _reg(name, fns):
    SFX[name] = fns if isinstance(fns, list) else [fns]


for surf, fn in (("asphalt", step_asphalt), ("metal", step_metal), ("stairs", step_stairs)):
    _reg("step_" + surf, variants(fn, 6, 100))
_reg("land_asphalt", variants(land, 3, 200, surface="asphalt"))
_reg("land_metal", variants(land, 3, 210, surface="metal"))
_reg("shot", [])                                                          # existing shot.wav is variant 0 (see Sfx), the new ones are shot_1..3
for i in range(1, 4):
    SFX["shot_%d" % i] = [lambda s=300 + 11 * i: gun(s, "rifle")]
for i in range(1, 3):
    SFX["enemy_shot_%d" % i] = [lambda s=400 + 13 * i: gun(s, "enemy")]
SFX["shot_far_0"] = [lambda: shot_far(500, "rifle")]
SFX["shot_far_1"] = [lambda: shot_far(510, "rifle")]
SFX["enemy_shot_far_0"] = [lambda: shot_far(520, "enemy")]
SFX["enemy_shot_far_1"] = [lambda: shot_far(530, "enemy")]
_reg("dry_fire", variants(dry_fire, 2, 600))
for i in range(1, 3):
    SFX["reload_%d" % i] = [lambda s=700 + 31 * i: reload_full(s)]
for kind, fn in (("concrete", impact_concrete), ("metal", impact_metal), ("glass", impact_glass), ("flesh", impact_flesh), ("asphalt", impact_asphalt)):
    _reg("impact_" + kind, variants(fn, 4, 800))
_reg("ricochet", variants(ricochet, 4, 900))
_reg("whizz", variants(whizz, 4, 950))
for i in range(1, 4):
    SFX["boom_%d" % i] = [lambda s=1000 + 7 * i: explosion(s, True)]
_reg("explosion_small", variants(explosion, 2, 1100, big=False))
_reg("distant_boom", variants(distant_boom, 2, 1200))
_reg("distant_gunfire", variants(distant_gunfire, 2, 1250))
for kind in ("alert", "attack", "pain", "death"):
    _reg("trooper_" + kind, [lambda s=1300 + 41 * i + len(kind), k=kind: trooper_voice(k, s) for i in range(3)])
for kind in ("pain", "effort", "death"):
    n_var = 1 if kind == "death" else 3
    _reg("hero_" + kind, [lambda s=1500 + 23 * i + len(kind), k=kind: hero_voice(k, s) for i in range(n_var)])
SFX["drone_hum"] = [drone_hum]
SFX["drone_charge"] = [drone_charge]
SFX["drone_alert"] = [drone_alert]
SFX["drone_death"] = [drone_death]
for i in range(1, 3):
    SFX["blink_%d" % i] = [lambda s=1600 + 13 * i: blink_sfx(s)]
SFX["link_1"] = [lambda: link_sfx(1650)]
SFX["link_2"] = [lambda: link_sfx(1660)]
SFX["superpos_enter"] = [lambda: superpos_enter(1670)]
SFX["superpos_loop"] = [superpos_loop]
SFX["entangle_loop"] = [entangle_loop]
SFX["quantum_ready"] = [quantum_ready]
SFX["quantum_fail"] = [quantum_fail]
SFX["engine_low"] = [engine_low]
SFX["engine_high"] = [engine_high]
SFX["engine_start"] = [engine_start]
SFX["tyre_squeal"] = [tyre_squeal]
_reg("car_crash", variants(car_crash, 3, 1700))
_reg("car_bump", variants(car_bump, 3, 1750))
_reg("horn", variants(horn, 2, 1800))
SFX["car_door"] = [lambda: car_door(1850)]
SFX["traffic_loop"] = [traffic_loop]
SFX["ui_click"] = [ui_click]
SFX["ui_tick"] = [ui_tick]
SFX["ui_confirm"] = [lambda: beep((659.25, 987.77), 0.07, 0.25, 0.6, seed=1900, level=-17.0, hp=400.0)]
SFX["ui_back"] = [lambda: beep((659.25, 440.0), 0.07, 0.2, 0.5, seed=1901, level=-18.0, hp=300.0)]
SFX["ui_error"] = [ui_error]
SFX["ui_pause"] = [lambda: beep((880.0, 660.0, 440.0), 0.06, 0.2, 0.6, seed=1902, level=-18.0, hp=250.0)]
SFX["ui_resume"] = [lambda: beep((440.0, 660.0, 880.0), 0.06, 0.2, 0.6, seed=1903, level=-18.0, hp=250.0)]
SFX["heartbeat"] = [heartbeat]
_reg("breath_in", [lambda s=2000 + i: breath("in", s) for i in range(2)])
_reg("breath_out", [lambda s=2010 + i: breath("out", s) for i in range(2)])
SFX["gasp"] = [lambda: gasp(2020)]
SFX["radio_open"] = [radio_open]
SFX["radio_close"] = [radio_close]
SFX["radio_static"] = [radio_static]
_reg("radio_glitch", variants(radio_glitch, 3, 2100))
SFX["babble"] = [lambda s=2200 + 9 * i: babble(s) for i in range(10)]
SFX["pickup_health"] = [pickup_health]
SFX["pickup_energy"] = [pickup_energy]
SFX["pickup_ammo"] = [pickup_ammo]
SFX["credit"] = [credit]
SFX["mission_start"] = [mission_start]
SFX["mission_complete"] = [mission_complete]
SFX["objective_ping"] = [objective_ping]
SFX["heat_up"] = [heat_up]
SFX["heat_down"] = [heat_down]


def file_names(name, count):
    """One generator -> name.wav; several -> name_0.wav ... (the engine finds variants by this scheme)."""
    return [name] if count == 1 else ["%s_%d" % (name, i) for i in range(count)]


def build_sfx(out_dir, only, verbose=True):
    made = {}
    for name, fns in SFX.items():
        if not fns:
            continue
        for fname, fn in zip(file_names(name, len(fns)), fns):
            if only and not any(fnmatch.fnmatch(fname, pat) or fnmatch.fnmatch(name, pat) for pat in only):
                continue
            t0 = time.time()
            x = fn()
            x = np.asarray(x, dtype=np.float64)
            write_wav(os.path.join(out_dir, fname + ".wav"), x, loop=(name in LOOPS))
            made[fname] = x
            if verbose:
                print("%-22s %5.2f s  peak %6.1f dBFS  rms %6.1f dBFS  (%.1fs)" % (fname, len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-12), 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12), time.time() - t0), flush=True)
    return made


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--only", default="")
    ap.add_argument("--no-music", action="store_true")
    ap.add_argument("--no-sfx", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    only = [s for s in args.only.split(",") if s]
    if args.list:
        for name, fns in SFX.items():
            print(name, len(fns))
        return 0
    os.makedirs(args.out, exist_ok=True)
    if not args.no_sfx:
        build_sfx(args.out, only)
    if not args.no_music:
        import make_music
        make_music.build(args.out, only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
