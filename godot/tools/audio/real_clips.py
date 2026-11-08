#!/usr/bin/env python3
"""Open-source (CC0) sound clips used by the game, the list of packs they come from and the harvest step that cuts them out of the downloaded packs.

Round 4: the synthesised weapon, impact, footstep, vehicle, UI and ambience sounds were replaced by real recordings (all CC0, see docs/AUDIO_SOURCES.md). The packs are big and
mostly unused, so the repo keeps only what the game uses: each clip is cut once (this script), converted to a mono 44.1 kHz OGG (q6, peak at -1 dBFS) and committed under
art_sources/audio_<group>/clips/<clip id>.ogg together with the pack's licence text and a SOURCE.md. tools/audio/make_real.py builds the final game files from those clips
(layering our own sub-bass and tail under the real transient where useful) and runs in tools/build_assets.sh; it does not need the raw packs.

Harvest (only when a clip is added or changed; needs numpy and ffmpeg, plus py7zr for the .7z packs):
  1. download the packs (page URLs in GROUPS) into one folder, unpack, keep the layout listed in the `src` column of CLIPS (relative to that folder)
  2. python3 tools/audio/real_clips.py <raw folder>
"""
import os
import subprocess
import sys

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ART = os.path.abspath(os.path.join(ROOT, "..", "art_sources"))

OGA = "https://opengameart.org/content/"
CC0 = "CC0 1.0 (public domain dedication)"

