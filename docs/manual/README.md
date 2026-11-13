# Jajucha manual digest: index

## 1. Purpose

This folder is a page-cited English digest of the official Korean Jajucha [자주차] documents. Use it instead of the PDFs; every fact carries a "(doc, p. N)" citation with PDF page numbers. The car manual is ground truth for car facts. The original PDFs are kept privately outside the repo.

## 2. Documents

| File | Source document | Pages | Covers |
|---|---|---|---|
| `car-manual.md` | Jajucha manual [자주차 매뉴얼] | 448 total; digested 4-54, 279-301 | Box contents, power, charging, software, notebook, `jchm` drive/depth/LiDAR API |
| `car-lane-detection.md` | Same manual, Part 4 ch. 2 [차선 인식하기] | 302-375 | Grid lane driving, ResNet classification, YOLO-seg, P/PI/PID |
| `car-obstacle-avoidance.md` | Same manual, Part 4 ch. 3 [장애물 회피하기] | 376-448 | Depth, LiDAR, YOLO object-detection avoidance |
| `competition-manual.md` | 2026 Hyundai Mobis Engineering Leader Festival guide [2026 현대모비스 공학 리더 페스티벌, 자율주행자동차 경진 대회] | 53 | Schedule, courses, missions, rules, scoring, hardware |
| `track-build-manual.md` | 2026 track construction guide [2026 ... 자주차 경진 대회 트랙 제작 안내] | 8 | Panels, assembly grid, hill, tunnel, starting light, speed meter |
| `track-summary.md` | 2026 track guide summary [2026 트랙 안내 요약 자료] | 9 | Qualifying/final run steps, mission descriptions |
| `signs.md` | 2026 competition signs [표지판], A4 and B4 sheets | 4 | Look and mission of the four signs |

## 3. Key car specs

| Item | Manual value | Citation |
|---|---|---|
| Steering per unit | 2 deg per unit of `left`/`right` | (car manual, p. 282) |
| Steering range | -10..10 units = -20..+20 deg, per wheel; negative = counter-clockwise (left turn) | (car manual, pp. 281-282, 286) |
| Servos | One DC servo per front wheel, angles independent | (car manual, p. 281) |
| Drive | Rear wheels, BLDC motor; front wheels steer | (car manual, pp. 284, 286) |
| Wheel diameter | 6.5 cm | (car manual, p. 284) |
| Speed per unit | about 5.13 cm/s per unit (4 rad/s per unit) | (car manual, p. 284) |
| Speed range | -30..30 units (about 154 cm/s at 30, derived by linear scaling) | (car manual, pp. 281, 284) |
| Gear ratio | 38:15 reduction (differential) | (car manual, p. 284) |
| Camera resolution | 640 x 400 ("640px X 400px") | (car manual, p. 171); also (car lane detection, pp. 313, 344-345) |
| Camera locations | `center`, `left`, `right` color windows; `get_image('center')` used for lanes; left/right pair gives stereo | (car manual, pp. 42, 287-288); (car lane detection, p. 304) |
| Depth image | Stereo, grayscale, near = bright; array is 3-channel; example size 202 x 220 (not stated as a spec) | (car manual, pp. 287, 290); (car obstacle avoidance, p. 378) |
| LiDAR range | 12 m max, 0.05 m blind range; 2D ToF at its scan-plane height only | (car manual, p. 294) |
| LiDAR points | about 300-450 per revolution (example 398) | (car manual, pp. 294-295) |
| LiDAR direction | Starts at front (0 deg), goes clockwise; distances in mm | (car manual, pp. 294-296, 298) |

## 4. jchm API quick reference

