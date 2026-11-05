#!/usr/bin/env python3
"""AUDIO v3 for Quantum Teleportar (numpy + ffmpeg/libvorbis only, same kit as make_pass2.py).

  verbs (WAV one-shots)  verb_shield (PHASE SHIELD), verb_slip (TIME SLIP), verb_arc (ARC), verb_slam (ground slam), verb_grab (warp grab lift), verb_throw,
                         verb_wallrun_0..2 (scrape ticks)
  weapons (WAV)          shot_rail, shot_flux, shot_gravity, shot_burst, shot_lance
  footsteps (WAV)        step_roof_0..3 (tar and gravel), step_tile_0..3 (interior hard floor), step_carpet_0..3
  engines (WAV loops)    engine_bike_low|high, engine_hover_low|high, engine_heavy_low|high
  stingers (WAV)         sting_stealth_spot, sting_stealth_clear, sting_phase (boss phase change), sting_chapter
  radio shows (OGG)      talk_neon_0|1, talk_vael_0|1, talk_club_0|1, talk_lofi_0|1 (garbled alien chatter, no words), ad_0..2 (jingle plus chatter)
Run: python3 tools/audio/make_v3.py [out_dir] [--only glob ...]   (called by tools/build_assets.sh after make_weapons.py).
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
from make_audio import SR, band, expenv, saturate, fm_bell, sine_sweep, white, echo, reverb, place  # noqa: E402
import make_library as ml  # noqa: E402
from make_library import R, lp, wet, scatter, modal  # noqa: E402
import make_music as mm  # noqa: E402


def _n(sec):
    return int(sec * SR)


def _t(n):
    return np.arange(n) / SR


def _sw(dur, f0, f1, n=None):
    s, _ = sine_sweep(dur, f0, f1)
    if n is None:
        return s
    o = np.zeros(n)
    m = min(n, len(s))
    o[:m] = s[:m]
    return o


# ------------------------------------------------------------------ verbs
def verb_shield():
    n = _n(0.8)
    t = _t(n)
    hum = np.zeros(n)
    for k, f in enumerate((220, 330, 495, 660)):                              # a stacked, slightly detuned hex hum that blooms
        hum += np.sin(2 * np.pi * f * (1 + 0.004 * k) * t) / (1 + k) * np.minimum(t / 0.12, 1.0)
    hum *= np.exp(-t / 0.45)
    glass = band(white(n, 801), 3500, 11000) * expenv(n, 0.06) * 0.5
    ring = fm_bell(0.8, 1760, 2.4, 1.6, 0.3, 0.12)[:n]
    x = hum * 0.8 + glass + ring * 0.35
    x += _sw(0.18, 160, 520, n) * expenv(n, 0.07) * 0.6
    return ml.done(reverb(x, 0.6, wet=0.2, damp=0.4, seed=8), -14.0, 140.0, fout=0.2, max_len=1.0)


def verb_slip():
    n = _n(1.1)
    t = _t(n)
    f = 520 * np.exp(-1.15 * t / 1.1)                                          # a falling, wobbling tone: time slowing
    ph = np.cumsum(2 * np.pi * f * (1 + 0.012 * np.sin(2 * np.pi * 6 * t)) / SR)
    x = (np.sin(ph) + 0.5 * np.sin(ph * 2.003)) * np.minimum(t / 0.05, 1.0) * np.exp(-t / 0.55)
    rev = band(white(n, 811), 600, 5000) * (t / 1.1) ** 2 * np.exp(-((t - 0.95) / 0.1) ** 2 * 0.5) * 1.2    # a swell that sucks inward, then lets go
    x = x * 0.7 + rev * 0.5 + _sw(0.25, 90, 40, n) * expenv(n, 0.1) * 0.5
    return ml.done(reverb(x, 0.9, wet=0.3, damp=0.5, seed=9), -14.0, 100.0, fout=0.3, max_len=1.3)


def verb_arc():
    n = _n(0.7)
    t = _t(n)
    x = np.zeros(n)
    r = R(821)
    for k in range(4):                                                         # four chained zaps, rising
        t0 = 0.04 + k * 0.13
        s = _sw(0.12, 900 + 500 * k, 3600 + 400 * k, _n(0.14))
        place(x, s * expenv(len(s), 0.04) * 0.8 + band(white(len(s), 822 + k), 2500, 12000) * expenv(len(s), 0.02) * 1.2, t0)
        place(x, ml.tick(r, 1500, 9000, 0.004, 1.0), t0)
    crackle = band(white(n, 830), 3000, 14000) * (np.sin(2 * np.pi * 90 * t) > 0.3) * expenv(n, 0.3) * 0.5
    x = band(x + crackle, 200, 12000)
    return ml.done(reverb(x, 0.4, wet=0.18, damp=0.5, seed=10), -13.0, 160.0, fout=0.15, max_len=0.8)


def verb_slam():
    n = _n(1.0)
    boom = _sw(0.5, 120, 32, n) * expenv(n, 0.2) * 1.3
    crack = band(white(n, 841), 1200, 9000) * expenv(n, 0.012) * 1.5
    rub = band(white(n, 842), 80, 700) * expenv(n, 0.18) * 0.9
    deb = scatter(n, R(843), 14, 0.06, 0.7, 1800, 7000, 0.01, 0.35)
    ring = _sw(0.4, 700, 300, n) * expenv(n, 0.08) * 0.35                       # the cyan shockwave sheen
    x = saturate(boom + crack + rub + deb + ring, 1.4)
    return ml.done(reverb(x, 0.8, wet=0.2, damp=0.6, seed=11), -9.0, 28.0, fout=0.25, max_len=1.1)


def verb_grab():
    n = _n(0.55)
    t = _t(n)
    f = 180 * np.exp(1.6 * t / 0.55)
    ph = np.cumsum(2 * np.pi * f / SR)
    x = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * np.minimum(t / 0.03, 1.0) * np.exp(-t / 0.4)      # a lifting warp whine
    x += band(white(n, 851), 900, 6000) * expenv(n, 0.2) * 0.25
    lock = np.zeros(n)
    place(lock, ml.tick(R(852), 700, 4000, 0.008, 1.0), 0.42)                    # the lock click at the top
    place(lock, fm_bell(0.1, 1500, 3.1, 1.0, 0.06, 0.04)[:_n(0.1)], 0.42, 0.5)
    return ml.done(x * 0.9 + lock, -14.0, 120.0, fout=0.12, max_len=0.6)


def verb_throw():
    n = _n(0.6)
    t = _t(n)
    whoosh = band(white(n, 861), 300, 5500, 2) * np.exp(-((t - 0.12) / 0.1) ** 2 * 0.5) * 1.1
    thump = _sw(0.2, 150, 55, n) * expenv(n, 0.06) * 1.1
    zip_ = _sw(0.35, 2400, 500, n) * expenv(n, 0.12) * 0.4
    return ml.done(saturate(whoosh + thump + zip_, 1.2), -12.0, 45.0, fout=0.15, max_len=0.7)


def verb_wallrun(seed):
    r = R(seed)
    n = _n(0.28)
    j = r.uniform(0.9, 1.15)
    x = band(white(n, seed), 1200 * j, 7500, 2) * expenv(n, 0.06) * 0.9                  # a scuffing, tearing slide
    x += band(white(n, seed + 1), 200, 900, 2) * expenv(n, 0.03) * 0.6
    x += modal(n, np.array([520, 1130, 1810]) * j, [0.05, 0.04, 0.03], [0.3, 0.2, 0.12])
    return ml.done(x, -20.0, 120.0, fout=0.07, max_len=0.3)


# ------------------------------------------------------------------ weapons
def shot_rail():
    n = _n(0.9)
    t = _t(n)
    zap = _sw(0.12, 4800, 380, n) * expenv(n, 0.03) * 1.1
    crack = band(white(n, 871), 2000, 14000) * expenv(n, 0.004) * 2.2
    body = _sw(0.3, 220, 45, n) * expenv(n, 0.09) * 1.0
    whine = np.sin(2 * np.pi * (900 + 600 * np.exp(-t / 0.2)) * t) * expenv(n, 0.35) * 0.18
    x = echo(saturate(zap + crack + body + whine, 1.5), 0.17, 0.25, lp=3000, taps=2)
    return ml.done(reverb(x, 0.9, wet=0.22, damp=0.5, seed=12), -11.0, 90.0, fout=0.25, max_len=1.0)


def shot_flux():
    n = _n(0.16)
    t = _t(n)
    x = np.sin(2 * np.pi * (1500 + 700 * np.sin(2 * np.pi * 70 * t)) * t) * expenv(n, 0.03) * 0.7
    x += band(white(n, 881), 3000, 11000) * expenv(n, 0.01) * 1.2
    return ml.done(x, -17.0, 400.0, fout=0.04, max_len=0.2)


def shot_gravity():
    n = _n(0.85)
    t = _t(n)
    x = _sw(0.7, 90, 30, n) * expenv(n, 0.3) * 1.2                                  # a heavy inward thump
    x += np.sin(2 * np.pi * (700 * np.exp(-2.0 * t)) * t) * expenv(n, 0.2) * 0.5
    x += band(white(n, 891), 120, 1400) * expenv(n, 0.12) * 0.9
    return ml.done(reverb(saturate(x, 1.3), 0.9, wet=0.25, damp=0.7, seed=13), -11.0, 25.0, fout=0.3, max_len=0.95)


def shot_burst():
    n = _n(0.3)
    x = band(white(n, 901), 1800, 11000) * expenv(n, 0.006) * 2.0 + band(white(n, 902), 400, 2600) * expenv(n, 0.02) * 1.2
    x += _sw(0.1, 800, 200, n) * expenv(n, 0.03) * 0.7
    return ml.done(echo(saturate(x, 1.4), 0.07, 0.2, lp=3000, taps=1), -14.0, 140.0, fout=0.08, max_len=0.35)


def shot_lance():
    n = _n(0.7)
    x = _sw(0.35, 3000, 220, n) * expenv(n, 0.08) * 0.9
    x += band(white(n, 911), 1500, 12000) * expenv(n, 0.008) * 1.6
    x += fm_bell(0.7, 640, 3.0, 2.0, 0.25, 0.1)[:n] * 0.4
    return ml.done(reverb(saturate(x, 1.3), 0.8, wet=0.25, damp=0.4, seed=14), -12.0, 100.0, fout=0.2, max_len=0.8)


# ------------------------------------------------------------------ footsteps
def step_roof(seed):
    r = R(seed)
    n = _n(0.4)
    j = r.uniform(0.85, 1.2)
    x = band(white(n, seed), 800 * j, 6500, 2) * expenv(n, 0.012) * 0.8                 # grit
    x += scatter(n, r, int(r.integers(4, 9)), 0.0, 0.12, 1500, 7000, 0.006, 0.4)        # gravel pieces
    x += _sw(0.1, 200 * j, 90, n) * expenv(n, 0.03) * 0.6                               # the dull tar body
    x += band(white(n, seed + 3), 2500, 9000) * expenv(n, 0.0025) * 0.35
    return ml.done(wet(saturate(x, 1.2), 0.25, mix=0.08, seed=seed), -22.0, 110.0, fout=0.1, max_len=0.4)


def step_tile(seed):
    r = R(seed)
    n = _n(0.45)
    j = r.uniform(0.9, 1.15)
    x = band(white(n, seed), 2200 * j, 9000, 2) * expenv(n, 0.002) * 0.7                # a hard heel tick
    x += band(white(n, seed + 1), 400, 2800, 2) * expenv(n, 0.01) * 0.6
    x += modal(n, np.array([980, 1730, 2650]) * j * r.uniform(0.95, 1.05, 3), [0.05, 0.035, 0.025], [0.25, 0.18, 0.1])
    x += _sw(0.08, 230 * j, 110, n) * expenv(n, 0.025) * 0.4
    return ml.done(reverb(x, 0.45, wet=0.3, predelay=0.006, damp=0.35, seed=seed), -22.0, 140.0, fout=0.12, max_len=0.45)


def step_carpet(seed):
    r = R(seed)
    n = _n(0.3)
    j = r.uniform(0.9, 1.15)
    x = band(white(n, seed), 300, 2200, 2) * expenv(n, 0.02) * 1.0                      # a muffled pad of a step
    x += _sw(0.12, 160 * j, 80, n) * expenv(n, 0.04) * 0.6
    x += band(white(n, seed + 1), 1500, 4500, 2) * expenv(n, 0.006) * 0.15
    return ml.done(x, -26.0, 90.0, fout=0.1, max_len=0.3)


# ------------------------------------------------------------------ engines (1 s loops, even cycle counts)
def _eng(f, bright, seed, rough, noise, whine=0.0, saw=1.0):
    n = _n(1.0)
    t = _t(n)
    r = R(seed)
    f = 2.0 * round(f / 2.0)
    out = np.zeros(n)
    for k in range(1, 31):
        out += np.sin(2 * np.pi * k * f * t + r.uniform(0, 6.28)) * k ** (-0.85 * saw) * (1 + 0.5 * r.random())
    lump = 1 + rough * np.sin(2 * np.pi * (f / 2) * t + 0.4)
    out = saturate(out * lump / np.max(np.abs(out * lump)), 1.8)
    out = lp(out, bright, 2)
    out += ml.pn(n, seed + 5, lambda x: ((x > 250) & (x < 3000)).astype(float) / np.sqrt(x), noise * np.std(out))
    if whine:
        out += np.sin(2 * np.pi * ml.snap(f * 9.0, 1.0) * t) * whine
    return out


def engine_bike_low():
    return ml.done_loop(_eng(78.0, 2600, 931, 0.5, 0.1), -17.0, 90.0)


def engine_bike_high():
    return ml.done_loop(_eng(210.0, 5200, 932, 0.3, 0.15), -18.0, 140.0)


def engine_hover_low():
    return ml.done_loop(_eng(96.0, 1800, 941, 0.05, 0.25, whine=0.05, saw=1.4), -18.0, 100.0)


def engine_hover_high():
    return ml.done_loop(_eng(320.0, 4200, 942, 0.04, 0.3, whine=0.06, saw=1.6), -19.0, 200.0)


def engine_heavy_low():
    return ml.done_loop(_eng(34.0, 1100, 951, 0.65, 0.18), -16.0, 45.0)


def engine_heavy_high():
    return ml.done_loop(_eng(88.0, 2200, 952, 0.45, 0.22), -17.0, 70.0)


# ------------------------------------------------------------------ stingers
def _chord(notes, dur, tau):
    n = _n(dur)
    t = _t(n)
    x = np.zeros(n)
    for f in notes:
        x += (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)) * np.exp(-t / tau)
    return x * np.minimum(t / 0.01, 1.0)


def sting_stealth_spot():
    n = _n(1.2)
    x = _chord([220, 233.1, 329.6], 1.2, 0.5)                                           # a minor second over the fifth: unease, a guard looked up
    x += _sw(0.5, 120, 60, n) * expenv(n, 0.2) * 0.8
    x += band(white(n, 961), 3000, 9000) * expenv(n, 0.015) * 0.5
    return ml.done(reverb(x, 1.0, wet=0.3, damp=0.5, seed=15), -14.0, 55.0, fout=0.35, max_len=1.4)


def sting_stealth_clear():
    n = _n(1.4)
    x = _chord([293.7, 440, 587.3], 1.4, 0.7)                                           # an open fifth settles
    x += fm_bell(1.4, 880, 2.0, 0.8, 0.6, 0.2)[:n] * 0.25
    return ml.done(reverb(x, 1.4, wet=0.35, damp=0.4, seed=16), -17.0, 90.0, fout=0.5, max_len=1.6)


def sting_phase():
    n = _n(1.5)
    t = _t(n)
    x = _chord([110, 164.8, 220], 1.5, 0.6) * 0.7
    x += _sw(0.4, 60, 36, n) * expenv(n, 0.2) * 1.2
    x += band(white(n, 971), 800, 8000) * expenv(n, 0.1) * 0.6 * (t < 0.3)
    x += _sw(0.25, 400, 2400, n) * expenv(n, 0.12) * 0.4
    return ml.done(reverb(saturate(x, 1.3), 1.1, wet=0.3, damp=0.5, seed=17), -11.0, 35.0, fout=0.5, max_len=1.7)


def sting_chapter():
    n = _n(2.0)
    x = _chord([146.8, 220, 293.7, 440], 2.0, 0.9)
    x += fm_bell(2.0, 587.3, 2.76, 1.4, 0.9, 0.3)[:n] * 0.3
    return ml.done(reverb(x, 1.8, wet=0.35, damp=0.5, seed=18), -14.0, 70.0, fout=0.7, max_len=2.2)


# ------------------------------------------------------------------ radio shows
def _syll(r, seed, f0, vowels, d):
    n = _n(d)
    u = np.linspace(0, 1, n)
    v1, v2 = r.choice(vowels), r.choice(vowels)
    f = f0 * r.uniform(0.9, 1.15) * (1.0 - 0.12 * u + 0.08 * np.sin(np.pi * u))
    x = ml.glottal(f, 0.12, 40, 0.05, seed, jitter=0.025)
    x = ml.formant_filter(x, [(ml.VOWELS[v1][0], ml.VOWELS[v2][0], 0.2, 1.0), (ml.VOWELS[v1][1], ml.VOWELS[v2][1], 0.2, 0.7), (2700, 2800, 0.25, 0.25)], frame=512)
    x *= np.minimum(u / 0.12, 1.0) * np.minimum((1 - u) / 0.25, 1.0)
    return x + band(white(n, seed + 5), r.uniform(1800, 4200), 7000) * expenv(n, 0.012) * r.uniform(0.0, 0.6)


STATION_VOICE = {
    # name: f0, syllable range (s), gap range (s), vowels, click gain, echo, crackle
    "neon": (150, (0.08, 0.15), (0.015, 0.06), ["a", "e", "i", "o", "u"], 0.0, 0.0, 0.0),
    "vael": (82, (0.1, 0.2), (0.03, 0.14), ["a", "o", "u", "e"], 0.7, 0.0, 0.2),
    "club": (210, (0.06, 0.11), (0.01, 0.04), ["i", "e", "a"], 0.0, 0.3, 0.0),
    "lofi": (118, (0.11, 0.2), (0.04, 0.16), ["o", "u", "a", "e"], 0.0, 0.18, 0.4),
}


def talk(station, seed, dur=3.4):
    f0, sy, gp, vow, click, echo_g, crackle = STATION_VOICE[station]
    vow = [v for v in vow if v in ml.VOWELS] or list(ml.VOWELS)
    r = R(seed)
    n = _n(dur)
    out = np.zeros(n)
    t = 0.12
    k = 0
    while t < dur - 0.4:
        for _ in range(int(r.integers(2, 6))):                                  # a burst of 2-5 syllables, then a breath
            d = r.uniform(*sy)
            place(out, _syll(r, seed + 31 * k, f0, vow, d), t)
            t += d + r.uniform(*gp)
            k += 1
            if t > dur - 0.4:
                break
        t += r.uniform(0.12, 0.35)
    if click > 0:
        out += ml.chatter(n, seed + 7, 0.1, dur - 0.3, 22, g=click * 0.6)
    if crackle > 0:
        out += scatter(n, r, int(60 * crackle * dur), 0.0, dur, 1200, 9000, 0.002, 0.25)
    out = ml.radio_filter(out / (np.max(np.abs(out)) + 1e-9), seed + 9, hiss=0.015)
    if echo_g > 0:
        out = echo(out, 0.19, echo_g, lp=2800, taps=2)
    return ml.done(out, -17.0, 300.0, fout=0.2, max_len=dur + 0.3, drive=1.0)


def ad(seed):
    r = R(seed)
    dur = 3.6
    n = _n(dur)
    out = np.zeros(n)
    scale = (261.6, 329.6, 392.0, 523.3, 659.3) if seed % 2 else (293.7, 349.2, 440.0, 587.3, 698.5)
    for k in range(5):                                                         # a little jingle on a pentatonic scale
        place(out, fm_bell(0.45, scale[int(r.integers(0, 5))], 2.0, 1.1, 0.25, 0.1)[:_n(0.45)], 0.05 + 0.2 * k, 0.7)
    t = 1.3
    k = 0
    while t < dur - 0.6:                                                       # the announcer, quick and bright
        d = r.uniform(0.07, 0.13)
        place(out, _syll(r, seed * 17 + k, 175, ["a", "e", "i", "o"], d) * 1.2, t)
        t += d + r.uniform(0.01, 0.05)
        k += 1
        if k % 5 == 0:
            t += 0.15
    for j in range(3):                                                         # the tag: three notes that fall
        place(out, fm_bell(0.5, scale[4 - j], 2.0, 1.0, 0.3, 0.1)[:_n(0.5)], dur - 0.9 + 0.12 * j, 0.5)
    out = ml.radio_filter(out / (np.max(np.abs(out)) + 1e-9), seed + 3, hiss=0.01)
    return ml.done(out, -17.0, 250.0, fout=0.25, max_len=dur + 0.2, drive=1.0)


WAVS = {
    "verb_shield": verb_shield, "verb_slip": verb_slip, "verb_arc": verb_arc, "verb_slam": verb_slam, "verb_grab": verb_grab, "verb_throw": verb_throw,
    "shot_rail": shot_rail, "shot_flux": shot_flux, "shot_gravity": shot_gravity, "shot_burst": shot_burst, "shot_lance": shot_lance,
    "sting_stealth_spot": sting_stealth_spot, "sting_stealth_clear": sting_stealth_clear, "sting_phase": sting_phase, "sting_chapter": sting_chapter,
}
LOOPS = {
    "engine_bike_low": engine_bike_low, "engine_bike_high": engine_bike_high, "engine_hover_low": engine_hover_low, "engine_hover_high": engine_hover_high,
    "engine_heavy_low": engine_heavy_low, "engine_heavy_high": engine_heavy_high,
}


OGG_ONESHOTS = {"verb_shield", "verb_slip", "verb_slam", "shot_rail", "shot_gravity", "shot_lance", "sting_stealth_spot", "sting_stealth_clear", "sting_phase", "sting_chapter"}


def build(out_dir, only=()):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    tmp = tempfile.mkdtemp(prefix="qt_v3_")
    jobs = []
    for name, fn in WAVS.items():
        jobs.append((name, fn, False))
    for name, fn in LOOPS.items():
        jobs.append((name, fn, True))
    for i in range(3):
        jobs.append(("verb_wallrun_%d" % i, lambda i=i: verb_wallrun(1000 + i * 7), False))
    for si, (nm, fn) in enumerate((("roof", step_roof), ("tile", step_tile), ("carpet", step_carpet))):
        for i in range(4):
            jobs.append(("step_%s_%d" % (nm, i), lambda fn=fn, i=i, si=si: fn(1100 + i * 13 + si * 100), False))
    try:
        for name, fn, loop in jobs:
            if want(name):
                x = fn()
                if name in OGG_ONESHOTS:                                            # long tails and stingers: Vorbis keeps the pack small
                    mm.to_ogg(x[None, :], os.path.join(out_dir, name + ".ogg"), 4, tmp)
                    print("%-22s %5.2f s  (ogg)" % (name, len(x) / SR), flush=True)
                    continue
                ma.write_wav(os.path.join(out_dir, name + ".wav"), x, loop=loop)
                print("%-22s %5.2f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)
        shows = []
        for si, st in enumerate(("neon", "vael", "club", "lofi")):
            for k in range(2):
                shows.append(("talk_%s_%d" % (st, k), lambda st=st, k=k, si=si: talk(st, 1200 + si * 50 + k * 9, 3.0 + 0.6 * k)))
        for k in range(3):
            shows.append(("ad_%d" % k, lambda k=k: ad(1300 + k)))
        for name, fn in shows:
            if want(name):
                x = fn()
                mm.to_ogg(x[None, :], os.path.join(out_dir, name + ".ogg"), 2, tmp)
                print("%-22s %5.2f s  (ogg)" % (name, len(x) / SR), flush=True)
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
