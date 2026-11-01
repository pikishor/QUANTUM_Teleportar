#!/usr/bin/env python3
"""Wave 17 audio depth for Quantum Teleportar (numpy + ffmpeg/libvorbis only).

  * music layers, each exactly one 30 s loop (same grid as the five stems, so Sfx can start them at the stems' playback position and they stay in time):
        music_district_0..3   a colour per district (neon market, foundry, rain slums, glass towers)
        music_boss            the Overseer theme (distorted root riff, hits, tritone stabs)
        music_chase           the driving chase theme (sixteenth bass, claps, hats)
  * combat intensity stingers: sting_combat_0 (alert), sting_combat_1 (firefight), sting_combat_2 (siege), sting_boss, sting_chase
  * alien barks (synthesised formant voices, no speech): alien_bark_0..3 (growls), alien_bark_4..7 (chitters), alien_yelp_0..1 (hurt)
  * ui_notify, ui_hover, airship_hum (OGG loop), wind_howl (OGG loop, the storm bed)
Run: python3 tools/audio/make_depth.py [out_dir] [--only glob ...]   (also called by make_audio.py's build chain through build_assets.sh)
Music and loops go to OGG (about 2 MB for everything); one-shots stay 16-bit mono WAV like the rest of the library.
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
from make_library import R, db, lp, pnoise  # noqa: E402
import make_music as mm  # noqa: E402
from make_music import N, STEP, BAR, SEG, CHORDS, mtof, place_c, circ_rev, pingpong  # noqa: E402

LAYER_RMS_DB = -23.0         # one layer on its own; the layer player adds it on top of the stems at about -6 dB
LAYER_PEAK_DB = -8.0


def _t(n):
    return np.arange(n) / SR


def _stereo(left, right=None):
    return np.stack([left, left if right is None else right])


def _fit(x, rms_db=LAYER_RMS_DB, peak_db=LAYER_PEAK_DB):
    x = x - np.mean(x, axis=-1, keepdims=True)
    g = db(rms_db) / (np.sqrt(np.mean(x ** 2)) + 1e-12)
    g = min(g, db(peak_db) / (np.max(np.abs(x)) + 1e-12))
    return mm.fft_filter_stereo(x * g, 40.0)


# ------------------------------------------------------------------ music layers
def layer_district(k):
    r = R(700 + k)
    out = np.zeros(N)
    if k == 0:                                           # neon market: bright FM bells in a dotted pattern
        for ci, c in enumerate(CHORDS):
            for st in range(0, 48, 3):
                if r.random() < 0.3:
                    continue
                m = c["arp"][(st // 3 + ci) % len(c["arp"])] + 24
                place_c(out, fm_bell(1.4, mtof(m), 3.01, 1.6, 0.35, 0.08), ci * SEG + st * STEP, 0.45)
        L, R_ = pingpong(lp(out, 6500, 2), STEP * 3, 0.55, 5, 3500.0)
    elif k == 1:                                         # foundry: clanking metal on the beat over a detuned sub drone
        clank = band(white(int(0.5 * SR), 710), 900, 5200) * expenv(int(0.5 * SR), 0.06)
        n = len(clank)
        clank = clank * np.sin(2 * np.pi * 173.0 * _t(n)) * 1.4 + band(white(n, 711), 2500, 8000) * expenv(n, 0.01) * 0.4
        for ci in range(4):
            for b in range(3):
                base = ci * SEG + b * BAR
                for s, g in ((0, 1.0), (6, 0.5), (11, 0.7)):
                    place_c(out, clank, base + s * STEP, g)
            c = CHORDS[ci]
            dur = SEG + 1.0
            t = _t(int(dur * SR))
            env = np.minimum(t / 1.0, 1.0) * np.minimum((dur - t) / 1.0, 1.0)
            f = mtof(c["root"] - 12)
            sub = sum(np.sin(2 * np.pi * f * 2.0 ** (d / 1200.0) * t) + 0.4 * np.sin(2 * np.pi * 2 * f * t) for d in (-9, 0, 9))
            place_c(out, saturate(sub * env * 0.5, 2.0), ci * SEG, 1.0)
        out = saturate(out / np.max(np.abs(out)), 1.3)
        L, R_ = circ_rev(out, 1.2, 0.35, 720), circ_rev(np.roll(out, 211), 1.2, 0.35, 721)
    elif k == 2:                                         # rain slums: sparse plucks, a breathing noise swell, a lot of room
        for ci, c in enumerate(CHORDS):
            for st in (0, 9, 20, 27, 38):
                m = c["pad"][(st + ci) % len(c["pad"])] + 12
                t = _t(int(2.2 * SR))
                f = mtof(m)
                v = sum(np.sin(2 * np.pi * f * h * t + 0.3 * h) / h ** 1.6 for h in range(1, 7)) * np.exp(-t / 0.55)
                place_c(out, v, ci * SEG + st * STEP, 0.6)
            dur = SEG
            n = int(dur * SR)
            t = _t(n)
            sw = band(white(n, 730 + ci), 700, 2400) * np.sin(np.pi * t / dur) ** 2
            place_c(out, sw, ci * SEG, 0.35)
        L, R_ = circ_rev(lp(out, 4200, 2), 4.2, 0.75, 731), circ_rev(lp(np.roll(out, 301), 4200, 2), 4.2, 0.75, 732)
    else:                                                # glass towers: high shimmer, fifths, slow tremolo
        for ci, c in enumerate(CHORDS):
            dur = SEG + 2.0
            t = _t(int(dur * SR))
            env = np.minimum(t / 2.0, 1.0) * np.minimum((dur - t) / 2.0, 1.0)
            v = np.zeros_like(t)
            for m in c["pad"][1:]:
                for off in (24, 31):
                    f = mtof(m + off)
                    v += np.sin(2 * np.pi * f * t + r.uniform(0, 6.28)) * (0.5 + 0.5 * np.sin(2 * np.pi * (1 / 6.0) * t + r.uniform(0, 6.28)))
            place_c(out, v * env, ci * SEG, 0.25)
        air = band(white(N, 740), 5500, 14000) * (0.5 + 0.5 * np.sin(2 * np.pi * 4 / mm.LOOP * _t(N)))
        out = out + air * 0.25
        L, R_ = circ_rev(out, 3.0, 0.6, 741), circ_rev(np.roll(out, 401), 3.0, 0.6, 742)
    return _fit(_stereo(L, R_))


def layer_boss():
    r = R(760)
    out = np.zeros(N)
    hits = np.zeros(N)
    nk = int(0.7 * SR)
    sw, _ = sine_sweep(0.7, 120, 38)
    hit = np.zeros(nk)
    hit[:len(sw)] = sw * expenv(len(sw), 0.2)
    hit = saturate(hit * 1.8, 2.4) + band(white(nk, 761), 200, 2500) * expenv(nk, 0.05) * 0.5
    for ci, c in enumerate(CHORDS):
        for b in range(3):
            base = ci * SEG + b * BAR
            for s in range(0, 16, 2):                                   # eighth-note distorted root riff, octave kicks on the off-beats
                m = c["root"] + (12 if s in (6, 14) else 0)
                f = mtof(m)
                n = int(STEP * 2 * 0.95 * SR) + int(0.1 * SR)
                t = _t(n)
                env = np.minimum(t / 0.004, 1.0) * np.where(t < STEP * 1.8, 1.0, np.exp(-(t - STEP * 1.8) / 0.02))
                saw = sum(np.sin(2 * np.pi * f * h * t) / h for h in range(1, 14))
                place_c(out, saturate(saw * env * 0.8, 4.0), base + s * STEP, 0.7 if s % 4 == 0 else 0.5)
            place_c(hits, hit, base, 1.0)
            place_c(hits, hit, base + 10 * STEP, 0.8)
            tri = mtof(c["root"] + 24)                                  # tritone stab on every bar's beat one
            t = _t(int(0.8 * SR))
            stab = (np.sin(2 * np.pi * tri * t) + np.sin(2 * np.pi * tri * 1.4142 * t)) * np.exp(-t / 0.18)
            place_c(hits, saturate(stab, 2.0), base, 0.35)
            if b == 2:
                for k2, f in enumerate((190.0, 150.0, 120.0, 95.0)):
                    ts, _ = sine_sweep(0.3, f * 1.4, f)
                    place_c(hits, saturate(ts * expenv(len(ts), 0.1) * 1.4, 1.5), base + (12 + k2) * STEP, 0.7)
    mono = lp(out, 3400, 2) + hits * 0.8
    L, R_ = circ_rev(mono, 1.3, 0.3, 762), circ_rev(np.roll(mono, 151), 1.3, 0.3, 763)
    return _fit(_stereo(L, R_), rms_db=-21.0)


def layer_chase():
    r = R(780)
    out = np.zeros(N)
    perc = np.zeros(N)
    clap = band(white(int(0.3 * SR), 781), 1100, 6500) * expenv(int(0.3 * SR), 0.05)
    hat = band(white(int(0.1 * SR), 782), 7000, 16000) * expenv(int(0.1 * SR), 0.014)
    for ci, c in enumerate(CHORDS):
        for b in range(3):
            base = ci * SEG + b * BAR
            for s in range(16):
                m = c["root"] + 12 + (7 if s % 8 == 5 else (12 if s % 4 == 3 else 0))
                f = mtof(m)
                t = _t(int(STEP * 0.9 * SR) + int(0.05 * SR))
                env = np.minimum(t / 0.003, 1.0) * np.where(t < STEP * 0.8, 1.0, np.exp(-(t - STEP * 0.8) / 0.012))
                saw = sum(np.sin(2 * np.pi * f * h * t) / h for h in range(1, 10))
                place_c(out, saturate(saw * env, 2.6), base + s * STEP, 0.55 if s % 4 else 0.8)
                place_c(perc, hat, base + s * STEP, (0.35 if s % 2 else 0.2) * r.uniform(0.8, 1.0))
            for s in (4, 12):
                place_c(perc, clap, base + s * STEP, 0.8)
    mono = lp(out, 4200, 2) * mm.kick_env([(ci * 3 + b) * BAR + s * STEP for ci in range(4) for b in range(3) for s in (0, 4, 8, 12)], 0.4, 0.06) + perc * 0.7
    L, R_ = pingpong(mono, STEP * 3, 0.3, 3, 3800.0)
    return _fit(_stereo(circ_rev(L, 0.9, 0.25, 783), circ_rev(R_, 0.9, 0.25, 784)), rms_db=-21.0)


# ------------------------------------------------------------------ stingers (WAV one-shots)
def _riser(dur, f0, f1, seed, noise=0.5):
    n = int(dur * SR)
    t = _t(n)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = np.cumsum(f) / SR * 2 * np.pi
    tone = sum(np.sin(h * ph) / h for h in range(1, 8))
    tone = lp(tone, 4000, 2)
    nz = band(white(n, seed), 1500, 9000) * (t / dur) ** 2 * noise
    return (tone * (t / dur) ** 1.3 + nz) * np.minimum((dur - t) / 0.03, 1.0)


def _slam(dur, f0, seed):
    n = int(dur * SR)
    sw, _ = sine_sweep(dur, f0 * 2.5, f0)
    x = np.zeros(n)
    x[:len(sw)] = sw * expenv(len(sw), dur * 0.3)
    return saturate(x * 1.6, 2.2) + band(white(n, seed), 120, 3000) * expenv(n, 0.08) * 0.5


def sting_combat(level):
    seeds = (800, 810, 820)
    rise = (0.5, 0.8, 1.1)[level]
    body = (0.6, 0.9, 1.3)[level]
    r = _riser(rise, 180.0 * (1 + level * 0.2), 700.0 * (1 + level * 0.3), seeds[level])
    s = _slam(body, (90, 70, 55)[level], seeds[level] + 1)
    x = np.concatenate([r, np.zeros(int(0.01 * SR))])
    buf = np.zeros(len(x) + len(s))
    buf[:len(x)] += x * 0.7
    buf[len(x) - int(0.01 * SR):len(x) - int(0.01 * SR) + len(s)] += s
    if level == 2:                                       # a stab chord over the slam
        t = _t(int(1.2 * SR))
        for m in (50, 53, 56, 62):
            buf[len(x):len(x) + len(t)] += saturate(np.sin(2 * np.pi * mtof(m) * t + 0.5 * np.sin(2 * np.pi * mtof(m) * t)) * np.exp(-t / 0.5), 1.8) * 0.25
    out = ml.wet(buf, 1.4, mix=0.3, predelay=0.02, damp=0.6, seed=830 + level, early=0.3)
    return ml.done(out, -12.0, 40.0, fout=0.3, max_len=4.0)


def sting_boss():
    n = int(3.4 * SR)
    t = _t(n)
    f = 41.2 * (1 + 0.03 * np.sin(2 * np.pi * 0.7 * t))
    ph = np.cumsum(f) / SR * 2 * np.pi
    low = saturate(sum(np.sin(h * ph) / h for h in range(1, 12)) * np.minimum(t / 0.3, 1.0) * np.exp(-t / 1.4), 3.0)
    hit = np.zeros(n)
    s = _slam(1.2, 48, 840)
    hit[:len(s)] = s
    stab = np.zeros(n)
    for m in (38, 44, 50):
        stab += saturate(np.sin(2 * np.pi * mtof(m) * t * (1 + 0.002 * np.sin(5 * t))) * np.exp(-t / 0.9), 2.4) * 0.5
    x = low * 0.6 + hit + stab * 0.5
    out = ml.wet(x, 2.2, mix=0.4, predelay=0.03, damp=0.6, seed=845, early=0.3)
    return ml.done(out, -10.0, 30.0, fout=0.5, max_len=4.2)


def sting_chase():
    r = _riser(0.6, 400, 1300, 850, 0.3)
    n = int(0.7 * SR)
    t = _t(n)
    sirenf = np.where((t % 0.25) < 0.125, 700.0, 940.0)
    ph = np.cumsum(sirenf) / SR * 2 * np.pi
    sir = saturate(np.sin(ph) + 0.4 * np.sin(2 * ph), 1.6) * np.minimum((0.7 - t) / 0.1, 1.0) * 0.5
    s = _slam(0.8, 80, 851)
    buf = np.concatenate([r * 0.6, np.zeros(len(s))])
    buf[len(r) - int(0.01 * SR):len(r) - int(0.01 * SR) + len(s)] += s
    buf[len(r):len(r) + n] += lp(sir, 3000, 2)
    out = ml.wet(buf, 1.1, mix=0.25, predelay=0.015, damp=0.6, seed=852, early=0.3)
    return ml.done(out, -12.0, 60.0, fout=0.25, max_len=2.6)


# ------------------------------------------------------------------ alien barks
def _formants(src, f1, f2, q1=8.0, q2=10.0):
    """Two moving resonators (time-varying centre frequencies, one-pole state variable filters); f1/f2 are per-sample frequency arrays."""
    out = np.zeros_like(src)
    for f, q, g in ((f1, q1, 1.0), (f2, q2, 0.7)):
        w = 2 * np.sin(np.pi * np.minimum(f, SR / 6) / SR)
        lo = 0.0
        bp = 0.0
        y = np.zeros_like(src)
        d = 1.0 / q
        for i in range(len(src)):
            lo += w[i] * bp
            hi = src[i] - lo - d * bp
            bp += w[i] * hi
            y[i] = bp
        out += y * g
    return out


def alien_growl(seed):
    r = R(seed)
    dur = r.uniform(0.35, 0.6)
    n = int(dur * SR)
    t = _t(n)
    f0 = r.uniform(55, 95) * (1.0 + 0.25 * np.sin(np.pi * t / dur) - 0.15 * t / dur)
    ph = np.cumsum(f0) / SR
    src = ((ph % 1.0) - 0.5) * 2.0
    src = src * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 27.0 * t)))             # vocal fry: a 27 Hz gate on the glottal saw
    src += white(n, seed + 1) * 0.15
    a = r.uniform(380, 520)
    b = r.uniform(900, 1500)
    g1 = a * (1.0 + 0.5 * np.sin(np.pi * t / dur))
    g2 = b * (1.0 - 0.35 * t / dur)
    v = _formants(src, g1, g2)
    v = saturate(v / (np.max(np.abs(v)) + 1e-9), 2.0)
    env = np.minimum(t / 0.03, 1.0) * np.minimum((dur - t) / 0.12, 1.0)
    return ml.done(v * env, -16.0, 70.0, fout=0.1, max_len=0.7)


def alien_chitter(seed):
    r = R(seed)
    dur = r.uniform(0.25, 0.5)
    n = int(dur * SR)
    t = _t(n)
    rate = r.uniform(24, 38)
    f0 = r.uniform(520, 820) * (1.0 + 0.3 * np.sin(2 * np.pi * rate * 0.1 * t + 1.0))
    ph = np.cumsum(f0) / SR
    src = ((ph % 1.0) - 0.5) * 2.0
    clicks = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) ** 3
    g1 = r.uniform(1200, 1800) * (1.0 + 0.4 * np.sin(2 * np.pi * rate * 0.5 * t))
    g2 = r.uniform(2800, 3600) * np.ones(n)
    v = _formants(src * clicks, g1, g2, 6.0, 8.0)
    v = saturate(v / (np.max(np.abs(v)) + 1e-9), 1.6)
    env = np.minimum(t / 0.01, 1.0) * np.minimum((dur - t) / 0.08, 1.0)
    return ml.done(v * env, -17.0, 250.0, fout=0.06, max_len=0.6)


def alien_yelp(seed):
    r = R(seed)
    dur = 0.28
    n = int(dur * SR)
    t = _t(n)
    f0 = r.uniform(300, 380) * (1.0 + 1.1 * np.exp(-t / 0.05)) * (1.0 - 0.4 * t / dur)
    ph = np.cumsum(f0) / SR
    src = ((ph % 1.0) - 0.5) * 2.0 + white(n, seed + 2) * 0.1
    v = _formants(src, 700 + 900 * np.exp(-t / 0.1), 1900 - 500 * t / dur, 7.0, 9.0)
    v = saturate(v / (np.max(np.abs(v)) + 1e-9), 1.8)
    env = np.minimum(t / 0.008, 1.0) * np.minimum((dur - t) / 0.08, 1.0)
    return ml.done(v * env, -15.0, 150.0, fout=0.08, max_len=0.4)


# ------------------------------------------------------------------ UI
def ui_notify():
    x = np.zeros(int(0.7 * SR))
    for k, (m, dt) in enumerate(((81, 0.0), (88, 0.11))):
        b = fm_bell(0.5, mtof(m), 2.0, 0.8, 0.12, 0.04)
        x[int(dt * SR):int(dt * SR) + len(b)] += b * (0.8 if k else 1.0)
    return ml.done(ml.wet(x, 0.5, mix=0.2, seed=860), -15.0, 400.0, fout=0.15, max_len=0.8)


def ui_hover():
    n = int(0.05 * SR)
    t = _t(n)
    x = np.sin(2 * np.pi * 2400 * t) * expenv(n, 0.008) + band(white(n, 861), 3000, 9000) * expenv(n, 0.004) * 0.3
    return ml.done(x, -26.0, 800.0, fout=0.01)


# ------------------------------------------------------------------ loops (OGG)
def airship_hum():
    dur = 12.0
    n = int(dur * SR)
    t = _t(n)
    x = np.zeros(n)
    for k in range(1, 9):                                                    # twin rotor thrum: whole cycles per loop keep the seam silent
        f = ml.snap(34.0 * k, dur)
        x += np.sin(2 * np.pi * f * t + k * 1.3) / k ** 0.9
    am = 0.65 + 0.35 * np.sin(2 * np.pi * (ml.snap(9.0, dur)) * t)
    x = lp(x * am, 700, 2)
    x += ml.pn(n, 870, lambda f: np.exp(-(((np.log(f) - np.log(260.0)) / 0.8) ** 2)), 0.12)
    return ml.done_loop(x, -9.0, 25.0)


def wind_howl():
    dur = 12.0
    n = int(dur * SR)
    t = _t(n)
    x = pnoise(n, 880, lambda f: np.exp(-(((np.log(f) - np.log(520.0)) / 0.6) ** 2)))
    x = x / (np.std(x) + 1e-9)
    y = np.zeros(n)
    for k, (f, ph) in enumerate(((ml.snap(0.25, dur), 0.4), (ml.snap(0.58, dur), 2.0), (ml.snap(1.3, dur), 4.1))):
        y += np.sin(2 * np.pi * f * t + ph) * (0.5, 0.3, 0.2)[k]
    x = x * (0.55 + 0.45 * y)
    return ml.done_loop(x, -10.0, 90.0)


# ------------------------------------------------------------------ build
def build(out_dir, only=()):
    def want(name):
        return not only or any(fnmatch.fnmatch(name, p) for p in only)

    tmp = tempfile.mkdtemp(prefix="qt_depth_")
    try:
        layers = {"music_district_%d" % k: (lambda k=k: layer_district(k)) for k in range(4)}
        layers["music_boss"] = layer_boss
        layers["music_chase"] = layer_chase
        for name, fn in layers.items():
            if want(name):
                x = fn()
                mm.to_ogg(x, os.path.join(out_dir, name + ".ogg"), 3, tmp)
                print("%-18s %5.1f s  peak %6.1f  rms %6.1f dBFS  seam %.2f" % (name, x.shape[1] / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(np.sqrt(np.mean(x ** 2))), mm.seam_ratio(x)), flush=True)
        for name, fn in (("airship_hum", airship_hum), ("wind_howl", wind_howl)):
            if want(name):
                x = fn()
                mm.to_ogg(x[None, :], os.path.join(out_dir, name + ".ogg"), 3, tmp)
                print("%-18s %5.1f s  seam %.2f" % (name, len(x) / SR, mm.seam_ratio(x)), flush=True)
        wavs = {"sting_combat_%d" % k: (lambda k=k: sting_combat(k)) for k in range(3)}
        wavs.update({"sting_boss": sting_boss, "sting_chase": sting_chase, "ui_notify": ui_notify, "ui_hover": ui_hover})
        for k in range(4):
            wavs["alien_bark_%d" % k] = (lambda k=k: alien_growl(900 + 7 * k))
            wavs["alien_bark_%d" % (k + 4)] = (lambda k=k: alien_chitter(950 + 7 * k))
        for k in range(2):
            wavs["alien_yelp_%d" % k] = (lambda k=k: alien_yelp(990 + 5 * k))
        for name, fn in wavs.items():
            if want(name):
                x = fn()
                ma.write_wav(os.path.join(out_dir, name + ".wav"), x)
                print("%-18s %5.2f s  peak %6.1f dBFS" % (name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)))), flush=True)
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
