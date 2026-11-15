#!/usr/bin/env python3
"""Synthesises the QUANTUM SNAKE COMBAT sounds (assets/audio/snw_*.ogg): original, generated here (no third-party audio). Needs numpy and ffmpeg:  python3 godot/tools/audio/make_snake_war.py
One shots, grouped like the powers: snw_arm / snw_deny (the wheel and the refusals), snw_pull snw_grab snw_throw snw_slam snw_net snw_lash snw_hit (the verbs), snw_shield_up snw_shield_hit snw_decoy
snw_trap snw_guard, snw_bomb_throw snw_burst snw_coil snw_swarm snw_flare snw_freeze snw_gravity snw_storm snw_mega (the bombs) and snw_cheer (the crowd that films the hero).
The family `snw_` of autoload/sfx.gd gives them four voices and a short gap."""
import os
import subprocess
import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio"))
rng = np.random.default_rng(1150)


def encode(x, name, q=3):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", str(q), os.path.join(OUT, name + ".ogg")], input=x.tobytes(), check=True)
    print(name, round(len(x) / SR, 2), "s", os.path.getsize(os.path.join(OUT, name + ".ogg")) // 1024, "KB")


def norm(x, peak=0.8):
    return x * (peak / max(np.abs(x).max(), 1e-6))


def noise(n):
    return rng.normal(size=n)


def tt(n):
    return np.arange(n) / SR


def lowpass(x, fc):
    a = np.exp(-2.0 * np.pi * fc / SR)
    out = np.zeros_like(x)
    y = 0.0
    for i in range(len(x)):
        y = (1 - a) * x[i] + a * y
        out[i] = y
    return out


def highpass(x, fc):
    return x - lowpass(x, fc)


def bandpass(x, f0, f1=None, q=5.0):
    n = len(x)
    out = np.zeros(n)
    lp = bp = 0.0
    fs = np.geomspace(f0, f1 if f1 else f0, n)
    for i in range(n):
        f = 2.0 * np.sin(np.pi * fs[i] / SR)
        hp = x[i] - lp - bp / q
        bp += f * hp
        lp += f * bp
        out[i] = bp
    return out


def hiss(n, f0=2500, f1=6500, q=2.5):
    return bandpass(noise(n), f0, f1, q)


def adsr(n, a, d):
    t = tt(n)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / d)


def sine(f, n, phase=0.0):
    return np.sin(2 * np.pi * np.cumsum(np.broadcast_to(f, (n,)) if np.isscalar(f) else f) / SR + phase)


def sweep(f0, f1, n):
    return np.sin(2 * np.pi * np.cumsum(np.geomspace(f0, f1, n)) / SR)


def mix(parts, n):
    out = np.zeros(n)
    for x, g, at in parts:
        i = int(at * SR)
        m = min(len(x), n - i)
        if m > 0:
            out[i:i + m] += x[:m] * g
    return out


def rattle(n, rate=38.0, f0=3000, f1=6000):
    t = tt(n)
    return hiss(n, f0, f1, 2.0) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * t))) ** 1.0


def arm():
    n = int(0.32 * SR)
    t = tt(n)
    return norm(sweep(380, 1250, n) * adsr(n, 0.01, 0.1) * 0.5 + hiss(n, 3000, 7000) * adsr(n, 0.02, 0.07) * 0.5 + sine(95, n) * adsr(n, 0.005, 0.05) * 0.4, 0.7)


def deny():
    n = int(0.2 * SR)
    t = tt(n)
    return norm(sine(150 - 60 * t / 0.2, n) * adsr(n, 0.004, 0.05) + lowpass(noise(n), 900) * adsr(n, 0.002, 0.03) * 0.7, 0.6)


def pull():
    n = int(0.42 * SR)
    t = tt(n)
    h = hiss(n, 1800, 7500, 3.0) * adsr(n, 0.02, 0.14)
    crack = highpass(noise(n), 2500) * np.exp(-np.maximum(t - 0.14, 0) / 0.01) * (t > 0.14) * 1.2
    thump = sine(80, n) * adsr(n, 0.004, 0.06)
    return norm(h * 1.1 + sweep(260, 1500, n) * adsr(n, 0.01, 0.1) * 0.3 + crack + thump * 0.6, 0.85)


