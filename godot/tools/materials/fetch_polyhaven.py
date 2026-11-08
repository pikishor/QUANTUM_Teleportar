#!/usr/bin/env python3
"""Download the 1K JPG maps (diffuse, arm = AO/roughness/metal, GL normal) of the Poly Haven (CC0) sets listed in world_materials.json into
assets_incoming/polyhaven_raw/<slug>/ (not committed: the packed result is). Plain curl with a descriptive user agent.
  python3 tools/materials/fetch_polyhaven.py [--res 1k]"""
import argparse, json, os, subprocess, sys

UA = "QuantumTeleportar-asset-fetch/1.0 (CC0 asset import; github.com/pikishor/QUANTUM_Teleportar)"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAPS = ("diff", "arm", "nor_gl")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--res", default="1k")
    ap.add_argument("--out", default=os.path.join(ROOT, "assets_incoming", "polyhaven_raw"))
    a = ap.parse_args()
    sets = json.load(open(os.path.join(HERE, "world_materials.json")))["sets"]
    slugs = sorted({v["slug"] for v in sets.values()})
    bad = 0
    for s in slugs:
        os.makedirs(os.path.join(a.out, s), exist_ok=True)
        for m in MAPS:
            dst = os.path.join(a.out, s, "%s_%s_%s.jpg" % (s, m, a.res))
            if os.path.exists(dst) and os.path.getsize(dst) > 1000:
                continue
            url = "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/%s/%s/%s_%s_%s.jpg" % (a.res, s, s, m, a.res)
            r = subprocess.run(["curl", "-sS", "-f", "-L", "-A", UA, "-o", dst, url])
            if r.returncode != 0:
                print("FAILED", url); bad += 1
    print("%d slugs, %d failures" % (len(slugs), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
