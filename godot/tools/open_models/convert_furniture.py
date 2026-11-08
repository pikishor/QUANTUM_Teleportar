"""Furniture for the interiors from Kenney's Furniture Kit (CC0, fetched from opengameart.org/content/furniture-kit): OBJ + MTL -> lean glb, assets/models/furn_<name>.glb.

Same glb contract as the interior kit (scripts/interiors/interior_kit.gd): non-indexed triangles with flat normals, COLOR_0 = the material's diffuse colour, UV0.x = material class
(0 main, 1 dark metal, 5 lamp light, 6 glass, 8 fabric, 9 plant), UV0.y = height 0..1. Pieces are scaled to metres (the kit is 0.2 m per unit), centred on x / z, feet at y = 0.
Run: python3 tools/open_models/convert_furniture.py <folder with the unzipped kit's Models/>   (needs numpy; the raw kit is not committed, see art_sources/kenney_furniture_kit/SOURCE.md)
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))
SCALE = 0.2
MAX_TRIS = 420

# piece name -> obj file (without extension)
PIECES = {
	"sofa": "loungeSofa", "armchair": "loungeChair", "table": "table", "table_round": "tableRound", "table_coffee": "tableCoffee", "side_table": "sideTableDrawers",
	"desk": "desk", "chair": "chair", "chair_cushion": "chairCushion", "stool": "stoolBar", "bed_double": "bedDouble", "bed_single": "bedSingle",
	"bookcase": "bookcaseClosed", "bookcase_wide": "bookcaseClosedWide", "tv_cabinet": "cabinetTelevision", "kitchen_cabinet": "kitchenCabinet",
	"kitchen_upper": "kitchenCabinetUpper", "kitchen_sink": "kitchenSink", "fridge": "kitchenFridge", "coffee_machine": "kitchenCoffeeMachine",
	"microwave": "kitchenMicrowave", "trashcan": "trashcan", "coat_rack": "coatRackStanding", "plant": "pottedPlant", "lamp_floor": "lampRoundFloor",
	"lamp_table": "lampRoundTable", "rug_rect": "rugRectangle", "books": "books", "speaker": "speaker", "speaker_small": "speakerSmall", "tv_modern": "televisionModern",
	"tv_vintage": "televisionVintage", "monitor": "computerScreen", "keyboard": "computerKeyboard", "box_closed": "cardboardBoxClosed", "box_open": "cardboardBoxOpen",
	"sink": "bathroomSink", "mirror": "bathroomMirror",
}
CLASS = {"metalDark": 1, "metalMedium": 1, "glass": 6, "lamp": 5, "carpet": 8, "carpetWhite": 8, "carpetDarker": 8, "fur": 8, "plant": 9}


def read_mtl(path):
	out, cur = {}, None
	if os.path.exists(path):
		for line in open(path):
			p = line.split()
			if p and p[0] == "newmtl":
				cur = p[1]
			elif p and p[0] == "Kd" and cur:
				out[cur] = tuple(float(x) for x in p[1:4])
	return out


def load_obj(path, mtl):
	v, tris, cols, cls = [], [], [], []
	cur, ccls = (0.5, 0.5, 0.5), 0
	for line in open(path):
		p = line.split()
		if not p:
			continue
		if p[0] == "v":
			v.append([float(x) for x in p[1:4]])
		elif p[0] == "usemtl":
			cur = mtl.get(p[1], (0.5, 0.5, 0.5))
			ccls = CLASS.get(p[1], 0)
		elif p[0] == "f":
			idx = [int(t.split("/")[0]) - 1 for t in p[1:]]
			for k in range(1, len(idx) - 1):
				tris.append([v[idx[0]], v[idx[k]], v[idx[k + 1]]])
				cols.append(cur)
				cls.append(ccls)
	return np.array(tris, dtype=np.float64), np.array(cols, dtype=np.float32), np.array(cls, dtype=np.float32)


def write_glb(path, tris, cols, cls):
	n = len(tris) * 3
	v = tris.reshape(-1, 3).astype(np.float32)
	nm = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
	ln = np.linalg.norm(nm, axis=1, keepdims=True)
	nm = np.where(ln > 1e-12, nm / np.maximum(ln, 1e-12), np.array([0, 1, 0]))
	nn = np.repeat(nm, 3, axis=0).astype(np.float32)
	cc = np.repeat(np.concatenate([cols, np.ones((len(cols), 1), np.float32)], axis=1), 3, axis=0).astype(np.float32)
	uv = np.zeros((n, 2), np.float32)
	uv[:, 0] = np.repeat(cls, 3)
	uv[:, 1] = v[:, 1] / max(float(v[:, 1].max()), 0.001)
	parts = [v.tobytes(), nn.tobytes(), cc.tobytes(), uv.tobytes()]
	offs, o = [], 0
	for p in parts:
		offs.append(o)
		o += len(p)
	binb = b"".join(parts)
	g = {"asset": {"version": "2.0", "generator": "convert_furniture.py"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": os.path.basename(path)[:-4]}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2, "TEXCOORD_0": 3}, "material": 0}]}],
		"materials": [{"name": "Furniture", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.7}}],
		"accessors": [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": v.min(axis=0).tolist(), "max": v.max(axis=0).tolist()},
			{"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"}, {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC4"},
			{"bufferView": 3, "componentType": 5126, "count": n, "type": "VEC2"}],
		"bufferViews": [{"buffer": 0, "byteOffset": offs[i], "byteLength": len(parts[i]), "target": 34962} for i in range(4)], "buffers": [{"byteLength": len(binb)}]}
	js = json.dumps(g, separators=(",", ":")).encode()
	js += b" " * (-len(js) % 4)
	binb += b"\0" * (-len(binb) % 4)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binb)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
		f.write(struct.pack("<II", len(binb), 0x004E4942) + binb)


def main():
	src = sys.argv[1]
	for name, obj in PIECES.items():
		tris, cols, cls = load_obj(os.path.join(src, obj + ".obj"), read_mtl(os.path.join(src, obj + ".mtl")))
		keep = np.abs(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])).sum(axis=1) > 1e-9
		tris, cols, cls = tris[keep] * SCALE, cols[keep], cls[keep]
		mn, mx = tris.reshape(-1, 3).min(axis=0), tris.reshape(-1, 3).max(axis=0)
		tris = tris - np.array([(mn[0] + mx[0]) * 0.5, mn[1], (mn[2] + mx[2]) * 0.5])
		if len(tris) > MAX_TRIS:
			print("SKIP %s: %d tris" % (name, len(tris)))
			continue
		write_glb(os.path.join(OUT, "furn_%s.glb" % name), tris, cols, cls)
		print("MODEL %-16s tris=%3d size=%.2f x %.2f x %.2f" % (name, len(tris), *(mx - mn)))


if __name__ == "__main__":
	main()
