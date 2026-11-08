#!/usr/bin/env python3
"""Real recordings instead of synthesis (round 4): weapon shots, impacts, explosions, footsteps, vehicles, UI cues and ambience beds built from CC0 clips.

Input: the clips committed under art_sources/audio_<group>/clips/ (see tools/audio/real_clips.py for the list and how they were cut, docs/AUDIO_SOURCES.md for the sources and licences).
Output: assets/audio/<name>.wav / .ogg (same file names and formats the game already loads; new numbered variants where a repeating sound needed more than one take).
Runs in tools/build_assets.sh AFTER every synthesising generator (they write the same names) and BEFORE shrink_audio.py. numpy and ffmpeg only.

How a sound is made
  * shots: the real transient (a recording of a real firearm for the gun classes, a Kenney laser for the sci-fi classes) is layered with our own sub-bass thump (the `body` of make_redesign) and,
    for the heavy classes, a short pitched-down copy, then mastered by make_redesign.master to the peak of the sound it replaces and a crest factor of about 7 dB (loud, not just tall);
    the far variants are the real mid-distance recordings, low-passed; the suppressed ones start from the 'Hollywood silencer' clip; the overcharged lance shot keeps the synthesised
    sub fall and shimmer under a real laser and a real boom.
  * impacts, explosions, footsteps, vehicle, UI, reloads: a real clip (or two), pitched / filtered a little, loudness-matched to the sound it replaces (tools/audio/real_levels.py holds
    the numbers of the synthesised originals, so the mix table in Sfx and check_audio.py stays as tuned); explosions keep a synthesised sub-bass fall under the real boom.
  * beds (rain, traffic, wind, city hum): a real recording cut to 24 s and made seamless by an equal-power crossfade of its tail into its head, mono OGG like the old beds.
  * engines: the qubodup racing-car loops (whole engine cycles: seamless) with the smpl loop chunk the game expects; bike and heavy engines are the same loops re-pitched (circular
    resample, still seamless).
Run: python3 tools/audio/make_real.py [out_dir] [--only glob ...]
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_audio as ma  # noqa: E402
from make_audio import SR, fade  # noqa: E402
import make_redesign as mr  # noqa: E402
import audio_metrics as am  # noqa: E402
import real_clips as rc  # noqa: E402
from real_levels import LEVELS  # noqa: E402

OUT = os.path.join(ma.ROOT, "assets", "audio")
DEFAULT_OUT = OUT
OGG_NAMES = re.compile(r"^(boom(_\d)?|distant_boom_\d|distant_gunfire_\d|car_crash_\d|explosion_small_\d|shot_rail|shot_gravity|shot_lance)$")   # the sounds the game ships as OGG (shrink_audio.py, make_v3.py)
ONLY = []
BUILT = {}


def _n(s):
    return int(s * SR)


# ------------------------------------------------------------------ building blocks
def pitch(x, semis):
    r = 2.0 ** (semis / 12.0)
    pos = np.arange(0, len(x) - 1, r)
    return np.interp(pos, np.arange(len(x)), x)


def glide(x, r0, r1):
    """Resample with a playback rate that moves from r0 to r1 (a ricochet's falling whine, a whizz's Doppler)."""
    rates = np.linspace(r0, r1, len(x))
    pos = np.cumsum(rates)
    pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x)


def loop_ratio(x, ratio):
    """Re-pitch a loop and keep it a loop: the same cycles over a different length (circular linear interpolation)."""
    n2 = int(round(len(x) / ratio))
    pos = np.arange(n2) * len(x) / n2
    i0 = np.floor(pos).astype(int)
    f = pos - i0
    return x[i0 % len(x)] * (1 - f) + x[(i0 + 1) % len(x)] * f


def C(cid, db=0.0, semis=0.0, delay=0.0, lp=None, hp=None, length=None, gl=None):
    """A clip as a (signal, start seconds) part, peak-normalised, then gained / pitched / filtered / shortened."""
    x = rc.load_clip(cid)
    x = x / (np.max(np.abs(x)) + 1e-12)
    if semis:
        x = pitch(x, semis)
    if gl:
        x = glide(x, gl[0], gl[1])
    if lp:
        x = mr.lp(x, lp)
    if hp:
        x = mr.hp(x, hp)
    if length:
        x = x[:_n(length)]
    return (x * 10 ** (db / 20.0), delay)


def mix(parts, length):
    n = _n(length)
    out = np.zeros(n)
    for x, t in parts:
        i = _n(t)
        if i < n:
            j = min(n, i + len(x))
            out[i:j] += x[:j - i]
    return out


def sub_body(n, cls, seed, gain, f0=None, f1=None):
    """Our own sub-bass thump of a weapon class (make_redesign.body), peak-normalised then scaled: it rides under the real transient."""
    c = mr.CLASSES[cls]
    bf0, bf1, bdur, btau, drv, _ = c["bd"]
    b = mr.body(n, mr.R(seed), f0 or bf0, f1 or bf1, bdur, btau, drv, 1.0)
    return b / (np.max(np.abs(b)) + 1e-12) * gain


def lv(name):
    if name in LEVELS:
        return LEVELS[name]
    base = name.rsplit("_", 1)[0]
    return LEVELS[base]


def trim(x, db=-55.0, pad=0.02):
    pk = np.max(np.abs(x)) + 1e-12
    idx = np.nonzero(np.abs(x) > pk * 10 ** (db / 20.0))[0]
    if len(idx):
        x = x[:min(len(x), idx[-1] + _n(pad))]
    return x


def match(x, name, window=500.0, fout=0.02, hp=None, boost=0.0, squash=0.0):
    """Scale to the K-weighted loudness of the sound it replaces (first `window` ms after the onset) and never above its peak."""
    lvl = lv(name)
    peak, lu = lvl[0] + boost, (lvl[4] if window <= 300.0 else lvl[1]) + boost
    x = trim(x)
    x = fade(x, 0.0004, min(fout, 0.4 * len(x) / SR))
    if hp:
        x = mr.hp(x, hp, 2)
    if squash:                                                       # soft-clip the transient: more body at the same peak (a real impact is tall and thin)
        x = np.tanh(x / (np.max(np.abs(x)) + 1e-12) * squash)
    g = 10 ** ((lu - am.short_term(x, window)) / 20.0)
    x = am.limiter(x * g, min(peak, -9.5), 0.003)
    return x


def ensure_import(name):
    """A new numbered variant needs a Godot .import file like its siblings (PCM, no QOA: the audio tests want 16-bit WAV): copy the sibling's parameters, Godot fills in uid and path."""
    if OUT != DEFAULT_OUT:
        return
    imp = os.path.join(OUT, name + ".wav.import")
    if os.path.exists(imp):
        return
    base = name.rsplit("_", 1)[0]
    sib = None
    for cand in (base + ".wav.import", base + "_0.wav.import"):
        if os.path.exists(os.path.join(OUT, cand)):
            sib = cand
            break
    params = open(os.path.join(OUT, sib)).read().split("[params]")[1] if sib else "\n\nforce/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\nedit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n"
    if "compress/mode=2" in params:
        params = params.replace("compress/mode=2", "compress/mode=0")
    open(imp, "w").write('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[deps]\n\nsource_file="res://assets/audio/%s.wav"\n\n[params]%s' % (name, params))


