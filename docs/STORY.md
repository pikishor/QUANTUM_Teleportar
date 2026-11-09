# THE LONG TOMORROW: story bible (wave 110)

Light, fast and always in service of the core loop (docs/DESIGN.md): the story is the reason for the next mission, never a lecture. Every mission is EASY,
has a clear objective line, one set piece and a checkpoint at each step. All words are subtitles (no recorded voice); each speaker has a portrait.
Quantum names stay plain: QUANTUM TELEPORT, SUPERPOSITION, ENTANGLE, COLLAPSE. Code: `scripts/story/story_{cast,acts,missions,scenes,runner}.gd`; test
`tests/test_story_acts.gd`. The older 12 "Vael / ORACLE" chapters stay in EXTRAS > CHAPTERS as the ARCHIVE; this is the default story on the Mission Board.

## Premise
2140: the Vael hive holds the Earth; the last human redoubt, LAST LIGHT, is about to go dark. Its one hope is a courier who can survive a FOLD, the jump
through time that tears anyone else apart. KESTREL (the hero from the future, name and look replaceable in one config) is sent back to **2091, Neo-Meridian,
the day before TUNING DAY**, when the Authority switches on the ARRAY: a door the Vael need in order to come through. Kestrel has one day, a rig that lets
her QUANTUM TELEPORT, and a voice in her ear.

## Characters (portraits generated from one base bust: `StoryCast.draw_portrait`)
| Id | Role | Look | Colour |
| --- | --- | --- | --- |
| KESTREL | hero, Warden of Last Light, dry and exact | short dark hair, amber visor strip, charcoal suit | amber |
| ORACLE | the rig's mind, half burned by the fold; ally, keeper of one secret | a cyan ring of light, no face | cyan |
| RIVET | harbour mechanic and smuggler, loud, loyal; hides Kestrel, gives wheels | cap, goggles, orange overalls | orange |
| DR. IRIS VANCE (IRIS) | physicist who built the observatory dish and was forced to tune the Array | silver bob, round glasses, lab coat | violet |
| CAPTAIN BASALT | Eastfield airport pilot, grounded by the Authority; in 2140 a name on the memorial wall of Last Light | grey crop, scar, flight jacket | green |
| DIRECTOR VOSS (VOSS) | head of the Meridian Authority; builds the Array for the hive believing it will spare his city | white hair, grey suit, red lapel pin | red |
| VAEL BROADCAST | the hive's voice on every Authority relay | three bright eyes, no mouth | magenta |

## Four acts, twelve missions
Each mission names where it happens (the world of waves 104-109), the one set piece, and what the player is told.

### ACT 1  LANDFALL (the city)
1. **LANDFALL** (street, patrol fight): Kestrel lands in a flash of light, follows the beacon, drives off the Authority patrol. Set piece: the landing and first fight.
2. **BORROWED WHEELS** (car chase to RIVET'S GARAGE): take any car, lose the Authority cars. RIVET introduces herself. Set piece: the chase.
3. **THE RELAY** (tower hack and defence): hack the Authority relay, hold it, drop the relay chief. **Twist 1**: the relay is not a defence net, it carries the
   hive's voice. The Authority is working for the Vael, and VOSS is on the line.

### ACT 2  THE HARBOUR AND THE HIGHLAND (harbour, mountains)
4. **CONTAINER 17** (harbour quay): clear the yard guards and crack the container: switchgear for the Array, signed by a physicist, IRIS.
5. **FERRY RUN** (speedboat across the bay): catch the courier boat before it clears the breakwater. Set piece: the boat chase. The courier names the observatory.
6. **SUMMIT ROAD** (4x4 up the mountain road): run the smuggler's pickup down the hairpins, secure the cargo (the Array's tuning fork) at the top.
7. **THE OBSERVATORY** (mountain site): hold the dish against the patrol while IRIS downloads the Array map. **Twist 2**: every time Kestrel FOLDS or TELEPORTS,
   the Array hears her; her jumps have been tuning it. ORACLE knew and said nothing.

### ACT 3  THE LONG WAY (air and sea)
8. **EASTFIELD** (airport): CAPTAIN BASALT is grounded; clear the hangar, take his plane, fly the dish parts out and land. The plane flies on trust.
9. **CANYON RUN** (helicopter through the gorge): stay under the ridge so the relays cannot see her; BASALT talks her through the rings and the landing.
10. **DEEP WATER** (speedboat out to sea): follow the buoys to the sunken relay at the end of the Array's power cable. IRIS finds where it ends: the alien outpost.

### ACT 4  THE ARRAY (alien outpost, city)
11. **THE OUTPOST** (alien camp in the mountains, helicopter in): break the OUTPOST WARDEN and plant IRIS'S damper core, which makes Kestrel's jumps silent.
    **Twist 3**: the beacon the hive follows is not Kestrel, it is ORACLE's link home to 2140. Cutting it will kill the rig's mind.
12. **TUNING DAY** (city, the Array tower): reach the tower, hold the lobby, break DIRECTOR VOSS, escape the collapse. Set piece: the Array folding in on itself.

## Ending
ORACLE chooses: it cuts its own link to Last Light so the Array goes deaf. VOSS falls with his door. The sky over Neo-Meridian is only sky. The last message from
2140 arrives anyway: Last Light is lit, because the door never opened. ORACLE returns at low power as the hint voice of free roam, a new voice with an old name. Kestrel
stays: the future she came from no longer exists, and the city is hers to roam.

## How it is told
- **Briefing**: every mission opens with a short cutscene (`story_brief`, 7-12 s, skippable): the camera works round Kestrel, subtitles with portraits, the act
  title card on the first mission of each act. Played from the STORY card on the Mission Board; skipped by the CINE OFF option and never started by tests.
- **Radio chatter**: one line at the start of each step (portrait beside the subtitle plate) and one outro line when the mission is done.
- **Set-piece beat**: the missions with a twist or a big moment (3, 5, 7, 9, 11, 12) play a second short cutscene (`story_beat`) at the named step.
- **Finale**: `story_end` plays the credits blocks over the city after mission 12.

## Board and save
- The STORY card (highlighted, magenta) always shows the next mission: "ACT 2  MISSION 5 OF 12". Missions unlock in order; the card never disappears until the story is done.
- Each mission runs through `CampaignRunner.start_custom` like every board mission: checkpoint at every step, instant retry, the objective line, MissionGuide, and the
  shared reward ladder (credits, weapon gifts). A mission dropped after five failures is NOT lost: it comes back as the STORY card.
- Progress is saved in the optional `[story]` section of save.cfg (missions done, the step of the running mission, cutscenes seen). Older saves have no section and load as
  "mission 1"; resuming after a quit starts the mission again from its saved step.
