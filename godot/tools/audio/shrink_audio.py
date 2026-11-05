#!/usr/bin/env python3
"""Size pass over assets/audio (idempotent, run after the make_*.py generators; wired into build_assets.sh).
  * long one-shots (booms, distant fire, crashes, explosions, sirens, stings, core, mission_complete) and the legacy 30 s music_ambient loop: WAV -> mono OGG q4 (the WAV and its .import are removed)
  * stereo ambience beds (rain, wind, city hum, far traffic): mono OGG q3
  * adaptive music stems: OGG q4 (stereo kept so the five stems stay sample-locked)
Short effects (under about 1.5 s), shots, UI and the smpl-looped WAV beds stay uncompressed.
Usage: python3 -I tools/audio/shrink_audio.py [--dir assets/audio]"""
import argparse, os, re, subprocess, sys

TO_OGG = re.compile(r"^(boom(_\d)?|distant_boom_\d|distant_gunfire_\d|car_crash_\d|explosion_small_\d|siren(_\d)?|sting_(boss|chase|combat_\d|death|win)|core|mission_complete|music_ambient)\.wav$")
MONO_BEDS = re.compile(r"^(rain_\w+|wind|city_hum|traffic_far)\.ogg$")
STEMS = re.compile(r"^music_(pulse|lead|pad|perc|bass)\.ogg$")
LOOP_IMPORT = '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[deps]\n\nsource_file="res://assets/audio/%s"\n\n[params]\n\nloop=%s\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n'


def enc(src, dst, q, mono):
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", src] + (["-ac", "1"] if mono else []) + ["-c:a", "libvorbis", "-q:a", str(q), "-map_metadata", "-1", "-fflags", "+bitexact", dst]
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "audio"))
    d = ap.parse_args().dir
    before = sum(os.path.getsize(os.path.join(d, n)) for n in os.listdir(d) if n.endswith((".wav", ".ogg")))
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        tmp = p + ".tmp.ogg"
        if TO_OGG.match(n):
            out = p[:-4] + ".ogg"
            enc(p, tmp, 4, True)
            os.replace(tmp, out)
            os.remove(p)
            if os.path.exists(p + ".import"):
                os.remove(p + ".import")
            imp = out + ".import"
            if not os.path.exists(imp):
                open(imp, "w").write(LOOP_IMPORT % (os.path.basename(out), "true" if n.startswith("music_ambient") else "false"))
        elif MONO_BEDS.match(n) and n.endswith(".ogg"):
            ch = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", p], capture_output=True, text=True).stdout.strip()
            if ch != "1":
                enc(p, tmp, 3, True)
                os.replace(tmp, p)
        elif STEMS.match(n):
            br = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=bit_rate", "-of", "csv=p=0", p], capture_output=True, text=True).stdout.strip()
            if br.isdigit() and int(br) > 135000:
                enc(p, tmp, 4, False)
                os.replace(tmp, p)
    after = sum(os.path.getsize(os.path.join(d, n)) for n in os.listdir(d) if n.endswith((".wav", ".ogg")))
    print("audio folder %.2f MB -> %.2f MB" % (before / 1048576, after / 1048576))


main()