def emit(name, x, loop=False, ogg=None):
    """Write assets/audio/<name>.wav, or .ogg when the game already ships that sound as OGG (or ogg=True)."""
    if ONLY and not any(fnmatch.fnmatch(name, p) for p in ONLY):
        return
    x = np.asarray(x, dtype=np.float64)
    if ogg is None:
        ogg = bool(OGG_NAMES.match(name))
    if ogg:
        for stale in (".wav", ".wav.import"):                       # the synthesised original of this sound (build_assets.sh writes it first): shrink_audio.py would turn it into OGG over ours
            if os.path.exists(os.path.join(OUT, name + stale)):
                os.remove(os.path.join(OUT, name + stale))
        p = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "4", "-map_metadata", "-1", "-fflags", "+bitexact", p],
                       input=x.astype("<f4").tobytes(), check=True)
    else:
        ma.write_wav(os.path.join(OUT, name + ".wav"), x, loop=loop)
        ensure_import(name)
    BUILT[name] = x
    print("%-22s %5.2f s  peak %6.1f  LU %6.1f  crest %4.1f  centroid %5.0f Hz" % (name, len(x) / SR, am.peak_db(x), am.short_term(x, 250.0), am.crest_db(x), am.centroid_hz(x, 250.0)), flush=True)


# ------------------------------------------------------------------ shots
def shot(name, parts, cls, seed, body=0.3, length=None, lp=None, crest=7.0, fade_out=None, tail=None, peak=None, body_f=None, presence=0.0):
    c = mr.CLASSES[cls]
    length = length or c["length"]
    x = mix(parts, length + 0.2)
    x = mr.hp(x, 80.0, 4)                                            # the field recordings carry infrasound (muzzle pressure): it would eat the loudness budget
    if lp:
        x = mr.lp(x, lp)
    if presence:                                                     # the crack: what a phone speaker (nothing under 300 Hz) turns into 'a gunshot' instead of 'a thud'
        x = x + mr.hp(x, 1800.0, 2) * presence
    if body:                                                         # body = level of the thump relative to the RMS of the real transient's first 120 ms (a real shot is tall and thin)
        k = _n(0.12)
        ref = np.sqrt(np.mean(x[:k] ** 2)) + 1e-12
        b = sub_body(len(x), cls, seed, 1.0, *(body_f or (None, None)))
        x = x + b / (np.sqrt(np.mean(b[:k] ** 2)) + 1e-12) * ref * body
    if tail:
        x = ma.reverb(x, tail[0], wet=tail[1], predelay=0.008, damp=0.55, seed=seed)
    return mr.master(x, peak if peak is not None else lv(name)[0], crest, 55.0, fade_out if fade_out is not None else length * 0.14 + 0.03, length)


def far_shot(name, cid, seed, semis=0.0, lp=2800.0):
    x = mr.hp(mix([C(cid, semis=semis, lp=lp)], 2.2), 80.0, 4)
    x = ma.reverb(x, 1.1, wet=0.25, predelay=0.02, damp=0.7, seed=seed)
    x = mr.band(x, 80, 3200)
    return mr.master(x, lv(name)[0], 10.0, 70.0, 0.25, 1.9)


