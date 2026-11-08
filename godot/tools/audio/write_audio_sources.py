#!/usr/bin/env python3
"""Writes the provenance files of the open-source audio: art_sources/audio_<group>/LICENSE.txt and SOURCE.md for every group in real_clips.GROUPS, and docs/AUDIO_SOURCES.md
(table of every clip: file, source URL, author, licence, and which game sounds it feeds). Run after changing real_clips.py or make_real.py:
  python3 tools/audio/write_audio_sources.py [--raw <folder with the unpacked packs>]   (--raw copies the pack's own License.txt where it ships one, e.g. Kenney's)
"""
import ast
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import real_clips as rc  # noqa: E402

DOCS = os.path.abspath(os.path.join(rc.ROOT, "..", "docs"))

CC0_TEXT = """CC0 1.0 Universal (Public Domain Dedication)

The person(s) who associated a work with this deed have dedicated the work to the public domain by waiving all of their rights to the work worldwide under copyright law,
including all related and neighbouring rights, to the extent allowed by law. You can copy, modify, distribute and perform the work, even for commercial purposes, all without
asking permission. Credit is not required (it is given anyway in docs/AUDIO_SOURCES.md and docs/THIRD_PARTY.md).

Full legal code: https://creativecommons.org/publicdomain/zero/1.0/legalcode
Deed: https://creativecommons.org/publicdomain/zero/1.0/

How the licence of each pack was established: the OpenGameArt.org page of the pack shows the licence 'CC0' (checked while fetching, round 4); the pack-specific statements are quoted below.
"""

PACK_NOTES = {
    "firearm_library": "Statement on the OpenGameArt page, quoting the project: 'Our team holds CC0 NO RIGHTS RESERVED for this library. It may be used without royalty or credit (though we would love to hear how you've used our sounds) for any application, personal or professional.'",
    "kenney_scifi": "License.txt of the pack (Kenney, https://kenney.nl): 'Creative Commons CC0 1.0 Universal ... you can use these assets in personal and commercial projects. Credit is not required but appreciated.'",
    "kenney_interface": "License.txt of the pack (Kenney, https://kenney.nl): 'Creative Commons CC0 1.0 Universal ... you can use these assets in personal and commercial projects. Credit is not required but appreciated.'",
    "impact_punch": "The Metal Impact Sounds page asks for optional credit: Brian MacIntosh. The Impact and Punch packs were made for lipsofsuna.org from qubodup's Freesound recordings (CC0 on the page).",
    "gunshot_singles": "The Gun Reload Sound Effects page asks for optional credit: Brian MacIntosh; Gun reload sounds (Joaken) 'free to use, credit will be nice'.",
    "explosion_singles": "Muffled Distant Explosion: a log drum hit by NenadSimic, uploaded by Cokabear; Chunky Explosion by looneybits.",
}


def used_by():
    """clip id -> the build functions of make_real.py that reference it (a coarse but exact list of what the clip feeds)."""
    tree = ast.parse(open(os.path.join(HERE, "make_real.py")).read())
    out = {}
    for fn in [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name.startswith("build_")]:
        for node in ast.walk(fn):
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                v = node.value
                hit = [v] if v in rc.CLIPS else ([c for c in rc.CLIPS if c.startswith(v.split("%d")[0])] if "%d" in v and len(v.split("%d")[0]) > 3 else
                                                   ([c for c in rc.CLIPS if c.startswith(v)] if v.endswith("_") and len(v) > 3 else []))
                for c in hit:
                    out.setdefault(c, set()).add(fn.name[len("build_"):])
    return out


FAMILY = {"shots": "weapon shots (all classes), enemy fire, melee", "weapon_foley": "reloads, dry fire, ricochets, bullet whizz", "impacts": "impacts (flesh, concrete, metal, glass, asphalt), landings",
          "hits": "hit markers", "explosions": "explosions, distant booms and gunfire, car crashes and bumps", "footsteps": "footsteps per surface", "vehicle": "engines, engine start, horn, car door",
          "ui": "UI cues", "beds": "ambience beds (rain, traffic, wind, city hum)"}


