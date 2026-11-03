#!/usr/bin/env python3
"""Size tuning of the import settings for the mobile pack (idempotent; rewrites tracked .import files).
  * packed ORM maps and emission masks (data, low visual sensitivity): size_limit 1024 (a quarter of the texels); ORM also compress/high_quality=false (ETC2, 4 bit per pixel); albedo and normal maps stay 2K ASTC (test_perf_budget asserts it)
  * long 44.1 kHz mono sound effects, ambience and crowd babble: force/max_rate=true at 22050 Hz (half the samples; weapon shots, UI and stings stay full rate)
Usage: python3 -I tools/release/tune_imports.py [--check]   (--check only reports; exit 1 when something would change)"""
import glob, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
LOW_RATE = re.compile(r"^(babble|step_|impact_|distant_|music_ambient|siren|horn|radio_glitch|car_|land_|rain|wind|ambient|boom|thunder)")


def set_key(text, key, value):
    pat = re.compile(r"^%s=.*$" % re.escape(key), re.M)
    return pat.sub("%s=%s" % (key, value), text) if pat.search(text) else text


def main():
    check = "--check" in sys.argv
    changed = 0
    for f in glob.glob(os.path.join(ROOT, "assets", "**", "*.import"), recursive=True):
        src = os.path.basename(f)[:-7]
        text = open(f, encoding="utf-8").read()
        new = text
        if src.endswith((".png", ".jpg")) and "compress/high_quality=true" in text:
            pass
        if src.endswith((".png", ".jpg")):
            stem = os.path.splitext(src)[0]
            if stem.endswith(("_orm", "_emit")) and "surface_" not in stem:
                new = set_key(new, "process/size_limit", "1024")
                if stem.endswith("_orm"):
                    new = set_key(new, "compress/high_quality", "false")
        elif src.endswith(".wav") and LOW_RATE.match(src):
            new = set_key(new, "force/max_rate", "true")
            new = set_key(new, "force/max_rate_hz", "22050")
        if new != text:
            changed += 1
            if not check:
                open(f, "w", encoding="utf-8").write(new)
    print("%s %d import file(s)" % ("would change" if check else "changed", changed))
    sys.exit(1 if (check and changed) else 0)


main()
