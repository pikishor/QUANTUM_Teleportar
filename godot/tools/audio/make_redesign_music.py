#!/usr/bin/env python3
"""Audio redesign, part 2: the adaptive music of Quantum Teleportar (numpy + ffmpeg/libvorbis; run AFTER make_pass2.py, it replaces those files).

One shared grid so that Sfx can stack any theme layer over the five stems and everything stays in time: 128 BPM, 16 bars of 4/4 = exactly 30.000 s (the loop length every
audio test and Sfx.play(fposmod(pos, 30)) rely on). D minor, two bars per chord:
    | Dm9  | Bbmaj7 | Fadd9 | Cadd9 |  i  VI  III VII     (bars 1-8:  restrained groove)
    | Dm   | Gm9    | Bbmaj7| A7b9  |  i  iv  VI  V       (bars 9-16: four on the floor, the V pulls back into the loop start)
Stems (stereo, sample-locked, faded by Sfx per game state): pad (detuned saw voices, filter opening and closing twice per loop), pulse (swung 3+3+2 / up-down arpeggios),
bass (rolling eighths with octave jumps, syncopated second pattern, sidechained to the kick), perc (kick / snare+clap / swung hats / open hats with variation per section and
fills at bars 4, 8, 12 and 16), lead (a written melody over every chord, call and response, ends on C# -> D).
Layers (each exactly one loop; the district layers differ in FEEL on the same grid, not in tempo, so they never drift against the stems):
    music_district_0 neon market  straight 128: dotted FM bells, off-beat shaker, light claps
    music_district_1 foundry      half-time 64: metal clanks on the back-beat, sub drone, growl saw
    music_district_2 rain slums   swung (triplet feel): electric-piano stabs on the off-beats, brushes, vinyl crackle
    music_district_3 glass towers double-time 256 feel: glass arpeggios, high shimmer pad
    music_boss, music_chase, music_night
Mastering of every file: per-stem EQ (high-pass, role-specific shelves), loudness balance (RMS targets, all five together -19.5 dBFS), circular look-ahead limiter (peak of the five
stems summed stays at or under -6 dBFS), Vorbis q4. Run: python3 tools/audio/make_redesign_music.py [out_dir] [--only glob ...]
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
from make_audio import SR, band, expenv, saturate, sine_sweep, white, fft_filter  # noqa: E402
import make_music as mm  # noqa: E402
from make_music import place_c, circ_rev, pingpong, mtof, to_ogg  # noqa: E402
import audio_metrics as am  # noqa: E402

BPM = 128.0
BEAT = 60.0 / BPM
STEP = BEAT / 4.0
BAR = 4 * BEAT
BARS = 16
LOOP = BARS * BAR                         # 30.0 s
N = int(round(LOOP * SR))
SEG = 2 * BAR                             # one chord
SWING = 0.10                              # the off-beat sixteenths of the groove stems land this fraction of a step late
MIX_PEAK_DB = -6.0
DB = lambda x: 10 ** (x / 20.0)  # noqa: E731

CHORDS = [
    dict(root=38, pcs=[2, 5, 9, 0, 4]),   # Dm9
    dict(root=34, pcs=[10, 2, 5, 9]),     # Bbmaj7
    dict(root=41, pcs=[5, 9, 0, 7]),      # Fadd9
    dict(root=36, pcs=[0, 4, 7, 2]),      # Cadd9
    dict(root=38, pcs=[2, 5, 9, 0]),      # Dm
    dict(root=43, pcs=[7, 10, 2, 5, 9]),  # Gm9
    dict(root=34, pcs=[10, 2, 5, 9]),     # Bbmaj7
    dict(root=33, pcs=[9, 1, 4, 7, 10]),  # A7b9
]


def R(seed):
    return np.random.default_rng(seed)


def lp(x, fc, order=2):
    return fft_filter(x, None, fc, order)


def tt(n):
    return np.arange(n) / SR


def tones(pcs, lo, hi):
    return sorted(m for m in range(lo, hi + 1) if m % 12 in pcs)


def voicing(pcs, lo=50):
    return sorted(lo + ((pc - lo) % 12) + (12 if i % 3 == 2 else 0) for i, pc in enumerate(pcs))


def sw(step):
    """Time in seconds of a sixteenth step inside a bar-aligned grid with swing on the odd steps."""
    return step * STEP + (SWING * STEP if step % 2 == 1 else 0.0)


def eq(x, pts):
    """Whole-signal (circular) EQ: pts = [(Hz, dB)...] interpolated on a log-frequency axis."""
    fs = np.array([p[0] for p in pts], dtype=float)
    gs = np.array([p[1] for p in pts], dtype=float)
    f = np.fft.rfftfreq(x.shape[-1], 1.0 / SR)
    g = 10 ** (np.interp(np.log(np.maximum(f, 1.0)), np.log(fs), gs) / 20.0)
    return np.fft.irfft(np.fft.rfft(x, axis=-1) * g, x.shape[-1], axis=-1)


def kick_env(kicks, depth, tau=0.11):
    t = tt(N)
    g = np.ones(N)
    for kt in kicks:
        g = np.minimum(g, 1.0 - depth * np.exp(-((t - kt) % LOOP) / tau))
    return g


KICKS_A = [b * BAR + s * STEP for b in range(8) for s in ((0, 7, 10) if b % 2 == 0 else (0, 7, 10, 14))]
KICKS_B = [b * BAR + s * STEP for b in range(8, 16) for s in (0, 4, 8, 12)]
KICKS = KICKS_A + KICKS_B


# ------------------------------------------------------------------ voices
def saw_voice(f, dur, tail, cut_k=0.0, nh=14, det=0.0, ph=0.0):
    """Band-limited saw by additive harmonics; cut_k > 0 closes the filter over the note (higher harmonics decay faster)."""
    n = int((dur + tail) * SR)
    t = tt(n)
    f = f * 2.0 ** (det / 1200.0)
    v = np.zeros(n)
    for k in range(1, nh + 1):
        if f * k > 15000:
            break
        v += np.sin(2 * np.pi * f * k * t + ph * k) / k * np.exp(-t * cut_k * (k - 1))
    return v


# ------------------------------------------------------------------ stems
def stem_pad(seed):
    chans = []
    for ch in range(2):
        r = R(seed + 31 * ch)
        buf = np.zeros(N)
        for ci, c in enumerate(CHORDS):
            dur = SEG + 1.8
            n = int(dur * SR)
            t = tt(n)
            env = np.minimum(t / 0.7, 1.0) * np.minimum(np.maximum(dur - t, 0) / 1.6, 1.0)
            for m in voicing(c["pcs"], 50) + [c["root"] + 12]:
                v = np.zeros(n)
                for d in (-8.0, 0.0, 7.5):
                    v += saw_voice(mtof(m), dur, 0.0, 0.0, 10, d + r.uniform(-2, 2), r.uniform(0, 6.28))
                place_c(buf, v * env * (0.55 if m < 48 else 0.4), ci * SEG)
        dark, bright = lp(buf, 700, 2), lp(buf, 4200, 2)
        t = tt(N)
        m = 0.5 + 0.5 * np.sin(2 * np.pi * (2.0 / LOOP) * t + ch * 1.3 - 1.0)                       # the filter opens and closes twice per loop
        mixed = dark * (1.0 - m) + bright * m * 0.7
        chans.append(circ_rev(mixed, 3.0, 0.55, 70 + ch, predelay=0.03, damp=0.4))
    out = np.stack(chans)
    return out / np.max(np.abs(out))


def stem_bass():
    out = np.zeros(N)
    pat_syn = [(0, 0, 3), (3, 0, 1), (6, 7, 2), (8, 0, 3), (11, 12, 1), (14, 7, 2)]                 # syncopated
    pat_roll = [(0, 0, 2), (2, 0, 2), (4, 12, 2), (6, 0, 2), (8, 0, 2), (10, 7, 2), (12, 0, 2), (14, 12, 2)]  # rolling eighths with octave jumps
    for ci, c in enumerate(CHORDS):
        for b in range(2):
            pat = pat_syn if (ci < 4 and b == 0) or (ci >= 4 and b == 1 and ci % 2 == 1) else pat_roll
            for k, (s0, semi, ln) in enumerate(pat):
                t0 = ci * SEG + b * BAR + sw(s0)
                f = mtof(c["root"] + semi)
                dur = ln * STEP * 0.9
                n = int((dur + 0.14) * SR)
                t = tt(n)
                env = np.minimum(t / 0.005, 1.0) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.02))
                s = np.sin(2 * np.pi * f * t) + 0.45 * np.sin(2 * np.pi * 2 * f * t + 0.4) + 0.2 * np.sin(2 * np.pi * 3 * f * t)
                s = saturate(s * 1.1, 3.0) + 0.18 * lp(saw_voice(f, dur, 0.14, 4.0, 10), 900, 2)
                place_c(out, s * env, t0, 1.0 if k % 2 == 0 else 0.7)
    out = saturate(out / np.max(np.abs(out)), 1.4)
    return np.stack([out, out])


def drum_kit(seed):
    r = R(seed)
    kick_sw, _ = sine_sweep(0.5, 170, 44)
    kick = np.zeros(_n(0.5))
    kick[:len(kick_sw)] = kick_sw * expenv(len(kick_sw), 0.12)
    kick += band(white(len(kick), seed), 1800, 9000) * expenv(len(kick), 0.0018) * 0.6
    kick = saturate(kick * 1.8, 2.0)
    ns = _n(0.5)
    snare = band(white(ns, seed + 1), 1400, 8000) * expenv(ns, 0.085) + np.sin(2 * np.pi * 192 * tt(ns)) * expenv(ns, 0.05) * 0.6 + band(white(ns, seed + 2), 3500, 10000) * expenv(ns, 0.012) * 0.7
    clap = np.zeros(ns)
    for k in range(4):
        b = band(white(ns, seed + 10 + k), 900, 3800) * expenv(ns, 0.012)
        clap += np.roll(b, int(0.0085 * k * SR)) * (0.7 if k < 3 else 1.0)
    clap += band(white(ns, seed + 15), 900, 3800) * expenv(ns, 0.09) * 0.4
    hat_c = band(white(_n(0.12), seed + 3), 7000, 16000) * expenv(_n(0.12), 0.016)
    hat_o = band(white(_n(0.5), seed + 4), 6000, 16000) * expenv(_n(0.5), 0.14)
    crash = band(white(_n(1.6), seed + 5), 3500, 15000) * expenv(_n(1.6), 0.5)
    toms = []
    for k, f in enumerate((220.0, 180.0, 148.0, 118.0)):
        s, _ = sine_sweep(0.3, f * 1.35, f)
        toms.append(saturate((s * expenv(len(s), 0.1) + band(white(len(s), seed + 20 + k), 700, 3200) * expenv(len(s), 0.008) * 0.3) * 1.5, 1.4))
    return dict(kick=kick, snare=snare, clap=clap, hat_c=hat_c, hat_o=hat_o, crash=crash, toms=toms)


def _n(sec):
    return int(sec * SR)


def stem_perc(seed):
    r = R(seed)
    kit = drum_kit(seed)
    dry = np.zeros(N)
    wetbus = np.zeros(N)
    for bar in range(BARS):
        base = bar * BAR
        sec = 0 if bar < 8 else 1
        fill = bar % 4 == 3
        kicks = ((0, 7, 10) + ((14,) if bar % 2 else ())) if sec == 0 else (0, 4, 8, 12)
        for s in kicks:
            place_c(dry, kit["kick"], base + sw(s), 1.0 if s % 4 == 0 else 0.8)
        if sec == 1 and bar % 2 == 1:
            place_c(dry, kit["kick"], base + sw(15), 0.6)
        for s in (4, 12):
            if fill and s == 12 and bar in (7, 15):
                continue
            place_c(wetbus, kit["snare"], base + sw(s), 0.9)
            place_c(wetbus, kit["clap"], base + sw(s) + 0.002, 0.6 if sec == 0 else 0.8)
        if sec == 1:
            for s in (7, 15):
                place_c(wetbus, kit["snare"], base + sw(s), 0.22 * r.uniform(0.7, 1.0))             # ghost notes
        for s in range(16):
            if sec == 0 and s % 2 == 1 and s not in (7, 15):
                continue
            vel = (0.42 if s % 4 == 0 else 0.3 if s % 2 == 0 else 0.2) * r.uniform(0.8, 1.0)
            place_c(dry, kit["hat_c"], base + sw(s), vel)
        place_c(dry, kit["hat_o"], base + sw(14 if sec == 0 else 6), 0.3)
        if sec == 1:
            place_c(dry, kit["hat_o"], base + sw(14), 0.26)
        if fill:                                                                                    # a snare roll, a tom run on the 8 and 16 bars
            roll = range(12, 16) if bar in (3, 11) else range(8, 16)
            for j, s in enumerate(roll):
                place_c(wetbus, kit["snare"], base + s * STEP, 0.35 + 0.1 * j)
            if bar in (7, 15):
                for k, tm in enumerate(kit["toms"]):
                    place_c(dry, tm, base + (12 + k) * STEP, 0.7)
        if bar % 8 == 0:
            place_c(dry, kit["crash"], base, 0.28)
    wetbus = circ_rev(wetbus, 0.8, 0.3, 90, predelay=0.012)
    mono = saturate((dry + wetbus) / np.max(np.abs(dry + wetbus)), 1.3)
    pan = np.roll(mono, int(0.0004 * SR))
    return np.stack([mono, pan])


def stem_pulse(seed):
    r = R(seed)
    chans = []
    pat_a = [0, 2, 4, 1, 3, 5, 2, 4, 0, 2, 4, 1, 3, 5, 2, 4]                  # 3 + 3 + 2 feel
    pat_b = [0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 5, 4, 3, 2]                  # up and down
    accent_a = [1.0, 0.4, 0.55, 0.9, 0.4, 0.55, 1.0, 0.45, 0.7, 0.4, 0.55, 0.95, 0.4, 0.55, 0.85, 0.5]
    accent_b = [1.0, 0.45, 0.6, 0.45, 0.9, 0.45, 0.6, 0.45, 1.0, 0.45, 0.6, 0.45, 0.9, 0.45, 0.6, 0.5]
    for ch in range(2):
        out = np.zeros(N)
        det = -4.0 if ch == 0 else 4.0
        for ci, c in enumerate(CHORDS):
            pool = tones(c["pcs"], 60, 88)[:7]
            pat, acc = (pat_a, accent_a) if ci < 4 else (pat_b, accent_b)
            for st in range(32):
                if ci % 2 == 1 and st >= 16 and st % 16 in (5, 13) and r.random() < 0.7:
                    continue
                m = pool[pat[st % 16] % len(pool)] + (12 if (st // 8) % 4 == 3 and pat[st % 16] < 2 else 0)
                f = mtof(m)
                n = int(0.9 * SR)
                t = tt(n)
                v = np.zeros(n)
                for k in range(1, 11):
                    if f * k > 14000:
                        break
                    v += np.sin(2 * np.pi * f * 2.0 ** (det / 1200.0) * k * t) / k * np.exp(-t * 6.0 * (k - 1))
                v *= np.minimum(t / 0.002, 1.0) * np.exp(-t / 0.15)
                place_c(out, v, ci * SEG + sw(st % 16) + (st // 16) * BAR, 0.5 * acc[st % 16])
        chans.append(out)
    L, R_ = pingpong(chans[0], STEP * 3, 0.45, 4, 3200.0)
    L2, R2 = pingpong(chans[1], STEP * 3, 0.45, 4, 3200.0)
    return np.stack([circ_rev(L + R2 * 0.3, 1.4, 0.28, 80), circ_rev(R_ + L2 * 0.3, 1.4, 0.28, 81)])


LEAD = [
    [(0, 74, 3), (4, 77, 3), (8, 81, 4), (14, 79, 2), (16, 77, 4), (22, 76, 2), (24, 74, 8)],
    [(0, 74, 3), (4, 77, 2), (7, 74, 1), (8, 72, 4), (14, 70, 2), (16, 74, 6), (24, 77, 8)],
    [(0, 77, 3), (4, 81, 3), (8, 79, 4), (14, 77, 2), (16, 76, 4), (20, 72, 4), (24, 77, 8)],
    [(0, 79, 4), (6, 76, 2), (8, 74, 4), (14, 72, 2), (16, 79, 3), (20, 81, 3), (24, 79, 8)],
    [(0, 74, 4), (4, 81, 4), (10, 79, 2), (12, 77, 4), (18, 74, 2), (20, 77, 4), (26, 76, 6)],
    [(0, 79, 3), (4, 82, 3), (8, 81, 4), (14, 79, 2), (16, 77, 4), (20, 74, 4), (26, 79, 6)],
    [(0, 82, 3), (4, 81, 3), (8, 77, 4), (14, 74, 2), (16, 77, 4), (22, 81, 2), (24, 82, 8)],
    [(0, 81, 3), (4, 73, 3), (8, 76, 4), (12, 82, 2), (14, 81, 2), (16, 73, 6), (24, 74, 8)],
]


def stem_lead(seed):
    out = np.zeros(N)
    for ci, ph in enumerate(LEAD):
        for st, m, ln in ph:
            f = mtof(m)
            dur = ln * STEP
            n = int((dur + 0.7) * SR)
            t = tt(n)
            vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.6 * t) * np.minimum(t / 0.3, 1.0)
            phs = 2 * np.pi * np.cumsum(f * vib) / SR
            v = np.zeros(n)
            for d in (-7.0, 0.0, 7.0):
                pd = phs * 2.0 ** (d / 1200.0)
                v += np.sin(pd + 1.0 * np.sin(pd) + 0.45 * np.sin(2 * pd))
            env = np.minimum(t / 0.02, 1.0) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.1)) * (0.8 + 0.2 * np.exp(-t / 0.2))
            place_c(out, v * env, ci * SEG + (st // 16) * BAR + sw(st % 16), 0.4)
    out = lp(out, 4200, 2)
    L, R_ = pingpong(out, STEP * 3, 0.5, 5, 2800.0)
    return np.stack([circ_rev(L, 1.9, 0.38, 100), circ_rev(R_, 1.9, 0.38, 101)])


STEMS = ("pad", "pulse", "bass", "perc", "lead")
STEM_RMS_DB = {"pad": -22.0, "pulse": -25.0, "bass": -23.0, "perc": -23.5, "lead": -26.0}
SC_DEPTH = {"pad": 0.35, "pulse": 0.18, "bass": 0.7, "perc": 0.0, "lead": 0.1}
STEM_EQ = {
    "pad": [(20, -40), (90, -10), (200, -2), (500, 0), (6000, -1), (12000, -9), (20000, -20)],
    "pulse": [(20, -40), (150, -18), (300, -3), (1500, 1), (6000, 0), (12000, -6), (20000, -14)],
    "bass": [(20, -30), (40, -6), (70, 2), (200, 0), (700, -8), (2500, -24), (20000, -40)],
    "perc": [(20, -30), (45, -3), (80, 1), (300, -2), (3000, 1), (9000, 0), (16000, -3), (20000, -8)],
    "lead": [(20, -40), (200, -20), (400, -3), (1500, 1), (5000, 0), (10000, -6), (20000, -18)],
}


def build_stems():
    raw = {"pad": stem_pad(200), "pulse": stem_pulse(210), "bass": stem_bass(), "perc": stem_perc(220), "lead": stem_lead(230)}
    for k in raw:
        if SC_DEPTH[k] > 0:
            raw[k] = raw[k] * kick_env(KICKS, SC_DEPTH[k])[None, :]
        raw[k] = eq(raw[k], STEM_EQ[k])
        raw[k] = raw[k] / (np.sqrt(np.mean(raw[k] ** 2)) + 1e-9) * DB(STEM_RMS_DB[k])
    total = sum(raw.values())
    gain = DB(-19.5) / np.sqrt(np.mean(total ** 2))
    for k in raw:
        raw[k] = am.limiter(raw[k] * gain, -15.0, 0.006, wrap=True)                                  # every stem rounds its own rare peaks
    total = sum(raw.values())
    scale = min(1.0, DB(MIX_PEAK_DB) / np.max(np.abs(total)))
    out = {k: am.limiter(raw[k] * scale, MIX_PEAK_DB - 0.5, 0.004, wrap=True) for k in raw}
    return {k: np.stack([fft_filter(c, lo=32.0, order=4) for c in v]) for k, v in out.items()}


# ------------------------------------------------------------------ layers
LAYER_RMS_DB = -23.0
LAYER_PEAK_DB = -8.0


def fit(x, eqpts=None):
    if eqpts:
        x = eq(x, eqpts)
    x = x - np.mean(x, axis=-1, keepdims=True)
    g = min(DB(LAYER_RMS_DB) / (np.sqrt(np.mean(x ** 2)) + 1e-12), DB(LAYER_PEAK_DB) / (np.max(np.abs(x)) + 1e-12))
    return np.stack([fft_filter(c, lo=40.0, order=4) for c in am.limiter(x * g, LAYER_PEAK_DB, 0.004, wrap=True)])


def bell(f, dur=1.0, ratio=3.01, index=1.6, tau=0.3, itau=0.08):
    return ma.fm_bell(dur, f, ratio, index, tau, itau)


def ep(f, dur=1.2):
    """Electric piano: two FM operators with a fast attack knock."""
    n = int(dur * SR)
    t = tt(n)
    mod = np.sin(2 * np.pi * f * t) * 1.4 * np.exp(-t / 0.18)
    v = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / 0.55) + 0.25 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t / 0.012)
    return v


def layer_district(k):
    r = R(700 + k)
    out = np.zeros(N)
    if k == 0:                                           # neon market: dotted FM bells, a shaker on the off-beats, light claps
        for ci, c in enumerate(CHORDS):
            pool = tones(c["pcs"], 72, 96)
            for st in range(0, 32, 3):
                if r.random() < 0.25:
                    continue
                place_c(out, bell(mtof(pool[(st // 3 + ci) % len(pool)]), 1.4, 3.01, 1.6, 0.35), ci * SEG + (st // 16) * BAR + sw(st % 16), 0.45)
        shaker = band(white(_n(0.08), 7101), 5000, 14000) * expenv(_n(0.08), 0.02)
        for bar in range(BARS):
            for s in range(2, 16, 4):
                place_c(out, shaker, bar * BAR + sw(s), 0.35 * r.uniform(0.7, 1.0))
        L, R_ = pingpong(lp(out, 7500, 2), STEP * 3, 0.5, 5, 3500.0)
        return fit(np.stack([L, R_]))
    if k == 1:                                           # foundry: half-time clanks on the back-beat, a detuned sub drone, a growl saw
        n = _n(0.5)
        clank = band(white(n, 710), 900, 5200) * expenv(n, 0.06) * np.sin(2 * np.pi * 173.0 * tt(n)) * 1.4 + band(white(n, 711), 2500, 8000) * expenv(n, 0.01) * 0.5
        for bar in range(BARS):
            for s, g in ((8, 1.0), (14, 0.45)) if bar % 2 == 0 else ((8, 1.0), (11, 0.4)):
                place_c(out, clank, bar * BAR + s * STEP, g)
        for ci, c in enumerate(CHORDS):
            dur = SEG + 0.8
            t = tt(int(dur * SR))
            env = np.minimum(t / 0.8, 1.0) * np.minimum((dur - t) / 0.8, 1.0)
            f = mtof(c["root"] - 12)
            sub = sum(np.sin(2 * np.pi * f * 2.0 ** (d / 1200.0) * t) + 0.4 * np.sin(2 * np.pi * 2 * f * t) for d in (-9, 0, 9))
            place_c(out, saturate(sub * env * 0.5, 2.0), ci * SEG, 1.0)
            for b in range(2):
                gr = saw_voice(mtof(c["root"]), 0.9 * BEAT * 2, 0.1, 3.0, 12)
                gr = saturate(lp(gr, 1500, 2) * 1.5, 2.2)
                place_c(out, gr, ci * SEG + b * BAR, 0.5)
                place_c(out, gr, ci * SEG + b * BAR + 2 * BEAT, 0.4)
        out = saturate(out / np.max(np.abs(out)), 1.3)
        return fit(np.stack([circ_rev(out, 1.1, 0.3, 720), circ_rev(np.roll(out, 211), 1.1, 0.3, 721)]))
    if k == 2:                                           # rain slums: swung electric-piano stabs on the off-beats, brushes, vinyl crackle
        saved = globals()["SWING"]
        globals()["SWING"] = 0.33
        brush = band(white(_n(0.14), 7201), 3500, 11000) * expenv(_n(0.14), 0.045)
        for ci, c in enumerate(CHORDS):
            ch = voicing(c["pcs"], 55)
            for bar in range(2):
                for s in (3, 7, 11) if bar == 0 else (3, 10):
                    for m in ch[:4]:
                        place_c(out, ep(mtof(m)), ci * SEG + bar * BAR + sw(s), 0.28)
                for s in range(0, 16, 2):
                    place_c(out, brush, ci * SEG + bar * BAR + sw(s), 0.22 * r.uniform(0.6, 1.0))
        globals()["SWING"] = saved
        crackle = np.zeros(N)
        for _ in range(900):
            tk = band(r.standard_normal(_n(0.01)), 1500, 9000) * np.exp(-np.arange(_n(0.01)) / SR / 0.002)
            place_c(crackle, tk, r.uniform(0, LOOP), r.uniform(0.02, 0.12))
        out = lp(out, 5500, 2)
        L, R_ = pingpong(out, STEP * 4, 0.4, 4, 2400.0)
        return fit(np.stack([circ_rev(L, 2.2, 0.45, 730) + crackle * 0.6, circ_rev(R_, 2.2, 0.45, 731) + np.roll(crackle, 777) * 0.6]))
    if k == 3:                                           # glass towers: double-time glass arpeggios, a high shimmer pad
        for ci, c in enumerate(CHORDS):
            pool = tones(c["pcs"], 76, 100)
            for st in range(64):
                if r.random() < 0.18:
                    continue
                place_c(out, bell(mtof(pool[(st * 3 + ci) % len(pool)]), 0.5, 4.0, 1.0, 0.12, 0.05), ci * SEG + st * STEP * 0.5, 0.3 * (1.0 if st % 4 == 0 else 0.6))
            dur = SEG + 1.0
            t = tt(int(dur * SR))
            env = np.minimum(t / 0.9, 1.0) * np.minimum((dur - t) / 0.9, 1.0)
            pad = sum(np.sin(2 * np.pi * mtof(m + 12) * 2.0 ** (d / 1200.0) * t) for m in voicing(c["pcs"], 62)[:3] for d in (-6, 6))
            place_c(out, pad * env * 0.12, ci * SEG, 1.0)
        L, R_ = pingpong(lp(out, 9000, 2), STEP * 3, 0.5, 5, 4500.0)
        return fit(np.stack([circ_rev(L, 2.6, 0.5, 740), circ_rev(R_, 2.6, 0.5, 741)]))
    raise ValueError(k)


def layer_boss():
    out = np.zeros(N)
    r = R(750)
    for ci, c in enumerate(CHORDS):
        f = mtof(c["root"] + 12)
        gr = saturate(lp(saw_voice(f, STEP, 0.04, 10.0, 14), 2600, 2) * 2.2, 2.8)
        for bar in range(2):
            for s in range(16):
                if s % 4 == 3 and bar == 1:
                    continue
                place_c(out, gr, ci * SEG + bar * BAR + s * STEP, 0.55 if s % 4 == 0 else 0.35)
        stab = sum(saw_voice(mtof(c["root"] + 24 + d), 0.2, 0.1, 6.0, 10) for d in (0, 6, 7))                # a tritone stab on the "and" of 2
        place_c(out, saturate(lp(stab, 3500, 2) * 0.6, 2.0), ci * SEG + 6 * STEP, 0.6)
        place_c(out, saturate(lp(stab, 3500, 2) * 0.6, 2.0), ci * SEG + BAR + 10 * STEP, 0.5)
        n = _n(0.8)
        sub_s, _ = sine_sweep(0.5, 90, 30)
        sub = np.zeros(n)
        sub[:len(sub_s)] = sub_s * expenv(len(sub_s), 0.2)
        hit = band(white(n, 751 + ci), 200, 3000) * expenv(n, 0.2) * 0.8 + saturate(sub * 1.5, 1.5) * 0.9
        place_c(out, hit, ci * SEG, 0.8)
    rise = band(white(_n(3.0), 760), 300, 9000) * np.linspace(0, 1, _n(3.0)) ** 2.0
    place_c(out, rise, LOOP - 3.0, 0.25)
    out = saturate(out / np.max(np.abs(out)), 1.4)
    return fit(np.stack([circ_rev(out, 1.0, 0.25, 750), circ_rev(np.roll(out, 99), 1.0, 0.25, 751)]))


def layer_chase():
    out = np.zeros(N)
    r = R(770)
    clap_n = _n(0.3)
    clap = sum(np.roll(band(white(clap_n, 771 + k), 900, 3800) * expenv(clap_n, 0.012), int(0.0085 * k * SR)) for k in range(4))
    hat = band(white(_n(0.05), 775), 8000, 16000) * expenv(_n(0.05), 0.012)
    for ci, c in enumerate(CHORDS):
        f = mtof(c["root"] + 12)
        for bar in range(2):
            base = ci * SEG + bar * BAR
            for s in range(16):
                m = f * (2.0 if s % 8 == 5 else 1.0)
                n = int(0.12 * SR)
                t = tt(n)
                v = saturate(np.sin(2 * np.pi * m * t) + 0.5 * np.sin(2 * np.pi * 2 * m * t) + 0.25 * np.sin(2 * np.pi * 3 * m * t), 2.4) * np.exp(-t / 0.055)
                place_c(out, v, base + s * STEP, 0.55 if s % 2 == 0 else 0.4)
                place_c(out, hat, base + s * STEP, 0.3 if s % 4 else 0.45)
            for s in (4, 12):
                place_c(out, clap, base + s * STEP, 0.7)
            if bar == 1 and ci % 2 == 1:
                for j in range(8, 16):
                    place_c(out, clap, base + j * STEP, 0.15 + 0.06 * (j - 8))
    out = saturate(out / np.max(np.abs(out)), 1.3)
    return fit(np.stack([circ_rev(out, 0.7, 0.2, 780), circ_rev(np.roll(out, 131), 0.7, 0.2, 781)]), [(20, -40), (100, -4), (400, 0), (6000, 1), (16000, -4), (20000, -12)])


def layer_night():
    L = np.zeros(N)
    Rr = np.zeros(N)
    r = R(790)
    for ci, c in enumerate(CHORDS):
        dur = SEG + 2.4
        n = int(dur * SR)
        t = tt(n)
        env = np.minimum(t / 1.6, 1.0) * np.minimum((dur - t) / 2.0, 1.0)
        for m in voicing(c["pcs"], 45):
            for ch, buf in enumerate((L, Rr)):
                v = sum(np.sin(2 * np.pi * mtof(m) * 2.0 ** ((d + r.uniform(-3, 3)) / 1200.0) * t + r.uniform(0, 6)) * (1.0 / (1 + 0.6 * k)) for k, d in enumerate((-9, 0, 9)))
                v += 0.35 * np.sin(2 * np.pi * mtof(m) * 2 * t + r.uniform(0, 6))
                place_c(buf, v * env * 0.4, ci * SEG)
        pool = tones(c["pcs"], 72, 91)
        for j in range(4):
            place_c(L if j % 2 == 0 else Rr, bell(mtof(pool[(j * 2 + ci) % len(pool)]), 2.0, 2.0, 0.9, 0.9, 0.2), ci * SEG + j * BEAT * 2 + 0.0, 0.2)
    t = tt(N)
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * (4.0 / LOOP) * t)
    L, Rr = lp(L * lfo, 1800, 2), lp(Rr * np.roll(lfo, 6000), 1800, 2)
    return fit(np.stack([circ_rev(L, 3.5, 0.5, 790), circ_rev(Rr, 3.5, 0.5, 791)]))


def build(out_dir, only):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    tmp = tempfile.mkdtemp(prefix="qt_music_")
    try:
        if any(want("music_" + s) for s in STEMS):
            stems = build_stems()
            for s, x in stems.items():
                if want("music_" + s):
                    to_ogg(x, os.path.join(out_dir, "music_%s.ogg" % s), 4, tmp)
                    print("music_%-6s %5.1f s  peak %6.1f  LU %6.1f  crest %4.1f  centroid %5.0f Hz  seam %.2f" % (s, x.shape[1] / SR, am.peak_db(x), am.lufs_like(x), am.crest_db(x), am.centroid_hz(x), mm.seam_ratio(x)), flush=True)
            tot = sum(stems.values())
            print("five stems summed: peak %.1f dBFS  LU %.1f  crest %.1f dB" % (am.peak_db(tot), am.lufs_like(tot), am.crest_db(tot)))
        jobs = [("music_district_%d" % k, lambda k=k: layer_district(k)) for k in range(4)] + [("music_boss", layer_boss), ("music_chase", layer_chase), ("music_night", layer_night)]
        for name, fn in jobs:
            if want(name):
                x = fn()
                to_ogg(x, os.path.join(out_dir, name + ".ogg"), 4, tmp)
                print("%-16s %5.1f s  peak %6.1f  LU %6.1f  crest %4.1f  centroid %5.0f Hz  seam %.2f" % (name, x.shape[1] / SR, am.peak_db(x), am.lufs_like(x), am.crest_db(x), am.centroid_hz(x), mm.seam_ratio(x)), flush=True)
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
