# Weapon pictures, screens and sound: render-look-fix loops (wave 114, builder w114-weapons-ui)

Frames come from `tests/bot_arsenal.gd` (`ARS_STEPS=loadout,parts,reveal_mid,hud_plate,wheel_classes,crate_pics,...`, real game, real camera, `BOT_RES=2400x1080` and `1688x780`
= the 844x390 phone aspect, `QUALITY=0`, `tools/bot.sh`) and from the picture renderer (`tools/icons/weapon_pics.sh`, sheet `weapon_atlas.py --sheet`). Every loop: render, open the
image, name the defect, fix it, render again. Sheets: `weapons_ui_*.jpg` in this folder.

1. Pictures, first render: the rim light was too weak, the weapon read as one grey slab. Key / fill / class-tinted rim energies raised (key 2.9, fill 0.75, rim 7.0, second rim 3.5), the sky
   became a studio panorama. Pages were 22 MB of PNG: tight crop + shelf packing + WebP q90 made them 6 MB (7.5 MB deflated as ETC2 in the APK).
2. First Arsenal frames (list, card, bars): the catalogue selection jumped back to the first weapon on every layout (a stale `ensure_sel()`), the compare numbers glided and the text scan
   saw two overlapping numbers (the number shown is the weapon's, the bar glides).
3. Squeezed aspect (a tall harness window): buttons under 64 px and off screen. Minimum widths for every chip and a floor for the squeeze (`k` >= 0.5); tests now set the window to a real size.
4. PARTS and AMMO tabs: a tap previews a part with the numbers it changes (before > after, percentage), the action button FIT / TAKE OFF / BUY applies; the 3D weapon is on show on this tab.
5. Rings to scale: blast dome with its core beside a 1.8 m person, the group at 20 m, the range ruler, melee reach.
6. Plate size (this session): the picture plate was 206 base px tall, an old test (and the owner) want a big picture, 480 x 240 or more: 240 px now, the bar rows and the three lines under
   them (VS IN HAND, MAG / RELOAD, WHERE) were re-fitted; an owned weapon prints WHERE too. The delta "-4" touched "496 RPM": the value column got 8 px more.
7. Reveal: the first frame showed NOTHING (an overlay made in `_ready` with `set_anchors_preset` had size 0 under a CanvasLayer: `set_anchors_and_offsets_preset`), then the weapon name
   sat on top of the three stat chips (card 320 -> 366 base px). Flash, middle and late frames checked.
8. HUD plates and the weapon wheel: the weapon picture on the weapon pop plate was hidden under the plate (the plate fill is queued, the picture was drawn at once: `Hud._weapon_pic`
   queues it), and the wheel discs of PISTOL, SMG and RIFLE and the kill feed showed WHITE boxes: the atlas page cache held 7 pages and the wheel draws one weapon of each of the 10
   classes (100 page loads in a few frames, evicted pages under queued draws). Thumb pages (about 7 MB for all 10) stay loaded, only the card pages are an LRU of 5; the test
   `test_weapon_pics` now loads a wheel's worth of thumbs and expects no more loads.
9. Crate pictures: a 1.6 m billboard is a speck from 20 m: it grows with the distance (`pixel_size` 0.0055 .. 0.0125).
Open after the last loop: the kill feed's third line can touch the objective text at the top (long weapon names), an old layout; the pictures of weapons follow the models of the art builder.