# group id -> title, author, page URLs (one per pack), licence, note. The committed folder is art_sources/audio_<group>/.
GROUPS = {
    "firearm_library": dict(title="The Free Firearm Sound Library (Prepared SFX Library)", author="The Free Firearm Sound Library team (college students, Kickstarter 2013), uploaded by Ylmir", license=CC0,
                            pages=[OGA + "the-free-firearm-sound-library"], note="CC0 'no rights reserved' statement on the page; 96 kHz 24-bit stereo field recordings of 23 real firearms, near and mid distance."),
    "gunshot_singles": dict(title="Gunshots (LarkPay), Gunshot Sounds (Raassh), Hollywood-style pistol silencer (bart), Laser weapon burst fire (number99), Gun reload sounds (Joaken), "
                            "Gun Reload Sound Effects (Brian MacIntosh), 2 Gun Reloads (starninjas), Shotgun Reload Sound effects, Equipment Clicks II",
                            author="LarkPay, Raassh, bart, number99, Joaken, Brian MacIntosh, starninjas, anonymous uploaders (OpenGameArt)", license=CC0,
                            pages=[OGA + s for s in ("gunshots", "gunshot-sounds", "hollywood-style-pistol-silencer-sound-effect", "laser-weapon-burst-fire", "gun-reload-sounds", "gun-reload-sound-effects",
                                                    "2-gun-reloads", "shotgun-reload-sound-effects", "equipment-clicks-ii")], note="each page declares CC0"),
    "explosion_singles": dict(title="Explosion (number99), Chunky Explosion (looneybits), Muffled Distant Explosion (NenadSimic via Cokabear), Explosion somewhere far (ripple182), 25 CC0 bang / firework SFX (Snabisch)",
                              author="number99, looneybits, NenadSimic (uploaded by Cokabear), ripple182, Snabisch", license=CC0,
                              pages=[OGA + s for s in ("explosion-0", "chunky-explosion", "muffled-distant-explosion", "explosion-somewhere-far", "25-cc0-bang-firework-sfx")], note="each page declares CC0"),
    "breaking_falling_75": dict(title="75 CC0 breaking / falling / hit sfx", author="frances (OpenGameArt)", license=CC0, pages=[OGA + "75-cc0-breaking-falling-hit-sfx"], note="CC0"),
    "impact_punch": dict(title="Impact and Punch (Lips of Suna audio tasks), Metal Impact Sounds, Crash Collision, Glass Break", author="qubodup (artificialintelligence / looneybits uploads), Brian MacIntosh (Hazmat Harry), Luca Pixel, anonymous",
                         license=CC0, pages=[OGA + s for s in ("impact", "punch", "metal-impact-sounds", "crash-collision", "glass-break")], note="each page declares CC0 (the metal impacts page asks for optional credit: Brian MacIntosh)"),
    "kenney_scifi": dict(title="Sci-Fi Sounds (Kenney)", author="Kenney (kenney.nl), re-uploaded to OpenGameArt by FiveBrosStopMosYT", license=CC0, pages=[OGA + "sci-fi-sounds"], note="License.txt of the pack: CC0 1.0 Universal"),
    "kenney_interface": dict(title="Interface Sounds (Kenney)", author="Kenney (kenney.nl), uploaded to OpenGameArt by MedicineStorm", license=CC0, pages=[OGA + "interface-sounds"], note="License.txt of the pack: CC0 1.0 Universal"),
    "scifi_number99": dict(title="50 CC0 Sci-Fi SFX and 60 CC0 Sci-Fi SFX", author="VividLegends / number99 (OpenGameArt)", license=CC0, pages=[OGA + "50-cc0-sci-fi-sfx", OGA + "60-cc0-sci-fi-sfx"], note="CC0"),
    "cc0_100": dict(title="100 CC0 SFX, 100 CC0 SFX #2, 30 CC0 SFX loops", author="rubberduck / aijikl, geekygnome (OpenGameArt)", license=CC0, pages=[OGA + "100-cc0-sfx", OGA + "100-cc0-sfx-2", OGA + "30-cc0-sfx-loops"], note="CC0"),
    "footsteps": dict(title="Fantozzi's Footsteps (stone, sand), Metal footsteps on concrete, Footsteps (subway), Different steps on wood, stone, leaves, gravel and mud",
                      author="Fantozzi (Freesound, via Raassh), anonymous uploader, anonymous uploader, qubodup", license=CC0,
                      pages=[OGA + s for s in ("fantozzis-footsteps-grasssand-stone", "metal-footsteps-on-concrete", "footsteps-0", "different-steps-on-wood-stone-leaves-gravel-and-mud")], note="each page declares CC0"),
    "vehicles": dict(title="racing car engine sound loops (qubodup), Car Sound Effects Pack, Car engine start 01, Car_door_SFX (MedicineStorm), Sci-Fi Vehicle Sound (qubodup)",
                     author="qubodup (engine loops cut from a public-domain pdsounds recording), anonymous uploaders, MedicineStorm", license=CC0,
                     pages=[OGA + s for s in ("racing-car-engine-sound-loops", "car-sound-effects-pack-low-quality", "car-engine-start-01", "cardoorsfx", "sci-fi-vehicle-sound")], note="each page declares CC0"),
    "swishes": dict(title="Swishes Sound Pack (qubodup), Air whoosh", author="qubodup, anonymous uploader", license=CC0, pages=[OGA + "swishes-sound-pack", OGA + "air-whoosh"], note="CC0"),
    "ui_sounds": dict(title="51 UI sound effects (gopherapps), 10 Clicks and Switches (PFNienow), UI Click Sounds Sci-Fi", author="gopherapps, PFNienow, anonymous uploader", license=CC0,
                      pages=[OGA + s for s in ("51-ui-sound-effects-buttons-switches-and-clicks", "10-clicks-and-switches", "ui-click-sounds-sci-fi")], note="each page declares CC0"),
    "ambience": dict(title="Rain (loopable) (Snabisch), High traffic road sounds (Snabisch), Scifi City Ambient Loop (2DPIXX), wind whoosh loop, windy ambient noise, AMB Rain Loop 1",
                     author="Snabisch, 2DPIXX, anonymous uploaders", license=CC0,
                     pages=[OGA + s for s in ("rain-loopable", "high-traffic-road-sounds", "scifi-city-ambient-loop", "wind-whoosh-loop", "windy-ambient-noise", "amb-rain-loop-1")], note="each page declares CC0"),
}

