# w1242-critic log
- step0: started review, read docs.
- step1: audit found shop sign in awning 1488/1978, billboards floating 8/18; test tests/test_street_w1242c.gd FAILS on old code (both)
- step2: fixed sign/awning + billboard roof (street_detail.gd); test PASS
- step3: tree crown lift + solid props (PhysicsServer body) in street_detail.gd; test part 3 fails W1242C_OLD=1
- step4: demo probe tests/dev_w1242c_demo.gd ran (log scratchpad demo.log): f_cryo, mpistol 0 shots on 0.5 s FIRE hold; investigating
- step5: DEMO prologue cards ate first FIRE taps; fixed story.gd _on_new_game; tests/test_demo_fire_w1242c.gd fails old (W1242C_OLD=1), passes new
- step6: fps test under xvfb MED: 112 draws/236k tris flight; street-share check 43% FAIL + timeout under real renderer (not fixed)
- step7: frames st2 checked; big crown in junction is the old street_dress tree (city_props.gd), not StreetDetail: listed not fixed. running perf
- step8: perf OK LOW 98/107, MED 131/146, HIGH 154/164. DONE; report sent