def grab():
    n = int(0.5 * SR)
    t = tt(n)
    squeeze = lowpass(noise(n), 700) * (0.4 + 0.6 * np.sin(2 * np.pi * 7 * t) ** 2) * adsr(n, 0.03, 0.3)
    creak = bandpass(noise(n), 500, 260, 12.0) * adsr(n, 0.02, 0.25) * 0.9
    thud = sine(110 - 50 * np.minimum(t / 0.2, 1), n) * adsr(n, 0.004, 0.09)
    return norm(squeeze * 1.0 + creak * 0.8 + thud * 0.9 + hiss(n, 3000, 5000) * adsr(n, 0.01, 0.1) * 0.3, 0.85)


def throw():
    n = int(0.5 * SR)
    t = tt(n)
    wh = bandpass(noise(n), 400, 2600, 2.0) * np.sin(np.pi * np.minimum(t / 0.38, 1.0)) ** 1.5
    snap = highpass(noise(n), 3000) * np.exp(-np.maximum(t - 0.02, 0) / 0.012) * 0.9
    return norm(wh * 1.0 + snap + sine(70, n) * adsr(n, 0.004, 0.1) * 0.5, 0.85)


def slam():
    n = int(0.8 * SR)
    t = tt(n)
    boom = sine(62 * np.exp(-t * 3.0) + 28, n) * adsr(n, 0.003, 0.22)
    crack = lowpass(noise(n), 5000) * np.exp(-t / 0.02) * 1.2
    tail = lowpass(noise(n), 400) * adsr(n, 0.01, 0.3) * 0.5
    return norm(boom * 1.3 + crack + tail + hiss(n, 2000, 5000) * adsr(n, 0.04, 0.2) * 0.35, 0.9)


def net():
    n = int(1.0 * SR)
    t = tt(n)
    parts = []
    for k in range(9):
        at = 0.02 + k * 0.07
        m = int(0.28 * SR)
        parts.append((hiss(m, 2200 + 350 * k, 6000, 2.5) * adsr(m, 0.01, 0.07), 0.55, at))
    sw = mix(parts, n)
    flap = bandpass(noise(n), 300, 900, 3.0) * adsr(n, 0.05, 0.25) * 0.4
    return norm(sw + flap + sine(90, n) * adsr(n, 0.01, 0.12) * 0.4, 0.8)


def lash():
    n = int(0.28 * SR)
    t = tt(n)
    c = highpass(noise(n), 1800) * np.exp(-t / 0.018) * 1.3
    w = bandpass(noise(n), 900, 4500, 3.0) * np.sin(np.pi * np.minimum(t / 0.12, 1.0)) * 0.8
    return norm(c + w + sweep(300, 900, n) * adsr(n, 0.005, 0.05) * 0.3, 0.85)


def hit():
    n = int(0.22 * SR)
    t = tt(n)
    return norm(sine(150 - 70 * np.minimum(t / 0.1, 1), n) * adsr(n, 0.002, 0.05) + lowpass(noise(n), 2500) * np.exp(-t / 0.02) + hiss(n, 3500, 6500) * adsr(n, 0.004, 0.04) * 0.5, 0.75)


def shield_up():
    n = int(0.8 * SR)
    t = tt(n)
    chord = sum(sine(f * (1 + 0.6 * t / 0.8), n) * 0.3 for f in (330, 495, 660)) * adsr(n, 0.12, 0.3)
    return norm(chord + hiss(n, 3500, 8000) * adsr(n, 0.08, 0.2) * 0.45 + sine(80, n) * adsr(n, 0.01, 0.1) * 0.4, 0.75)


def shield_hit():
    n = int(0.28 * SR)
    t = tt(n)
    ring = sum(sine(f, n) * a for f, a in ((880, 0.5), (1320, 0.35), (1980, 0.25))) * np.exp(-t / 0.07)
    return norm(ring + highpass(noise(n), 3000) * np.exp(-t / 0.008) * 0.8, 0.7)


