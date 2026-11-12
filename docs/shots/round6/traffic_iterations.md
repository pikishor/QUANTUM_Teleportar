# Round 6 traffic: render-look-fix notes

Frames: `tests/bot_traffic.gd` at 2400x1080 (phone), MED and LOW, rain, noon and 21:30. Sheets: `traffic_before_after.jpg` (base commit left, this work right, same views, MED) and `traffic_road_night.jpg`.

Loop 1 (MED, streets, highway, village)
1. The streets had no kerb cars at all (base): bays now hold 25+ parked cars within 80 m of the market, 7 kinds.
2. Highway frame: no car within 100 m of the hero. The bot now runs the traffic until a road car is 14 - 46 m ahead of the camera (OUT_WAIT_CAR=0 turns it off).
3. Village frame: one parked van only. Driveways are generated (12 within 130 m of DUST WELLS), but only one stands in the camera cone; left as is.
4. Highway cars in the first frames showed only far lamp pairs: fine (road cars beyond 52 m are light pairs by design).
Loop 2 (highway, looking across the road)
5. Yaw sign of the road view was wrong for road 1 (looked away from the road): bot uses +1.2 for both.
6. A white box truck / ambulance is blown out in rain light: ambulance 0.90 -> 0.74, delivery white 0.84 -> 0.70, box truck white 0.78 -> 0.68 (assets/shaders/prop_nearcar.gdshader).
Loop 3 (LOW, night, streets and highway)
7. Night street at LOW: dense (61 near + 24 parked in the ring), taillights and headlights read, patrol roofs flash.
8. Highway at night: road cars show lamps only from the front or back, from the side they are dark shapes: accepted.
Loop 4 (close view of kerb cars, 4 m)
- KNOWN GAP: the near car mesh (426 - 445 triangles, shared with the near traffic) looks faceted when a parked car stands 4 m from the camera (wide wheel arches read as wings). The kerb cars are more numerous now, so this shows more. Fix belongs to the cars v2 near mesh (`cv2_near`), not to the traffic code.
