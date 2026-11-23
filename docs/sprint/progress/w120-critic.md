# w120-critic
- step 1: started review (read docs). Next: read w120 tests and diff.
- step 2: wrote tests/test_critic_w120.gd (sunk re-enter, boat edge wall). Running fail-first.
- step 3: fail-first shown (sunk re-enter: got in; boat: 9 m from wall). Fixed reach_car skip sunk; edge_turn for boats. Re-running.
- step 4: tests pass after fix; rendering boat edge frames via tests/bot_critic_w120.gd into docs/shots/round7/critic_w120.
- step 5: plane at edge stalled (2.7 m/s) -> fixed in AircraftFlight.edge_turn (keep airspeed). test plane part passes. Next: look at boat frames, run sky/reach tests.
- step 6: sky, critic, reach car+edge, airport, harbour boats PASS. Running perf gate once.
- step 7: perf: MED OK draws=100 death=147; HIGH OVER death 174>170 (pre-existing per both builders; my changes are logic only, no nodes). Done; reporting.