def build_shots():
    # gun classes: real recordings of real guns (The Free Firearm Sound Library), our sub-bass under them
    for i, (name, cid, semis) in enumerate((("shot", "fl_ar15_near", 0.0), ("shot_1", "fl_ak_near", 0.0), ("shot_2", "fl_sks_near", 0.0), ("shot_3", "fl_savage_near", 0.0))):
        emit(name, shot(name, [C(cid, semis=semis, lp=7500)], "rifle", 9100 + 17 * i, body=0.35, presence=1.0, length=0.9, body_f=(260 * [1.0, 1.3, 0.85, 1.15][i], 70)))
    for i, (name, cid) in enumerate((("shot_twin", "fl_1911_near"), ("shot_twin_1", "fl_ppq_near"), ("shot_twin_2", "fl_bersa_near"))):
        emit(name, shot(name, [C(cid, lp=7500)], "pistol", 9400 + 13 * i, body=0.6, presence=0.8, length=0.7, body_f=(330 * [1.0, 1.2, 0.85][i], 95)))
    for i, (name, cid, semis) in enumerate((("shot_rev", "fl_sw642_near", -3.0), ("shot_rev_1", "fl_ruger6_near", -3.0), ("shot_rev_2", "fl_marlin_near", -1.0))):
        emit(name, shot(name, [C(cid, semis=semis, lp=6500), C("fl_sw642_near", db=-6.0, semis=-9.0, lp=900, delay=0.002)], "revolver", 9410 + 3 * i, body=0.6, presence=1.3, length=1.1, body_f=(230 * [1.0, 1.25, 0.8][i], 75)))
    for i, (name, cid) in enumerate((("shot_scatter", "fl_mossberg_near"), ("shot_scatter_1", "fl_nova_near"), ("shot_scatter_2", "fl_model12_near"))):
        emit(name, shot(name, [C(cid, lp=7500)], "shotgun", 9420 + 11 * i, body=0.45, presence=1.3, length=1.0, body_f=(210 * [1.0, 1.25, 0.8][i], 70)))
    for i, name in enumerate(("shot_mini", "shot_mini_1", "shot_mini_2", "shot_mini_3")):
        emit(name, shot(name, [C("fl_ppsh_r%d" % i, lp=7000, semis=[0.0, 0.5, -0.4, 0.9][i])], "minigun", 9430 + i, body=0.6, presence=0.3, length=0.2))
    for i, name in enumerate(("shot_burst", "shot_burst_1", "shot_burst_2", "shot_burst_3")):
        emit(name, shot(name, [C("fl_cg_r%d" % i, lp=7000)], "burst", 9440 + i, body=0.6, presence=0.8, length=0.4))
    # enemy fire: a real SMG / rifle transient with a Kenney zap on top, so it reads as theirs, not yours
    emit("enemy_shot", shot("enemy_shot", [C("fl_cg_single", lp=6000, semis=-2.0), C("kn_laser_s3", db=-5.0, lp=6000)], "enemy", 9300, body=0.6, presence=0.6, length=0.7))
    emit("enemy_shot_1", shot("enemy_shot_1", [C("fl_bersa_near", lp=6000, semis=-3.0), C("kn_laser_s2", db=-5.0, lp=6000)], "enemy", 9319, body=0.6, presence=0.6, length=0.7))
    emit("enemy_shot_2", shot("enemy_shot_2", [C("fl_ak_near2", lp=6000, semis=-4.0), C("kn_laser_r0", db=-8.0, lp=6000)], "enemy", 9338, body=0.6, presence=0.6, length=0.7))
    # sci-fi classes: a real laser transient (Kenney, number99) with the thump of the class under it
    emit("shot_flux", shot("shot_flux", [C("kn_laser_s1", lp=9000), C("sf50_shoot1", db=-8.0, lp=8000)], "flux", 9450, body=0.5, length=0.5))
    emit("shot_flux_1", shot("shot_flux_1", [C("kn_laser_s3", lp=9000), C("sf50_shoot2", db=-8.0, lp=8000)], "flux", 9451, body=0.5, length=0.5))
    emit("shot_flux_2", shot("shot_flux_2", [C("kn_laser_s0", lp=9000), C("sf50_shoot1", db=-8.0, semis=-3.0, lp=8000)], "flux", 9452, body=0.5, length=0.5))
    emit("shot_arc", shot("shot_arc", [C("kn_laser_r4", lp=9000), C("sf60_21a", db=-7.0, lp=9000)], "flux", 9460, body=0.4, length=0.5, tail=(0.4, 0.2)))
    emit("shot_arc_1", shot("shot_arc_1", [C("kn_laser_r0", lp=9000), C("sf50_retro_laser1", db=-5.0, lp=9000)], "flux", 9461, body=0.4, length=0.5, tail=(0.4, 0.2)))
    emit("shot_rail", shot("shot_rail", [C("kn_laser_l2", lp=9000), C("lark_blackpowder", db=-3.0, lp=4000)], "rifle", 9470, body=0.8, length=0.9, body_f=(230, 80)))
    emit("shot_rail_1", shot("shot_rail_1", [C("kn_laser_l0", lp=9000), C("fl_mosin_near", db=-3.0, lp=4000)], "rifle", 9471, body=0.8, length=0.9, body_f=(230, 80)))
    emit("shot_lance", shot("shot_lance", [C("kn_laser_l3", lp=9000), C("kn_forcefield0", db=-6.0, lp=6000), C("fl_1917_near", db=-4.0, lp=3500)], "revolver", 9480, body=0.9, length=1.0, tail=(0.6, 0.25)))
    emit("shot_gravity", shot("shot_gravity", [C("kn_forcefield0", lp=5000), C("kn_lowexpl1", db=-3.0, lp=900)], "revolver", 9490, body=1.3, length=1.0, tail=(0.7, 0.25), body_f=(150, 38)))
    emit("shot_gravity_1", shot("shot_gravity_1", [C("kn_forcefield2", lp=5000), C("kn_lowexpl0", db=-3.0, lp=900)], "revolver", 9491, body=1.3, length=1.0, tail=(0.7, 0.25), body_f=(150, 38)))
    # variants: the suppressed pistol (the Hollywood silencer clip), the overcharged lance (a real laser and boom over the synthesised sub fall and shimmer)
    for i in range(2):
        nm = "shot_supp_%d" % i
        base = C("silencer", semis=[0.0, -1.5][i], lp=1900)
        extra = [] if i == 0 else [C("fl_ppq_near", db=-14.0, lp=1200, delay=0.001)]
        x = mix([base] + extra, 0.8)
        x = ma.reverb(x, 0.25, wet=0.1, predelay=0.006, damp=0.7, seed=9500 + i)
        emit(nm, mr.master(x, lv(nm)[0] - 1.5, 7.0, 80.0, 0.04, 0.55))
    for i in range(2):
        nm = "shot_oc_%d" % i
        synth = mr.synth_shot("revolver", 9550 + 7 * i, "oc")
        synth = synth / (np.max(np.abs(synth)) + 1e-12)
        real = mix([C(["kn_laser_l0", "kn_laser_l2"][i], lp=9000), C("lark_blackpowder", db=-4.0, lp=3000), C("sf50_rocket", db=-9.0, semis=-3.0, lp=2500, delay=0.02)], 1.6)
        x = np.zeros(max(len(synth), len(real)))
        x[:len(synth)] += synth * 1.3
        x[:len(real)] += real
        x = ma.reverb(x, 1.0, wet=0.35, predelay=0.012, damp=0.4, seed=9550 + i)
        emit(nm, mr.master(x, lv(nm)[0], 6.5, 40.0, 0.2, 1.6))
    # far: the real mid-distance recordings, dull and late
    for nm, cid, sm in (("shot_far_0", "fl_ar15_mid", 0.0), ("shot_far_1", "fl_ak_mid", 0.0), ("enemy_shot_far_0", "fl_1911_mid", -2.0), ("enemy_shot_far_1", "fl_mossberg_mid", 2.0)):
        emit(nm, far_shot(nm, cid, 9200, sm))
    # melee: real swishes with a ring (blade) or a crack (whip)
    x = mix([C("sw_2", lp=9000), C("sw_3", db=-3.0, delay=0.05, lp=9000), C("sf50_shoot2", db=-6.0, delay=0.18, hp=1500)], 0.5)
    emit("melee_whip", match(x, "melee_whip"))
    x = mix([C("sw_4", semis=-2.0, lp=9000), C("kn_impact_metal4", db=-7.0, delay=0.08, semis=4.0, hp=800)], 0.7)
    emit("melee_blade", match(x, "melee_blade"))


