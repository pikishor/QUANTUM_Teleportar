export const meta = {
  name: 'wave-runner',
  description: 'Runs ONE wave of docs/PLAN_116_150.md: two builders, an independent critic-fixer, the integrator, then CI and the Android build',
  phases: [{ title: 'Build' }, { title: 'Review' }, { title: 'Integrate' }, { title: 'CI and APK' }],
}
// args: {wave: 116, skipTags: ['touch-audit'], skipCritic: false, reports: {tag: 'pointer', critic: 'pointer'}, ciSha: '<integrator text>' (only the CI and APK step runs)}
const A = args || {}
const N = Number(A.wave || 116)
const SKIP = A.skipTags || []
const REP = A.reports || {}
const EFF = A.effort || 'low'

const COMMON = `
You work on the Godot 4.6.1 game QUANTUM TELEPORTAR in /home/user/QUANTUM_Teleportar (project in godot/). Read first: docs/ROUND7.md (the owner's words and the rule that came out of
round 7), docs/PLAN_116_150.md (this wave's line), the section "Rules for every agent of the sprint" in docs/ROUND6.md (progress log docs/sprint/progress/<your label>.md kept current
after every step so another agent can resume; small working steps; NO commits and NO pushes unless your task says so; disk above 4 GB; machine time rule) and the last 3 sections of
docs/HANDOFF.md. The owner plays on a PHONE with touch only and rated the last build 4/10: "small silly errors. Are you even checking."
HARD RULES: (1) every UI or control check you write drives the real main scene with REAL finger events (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event,
window coordinates: root.get_final_transform() * pos; see godot/tests/test_touch_buttons_r7.gd), never the mouse and never a direct function call, with Game.force_touch = true and the
phone-only layers on (CrateReveal._quiet = 0); (2) each fix gets a check that FAILS on the old code (show it failing first); (3) never weaken a test, never raise a perf limit
(PERF_CHECK=1 tools/perf_report.sh 0 1 2 must stay OK on LOW, MED and HIGH: run it at most twice, at the end); (4) another agent edits the same tree at the same time: touch only
what your task needs, keep other agents' hook lines, run tools/import.sh after adding a class_name; (5) look at your own frames (tools/bot.sh renders at phone aspect 2400x1080 or
1200x540) before you call something fixed; (6) original names, only own-made or CC0 assets, no secrets in files. If you were restarted, your log says where to continue.
Your FINAL message is your report (plain text, under 350 words): what you fixed with the check that proves each, what you found and did not fix, files touched, perf lines.`

const WAVES = {
  116: {
    title: 'Touch-first pass and a clear flight view',
    builders: [
      { tag: 'touch-audit', prompt: `TASK (label w116-touch-audit): THE TOUCH AUDIT. Build godot/tests/bot_touch_audit.gd plus a test godot/tests/test_touch_audit.gd that, in the real main scene with
touch on, find EVERY control a player can press and press each with a real finger: all HUD buttons on foot, in a car, in the air (snake flight), in an aircraft, in an interior; MORE and its
cards; the weapon wheel (both levels) and the ability wheel; pause menu and every sub-screen (loadout / Arsenal, options, map, mission board, shop, skills, suit, garage, extras, photo mode,
vendor window, fast-travel list, the TEST and DEMO menus, title screen). For each: does the press do what the label says, can the screen be LEFT again by a finger (BACK / CLOSE / X and the
phone back key), does any layer sit on top and swallow the touch, is the target at least 44 px at 844x390 and not overlapping a neighbour. The round 7 bug class: plain Godot Button nodes
are deaf to touch (now pressed by scripts/ui/touch_buttons.gd): check no screen double-fires because of it and none is still deaf (ScrollContainers, sliders, LineEdits, OptionButtons,
CheckBoxes are Controls too: emulate_mouse_from_touch is off). Write the table of findings into your log, fix every dead, wrong or trapped control, keep the audit as a permanent test.` },
      { tag: 'flight-view', prompt: `TASK (label w116-flight-view): A CLEAR VIEW AND HONEST CONTROLS IN THE AIR. Owner: "fly is working but sometimes there are many rays obscuring the view" (frames
docs/owner_shots/round7: light-blue wing bands crossing the whole screen, radial rays, big translucent buttons over the hero). (a) Find every full-screen or large overlay drawn while swinging,
zipping, flying or boosting (snake_speed_lines shader, wing snakes scripts/quantum/snake_flight.gd, snake_fx.gd, reward and hint layers, rain streaks) and make the view clear: the wings
must not cross the centre of the screen or hide the horizon and the target, speed streaks only at the far edges and faint, nothing over the crosshair; render before / after frames from the
real chase camera at 1200x540 on LOW and MED and check them by eye and by a pixel test (share of the central 60 % of the frame covered by overlay pixels under a small limit). (b) In flight
the phone shows FPS 37 to 41 with drops to 13 to 28 and the perf line says VEHICLES 4 to 6.5 ms of script time far from any car: find what the vehicle code does in the air and cut it
(measure with tools/cpu_frame.sh or the in-game perf overlay code). (c) Drive SNAKE, ZIP, FLY / LAND, BOOST and UP by real finger events and write down exactly how each misbehaves today
(the owner: "zip line is not working properly", "behaves abnormally"): fix plain bugs (a press that does nothing, a state that cannot be left, the hero stuck or flung); the rebuild of the
swing itself is wave 117: leave a precise defect list for it in docs/sprint/progress/w116-flight-view.md under "FOR WAVE 117".` },
    ],
    critic: `You are the INDEPENDENT REVIEWER of wave 116 (label w116-critic), then its fixer. You did not build it; assume it is broken until you have seen it work. Play the real main scene
ONLY through finger events with a bot of your own (do not reuse the builders' bot): title, start, walk, shoot, swap weapon by the wheel, open and LEAVE every screen, enter and leave a car,
swing, zip, fly, land, open the map and close it, demo mode on and off. Hunt the owner's class of bug: a control that does nothing under a finger, a screen you cannot leave, a layer over
the view, something that repeats or never ends. Render frames and LOOK at them. List the 10 worst defects with evidence, fix them most severe first, each with a check that fails without the fix.`,
    commit: 'Wave 116: every control answers a finger (touch audit), a clear view in flight',
  },
}
const W = WAVES[N]
if (!W) { log(`wave ${N} has no definition in this script yet: add it to WAVES`); return { wave: N, error: 'no definition' } }
const L = t => `w${N}-${t}`
log(`wave ${N}: ${W.title}`)

