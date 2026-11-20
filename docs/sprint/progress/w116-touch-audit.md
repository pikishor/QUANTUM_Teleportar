# w116-touch-audit progress log
GOAL: a touch-only audit of every pressable control in the real main scene (tests/bot_touch_audit.gd + tests/test_touch_audit.gd), fix every dead / wrong / trapped control.
DONE:
- (start) read ROUND7, PLAN_116_150, ROUND6 rules, HANDOFF tail, scripts/ui/touch_buttons.gd, tests/test_touch_buttons_r7.gd
NEXT:
- survey every UI screen (scripts/ui), how each handles touch (_input ScreenTouch vs Button / gui_input)
- write the audit library + bot, run it, table of findings here
- fix, each with a check failing on old code
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