def build_weapon_foley():
    emit("dry_fire_0", match(mix([C("equip_click_a", hp=600)], 0.2), "dry_fire_0", window=200.0))
    emit("dry_fire_1", match(mix([C("equip_click_b", hp=600)], 0.2), "dry_fire_1", window=200.0))
    emit("reload", match(mix([C("reload_ar", lp=9000)], 1.6), "reload", window=600.0))
    emit("reload_1", match(mix([C("reload_pistol", lp=9000)], 1.6), "reload_1", window=600.0))
    emit("reload_2", match(mix([C("reload_starninjas", lp=9000), C("reload_clip2", db=-6.0, delay=1.0), C("shotgun_cock", db=-8.0, delay=0.4)], 1.5), "reload_2", window=600.0))
    # ricochets: a clink whose pitch falls away, with a little air on top; whizzes: a swish pushed up and Doppler-bent
    for i, cid in enumerate(("mi_clink1", "mi_clink2", "mi_clink3", "mi_bing")):
        x = mix([C(cid, gl=(1.7 + 0.15 * i, 0.75), hp=700), C("sw_5", db=-9.0, hp=2500, delay=0.0)], 0.6)
        emit("ricochet_%d" % i, match(x, "ricochet_%d" % i, window=300.0))
    for i, cid in enumerate(("sw_1", "sw_2", "sw_3", "sw_7")):
        x = C(cid, semis=5.0 + i, gl=(1.5, 0.8), hp=1800)[0]
        x = mr.band(x, 1500, 9500)
        emit("whizz_%d" % i, match(x, "whizz_%d" % i, window=300.0))


# ------------------------------------------------------------------ impacts, explosions, crashes
def add_body(x, seed, gain, f0=190, f1=62, dur=0.07, tau=0.03):
    n = len(x)
    b = mr.body(n, mr.R(seed), f0, f1, dur, tau, 2.4, 1.0)
    return x + b / (np.max(np.abs(b)) + 1e-12) * gain


def build_impacts():
    flesh = (("qi_meat1", 0.0), ("qp_punch1", -2.0), ("qi_meat2", 0.0), ("qp_punch4", -1.0))
    for i, (cid, sm) in enumerate(flesh):
        x = mix([C(cid, semis=sm, lp=6500)], 0.5)
        emit("impact_flesh_%d" % i, match(add_body(x, 9600 + i, 0.45), "impact_flesh_%d" % i, window=300.0, hp=70.0, boost=3.0, squash=2.2))
    conc = (("qi_stone", 0.0, "br_rock_h01"), ("br_rock_h01", -2.0, "c2_stones2"), ("c2_stones1", 0.0, None), ("c2_stones3", -2.0, "br_rock_h01"))
    for i, (cid, sm, extra) in enumerate(conc):
        parts = [C(cid, semis=sm)] + ([C(extra, db=-5.0, semis=-3.0, delay=0.004)] if extra else [])
        emit("impact_concrete_%d" % i, match(add_body(mix(parts, 0.55), 9700 + i, 0.4, 260, 90, 0.05, 0.02), "impact_concrete_%d" % i, window=300.0, hp=90.0, boost=5.0, squash=3.0))
    for i, cid in enumerate(("qi_metal", "br_metal_h03", "c2_metal_h1", "mi_clink3")):
        emit("impact_metal_%d" % i, match(mix([C(cid, hp=300)], 0.8), "impact_metal_%d" % i, window=300.0, boost=3.0, squash=2.2))
    for i, cid in enumerate(("br_glass_h02", "c2_glass1", "br_glass_b02", "c2_glass6")):
        emit("impact_glass_%d" % i, match(mix([C(cid, hp=400)], 0.7), "impact_glass_%d" % i, window=300.0, boost=3.0, squash=2.2))
    asph = (("qi_stone", -4.0, "mi_thud3"), ("br_rock_h01", -3.0, "mi_thud3"), ("c2_stones3", -3.0, None), ("br_rock_f09", 0.0, None))
    for i, (cid, sm, extra) in enumerate(asph):
        parts = [C(cid, semis=sm, lp=7000)] + ([C(extra, db=-6.0, semis=-4.0, delay=0.002, lp=3000)] if extra else [])
        emit("impact_asphalt_%d" % i, match(add_body(mix(parts, 0.6), 9750 + i, 0.35, 230, 80, 0.06, 0.025), "impact_asphalt_%d" % i, window=300.0, hp=80.0, boost=3.0, squash=2.2))
    for i, (cid, sm) in enumerate((("st_stone01", -4.0), ("st_stone_l1", -5.0), ("st_stone_r2", -6.0))):
        emit("land_asphalt_%d" % i, match(add_body(mix([C(cid, semis=sm, lp=6000), C("mi_thud3", db=-4.0, semis=-5.0, lp=2000)], 0.5), 9760 + i, 0.4, 200, 70, 0.06, 0.03), "land_asphalt_%d" % i, window=300.0, hp=60.0))
    for i, (cid, sm) in enumerate((("st_metal_25", -4.0), ("st_metal_09", -5.0), ("st_metal_17", -6.0))):
        emit("land_metal_%d" % i, match(add_body(mix([C(cid, semis=sm), C("mi_thud2", db=-5.0, semis=-3.0, lp=3000)], 0.5), 9770 + i, 0.3, 210, 75, 0.05, 0.025), "land_metal_%d" % i, window=300.0, hp=60.0))


def build_hits():
    """The hit marker when your round lands on a foe: a punch / meat impact with a tick on top (hit), a heavier one for a kill (hit_kill)."""
    emit("hit", match(add_body(mix([C("qp_punch3", lp=7000), C("ki_tick4", db=-6.0, hp=1500)], 0.4), 9780, 0.4, 220, 80, 0.05, 0.025), "hit", window=250.0, hp=80.0, squash=2.0))
    emit("hit_kill", match(add_body(mix([C("qi_meat2", lp=7000), C("qp_punch5", db=-3.0, delay=0.01), C("ki_confirm4", db=-12.0, delay=0.03, hp=1200)], 0.6), 9781, 0.7, 180, 55, 0.09, 0.04), "hit_kill", window=300.0, hp=60.0, squash=2.0))