FL = "x_firearm_lib/Prepared SFX Library/"
K = "x_scifi_sounds/Audio/"
KI = "x_kenney_if/Audio/"
BF = "x_breaking_75/bfh1_"
C2 = "x_cc0_100v2/sfx100v2_"
QI = "x_qimpact/qubodupImpact/qubodupImpact"
QP = "x_qpunch/qubodupPunch/qubodupPunch"
FA = "x_fantozzi/Fantozzi-footsteps/ogg/Fantozzi-"
MS = "x_metal_steps/metal_steps_"

# clip id | group | src (under the raw folder) | spec. Specs: sN = the N-th gun shot / onset (cut from just before it to just before the next shot, at most 2.2 s; sNb = a round of an automatic burst, cut at the next round), wN = the whole file
# (trimmed, at most N seconds), l = a loop, the whole file untouched (stored as FLAC), a:b = seconds a to b.
CLIPS_TEXT = """
fl_ar15_near|firearm_library|FL+AR-15/D_32P.wav|s0
fl_ar15_mid|firearm_library|FL+AR-15/D_24P.wav|s0
fl_ak_near|firearm_library|FL+AK-47/C_28P.wav|s0
fl_ak_near2|firearm_library|FL+AK-47/C_28P.wav|s1
fl_ak_mid|firearm_library|FL+AK-47/C_31P.wav|s0
fl_sks_near|firearm_library|FL+SKS/U_14P.wav|s0
fl_savage_near|firearm_library|FL+Savage 10 .300 Blackout/T_27P.wav|s0
fl_1911_near|firearm_library|FL+1911/A_42P.wav|s0
fl_1911_mid|firearm_library|FL+1911/A_34P.wav|s0
fl_ppq_near|firearm_library|FL+Walther PPQ/X_39P.wav|s0
fl_bersa_near|firearm_library|FL+Bersa/F_47P.wav|s0
fl_sw642_near|firearm_library|FL+Smith & Wesson 642/V_27P.wav|s0
fl_ruger6_near|firearm_library|FL+Ruger Single Six/S_14P.wav|s0
fl_marlin_near|firearm_library|FL+Marlin 336/I_22P.wav|s0
fl_mosin_near|firearm_library|FL+Mosin Nagant/M_21P.wav|s0
fl_1917_near|firearm_library|FL+1917/B_24P.wav|s0
fl_mossberg_near|firearm_library|FL+Mossberg/N_30P.wav|s0
fl_mossberg_mid|firearm_library|FL+Mossberg/N_26P.wav|s0
fl_nova_near|firearm_library|FL+Nova/O_21P.wav|s0
fl_model12_near|firearm_library|FL+Model 12/K_22P.wav|s0
fl_ppsh_r0|firearm_library|FL+PPSh/P_34P.wav|s0b
fl_ppsh_r1|firearm_library|FL+PPSh/P_34P.wav|s1b
fl_ppsh_r2|firearm_library|FL+PPSh/P_34P.wav|s2b
fl_ppsh_r3|firearm_library|FL+PPSh/P_34P.wav|s3b
fl_cg_r0|firearm_library|FL+Carl Gustav M45/G_35P.wav|s0b
fl_cg_r1|firearm_library|FL+Carl Gustav M45/G_35P.wav|s1b
fl_cg_r2|firearm_library|FL+Carl Gustav M45/G_35P.wav|s2b
fl_cg_r3|firearm_library|FL+Carl Gustav M45/G_35P.wav|s3b
fl_cg_single|firearm_library|FL+Carl Gustav M45/G_31P.wav|s0
fl_ak_burst_mid|firearm_library|FL+AK-47/C_36P.wav|0.5:4.0
fl_ppsh_burst_mid|firearm_library|FL+PPSh/P_22P.wav|0.9:3.2
fl_ak_burst_mid2|firearm_library|FL+AK-47/C_34P.wav|0.4:4.5
lark_blackpowder|gunshot_singles|gunshots_larkpay/Black_Powder.wav|s0
silencer|gunshot_singles|silencer/silencer.wav|w1.4
reload_ar|gunshot_singles|reload/assaultriflereload1_0.wav|w1.6
reload_pistol|gunshot_singles|reload/gunreload1.wav|w1.6
reload_clip2|gunshot_singles|reload3/clipload2.wav|w0.4
reload_starninjas|gunshot_singles|x_reload2/gun_reload.2.ogg|w1.4
shotgun_cock|gunshot_singles|reload/shotguncock_0.wav|w0.6
equip_click_a|gunshot_singles|equip/equipmentclicks.wav|0.0:0.22
equip_click_b|gunshot_singles|equip/equipmentclicks.wav|0.9:1.1
kn_laser_s0|kenney_scifi|K+laserSmall_000.ogg|w0.5
kn_laser_s1|kenney_scifi|K+laserSmall_001.ogg|w0.5
kn_laser_s2|kenney_scifi|K+laserSmall_002.ogg|w0.5
kn_laser_s3|kenney_scifi|K+laserSmall_003.ogg|w0.5
kn_laser_l0|kenney_scifi|K+laserLarge_000.ogg|w0.8
kn_laser_l2|kenney_scifi|K+laserLarge_002.ogg|w0.8
kn_laser_l3|kenney_scifi|K+laserLarge_003.ogg|w0.8
kn_laser_r0|kenney_scifi|K+laserRetro_000.ogg|w0.4
kn_laser_r4|kenney_scifi|K+laserRetro_004.ogg|w0.4
kn_forcefield0|kenney_scifi|K+forceField_000.ogg|w1.0
kn_forcefield2|kenney_scifi|K+forceField_002.ogg|w1.0
kn_expl_crunch0|kenney_scifi|K+explosionCrunch_000.ogg|w1.0
kn_expl_crunch2|kenney_scifi|K+explosionCrunch_002.ogg|w1.4
kn_expl_crunch3|kenney_scifi|K+explosionCrunch_003.ogg|w1.8
kn_expl_crunch4|kenney_scifi|K+explosionCrunch_004.ogg|w2.2
kn_lowexpl0|kenney_scifi|K+lowFrequency_explosion_000.ogg|w2.2
kn_lowexpl1|kenney_scifi|K+lowFrequency_explosion_001.ogg|w1.2
kn_impact_metal4|kenney_scifi|K+impactMetal_004.ogg|w0.5
sf50_shoot1|scifi_number99|x_scifi_50/shoot_01.ogg|w0.3
sf50_shoot2|scifi_number99|x_scifi_50/shoot_02.ogg|w0.2
sf50_expl1|scifi_number99|x_scifi_50/explosion_01.ogg|w2.0
sf50_rocket|scifi_number99|x_scifi_50/rocket_01.ogg|w2.1
sf50_retro_laser1|scifi_number99|x_scifi_50/retro_laser_01.ogg|w0.6
sf60_21a|scifi_number99|x_scifi60/sfx_21a.ogg|w0.6
expl_n99|explosion_singles|explosion_n99/explosion.wav|w1.0
expl_chunky|explosion_singles|chunky/Chunky_Explosion.mp3|w3.5
expl_muffled|explosion_singles|muffled/NenadSimic_-_Muffled_Distant_Explosion.wav|w5.2
expl_far|explosion_singles|far/explosion_somewhere_far.mp3|w3.0
bang_01|explosion_singles|x_bang_25/bang_01.ogg|w1.2
bang_06|explosion_singles|x_bang_25/bang_06.ogg|w1.4
bang_cannon2|explosion_singles|x_bang_25/cannon_02.ogg|w1.8
bang_cannon4|explosion_singles|x_bang_25/cannon_04.ogg|w1.0
qi_meat1|impact_punch|QI+Meat01.ogg|w0.5
qi_meat2|impact_punch|QI+Meat02.ogg|w0.5
qi_stone|impact_punch|QI+Stone.ogg|w0.5
qi_metal|impact_punch|QI+Metal.ogg|w0.5
qp_punch1|impact_punch|QP+01.ogg|w0.5
qp_punch3|impact_punch|QP+03.ogg|w0.5
qp_punch4|impact_punch|QP+04.ogg|w0.5
qp_punch5|impact_punch|QP+05.ogg|w0.5
mi_bing|impact_punch|metal_impacts/bing1.wav|w0.8
mi_clink1|impact_punch|metal_impacts/clink1_0.wav|w0.4
mi_clink2|impact_punch|metal_impacts/clink2.wav|w0.4
mi_clink3|impact_punch|metal_impacts/clink3.wav|w0.4
mi_thud2|impact_punch|metal_impacts/thud2.wav|w0.6
mi_thud3|impact_punch|metal_impacts/thud3.wav|w0.5
crash_qubodup|impact_punch|crash/qubodup-crash.ogg|w0.7
glass_break|impact_punch|glassbreak/glass_breaking.wav|w1.4
br_hit12|breaking_falling_75|BF+hit_12.ogg|w0.5
br_glass_b01|breaking_falling_75|BF+glass_breaking_01.ogg|w0.8
br_glass_b02|breaking_falling_75|BF+glass_breaking_02.ogg|w0.5
br_glass_h02|breaking_falling_75|BF+glass_hit_02.ogg|w0.35
br_metal_h02|breaking_falling_75|BF+metal_hit_02.ogg|w0.6
br_metal_h03|breaking_falling_75|BF+metal_hit_03.ogg|w0.5
br_metal_h04|breaking_falling_75|BF+metal_hit_04.ogg|w0.5
br_metal_f01|breaking_falling_75|BF+metal_falling_01.ogg|w1.2
br_rock_h01|breaking_falling_75|BF+rock_hit_01.ogg|w0.2
br_rock_b01|breaking_falling_75|BF+rock_breaking_01.ogg|w1.2
br_rock_f09|breaking_falling_75|BF+rock_falling_09.ogg|w0.7
br_fall04|breaking_falling_75|BF+falling_04.ogg|w1.5
c2_stones1|cc0_100|C2+stones_01.ogg|w0.5
c2_stones2|cc0_100|C2+stones_02.ogg|w0.6
c2_stones3|cc0_100|C2+stones_03.ogg|w0.55
c2_metal_h1|cc0_100|C2+metal_hit_01.ogg|w0.8
c2_glass1|cc0_100|C2+glass_01.ogg|w0.4
c2_glass3|cc0_100|C2+glass_03.ogg|w0.65
c2_glass6|cc0_100|C2+glass_06.ogg|w0.4
c2_slam|cc0_100|x_cc0_100/slam_02.ogg|w0.65
st_stone_l1|footsteps|FA+StoneL1.ogg|w0.4
st_stone_l2|footsteps|FA+StoneL2.ogg|w0.35
st_stone_l3|footsteps|FA+StoneL3.ogg|w0.35
st_stone_r1|footsteps|FA+StoneR1.ogg|w0.4
st_stone_r2|footsteps|FA+StoneR2.ogg|w0.35
st_stone_r3|footsteps|FA+StoneR3.ogg|w0.35
st_sand_l1|footsteps|FA+SandL1.ogg|w0.45
st_sand_l2|footsteps|FA+SandL2.ogg|w0.35
st_sand_r1|footsteps|FA+SandR1.ogg|w0.45
st_sand_r2|footsteps|FA+SandR2.ogg|w0.35
st_metal_01|footsteps|MS+01.wav|w0.3
st_metal_03|footsteps|MS+03.wav|w0.3
st_metal_05|footsteps|MS+05.wav|w0.3
st_metal_07|footsteps|MS+07.wav|w0.3
st_metal_09|footsteps|MS+09.wav|w0.3
st_metal_11|footsteps|MS+11.wav|w0.3
st_metal_13|footsteps|MS+13.wav|w0.3
st_metal_15|footsteps|MS+15.wav|w0.3
st_metal_17|footsteps|MS+17.wav|w0.3
st_metal_21|footsteps|MS+21.wav|w0.3
st_metal_25|footsteps|MS+25.wav|w0.35
st_sub_1|footsteps|footsteps_0/01-footstep_0.ogg|w0.3
st_sub_2|footsteps|footsteps_0/02-footstep.ogg|w0.3
st_sub_3|footsteps|footsteps_0/03-footstep.ogg|w0.4
st_sub_4|footsteps|footsteps_0/04-footstep.ogg|w0.4
st_wood1|footsteps|x_diffsteps/wood01.ogg|w0.3
st_wood2|footsteps|x_diffsteps/wood02.ogg|w0.3
st_wood3|footsteps|x_diffsteps/wood03.ogg|w0.35
st_stone01|footsteps|x_diffsteps/stone01.ogg|w0.35
st_gravel|footsteps|x_diffsteps/gravel.ogg|w0.75
st_c2_01|cc0_100|C2+footstep_01.ogg|w0.45
st_c2_02|cc0_100|C2+footstep_02.ogg|w0.4
st_c2_wood1|cc0_100|C2+footstep_wood_01.ogg|w0.3
st_c2_wood3|cc0_100|C2+footstep_wood_03.ogg|w0.3
st_c2_wood4|cc0_100|C2+footstep_wood_04.ogg|w0.4
veh_loop0|vehicles|carloops/loop_0.wav|l
veh_loop1|vehicles|carloops/loop_1_0.wav|l
veh_loop3|vehicles|carloops/loop_3_0.wav|l
veh_loop5|vehicles|carloops/loop_5_0.wav|l
veh_start1|vehicles|carstart/generic_car_startengine.wav|w1.8
veh_start2|vehicles|x_carsfx/Car_Engine_Start_Up.ogg|w2.0
veh_horn|vehicles|x_carsfx/Car_Horn.ogg|w0.6
veh_door_close|vehicles|cardoor/door_closing.wav|w0.8
veh_door_close2|vehicles|x_carsfx/Car_Door_Close.ogg|w0.7
sw_1|swishes|x_swishes/swishes/swish-3.wav|w0.2
sw_2|swishes|x_swishes/swishes/swish-4.wav|w0.2
sw_3|swishes|x_swishes/swishes/swish-7.wav|w0.25
sw_4|swishes|x_swishes/swishes/swish-9.wav|w0.25
sw_5|swishes|x_swishes/swishes/swish-12.wav|w0.1
sw_7|swishes|x_swishes/swishes/swish-1.wav|w0.15
ui_click2|ui_sounds|x_ui51/click2.wav|w0.3
ki_click3|kenney_interface|KI+click_003.ogg|w0.3
ki_tick2|kenney_interface|KI+tick_002.ogg|w0.2
ki_tick4|kenney_interface|KI+tick_004.ogg|w0.2
ki_select3|kenney_interface|KI+select_003.ogg|w0.4
ki_confirm3|kenney_interface|KI+confirmation_003.ogg|w0.6
ki_confirm4|kenney_interface|KI+confirmation_004.ogg|w0.6
ki_back2|kenney_interface|KI+back_002.ogg|w0.4
ki_error2|kenney_interface|KI+error_002.ogg|w0.5
ki_error4|kenney_interface|KI+error_004.ogg|w0.5
ki_toggle3|kenney_interface|KI+toggle_003.ogg|w0.3
ki_scroll1|kenney_interface|KI+scroll_001.ogg|w0.4
ki_bong1|kenney_interface|KI+bong_001.ogg|w0.8
ki_question1|kenney_interface|KI+question_001.ogg|w0.6
ki_glass1|kenney_interface|KI+glass_001.ogg|w0.8
ki_drop4|kenney_interface|KI+drop_004.ogg|w0.4
ki_maximize5|kenney_interface|KI+maximize_005.ogg|w0.5
ki_minimize6|kenney_interface|KI+minimize_006.ogg|w0.5
sf_term09|scifi_number99|x_scifi_50/terminal_09.ogg|w0.35
amb_rain_a|ambience|x_rain1/1.ogg|1.0:26.5
amb_rain_b|ambience|x_rain1/2.ogg|1.0:25.5
amb_rain_c|ambience|x_rain1/4.ogg|2.0:27.0
amb_traffic|ambience|traffic/gatve_Varniu_2.ogg|8.0:33.0
amb_wind|ambience|windy/windy_ambiance_0.ogg|30.0:55.0
amb_city|ambience|cyber/busy_cyberworld.ogg|2.0:27.0
"""


