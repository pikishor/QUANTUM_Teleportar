#!/usr/bin/env python3
"""Checks the committed audio files (WAV and OGG) and the full mix numerically. Exit code 1 on any failure.

  * formats and durations of every file under assets/audio (WAV 44.1 kHz mono 16-bit; OGG through ffmpeg),
  * loop continuity of every loop (WAV loops carry a smpl chunk; the OGG beds and the music stems loop by import flag): the jump across the seam must be no larger
    than the steepest sample-to-sample step inside the loop,
  * the five music stems are the same length and, summed at their loudest state, stay below -5 dBFS,
  * the whole mix of a 20-shot firefight (family caps like Sfx, the SFX volumes the game uses) plus the combat music, the rain bed, thunder and the radio: peak and RMS
    before the Master limiter (peak must stay below -1 dBFS) and RMS must be in a sane range.
  * the audio redesign (quality table, printed): LUFS-like loudness (K-weighted, first 250 ms for shots), crest factor, spectral centroid and low-band shares of every weapon class and
    of the close / far / suppressed / overcharged variants, impacts and explosions (sub-bass share); the five stems and the seven layers (loudness, crest, centroid per role), the
    tempo estimated from the percussion stem (128 BPM, inside 90-140), the bass stem's note per chord against the progression, the tonal centre (D minor) of the melodic stems,
    and the shots against the combat music (shots must dominate by at least 6 LU).
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_metrics as am  # noqa: E402

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


# ------------------------------------------------------------------ the audio redesign: quality table and checks
PROGRESSION_ROOTS = [38, 34, 41, 36, 38, 43, 34, 33]          # Dm9 Bbmaj7 Fadd9 Cadd9 | Dm Gm9 Bbmaj7 A7b9 (two bars each)
D_MINOR = {0, 2, 4, 5, 7, 9, 10, 1}                           # natural minor plus C# (the leading tone of the A7)
GRID_BPM = 128.0


def estimate_bpm(x, lo=0.35, hi=0.60):
    """Tempo from an onset envelope (10 ms RMS, half-wave rectified difference) by autocorrelation: the strongest lag between lo and hi seconds."""
    m = x.mean(axis=0) if x.ndim == 2 else x
    hop = int(0.005 * SR)
    env = np.sqrt(np.convolve(m ** 2, np.ones(hop * 2) / (hop * 2), "same"))[::hop]
    on = np.maximum(np.diff(env), 0.0)
    on = on - on.mean()
    ac = np.fft.irfft(np.abs(np.fft.rfft(on, 2 * len(on))) ** 2)[:len(on)]            # circular enough for a loop
    lags = np.arange(len(ac)) * hop / SR
    sel = (lags >= lo) & (lags <= hi)
    return 60.0 / float(lags[sel][np.argmax(ac[sel])])


def chroma_in_key(x, lo=80.0, hi=1400.0):
    m = x.mean(axis=0) if x.ndim == 2 else x
    S = np.abs(np.fft.rfft(m)) ** 2
    f = np.fft.rfftfreq(len(m), 1.0 / SR)
    sel = (f >= lo) & (f <= hi)
    pc = np.round(12 * np.log2(f[sel] / 440.0) + 69).astype(int) % 12
    e = np.bincount(pc, weights=S[sel], minlength=12)
    return float(sum(e[k] for k in D_MINOR) / (np.sum(e) + 1e-12))


def bass_notes_per_chord(x):
    m = x.mean(axis=0)
    seg = len(m) // 8
    out = []
    for i in range(8):
        y = m[i * seg:(i + 1) * seg]
        S = np.abs(np.fft.rfft(y * np.hanning(len(y)))) ** 2
        f = np.fft.rfftfreq(len(y), 1.0 / SR)
        sel = (f >= 40.0) & (f <= 130.0)
        k = np.argmax(S[sel])
        out.append(int(round(12 * np.log2(f[sel][k] / 440.0) + 69)) % 12)
    return out


def quality(d, pcm, dec, stems, combat, music_db):
    print("\n== audio quality table (LU = K-weighted loudness, first 250 ms for one-shots; low = share of energy 40-250 Hz, sub = under 80 Hz)")
    print("%-18s %5s %6s %6s %6s %7s %5s %5s" % ("sound", "len s", "peak", "LU", "crest", "centroid", "low", "sub"))

    def row(name, x, ms=250.0):
        print("%-18s %5.2f %6.1f %6.1f %6.1f %7.0f %5.2f %5.2f" % (name, len(x) / SR, am.peak_db(x), am.short_term(x, ms), am.crest_db(x), am.centroid_hz(x, ms), am.band_share(x, 40, 250, ms), am.band_share(x, 20, 80, ms)))

    def sound(n):
        return pcm[n] if n in pcm else (dec[n][0] if n in dec else None)

    close = ["shot", "shot_1", "shot_2", "shot_3", "shot_twin", "shot_rev", "shot_scatter", "shot_mini", "shot_burst", "shot_flux", "enemy_shot", "enemy_shot_1"]
    others = ["shot_far_0", "enemy_shot_far_0", "shot_supp_0", "shot_oc_0", "impact_flesh_0", "impact_flesh_1", "impact_concrete_0", "impact_metal_0", "boom", "boom_1", "explosion_small_0"]
    for n in close + others:
        x = sound(n)
        if x is not None:
            row(n, x, 250.0 if n.startswith(("shot", "enemy", "impact")) else 600.0)
    # shots
    for n in close:
        x = sound(n)
        if x is None:
            check(False, "%s exists" % n)
            continue
        lu, cr, ce, pk = am.short_term(x, 250.0), am.crest_db(x), am.centroid_hz(x, 250.0), am.peak_db(x)
        floor = -22.5 if n in ("shot_mini", "shot_burst", "enemy_shot", "enemy_shot_1") else -20.0
        check(lu >= floor and pk <= -9.0, "%s is loud and not clipped: %.1f LU (at least %.1f), peak %.1f dBFS" % (n, lu, floor, pk))
        check(cr <= 12.0, "%s is dense, not just tall: crest %.1f dB (at most 12)" % (n, cr))
        check(300.0 <= ce <= 3500.0, "%s centroid %.0f Hz is in the 300-3500 Hz range a phone reproduces (no hiss, no rumble)" % (n, ce))
        check(am.band_share(x, 40, 1400, 250.0) >= 0.45, "%s keeps %.0f %% of its first 250 ms under 1.4 kHz (body)" % (n, 100 * am.band_share(x, 40, 1400, 250.0)))
    base = sound("shot")
    check(abs(np.corrcoef(base[:8000], sound("shot_1")[:8000])[0, 1]) < 0.6 and abs(np.corrcoef(base[:8000], sound("shot_2")[:8000])[0, 1]) < 0.6, "the carbine variants are not copies of each other")
    far, supp, oc = sound("shot_far_0"), sound("shot_supp_0"), sound("shot_oc_0")
    check(am.short_term(base) - am.short_term(far) >= 3.0 and am.centroid_hz(far, 600.0) < am.centroid_hz(base, 600.0) and len(far) / SR >= 1.0, "the distant shot is quieter (%.1f LU), duller (%.0f vs %.0f Hz) and longer (%.1f s)" % (am.short_term(far) - am.short_term(base), am.centroid_hz(far, 600.0), am.centroid_hz(base, 600.0), len(far) / SR))
    check(am.short_term(base) - am.short_term(supp) >= 2.5 and am.band_share(supp, 1500, 16000, 30.0) < am.band_share(base, 1500, 16000, 30.0), "the suppressed shot is %.1f LU quieter and has less crack (%.3f vs %.3f of its first 30 ms above 1.5 kHz)" % (am.short_term(base) - am.short_term(supp), am.band_share(supp, 1500, 16000, 30.0), am.band_share(base, 1500, 16000, 30.0)))
    check(len(oc) / SR >= 1.0 and am.band_share(oc, 20, 80, 600.0) > am.band_share(base, 20, 80, 600.0), "the overcharged shot is long (%.1f s) with more sub-bass (%.2f vs %.2f)" % (len(oc) / SR, am.band_share(oc, 20, 80, 600.0), am.band_share(base, 20, 80, 600.0)))
    for n in ("impact_flesh_0", "impact_flesh_1", "impact_flesh_2", "impact_flesh_3", "impact_concrete_0", "impact_metal_0"):
        x = sound(n)
        check(am.short_term(x) >= -23.0 and am.peak_db(x) <= -9.0 and 500.0 <= am.centroid_hz(x, 250.0) <= 6500.0, "%s is punchy: %.1f LU, centroid %.0f Hz" % (n, am.short_term(x), am.centroid_hz(x, 250.0)))
    for n in ("boom", "boom_1", "boom_2", "boom_3", "explosion_small_0", "explosion_small_1"):
        x = sound(n)
        sub = am.band_share(x, 20, 100, 1200.0)
        check(sub >= 0.12 and am.short_term(x, 600.0) >= -20.0, "%s has sub-bass (%.0f %% of its first 1.2 s under 100 Hz) and %.1f LU" % (n, 100 * sub, am.short_term(x, 600.0)))
    # shots against the combat music: the game plays shots at -2 dB and the music at MUSIC_DB plus the combat stem levels
    n = min(dec["music_" + s].shape[1] for s in stems)
    mus = sum(dec["music_" + s][:, :n] * 10 ** (lvl / 20) for s, lvl in zip(stems, combat)) * 10 ** (music_db / 20)
    mus_lu = am.lufs_like(mus)
    shot_lu = am.short_term(base) - 2.0
    check(shot_lu - mus_lu >= 6.0, "shots dominate the combat music: shot %.1f LU vs music %.1f LU (+%.1f, at least +6)" % (shot_lu, mus_lu, shot_lu - mus_lu))
    # music
    print("\n%-18s %6s %6s %6s %7s %7s" % ("music", "peak", "LU", "crest", "centroid", "<250Hz"))
    for s in stems:
        x = dec["music_" + s]
        print("%-18s %6.1f %6.1f %6.1f %7.0f %7.2f" % ("music_" + s, am.peak_db(x), am.lufs_like(x), am.crest_db(x), am.centroid_hz(x), am.band_share(x.mean(axis=0), 20, 250)))
    for k in list(range(4)) + ["boss", "chase", "night"]:
        nm = "music_district_%d" % k if isinstance(k, int) else "music_%s" % k
        x = dec[nm]
        print("%-18s %6.1f %6.1f %6.1f %7.0f %7.2f" % (nm, am.peak_db(x), am.lufs_like(x), am.crest_db(x), am.centroid_hz(x), am.band_share(x.mean(axis=0), 20, 250)))
        check(abs(x.shape[1] / SR - 30.0) < 0.1 and -36.0 <= am.lufs_like(x) <= -18.0 and am.peak_db(x) <= -7.5, "%s is one 30 s loop at a sane level (%.1f LU, peak %.1f)" % (nm, am.lufs_like(x), am.peak_db(x)))
    cen = {s: am.centroid_hz(dec["music_" + s]) for s in stems}
    check(cen["bass"] < 450.0 and cen["pad"] < 2000.0 and cen["perc"] > 1500.0 and 500.0 < cen["lead"] < 3500.0 and 500.0 < cen["pulse"] < 3500.0, "each stem sits in its role: centroids %s" % {k: int(v) for k, v in cen.items()})
    tot = sum(dec["music_" + s][:, :n] for s in stems)
    check(-26.0 <= am.lufs_like(tot) <= -17.0 and am.crest_db(tot) <= 15.0, "all five stems: %.1f LU, crest %.1f dB (mastered: limited, not squashed)" % (am.lufs_like(tot), am.crest_db(tot)))
    bpm = estimate_bpm(dec["music_perc"])
    check(90.0 <= bpm <= 140.0 and abs(bpm - GRID_BPM) <= 4.0, "the percussion stem's tempo is %.1f BPM (the 128 BPM grid, inside the 90-140 set)" % bpm)
    notes = bass_notes_per_chord(dec["music_bass"])
    ok = sum(1 for a, r in zip(notes, PROGRESSION_ROOTS) if a == r % 12)
    check(ok >= 7, "the bass plays the chord roots of the progression in %d of 8 chords (%s)" % (ok, notes))
    for s in ("pad", "pulse", "lead"):
        c = chroma_in_key(dec["music_" + s])
        check(c >= 0.72, "music_%s stays in D minor: %.0f %% of its pitch-class energy is in the scale" % (s, 100 * c))


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

    loops_wav = {"drone_hum", "radio_static", "superpos_loop", "entangle_loop", "engine_low", "engine_high", "tyre_squeal", "traffic_loop"}
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
    for k in ("boom", "core"):   # long one-shots shipped as OGG by the size pass: decode into the mix table
        if k not in pcm and k in dec:
            pcm[k] = dec[k][0]
    for b in beds:
        x = dec.get(b)
        check(x is not None and abs(x.shape[1] / SR - 24.0) < 0.2 and x.shape[0] in (1, 2), "%s.ogg is a 24 s bed (mono since the size pass)" % b)
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
    quality(d, pcm, dec, stems, combat, music_db)
    print("music alone: rms %.1f dBFS; ambience alone: rms %.1f dBFS" % (db(np.sqrt(np.mean(mus ** 2))), db(np.sqrt(np.mean(amb ** 2)))))
    print("files: %d wav, %d ogg, %.1f MB" % (len(wavs), len(oggs), total / 1e6))
    print("RESULT:", "PASS" if not FAILS else "FAIL (%d)" % len(FAILS))
    return 0 if not FAILS else 1


if __name__ == "__main__":
    sys.exit(main())
