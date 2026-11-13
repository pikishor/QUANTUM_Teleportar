# w112-hero-look (done)

agent id a69d96b40de14c54e, 1530 events, first activity 2026-11-13T14:59:05.954Z, last activity 2026-11-13T19:24:15.367Z

## Final report

REPORT w112-hero-look (hero look v3, Round 6 wave 112). Working tree only, NOTHING committed or pushed. Progress log: /home/user/QUANTUM_Teleportar/docs/sprint/progress/w112-hero-look.md VERDICT: done and verified (software renderer only, nothing run on a phone). Perf gate is OK on all three tiers. PERF GATE (PERF_CHECK=1 tools/perf_report.sh 0 1 2, run by me last on the shared working tree that includes every builder's uncommitted changes): PERF RESULT tier=0 label=LOW renderer=mobile touch=0 draws=74 prims=138801 total_draws=96 total_prims=139667 nodes=2892 tex_mb=110 lights=3 hud_draws=21 death_draws=108 death_prims=134393 enemies=4 verdict=OK PERF RESULT tier=1 label=MED renderer=mobile touch=0 draws=97 prims=240518 total_draws=129 total_prims=272186 nodes=3030 tex_mb=141 lights=9 hud_draws=24 death_draws=144 death_prims=268140 enemies=4 verdict=OK PERF RESULT tier=2 label=HIGH renderer=mobile touch=0 draws=113 prims=326420 total_draws=149 total_prims=377842 nodes=3148 tex_mb=207 lights=12 hud_draws=25 death_draws=166 death_prims=371530 enemies=4 verdict=OK Attribution (A/B in a clean checkout of HEAD 2b4c37b plus ONLY my files, scratch worktree removed afterwards): HEAD alone MED = 130 total draws / 276,878 prims / tex 175 MB; HEAD + hero = MED 130 / 274,440 / 146 MB, LOW 96 / 139,473 / 115 MB, HIGH 149 / 368,888 / 207 MB, all OK. Hero LOD0 is 16,143 triangles against 16,023 before (one surface, one draw). Hero texture memory fell about 34 MB (tex limits untouched). My FIRST MED run was OVER (296,720 prims) although the triangle count was the same: the merged hero's LOD edge lengths (flat plates) made the engine keep fine LODs far too long (hero + shadow proxy + mirror). Fixed in HeroCharacter.LOD_SCHEDULE: the generated LODs get the old hero's switch sizes by triangle share (LODs: 16143, 8071, 3929, 959, 452, 192 triangles). Later runs differ only by other builders' concurrent changes (HIGH prims 369.5k -> 377.8k between my two last runs, limit 430k). APK effect (estimate from the import cache, no Android export here): repo +2.4 MB (hero_suit.glb 0.35, atlas albedo/normal/orm 0.83, 7 webp portraits 0.06, RGBA suit masks in the two rough maps ~+1) plus 3.9 MB of contact sheets (not in the APK). In an APK about +7.5 MB: hero textures re-imported VRAM compressed with mipmaps (skin colour ETC2/DXT1, 2K body normals limited to 1K, rest ASTC/BPTC) = 25 MB for the whole hero set vs ~18 MB lossless before (ASTC 4x4 everywhere would have been +26 MB; a 4x zoom of the face shows no visible loss, mean difference 0.09/255). WHITE RECTANGLES ON THE LEGS: a REAL defect. They were the procedural box gear (HeroCharacter._gear_boxes: pale bevelled boxes bound to calf/thigh bones that floated off the legs when running, visible in owner round 5 and in my BEFORE renders). Replaced by the suit kit; _gear_piece stays only as fallback when hero_suit.glb is absent. Test checks the atlas under every kit vertex for black/white texels (none). WHAT WAS BUILT - Kit ...

## Last notes of the agent

- 15:20:56 Now the Blender side. First the body loader + conformal fitting helpers; I'll test them on a first part before building the whole kit.
- 15:31:58 Now the shader. I need to keep the legacy jacket/pants path byte-identical for NPCs and enemies (they share this shader) and add the new hero style next to it.
- 15:32:55 Now the PlayerBody integration (glow object, registration, per-frame update, event hooks, palette).
- 15:38:32 Now the body surgery (gloves covered by the suit, feet cut under the boots, hands/eyes/brows decimated) in HeroCharacter.
- 17:01:54 Now let me write the test.
- 18:20:12 Now let me review the main before/after contact sheet as a self-review.

## Recent steps (last 40)

- 18:44:25 Sum the mobile-format imported sizes of all hero textures
- 18:44:43 Check how the LOW tier halving handles VRAM compressed textures
- 18:44:45 Read halve_texture and _low_tex
- 18:44:55 Read the hero import patch tool
- 18:45:05 Cut the hero body textures: skin colour in DXT1/ETC2 and normals at 1K, then re-import
- 18:45:44 Compare head and bust renders before and after the texture size cuts
- 18:46:03 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/imp/zoom.png
- 18:46:11 Compute the hero asset weight in an APK after the texture cuts
- 18:46:15 Re-run the hero tests after the texture import changes
- 18:47:42 Review the diff stats of all shared files I touched
- 18:47:53 Remember failed portrait captures so they are not retried every frame
- 18:48:01 Check for stray bytecode caches and untracked tool files
- 18:48:03 Final perf gate for LOW, MED and HIGH after the texture cuts
- 18:54:32 Re-read the end of HANDOFF.md right before appending
- 18:54:56 Compare the hero's cast shadow with the default proxy LOD and with full LOD
- 18:55:23 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/shadow/cmp.png
- 18:55:30 Read the cape construction code
- 18:55:40 Slant the cape hem and rebake the kit, then render the shadow and back views
- 18:56:30 Crop the new shadow and back view
- 18:56:32 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/shadow/n_cmp.png
- 18:56:46 Re-bake portraits and re-render turntable, suits, glide and far views with the new cape
- 19:00:21 Re-run the real-game bot phases for the final frames
- 19:05:29 Finish the variant renders and rebuild all hero contact sheets
- 19:06:27 Refresh the portrait sheet from the final baked portraits
- 19:06:30 /home/user/QUANTUM_Teleportar/docs/shots/round6/hero_suits_six.jpg
- 19:06:40 Read the flight set extras (wing mounts)
- 19:06:55 Shorten the flight wing panels, retune the gilded gold, rebake and render both
- 19:08:01 /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad/it/sheet.png
- 19:08:08 Refresh portraits, flight/gilded renders and the two bot frames after the final kit change
- 19:12:21 Rebuild all contact sheets after the final kit change
- 19:12:24 /home/user/QUANTUM_Teleportar/docs/shots/round6/hero_action.jpg
- 19:12:24 /home/user/QUANTUM_Teleportar/docs/shots/round6/hero_customisation.jpg
- 19:12:30 Re-run the hero, UI and demo tests after the final kit changes
- 19:16:16 Final perf gate for all three tiers on the shared tree after the last kit change
- 19:22:56 Append the wave 112 hero look v3 section to HANDOFF.md
- 19:23:07 Add the later iterations to the iteration notes
- 19:23:13 Delete my scratch render directories and files
- 19:23:26 /home/user/QUANTUM_Teleportar/docs/sprint/progress/w112-hero-look.md
- 19:23:31 Final sanity: debug leftovers, parse errors and my untracked files
- 19:24:15 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- godot/scripts/player/hero_look.gd
- godot/scripts/characters/hero_portrait.gd
- docs/sprint/progress/w112-hero-look.md
- godot/tests/test_hero_look_v3.gd
- docs/shots/round6/hero_iterations.md