def parse_clips():
    pre = {"FL": FL, "K": K, "KI": KI, "BF": BF, "C2": C2, "QI": QI, "QP": QP, "FA": FA, "MS": MS}
    out = {}
    for line in CLIPS_TEXT.strip().splitlines():
        cid, grp, src, spec = line.split("|")
        if "+" in src and src.split("+", 1)[0] in pre:
            p, rest = src.split("+", 1)
            src = pre[p] + rest
        out[cid] = dict(group=grp, src=src, spec=spec)
    return out


CLIPS = parse_clips()


# top-level folder of a clip's source -> (OpenGameArt page slug, author as credited on the page, original pack file naming note)
SRC_META = {
    "x_firearm_lib": ("the-free-firearm-sound-library", "The Free Firearm Sound Library team (uploaded by Ylmir)"),
    "gunshots_larkpay": ("gunshots", "LarkPay"), "x_gunshot_sounds_raassh": ("gunshot-sounds", "Raassh"),
    "silencer": ("hollywood-style-pistol-silencer-sound-effect", "bart (uploader)"), "laserburst": ("laser-weapon-burst-fire", "number99"),
    "reload": ("gun-reload-sounds", "Joaken"), "reload3": ("gun-reload-sound-effects", "Brian MacIntosh"), "x_reload2": ("2-gun-reloads", "starninjas"),
    "x_shotgun_reload": ("shotgun-reload-sound-effects", "uploader not named on the page"), "equip": ("equipment-clicks-ii", "anonymous uploader"),
    "x_scifi_sounds": ("sci-fi-sounds", "Kenney (kenney.nl), re-uploaded by FiveBrosStopMosYT"), "x_kenney_if": ("interface-sounds", "Kenney (kenney.nl), uploaded by MedicineStorm"),
    "x_scifi_50": ("50-cc0-sci-fi-sfx", "number99"), "x_scifi60": ("60-cc0-sci-fi-sfx", "number99"),
    "explosion_n99": ("explosion-0", "number99"), "chunky": ("chunky-explosion", "looneybits"), "muffled": ("muffled-distant-explosion", "NenadSimic (uploaded by Cokabear)"),
    "far": ("explosion-somewhere-far", "ripple182"), "x_bang_25": ("25-cc0-bang-firework-sfx", "Snabisch"), "x_breaking_75": ("75-cc0-breaking-falling-hit-sfx", "frances"),
    "x_qimpact": ("impact", "qubodup (pack uploaded as artificialintel...)"), "x_qpunch": ("punch", "qubodup (pack uploaded by looneybits)"),
    "metal_impacts": ("metal-impact-sounds", "Brian MacIntosh (Hazmat Harry)"), "crash": ("crash-collision", "Luca Pixel"), "glassbreak": ("glass-break", "anonymous uploader (made for Duckstruction)"),
    "x_cc0_100": ("100-cc0-sfx", "aijikl"), "x_cc0_100v2": ("100-cc0-sfx-2", "geekygnome"),
    "x_fantozzi": ("fantozzis-footsteps-grasssand-stone", "Fantozzi (Freesound), uploaded by Raassh"), "x_metal_steps": ("metal-footsteps-on-concrete", "anonymous uploader"),
    "footsteps_0": ("footsteps-0", "anonymous uploader"), "x_diffsteps": ("different-steps-on-wood-stone-leaves-gravel-and-mud", "qubodup"),
    "carloops": ("racing-car-engine-sound-loops", "qubodup"), "carstart": ("car-engine-start-01", "uploader not named on the page"), "x_carsfx": ("car-sound-effects-pack-low-quality", "anonymous uploader"),
    "cardoor": ("cardoorsfx", "MedicineStorm"), "scifivehicle": ("sci-fi-vehicle-sound", "qubodup"), "x_swishes": ("swishes-sound-pack", "qubodup"),
    "x_ui51": ("51-ui-sound-effects-buttons-switches-and-clicks", "gopherapps"), "x_rain1": ("rain-loopable", "Snabisch"), "traffic": ("high-traffic-road-sounds", "Snabisch"),
    "windy": ("windy-ambient-noise", "anonymous uploader"), "windwhoosh": ("wind-whoosh-loop", "anonymous uploader"), "cyber": ("scifi-city-ambient-loop", "2DPIXX"),
}


