# w118-ci-apk (done)

agent id a86d18d041af9f927, 56 events, first activity 2026-11-22T14:17:06.364Z, last activity 2026-11-22T15:07:21.391Z

## Final report

GREEN d4391eafaee4e539c12b25bc866975f96419210c APK https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/45035305280 ARTIFACT 14759259564 319894185 - CI run 45031931626 (ci.yml, commit d4391ea) passed on the first try. Started 14:16Z, finished about 14:53Z. Nothing was red, so I committed nothing, pushed nothing and did not write docs/sprint/progress/w118-ci-apk.md or a "Wave 118 CI fixes" section in docs/HANDOFF.md. - Passed only on a retry, from the check-run annotations: tests/test_soak_quick.gd failed its first attempt with "leak: orphans grew from 57.0 to 70.0 at checkpoint 1 (limit 69.0)" and passed the second. It is not on the integrator's known-flake list, so it may be a new soak flake or the start of a small leak from wave 118. I did not reproduce or investigate it. - The known flakes test_superhero_hero and test_world_hud did not show up as flaky in this run. - Android run 45035305280 (android.yml, workflow_dispatch on main) succeeded. Its artifact is android-debug-apk, id 14759259564, 319,894,185 bytes. - The only other annotations were Node.js 20 deprecation warnings on the actions.

## Last notes of the agent

- 14:53:50 Green. Now check flaky annotations and trigger android.

## Recent steps (last 40)

- 14:17:10 git log -1 --format='%H %s' && gh run list -w ci.yml -L 5
- 14:17:13 while [ "$(gh run view 45031931626 --json status -q .status)" != completed ]; do sleep 60; done; gh run view 45031931626 --json conclusion -q .conclusion
- 14:17:15 select:Monitor
- 14:17:18 CI run 45031931626 conclusion
- 14:17:21 grep -n "Wave 114 CI fixes" -A40 docs/HANDOFF.md | head -60; git log -1 --format=%B | tail -4
- 14:17:24 F=/tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/tasks/bm44vr6vd.output; timeout 590 bash -c "until [ -s $F ]; do sleep 20; done"; ca...
- 14:27:18 F=/tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/tasks/bm44vr6vd.output; timeout 590 bash -c "until [ -s $F ]; do sleep 20; done"; ca...
- 14:37:13 F=/tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/tasks/bm44vr6vd.output; timeout 590 bash -c "until [ -s $F ]; do sleep 20; done"; ca...
- 14:47:07 F=/tmp/claude-0/-home-user-QUANTUM-Teleportar/2e2fe9d5-4efc-51be-91b4-8eed795e3168/tasks/bm44vr6vd.output; timeout 590 bash -c "until [ -s $F ]; do sleep 20; done"; ca...
- 14:53:51 for j in $(gh run view 45031931626 --json jobs -q '.jobs[].databaseId'); do gh api repos/pikishor/QUANTUM_Teleportar/check-runs/$j/annotations -q '.[]|select(.annotati...
- 14:54:10 timeout 590 bash -c 'until [ "$(gh run view 45035305280 --json status -q .status)" = completed ]; do sleep 30; done'; gh run view 45035305280 --json status,conclusion
- 15:04:05 timeout 590 bash -c 'until [ "$(gh run view 45035305280 --json status -q .status)" = completed ]; do sleep 30; done'; gh run view 45035305280 --json status,conclusion
- 15:07:15 gh api repos/pikishor/QUANTUM_Teleportar/actions/runs/45035305280/artifacts -q '.artifacts[]|"\(.id) \(.size_in_bytes) \(.name)"'
- 15:07:21 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