| Function | Meaning | Citation |
|---|---|---|
| `jchm.control.set_motor(left, right, speed)` | Steer left/right front wheel (int -10..10 each), drive speed (int -30..30); `(0,0,0)` straightens and stops | (car manual, pp. 281-283) |
| `jchm.camera.get_image('center')` | Capture color camera image (default 640x400) | (car lane detection, pp. 304-305, 313) |
| `jchm.camera.get_depth()` | Stereo depth image as NumPy array; larger value = closer; `[0]` of a pixel gives scalar | (car manual, pp. 289-290) |
| `jchm.camera.show_image(img, "location", quality=80)` | Show image in toolbar window `center`(default)/`right`/`left`/`depth`/`lidar`; window must be open first | (car manual, pp. 42, 288-289) |
| `(V, L, R), grid = jchm.camera.gridFront(img)` | ROI, blur, Canny, grid; returns 7 V, 3 L, 3 R values plus grid image | (car lane detection, pp. 313-315) |
| `theta_array, dist_array = jchm.lidar.get_lidar()` | NumPy angles (deg, 0 = front, clockwise) and distances (mm) | (car manual, p. 295); (car obstacle avoidance, p. 391) |
| `jchm.lidar.show_lidar(theta_array, dist_array, max_dist)` | Draw scan in `lidar` window; `max_dist` in mm up to 12000 | (car manual, p. 296) |
| `jchm.load_ai()` / `jchm.ai.get_model_output(img, NAME)` | Load and run user-trained ResNet/YOLO model | (car lane detection, pp. 355-356, 365) |

## 5. Competition at a glance

Preliminary course, 10 zones (competition manual, p. 18; track summary, p. 2):
- 1 start on the starting-light signal; 2 S-curve; 3 right-angle section; 4 tunnel (U-shaped) (competition manual, p. 18).
- 5-6 ramp, then right turn and straight; 7 zigzag; 8 obstacle zone; 9 curve then straight (competition manual, p. 18).
- 10 finish without hitting the pit-sign partition [격벽] (competition manual, p. 18).

Final course, 9 zones plus extras (competition manual, p. 20; track summary, p. 4):
- 1 start light; 2 S-shaped tunnel; 3 right-angle; 4 U-turn then straight; 5 corner (ㄱ) ramp; 6 zigzag (competition manual, p. 20).
- 7 obstacle zone (scored as A and B); 8 curve then straight; 9 finish without hitting the pit sign (competition manual, pp. 20, 22).
- Extra: yellow flag with speed check (`set_motor` speed 1-3 passes, 4+ fails) (competition manual, pp. 22, 26).
- Extra: sudden obstacle, car must stop with a front wheel on its panel (competition manual, pp. 23, 26).

Scoring headline: both sheets start at 100; lane touch -1, driving while touching -1 per second, lane departure -10, pit-sign failure -3, false start -4, start-light success +4, tunnel +5, time bonus by rank (competition manual, pp. 27-28).

Start/finish: four LEDs light at 1.5 s intervals, all go off after a random 3-6 s and a buzzer sounds; that moment is the start; starting early is a false start; not moving within 5 s of the buzzer fails (competition manual, pp. 18, 26; track summary, p. 5). Start/finish line is at the bottom edge of the map (track summary, p. 1).

## 6. Track at a glance

- Panels: foam board, 3 mm thick, 900 x 900 mm; 41 panels on an 11 x 6 grid (9.9 m x 5.4 m), 41 of 66 cells filled (track build manual, pp. 1-2).
- Hill: 900 x 900 x 100 mm styrofoam block, plus 2 triangular slope blocks; about 6 degrees (track build manual, p. 3; competition manual, pp. 19, 21).
- Tunnel: 220 mm high, 390 mm wide at entrance; top plate five 260 mm sides and one 98 mm side (track build manual, p. 6).
- Obstacles: 15 cm sponge cubes (competition manual, pp. 19, 22).
- Starting light: about 160 mm x 80 mm; placard 3 cm x 13 cm (track build manual, p. 4; competition manual, p. 51).
- Speed meter: 2 IR sensors 30 cm apart; limit 21 cm/s by default (track summary, p. 6; competition manual, p. 47).
- Signs: pit 32 x 13 cm, yellow flag 15 x 18 cm, sudden obstacle 24 x 24 cm (competition manual, p. 51).

## 7. Where the simulator differs

