# w126-critic log (independent review + fixes of wave 126: plane roster, hangars, air traffic, air missions, aircraft weapons)
GOAL: finger-only bot in real main scene; list 8 worst defects; fix most severe first with fail-first checks.
DONE
- godot/tests/bot_w126_critic.gd: headless finger probe (CRP_PARTS line,fly,missions,traffic; CRP_KINDS). Runner caps 140 s: one kind per process.
  run: scratchpad crp/run.sh out.txt with env.
- godot/tests/bot_w126_critic_look.gd: frames + flight perf (CL_PARTS views,board,fly) via tools/bot.sh.
- FIX 1 (written, check pending): VehicleManager._tick_spawn_points spawns the NEAREST fixed point first (_spawn_point helper). W126C_OLD=1 = old order.
FINDINGS SO FAR
- helicopter in front of the hero on the HELI LINE stands only after 8-9 s (10-11 plane-line planes first): cause of test_helis_w125 fail.
- p_duster circuit to the +side (east, local +x) flew into rising terrain (y 100->206) and crashed: probe circuit now on the other side.
NEXT
- results of p_duster/p_jumbo/p_fighter runs; more kinds; missions; traffic; look bot LOW+MED; checks test_w126_critic.gd.
DECISIONS
- switch W126C_OLD=1 turns all my fixes off.
TESTS AND PERF
OPEN PROBLEMS
