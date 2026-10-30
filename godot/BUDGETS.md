# Mobile budgets (v1.0 target)

This is a **mobile-first** game. Size and performance are product requirements, not afterthoughts.

## Install size: ≤ 1 GB
- **Total install ≤ 1 GB.** Aim for a base package ≤ 200 MB (Google Play's base-download limit) with the rest delivered as asset packs
  (Play Asset Delivery on Android; On-Demand Resources on iOS). Check the stores' current rules before launch.
- Rough allocation of the 1 GB: engine/runtime 60–100 MB · textures ~450 MB · meshes + animation ~150 MB · audio ~150 MB · data/other ~50 MB · headroom ~100 MB.
- Size is a **ceiling, not a target**. What fills it is content: generated assets will use tens of MB; the rest needs art/audio from artists or licensed packs.
- Formats: textures ASTC (project already enables ETC2/ASTC import), 1K for most surfaces, 2K only for hero assets; audio OGG Vorbis/Opus, music streamed;
  meshes with LODs; glTF/GLB with unused data stripped.
- `tools/size_report.sh [budget_mb]` reports the biggest files and the total, and fails when over budget.

## Runtime
| Budget | Target |
|---|---|
| Frame rate | 60 fps on mid-range phones (~2021 Snapdragon 7-series / Apple A13), graceful 30 fps fallback |
| Draw calls | ≤ 150 per frame (MultiMesh/instancing, merged meshes) |
| Visible triangles | ≤ 300 k |
| Texture memory | ≤ 400 MB |
| RAM | ≤ 1.5 GB |
| Per-frame allocations | none in hot paths (pool nodes, reuse vectors) |
| Quality tiers | LOW / MEDIUM / HIGH change render scale, MSAA, shadows; later dynamic resolution |

The GL Compatibility renderer was chosen for the widest phone support; revisit the Mobile (Vulkan/Metal) renderer once it can be tested on real devices.