def synth_explosion(seed, big):
    s = mr.explosion(seed, big)
    return s / (np.max(np.abs(s)) + 1e-12)


def boom_mix(parts, length, seed, big, sub=0.7, rt=1.4, wet=0.25):
    real = mix(parts, length)
    sy = synth_explosion(seed, big)
    x = np.zeros(max(len(real), len(sy)))
    x[:len(real)] += real
    low = mr.lp(sy, 220.0, 2)
    x[:len(low)] += low * sub                                       # only its sub-bass and rumble: the crack and debris come from the real clips
    x = ma.reverb(x, rt, wet=wet, predelay=0.02, damp=0.55, seed=seed + 7)
    return x


def build_explosions():
    jobs = (("boom", [C("expl_chunky", lp=9000), C("sf50_expl1", db=-6.0, delay=0.02, lp=7000)], 3.4, 9900, True),
            ("boom_1", [C("kn_expl_crunch4", lp=9000), C("bang_cannon2", db=-4.0, delay=0.01, lp=8000)], 3.2, 9923, True),
            ("boom_2", [C("expl_muffled", db=-3.0), C("kn_expl_crunch3", db=-4.0, delay=0.02, lp=8000)], 3.4, 9946, True),
            ("boom_3", [C("expl_n99", lp=9000), C("sf50_rocket", db=-8.0, semis=-5.0, delay=0.04, lp=3000), C("bang_06", db=-5.0, lp=8000)], 3.2, 9969, True),
            ("explosion_small_0", [C("kn_expl_crunch0", lp=9000), C("bang_01", db=-4.0, lp=8000)], 1.8, 9950, False),
            ("explosion_small_1", [C("bang_cannon4", lp=9000), C("kn_expl_crunch2", db=-5.0, delay=0.02, lp=8000)], 1.8, 9973, False))
    for name, parts, length, seed, big in jobs:
        x = boom_mix(parts, length, seed, big, sub=0.55 if big else 0.45)
        emit(name, mr.master(x, lv(name)[0], 6.5, 30.0, 0.5, length + 0.4))
    # distant fire and booms: the real mid-distance recordings and the real far explosion, made duller and wetter
    x = mr.lp(mix([C("expl_far", lp=2500)], 3.0), 1800)
    emit("distant_boom_0", match(ma.reverb(x, 1.4, wet=0.3, predelay=0.02, damp=0.7, seed=3), "distant_boom_0", window=800.0, fout=0.3))
    x = mix([C("expl_muffled", lp=1400, db=-2.0)], 3.5)
    emit("distant_boom_1", match(x, "distant_boom_1", window=800.0, fout=0.4))
    x = mr.lp(mix([C("fl_ak_burst_mid", lp=3000)], 3.5), 2600)
    emit("distant_gunfire_0", match(ma.reverb(x, 1.0, wet=0.3, predelay=0.03, damp=0.7, seed=4), "distant_gunfire_0", window=800.0, fout=0.4))
    x = mr.lp(mix([C("fl_ppsh_burst_mid", lp=3000), C("fl_ak_burst_mid2", db=-6.0, lp=2500, delay=0.6)], 3.8), 2600)
    emit("distant_gunfire_1", match(ma.reverb(x, 1.0, wet=0.3, predelay=0.03, damp=0.7, seed=5), "distant_gunfire_1", window=800.0, fout=0.4))
    # vehicle crashes and bumps: real metal and glass, a thump under them
    crashes = (([C("br_metal_f01"), C("br_glass_b01", db=-3.0, delay=0.06), C("crash_qubodup", db=-4.0)], 1.9, 9801),
               ([C("br_fall04"), C("crash_qubodup", db=-3.0, delay=0.02), C("c2_glass3", db=-4.0, delay=0.12)], 1.9, 9802),
               ([C("br_rock_b01", lp=8000), C("br_metal_h02", db=-2.0, delay=0.03), C("glass_break", db=-5.0, delay=0.1)], 2.0, 9803))
    for i, (parts, length, seed) in enumerate(crashes):
        x = add_body(mix(parts, length), seed, 0.8, 140, 40, 0.18, 0.08)
        x = ma.reverb(x, 1.3, wet=0.3, predelay=0.012, damp=0.5, seed=seed)         # a street-corner tail: the real hits are short
        emit("car_crash_%d" % i, match(x, "car_crash_%d" % i, window=700.0, fout=0.3, hp=40.0))
    bumps = (([C("br_metal_h04", semis=-4.0), C("mi_thud3", db=-3.0, semis=-3.0)], 9811), ([C("br_hit12", semis=-3.0, lp=5000), C("mi_thud2", db=-3.0, semis=-2.0)], 9812), ([C("c2_slam", semis=-2.0, lp=5000)], 9813))
    for i, (parts, seed) in enumerate(bumps):
        emit("car_bump_%d" % i, match(add_body(mix(parts, 0.6), seed, 0.7, 170, 55, 0.1, 0.05), "car_bump_%d" % i, window=300.0, hp=50.0))


# ------------------------------------------------------------------ footsteps
def build_footsteps():
    asphalt = ("st_stone_l1", "st_stone_r1", "st_stone_l2", "st_stone_r2", "st_stone_l3", "st_stone_r3", "st_c2_01", "st_c2_02")
    for i, cid in enumerate(asphalt):
        emit("step_asphalt_%d" % i, match(mix([C(cid, semis=[0, 0.4, -0.5, 0.2, -0.3, 0.6, 0, 0][i])], 0.5), "step_asphalt_0", window=300.0, hp=70.0))
    for i, k in enumerate(("01", "05", "09", "13", "17", "21", "03", "07", "11", "15")):
        emit("step_metal_%d" % i, match(mix([C("st_metal_" + k)], 0.4), "step_metal_0", window=250.0, hp=80.0))
    for i, cid in enumerate(("st_wood1", "st_wood2", "st_wood3", "st_c2_wood1", "st_c2_wood3", "st_c2_wood4")):
        emit("step_stairs_%d" % i, match(mix([C(cid)], 0.5), "step_stairs_0", window=300.0, hp=70.0))
    for i, cid in enumerate(("st_sub_1", "st_sub_2", "st_sub_3", "st_sub_4")):
        emit("step_tile_%d" % i, match(mix([C(cid, lp=7500)], 0.45), "step_tile_0", window=300.0, hp=90.0))
    for i, cid in enumerate(("st_sand_l1", "st_sand_r1", "st_sand_l2", "st_sand_r2")):
        emit("step_carpet_%d" % i, match(mix([C(cid, lp=2200)], 0.5), "step_carpet_0", window=300.0, hp=70.0))
    roof = ((("st_gravel", 0.0), ("st_stone_l2", -4.0)), (("st_gravel", 2.0), ("st_stone_r2", -4.0)), (("st_sand_l1", 0.0), ("st_stone_l3", -5.0)), (("st_gravel", -1.5), ("st_stone_r3", -4.0)))
    for i, ((c1, s1), (c2, s2)) in enumerate(roof):
        emit("step_roof_%d" % i, match(mix([C(c1, semis=s1, length=0.5, lp=7500), C(c2, db=-3.0, semis=s2, delay=0.0)], 0.6), "step_roof_0", window=300.0, hp=70.0))


