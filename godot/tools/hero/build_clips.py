#!/usr/bin/env python3
"""Bake the Quaternius Universal Animation Library (CC0) locomotion clips onto the hero's skeleton.

    python3 -I tools/hero/build_clips.py <UAL1 godot .glb> <UAL2 godot .glb> <hero kit .gltf> <out.json>

Both libraries and the hero kit use the same UE-style humanoid (same rest orientations, the library's 'DEF-' names in UAL1 are mapped), so a clip is retargeted by the
global delta of each bone from its own rest pose (Q = G_anim * G_rest^-1), which the hero then wears on top of ITS rest pose. The hero skeleton is built with identity
model-aligned bone frames (scripts/characters/hero_character.gd), so the stored local rotations are applied by CharacterRig as `rest * delta` unchanged.
Output per clip (30 fps, loops re-timed so frame 0 is the left foot's heel strike):
  hips   per frame model-space offset of the pelvis from the hero's standing pelvis (metres; the vertical part is floor-corrected from the hero's own leg lengths)
  q      per frame, per bone of BONES: the local rotation (x, y, z, w), model frame
  stride metres of ground the body travels per cycle (from the foot contacts, hero leg lengths): the clip plays by DISTANCE, so a planted foot does not slide
"""
import json
import math
import struct
import sys

import numpy as np

