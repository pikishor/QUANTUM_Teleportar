# Mobile budgets (v1.0 target)

This is a **mobile-first** game that aims for a premium, console-adjacent look. Size and performance are product requirements.

## Install size: up to 5 GB
- **Total install up to 5 GB.** Delivery plan: (1) a **base package of at most about 200 MB** (engine, code, UI, first-mission content);
  (2) store-native asset packs: Play Asset Delivery on Android and On-Demand Resources on iOS; (3) anything beyond the stores' native limits is an in-game
  download from our own CDN (hosting cost and a downloader UI). Store limits change: verify the current Google Play and Apple rules before launch
  (Play currently caps each asset pack at about 1 GB and the total at about 4 GB).
- Rough allocation of 5 GB: textures (PBR, 2K-4K ASTC) about 2.2 GB, meshes and animation 0.8 GB, audio (SFX, music, voice-over) 0.9 GB,
  cutscene video 0.6 GB, levels and data 0.2 GB, engine runtime 0.1 GB, headroom 0.2 GB.
- Size is a **ceiling, not a target**. Generated assets will use only tens to a few hundred MB; the rest needs artists, voice actors and composers (or licensed packs).
- Formats: textures ASTC (project enables ETC2/ASTC import), 2K for most surfaces, 4K only for hero assets, mip limits per quality tier;
  audio OGG Vorbis/Opus with music streamed; meshes with LODs; glTF/GLB with unused data stripped; cutscenes as compressed video.
- `tools/size_report.sh [budget_mb]` reports the biggest files and the total (default 5120) and fails when over budget.

## Runtime (per quality tier)
| Budget | Mid-range phone (MED) | Flagship (HIGH) |
|---|---|---|
| Frame rate | 60 fps target, graceful 30 fps fallback | 60 fps (90/120 where the display allows) |
| Draw calls (whole frame incl. shadow passes and canvas) | at most 140 (LOW 100) | at most 160 |
| Triangles (whole frame incl. shadow passes) | at most 280 k (LOW 160 k; restored to 280 k by shadow range LOD) | at most 430 k |
| Texture memory | gate 260 MB staged scene (staged scene today 201 MB incl. about 13 MB of surface sets; hard ceiling 600 MB) | gate 360 MB (302 MB today; ceiling 1.2 GB) |
| RAM | at most 1.5 GB | at most 3 GB |
| Per-frame allocations | none in hot paths (pool nodes, reuse vectors) | same |

Measured and gated by `tools/perf_report.sh` (`PERF_CHECK=1`, budgets in `scripts/common/perf_probe.gd`): staged full-game view = hero, 4 enemies, the starter car, HUD; the 4-enemy simultaneous death stays under 150 draws (LOW 115, HIGH 180); the touch layout adds at most 15 canvas draws; the Compatibility fallback gets +20 draws of headroom and 25 % smaller pools.

LOW tier: render scale 0.7, no shadows, 1K textures, no surface texture taps (procedural look, gate 200 MB, 153 MB today), reduced particles. Dynamic resolution is a later task.
The Mobile renderer is primary; Compatibility is the automatic fallback for devices without Vulkan 1.1 / Metal support.

## Phone profiling and render defaults (benchmark wave)
- FPS readout: hidden by default; long-press its corner (under the minimap) shows it, long-press again opens the report panel (SEND REPORT, 64 px: clipboard + `user://perf_report.txt`), once more hides both.
- OPTIONS > RUN BENCHMARK (`scripts/common/benchmark_run.gd`): 30 s fixed 400 m road route, 7.5 s each on LOW+, LOW, MED, HIGH; result block (min / avg / p95 FPS = 1000 / worst frame, frames / s, 1000 / 95th percentile frame; draws, tris, render CPU / GPU ms, device, GPU, renderer, resolution, temperature) in `user://benchmark.txt`, the clipboard, the perf log and a result panel. Test: `tests/test_benchmark_mode.gd`.
- Perf log (`user://perf_log.txt`) samples carry per-system ms (script, physics, render CPU / GPU while measuring), temperature, tier and resolution changes. Battery and temperature come from /sys where the OS allows the read (Godot 4 has no API): "n/a" otherwise.
- Safe low-end defaults (project.godot): Vulkan Mobile with OpenGL fallback, MSAA 2D/3D off, no screen-space AA / TAA, roughness limiter off, sun shadow map 1024 (the world raises it per tier), positional atlas 1024 (LOW 512), 16-bit shadow depth, positional shadow filter hard, anisotropy 2x (PerfTiers sets 2x / 4x / 8x per tier), sky reflections 6 layers / 16 samples. PerfTiers also turns debanding off on LOW and LOW+.

## LOW+ (the tier below LOW) and CPU time
- LOW+ = quality 0 plus `Game.low_plus` (`scripts/common/low_plus.gd`, test `tests/test_low_plus.gd`): 3D scale 0.55 with bilinear (no FSR pass), no shadows / bloom / colour adjustment / height fog / MSAA / reflection, material v2 and the quantum surface layer off, the lean facade shader on every building, enemies 3, cars 2, crowd, traffic, flocks and particles at about half of LOW, no model lights (pickups, car underglow), physics 30 Hz with at most 2 catch-up ticks, HUD and touch layer redraw 12 Hz (LOW 20 Hz), minimap 7.5 Hz. Same textures as LOW (never more memory). Gate (`tools/perf_report.sh lp`): at most 95 draws, 140k triangles, 105 draws in the death spike, texture memory under LOW's 200 MB (measured 90 draws / 116k tris / 152 MB).
- Entry: the governor steps LOW -> LOW+ after 5 s under 30 FPS (never saved), a touchscreen with a weak GPU (`LowPlus.weak_gpu`: old Mali, Adreno 3xx-6xx low end, PowerVR, Vivante) starts on LOW+ until the player chooses, and OPTIONS > GRAPHICS / the title buttons cycle LOW+ LOW MED HIGH.
- CPU: frame time is not only draws and triangles. `PerfTimers` (`scripts/common/perf_timers.gd`) times 17 systems (HUD, screens, minimap, touch layer, crowd, NPC, citizens, fauna, sky, enemy AI, enemy manager, vehicles, player, effects, world, missions, audio) in ms per frame, exposed as Performance monitors `quantum/<id>_ms`, in the PerfOverlay report and SAMPLE log lines, in the debug box and in `tools/perf_report.sh`; `tools/cpu_frame.sh` measures the CPU frame headless. Largest wins of this wave: `DisplayServer` window / safe-area queries were made dozens of times per frame by the HUD and touch layer (a per-button query; cached 20 frames, `UiUtil`), the HUD / touch layer / minimap no longer redraw every frame on LOW, button labels are measured once.