if (!A.ciSha) {
  phase('Build')
  const built = await parallel(W.builders.map(b => () => {
    if (SKIP.includes(b.tag)) return Promise.resolve(REP[b.tag] || `finished before the restart: its report is in docs/sprint/progress/${L(b.tag)}.md`)
    const restart = A.restarted ? `\nRESTART NOTICE: this task was started before and interrupted. Read docs/sprint/progress/${L(b.tag)}.md and git status first and continue from there; do not redo finished steps.` : ''
    return agent(COMMON + '\n' + b.prompt + restart, { label: L(b.tag), phase: 'Build', effort: EFF })
  }))
  const reports = W.builders.map((b, i) => `--- ${L(b.tag)} ---\n${built[i] || 'NO REPORT (the agent died): read docs/sprint/progress/' + L(b.tag) + '.md'}`).join('\n')

  phase('Review')
  const critic = A.skipCritic ? (REP.critic || `finished before the restart: docs/sprint/progress/${L('critic')}.md`)
    : await agent(COMMON + '\nTASK: ' + W.critic + (A.restarted ? `\nRESTART NOTICE: read docs/sprint/progress/${L('critic')}.md first and continue.` : '') + '\nThe builders reported:\n' + reports,
        { label: L('critic'), phase: 'Review', effort: EFF })

  phase('Integrate')
  var integ = await agent(COMMON + `\nTASK (label ${L('integrator')}): YOU ARE THE INTEGRATOR of wave ${N}. The builders and the reviewer left their work uncommitted in the tree. (1) tools/import.sh, then the FULL suite
(godot/tools/test_all.sh logic, 3 jobs, a clean XDG_DATA_HOME per test, one retry; a tool call is limited to 10 minutes, so run it in resumable slices in the background and poll); look at
every FAIL against a copy of HEAD to tell this wave from old flakes; fix real bugs, move stale tests with a reason, weaken nothing. (2) PERF_CHECK=1 tools/perf_report.sh 0 1 2: all three OK,
no limit raised (trim instead). (3) tools/visual_qa.sh and LOOK at docs/shots/latest.png. (4) Run every touch test of this wave again on the final tree. (5) Tidy (no scratch files, disk),
add a section "Wave ${N} integration" to docs/HANDOFF.md (what the wave holds, suite result, perf lines, open follow-ups), then commit everything that belongs to the wave (never
docs/sprint/progress/auto_*.md or AUTO_INDEX.md) with the message "${W.commit}" and the trailers "Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>" and
"Claude-Session: https://claude.ai/code/session_01WbKrgUpExX7TuSc4cdY35F", and git push origin main (fetch and rebase first if main moved: the main session pushes notes with [skip ci]).
Never push with a perf verdict OVER. FINAL message: the commit sha on the first line, then the summary.\nReports:\n` + reports + '\n--- reviewer ---\n' + (critic || 'NO REPORT'),
    { label: L('integrator'), phase: 'Integrate', effort: EFF })
} else {
  var integ = String(A.ciSha)
}

phase('CI and APK')
const ci = await agent(`You watch the CI of wave ${N} of the game in /home/user/QUANTUM_Teleportar (repo pikishor/QUANTUM_Teleportar, branch main) and then build the phone APK (label ${L('ci-apk')}).
The integrator reported: ${String(integ).slice(0, 600)}
(1) Find the CI run of that commit (gh run list -w ci.yml -L 5) and wait for it WITHOUT burning turns: one background shell loop that sleeps and exits when the run completes (a tool call
is limited to 10 minutes; a shard takes up to 45). (2) If it is red: read which tests failed (the check-run annotations name them: docs/HANDOFF.md "Wave 114 CI fixes"), reproduce locally
(the runner's font is DejaVu: the FONTCONFIG_FILE trick is in that section), fix the REAL cause (never skip, weaken or retry-loop a test), commit only your own paths with the same
trailers as the last commit on main, push, wait again. Keep notes in docs/sprint/progress/${L('ci-apk')}.md and a section "Wave ${N} CI fixes" in docs/HANDOFF.md. (3) When CI is green:
gh workflow run android.yml --ref main, wait for it, and read the artifact (gh api repos/pikishor/QUANTUM_Teleportar/actions/runs/<id>/artifacts).
FINAL message, first line: GREEN <sha> APK <run url> ARTIFACT <artifact id> <bytes>; then what was red and how it was fixed, and tests that only passed on a retry.`,
  { label: L('ci-apk'), phase: 'CI and APK', effort: EFF })
return { wave: N, integrator: integ, ci }
