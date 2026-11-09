#!/usr/bin/env python3
"""Synthesises the aircraft engine loops (assets/audio/engine_rotor_*.ogg, engine_jet_*.ogg, engine_prop_*.ogg): original, generated here (no third-party audio). Each family is a LOW and a HIGH loop that
AudioDirector cross-fades by the engine's rpm and pitch-shifts; all loops are exactly periodic so they repeat without a seam. Needs numpy and ffmpeg:  python3 godot/tools/audio/make_air.py"""
import os
import subprocess
import numpy as np

SR = 44100
OUT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio"))
rng = np.random.default_rng(1061)


def encode(x, name):
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "3", os.path.join(OUT, name + ".ogg")], input=x.tobytes(), check=True)
    print(name, round(len(x) / SR, 2), "s")


def norm(x, peak=0.8):
    return x * (peak / max(np.abs(x).max(), 1e-6))


def periodic_noise(n, lo_bin, hi_bin):
    """Exactly periodic noise with a band-limited random spectrum (lo..hi FFT bins)."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    k = np.arange(lo_bin, hi_bin)
    spec[k] = rng.normal(size=len(k)) + 1j * rng.normal(size=len(k))
    return np.fft.irfft(spec, n)


def rotor(rate_hz, whine_hz, dur=2.0):
    """A helicopter: the blade slap (a thump of low noise every 1/rate s, a quieter second one halfway for the tail rotor) and a turbine whine. `dur * rate_hz` is a whole number."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = periodic_noise(n, 2, 60)
    x = np.zeros(n)
    period = 1.0 / rate_hz
    for k in range(int(round(dur * rate_hz))):
        for off, amp in [(0.0, 1.0), (0.45 * period, 0.35)]:
            i0 = int((k * period + off) * SR)
            m = int(0.09 * SR)
            env = np.exp(-np.arange(m) / (0.018 * SR))
            seg = np.take(base, np.arange(i0, i0 + m), mode="wrap") * env * amp
            thump = np.sin(2 * np.pi * (55.0 + 25.0 * np.exp(-np.arange(m) / (0.01 * SR))) * np.arange(m) / SR) * env * amp * 1.6
            idx = np.arange(i0, i0 + m) % n
            x[idx] += seg * 2.2 + thump
    x += 0.05 * periodic_noise(n, 60, 400)
    x += 0.07 * np.sin(2 * np.pi * whine_hz * t)
    return norm(x, 0.8)


def jet(whine_hz, rumble_bins, hiss, dur=2.0):
    """A turbofan: a broadband roar (low rumble + hiss) and a high whine with a second harmonic."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = periodic_noise(n, 2, rumble_bins) * 1.0
    x = x / max(np.abs(x).max(), 1e-6)
    h = periodic_noise(n, int(0.3 * n / 2), int(0.7 * n / 2))
    x += hiss * h / max(np.abs(h).max(), 1e-6)
    x *= 0.6 + 0.4 * np.sin(2 * np.pi * 3.0 * t) ** 2                    # the roar breathes a little
    x += 0.12 * np.sin(2 * np.pi * whine_hz * t) + 0.05 * np.sin(2 * np.pi * whine_hz * 2.01 * t)
    return norm(x, 0.8)


def prop(f0, dur=2.0):
    """A small piston engine and propeller: a buzzy harmonic stack with a slow beat and some air."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.8), (3, 0.6), (4, 0.4), (5, 0.3), (6, 0.2), (8, 0.12)]:
        x += a * np.sin(2 * np.pi * f0 * h * t + h * 0.3)
    x *= 0.75 + 0.25 * np.sin(2 * np.pi * (f0 / 12.0) * t)
    x += 0.15 * periodic_noise(n, 20, 700) / 4.0
    return norm(x, 0.8)


def main():
    encode(rotor(11.0, 900.0), "engine_rotor_low")
    encode(rotor(17.0, 1400.0), "engine_rotor_high")
    encode(jet(1700.0, 80, 0.35), "engine_jet_low")
    encode(jet(2600.0, 140, 0.8), "engine_jet_high")
    encode(prop(60.0), "engine_prop_low")
    encode(prop(105.0), "engine_prop_high")


if __name__ == "__main__":
    main()