def decoy():
    n = int(0.55 * SR)
    t = tt(n)
    a = bandpass(noise(n), 2400, 500, 3.0) * adsr(n, 0.02, 0.15)
    b = mix([(bandpass(noise(int(0.3 * SR)), 2000, 400, 3.0) * adsr(int(0.3 * SR), 0.02, 0.1), 0.8, 0.18)], n)
    return norm(a + b + sine(220 - 100 * t, n) * adsr(n, 0.01, 0.15) * 0.3, 0.7)


def trap():
    n = int(0.45 * SR)
    t = tt(n)
    return norm(sine(90, n) * adsr(n, 0.004, 0.07) * 0.8 + rattle(n, 34.0) * adsr(n, 0.03, 0.2) * 0.9 + lowpass(noise(n), 600) * adsr(n, 0.005, 0.05) * 0.5, 0.75)


def guard():
    n = int(0.9 * SR)
    parts = []
    for k in range(5):
        m = int(0.4 * SR)
        parts.append((hiss(m, 1800 + 450 * k, 5500, 2.5) * adsr(m, 0.03, 0.14), 0.6, k * 0.11))
    mx = mix(parts, n)
    t = tt(n)
    return norm(mx + sweep(180, 520, n) * adsr(n, 0.05, 0.3) * 0.35 + sine(70, n) * adsr(n, 0.01, 0.12) * 0.4, 0.8)


def bomb_throw():
    n = int(0.45 * SR)
    t = tt(n)
    wh = bandpass(noise(n), 300, 2000, 2.0) * np.sin(np.pi * np.minimum(t / 0.3, 1.0)) ** 1.4
    return norm(wh + rattle(n, 30.0, 2500, 5000) * adsr(n, 0.05, 0.3) * 0.45 + sine(75, n) * adsr(n, 0.004, 0.08) * 0.5, 0.8)


def burst():
    n = int(0.9 * SR)
    t = tt(n)
    pop = sine(120 * np.exp(-t * 5) + 45, n) * adsr(n, 0.003, 0.12)
    sh = hiss(n, 1500, 7000, 3.0) * adsr(n, 0.01, 0.35)
    return norm(pop * 1.0 + sh * 0.9 + lowpass(noise(n), 1200) * np.exp(-t / 0.04) + sweep(200, 900, n) * adsr(n, 0.02, 0.2) * 0.3, 0.85)


def coil():
    n = int(0.95 * SR)
    t = tt(n)
    creak = bandpass(noise(n), 420, 180, 14.0) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * adsr(n, 0.05, 0.5)
    sq = lowpass(noise(n), 500) * adsr(n, 0.04, 0.4) * 0.7
    return norm(creak * 1.0 + sq + hiss(n, 2500, 5000) * adsr(n, 0.03, 0.2) * 0.4 + sine(60, n) * adsr(n, 0.01, 0.2) * 0.5, 0.8)


def swarm():
    n = int(1.3 * SR)
    parts = []
    for k in range(14):
        m = int(0.5 * SR)
        parts.append((hiss(m, 1500 + 200 * (k % 5), 5500, 2.5) * adsr(m, 0.04, 0.16), 0.4, k * 0.07))
        parts.append((rattle(m, 24.0 + k, 2500, 5500) * adsr(m, 0.03, 0.14), 0.25, k * 0.07 + 0.02))
    return norm(mix(parts, n), 0.8)


def flare():
    n = int(0.75 * SR)
    t = tt(n)
    whistle = sweep(1200, 3800, n) * adsr(n, 0.01, 0.2)
    flash = highpass(noise(n), 1500) * np.exp(-t / 0.08)
    return norm(whistle * 0.5 + flash * 1.0 + hiss(n, 4000, 9000) * adsr(n, 0.01, 0.3) * 0.5 + sine(100, n) * adsr(n, 0.003, 0.06) * 0.5, 0.8)


