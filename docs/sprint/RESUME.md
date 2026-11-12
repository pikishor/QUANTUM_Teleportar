# Resuming the round 6 sprint in the middle of a wave

The owner asked that nothing is lost or wasted if the session or the tokens end in the middle of a wave. This is how the work is saved and how to continue.

## What is saved where
- **Finished waves** are on `main` (`git log --oneline`: "Wave NNN: ..."), with the integrator notes in `docs/HANDOFF.md`, the plan in `docs/ROUND6.md` and the review in `docs/SLICE_REVIEW.md`.
- **Unfinished work** (builders' files, new assets, tests, notes) is copied by `godot/tools/wip_snapshot.sh` to the branch `claude/determined-bardeen-mvwr5u` every 25 minutes. It is built with a private git index, so `main`, the real index and the working files are never touched. The branch holds UNTESTED work and is never merged automatically.
- **What each agent was doing**: `docs/sprint/progress/<label>.md` (the agent's own notes, rule in `docs/ROUND6.md`) and `docs/sprint/progress/auto_<label>.md` (an automatic digest of its recent steps, last notes, the files it edited and its final report), index `docs/sprint/progress/AUTO_INDEX.md`. They are part of the snapshot.
- **The sprint script** with restart controls: `docs/sprint/round6_sprint.js`; the arguments of the first launch: `docs/sprint/round6_args.json`; current state: `docs/sprint/STATE.md`.

## Steps to continue
1. `git fetch origin`; `git checkout main`; `git log --oneline -12`. The first wave that is not on `main` is **N**.
2. Bring back the unfinished work without committing it: `git fetch origin claude/determined-bardeen-mvwr5u` and look (`git log main..origin/claude/determined-bardeen-mvwr5u`, `git diff --stat main origin/claude/determined-bardeen-mvwr5u`), then on a clean `main`: `git checkout origin/claude/determined-bardeen-mvwr5u -- .`. The working tree now holds everything that existed at the last snapshot.
3. Read `docs/sprint/progress/AUTO_INDEX.md` and the files it lists. A builder with status `done` and a final report had finished; one that was `running` was mid-way (its notes say what is done and next).
4. Copy `docs/sprint/round6_sprint.js` out of the repository and run it with the Workflow tool, with these arguments:
   `{"startWave": N, "skipTags": ["tags of the builders of wave N that had finished"], "skipCritic": false}`
   (for `N = 121` add `"reviewDefects": [...]` taken from review 7 in `docs/SLICE_REVIEW.md`; `sha111` is only needed for a run that starts at 111).
   Waves before N are skipped. A builder that was mid-way gets a RESTART NOTICE and continues from its notes and the files in the tree. A wave whose builders are all finished goes straight to the critic-fixers and the integrator.
5. The integrator runs the full suite, the perf gate on LOW, MED and HIGH, the visual check, then commits and pushes to `main`. Never push to `main` with a perf verdict OVER.

## Standing rules
- Every agent runs at max effort. The machine has 4 CPUs, so a workflow runs 2 agents at a time; waves have 2 or 4 builders.
- Keep the backup running in the background: `godot/tools/wip_snapshot.sh loop 1500` (one snapshot now: `godot/tools/wip_snapshot.sh`).
- Android builds come from `android.yml` on `main` after CI is green (waves 111, 113, 115, 116, 119, 121).
- Owner-dependent items are in `docs/HANDOFF.md` (hero name and voice, AdMob, Apple secrets, store accounts, audio feedback).
