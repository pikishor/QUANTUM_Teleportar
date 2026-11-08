Universal Animation Library (Standard, 45 clips) and Universal Animation Library 2 (Standard, 43 clips) by Quaternius, CC0 1.0 (License_UAL1.txt, License_UAL2.txt as shipped in the zips).

Fetched with plain curl and a descriptive user agent (CC0 listings on OpenGameArt; the itch.io and Google Drive mirrors are blocked in the sandbox):
- https://opengameart.org/content/universal-animation-library  ->  https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip  (14.5 MB, Godot/AnimationLibrary_Godot_Standard.glb, 53-bone Blender 'DEF-' humanoid)
- https://opengameart.org/content/universal-animation-library-2  ->  https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip  (10.3 MB, Unreal-Godot/UAL2_Standard.glb, 65-bone UE humanoid = the hero's skeleton)
- Project pages: https://quaternius.com/packs/universalanimationlibrary.html (the paid Source / Pro versions with 120+ clips are NOT used)

The raw zips (24 MB) are not committed. `godot/tools/hero/clips.sh` downloads them again, retargets 14 clips (idle, ready (pistol idle), walk, jog, sprint, crouch idle / walk, jump start / loop / land, three aim poses, walk carry)
onto the hero skeleton (godot/tools/hero/build_clips.py: same UE rest orientations, global-delta retarget, hero leg lengths, floor-corrected pelvis, loops re-timed to the left heel strike, ground speed per clip
from the foot contacts) and bakes godot/assets/anim/hero_clips.res (115 KB) with godot/tools/hero/bake_clips.gd. Credit is in docs/THIRD_PARTY.md.