def main():
    raw = None
    if "--raw" in sys.argv:
        raw = sys.argv[sys.argv.index("--raw") + 1]
    users = used_by()
    by_group = {}
    for cid, c in rc.CLIPS.items():
        by_group.setdefault(c["group"], []).append(cid)
    total = 0
    for g, info in rc.GROUPS.items():
        d = os.path.join(rc.ART, "audio_" + g)
        os.makedirs(d, exist_ok=True)
        lic = CC0_TEXT + "\n" + PACK_NOTES.get(g, "")
        if raw:
            for top in sorted({rc.CLIPS[c]["src"].split("/")[0] for c in by_group[g]}):
                for nm in ("License.txt", "license.txt", "readme.txt"):
                    p = os.path.join(raw, top, nm)
                    if os.path.exists(p):
                        lic += "\n\n---- %s/%s (shipped with the pack) ----\n" % (top, nm) + open(p, errors="ignore").read()
        open(os.path.join(d, "LICENSE.txt"), "w").write(lic.strip() + "\n")
        size = sum(os.path.getsize(rc.clip_path(c)) for c in by_group[g])
        total += size
        lines = ["# %s" % info["title"], "", "- Author: %s" % info["author"], "- Licence: %s" % info["license"], "- Pages (checked in round 4, all show CC0):"]
        lines += ["  - %s" % u for u in info["pages"]]
        lines += ["- Note: %s" % info["note"], "",
                  "Only the clips the game uses are kept here (%d clips, %.0f KB): cut by tools/audio/real_clips.py (mono, 44.1 kHz, peak -1 dBFS, OGG q6; loops FLAC), "
                  "turned into the game's sounds by tools/audio/make_real.py. The rest of the pack is not in the repo; download it from the page above." % (len(by_group[g]), size / 1024), "",
                  "| clip | original file in the pack | page | author | feeds |", "|---|---|---|---|---|"]
        for cid in by_group[g]:
            url, author, orig = rc.clip_meta(cid)
            lines.append("| clips/%s | %s | %s | %s | %s |" % (os.path.basename(rc.clip_path(cid)), orig, url, author, ", ".join(sorted(users.get(cid, ["-"])))))
        open(os.path.join(d, "SOURCE.md"), "w").write("\n".join(lines) + "\n")
    # docs/AUDIO_SOURCES.md
    rows = []
    for cid, c in rc.CLIPS.items():
        url, author, orig = rc.clip_meta(cid)
        rows.append("| art_sources/audio_%s/clips/%s | %s | %s | %s | CC0 | %s |" % (c["group"], os.path.basename(rc.clip_path(cid)), orig, url, author, "; ".join(FAMILY.get(f, f) for f in sorted(users.get(cid, ["-"])))))
    out = ["# Audio sources (open-source recordings)", "",
           "Round 4: the weapon, impact, explosion, footstep, vehicle, UI and ambience sounds that used to be synthesised (and sounded like Tetris) are built from real CC0 recordings. Every pack was fetched from "
           "OpenGameArt.org with a plain, descriptive user agent; each page was checked to show the licence CC0 before the pack was used. Nothing else is used: no CC-BY, no NC, no sampling from games or sample libraries.", "",
           "Pipeline: `tools/audio/real_clips.py` cuts the clips (kept in `art_sources/audio_<group>/clips/` with the pack's licence text in `LICENSE.txt` and a `SOURCE.md`) -> `tools/audio/make_real.py` builds `godot/assets/audio/*` "
           "(real transient + our own sub-bass / tail where useful, mastered to the peak and K-weighted loudness of the sound it replaces; `tools/audio/real_levels.py` holds the numbers of the synthesised originals, "
           "so the mix table of `Sfx` and `tools/audio/check_audio.py` stays as tuned) -> `tools/audio/shrink_audio.py`. `tools/build_assets.sh` runs it after all synthesising generators. `tools/audio/write_audio_sources.py` regenerates the provenance files and this table.", "",
           "## What is real now", "",
           "| Sound family | Made from |", "|---|---|",
           "| Rifle shots `shot`, `shot_1..3` | AR-15, AK-47, SKS and Savage .300 recordings (Free Firearm Sound Library), sub-bass thump and a crack boost on top |",
           "| Pistols `shot_twin`, `_1`, `_2` | 1911, Walther PPQ, Bersa |",
           "| Revolvers `shot_rev`, `_1`, `_2` | Smith & Wesson 642, Ruger Single Six, Marlin 336, pitched down with a heavy sub |",
           "| Shotguns `shot_scatter`, `_1`, `_2` | Mossberg, Nova, Model 12 |",
           "| Minigun `shot_mini`, `_1..3` and burst `shot_burst`, `_1..3` | single rounds cut from PPSh-41 and Carl Gustav M45 bursts (four different rounds, so a long burst does not machine-gun one sample) |",
           "| Pulse classes `shot_flux`, `shot_arc`, `shot_rail`, `shot_lance`, `shot_gravity` | Kenney laser / force-field samples over real firearm transients and our own sub-bass |",
           "| Suppressed `shot_supp_*` | the 'Hollywood silencer' recording |", "| Overcharged `shot_oc_*` | real laser + black-powder boom + rocket over the synthesised sub fall and shimmer |",
           "| Distant `shot_far_*`, `enemy_shot_far_*`, `distant_gunfire_*`, `distant_boom_*` | the library's mid-distance recordings and real far explosions, low-passed |",
           "| Enemy fire `enemy_shot*` | SMG / pistol / rifle transients with a Kenney zap, pitched down so it reads as theirs |",
           "| Reloads, dry fire, ricochets, whizz, melee | Joaken / starninjas / Brian MacIntosh reloads, equipment clicks, metal clinks with a falling pitch, qubodup swishes |",
           "| Impacts `impact_*`, landings, hit markers | qubodup meat / stone / metal impacts and punches, 75 CC0 breaking sounds, glass and metal hits |",
           "| Explosions `boom*`, `explosion_small_*` | real booms (Chunky, number99, Kenney, cannon / firework bangs) over a synthesised sub-bass fall |",
           "| Car crashes and bumps | real metal / glass / rock breaking with a thump and a street tail |",
           "| Footsteps (asphalt, metal, stairs, tile, carpet, roof) | Fantozzi stone and sand, metal-on-concrete, subway, wood and gravel steps |",
           "| Engines `engine_*` | qubodup racing-car loops (whole cycles, seamless); bike and heavy variants re-pitched circularly |",
           "| Engine start, horn, car door | car engine start recordings, car sound effects pack, MedicineStorm's car door |",
           "| UI cues `ui_*` | Kenney Interface Sounds, gopherapps UI SFX, number99 terminal beeps |",
           "| Beds `rain_*`, `traffic_far`, `wind`, `city_hum` | Snabisch rain and traffic, a windy ambience, the 2DPIXX sci-fi city loop, crossfaded to 24 s seamless loops |", "",
           "Still synthesised (no suitable CC0 source found or fetched): tyre squeal (`tyre_squeal`), `engine_hover_*`, the quantum ability sounds (blink, link, superposition, collapse: these are the game's own identity), voices (troopers, aliens, hero, radio babble), stings, heartbeat and breath, sirens, pickups.", "",
           "## Music (composed as MIDI, rendered with a SoundFont)", "",
           "The music is no longer synthesised: `godot/tools/music/compose.py` composes four original tracks (explore 96 BPM, menu 64, combat 144, chase 160) plus seven theme layers as MIDI (`godot/tools/music/midi/`) and renders them with FluidSynth and the **FluidR3 GM SoundFont by Frank Wen, MIT licence** (https://musescore.org/download/fluid-soundfont.tar.gz, installed from the Ubuntu package `fluid-soundfont-gm`; licence text and SOURCE.md in `art_sources/soundfont_fluidr3_gm/`; the 148 MB `.sf2` is not committed). Tracks, stems, loop method, mastering numbers, how to run it and what was blocked or not done: **docs/MUSIC.md**.", "",
           "Blocked or unusable: kenney.nl returns 403 to scripts, so Kenney's packs came through their CC0 re-uploads on OpenGameArt (their License.txt is kept); the 'SuperTuxKart sound effects' pack (OpenGameArt) is one 82 s unlabelled mp3 with no way to tell skids from crashes, so it was not used; "
           "'Footsteps Leather, Cloth, Armor' is dual-licensed OGA-BY / CC0 and was skipped to keep the list strictly CC0.", "",
           "Size: art_sources clips %.1f MB (kept in the repo so the build is reproducible); assets/audio stays inside the 24 MB budget of test_audio_budget2." % (total / 1048576), "",
           "## Every clip", "",
           "| Clip (committed) | Original file in the pack | Source URL | Author | License | Feeds |", "|---|---|---|---|---|---|"]
    out += rows
    open(os.path.join(DOCS, "AUDIO_SOURCES.md"), "w").write("\n".join(out) + "\n")
    print("wrote %d group folders and docs/AUDIO_SOURCES.md (%d clips, %.2f MB)" % (len(rc.GROUPS), len(rc.CLIPS), total / 1048576))


if __name__ == "__main__":
    main()