def clip_meta(cid):
    """(page URL, author, original file name inside the pack) of a clip."""
    src = CLIPS[cid]["src"]
    top = src.split("/")[0]
    slug, author = SRC_META[top]
    return OGA + slug, author, src.split("/", 1)[1]


def clip_path(cid):
    ext = "flac" if CLIPS[cid]["spec"] == "l" else "ogg"           # loops stay lossless: Vorbis priming at the ends would break the seam
    return os.path.join(ART, "audio_" + CLIPS[cid]["group"], "clips", cid + "." + ext)


def load_audio(path):
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True, check=True)
    return np.frombuffer(r.stdout, "<f4").astype(np.float64)


def load_clip(cid):
    """A committed clip (mono, 44.1 kHz, peak about -1 dBFS) as float64."""
    return load_audio(clip_path(cid))


def onsets(x, rel=0.25, quiet_ms=120, hop=44):
    n = len(x) // hop
    env = np.sqrt((x[:n * hop].reshape(n, hop) ** 2).mean(1))
    thr = env.max() * rel
    out = []
    i, last = 0, -10 ** 9
    while i < n:
        if env[i] > thr and i - last > quiet_ms * SR / 1000 / hop:
            seg = np.abs(x[i * hop:(i + 4) * hop + 1])
            j = int(np.argmax(seg > seg.max() * 0.2))
            out.append(i * hop + j)
            while i < n and env[i] > thr * 0.3:
                i += 1
            last = i
            continue
        i += 1
    return out