# ------------------------------------------------------------------ vehicles
def circ_hp(x, hz):
    return ma.fft_filter(x, lo=hz, order=4) if hz else x


def engine_loop(cid, ratio=1.0, lp=None, name=None):
    x = rc.load_clip(cid)
    if ratio != 1.0:
        x = loop_ratio(x, ratio)
    x = circ_hp(x, 45.0)
    if lp:
        x = ma.fft_filter(x, None, lp, 2)
    x = x - np.mean(x)
    x = np.tile(x, int(np.ceil(1.2 / (len(x) / SR))))                 # whole cycles repeated: still seamless, and long enough for the tests (and the ear) not to hear a 0.6 s stutter
    x = x / (np.max(np.abs(x)) + 1e-12)
    peak, rms = lv(name)[0], lv(name)[2]
    x = x * 10 ** (rms / 20.0) / (np.sqrt(np.mean(x ** 2)) + 1e-12) * 1.0
    k = np.max(np.abs(x))
    if k > 10 ** (min(peak, -9.0) / 20.0):
        x = x / k * 10 ** (min(peak, -9.0) / 20.0)
    return x


def build_vehicle():
    emit("engine_low", engine_loop("veh_loop1", name="engine_low"), loop=True)
    emit("engine_high", engine_loop("veh_loop5", name="engine_high"), loop=True)
    emit("engine_bike_low", engine_loop("veh_loop3", 1.3, name="engine_bike_low"), loop=True)
    emit("engine_bike_high", engine_loop("veh_loop5", 1.5, name="engine_bike_high"), loop=True)
    emit("engine_heavy_low", engine_loop("veh_loop0", 0.85, lp=1800, name="engine_heavy_low"), loop=True)
    emit("engine_heavy_high", engine_loop("veh_loop1", 0.9, lp=2000, name="engine_heavy_high"), loop=True)
    emit("engine_start", match(mix([C("veh_start1"), C("veh_start2", db=-8.0, delay=0.9, length=1.0)], 2.2), "engine_start", window=800.0, fout=0.1))
    emit("horn_0", match(mix([C("veh_horn")], 0.7), "horn_0", window=300.0))
    emit("horn_1", match(mix([C("veh_horn", semis=-3.0)], 0.7), "horn_1", window=300.0))
    emit("car_door", match(mix([C("veh_door_close2"), C("veh_door_close", db=-5.0, delay=0.03)], 0.8), "car_door", window=300.0))


# ------------------------------------------------------------------ UI
def build_ui():
    ui = {
        "ui_click": [C("ki_click3")], "ui_tap": [C("ui_click2")], "ui_tick": [C("ki_tick4")], "ui_hover": [C("ki_tick2", db=-2.0)], "ui_toggle": [C("ki_toggle3")],
        "ui_slide": [C("ki_scroll1")], "ui_back": [C("ki_back2")], "ui_confirm": [C("ki_confirm3")], "ui_deny": [C("ki_error2")], "ui_error": [C("ki_error4")],
        "ui_notify": [C("ki_question1"), C("ki_glass1", db=-5.0, delay=0.14)], "ui_pause": [C("ki_minimize6")], "ui_resume": [C("ki_maximize5")],
        "ui_purchase": [C("ki_confirm4"), C("ki_drop4", db=-4.0, delay=0.12)], "ui_upgrade": [C("ki_glass1"), C("sf_term09", db=-8.0, delay=0.1, lp=8000)],
        "ui_contract_accept": [C("ki_select3"), C("ki_confirm3", db=-2.0, delay=0.14)], "ui_contract_complete": [C("ki_confirm4"), C("ki_bong1", db=-4.0, delay=0.18)],
        "ui_contract_fail": [C("ki_error4"), C("ki_bong1", db=-4.0, semis=-5.0, delay=0.15)],
    }
    for name, parts in ui.items():
        emit(name, match(mix(parts, lv(name)[3] + 0.3), name, window=250.0, fout=0.04))


# ------------------------------------------------------------------ ambience beds
def bed(cid, name, lp=None, hp=None, gain_db=0.0, seconds=24.0, xf=0.5):
    x = rc.load_clip(cid)
    L, X = _n(seconds), _n(xf)
    if len(x) < L + X:
        raise SystemExit("%s: clip %s is %.1f s, need %.1f" % (name, cid, len(x) / SR, seconds + xf))
    if hp:
        x = mr.hp(x, hp, 2)
    if lp:
        x = mr.lp(x, lp, 2)
    x = x - np.mean(x)
    out = x[:L].copy()
    t = np.linspace(0.0, np.pi / 2, X)
    out[:X] = x[:X] * np.sin(t) + x[L:L + X] * np.cos(t)             # the tail fades into the head: out[0] follows out[L-1] in the source
    peak, rms = lv(name)[0], lv(name)[2]
    out = out * 10 ** ((rms - am.rms_db(out) + gain_db) / 20.0)           # rms_db is 10 log10 of the mean square: a dB of power, i.e. of amplitude
    out = am.limiter(out, min(peak, -9.0), 0.02, wrap=True)
    return out


