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
| Draw calls | at most 150 | at most 300 |
| Visible triangles | at most 300 k | at most 800 k |
| Texture memory | at most 600 MB | at most 1.2 GB |
| RAM | at most 1.5 GB | at most 3 GB |
| Per-frame allocations | none in hot paths (pool nodes, reuse vectors) | same |

LOW tier: render scale 0.7, no shadows, 1K textures, reduced particles. Dynamic resolution is a later task.
The Mobile renderer is primary; Compatibility is the automatic fallback for devices without Vulkan 1.1 / Metal support.
