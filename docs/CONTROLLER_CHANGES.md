# Supplied controller changes

The pasted source is preserved byte-for-byte in
`python_bridge/user_supplied_original.txt`. The active file is
`python_bridge/user_supplied_controller.py`. It keeps the supplied camera
calibration, BEV transform, Canny processing, footprint-clearance calculation,
pure-pursuit steering, speed conversion, and reverse recovery.

| Parameter | Pasted source | Active version |
| --- | ---: | ---: |
| BEV forward maximum | 0.70 m | 1.20 m |
| Minimum lookahead | 0.38 m | 0.32 m |
| Maximum lookahead | 0.50 m | 0.50 m |
| Curvature lookahead gain | 0.06 | 0.06 |
| Speed limits | 0.255–0.510 m/s | unchanged |

The path picker now finds a continuous path through the same clearance map
instead of choosing an unrelated maximum independently on each image row.
It can target a lateral exit when the road turns across the image. When
forward travel is blocked at a T, it selects the left branch. Usable path
length is measured radially so a sideways turn is not rejected merely because
it makes little forward progress.

Visible orange pixels mark the mission cube as occupied. The planner passes
that cube on its right to remain aligned with the narrowing lane beyond it.
Green track margins and the blue board surround are also occupied. Small
colored seams and speckles in the manual's raster artwork are removed before
those masks are used. Wide unmarked asphalt is traversed slowly along the
current heading until a boundary is visible again.

A failed path sends an immediate zero-speed request while preserving steering,
then uses the original bounded reverse-recovery procedure. Tiny disconnected
free components are rejected, and empty downsampled regions return a failed
path instead of crashing the controller.

Driving decisions use the center camera only. The active script does not read
the diagnostic vehicle pose, course map, gate positions, obstacle coordinates,
or any reference trajectory. Those are used only by the recorder and the lap
verification tools.

The resulting behavior is verified in the simulated scene; it does not certify
physical vehicle handling or general obstacle detection from arbitrary colors.
