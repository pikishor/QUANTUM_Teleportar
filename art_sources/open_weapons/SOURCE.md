# Open-source guns

| Pack | Author | URL | Files kept here |
|---|---|---|---|
| Ultimate Gun Pack (July 2019) | Quaternius | https://opengameart.org/content/low-poly-guns-pack (zip: https://opengameart.org/sites/default/files/ultimate_gun_pack_by_quaternius.zip) | ultimate_gun_pack/*.obj + .mtl: Pistol_1, Pistol_3, Pistol_6, Revolver_2, SubmachineGun_1, AssaultRifle_2, SniperRifle_2, SniperRifle_6, Bullpup_1, Shotgun_1, Shotgun_ShortStock, Shotgun_SawedOff; round 4 part 2 (same zip, fetched with a plain curl and a descriptive user agent): SubmachineGun_3, SubmachineGun_4, AssaultRifle_4, Shotgun_3, SniperRifle_3, SniperRifle_4 and Accessories/Bayonet_2 (the PHASE KNIFE) |
| Low Poly Weapon Pack | byzmod3d | https://opengameart.org/content/low-poly-weapon-pack (file: https://opengameart.org/sites/default/files/rpg7_1.obj) | rpg7/rpg7_1.obj (its .mtl is not published; the three parts are coloured by tools/open_models/convert_weapons.py) |

Roster round (same zip, re-fetched with a plain curl and a descriptive user agent): Pistol_5, SubmachineGun_2, AssaultRifle2_2, Bullpup_2, Bullpup_3, SniperRifle_5 (.obj + .mtl, 0.8 MB, the heavy pistol, machine pistol, RANGER rifle, BULLPUP rifle, LMG, anti-material rifle).

Licence: CC0 1.0 (LICENSE.txt). Only the guns the game uses are kept (about 0.8 MB); the other 40 guns and accessories of the pack are not committed.
Used by: godot/tools/open_models/convert_weapons.py -> godot/assets/models/ow_<weapon>.glb -> WeaponModels (scripts/player/weapon_models.gd).
Not fetched / not used: Kenney.nl (403 to scripts), the Quaternius site's own downloads (Google Drive, blocked), a launcher and a grenade model other than the RPG-7 (the procedural grenade stays).
