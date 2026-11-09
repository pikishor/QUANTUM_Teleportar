#!/usr/bin/env python3
"""Builds the wildlife sounds (assets/audio/animal_*.ogg) from the committed CC0 clips in art_sources/audio_animals/clips (see SOURCE.md there) plus a few synthesized calls
(eagle cry, dolphin chirps, deer / horse snort), all mono 44.1 kHz, head silence trimmed, a short fade out, peak normalised to -3 dBFS, OGG q5 through ffmpeg.
  python3 godot/tools/audio/make_animals.py   (needs numpy and ffmpeg)"""
import os
import subprocess
import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CLIPS = os.path.abspath(os.path.join(ROOT, "..", "art_sources", "audio_animals", "clips"))
OUT = os.path.join(ROOT, "assets", "audio")

# game name -> (clip, speed factor (resample: pitch and length), gain dB)
MAP = {
    "animal_wolf_0": ("wolf", 1.0, 0.0), "animal_wolf_1": ("wolf", 0.82, 0.0),
    "animal_coyote_0": ("wolf", 1.45, -1.0), "animal_coyote_1": ("wolf", 1.7, -1.0),
    "animal_gull_0": ("gull_a", 1.0, 0.0), "animal_gull_1": ("gull_b", 1.0, 0.0), "animal_gull_2": ("gull_c", 1.0, 0.0), "animal_gull_3": ("gull_hit", 1.0, 0.0),
    "animal_bird_0": ("bird_a", 1.0, 0.0), "animal_bird_1": ("bird_b", 1.0, 0.0), "animal_bird_2": ("bird_c", 1.0, 0.0), "animal_bird_3": ("bird_d", 1.0, 0.0), "animal_bird_4": ("bird_e", 1.0, 0.0),
    "animal_sheep_0": ("sheep", 1.0, 0.0), "animal_goat_0": ("sheep", 0.8, 0.0), "animal_goat_1": ("sheep", 0.7, 0.0),
    "animal_cow_0": ("cow", 1.0, 0.0), "animal_cow_1": ("cow_long", 1.0, 0.0), "animal_horse_0": ("cow", 1.55, -1.0),
}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def encode(x, path):
    pcm = np.clip(x, -1.0, 1.0).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", path], input=pcm, check=True)


def finish(x, db=0.0):
    idx = np.nonzero(np.abs(x) > 0.01 * max(np.abs(x).max(), 1e-6))[0]
    if len(idx):
        x = x[max(0, idx[0] - 200):]
    fade = min(int(0.03 * SR), len(x) // 2)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    x *= (10 ** (-3.0 / 20)) / max(np.abs(x).max(), 1e-6)
    return x * 10 ** (db / 20)


def speed(x, k):
    n = int(len(x) / k)
    return np.interp(np.linspace(0, len(x) - 1, n), np.arange(len(x)), x).astype(np.float32)


def sweep(f0, f1, dur, vib=0.0, harm=(1.0, 0.3)):
    t = np.arange(int(dur * SR)) / SR
    f = f0 + (f1 - f0) * (t / dur)
    f = f * (1.0 + vib * np.sin(2 * np.pi * 32 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum(a * np.sin((i + 1) * ph) for i, a in enumerate(harm))
    env = np.minimum(1.0, t / 0.02) * np.exp(-3.0 * t / dur)
    return (y * env).astype(np.float32)


def eagle(seed):
    r = np.random.RandomState(seed)
    out = np.zeros(int(1.5 * SR), dtype=np.float32)
    pos = 0
    for k in range(4):
        s = sweep(3400 + r.randint(-200, 200), 2300 - k * 120, 0.28 - k * 0.03, vib=0.03, harm=(1.0, 0.4, 0.15))
        out[pos:pos + len(s)] += s
        pos += int(0.31 * SR)
    return out[:pos]


def dolphin(seed):
    r = np.random.RandomState(seed)
    out = np.zeros(int(1.2 * SR), dtype=np.float32)
    pos = 0
    for k in range(5):
        a = 1800 + r.randint(0, 900)
        b = 5200 + r.randint(0, 1400)
        s = sweep(a, b, 0.11, harm=(1.0, 0.2))
        out[pos:pos + len(s)] += s
        pos += int((0.16 + 0.03 * k) * SR)
        if pos + int(0.12 * SR) > len(out):
            break
    return out[:pos + int(0.12 * SR)]


def snort(seed):
    r = np.random.RandomState(seed)
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    noise = r.randn(n).astype(np.float32)
    k = np.ones(40, dtype=np.float32) / 40
    low = np.convolve(noise, k, mode="same")
    band = noise - np.convolve(noise, np.ones(8, dtype=np.float32) / 8, mode="same")
    y = (low * 2.2 + band * 0.25) * np.exp(-9.0 * t) * np.minimum(1.0, t / 0.01)
    return y.astype(np.float32)


def main():
    for name, (cid, k, db) in MAP.items():
        x = decode(os.path.join(CLIPS, cid + ".ogg"))
        if k != 1.0:
            x = speed(x, k)
        x = finish(x, db)
        encode(x, os.path.join(OUT, name + ".ogg"))
        print(name, round(len(x) / SR, 2), "s")
    synth = {"animal_eagle_0": eagle(1), "animal_eagle_1": eagle(2), "animal_dolphin_0": dolphin(1), "animal_dolphin_1": dolphin(2), "animal_snort_0": snort(1), "animal_snort_1": snort(2)}
    for name, x in synth.items():
        x = finish(x, -2.0 if "snort" in name else 0.0)
        encode(x, os.path.join(OUT, name + ".ogg"))
        print(name, round(len(x) / SR, 2), "s (synthesized)")


if __name__ == "__main__":
    main()
