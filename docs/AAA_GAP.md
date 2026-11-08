# Why this game is not AAA yet: every reason, and who can fix it

Owner ratings so far: 2 (wave 76 build), 2.5 (wave 84), 3.5 (wave 93). Independent director review scored 4.5 on wave 92 by looking at frames.
Legend: [ME] I can fix it with code/agents; [YOU] needs a decision, files, money or a person; [BOTH] needs both.

## 1. Art and content (the biggest visible gap)
1. Characters: the hero and enemies are generated or free low-poly rigs, not sculpted, scanned or hand-animated characters. [YOU: real character packs or an artist; BOTH]
2. Cars are procedural boxes with wheels; AAA cars are 50-150k-triangle modelled assets with interiors. [YOU: licensed/CC0 car models; I import them]
3. Weapons are simple generated models, no real gun art (no detailed parts, no per-weapon animations). [YOU: CC0/licensed weapon models; BOTH]
4. Buildings are kit-bashed procedural blocks; AAA streets are hand-built with unique assets. [BOTH: more kits, then more of my variety work]
5. Surfaces are procedural, not scanned PBR textures. [ME now that downloads are allowed: ambientCG/Poly Haven]
6. No cinematic art (no key art, no concept direction, no consistent style guide). [YOU: art director decisions]
7. Animation: no motion-capture library; walks, runs, aim, reload, climb, drive are procedural. [BOTH: CC0 animation packs; mocap is paid]

## 2. Audio
8. Sounds are synthesised with code (the owner says they sound like Tetris); AAA uses recorded and layered real sounds. [ME: fetch CC0 samples; YOU for paid libraries]
9. Music is generated, not composed or recorded. [YOU: composer or licensed tracks]
10. No voice acting. [YOU: voice actors or licensed TTS]
11. I cannot listen to audio at all; I can only measure it. [YOU: your ears as the only audio QA]

## 3. Game design
12. No game designer: systems were stacked (14+ weapons, 7 abilities, crafting, factions, ...) without a tight core loop. [BOTH: you decide what the game is; I cut and focus]
13. Missions are generic step kinds, not authored set pieces with story beats. [BOTH]
14. Onboarding and discoverability are weak ("game is not obvious", "hard to find weapons"). [ME with your direction]
15. Balance is simulated, never playtested by many humans. [YOU: playtesters]
16. Open world is a small procedural city (640 m); GTA is dozens of km2 with hand-placed content. [ME: bigger streamed city; BOTH: content]

## 4. Engineering and platform
17. Mobile GPU budget: 30-60 FPS on a phone caps draws, triangles and texture memory; AAA assumes console/PC. [fundamental; ME to scale detail by tier]
18. No real-device testing by me: I only see software renders (no phone FPS, heat, GPU cost, audio, touch feel). [YOU: tests every build; ideally several phones]
19. Godot 4 Mobile renderer limits (no GI, limited post, shadows cost). [fundamental; ME to work around]
20. Many systems integrated late and by separate agents, so bugs appear at seams (map freeze, interior tasks not completable, stuck states). [ME: integration audits, playthrough bots]
21. Test suite proves code paths, not fun. [ME: director-review loops; YOU: feedback]

## 5. Process and resources
22. Team size: AAA is 100-1000 people over 3-5 years; this is one human plus AI agents over days. [fundamental]
23. Tokens/usage limits cap how much I can do per day (the weekly limit was hit once). [YOU: budget]
24. Container restarts and slow CI interrupted long runs several times. [ME to resume; platform limit]
25. I cannot judge look/feel without frames, and my self-review is optimistic; the independent director step helps but is still software-rendered. [YOU]
26. Network was blocked until now, so no open-source art/audio could be downloaded. [fixed: QUANTUM_Teleportar environment allows ambientcg, polyhaven, opengameart, quaternius]

## 6. Business and release
27. Licensing: every asset needs a clear license; some free packs are non-commercial. [YOU confirm license per pack]
28. Store requirements: accounts, signing keys, privacy policy, age rating, store art. [YOU]
29. Localisation, accessibility and QA at scale need testers. [YOU]
