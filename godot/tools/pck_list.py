#!/usr/bin/env python3
"""Summarise a Godot 4 .pck: what is inside, by kind, and the biggest files.  Usage: pck_list.py file.pck [--all]
Reads the format versions 2 and 3 header (magic GDPC, 64-bit file offsets, directory at dir_offset)."""
import struct, sys, collections


def read_pck(path):
    f = open(path, "rb")
    magic, version, vmaj, vmin, vpatch, flags = struct.unpack("<6I", f.read(24))
    if magic != 0x43504447:
        raise SystemExit("not a Godot pck (magic %08x)" % magic)
    file_base, = struct.unpack("<Q", f.read(8))
    if version >= 2:
        dir_offset, = struct.unpack("<Q", f.read(8))
        f.seek(dir_offset)
    else:
        f.seek(16 * 4, 1)
    count, = struct.unpack("<I", f.read(4))
    entries = []
    for _ in range(count):
        n, = struct.unpack("<I", f.read(4))
        raw = f.read(n)
        name = raw.split(b"\0", 1)[0].decode("utf-8", "replace")
        ofs, size = struct.unpack("<QQ", f.read(16))
        f.read(16)                      # md5
        f.read(4)                       # flags (version 2+)
        entries.append((name, size))
    return (version, vmaj, vmin, vpatch), entries


def kind(name):
    n = name.lower()
    if ".glb-" in n or ".gltf-" in n:
        return "3D models (imported glb)"
    if n.endswith(".ctex") or ".ctex" in n:
        return "textures (compressed)"
    if n.endswith(".sample") or ".wav-" in n:
        return "audio samples"
    if n.endswith((".gdc", ".gd")):
        return "scripts"
    if n.endswith((".gdshader", ".gdshaderinc")):
        return "shaders"
    if n.endswith((".scn", ".tscn", ".res", ".tres")):
        return "scenes and resources"
    return "other"


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    ver, entries = read_pck(sys.argv[1])
    print("pck format %d, Godot %d.%d.%d, %d files, %.1f MB" % (ver[0], ver[1], ver[2], ver[3], len(entries), sum(s for _, s in entries) / 1048576))
    by = collections.defaultdict(lambda: [0, 0])
    for name, size in entries:
        k = kind(name)
        by[k][0] += 1
        by[k][1] += size
    for k, (n, size) in sorted(by.items(), key=lambda kv: -kv[1][1]):
        print("  %-28s %5d files  %7.2f MB" % (k, n, size / 1048576))
    models = sorted(n.split("/")[-1].split(".glb-")[0] for n, _ in entries if ".glb-" in n and n.endswith(".scn"))
    print("models:", ", ".join(models) if models else "(none)")
    print("biggest files:")
    for name, size in sorted(entries, key=lambda e: -e[1])[:8]:
        print("  %8.2f MB  %s" % (size / 1048576, name))
    if "--all" in sys.argv:
        for name, size in entries:
            print(size, name)


main()