| Item | Manual | Simulator now | Where in sim |
|---|---|---|---|
| Steering limit | +/-20 deg per wheel, 2 deg per unit (car manual, p. 282) | 35 deg for full lock (tuned; physical maximum unverified) | `calibration.json` `rig.steering_limit_deg` (also `steering_limit_deg` in main.gd, default 28) |
| Servo to steering | Left and right wheels independent (car manual, p. 281) | One bicycle-model angle from `-(left + right) / 20` times the limit; per-wheel angles lost | `_handle_notebook_message` (`notebook_control`), `apply_python_command` |
| Single-wheel command | `set_motor(-10, 0, 0)` turns only the left wheel 20 deg (car manual, p. 282) | Becomes half lock, about 17.5 deg of body steering | `_handle_notebook_message` |
| Wheel diameter | 6.5 cm (car manual, p. 284) | Tire cylinder radius 0.040 m (80 mm diameter); visual only | `top_radius` in the wheel-building code of main.gd; `calibration.json` `tire_diameter_m` is null |
| Speed per unit | about 5.13 cm/s per unit, -30..30 (car manual, p. 284) | 0.0513 m/s per unit, matches | `_handle_notebook_message` |
| Speed range | up to about 154 cm/s at 30, derived (car manual, pp. 281, 284) | Clamped to 0.6156 m/s (about 12 units) | `calibration.json` `rig.speed_cap_mps` |
| Drive model | Rear-wheel drive BLDC, gear 38:15 (car manual, p. 284) | Kinematic bicycle, speed ramps by acceleration/braking | `wheelbase_m` 0.183 (unconfirmed), `calibration.json` `rig.acceleration_mps2`, `braking_mps2` |
| LiDAR | 300-450 points, 12 m, 0.05 m blind (car manual, p. 294) | 409 rays, 12 m, 0.05 m; angles deg, ranges mm | `calibration.json` `lidar`; `_receive_python_packets` path sends `lidar_angles_deg`, `lidar_ranges_mm` |
| Camera | 640 x 400 (car manual, p. 171) | 640 x 400; side cameras share the center optics | `calibration.json` `coordinate_frame.image_size_wh_px`, `rig.side_intrinsics_status` |
| Depth image | Stereo depth, near = bright (car manual, p. 287) | Depth encoded as 255 * 0.4 / distance, 640 x 400 fallback | `compute_stereo_depth`; `calibration.json` `rig.stereo_baseline_m` (0.058, derived) |
| Camera height | Not stated in digests | 0.099 m calibrated vs 0.075 m photo estimate, unresolved | `calibration.json` `rig.camera_height_*` |

## 8. Known inconsistencies in the manuals

- Boot cue: text says the front wheels move left once, the figure caption says right (car manual, p. 12).
- `show_lidar` signature on p. 296 prints `show_image`, example code uses `show_lidar` (car manual, p. 296).
- Lane digest: ROI grid has "30 regions" in a caption and "32" in the body (car lane detection, p. 313).
- Lane digest: result item says "turn right" for R[1] < 150 but code and flowchart turn left (car lane detection, pp. 329-331).
- Lane digest: flowchart gate `V[2] >= 100` is absent from the code (car lane detection, pp. 329-330).
- Lane digest: class meaning 0/1/2 differs between code comments and result text (car lane detection, pp. 357-358).
- Lane digest: y-center written as 320 but 0.81 x 400 = 324 (car lane detection, p. 354).
- Obstacle digest: prose after YOLO samples says "right" where code turns left (car obstacle avoidance, pp. 428-430).
- Obstacle digest: sections numbered 2.3 with no 2.2, and 3.1 used twice (car obstacle avoidance, pp. 403, 417, 424).
- Obstacle digest: meaning of first two `set_motor` arguments is undefined there; LiDAR angle direction is inferred (car obstacle avoidance, pp. 387, 399-400).
- Competition: 7 vs 8 preliminary teams, scoring uses 8 (competition manual, pp. 2-4, 27).
- Competition: final-sheet speed violation printed as "4 points", sign unclear (competition manual, p. 28).
- Competition: disqualification time limit has no number (competition manual, pp. 27-28).
- Track: no type E panel; 41 panels on 66 cells; assembly drawing shows no mission positions (track build manual, pp. 1-2).
- Track: inventory and assembly drawing agree on I = 1 and J = 5, so there is no I/J conflict (older repo notes claimed one); `scripts/course_data.gd` `INVENTORY_TILE_COUNTS` matches (track build manual, pp. 1-2).
- Track: tunnel top plate shows five 260 mm labels vs caption's single long side (track build manual, p. 6).
- Signs: no sizes marked on the sign sheets themselves; sizes come from the competition manual (signs A4, p. 1; competition manual, p. 51).