def cut(x, spec):
    if spec[0] == "s":
        burst = spec.endswith("b")                       # a round of an automatic burst: cut at the next round; a single shot ignores echoes closer than 0.5 s
        k = int(spec[1:].rstrip("b"))
        on = onsets(x)
        a = max(0, on[k] - int(0.003 * SR))
        b = min(len(x), a + int(2.2 * SR))
        nxt = [o for o in on[k + 1:] if burst or o - on[k] > 0.5 * SR]
        if nxt:
            b = min(b, nxt[0] - int(0.004 * SR))
        y = x[a:b]
    elif spec == "l":
        y = x                                                         # a loop: the whole file, untouched
    elif spec[0] == "w":
        y = x[:int(float(spec[1:]) * SR)]
        pk = np.max(np.abs(y)) + 1e-12
        idx = np.nonzero(np.abs(y) > pk * 10 ** (-55 / 20))[0]
        if len(idx):
            y = y[max(0, idx[0] - int(0.001 * SR)):idx[-1] + 1]
    else:
        a, b = spec.split(":")
        y = x[int(float(a) * SR):int(float(b) * SR)]
    return y


def encode(y, path, q):
    y = y / (np.max(np.abs(y)) + 1e-12) * 10 ** (-1 / 20)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    codec = ["-c:a", "flac"] if path.endswith(".flac") else ["-c:a", "libvorbis", "-q:a", str(q)]
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-"] + codec + ["-map_metadata", "-1", "-fflags", "+bitexact", path],
                   input=y.astype("<f4").tobytes(), check=True)


def harvest(raw):
    n_bytes = 0
    cache = {}
    for cid, c in CLIPS.items():
        p = os.path.join(raw, c["src"])
        if p not in cache:
            cache[p] = load_audio(p)
        y = cut(cache[p], c["spec"])
        long = c["spec"][0] not in "swl" or len(y) > 8 * SR
        encode(y, clip_path(cid), 4 if long else 6)
        n_bytes += os.path.getsize(clip_path(cid))
        print("%-18s %-16s %5.2f s" % (cid, c["group"], len(y) / SR), flush=True)
    print("%d clips, %.2f MB" % (len(CLIPS), n_bytes / 1048576))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    harvest(sys.argv[1])
