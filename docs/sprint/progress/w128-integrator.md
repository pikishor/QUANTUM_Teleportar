GOAL: integrate wave 128 (anim, airlook, arsenal, open, critic): import, full suite, perf, visual_qa, touch reruns, HANDOFF, commit+push.
SCRATCH: /tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/scratchpad (suite128/res.txt, head128 = HEAD copy)
NEXT: import; full suite in background; triage vs HEAD copy; perf; visual_qa; touch reruns; handoff; commit.
- import OK; suite started 18:23 (scratchpad/suite128/res.txt, runner scratchpad/suite.sh resumable); HEAD copy extracted at scratchpad/head128 (not imported yet)
- FIX 1: test_safehouses + test_sequel_mechanics FAIL 2/2 (demo tab count = catalog + 2; w128-open added VEHICLES/AIRCRAFT tabs). DemoPanel.OWN_TABS added; checks count catalog + OWN_TABS and require SPAWN/TOOLS. Both PASS.
- suite DONE 337 files: FAIL safehouses, sequel_mechanics, weapon_crafting (all the demo tab count, fixed: weapon_crafting PASS after); FLAKY device_fixes (known), interior_tasks_ui, mission_audit. NEXT perf
- perf OK: LOW draws=75 total=97 death=107; MED 99/131 prims 274k death 145; HIGH 118/154 death 164. NEXT visual_qa
- visual_qa 27/27 PASS, latest.png looked at. NEXT touch reruns (scratchpad/re128)
- HANDOFF section added (rerun line pending)