FPS = 30.0
SOLE_H = 0.015                           # the hero's foot points (heel, ball, toe tip) rest 1.5 cm above the floor: the lowest point of the clip is put there
# bones written per frame (hero names); parent chain of the hero skeleton (Head and the arms hang from spine_02, but only these are posed)
BONES = ["pelvis", "spine_01", "spine_02", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
PARENT = {"pelvis": None, "spine_01": "pelvis", "spine_02": "spine_01", "spine_03": "spine_02", "neck_01": "spine_03", "Head": "neck_01",
          "thigh_l": "pelvis", "calf_l": "thigh_l", "foot_l": "calf_l", "ball_l": "foot_l",
          "thigh_r": "pelvis", "calf_r": "thigh_r", "foot_r": "calf_r", "ball_r": "foot_r"}
DEF = {"DEF-hips": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03", "DEF-neck": "neck_01", "DEF-head": "Head",
       "DEF-thigh.L": "thigh_l", "DEF-shin.L": "calf_l", "DEF-foot.L": "foot_l", "DEF-toe.L": "ball_l",
       "DEF-thigh.R": "thigh_r", "DEF-shin.R": "calf_r", "DEF-foot.R": "foot_r", "DEF-toe.R": "ball_r"}
# clip name (source) -> (library, output name, loop, ground_lock: the lowest foot is kept on the floor every frame (no flight phase))
CLIPS = [
    ("Idle_Loop", 1, "idle", True, True), ("Pistol_Idle_Loop", 1, "ready", True, True), ("Walk_Loop", 1, "walk", True, True), ("Jog_Fwd_Loop", 1, "jog", True, False),
    ("Sprint_Loop", 1, "sprint", True, False), ("Crouch_Idle_Loop", 1, "crouch_idle", True, True), ("Crouch_Fwd_Loop", 1, "crouch_walk", True, True),
    ("Jump_Start", 1, "jump_start", False, False), ("Jump_Loop", 1, "jump_loop", True, False), ("Jump_Land", 1, "jump_land", False, False),
    ("Pistol_Aim_Neutral", 1, "aim_neutral", False, True), ("Pistol_Aim_Up", 1, "aim_up", False, True), ("Pistol_Aim_Down", 1, "aim_down", False, True),
    ("Walk_Carry_Loop", 2, "walk_carry", True, True),
]


def load_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    g = json.loads(d[20:20 + jl])
    off = 20 + jl + 8
    return g, d[off:]


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def mat_to_q(m):
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    q /= np.linalg.norm(q)
    if q[3] < 0:
        q = -q
    return q


def slerp(a, b, t):
    a = np.array(a, float)
    b = np.array(b, float)
    d = float(np.dot(a, b))
    if d < 0:
        b = -b
        d = -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = math.acos(d)
    return (math.sin((1 - t) * th) * a + math.sin(t * th) * b) / math.sin(th)


def accessor(g, blob, idx):
    a = g["accessors"][idx]
    bv = g["bufferViews"][a["bufferView"]]
    n = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(blob, dtype="<f4", count=a["count"] * n, offset=off).reshape(a["count"], n)


class Lib:
    def __init__(self, path, lib):
        self.g, self.blob = load_glb(path)
        self.lib = lib
        g = self.g
        self.names = [n["name"] for n in g["nodes"]]
        self.idx = {n: i for i, n in enumerate(self.names)}
        self.par = {}
        for i, n in enumerate(g["nodes"]):
            for c in n.get("children", []):
                self.par[c] = i

    def ue(self, node_name):
        return DEF.get(node_name, node_name)

    def node_of(self, ue_name):
        for n, i in self.idx.items():
            if self.ue(n) == ue_name:
                return i
        raise KeyError(ue_name)

    def rest_local(self, i):
        n = self.g["nodes"][i]
        return qmat(n.get("rotation", [0, 0, 0, 1])), np.array(n.get("translation", [0, 0, 0]), float)

    def chain(self, i):
        c = []
        while i is not None:
            c.append(i)
            i = self.par.get(i)
        return c[::-1]

    def sample(self, anim):
        """{node index: (times, rot[n,4] or None, trans[n,3] or None)}"""
        out = {}
        for ch in anim["channels"]:
            t = ch["target"]
            if "node" not in t or t["path"] not in ("rotation", "translation"):
                continue
            s = anim["samplers"][ch["sampler"]]
            times = accessor(self.g, self.blob, s["input"])[:, 0]
            vals = accessor(self.g, self.blob, s["output"])
            e = out.setdefault(t["node"], {})
            e["t"] = times
            e[t["path"]] = vals
        return out

    def eval(self, samp, i, t, path):
        e = samp.get(i)
        if e is None or path not in e:
            return None
        times = e["t"]
        v = e[path]
        if t <= times[0]:
            return v[0]
        if t >= times[-1]:
            return v[-1]
        k = int(np.searchsorted(times, t) - 1)
        u = (t - times[k]) / max(times[k + 1] - times[k], 1e-9)
        if path == "rotation":
            return slerp(v[k], v[k + 1], u)
        return v[k] * (1 - u) + v[k + 1] * u

    def globals_at(self, samp, t, want):
        """global rotation matrix and position (library frame) of every wanted node index at time t"""
        res = {}
        for w in want:
            R = np.eye(3)
            P = np.zeros(3)
            for i in self.chain(w):
                rq = self.eval(samp, i, t, "rotation")
                tr = self.eval(samp, i, t, "translation")
                rr, rt = self.rest_local(i)
                Lr = qmat(rq) if rq is not None else rr
                Lt = np.array(tr, float) if tr is not None else rt
                P = P + R @ Lt
                R = R @ Lr
            res[w] = (R, P)
        return res

    def rest_globals(self, want):
        res = {}
        for w in want:
            R = np.eye(3)
            P = np.zeros(3)
            for i in self.chain(w):
                rr, rt = self.rest_local(i)
                P = P + R @ rt
                R = R @ rr
            res[w] = (R, P)
        return res


def hero_rest(path):
    g = json.load(open(path))
    names = [n["name"] for n in g["nodes"]]
    par = {}
    for i, n in enumerate(g["nodes"]):
        for c in n.get("children", []):
            par[c] = i
    out = {}
    for i, n in enumerate(g["nodes"]):
        R = np.eye(3)
        P = np.zeros(3)
        chain = []
        k = i
        while k is not None:
            chain.append(k)
            k = par.get(k)
        for j in chain[::-1]:
            nn = g["nodes"][j]
            R2 = qmat(nn.get("rotation", [0, 0, 0, 1]))
            P = P + R @ np.array(nn.get("translation", [0, 0, 0]), float)
            R = R @ R2
        out[names[i]] = P
    return out


F = np.diag([-1.0, 1.0, -1.0])           # kit space (faces +Z) -> model space (faces -Z): a half turn about Y


def build(libs, hero_path, out_path):
    hp = hero_rest(hero_path)             # kit space rest positions of the hero's bones
    need = [b for b in PARENT]
    clips = {}
    report = []
    for src, lib, outname, loop, lock in CLIPS:
        L = libs[lib]
        anim = next((a for a in L.g["animations"] if a["name"] == src), None)
        if anim is None:
            print("missing", src)
            continue
        samp = L.sample(anim)
        dur = max(float(e["t"][-1]) for e in samp.values())
        n = int(round(dur * FPS)) + (0 if loop else 1)
        n = max(n, 2)
        nodes = {b: L.node_of(b) for b in need}
        rest = L.rest_globals(list(nodes.values()))
        # source pelvis rest position
        pel_rest = rest[nodes["pelvis"]][1]
        frames = []
        for f in range(n):
            t = min(f / FPS, dur)
            gl = L.globals_at(samp, t, list(nodes.values()))
            Q = {}
            for b in need:
                Rg, Pg = gl[nodes[b]]
                Rr = rest[nodes[b]][0]
                Qk = Rg @ Rr.T
                Q[b] = F @ Qk @ F
            hips_d = (gl[nodes["pelvis"]][1] - pel_rest)
            frames.append((Q, hips_d))
        # hero forward kinematics (kit space): pelvis offset from the clip, scaled by the pelvis height ratio
        scale = hp["pelvis"][1] / pel_rest[1]
        pts_rest = {k: hp[k] for k in ["pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "ball_leaf_l", "thigh_r", "calf_r", "foot_r", "ball_r", "ball_leaf_r"]}

        def fk(Q, hips_d):
            # Q in model frame; convert back to kit frame for the geometry (kit-space offsets are rotated by the same delta)
            Qk = {b: F @ Q[b] @ F for b in Q}
            P = {}
            pel = pts_rest["pelvis"] + hips_d * scale
            P["pelvis"] = pel
            for b, par in [("thigh_l", "pelvis"), ("calf_l", "thigh_l"), ("foot_l", "calf_l"), ("ball_l", "foot_l"), ("thigh_r", "pelvis"), ("calf_r", "thigh_r"), ("foot_r", "calf_r"), ("ball_r", "foot_r")]:
                P[b] = P[par] + Qk[par] @ (pts_rest[b] - pts_rest[par])
            P["leaf_l"] = P["ball_l"] + Qk["ball_l"] @ (pts_rest["ball_leaf_l"] - pts_rest["ball_l"])
            P["leaf_r"] = P["ball_r"] + Qk["ball_r"] @ (pts_rest["ball_leaf_r"] - pts_rest["ball_r"])
            # heel point: under and behind the ankle at the floor (rest)
            hl = pts_rest["foot_l"] + np.array([0.0, -0.071, -0.03])
            hr = pts_rest["foot_r"] + np.array([0.0, -0.071, -0.03])
            P["heel_l"] = P["foot_l"] + Qk["foot_l"] @ (hl - pts_rest["foot_l"])
            P["heel_r"] = P["foot_r"] + Qk["foot_r"] @ (hr - pts_rest["foot_r"])
            return P

        def soles(P):
            """lowest point of each foot (floor contact), height above the rest floor"""
            return [min(P["heel_l"][1], P["ball_l"][1], P["leaf_l"][1]) - 0.0, min(P["heel_r"][1], P["ball_r"][1], P["leaf_r"][1]) - 0.0]

        fkp = [fk(Q, hd) for Q, hd in frames]
        sol = np.array([soles(P) for P in fkp])            # n x 2
        low = sol.min(axis=1)
        floor = float(low.min()) if not lock else None
        # re-time the loop so that frame 0 is the left heel strike: the frame where the left heel is furthest forward (+Z) of the right one
        shift = 0
        if loop and outname in ("walk", "jog", "sprint", "crouch_walk", "walk_carry"):
            rel = np.array([P["heel_l"][2] - P["heel_r"][2] for P in fkp])
            shift = int(np.argmax(rel))
            frames = frames[shift:] + frames[:shift]
            fkp = fkp[shift:] + fkp[:shift]
            sol = np.roll(sol, -shift, axis=0)
            low = sol.min(axis=1)
        # floor correction (vertical) per frame or per clip
        corr = np.zeros(n)
        if lock:
            c = -low + SOLE_H
            # smooth a little so the lowest foot swapping does not pop; keep the correction small
            k = np.ones(5) / 5.0
            pad = np.concatenate([c[-2:], c, c[:2]]) if loop else np.concatenate([[c[0]] * 2, c, [c[-1]] * 2])
            corr = np.convolve(pad, k, mode="valid")[:n]
            corr = np.clip(corr, -0.08, 0.08)
        else:
            corr[:] = -float(low.min()) + SOLE_H
        # ground contacts: stride from the planted foot's backward travel, per cycle
        stride = 0.0
        speed = 0.0
        if outname in ("walk", "jog", "sprint", "crouch_walk", "walk_carry"):
            # S0: the planted lowest point's backward travel (same point in two frames); S: the speed at which the contacts of heel, ball and toe tip (each within 2 cm of the
            # floor, per point) travel least over the cycle, searched within 0.7..1.3 x S0 (what the game's foot meter reads)
            vs = []
            for margin in (0.015, 0.03, 0.05, 0.08):
                vs = []
                for side in ["l", "r"]:
                    pts = ["heel_" + side, "ball_" + side, "leaf_" + side]
                    for f in range(n):
                        f2 = (f + 1) % n
                        a0 = int(np.argmin([fkp[f][q_][1] for q_ in pts]))
                        a1 = int(np.argmin([fkp[f2][q_][1] for q_ in pts]))
                        if a0 == a1 and fkp[f][pts[a0]][1] + corr[f] < SOLE_H + margin and fkp[f2][pts[a1]][1] + corr[f2] < SOLE_H + margin:
                            vs.append(-(fkp[f2][pts[a0]][2] - fkp[f][pts[a0]][2]) * FPS)
                if len(vs) >= 4:
                    break
            s0 = float(np.median(vs)) if vs else 1.0
            best = (1e9, s0)
            for S in np.arange(max(0.3, s0 * 0.7), s0 * 1.3 + 0.001, 0.01):
                tot = 0.0
                for side in ["l", "r"]:
                    for pt in ["heel_", "ball_", "leaf_"]:
                        z = np.array([fkp[f][pt + side][2] for f in range(n)])
                        h = np.array([fkp[f][pt + side][1] for f in range(n)]) + corr
                        low = h < SOLE_H + 0.01
                        zz = np.concatenate([z + S * (np.arange(n) / FPS), z + S * ((np.arange(n) + n) / FPS)])
                        ll = np.concatenate([low, low])
                        i = 0
                        while i < 2 * n:
                            if ll[i]:
                                j = i
                                while j < 2 * n and ll[j]:
                                    j += 1
                                if i > 0 and j < 2 * n:
                                    tot += float(zz[i:j].max() - zz[i:j].min())
                                i = j
                            else:
                                i += 1
                tot += 0.02 * abs(S - s0)
                if tot < best[0]:
                    best = (tot, float(S))
            speed = best[1]
            stride = speed * n / FPS
            report.append("   S0 %.2f best speed %.2f m/s, contact travel over two cycles %.1f cm (%d samples)" % (s0, speed, best[0] * 100.0, len(vs)))
        # outputs: local rotations in the hero's parent frames (model frame)
        qs = []
        hips_out = []
        for f in range(n):
            Q, hd = frames[f]
            row = []
            for b in BONES:
                par = PARENT[b]
                Lq = Q[b] if par is None else Q[par].T @ Q[b]
                row.extend(mat_to_q(Lq).tolist())
            qs.append(row)
            hm = F @ (hd * scale)                              # model frame
            hips_out.append([float(hm[0]), float(hm[1] + corr[f]), float(hm[2])])
        # make successive quaternions of one bone continuous (shortest arc) for blending
        qs = np.array(qs).reshape(n, len(BONES), 4)
        for f in range(1, n):
            for bi in range(len(BONES)):
                if np.dot(qs[f, bi], qs[f - 1, bi]) < 0:
                    qs[f, bi] = -qs[f, bi]
        hips_arr = np.array(hips_out)
        if loop or True:
            # the clips are in place: remove the horizontal drift of the pelvis (root motion) but keep the sway
            hips_arr[:, 2] -= hips_arr[:, 2].mean() if outname in ("walk", "jog", "sprint", "crouch_walk", "walk_carry", "idle", "ready", "crouch_idle") else 0.0
        clips[outname] = {"n": n, "loop": loop, "fps": FPS, "dur": n / FPS, "speed": round(speed, 3), "stride": round(stride, 3), "shift": shift,
                          "q": [round(float(v), 5) for v in qs.reshape(-1)], "hips": [round(float(v), 5) for v in hips_arr.reshape(-1)]}
        report.append("%-12s frames %3d dur %.2fs  speed %.2f m/s  stride %.2f m  hips y %.3f..%.3f  corr %.3f..%.3f  shift %d" % (
            outname, n, n / FPS, speed, stride, hips_arr[:, 1].min(), hips_arr[:, 1].max(), corr.min(), corr.max(), shift))
    data = {"bones": BONES, "fps": FPS, "clips": clips, "pelvis_rest_y": float(hp["pelvis"][1])}
    json.dump(data, open(out_path, "w"), separators=(",", ":"))
    print("\n".join(report))


if __name__ == "__main__":
    l1 = Lib(sys.argv[1], 1)
    l2 = Lib(sys.argv[2], 2)
    build({1: l1, 2: l2}, sys.argv[3], sys.argv[4])
