#!/usr/bin/env python3
"""Builds the water sounds (assets/audio/water_*.ogg) from the committed CC0 clips in art_sources/audio_water/clips (see SOURCE.md there).
Mono 44.1 kHz, head silence trimmed, a 12 ms fade out on one-shots, peak normalised (one-shots -3 dBFS, loops by RMS), encoded with ffmpeg (OGG q5).
  python3 godot/tools/audio/make_water.py   (needs numpy and ffmpeg)"""
import os
import subprocess
import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CLIPS = os.path.abspath(os.path.join(ROOT, "..", "art_sources", "audio_water", "clips"))
OUT = os.path.join(ROOT, "assets", "audio")

# game name -> (clip, gain in dB after normalising, loop)
MAP = {
    "water_splash_0": ("wsp_a", 0.0, False), "water_splash_1": ("wsp_b", 0.0, False), "water_splash_2": ("wsp_c", 0.0, False), "water_splash_3": ("wsp_d", 0.0, False),
    "water_splash_big_0": ("wbig_a", 0.0, False), "water_splash_big_1": ("wbig_b", 0.0, False),
    "water_wade_0": ("wwade_a", -4.0, False), "water_wade_1": ("wwade_b", -4.0, False), "water_wade_2": ("wwade_c", -4.0, False),
    "water_stroke_0": ("wstroke_a", -5.0, False), "water_stroke_1": ("wstroke_b", -5.0, False), "water_stroke_2": ("wstroke_c", -5.0, False),
    "water_bubble": ("wbubble", -3.0, False),
    "water_river": ("wriver_loop", 0.0, True), "water_surf": ("wsurf_loop", 0.0, True),
}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def encode(x, path):
    pcm = np.clip(x, -1.0, 1.0).astype(np.float32).tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", path], input=pcm, check=True)


def main():
    for name, (cid, db, loop) in MAP.items():
        x = decode(os.path.join(CLIPS, cid + ".ogg"))
        if not loop:
            idx = np.nonzero(np.abs(x) > 0.01 * max(np.abs(x).max(), 1e-6))[0]
            if len(idx):
                x = x[max(0, idx[0] - 200):]
            fade = int(0.012 * SR)
            x[-fade:] *= np.linspace(1.0, 0.0, fade)
            x *= (10 ** (-3.0 / 20)) / max(np.abs(x).max(), 1e-6)
        else:
            rms = float(np.sqrt(np.mean(x * x)))
            x *= (10 ** (-20.0 / 20)) / max(rms, 1e-6)
            x *= min(1.0, 0.89 / max(np.abs(x).max(), 1e-6))
        x *= 10 ** (db / 20)
        encode(x, os.path.join(OUT, name + ".ogg"))
        print(name, round(len(x) / SR, 2), "s")


if __name__ == "__main__":
    main()
