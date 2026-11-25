GOAL: integrate wave 122 (suite, perf, visual qa, touch tests, handoff, commit, push)
DONE:
- import; full suite running from scratchpad runner (results file in scratchpad/suite/results); HEAD copy in scratchpad/head (worktree) for comparison
- fix roof_parapets.gd: walls off while a snake move carries the hero (test_flight_cost_w116 zip 5/6 -> 7/7); gap at TowerLift roof door (test_lifts_w121 back-door walk failed -> pass)
- shop_fronts.gd keeps d["pos0"]; test_interior_gameplay determinism compares pos0 (shops move door on purpose)
- test_integration crown ledge probe uses the part under the crown (old spot sat on new parapet)
NEXT: commit + push (all checks done)
OPEN: test_integration node count 3015 fails on HEAD too (old)
