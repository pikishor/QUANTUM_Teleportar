#!/usr/bin/env python3
"""Checks the committed audio files (WAV and OGG) and the full mix numerically. Exit code 1 on any failure.

  * formats and durations of every file under assets/audio (WAV 44.1 kHz mono 16-bit; OGG through ffmpeg),
  * loop continuity of every loop (WAV loops carry a smpl chunk; the OGG beds and the music stems loop by import flag): the jump across the seam must be no larger
    than the steepest sample-to-sample step inside the loop,
  * the five music stems are the same length and, summed at their loudest state, stay below -5 dBFS,
  * the whole mix of a 20-shot firefight (family caps like Sfx, the SFX volumes the game uses) plus the combat music, the rain bed, thunder and the radio: peak and RMS
    before the Master limiter (peak must stay below -1 dBFS) and RMS must be in a sane range.
Usage: python3 check_audio.py [--dir assets/audio] [--verbose]
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FAILS = []


def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg)
    if not cond:
        FAILS.append(msg)


def read_wav(path):
    with wave.open(path) as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    x = np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, ch).T, sr, sw


def has_smpl(path):
    with open(path, "rb") as f:
        return b"smpl" in f.read()


def read_ogg(path):
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(SR), "-"], capture_output=True, check=True)
    x = np.frombuffer(p.stdout, "<f4").astype(np.float64)
    info = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    ch = int(info or 1)
    return x.reshape(-1, ch).T


def db(x):
    return 20 * np.log10(max(float(x), 1e-9))


def seam_ratio(x):
    d = np.abs(np.diff(x, axis=-1))
    return float(np.max(np.abs(x[..., 0] - x[..., -1]) / (np.max(d, axis=-1) + 1e-12)))


def parse_states(src):
    out = {}
    for m in re.finditer(r'&"(\w+)":\s*\[(\s*-?[\d.]+(?:\s*,\s*-?[\d.]+)+)\s*\]', src):
        vals = [float(v) for v in m.group(2).split(",")]
        if len(vals) == 5:
            out[m.group(1)] = vals
    return out


def place(buf, x, t, gain=1.0):
    i = int(t * SR)
    if i < len(buf):
        j = min(len(buf), i + len(x))
        buf[i:j] += x[:j - i] * gain


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "assets", "audio"))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    d = args.dir
    names = sorted(os.listdir(d))
    wavs = [n for n in names if n.endswith(".wav")]
    oggs = [n for n in names if n.endswith(".ogg")]
    total = sum(os.path.getsize(os.path.join(d, n)) for n in names if not n.endswith(".import"))
    check(total < 40e6, "total audio size %.1f MB (at most about 40 MB)" % (total / 1e6))

    loops_wav = {"drone_hum", "radio_static", "superpos_loop", "entangle_loop", "engine_low", "engine_high", "tyre_squeal", "traffic_loop", "music_ambient"}
    bad = []
    pcm = {}
    for n in wavs:
        x, sr, sw = read_wav(os.path.join(d, n))
        stem = n[:-4]
        if x.shape[0] != 1 or sr != SR or sw != 2:
            bad.append(n)
            continue
        pcm[stem] = x[0]
        pk = db(np.max(np.abs(x)))
        if pk > -6.0:
            bad.append(n + " peak %.1f" % pk)
        if stem in loops_wav:
            check(has_smpl(os.path.join(d, n)), "%s carries a loop chunk" % n)
            r = seam_ratio(x[0])
            check(r <= 1.5, "%s loops seamlessly (seam %.2f x the steepest step)" % (n, r))
    check(not bad, "%d WAV files are 44.1 kHz mono 16-bit and peak below -6 dBFS %s" % (len(wavs), bad[:5]))

    beds = ["rain_asphalt", "rain_metal", "rain_awning", "traffic_far", "wind", "city_hum"]
    stems = ["pad", "pulse", "bass", "perc", "lead"]
    dec = {}
    for n in oggs:
        dec[n[:-4]] = read_ogg(os.path.join(d, n))
    for b in beds:
        x = dec.get(b)
        check(x is not None and abs(x.shape[1] / SR - 24.0) < 0.2 and x.shape[0] == 2, "%s.ogg is a 24 s stereo bed" % b)
        if x is not None:
            r = seam_ratio(x)
            check(r <= 1.5, "%s.ogg loops seamlessly after Vorbis (seam %.2f)" % (b, r))
            check(db(np.max(np.abs(x))) < -9.0 and db(np.sqrt(np.mean(x ** 2))) > -45.0, "%s.ogg level: peak %.1f, rms %.1f dBFS" % (b, db(np.max(np.abs(x))), db(np.sqrt(np.mean(x ** 2)))))
    lens = [dec["music_" + s].shape[1] for s in stems]
    check(max(lens) - min(lens) <= 64 and abs(lens[0] / SR - 30.0) < 0.1, "the five stems have the same length (%s samples = %.2f s)" % (lens, lens[0] / SR))
    for s in stems:
        r = seam_ratio(dec["music_" + s])
        check(r <= 1.5, "music_%s.ogg loops seamlessly (seam %.2f)" % (s, r))
    n = min(lens)
    tot = sum(dec["music_" + s][:, :n] for s in stems)
    check(db(np.max(np.abs(tot))) < -5.0, "all five stems at full level sum to %.1f dBFS peak (rms %.1f)" % (db(np.max(np.abs(tot))), db(np.sqrt(np.mean(tot ** 2)))))
    for t in range(3):
        x = dec.get("thunder_%d" % t)
        check(x is not None and 5.0 < x.shape[1] / SR < 12.0, "thunder_%d.ogg is %.1f s" % (t, x.shape[1] / SR if x is not None else 0))

    # ---- the full mix of a firefight at combat state
    src = open(os.path.join(ROOT, "autoload", "sfx.gd")).read()
    states = parse_states(src)
    combat = states["combat"]
    music_db = float(re.search(r"const MUSIC_DB := (-?[\d.]+)", src).group(1))
    seconds = 6.0
    buf = np.zeros(int(seconds * SR))

    def g(name, i=0):
        return pcm[name] if name in pcm else pcm["%s_%d" % (name, i)]

    # SFX (the volumes the game passes): rifle 6-voice cap (oldest cut), hits, enemy fire, whizzes, voices, an explosion, a hurt, steps
    shots = []
    for k in range(20):
        t = 0.2 + k * 0.11
        x = g("shot", 0) if k % 4 == 0 else pcm["shot_%d" % (1 + k % 3)]
        shots.append((t, x * 10 ** (-2 / 20)))
    for i, (t, x) in enumerate(shots):
        end = len(x)
        later = [s for (s, _) in shots[i + 1:] if True]
        if len(later) >= 6:                           # the 7th later shot cuts this voice (family cap 6)
            end = min(end, int((later[5] - t) * SR))
        place(buf, x[:end], t)
    for k in range(8):
        place(buf, pcm["impact_%s_%d" % (["flesh", "concrete", "metal"][k % 3], k % 4)], 0.4 + k * 0.25, 10 ** (-2 / 20))
    for k in range(4):
        place(buf, pcm["enemy_shot"], 0.5 + k * 0.5, 10 ** (-4 / 20))
        place(buf, pcm["whizz_%d" % k], 0.6 + k * 0.5, 10 ** (-4 / 20))
    place(buf, pcm["trooper_pain_0"], 0.8)
    place(buf, pcm["trooper_alert_1"], 1.6)
    place(buf, pcm["step_asphalt_2"], 0.5, 10 ** (-6 / 20))
    place(buf, pcm["boom"], 1.2, 10 ** (-3 / 20))
    place(buf, pcm["hurt"], 1.4)
    place(buf, pcm["reload_1"], 3.0)
    place(buf, pcm["heartbeat"], 2.0, 10 ** (-6 / 20))
    sfx_peak = db(np.max(np.abs(buf)))
    # music (combat stems, Music bus ducked by the explosion for the first seconds) and ambience beds (rain on asphalt, traffic, wind, hum) and the radio babble
    mus = np.zeros(len(buf))
    for s, lvl in zip(stems, combat):
        x = dec["music_" + s]
        mono = np.tile(x.mean(axis=0), 2)[:len(buf)]
        mus += mono * 10 ** (lvl / 20)
    duck = np.ones(len(buf))
    t = np.arange(len(buf)) / SR
    duck = np.where(t < 1.4, 10 ** (-9 / 20), np.where(t < 3.6, 10 ** (-9 / 20 * np.exp(-(t - 1.4) / 1.0)), 1.0))
    mus *= 10 ** (music_db / 20) * duck
    amb = np.zeros(len(buf))
    for b, v in (("rain_asphalt", 0.5), ("traffic_far", 0.75), ("wind", 0.65), ("city_hum", 0.6)):
        x = np.tile(dec[b].mean(axis=0), 1)[:len(buf)]
        amb += x * v * 10 ** (-3 / 20)
    voice = np.zeros(len(buf))
    for k in range(8):
        place(voice, pcm["babble_%d" % (k % 8)], 2.0 + k * 0.1, 10 ** (-2 / 20))
    mix = buf * 10 ** (-1 / 20) + mus + amb + voice
    pk = db(np.max(np.abs(mix)))
    rms = db(np.sqrt(np.mean(mix[:int(5.0 * SR)] ** 2)))
    check(sfx_peak < -1.0, "20-shot firefight, effects only: peak %.1f dBFS (before the SFX compressor and the Master limiter)" % sfx_peak)
    check(pk < -1.0, "full mix (effects + combat music + rain/traffic/wind/hum + radio): peak %.1f dBFS, RMS %.1f dBFS before the limiter (peak below -1)" % (pk, rms))
    check(-40.0 < rms < -12.0, "full mix RMS %.1f dBFS is audible and not squashed" % rms)
    print("music alone: rms %.1f dBFS; ambience alone: rms %.1f dBFS" % (db(np.sqrt(np.mean(mus ** 2))), db(np.sqrt(np.mean(amb ** 2)))))
    print("files: %d wav, %d ogg, %.1f MB" % (len(wavs), len(oggs), total / 1e6))
    print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
    return 0 if not FAILS else 1


if __name__ == "__main__":
    sys.exit(main())
