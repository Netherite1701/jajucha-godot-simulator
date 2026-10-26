# Implementation notes and dimension register

## Directly documented dimensions

| Item | Value | Source |
|---|---:|---|
| Track panel | 900 × 900 × 3 mm | 2026 track-construction manual, p. 1 (900 mm sides; 3T foamboard) |
| Assembled footprint | 9.9 × 5.4 m | same, p. 1 |
| Panel inventory | 41 panels | same, p. 1 |
| Raised block | 900 × 900 × 100 mm | same, p. 3 |
| Tunnel upper sheet | 260 mm long sides; 98 mm short side | same, p. 6 |
| Tunnel portal | 390 mm wide × 220 mm high | same, p. 6 |
| Pit sign | 320 × 130 mm | competition manual, p. 19 |
| Starting-light sign/body | 80 × 160 mm | track manual, p. 4 |
| Light shield | 70 × 130 × 40 mm | same, p. 4 |
| Obstacle cube | 150 mm per side | competition manual, p. 19 |

The competition track diagram is an illustration rather than a surveyed set of
world coordinates. The construction manual's assembled drawing is laid on an
11-column by 6-row grid of 900 mm cells, leaving empty cells. Its visible board
art is used as the cell textures, with the editorial panel-ID letters removed
from the road surfaces. The UI preserves the 9.9 × 5.4 m documented
footprint and calls out that the full route geometry is reconstructed. The car
spawns at the center of the lower straight's D panel (GridMap cell 4, 0, 5),
pointed along the road.

Repeated panel types use one canonical artwork texture and per-cell quarter
turns recovered from their orientations in the p. 2 assembly drawing. This
keeps the lane markings aligned where adjacent road pieces meet.

The two 900 × 900 × 100 mm slope blocks are modeled with a 900 mm run and a
100 mm rise, derived from the square block cut into a triangular slope. The
tunnel is modeled with the documented 390 × 220 mm portal and 5 mm material.
Its 260 × 98 mm upper-sheet shape is represented as four adjacent roof strips;
the 260 mm dimension along the passage is an orientation reconstruction.

## Panel-count discrepancy

The manual's printed panel inventory on p. 1 lists I=1 and J=5. Its p. 2
assembly picture uses I=2 and J=4. Both totals are 41 panels. The project
keeps the printed assembly locations and the 41 occupied cells. It does not
alter tiles to force the parts inventory count.

## Vehicle and sensors

| Parameter | Project value | Evidence/status |
|---|---:|---|
| Camera resolution | 640 × 400 pixels | archived Jajucha manual and project calibration |
| Center camera K | fx=310.70, fy=309.58, cx=309.52, cy=222.31 px | saved calibration in `jajucha_code/config/bev_center.json` |
| Center distortion | `[0.084568, -0.072728, -0.000606, 0.004212, 0.0]` | same calibration file |
| Outer cameras | copies of center K/distortion | provisional; no independent calibration supplied |
| Optical height | 99.009 mm | archived working-run calibration |
| Photo height estimate | 75 mm | conflicting annotated photo estimate; needs physical remeasurement |
| Outer-camera baseline | 58 mm | derived from 29 mm adjacent openings; lens centers unverified |
| Vehicle width | 177.6 mm | measured from supplied photo |
| Tire width | 27 mm | measured from supplied photo |
| Camera front setback | 53 mm | annotated photo measurement |
| LiDAR front setback | 150 mm | annotated photo measurement |
| LiDAR minimum range | 50 mm | archived manual/interface notes |
| LiDAR maximum range | 12 m | archived manual/interface notes |
| LiDAR samples per turn | 409 (editable) | within the 300–450 manual range |
| LiDAR height | 75 mm | provisional photo estimate |

Wheelbase (initially 183 mm), chassis length (initially 252 mm), exact body
depth, tire diameter (initially 80 mm visually), front-edge-to-rear-axle
translation, steering limit, dynamic response, left/right image calibration,
and the 75/99 mm camera height disagreement remain unconfirmed. Edit the
simulator's `calibration.json` where a parameter is explicitly represented;
edit `scripts/main.gd` for procedural mesh sizes and control limits.

The center camera uses an off-axis frustum to place its principal point
without translating the optical center in world space. The sensor-output
shader applies the saved Brown-Conrady radial and tangential lens model and
the small fx/fy difference. The supplied controller then performs its own
OpenCV undistortion on this simulated raw image. Vehicle meshes render on a
separate layer excluded from all three sensor cameras, and camera transforms
follow vehicle motion every physics tick. Outer stereo images
are synchronized but are not rectified against an independently measured
extrinsic pair. The block matcher returns approximate gray range and an
explicit validity mask; its brightness transfer is not an empirical device
calibration.

## Motion and protocol

The vehicle uses a controlled bicycle model. Wheels are visual, tire dynamics
are not simulated, and ramp contact follows a simple grade model. Requested
speed uses the supplied controller's command conversion of 0.0513 m/s per motor unit, capped
at 0.6156 m/s. These are commands, not measured vehicle dynamics.

Godot advances motion at 40 Hz and targets complete sensor bundles at 10 Hz
over `127.0.0.1:8765`. Messages have a four-byte network-order length followed
by UTF-8 JSON. Images are lossless PNG in base64; LiDAR angles and ranges are
plain arrays. The driving controller uses rendered sensor inputs and static
calibration. Diagnostic packets also carry vehicle pose for recording and
verification; the controller does not read that pose, course coordinates,
or obstacle locations. The
controller's `time.sleep`, `time.perf_counter`, and `time.monotonic` are tied
to simulation time. Invalid packets and a controller disconnect stop output.

The user-supplied controller calls `camera.get_image("center")`,
`camera.show_image(...)`, and `control.set_motor(left, right, speed)`. The
bridge also exposes depth and LiDAR for other compatible controllers. The
lap monitor records an entire attempt and requires ordered checkpoints
around the course before accepting a return to the starting pose. It writes
the measured result in each run's `result.json`; a partial drive is not a lap.
Hidden-tunnel planning, competition scoring, physical speed matching, and
actual stereo calibration are not validated by a circuit in this scene.