def build_beds():
    emit("rain_asphalt", bed("amb_rain_a", "rain_asphalt"), ogg=True)
    emit("rain_metal", bed("amb_rain_c", "rain_metal", hp=500.0), ogg=True)
    emit("rain_awning", bed("amb_rain_b", "rain_awning", lp=5200.0), ogg=True)
    emit("traffic_far", bed("amb_traffic", "traffic_far", lp=2600.0), ogg=True)
    emit("wind", bed("amb_wind", "wind", lp=3500.0), ogg=True)
    emit("city_hum", bed("amb_city", "city_hum", lp=2400.0), ogg=True)


# ------------------------------------------------------------------ round 5: the weapon roster (docs/DESIGN.md)
ROSTER_ALIAS = {   # new sound -> an existing sound whose level row (real_levels.py) it follows
    "shot_magnum": "shot_rev", "shot_mp": "shot_burst", "shot_ar2": "shot", "shot_bpup": "shot_burst", "shot_lmg": "shot", "shot_amr": "shot_rail", "shot_xbow": "melee_whip",
    "shot_flame": "shot_mini", "shot_stun": "shot_arc", "melee_katana": "melee_blade", "melee_bat": "melee_blade", "shot_qsuper": "shot_arc", "shot_qlink": "shot_arc",
    "shot_qcollapse": "shot_gravity", "shot_qblink": "shot_arc", "shot_qphase": "shot_lance", "shot_qstasis": "shot_arc",
}


def _rs(seed):
    return np.random.RandomState(seed)


def twang(seed, f0=560.0, f1=170.0, dur=0.4, decay=13.0):
    """A plucked string (crossbow release): a falling fundamental with two harmonics and a short noise click."""
    n = _n(dur)
    t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 20.0)
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    x = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)) * np.exp(-t * decay)
    click = _rs(seed).randn(n) * np.exp(-t * 400.0)
    return (x + 0.6 * click) / 1.8


def crackle(seed, dur=0.35, density=0.03, hp_hz=1800.0):
    """Electric crackle: random sparse impulses through a high-pass with a decaying envelope (stun gun, stasis)."""
    n = _n(dur)
    r = _rs(seed)
    x = r.randn(n) * (r.rand(n) < density)
    x = mr.hp(x, hp_hz, 2)
    return x * np.exp(-np.arange(n) / SR * 9.0)


def whoosh(seed, dur=0.26, lo=250.0, hi=3200.0, attack=0.025, decay=9.0):
    """A flame / air roar: band-limited noise with a short attack."""
    n = _n(dur)
    t = np.arange(n) / SR
    x = mr.band(_rs(seed).randn(n), lo, hi)
    return x * np.minimum(1.0, t / attack) * np.exp(-t * decay)


def part(x, db=0.0, delay=0.0):
    x = np.asarray(x, dtype=np.float64)
    return (x / (np.max(np.abs(x)) + 1e-12) * 10 ** (db / 20.0), delay)


def emit_o(name, x):
    """The roster sounds ship as OGG (q4): a third of the size of the WAV, the audio folder is inside its budget."""
    emit(name, x, ogg=True)


