#!/usr/bin/env python3
"""Synthesises the railway and ship sounds (assets/audio/train_*.ogg, maglev_*.ogg, crossing_bell.ogg, ship_*.ogg). Original, generated here (no third-party audio), mono 44.1 kHz,
loops are exact periodic signals so they repeat without a seam. Needs numpy and ffmpeg:  python3 godot/tools/audio/make_rail.py"""
import os
import subprocess
import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio"))
rng = np.random.default_rng(106)


def encode(x, name):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], input=x.tobytes(), check=True)
    print(name, round(len(x) / SR, 2), "s")


def norm(x, peak=0.8):
    return x * (peak / max(np.abs(x).max(), 1e-6))


def lowpass_periodic(n, cutoff_bins):
    """Periodic noise: random spectrum below a cutoff (in FFT bins), exactly periodic over n samples."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    k = np.arange(1, cutoff_bins)
    spec[k] = (rng.normal(size=len(k)) + 1j * rng.normal(size=len(k))) / np.sqrt(k)
    return np.fft.irfft(spec, n)


def horn(freqs, dur, attack=0.04, release=0.35, vib=0.0):
    t = np.arange(int(dur * SR)) / SR
    x = np.zeros_like(t)
    for f in freqs:
        for h, a in [(1, 1.0), (2, 0.5), (3, 0.33), (4, 0.18), (5, 0.1)]:
            x += a * np.sin(2 * np.pi * f * h * t + vib * np.sin(2 * np.pi * 5.0 * t))
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (dur - t) / release)
    x = x * env + 0.05 * np.random.default_rng(3).normal(size=len(t)) * env
    return norm(x, 0.85)


def main():
    # train horn: two chords, a long blast and a short one
    long_ = horn([311.0, 392.0, 466.0], 1.5)
    gap = np.zeros(int(0.12 * SR))
    short = horn([311.0, 392.0, 466.0], 0.55)
    encode(np.concatenate([long_, gap, short]), "train_horn")
    # maglev chime: three rising bell tones
    parts = []
    for f in [880.0, 1108.0, 1318.0]:
        t = np.arange(int(0.55 * SR)) / SR
        parts.append(np.sin(2 * np.pi * f * t) * np.exp(-t * 4.5) * 0.7 + np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 8) * 0.15)
    encode(norm(np.concatenate(parts), 0.7), "maglev_chime")
    # wheel clatter loop: 2.4 s, joints every 0.3 s as a clack-clack pair over a rumble
    n = int(2.4 * SR)
    x = lowpass_periodic(n, 60) * 1.0
    x = norm(x, 0.25)
    for k in range(8):
        for off, amp in [(0.0, 1.0), (0.07, 0.7)]:
            i0 = int((k * 0.3 + off) * SR)
            m = int(0.05 * SR)
            tt = np.arange(m) / SR
            click = (rng.normal(size=m) * 0.5 + np.sin(2 * np.pi * 180 * tt)) * np.exp(-tt * 90) * amp
            idx = (i0 + np.arange(m)) % n
            x[idx] += click * 0.5
    encode(norm(x, 0.7), "train_clatter")
    # maglev hum loop: 2 s of 140 / 280 Hz harmonics and wind
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    x = 0.5 * np.sin(2 * np.pi * 140 * t) + 0.3 * np.sin(2 * np.pi * 280 * t + 0.4) + 0.12 * np.sin(2 * np.pi * 420 * t)
    x += 0.5 * lowpass_periodic(n, 900)
    encode(norm(x, 0.6), "maglev_hum")
    # crossing bell loop: 1.0 s, two strikes at 0 and 0.5 s
    n = SR
    x = np.zeros(n)
    for s0 in [0.0, 0.5]:
        m = int(0.5 * SR)
        tt = np.arange(m) / SR
        bell = (np.sin(2 * np.pi * 1650 * tt) + 0.5 * np.sin(2 * np.pi * 1650 * 2.4 * tt)) * np.exp(-tt * 9)
        idx = (int(s0 * SR) + np.arange(m)) % n
        x[idx] += bell
    encode(norm(x, 0.6), "crossing_bell")
    # ship horn: very low, long
    encode(horn([58.0, 87.0, 117.0], 3.2, attack=0.25, release=0.9, vib=0.4), "ship_horn")
    # ship engine loop: a slow diesel beat 11 Hz and rumble, 2 s
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    beat = (np.sin(2 * np.pi * 11 * t) > 0.6).astype(float)
    x = 0.6 * np.sin(2 * np.pi * 44 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t)) + 0.4 * np.sin(2 * np.pi * 88 * t) * beat + 0.6 * lowpass_periodic(n, 160)
    encode(norm(x, 0.7), "ship_engine")
    # brake squeal
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    f = 2200 + 900 * np.sin(2 * np.pi * 1.3 * t) - 700 * t / 1.6
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.4 + rng.normal(size=n) * 0.12
    env = np.minimum(1.0, t / 0.1) * np.minimum(1.0, (1.6 - t) / 0.5)
    encode(norm(x * env, 0.5), "train_brake")


if __name__ == "__main__":
    main()
