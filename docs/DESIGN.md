# Quantum Teleportar: design pillars (owner direction, 2026-11-08)

**What the game is:** a full-action, near-future open-world mobile game. You are a hero from the future who can do almost anything:
kill, teleport, drive and ride anything, and complete missions. Missions are EASY and constant: GTA-style freedom in the city plus
Call of Duty-style gunfights, weapons and bombs. Story is light; action is the point.

## Core loop (everything must serve this)
1. Drop in. A clear next mission is always on screen with a route.
2. Go there: run, drive anything, or teleport.
3. Fight: guns, bombs, melee, abilities; enemies come to you; the hero is powerful.
4. Complete the (easy) mission; get credits, a new weapon or an upgrade; see the next mission at once.
5. Repeat, with bigger fights, bigger vehicles and wilder weapons.

## Must be excellent (in this order)
Shooting and weapon feel and variety (pictures, stats, range, blast radius) > vehicles and driving > missions you can always finish >
clear map and objectives > hero movement > sound and music > looks of streets and interiors.

## Cut or hide from the default experience (keep code behind flags, not in menus)
Weapon crafting, faction reputation screens, safehouse management, photo mode, heists planning, boss rush, achievements screens,
collectibles tracking, NPC rumours, skill-tree depth (keep a simple upgrade list), weather gameplay effects, companion commands.
Menus show: PLAY, MAP, LOADOUT (weapons with pictures), UPGRADES (simple), OPTIONS. Everything else is under MORE or removed.

## HUD default
Stick, look, FIRE, AIM, JUMP, RELOAD, one ABILITY wheel, weapon swap, contextual USE/ENTER. One objective line. Nothing else.

## Difficulty
Easy by default (hero is strong). Hard modes optional. No sudden deaths; checkpoints at every mission step.

## Art and sound policy
Free CC0 / commercial-use-allowed assets first (credit in docs/THIRD_PARTY.md); license kept with each pack.
Music: composed as MIDI by the agent and rendered with free SoundFonts, or CC0 tracks. Voices: free TTS if available, else subtitles only.

## Nothing is wasted: how each built system serves the core loop (repurposing map)
- Heists, stealth missions, rescue, bounty hunts, convoy intercepts, chase set pieces, arena, boss rush, set pieces -> become MISSION TYPES on one easy Mission Board (GTA + COD flavour); every mission is short, completable, rewarded.
- Campaign chapters 1-12 -> the guided mission chain; each step uses the same easy mission mechanics; checkpoints at every step.
- Crafting and mods -> simple 'weapon mods' found as pickups and applied in LOADOUT with one tap (no crafting screen).
- Skill tree -> a flat UPGRADES list (damage, health, ability power, teleport range), bought with credits.
- Factions and wanted v2 -> enemy variety and territory flavour (who attacks you where) and police pursuit intensity; screens hidden.
- Safehouses -> mission hubs and garage/loadout points (one tap, no management).
- Side activities, races, events -> optional open-world fun with markers; rewards feed weapons.
- Companion ally -> optional ally on selected missions. Photo mode -> one small camera button in pause. Achievements/collectibles -> rewards shown as simple toasts.
- Weather/time of day -> visuals and atmosphere only; no extra rules to learn.
- Interiors -> destinations for missions (every door leads somewhere with a task).
- Tests, bots, director reviews, CI -> kept; they are the quality gate.
