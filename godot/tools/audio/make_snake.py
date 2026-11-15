#!/usr/bin/env python3
"""Synthesises the QUANTUM SNAKE traversal sounds (assets/audio/snk_*.ogg): original, generated here (no third-party audio). Needs numpy and ffmpeg:  python3 godot/tools/audio/make_snake.py
One shot sounds: snk_fire (the snake leaves the hand), snk_attach (it bites), snk_strain (the rope takes the weight), snk_release (let go), snk_miss (nothing to bite), snk_zip (the pull-in),
snk_land (touchdown), snk_wings (the wings unfurl), snk_boost (boost), snk_roll (barrel roll). Loops (exactly periodic, no seam): snk_hum (the energy hum of a snake state) and snk_wind (air rush,
the game raises its volume and pitch with the speed)."""
import os
import subprocess
import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio"))
rng = np.random.default_rng(115)


def encode(x, name, q=3):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", str(q), os.path.join(OUT, name + ".ogg")], input=x.tobytes(), check=True)
    print(name, round(len(x) / SR, 2), "s")


def norm(x, peak=0.8):
    return x * (peak / max(np.abs(x).max(), 1e-6))


def noise(n):
    return rng.normal(size=n)


def bandpass_sweep(n, f0, f1, q=6.0):
    """White noise through a resonant band-pass whose centre glides f0 -> f1 (a state variable filter, per sample)."""
    x = noise(n)
    out = np.zeros(n)
    lp = bp = 0.0
    fs = np.geomspace(f0, f1, n)
    for i in range(n):
        f = 2.0 * np.sin(np.pi * fs[i] / SR)
        hp = x[i] - lp - bp / q
        bp += f * hp
        lp += f * bp
        out[i] = bp
    return out


def env(n, a, d, power=2.0):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)
    return e ** (1.0 if power == 1.0 else 1.0)


def lowpass(x, fc):
    a = np.exp(-2.0 * np.pi * fc / SR)
    out = np.zeros_like(x)
    y = 0.0
    for i in range(len(x)):
        y = (1 - a) * x[i] + a * y
        out[i] = y
    return out


def periodic_noise(n, lo_bin, hi_bin):
    spec = np.zeros(n // 2 + 1, dtype=complex)
    k = np.arange(lo_bin, hi_bin)
    spec[k] = rng.normal(size=len(k)) + 1j * rng.normal(size=len(k))
    return np.fft.irfft(spec, n)


def fire():
    n = int(0.42 * SR)
    t = np.arange(n) / SR
    hiss = bandpass_sweep(n, 1800, 7000, 3.0) * np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.16)
    sweep = np.sin(2 * np.pi * np.cumsum(np.geomspace(260, 1500, n)) / SR) * np.exp(-t / 0.1) * 0.35
    thump = np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.05) * 0.6
    return norm(hiss * 1.2 + sweep + thump, 0.85)


def attach():
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    thud = np.sin(2 * np.pi * (95 - 40 * np.minimum(t / 0.15, 1.0)) * t) * np.exp(-t / 0.07) * 1.0
    crack = lowpass(noise(n), 6000) * np.exp(-t / 0.012) * 1.4
    zap = np.zeros(n)
    for k in range(6):
        i0 = int((0.01 + k * 0.022 + rng.random() * 0.01) * SR)
        m = int(0.02 * SR)
        zap[i0:i0 + m] += noise(m) * np.exp(-np.arange(m) / (0.006 * SR)) * (0.5 - 0.06 * k)
    ring = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(1180, 0.25), (1770, 0.14), (2650, 0.08)]) * np.exp(-t / 0.16)
    return norm(thud + crack + zap + ring, 0.85)


def strain():
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = 62 + 26 * (t / 0.9) + 3.0 * np.sin(2 * np.pi * 7 * t)
    saw = 2.0 * ((np.cumsum(f) / SR) % 1.0) - 1.0
    creak = lowpass(saw, 420) * 0.8
    grit = bandpass_sweep(n, 400, 1100, 8.0) * 0.12
    e = np.minimum(t / 0.12, 1.0) * np.minimum((0.9 - t) / 0.2, 1.0)
    return norm((creak + grit) * e, 0.55)


