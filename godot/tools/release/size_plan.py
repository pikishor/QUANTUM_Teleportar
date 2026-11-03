#!/usr/bin/env python3
"""Estimate the Android pack composition from the CURRENT import (run tools/import.sh first): only the files a phone loads
(ETC2 / ASTC textures, samples, ogg, scenes), each .import's dest_files, minus what export_presets.cfg excludes.
Prints MB per class and the biggest textures, and whether the AAB base module (200 MB) fits.  Usage: python3 -I tools/release/size_plan.py [--json]"""
import fnmatch, glob, json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
LIMIT_MB = 200.0
PHONE = (".etc2.ctex", ".astc.ctex", ".sample", ".oggvorbisstr", ".mp3str", ".scn", ".res", ".fontdata")


def excludes():
    pats = []
    for m in re.finditer(r'^exclude_filter="(.*)"', open(os.path.join(ROOT, "export_presets.cfg"), encoding="utf-8").read(), re.M):
        pats += [p.strip() for p in m.group(1).split(",") if p.strip()]
    return sorted(set(pats))


def plan():
    ex = excludes()
    rows = []
    for f in glob.glob(os.path.join(ROOT, "assets", "**", "*.import"), recursive=True):
        src = os.path.relpath(f[:-7], ROOT).replace(os.sep, "/")
        if any(fnmatch.fnmatch(src, p) for p in ex):
            continue
        text = open(f, encoding="utf-8").read()
        m = re.search(r"^dest_files=\[(.*)\]", text, re.M)
        if not m:
            continue
        size = 0
        for d in re.findall(r'"res://([^"]+)"', m.group(1)):
            if d.endswith(PHONE):
                p = os.path.join(ROOT, d)
                size += os.path.getsize(p) if os.path.exists(p) else 0
        rows.append((size, src))
    return rows, ex


def klass(src):
    if "/models/" in src:
        return "models"
    if src.endswith((".wav", ".ogg")):
        return "audio"
    if src.startswith("assets/textures/surface_"):
        return "surface textures (2K PBR sets)"
    if src.endswith((".png", ".jpg")):
        return "model/other textures"
    return "other"


def main():
    rows, ex = plan()
    by = {}
    for s, src in rows:
        by[klass(src)] = by.get(klass(src), 0) + s
    total = sum(by.values()) / 1048576
    if "--json" in sys.argv:
        print(json.dumps({"total_mb": round(total, 1), "by_class_mb": {k: round(v / 1048576, 1) for k, v in by.items()}, "excluded": ex}))
        return
    print("estimated phone content (excluded: %s)" % ", ".join(ex))
    for k, v in sorted(by.items(), key=lambda kv: -kv[1]):
        print("  %-34s %7.1f MB" % (k, v / 1048576))
    print("  %-34s %7.1f MB  (+ engine template about 60-90 MB; base-module limit %d MB)" % ("TOTAL content", total, LIMIT_MB))
    pad = sum(s for s, src in rows if src.startswith("assets/textures/surface_")) / 1048576
    pad2 = pad + sum(s for s, src in rows if src.endswith("_normal.png") and "/surface_" not in src) / 1048576
    print("Play Asset Delivery plan (install-time pack, same download, not counted in the 200 MB base module):")
    print("  pack 'hires_surfaces' = assets/textures/surface_*           -> base module content %6.1f MB" % (total - pad))
    print("  + 2K model normal maps                                      -> base module content %6.1f MB" % (total - pad2))
    print("biggest:")
    for s, src in sorted(rows, reverse=True)[:6]:
        print("  %6.1f MB  %s" % (s / 1048576, src))


main()