def freeze():
    n = int(1.0 * SR)
    t = tt(n)
    clicks = np.zeros(n)
    for k in range(26):
        i = int(rng.uniform(0.0, 0.8) * SR)
        m = int(0.02 * SR)
        if i + m < n:
            clicks[i:i + m] += highpass(noise(m), 4000) * np.exp(-np.arange(m) / (0.004 * SR)) * rng.uniform(0.3, 1.0)
    chime = sum(sine(f, n) * a for f, a in ((1760, 0.4), (2637, 0.3), (3520, 0.2))) * adsr(n, 0.01, 0.35)
    return norm(clicks * 1.0 + chime * 0.6 + lowpass(noise(n), 700) * adsr(n, 0.05, 0.3) * 0.4, 0.75)


def gravity():
    n = int(1.5 * SR)
    t = tt(n)
    sw = sweep(900, 55, n) * np.minimum(t / 0.08, 1.0) * np.exp(-np.maximum(t - 1.1, 0) / 0.25)
    rumble = lowpass(noise(n), 300) * (0.3 + 0.7 * t / 1.5) * 0.9
    pop = sine(50, n) * np.exp(-np.maximum(t - 1.3, 0) / 0.08) * (t > 1.3) * 1.2
    return norm(sw * 0.9 + rumble + pop + hiss(n, 800, 3000) * np.sin(np.pi * np.minimum(t / 1.4, 1.0)) * 0.4, 0.85)


def storm():
    n = int(0.55 * SR)
    t = tt(n)
    z = highpass(noise(n), 1200) * (0.4 + 0.6 * (np.sin(2 * np.pi * 90 * t) > 0)) * adsr(n, 0.004, 0.14)
    crack = highpass(noise(n), 3000) * np.exp(-t / 0.01) * 1.3
    return norm(z + crack + sweep(2400, 300, n) * adsr(n, 0.004, 0.12) * 0.4 + sine(60, n) * adsr(n, 0.01, 0.2) * 0.3, 0.8)


def mega():
    n = int(2.2 * SR)
    t = tt(n)
    roar = (np.sin(2 * np.pi * np.cumsum(70 + 20 * np.sin(2 * np.pi * 3 * t)) / SR) + 0.6 * np.sign(np.sin(2 * np.pi * np.cumsum(70 + 20 * np.sin(2 * np.pi * 3 * t)) / SR))) * np.sin(np.pi * np.minimum(t / 1.1, 1.0)) ** 2 * 0.5
    sw = lowpass(noise(n), 900) * np.sin(np.pi * np.minimum(t / 1.4, 1.0)) * 0.8
    impact = sine(44 * np.exp(-np.maximum(t - 1.1, 0) * 1.5) + 26, n) * (t > 1.1) * np.exp(-np.maximum(t - 1.1, 0) / 0.5) * 1.4
    crack = lowpass(noise(n), 6000) * np.exp(-np.maximum(t - 1.1, 0) / 0.03) * (t > 1.1) * 1.2
    return norm(roar + sw + impact + crack + hiss(n, 1500, 6000) * adsr(n, 0.2, 0.7) * 0.4, 0.95)


def cheer():
    n = int(1.1 * SR)
    t = tt(n)
    voices = np.zeros(n)
    for k in range(10):
        f = rng.uniform(260, 520)
        env_ = np.sin(np.pi * np.clip((t - 0.03 * k) / 0.9, 0.0, 1.0)) ** 2
        v = sum(np.sin(2 * np.pi * np.cumsum(f * m * (1 + 0.05 * np.sin(2 * np.pi * rng.uniform(4, 7) * t))) / SR) / m for m in (1, 2, 3, 4))
        voices += v * env_ * rng.uniform(0.5, 1.0)
    voices = bandpass(voices + noise(n) * 0.5, 900, 900, 0.9) * 1.0
    return norm(voices, 0.55)


ALL = [arm, deny, pull, grab, throw, slam, net, lash, hit, shield_up, shield_hit, decoy, trap, guard, bomb_throw, burst, coil, swarm, flare, freeze, gravity, storm, mega, cheer]

if __name__ == "__main__":
    for fn in ALL:
        encode(fn(), "snw_" + fn.__name__)