def release():
    n = int(0.38 * SR)
    t = np.arange(n) / SR
    swish = bandpass_sweep(n, 5200, 900, 2.5) * np.minimum(t / 0.01, 1.0) * np.exp(-t / 0.1)
    snap = lowpass(noise(n), 8000) * np.exp(-t / 0.006) * 0.9
    ting = np.sin(2 * np.pi * 2100 * t) * np.exp(-t / 0.05) * 0.3
    return norm(swish + snap + ting, 0.8)


def miss():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    fizz = bandpass_sweep(n, 3200, 600, 3.0) * np.exp(-t / 0.07)
    pop = np.sin(2 * np.pi * 120 * t) * np.exp(-t / 0.03) * 0.5
    return norm(fizz + pop, 0.6)


def zip_():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    z = bandpass_sweep(n, 350, 5200, 4.0) * np.minimum(t / 0.05, 1.0) * np.minimum((0.7 - t) / 0.1, 1.0)
    g = np.sin(2 * np.pi * np.cumsum(np.geomspace(180, 1900, n)) / SR) * 0.25 * np.minimum(t / 0.05, 1.0) * np.exp(-np.maximum(t - 0.3, 0) / 0.2)
    return norm(z + g, 0.8)


def land():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (70 - 30 * np.minimum(t / 0.2, 1.0)) * t) * np.exp(-t / 0.09) * 1.0
    dust = lowpass(noise(n), 1800) * np.exp(-t / 0.08) * 0.8
    return norm(thump + dust, 0.85)


def wings():
    n = int(0.95 * SR)
    t = np.arange(n) / SR
    sh = bandpass_sweep(n, 700, 4200, 3.0) * np.minimum(t / 0.2, 1.0) * np.exp(-np.maximum(t - 0.45, 0) / 0.25)
    wh = lowpass(noise(n), 500) * np.minimum(t / 0.1, 1.0) * np.exp(-t / 0.45) * 1.4
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 14 * t)
    return norm((sh + wh) * trem, 0.8)


def boost():
    n = int(0.8 * SR)
    t = np.arange(n) / SR
    roar = lowpass(noise(n), 900) * np.minimum(t / 0.06, 1.0) * np.exp(-t / 0.32)
    sw = np.sin(2 * np.pi * np.cumsum(np.geomspace(85, 340, n)) / SR) * np.minimum(t / 0.05, 1.0) * np.exp(-t / 0.3)
    sw = np.tanh(sw * 3.0) * 0.5
    air = bandpass_sweep(n, 900, 3800, 2.5) * np.exp(-t / 0.25) * 0.5
    return norm(roar * 1.4 + sw + air, 0.88)


def roll():
    n = int(0.55 * SR)
    t = np.arange(n) / SR
    sw = bandpass_sweep(n, 600, 2800, 3.5)
    swirl = 0.55 + 0.45 * np.sin(2 * np.pi * 3.2 * t - 1.2)
    return norm(sw * swirl * np.sin(np.pi * np.minimum(t / 0.55, 1.0)) ** 0.6, 0.75)


def hum():
    dur = 2.0
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 110 * t) * 0.5 + np.sin(2 * np.pi * 165 * t + 1.0) * 0.25 + np.sin(2 * np.pi * 220 * t + 0.4) * 0.18 + np.sin(2 * np.pi * 331 * t) * 0.07
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 3 * t)
    x += 0.06 * periodic_noise(n, 40, 400) / max(np.abs(periodic_noise(n, 40, 400)).max(), 1e-6)
    return norm(x, 0.5)


def wind():
    n = int(2.0 * SR)
    x = periodic_noise(n, 4, 220) + 0.6 * periodic_noise(n, 220, 1200)
    t = np.arange(n) / SR
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * 1.0 * t + 0.7)
    return norm(x, 0.7)


if __name__ == "__main__":
    for name, fn in [("snk_fire", fire), ("snk_attach", attach), ("snk_strain", strain), ("snk_release", release), ("snk_miss", miss), ("snk_zip", zip_), ("snk_land", land), ("snk_wings", wings), ("snk_boost", boost), ("snk_roll", roll), ("snk_hum", hum), ("snk_wind", wind)]:
        encode(fn(), name)