def build_roster():
    for k, v in ROSTER_ALIAS.items():
        for sfx in ("", "_1", "_2"):
            LEVELS[k + sfx] = LEVELS[v]
    # heavy pistol: the 1911 and the 1917 with a revolver-class thump and a long tail
    for i, (cid, sm) in enumerate((("fl_1911_near", -4.0), ("fl_1917_near", -2.0))):
        nm = "shot_magnum" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=7000), C("fl_sw642_near", db=-7.0, semis=-8.0, lp=900, delay=0.002)], "revolver", 9800 + i, body=0.7, presence=1.2, length=0.9, body_f=(250, 80)))
    # machine pistol: three quick pistol cracks pitched up, no tail (it repeats 14 times a second)
    for i, (cid, sm) in enumerate((("fl_ppq_near", 1.5), ("fl_bersa_near", 2.5), ("fl_1911_near", 3.5))):
        nm = "shot_mp" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=7500)], "burst", 9810 + i, body=0.5, presence=1.0, length=0.22))
    # RANGER assault rifle: the AR-15 and AK a little lower than the carbine's, so the two are not the same gun
    for i, (cid, sm) in enumerate((("fl_ar15_near", -2.5), ("fl_ak_near2", -3.0), ("fl_sks_near", -2.0))):
        nm = "shot_ar2" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=6500)], "rifle", 9820 + i, body=0.5, presence=0.9, length=0.7, body_f=(220, 65)))
    # BULLPUP burst rifle: a bright, light crack (the savage .300 and the AR-15 pitched up)
    for i, (cid, sm) in enumerate((("fl_savage_near", 2.0), ("fl_ar15_near", 2.5), ("fl_ak_near", 1.5))):
        nm = "shot_bpup" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=8000)], "burst", 9830 + i, body=0.4, presence=1.4, length=0.3))
    # LMG: heavy and dull, the AK pitched well down over a low thump
    for i, (cid, sm) in enumerate((("fl_ak_near", -4.5), ("fl_ak_near2", -5.5), ("fl_ar15_near", -5.0))):
        nm = "shot_lmg" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=5200)], "rifle", 9840 + i, body=0.85, presence=0.6, length=0.45, body_f=(190, 55)))
    # anti-material rifle: a Mosin crack, a black-powder boom and a cannon tail
    for i, (cid, sm, bang) in enumerate((("fl_mosin_near", -5.0, "bang_cannon2"), ("fl_savage_near", -6.0, "bang_cannon4"))):
        nm = "shot_amr" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(cid, semis=sm, lp=6000), C("lark_blackpowder", db=-3.0, semis=-5.0, lp=2500), C(bang, db=-8.0, semis=-3.0, lp=1500, delay=0.01)], "revolver", 9850 + i, body=1.1, presence=1.0,
                      length=1.4, tail=(1.1, 0.3), body_f=(170, 45)))
    # crossbow: a string twang, the latch click and a short swish of the bolt
    for i in range(2):
        nm = "shot_xbow" + ("" if i == 0 else "_%d" % i)
        x = mix([part(twang(9860 + i, 560.0 + 80.0 * i, 170.0 + 20.0 * i), 0.0), C("equip_click_a", db=-6.0, hp=900), C("sw_2", db=-10.0, semis=3.0 + i, delay=0.01, hp=1800)], 0.5)
        emit_o(nm, match(x, nm, boost=3.0))
    # flamethrower: a fuel whoosh, a low rumble and a hiss (three takes, it repeats 16 times a second)
    for i in range(3):
        nm = "shot_flame" + ("" if i == 0 else "_%d" % i)
        x = mix([part(whoosh(9870 + i, 0.24, 250.0, 3200.0), 0.0), part(whoosh(9880 + i, 0.2, 60.0, 400.0, 0.02, 10.0), -2.0), C("sw_%d" % (1 + i * 2), db=-8.0, semis=-4.0 + i, lp=3500)], 0.3)
        emit_o(nm, match(x, nm, window=200.0))
    # stun gun: an electric zap over a crackle
    for i in range(2):
        nm = "shot_stun" + ("" if i == 0 else "_%d" % i)
        x = mix([C(["kn_laser_s0", "kn_laser_s2"][i], semis=-3.0 + 2.0 * i, lp=9000), part(crackle(9890 + i, 0.4, 0.03 + 0.01 * i), -2.0), C("sf60_21a", db=-9.0, semis=2.0, lp=8000)], 0.5)
        emit_o(nm, match(x, nm, boost=2.0))
    # katana: a fast high swish, then a steel ring
    for i in range(2):
        nm = "melee_katana" + ("" if i == 0 else "_%d" % i)
        x = mix([C("sw_3", semis=3.0 + i, hp=600, lp=10000), C("kn_impact_metal4", db=-9.0, delay=0.06, semis=9.0 + 2.0 * i, hp=2500)], 0.55)
        emit_o(nm, match(x, nm))
    # bat: a heavy low swish and a wooden thwack
    for i in range(2):
        nm = "melee_bat" + ("" if i == 0 else "_%d" % i)
        x = mix([C("sw_4", semis=-4.0 - i, lp=7000), C(["st_c2_wood1", "st_c2_wood3"][i], db=-1.0, delay=0.07, semis=-5.0, lp=3000), C("qp_punch1", db=-8.0, delay=0.075, semis=-3.0, lp=2000)], 0.6)
        emit_o(nm, match(x, nm, boost=2.0))
    # quantum weapons
    for i in range(2):                                                                     # SUPERPOSITION: a laser and its fading echo a split second later
        nm = "shot_qsuper" + ("" if i == 0 else "_%d" % i)
        base = C(["kn_laser_s1", "kn_laser_r0"][i], lp=9000)
        echo1 = C(["kn_laser_s1", "kn_laser_r0"][i], db=-6.0, semis=4.0, delay=0.09, lp=7000)
        echo2 = C(["kn_laser_s1", "kn_laser_r0"][i], db=-12.0, semis=8.0, delay=0.18, lp=5000)
        emit_o(nm, shot(nm, [base, echo1, echo2], "flux", 9900 + i, body=0.4, length=0.6, tail=(0.5, 0.25)))
    for i in range(2):                                                                     # ENTANGLE: two tones a fifth apart, one laser each, joined by a shimmer
        nm = "shot_qlink" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(["kn_laser_r4", "kn_laser_r0"][i], lp=9000), C(["kn_laser_r4", "kn_laser_r0"][i], db=-3.0, semis=7.0, delay=0.012, lp=8000), C("sf60_21a", db=-8.0, hp=2000)], "flux", 9910 + i, body=0.35,
                      length=0.5, tail=(0.4, 0.2)))
    for i in range(2):                                                                     # COLLAPSE CANNON: a huge low boom with a falling force-field whine
        nm = "shot_qcollapse" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(["kn_lowexpl0", "kn_lowexpl1"][i], semis=-5.0, lp=1200), C(["kn_forcefield2", "kn_forcefield0"][i], db=-3.0, semis=-6.0, lp=4000, gl=(1.2, 0.6)), C("bang_cannon2", db=-6.0, semis=-6.0, lp=900, delay=0.01)],
                      "revolver", 9920 + i, body=1.5, length=1.3, tail=(0.9, 0.3), body_f=(130, 32)))
    for i in range(2):                                                                     # BLINK PISTOL: a retro laser that rises, a swish pulled upward
        nm = "shot_qblink" + ("" if i == 0 else "_%d" % i)
        x = mix([C("sf50_retro_laser1", gl=(0.8, 1.5 + 0.2 * i), lp=9000), C("sw_2", db=-7.0, semis=6.0, gl=(0.9, 1.6), hp=1500)], 0.5)
        emit_o(nm, shot(nm, [(x, 0.0)], "flux", 9930 + i, body=0.3, length=0.45))
    for i in range(2):                                                                     # PHASE RIFLE: a muffled laser behind a force field, as heard through a wall
        nm = "shot_qphase" + ("" if i == 0 else "_%d" % i)
        emit_o(nm, shot(nm, [C(["kn_laser_l2", "kn_laser_l0"][i], lp=4500), C("kn_forcefield0", db=-4.0, semis=2.0 + i, lp=3500), C("sf50_shoot1", db=-9.0, hp=1200, lp=7000)], "flux", 9940 + i, body=0.45,
                      length=0.6, tail=(0.7, 0.3)))
    for i in range(2):                                                                     # STASIS RAY: a cold, steady hum with a crystalline crackle
        nm = "shot_qstasis" + ("" if i == 0 else "_%d" % i)
        x = mix([C(["kn_forcefield0", "kn_forcefield2"][i], semis=3.0, hp=300, lp=9000), part(crackle(9950 + i, 0.5, 0.012, 3500), -6.0), C("kn_laser_s2", db=-9.0, semis=5.0, lp=9000)], 0.6)
        emit_o(nm, match(x, nm, boost=1.0))


STEPS = [build_shots, build_weapon_foley, build_impacts, build_hits, build_explosions, build_footsteps, build_vehicle, build_ui, build_beds, build_roster]


def main():
    global OUT, ONLY
    args = sys.argv[1:]
    if "--only" in args:
        i = args.index("--only")
        ONLY = args[i + 1:]
        args = args[:i]
    if args:
        OUT = args[0]
    os.makedirs(OUT, exist_ok=True)
    for fn in STEPS:
        fn()
    if not ONLY:                                                     # the list tests/test_audio_real_samples.gd reads: what was built from real clips
        with open(os.path.join(OUT, "real_manifest.json"), "w") as f:
            json.dump({"builder": "tools/audio/make_real.py", "clips": len(rc.CLIPS), "built": sorted(BUILT)}, f, indent=0)
            f.write("\n")


if __name__ == "__main__":
    main()
