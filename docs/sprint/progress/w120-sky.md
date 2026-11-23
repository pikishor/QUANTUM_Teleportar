GOAL: w120-sky fly anywhere (ceiling, edge), rooftops, map targets.
PROBE (finger/real scene): highest peak 559 m at (-200,-2950) (25 m grid scan). Heli ceil 280 not enforced, but VehicleManager._sanity
  teleported any craft > ceil+30 m above ground (heli 310 m over city -> forced drop to ground). Plane ceil 420 absolute < peak.
  Aircraft at world edge: flew into PLAY_HALF clamp, stopped dead (vel 0). Snake flight: soft push at PLAY_HALF-90, no ceiling (ok).
  Roofs: 10 tall towers (every 3rd of tallest) solid, stand + finger JUMP + land again: 10/10 on old code too (no defect).
  GPS short stop (w118): fixed by w119-hud5 (WorldRoute.route_fix), not re-done. Map waypoint limit already WORLD_HALF-60 (outskirts ok).
DONE:
  - vehicle_specs.gd: heli/gunship/hauler ceil 900, plane 1000.
  - aircraft_flight.gd: sky_fix switch (W120_OLD=1), ceil_of(), heli holds at ceiling, edge_turn() soft turn-back (EDGE_SOFT 260 m).
  - vehicle_craft.gd _move_air calls edge_turn; vehicle_manager _sanity uses ceil_of.
  - tests/test_sky_w120.gd: old 3 FAIL (heli dropped to y 135; plane held at 500; corner stopped dead at 4455), new PASS.
TESTS: test_sky_w120 PASS (old W120_OLD=1: 3 FAIL); test_airport_aircraft PASS; test_controls_w118 PASS.
FRAME: plane at 537 m climbing over the peak range (1200x540, touch HUD): view clear.
PERF: LOW OK, MED OK, HIGH OVER death spike 176/175 > 170 (twice; death scene has no aircraft, my changes are flight logic only: not from w120-sky; integrator to check other agents' draws).
NEXT: done (handed off).
DECISIONS: AircraftFlight.EDGE_SOFT 260; ceiling 900/1000 m.
OPEN: map GPS target on a mountain by finger not in the permanent test; plane-on-corner edge only tested with heli.
