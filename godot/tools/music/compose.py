#!/usr/bin/env python3
"""Quantum Teleportar music: composed as MIDI in code, rendered with FluidSynth and the FluidR3 GM SoundFont (MIT licence), mastered with numpy, written as OGG.

Four tracks, every one a sample-exact 30.000 s loop (so the 5 stems and the theme layers of Sfx stay locked on one grid) with five stems (pad, pulse, bass, perc, lead):

    track    BPM  bars  key       what it is
    explore   96   12   D minor   calm groove: warm pad, electric piano arpeggio with a soft shaker beat, finger bass, flute melody; 3 sections (A restrained, B fuller, C lift) and a
                                  turnaround (A7b9) into the loop start. Stem files keep their old names music_pad|pulse|bass|perc|lead.
    menu      64    8   D minor   cinematic title theme: slow strings and choir, harp arpeggios, contrabass, timpani and taiko, horn melody, reverse-cymbal swells.
    combat   144   18   E minor   driving: power-chord guitar chugs, pumping synth bass, power-kit drums with fills, saw lead and brass stabs; F (bII) to B7 pulls back to the start.
    chase    160   20   A minor   urgent: tremolo strings, pizzicato 16th ostinato, 16th synth bass, electronic-kit drums, saw hook, brass stabs; Bb (bII) and E7 give the pressure.
    layers (same grid as the track they colour): music_district_0..3 + music_night (explore grid), music_boss (combat grid), music_chase (chase grid).

Every stem is its own MIDI file (tools/music/midi/<track>_<stem>.mid, written by this script) so a stem can be remixed without touching the others. The loop is played three
times in a row (one event per 64-sample FluidSynth block, a pass is an exact number of blocks, so the passes are identical) and the third pass is cut out: the reverb and release
tails of the previous pass run across the seam, the loop has no click and no gap.
Mastering: 30 Hz high-pass, per-stem trims, all five stems summed to -22 LUFS (combat and chase -23; K-weighted, ITU-R BS.1770 shape), one shared look-ahead limiter (all stems get the same gain curve,
so any subset of stems stays balanced) with the five-stem sum capped at -8 dBFS, OGG Vorbis (bass mono).

Needs: python3 -m pip install mido numpy scipy pyfluidsynth; apt install fluidsynth fluid-soundfont-gm ffmpeg (SoundFont: /usr/share/sounds/sf2/FluidR3_GM.sf2, override with --soundfont).
Run:   python3 tools/music/compose.py [--only explore menu combat chase layers] [--midi-only] [--out assets/audio] [--soundfont path.sf2]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
import zlib
from concurrent.futures import ThreadPoolExecutor

import mido
import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(GODOT, "tools", "audio"))
import audio_metrics as am  # noqa: E402

SR = 44100
LOOP_SECONDS = 30.0
PRE_ROLL = 256              # the loop window starts 5.8 ms before the downbeat so that no attack sits exactly on the seam (every stem and layer has the same pre-roll)
N = int(round(LOOP_SECONDS * SR))
STEMS = ["pad", "pulse", "bass", "perc", "lead"]
TPB = 480
REPEATS = 3
TARGET_LUFS = -22.0          # five stems summed (the scale tools/audio/check_audio.py uses: -26 .. -17); combat and chase sit 1 dB lower so shots dominate them by 6 LU
LAYER_LUFS = -25.0
SUM_PEAK_DB = -8.0
LAYER_PEAK_DB = -10.0
DEFAULT_SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"

NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
# chord quality -> semitones above the root
Q = {
    "m": [0, 3, 7], "": [0, 4, 7], "m7": [0, 3, 7, 10], "m9": [0, 3, 7, 10, 14], "maj7": [0, 4, 7, 11], "add9": [0, 4, 7, 14], "7": [0, 4, 7, 10],
    "7b9": [0, 4, 7, 10, 13], "sus4": [0, 5, 7], "5": [0, 7],
}
# drum notes (GM)
KICK, RIM, SNARE, CLAP, HAT, OHAT, PHAT, TOM_LO, TOM_MID, TOM_HI, CRASH, RIDE, COWBELL, TAMB, SHAKER, TOM_F = 36, 37, 38, 39, 42, 46, 44, 45, 47, 50, 49, 51, 56, 54, 70, 43


def pc(name):
    """'D' -> 2, 'Bb' -> 10, 'F#' -> 6"""
    v = NOTE_PC[name[0]]
    for ch in name[1:]:
        v += 1 if ch == "#" else -1
    return v % 12


def mid(name):
    """'F#4' -> 66, 'Bb3' -> 58"""
    i = 1
    v = NOTE_PC[name[0]]
    while name[i] in "#b":
        v += 1 if name[i] == "#" else -1
        i += 1
    return v + 12 * (int(name[i:]) + 1)


def crc(*parts):
    return zlib.crc32("|".join(str(p) for p in parts).encode())


def jitter(*key):
    """deterministic value in [-1, 1) from a key (never python's salted hash: the MIDI files must be reproducible)"""
    return (crc(*key) % 2000) / 1000.0 - 1.0


class Part:
    def __init__(self, channels):
        self.channels = channels        # ch -> dict(program, vol, pan, rev, cho, drum)
        self.notes = []                 # (ch, pitch, start_beat, dur_beat, vel)

    def add(self, ch, pitch, start, dur, vel):
        self.notes.append((ch, int(pitch), float(start), float(dur), int(max(1, min(127, vel)))))


class Song:
    def __init__(self, name, bpm, bars, chords, trims, target=TARGET_LUFS):
        self.name, self.bpm, self.bars, self.chords = name, bpm, bars, chords      # chords: one (root_pc, quality) per bar
        assert len(chords) == bars
        assert abs(bars * 4 * 60.0 / bpm - LOOP_SECONDS) < 1e-6, "%s must be exactly %.1f s" % (name, LOOP_SECONDS)
        self.trims = trims
        self.target = target
        self.parts = {}

    @property
    def beats(self):
        return self.bars * 4

    def chord(self, bar):
        return self.chords[bar % self.bars]

    def runs(self):
        """[(first_bar, length_in_bars, chord)] with equal neighbouring chords merged"""
        out = []
        for b, c in enumerate(self.chords):
            if out and out[-1][2] == c:
                out[-1][1] += 1
            else:
                out.append([b, 1, c])
        return out


def bass_root(pcv, lo):
    return lo + (pcv - lo) % 12


def chord_pcs(root, q):
    return [(root + i) % 12 for i in Q[q]]


def voicing(root, q, prev, lo, hi, skip_root=True):
    """Voice-led chord tones inside [lo, hi]: each tone takes the octave nearest to the previous voicing's centre."""
    ivs = Q[q][1:] if skip_root else Q[q]
    centre = (sum(prev) / len(prev)) if prev else (lo + hi) / 2.0
    out = []
    for iv in ivs:
        base = (root + iv) % 12
        cands = [p for p in range(lo, hi + 1) if p % 12 == base]
        out.append(min(cands, key=lambda p: abs(p - centre)))
    return sorted(set(out))


def role_pitch(role, root_m, q, next_root_m):
    """Bass roles: R root, O octave, 3 third, 5 fifth, 7 seventh, A chromatic approach to the next root, a approach from above."""
    ivs = Q[q]
    if role == "R":
        return root_m
    if role == "O":
        return root_m + 12
    if role == "3":
        return root_m + ivs[1]
    if role == "5":
        return root_m + 7
    if role == "7":
        return root_m + (ivs[3] if len(ivs) > 3 else 10)
    if role == "A":
        return next_root_m - 1
    if role == "a":
        return next_root_m + 1
    raise ValueError(role)


def parse_line(text, start_beat):
    """'A4 1.5, C5 .5, R 1' -> [(pitch, start, dur)]. R is a rest."""
    out = []
    t = start_beat
    for tok in text.split(","):
        n, d = tok.split()
        d = float(d)
        if n != "R":
            out.append((mid(n), t, d))
        t += d
    return out


def add_line(part, ch, bars_text, vel, legato=0.92, accent=None):
    """bars_text: list of (bar_index, 'note dur, note dur, ...') whose durations add up to 4 beats."""
    for bar, text in bars_text:
        line = parse_line(text, bar * 4)
        total = sum(float(tok.split()[1]) for tok in text.split(","))
        assert abs(total - 4.0) < 1e-9, "bar %d adds up to %s beats: %s" % (bar, total, text)
        for i, (p, s, d) in enumerate(line):
            v = vel + (accent if accent and (s % 1.0 == 0.0) else 0) + int(jitter("lead", bar, i) * 4)
            part.add(ch, p, s, d * legato, v)


def humanize(part, name, amount=0.012, vamount=5):
    """small timing and velocity variation, deterministic (the same on every pass of the loop because it is part of the note list)"""
    out = []
    for i, (ch, p, s, d, v) in enumerate(part.notes):
        drum = part.channels[ch].get("drum")
        a = amount * (0.4 if drum else 1.0)
        s2 = max(0.0, s + (jitter(name, "t", i, ch, round(s, 3)) * a if s > 0.01 else 0.0))
        v2 = v + int(jitter(name, "v", i, ch, round(s, 3)) * vamount)
        out.append((ch, p, s2, d, max(1, min(127, v2))))
    part.notes = out


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
# MIDI writing
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

def write_midi(path, part, bpm, loop_beats, repeats=REPEATS):
    mf = mido.MidiFile(type=1, ticks_per_beat=TPB)
    tr = mido.MidiTrack()
    mf.tracks.append(tr)
    tr.append(mido.MetaMessage("set_tempo", tempo=int(round(60_000_000 / bpm)), time=0))
    tr.append(mido.MetaMessage("time_signature", numerator=4, denominator=4, time=0))
    events = []     # (tick, order, msg)
    for ch, c in part.channels.items():
        if not c.get("drum"):
            events.append((0, 0, mido.Message("control_change", channel=ch, control=0, value=0)))
            events.append((0, 0, mido.Message("control_change", channel=ch, control=32, value=0)))
        events.append((0, 1, mido.Message("program_change", channel=ch, program=c["program"])))
        events.append((0, 1, mido.Message("control_change", channel=ch, control=7, value=c.get("vol", 100))))
        events.append((0, 1, mido.Message("control_change", channel=ch, control=10, value=c.get("pan", 64))))
        events.append((0, 1, mido.Message("control_change", channel=ch, control=91, value=c.get("rev", 40))))
        events.append((0, 1, mido.Message("control_change", channel=ch, control=93, value=c.get("cho", 0))))
    for k in range(repeats):
        off = k * loop_beats
        for ch, p, s, d, v in part.notes:
            t0 = int(round((off + s) * TPB))
            t1 = int(round((off + s + max(d, 0.05)) * TPB))
            events.append((t0, 3, mido.Message("note_on", channel=ch, note=p, velocity=v)))
            events.append((t1, 2, mido.Message("note_off", channel=ch, note=p, velocity=0)))
    events.sort(key=lambda e: (e[0], e[1]))
    last = 0
    for tick, _, msg in events:
        tr.append(msg.copy(time=tick - last))
        last = tick
    tr.append(mido.MetaMessage("end_of_track", time=max(0, repeats * int(loop_beats * TPB) + 4 * TPB - last)))
    mf.save(path)


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
# the songs
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

def swing_start(bar, step, amount=0.10):
    """start beat of a 16th step; the off-beat sixteenths land late by `amount` of a step"""
    return bar * 4 + step * 0.25 + (amount * 0.25 if step % 2 == 1 else 0.0)


def drums_explore(part, ch, song, full):
    """The shared groove. `full` = the perc stem (16th hats, open hats, ghost notes, fills, claps); otherwise the soft skeleton that lives in the pulse stem (same hit times)."""
    for b in range(song.bars):
        sec = 0 if b < 4 else (1 if b < 8 else 2)
        kick = [0, 7, 10] if sec == 0 else ([0, 7, 10, 14] if sec == 1 else [0, 3, 7, 10, 14])
        for s in kick:
            part.add(ch, KICK, swing_start(b, s), 0.2, (100 if s == 0 else 80) if full else 52)
        for s in (4, 12):
            if full:
                part.add(ch, SNARE, swing_start(b, s), 0.25, 96)
                if sec == 2:
                    part.add(ch, CLAP, swing_start(b, s), 0.2, 70)
            else:
                part.add(ch, RIM, swing_start(b, s), 0.15, 58)
        steps = range(16) if full else range(0, 16, 2)
        for s in steps:
            v = [66, 24, 44, 26, 58, 24, 42, 28, 62, 24, 44, 26, 58, 24, 42, 30][s]
            if full and sec == 0 and s % 2 == 1:
                continue
            part.add(ch, HAT, swing_start(b, s), 0.1, v if full else int(v * 0.55))
        if full:
            if sec >= 1:
                part.add(ch, OHAT, swing_start(b, 14), 0.3, 60)
                part.add(ch, SNARE, swing_start(b, 15), 0.1, 32)
                part.add(ch, SNARE, swing_start(b, 7), 0.1, 30)
            if sec == 2:
                for s in range(0, 16, 4):
                    part.add(ch, TAMB, swing_start(b, s + 2), 0.1, 46)
            if b in (0, 8):
                part.add(ch, CRASH, b * 4, 2.0, 78 if b == 0 else 92)
            if b % 4 == 3:       # fill in the last bar of every section
                for i, (s, n) in enumerate([(12, SNARE), (13, SNARE), (14, TOM_HI), (15, TOM_MID)]):
                    part.add(ch, n, swing_start(b, s), 0.15, 70 + 6 * i)
                if b == 11:
                    part.add(ch, TOM_LO, swing_start(b, 15) + 0.1, 0.15, 96)
        else:
            part.add(ch, SHAKER, swing_start(b, 15), 0.1, 30)
            for s in range(1, 16, 2):
                part.add(ch, SHAKER, swing_start(b, s), 0.08, 26 if s % 4 else 34)


def build_explore():
    D, B, G, A = pc("D"), pc("Bb"), pc("G"), pc("A")
    chords = [(D, "m9")] * 2 + [(B, "maj7")] * 2 + [(G, "m9")] * 2 + [(D, "m9")] * 2 + [(B, "maj7"), (G, "m9"), (A, "7"), (A, "7b9")]
    s = Song("explore", 96, 12, chords, {"pad": 0, "pulse": -1.0, "bass": 0.5, "perc": 0.5, "lead": 0.0})
    # pad: warm pad + strings (B, C) + sparse celesta
    pad = Part({0: dict(program=89, vol=100, pan=64, rev=70, cho=30), 1: dict(program=48, vol=80, pan=64, rev=80, cho=20), 2: dict(program=8, vol=70, pan=64, rev=110, cho=0)})
    prev = None
    for b0, n, (r, q) in s.runs():
        v = voicing(r, q, prev, 52, 76)
        prev = v
        for p in v:
            pad.add(0, p, b0 * 4, n * 4 + 0.15, 60 + (p % 5))
        if b0 >= 4:
            for p in v[-3:]:
                pad.add(1, p + (12 if p < 64 else 0), b0 * 4, n * 4 + 0.1, 46)
    for b in range(s.bars):
        r, q = s.chord(b)
        if b % 2 == 1 and b >= 3 or b == 10:
            tones = [p for p in range(79, 92) if p % 12 in chord_pcs(r, q)]
            t0 = b * 4 + 2.0
            for i, p in enumerate(tones[:4]):
                pad.add(2, p, t0 + i * 0.5, 0.9, 44 + 3 * i)
    s.parts["pad"] = pad
    # pulse: electric piano arpeggio (tresillo) + the soft groove skeleton
    pulse = Part({0: dict(program=4, vol=92, pan=50, rev=60, cho=60), 9: dict(program=8, vol=80, pan=64, rev=25, cho=0, drum=True)})
    prevv = None
    for b in range(s.bars):
        r, q = s.chord(b)
        prevv = voicing(r, q, prevv if b else None, 60, 79, skip_root=False)
        tones = prevv
        sec = 0 if b < 4 else (1 if b < 8 else 2)
        steps = [0, 3, 6, 8, 11, 14] if sec == 0 else ([0, 3, 6, 8, 10, 11, 14] if sec == 1 else [0, 2, 3, 6, 8, 10, 11, 14])
        seq = tones + tones[-2:0:-1]
        for i, st in enumerate(steps):
            p = seq[i % len(seq)] + (12 if sec == 2 and i % 4 == 3 and seq[i % len(seq)] < 74 else 0)
            pulse.add(0, p, swing_start(b, st, 0.06), 0.42, (74 if st in (0, 6, 11) else 58) - (6 if sec == 0 else 0))
    drums_explore(pulse, 9, s, False)
    s.parts["pulse"] = pulse
    # bass: finger bass, three patterns
    bass = Part({0: dict(program=33, vol=112, pan=64, rev=8, cho=0)})
    patterns = [
        [(0, "R", 5, 100), (6, "O", 1, 80), (8, "R", 2, 92), (10, "5", 2, 86), (12, "7", 3, 82)],
        [(0, "R", 3, 104), (3, "R", 1, 70), (4, "O", 1, 78), (6, "7", 1, 74), (7, "R", 1, 84), (8, "5", 2, 90), (10, "R", 1, 80), (11, "O", 1, 74), (12, "3", 2, 84), (14, "5", 1, 76), (15, "A", 1, 80)],
        [(0, "R", 2, 108), (2, "R", 1, 64), (3, "O", 1, 80), (4, "R", 2, 90), (6, "5", 1, 76), (7, "R", 1, 86), (8, "O", 2, 90), (10, "7", 1, 80), (11, "5", 1, 74), (12, "3", 2, 86), (14, "R", 1, 78), (15, "A", 1, 84)],
    ]
    for b in range(s.bars):
        r, q = s.chord(b)
        nr, _ = s.chord(b + 1)
        sec = 0 if b < 4 else (1 if b < 8 else 2)
        root_m, nroot_m = bass_root(r, 34), bass_root(nr, 34)
        for st, role, dur, vel in patterns[sec]:
            bass.add(0, role_pitch(role, root_m, q, nroot_m), swing_start(b, st, 0.06), dur * 0.25 * 0.9, vel)
    s.parts["bass"] = bass
    # perc: full groove
    perc = Part({9: dict(program=0, vol=110, pan=64, rev=30, cho=0, drum=True)})
    drums_explore(perc, 9, s, True)
    s.parts["perc"] = perc
    # lead: flute (heard while driving), a written melody over the progression
    lead = Part({0: dict(program=73, vol=104, pan=70, rev=70, cho=10), 1: dict(program=11, vol=70, pan=58, rev=80, cho=30)})
    add_line(lead, 0, [
        (0, "A4 1.5, C5 .5, E5 1.5, D5 .5"), (1, "C5 1, A4 1, F4 2"), (2, "D5 1.5, F5 .5, A5 1, G5 1"), (3, "F5 2, E5 1, D5 1"),
        (4, "D5 1, Bb4 1, G4 1.5, A4 .5"), (5, "Bb4 2, D5 1, F5 1"), (6, "E5 1.5, D5 .5, C5 1, A4 1"), (7, "A4 .5, C5 .5, D5 1, E5 2"),
        (8, "F5 1.5, A5 .5, D6 1.5, C6 .5"), (9, "Bb5 1, A5 1, G5 1, D5 1"), (10, "C#5 1, E5 1, A5 1.5, G5 .5"), (11, "Bb5 .5, A5 .5, G5 1, E5 1, C#5 1"),
    ], 80, accent=6)
    for b0, n, (r, q) in s.runs():
        if b0 >= 8:
            lead.add(1, bass_root(r, 48) + 12, b0 * 4, n * 2.0, 52)    # vibraphone roots under the lift
    s.parts["lead"] = lead
    return s


def build_menu():
    D, B, F, C, G, A = pc("D"), pc("Bb"), pc("F"), pc("C"), pc("G"), pc("A")
    chords = [(D, "m"), (B, ""), (F, ""), (C, ""), (D, "m"), (B, "maj7"), (G, "m"), (A, "7")]
    s = Song("menu", 64, 8, chords, {"pad": 0, "pulse": -1.0, "bass": 0.0, "perc": 0.5, "lead": 1.0})
    pad = Part({0: dict(program=49, vol=104, pan=64, rev=100, cho=30), 1: dict(program=52, vol=80, pan=64, rev=110, cho=0), 2: dict(program=89, vol=80, pan=64, rev=100, cho=40)})
    prev = None
    for b in range(s.bars):
        r, q = s.chord(b)
        v = voicing(r, q, prev, 50, 74)
        prev = v
        for p in v:
            pad.add(0, p, b * 4, 4.15, 66 + (p % 4))
        if b >= 4:
            for p in v[-3:]:
                pad.add(1, p + 12 if p < 62 else p, b * 4, 4.1, 50)
        pad.add(2, bass_root(r, 38) + 12, b * 4, 4.1, 50)
    s.parts["pad"] = pad
    pulse = Part({0: dict(program=46, vol=104, pan=48, rev=90, cho=20), 1: dict(program=0, vol=86, pan=80, rev=100, cho=10)})
    prevv = None
    for b in range(s.bars):
        r, q = s.chord(b)
        tones = voicing(r, q, prevv, 57, 84, skip_root=False)
        prevv = tones
        up = tones + [tones[1] + 12, tones[2] + 12]
        seq = up + up[-2:0:-1]
        for i in range(8):
            pulse.add(0, seq[i % len(seq)], b * 4 + i * 0.5, 1.2, 62 + (10 if i % 4 == 0 else 0) + (8 if b >= 4 else 0))
        if b >= 4:
            for p in (bass_root(r, 48), bass_root(r, 48) + 7, bass_root(r, 48) + 12):
                pulse.add(1, p, b * 4, 3.6, 66)
    s.parts["pulse"] = pulse
    bass = Part({0: dict(program=43, vol=116, pan=64, rev=40, cho=0), 1: dict(program=38, vol=80, pan=64, rev=10, cho=0)})
    for b in range(s.bars):
        r, q = s.chord(b)
        m = bass_root(r, 33)
        bass.add(0, m, b * 4, 3.9, 96)
        if b >= 4:
            bass.add(0, m + 7, b * 4 + 2.0, 1.9, 78)
            bass.add(1, m + 12, b * 4, 0.9, 60)
    s.parts["bass"] = bass
    perc = Part({0: dict(program=47, vol=120, pan=64, rev=90, cho=0), 1: dict(program=116, vol=110, pan=64, rev=80, cho=0), 2: dict(program=119, vol=95, pan=64, rev=60, cho=0),
                 9: dict(program=48, vol=100, pan=64, rev=70, cho=0, drum=True)})
    for b in range(s.bars):
        r, q = s.chord(b)
        m = bass_root(r, 38)
        perc.add(0, m, b * 4, 2.5, 92 if b % 4 == 0 else 78)
        if b >= 4:
            perc.add(1, 38, b * 4 + 2.0, 1.0, 100)
            perc.add(1, 43, b * 4 + 3.0, 1.0, 84)
        if b in (3, 7):         # timpani rolls into the next section / the loop
            for i in range(12):
                perc.add(0, m + 7, b * 4 + 2.0 + i * (1.9 / 12), 0.3, 50 + i * 4)
    perc.add(9, CRASH, 0.0, 3.0, 84)
    perc.add(9, CRASH, 16.0, 3.0, 100)
    perc.add(2, 60, 12.0, 4.0, 90)        # reverse cymbal swell into bar 4
    perc.add(2, 60, 28.0, 4.0, 100)       # and into the loop start
    s.parts["perc"] = perc
    lead = Part({0: dict(program=60, vol=112, pan=60, rev=90, cho=0), 1: dict(program=0, vol=90, pan=76, rev=90, cho=10)})
    add_line(lead, 0, [
        (0, "A4 2, D5 1.5, C5 .5"), (1, "D5 2, C5 1, Bb4 1"), (2, "A4 2, C5 1, F5 1"), (3, "E5 3, D5 1"),
        (4, "F5 2, A5 1.5, G5 .5"), (5, "F5 2, D5 1, F5 1"), (6, "G5 1.5, F5 .5, D5 1, Bb4 1"), (7, "C#5 2, E5 2"),
    ], 86, legato=0.97, accent=4)
    for b in range(4, 8):          # piano answers an octave below the horn
        for p, st, d in parse_line({4: "F4 2, A4 2", 5: "F4 2, D4 2", 6: "G4 2, D4 2", 7: "C#4 2, E4 2"}[b], b * 4):
            lead.add(1, p, st + 0.02, d * 0.95, 60)
    s.parts["lead"] = lead
    return s


def chug(part, ch, b, steps, root_m, vel, dur=0.2):
    for i, st in enumerate(steps):
        v = vel + (10 if st % 4 == 0 else 0)
        for p in (root_m, root_m + 7, root_m + 12):
            part.add(ch, p, b * 4 + st * 0.25, dur, v)


def build_combat():
    E, C, D, Bn, A, G, F = pc("E"), pc("C"), pc("D"), pc("B"), pc("A"), pc("G"), pc("F")
    chords = [(E, "m"), (E, "m"), (C, ""), (D, ""), (E, "m"), (E, "m"), (C, ""), (Bn, "7"), (A, "m"), (A, "m"), (G, ""), (D, ""), (E, "m"), (C, ""), (D, ""), (Bn, "7"), (F, ""), (Bn, "7")]
    s = Song("combat", 144, 18, chords, {"pad": -2.0, "pulse": 0.0, "bass": 0.0, "perc": 0.0, "lead": -1.0}, TARGET_LUFS - 1.0)
    sec = lambda b: 0 if b < 4 else (1 if b < 8 else (2 if b < 12 else (3 if b < 16 else 4)))   # noqa: E731
    pad = Part({0: dict(program=50, vol=100, pan=64, rev=60, cho=30), 1: dict(program=90, vol=70, pan=64, rev=50, cho=30)})
    prev = None
    for b0, n, (r, q) in s.runs():
        v = voicing(r, q, prev, 52, 75)
        prev = v
        for p in v:
            pad.add(0, p, b0 * 4, n * 4 + 0.1, 64)
            if sec(b0) >= 2:
                pad.add(1, p, b0 * 4, n * 4, 52)
    s.parts["pad"] = pad
    pulse = Part({0: dict(program=29, vol=104, pan=44, rev=25, cho=10), 1: dict(program=29, vol=96, pan=84, rev=25, cho=10)})
    shapes = [[0, 2, 3, 6, 8, 10, 11, 14], [0, 2, 4, 6, 8, 10, 12, 14], [0, 1, 2, 3, 4, 6, 8, 10, 11, 12, 14], [0, 2, 3, 4, 6, 8, 9, 10, 12, 14, 15], [0, 2, 4, 6, 8, 10, 12, 14]]
    for b in range(s.bars):
        r, q = s.chord(b)
        root_m = bass_root(r, 40)
        steps = shapes[sec(b)]
        chug(pulse, 0, b, steps, root_m, 78 if sec(b) < 2 else 84)
        if sec(b) >= 2:
            chug(pulse, 1, b, steps, root_m, 66, 0.2)
    s.parts["pulse"] = pulse
    bass = Part({0: dict(program=38, vol=116, pan=64, rev=5, cho=0)})
    for b in range(s.bars):
        r, q = s.chord(b)
        nr, _ = s.chord(b + 1)
        root_m, nroot_m = bass_root(r, 28), bass_root(nr, 28)
        sc = sec(b)
        for i in range(8):
            role = "O" if (i == 3 or (sc >= 2 and i in (3, 6))) else "R"
            if i == 7 and b % 4 == 3:
                role = "A"
            bass.add(0, role_pitch(role, root_m, q, nroot_m), b * 4 + i * 0.5, 0.42 if sc < 3 else 0.36, 100 if i % 2 == 0 else 80)
        if sc >= 3:
            for st in (2, 11, 14):
                bass.add(0, root_m + 24, b * 4 + st * 0.25, 0.2, 70)
    s.parts["bass"] = bass
    perc = Part({9: dict(program=16, vol=116, pan=64, rev=28, cho=0, drum=True), 1: dict(program=116, vol=108, pan=64, rev=50, cho=0)})
    for b in range(s.bars):
        sc = sec(b)
        for st in (0, 4, 8, 12):
            perc.add(9, KICK, b * 4 + st * 0.25, 0.2, 112 if st == 0 else 98)
        if sc >= 1:
            perc.add(9, KICK, b * 4 + 10 * 0.25, 0.2, 90)
        if sc >= 3:
            perc.add(9, KICK, b * 4 + 14 * 0.25, 0.2, 86)
        for st in (4, 12):
            perc.add(9, SNARE, b * 4 + st * 0.25, 0.25, 110)
            perc.add(9, CLAP, b * 4 + st * 0.25, 0.2, 80)
        for st in range(16):
            v = [86, 40, 66, 44][st % 4]
            if sc >= 2 or st % 2 == 0:
                perc.add(9, HAT, b * 4 + st * 0.25, 0.1, v)
        if sc >= 1:
            for st in (2, 6, 10, 14):
                perc.add(9, OHAT, b * 4 + st * 0.25, 0.2, 58)
        if b in (0, 4, 8, 12, 16):
            perc.add(9, CRASH, b * 4, 2.5, 100)
        if b % 4 == 3 and b < 16 or b == 17:       # fills; the last bar is a snare build into the loop
            if b == 17:
                for i in range(16):
                    perc.add(9, SNARE, b * 4 + i * 0.25, 0.12, 50 + i * 4)
                for st in (0, 4, 8, 12):
                    perc.add(9, KICK, b * 4 + st * 0.25, 0.2, 90)
            else:
                for i, (st, n) in enumerate([(12, SNARE), (13, TOM_HI), (14, TOM_MID), (15, TOM_LO)]):
                    perc.add(9, n, b * 4 + st * 0.25, 0.2, 96 + 4 * i)
        if b % 2 == 0 and b < 16:
            perc.add(1, 38 if b % 4 == 0 else 43, b * 4, 1.0, 104)
    s.parts["perc"] = perc
    lead = Part({0: dict(program=81, vol=96, pan=64, rev=45, cho=20), 1: dict(program=61, vol=104, pan=64, rev=50, cho=0)})
    add_line(lead, 0, [
        (0, "E5 .5, E5 .5, G5 .5, B5 .5, A5 1, G5 .5, E5 .5"), (1, "B4 .5, E5 .5, G5 1, F#5 .5, E5 .5, D5 .5, E5 .5"), (2, "G5 .5, G5 .5, C6 .5, B5 .5, G5 1, E5 1"),
        (3, "F#5 1, A5 1, D6 1, A5 1"), (4, "E5 1, G5 .5, B5 .5, E6 1, D6 .5, B5 .5"), (5, "C6 1, B5 1, G5 1, E5 1"), (6, "E6 1.5, D6 .5, C6 1, G5 1"),
        (7, "D#6 1, F#6 1, B5 1, A5 .5, F#5 .5"), (8, "A5 1, C6 1, E6 1.5, D6 .5"), (9, "C6 .5, B5 .5, A5 1, E5 2"), (10, "B5 1, D6 1, G6 1, D6 1"),
        (11, "A5 .5, F#5 .5, D5 1, F#5 .5, A5 .5, D6 1"), (12, "E6 1, B5 1, G5 1, E5 1"), (13, "E5 1, G5 1, C6 1, E6 1"), (14, "F#6 1, D6 1, A5 1, F#5 1"),
        (15, "D#6 .5, F#6 .5, B6 1, A6 1, F#6 1"), (16, "A5 1, C6 1, F6 2"), (17, "D#6 1, F#6 1, A6 1, B6 1"),
    ], 88, legato=0.9, accent=8)
    for b in list(range(8, 12)) + [16, 17]:
        r, q = s.chord(b)
        v = voicing(r, q, None, 62, 80, skip_root=False)
        for st in (0, 6, 10):
            for p in v[:4]:
                lead.add(1, p, b * 4 + st * 0.25, 0.4, 96 if st == 0 else 84)
    s.parts["lead"] = lead
    return s


def build_chase():
    A, Bb, G, E, D, F = pc("A"), pc("Bb"), pc("G"), pc("E"), pc("D"), pc("F")
    chords = [(A, "m"), (A, "m"), (Bb, ""), (G, ""), (A, "m"), (A, "m"), (Bb, ""), (E, "7"), (D, "m"), (D, "m"), (F, ""), (E, "7"),
              (A, "m"), (Bb, ""), (G, ""), (E, "7"), (A, "m"), (Bb, ""), (E, "7"), (E, "7")]
    s = Song("chase", 160, 20, chords, {"pad": -1.0, "pulse": 0.0, "bass": 0.0, "perc": 0.0, "lead": -1.0}, TARGET_LUFS - 1.0)
    sec = lambda b: 0 if b < 4 else (1 if b < 8 else (2 if b < 12 else (3 if b < 16 else 4)))   # noqa: E731
    pad = Part({0: dict(program=44, vol=104, pan=64, rev=45, cho=20), 1: dict(program=51, vol=80, pan=64, rev=50, cho=20)})
    prev = None
    for b0, n, (r, q) in s.runs():
        v = voicing(r, q, prev, 54, 79)
        prev = v
        for b in range(b0, b0 + n):
            for p in v:
                pad.add(0, p, b * 4, 4.05, 68 + (8 if sec(b) >= 2 else 0))
                if sec(b) >= 3:
                    pad.add(1, p, b * 4, 4.0, 58)
    s.parts["pad"] = pad
    pulse = Part({0: dict(program=45, vol=106, pan=56, rev=30, cho=10), 1: dict(program=45, vol=90, pan=76, rev=30, cho=10)})
    prevv = None
    for b in range(s.bars):
        r, q = s.chord(b)
        prevv = voicing(r, q, prevv, 57, 80, skip_root=False)
        tones = prevv
        seq = [tones[0], tones[1], tones[2], tones[1], tones[0], tones[2], tones[-1], tones[2]]
        for st in range(16):
            p = seq[st % len(seq)] + (12 if sec(b) >= 3 and st % 8 == 7 else 0)
            v = 84 if st % 4 == 0 else (66 if st % 2 == 0 else 54)
            if sec(b) == 0 and st % 2 == 1:
                continue
            pulse.add(0, p, b * 4 + st * 0.25, 0.2, v)
            if sec(b) >= 2 and st % 4 == 2:
                pulse.add(1, p + 12 if p < 70 else p, b * 4 + st * 0.25 + 0.01, 0.2, 60)
    s.parts["pulse"] = pulse
    bass = Part({0: dict(program=38, vol=116, pan=64, rev=5, cho=0)})
    pat = [(0, "R"), (2, "R"), (3, "R"), (4, "O"), (6, "R"), (8, "R"), (10, "5"), (11, "R"), (12, "O"), (14, "R"), (15, "R")]
    pat2 = [(0, "R"), (1, "R"), (2, "O"), (3, "R"), (4, "R"), (6, "O"), (7, "R"), (8, "R"), (9, "R"), (10, "O"), (11, "5"), (12, "R"), (13, "R"), (14, "O"), (15, "A")]
    for b in range(s.bars):
        r, q = s.chord(b)
        nr, _ = s.chord(b + 1)
        root_m, nroot_m = bass_root(r, 33), bass_root(nr, 33)
        for st, role in (pat if sec(b) < 2 else pat2):
            bass.add(0, role_pitch(role, root_m, q, nroot_m), b * 4 + st * 0.25, 0.2, 104 if st % 4 == 0 else 84)
    s.parts["bass"] = bass
    perc = Part({9: dict(program=24, vol=114, pan=64, rev=22, cho=0, drum=True), 1: dict(program=116, vol=108, pan=64, rev=40, cho=0)})
    for b in range(s.bars):
        sc = sec(b)
        for st in ([0, 3, 8, 11, 14] if sc < 2 else [0, 3, 6, 8, 11, 14]):
            perc.add(9, KICK, b * 4 + st * 0.25, 0.2, 112 if st == 0 else 94)
        for st in (4, 12):
            perc.add(9, SNARE, b * 4 + st * 0.25, 0.25, 112)
        if sc >= 1:
            perc.add(9, SNARE, b * 4 + 15 * 0.25, 0.12, 70)
            perc.add(9, SNARE, b * 4 + 9 * 0.25, 0.12, 52)
        for st in range(16):
            perc.add(9, HAT, b * 4 + st * 0.25, 0.08, [88, 46, 70, 50][st % 4])
        if sc >= 2:
            for st in (2, 6, 10, 14):
                perc.add(9, OHAT, b * 4 + st * 0.25, 0.15, 60)
        if b in (0, 4, 8, 12, 16):
            perc.add(9, CRASH, b * 4, 2.0, 104)
        if b % 4 == 3:
            for i, (st, n) in enumerate([(10, TOM_HI), (11, TOM_HI), (12, TOM_MID), (13, TOM_MID), (14, TOM_LO), (15, TOM_LO)]):
                perc.add(9, n, b * 4 + st * 0.25, 0.15, 90 + 4 * i)
        perc.add(1, 33 if b % 2 == 0 else 40, b * 4, 0.8, 100)
        if sc >= 2:
            perc.add(1, 33, b * 4 + 2.0, 0.8, 90)
    s.parts["perc"] = perc
    lead = Part({0: dict(program=81, vol=98, pan=64, rev=40, cho=20), 1: dict(program=62, vol=104, pan=64, rev=45, cho=0)})
    add_line(lead, 0, [
        (0, "A5 .5, C6 .5, E6 .5, C6 .5, A5 .5, C6 .5, E6 1"), (1, "D6 .5, C6 .5, B5 .5, C6 .5, A5 2"), (2, "Bb5 .5, D6 .5, F6 .5, D6 .5, Bb5 .5, D6 .5, F6 1"),
        (3, "G5 .5, B5 .5, D6 .5, B5 .5, D6 1, E6 1"),
        (4, "A5 .5, C6 .5, E6 .5, C6 .5, A5 .5, C6 .5, E6 1"), (5, "E6 1, D6 1, C6 1, A5 1"), (6, "F6 1, D6 1, Bb5 1, D6 1"), (7, "G#5 .5, B5 .5, D6 .5, B5 .5, E6 2"),
        (8, "D6 1, F6 1, A6 1, F6 1"), (9, "E6 .5, F6 .5, E6 .5, D6 .5, A5 2"), (10, "C6 1, F6 1, A6 1.5, G6 .5"), (11, "G#5 1, B5 1, D6 1, E6 1"),
        (12, "A6 .5, G6 .5, E6 .5, C6 .5, A5 2"), (13, "Bb5 1, D6 1, F6 1, Bb6 1"), (14, "B5 1, D6 1, G6 1, B6 1"), (15, "G#5 .5, B5 .5, E6 1, D6 1, B5 1"),
        (16, "A5 .5, C6 .5, E6 .5, A6 .5, G6 1, E6 1"), (17, "Bb5 .5, D6 .5, F6 .5, Bb6 .5, A6 1, F6 1"), (18, "G#5 1, B5 1, D6 1, E6 1"), (19, "E6 .5, D6 .5, B5 .5, G#5 .5, E5 2"),
    ], 90, legato=0.88, accent=8)
    for b in list(range(8, 12)) + list(range(16, 20)):
        r, q = s.chord(b)
        v = voicing(r, q, None, 60, 80, skip_root=False)
        for st in (3, 6, 10, 14):
            for p in v[:4]:
                lead.add(1, p, b * 4 + st * 0.25, 0.3, 92 if st == 14 else 80)
    s.parts["lead"] = lead
    return s


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
# theme layers: one MIDI file each, on the grid of the track they colour
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

def layer_part(name, base):
    """returns Part for a theme layer built on the chords of `base` (a Song)"""
    s = base
    D = Part
    if name == "district_0":     # neon market: marimba bells (dotted), shaker and tambourine
        part = D({0: dict(program=12, vol=104, pan=70, rev=70, cho=40), 1: dict(program=108, vol=84, pan=56, rev=80, cho=20), 9: dict(program=0, vol=70, pan=64, rev=30, cho=0, drum=True)})
        prev = None
        for b in range(s.bars):
            r, q = s.chord(b)
            prev = voicing(r, q, prev, 64, 88, skip_root=False)
            for i, st in enumerate([0, 3, 6, 8, 11, 14]):
                part.add(0, prev[(i * 2) % len(prev)], b * 4 + st * 0.25, 0.4, 66 if st in (0, 6) else 52)
            if b % 2 == 1:
                part.add(1, prev[-1] + 12 if prev[-1] < 80 else prev[-1], b * 4 + 2.0, 1.2, 56)
            for st in range(16):
                part.add(9, SHAKER, b * 4 + st * 0.25, 0.08, 34 if st % 4 == 0 else 22)
            for st in (4, 12):
                part.add(9, TAMB, b * 4 + st * 0.25, 0.1, 50)
        return part
    if name == "district_1":     # foundry: bells, half-time taiko, metal on the back-beat, a low drone
        part = D({0: dict(program=14, vol=96, pan=60, rev=100, cho=0), 1: dict(program=116, vol=108, pan=64, rev=60, cho=0), 2: dict(program=38, vol=84, pan=64, rev=10, cho=0),
                  9: dict(program=0, vol=80, pan=64, rev=40, cho=0, drum=True)})
        for b0, n, (r, q) in s.runs():
            part.add(2, bass_root(r, 38), b0 * 4, n * 4 + 0.05, 70)
            part.add(0, bass_root(r, 62), b0 * 4, 6.0, 64)
            part.add(0, bass_root(r, 62) + 7, b0 * 4 + 2.0, 6.0, 52)
        for b in range(s.bars):
            part.add(1, 38, b * 4 + 2.0, 1.0, 104)
            if b % 2 == 1:
                part.add(1, 43, b * 4 + 3.5, 0.5, 80)
            for st in (4, 12):
                part.add(9, COWBELL, b * 4 + st * 0.25, 0.2, 52)
            part.add(9, 53, b * 4 + 8 * 0.25, 0.4, 46)
        return part
    if name == "district_2":     # rain slums: swung electric-piano stabs, brushes
        part = D({0: dict(program=5, vol=100, pan=60, rev=90, cho=70), 1: dict(program=24, vol=80, pan=72, rev=70, cho=10), 9: dict(program=40, vol=84, pan=64, rev=50, cho=0, drum=True)})
        prev = None
        for b in range(s.bars):
            r, q = s.chord(b)
            prev = voicing(r, q, prev, 55, 74)
            for st in (3, 7, 10, 14):
                for p in prev[:4]:
                    part.add(0, p, swing_start(b, st, 0.33), 0.5, 62 if st in (7, 14) else 50)
            if b % 4 == 3:
                for i in range(4):
                    part.add(1, voicing(r, q, None, 62, 74, skip_root=False)[i % 3], b * 4 + 2.0 + i * 0.5, 0.6, 54)
            for st in range(0, 16, 2):
                part.add(9, HAT, swing_start(b, st, 0.33), 0.1, 30)
            for st in (4, 12):
                part.add(9, SNARE, swing_start(b, st, 0.33), 0.4, 46)
        return part
    if name == "district_3":     # glass towers: celesta arpeggios, glockenspiel, crystal pad
        part = D({0: dict(program=8, vol=96, pan=60, rev=100, cho=30), 1: dict(program=9, vol=84, pan=74, rev=110, cho=0), 2: dict(program=98, vol=70, pan=64, rev=110, cho=50)})
        prev = None
        for b in range(s.bars):
            r, q = s.chord(b)
            prev = voicing(r, q, prev, 72, 96, skip_root=False)
            seq = prev + prev[-2:0:-1]
            for st in range(16):
                part.add(0, seq[st % len(seq)], b * 4 + st * 0.25, 0.3, 54 if st % 4 == 0 else 38)
            part.add(1, prev[-1], b * 4 + 2.0, 1.5, 60)
        for b0, n, (r, q) in s.runs():
            v = voicing(r, q, None, 74, 91)
            for p in v[:3]:
                part.add(2, p, b0 * 4, n * 4 + 0.1, 40)
        return part
    if name == "night":          # night pad: atmosphere, voice oohs, a slow harp
        part = D({0: dict(program=99, vol=94, pan=64, rev=110, cho=40), 1: dict(program=53, vol=84, pan=64, rev=110, cho=0), 2: dict(program=46, vol=76, pan=64, rev=100, cho=20)})
        prev = None
        for b0, n, (r, q) in s.runs():
            prev = voicing(r, q, prev, 55, 79)
            for p in prev:
                part.add(0, p, b0 * 4, n * 4 + 0.1, 52)
            for p in prev[-3:]:
                part.add(1, p, b0 * 4, n * 4 + 0.1, 44)
        for b in range(s.bars):
            r, q = s.chord(b)
            t = voicing(r, q, None, 62, 86, skip_root=False)
            for i in range(2):
                part.add(2, t[(b + i * 2) % len(t)], b * 4 + i * 2.0, 2.0, 46)
        return part
    if name == "boss":           # choir, low brass, timpani rolls, orchestra hits
        part = D({0: dict(program=52, vol=106, pan=64, rev=100, cho=0), 1: dict(program=57, vol=100, pan=64, rev=60, cho=0), 2: dict(program=47, vol=118, pan=64, rev=80, cho=0),
                  3: dict(program=55, vol=100, pan=64, rev=60, cho=0)})
        prev = None
        for b0, n, (r, q) in s.runs():
            prev = voicing(r, q, prev, 55, 79)
            for p in prev[:4]:
                part.add(0, p, b0 * 4, n * 4 + 0.1, 70)
        for b in range(s.bars):
            r, q = s.chord(b)
            m = bass_root(r, 40)
            part.add(1, m, b * 4, 0.9, 100)
            part.add(1, m, b * 4 + 1.5, 0.4, 80)
            part.add(2, bass_root(r, 38), b * 4, 1.0, 100)
            if b % 4 == 3 or b == 17:
                for i in range(16):
                    part.add(2, m + 7 if m + 7 < 56 else m, b * 4 + 2.0 + i * 0.125, 0.15, 56 + i * 3)
        for b in (0, 4, 8, 12, 16):
            part.add(3, 52, b * 4, 0.6, 108)
        return part
    if name == "chase":         # orchestra-hit stabs, staccato synth strings, taiko double time
        part = D({0: dict(program=55, vol=104, pan=64, rev=50, cho=0), 1: dict(program=51, vol=96, pan=64, rev=40, cho=20), 2: dict(program=116, vol=108, pan=64, rev=40, cho=0)})
        prev = None
        for b in range(s.bars):
            r, q = s.chord(b)
            prev = voicing(r, q, prev, 57, 76)
            for st in (3, 7, 11, 15):
                part.add(0, prev[0], b * 4 + st * 0.25, 0.15, 90)
            m = bass_root(r, 45)
            for i in range(8):
                for p in (m, m + 7):
                    part.add(1, p, b * 4 + i * 0.5, 0.25, 74 if i % 2 == 0 else 58)
            for st in range(0, 16, 2):
                part.add(2, 38 if st % 4 == 0 else 43, b * 4 + st * 0.25, 0.2, 90 if st % 4 == 0 else 70)
        return part
    raise KeyError(name)


LAYERS = {   # layer name -> (file name, song it sits on)
    "district_0": ("music_district_0", "explore"), "district_1": ("music_district_1", "explore"), "district_2": ("music_district_2", "explore"),
    "district_3": ("music_district_3", "explore"), "night": ("music_night", "explore"), "boss": ("music_boss", "combat"), "chase": ("music_chase", "chase"),
}
BUILDERS = {"explore": build_explore, "menu": build_menu, "combat": build_combat, "chase": build_chase}


def stem_file(song, stem):
    """explore keeps the legacy names (music_pad ...), the others are mus_<track>_<stem>"""
    return "music_%s" % stem if song == "explore" else "mus_%s_%s" % (song, stem)


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
# rendering and mastering
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

BLOCK = 64                      # FluidSynth renders (and starts notes) in blocks of 64 samples
LOOP_BLOCKS = 20672             # one loop pass = 1,323,008 samples = 30.00018 s, an exact number of blocks: every event of every pass lands on the same block, so the passes are identical
PASS_SAMPLES = LOOP_BLOCKS * BLOCK


def render_midi(midi_path, sf2, loop_ticks):
    """Plays a MIDI file (the loop written REPEATS times) through FluidSynth + the SoundFont, one event per 64-sample block, and returns the THIRD pass as a (2, N) float array.

    A pass is mapped to exactly LOOP_BLOCKS blocks (ticks are scaled by LOOP_BLOCKS / loop_ticks, a stretch of 6 ppm): block-quantised note starts then repeat exactly from pass to
    pass and the tails of pass 2 run across the seam into pass 3 as steady state. The pass is stretched to N samples by FFT resampling (exact for a periodic signal)."""
    import fluidsynth
    mf = mido.MidiFile(midi_path)
    ev = []
    tick = 0
    for i, msg in enumerate(mf.tracks[0]):
        tick += msg.time
        if msg.type in ("note_on", "note_off", "control_change", "program_change"):
            ev.append((int(round(tick * LOOP_BLOCKS / loop_ticks)), i, msg))
    ev.sort(key=lambda e: (e[0], e[1]))
    fs = fluidsynth.Synth(gain=0.8, samplerate=SR)
    fs.setting("synth.polyphony", 256)
    sfid = fs.sfload(sf2)
    fs.set_reverb(roomsize=0.6, damping=0.35, width=0.5, level=0.7)
    fs.set_chorus(nr=3, level=1.2, speed=0.3, depth=6.0, type=0)      # 0.3 Hz = 9 whole LFO cycles per 30 s pass, so even the chorus repeats
    total_blocks = 3 * LOOP_BLOCKS + 8
    chunks = []
    at = 0
    for blk, _, msg in ev:
        if blk >= total_blocks:
            break
        if blk > at:
            chunks.append(fs.get_samples((blk - at) * BLOCK))
            at = blk
        t = msg.type
        if t == "note_on":
            fs.noteon(msg.channel, msg.note, msg.velocity)
        elif t == "note_off":
            fs.noteoff(msg.channel, msg.note)
        elif t == "control_change":
            fs.cc(msg.channel, msg.control, msg.value)
        else:
            fs.program_select(msg.channel, sfid, 128 if msg.channel == 9 else 0, msg.program)
    if total_blocks > at:
        chunks.append(fs.get_samples((total_blocks - at) * BLOCK))
    fs.delete()
    x = np.concatenate(chunks).astype(np.float64).reshape(-1, 2).T / 32768.0
    cut = x[:, 2 * PASS_SAMPLES - PRE_ROLL:3 * PASS_SAMPLES - PRE_ROLL]
    return signal.resample(cut, N, axis=1)


def highpass(x, hz=30.0):
    sos = signal.butter(2, hz, "highpass", fs=SR, output="sos")
    n = x.shape[-1]
    return signal.sosfilt(sos, np.concatenate([x, x, x], axis=-1), axis=-1)[..., n:2 * n]      # filtered as a loop: the middle copy has no start-up transient


def shared_gain(total, ceil_db):
    """look-ahead limiter gain curve (loop-wrapped) computed on the summed signal; the SAME curve is applied to each stem"""
    m = np.max(np.abs(total), axis=0)
    lim = am.limiter(m, ceil_db=ceil_db, look=0.006, wrap=True)
    g = np.where(m > 1e-9, lim / np.maximum(m, 1e-9), 1.0)
    return np.clip(g, 0.0, 1.0)


def master_stems(arrs, trims, target_lufs, peak_db):
    arrs = {k: highpass(v) * 10 ** (trims.get(k, 0.0) / 20) for k, v in arrs.items()}
    scale = 1.0
    for _ in range(24):
        tot = sum(arrs.values()) * scale
        g = shared_gain(tot, peak_db)
        lim = tot * g[None, :]
        err = target_lufs - am.lufs_like(lim)
        if abs(err) < 0.05:
            break
        scale *= 10 ** (err / 20)
    tot = sum(arrs.values()) * scale
    g = shared_gain(tot, peak_db)
    return {k: v * scale * g[None, :] for k, v in arrs.items()}


def to_ogg(x, path, mono=False, quality=2.0):
    if mono:
        x = x.mean(axis=0, keepdims=True)
    data = np.clip(x.T, -1.0, 1.0).astype("<f4").tobytes()
    ch = x.shape[0]
    cmd = ["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-", "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=data, check=True)


def decode_ogg(path):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ar", str(SR), "-ac", "2", "-"], capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").astype(np.float64).reshape(-1, 2).T


def itu_lufs(x):
    """integrated loudness (ITU-R BS.1770 / EBU R128, gated) of a (2, n) array, measured by ffmpeg's ebur128 filter"""
    data = np.clip(x.T, -1.0, 1.0).astype("<f4").tobytes()
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-af", "ebur128", "-f", "null", "-"], input=data, capture_output=True)
    text = r.stderr.decode("utf8", "replace")
    return float(re.findall(r"I:\s+(-?[\d.]+) LUFS", text)[-1])


def seam_ratio(x):
    d = np.abs(np.diff(x, axis=-1))
    return float(np.max(np.abs(x[..., 0] - x[..., -1]) / (np.max(d, axis=-1) + 1e-12)))


def write_manifest(out_dir, songs, want):
    """tools/music/manifest.json: what was measured on the encoded OGG files (tests/test_music_midi.gd cross-checks it against the files and the MIDI)."""
    files = []
    tracks = {}
    for name, song in songs.items():
        xs = []
        for stem in STEMS:
            fn = stem_file(name, stem) + ".ogg"
            path = os.path.join(out_dir, fn)
            if not os.path.exists(path):
                continue
            x = decode_ogg(path)
            xs.append(x)
            files.append(dict(file=fn, kind="stem", track=name, stem=stem, bpm=song.bpm, bars=song.bars, samples=int(x.shape[1]), seconds=round(x.shape[1] / SR, 4),
                              lufs=round(float(am.lufs_like(x)), 2), lufs_itu=round(itu_lufs(x), 2), peak_db=round(float(20 * np.log10(np.max(np.abs(x)) + 1e-9)), 2),
                              seam=round(seam_ratio(x), 3), bytes=os.path.getsize(path), midi="midi/%s_%s.mid" % (name, stem)))
        if len(xs) == len(STEMS):
            n = min(x.shape[1] for x in xs)
            tot = sum(x[:, :n] for x in xs)
            tracks[name] = dict(bpm=song.bpm, bars=song.bars, lufs=round(float(am.lufs_like(tot)), 2), lufs_itu=round(itu_lufs(tot), 2), peak_db=round(float(20 * np.log10(np.max(np.abs(tot)))), 2))
    for lname, (fname, base) in LAYERS.items():
        path = os.path.join(out_dir, fname + ".ogg")
        if os.path.exists(path):
            x = decode_ogg(path)
            files.append(dict(file=fname + ".ogg", kind="layer", track=base, stem=lname, bpm=songs[base].bpm, bars=songs[base].bars, samples=int(x.shape[1]), seconds=round(x.shape[1] / SR, 4),
                              lufs=round(float(am.lufs_like(x)), 2), lufs_itu=round(itu_lufs(x), 2), peak_db=round(float(20 * np.log10(np.max(np.abs(x)) + 1e-9)), 2),
                              seam=round(seam_ratio(x), 3), bytes=os.path.getsize(path), midi="midi/layer_%s.mid" % lname))
    man = dict(generator="tools/music/compose.py", soundfont="FluidR3_GM.sf2 (MIT)", sample_rate=SR, loop_samples=N, loop_seconds=LOOP_SECONDS, tracks=tracks, files=files)
    with open(os.path.join(HERE, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
        f.write("\n")
    return len(files)


# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None, help="explore menu combat chase layers")
    ap.add_argument("--midi-only", action="store_true")
    ap.add_argument("--out", default=os.path.join(GODOT, "assets", "audio"))
    ap.add_argument("--soundfont", default=DEFAULT_SF2)
    ap.add_argument("--midi-dir", default=os.path.join(HERE, "midi"))
    ap.add_argument("--quality", type=float, default=1.0, help="libvorbis -q:a (1 = about 80 kbps, what is committed)")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    want = set(args.only) if args.only else {"explore", "menu", "combat", "chase", "layers"}
    os.makedirs(args.midi_dir, exist_ok=True)
    songs = {}
    for name, fn in BUILDERS.items():
        song = fn()
        for stem in STEMS:
            humanize(song.parts[stem], "%s_%s" % (name, stem))
        songs[name] = song
    jobs = []        # (kind, key, midi path)
    for name, song in songs.items():
        for stem in STEMS:
            path = os.path.join(args.midi_dir, "%s_%s.mid" % (name, stem))
            write_midi(path, song.parts[stem], song.bpm, song.beats)
            if name in want:
                jobs.append(("stem", (name, stem), path, song.beats * TPB))
    layer_parts = {}
    for lname, (fname, base) in LAYERS.items():
        part = layer_part(lname, songs[base])
        humanize(part, "layer_" + lname, 0.01, 4)
        path = os.path.join(args.midi_dir, "layer_%s.mid" % lname)
        write_midi(path, part, songs[base].bpm, songs[base].beats)
        layer_parts[lname] = path
        if "layers" in want:
            jobs.append(("layer", lname, path, songs[base].beats * TPB))
    print("wrote MIDI for %d stems and %d layers into %s" % (len(songs) * len(STEMS), len(LAYERS), args.midi_dir))
    if args.midi_only:
        return 0
    if not os.path.exists(args.soundfont) or shutil.which("fluidsynth") is None:
        print("SoundFont or fluidsynth missing: install fluidsynth + fluid-soundfont-gm (see the docstring)", file=sys.stderr)
        return 2
    work = tempfile.mkdtemp(prefix="qt_music_")
    try:
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            results = list(ex.map(lambda j: render_midi(j[2], args.soundfont, j[3]), jobs))
        rendered = {(j[0], j[1]): r for j, r in zip(jobs, results)}
        os.makedirs(args.out, exist_ok=True)
        for name, song in songs.items():
            if name not in want:
                continue
            arrs = {stem: rendered[("stem", (name, stem))] for stem in STEMS}
            out = master_stems(arrs, song.trims, song.target, SUM_PEAK_DB)
            for stem in STEMS:
                to_ogg(out[stem], os.path.join(args.out, stem_file(name, stem) + ".ogg"), mono=(stem == "bass"), quality=args.quality)
            tot = sum(out.values())
            print("%-8s %3d BPM %2d bars  sum %.1f LU, peak %.1f dBFS" % (name, song.bpm, song.bars, am.lufs_like(tot), 20 * np.log10(np.max(np.abs(tot)))))
            if name == "explore":      # the legacy single loop (Sfx falls back to it when the stems cannot load): pad + pulse + bass
                mix = out["pad"] + out["pulse"] + out["bass"]
                mix *= 10 ** (-20.0 / 20) / (np.sqrt(np.mean(mix ** 2)) + 1e-9) * 10 ** (-1.0 / 20)
                mix *= min(1.0, 10 ** (-7.0 / 20) / (np.max(np.abs(mix)) + 1e-9))
                to_ogg(mix, os.path.join(args.out, "music_ambient.ogg"), mono=False, quality=args.quality)
        if "layers" in want:
            for lname, (fname, base) in LAYERS.items():
                x = master_stems({"x": rendered[("layer", lname)]}, {}, LAYER_LUFS, LAYER_PEAK_DB)["x"]
                to_ogg(x, os.path.join(args.out, fname + ".ogg"), quality=args.quality)
                print("%-18s %.1f LU peak %.1f dBFS" % (fname, am.lufs_like(x), 20 * np.log10(np.max(np.abs(x)))))
        if not args.only:
            print("manifest.json: %d files measured" % write_manifest(args.out, songs, want))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
