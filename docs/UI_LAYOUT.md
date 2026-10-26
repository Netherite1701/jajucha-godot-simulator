# Simulator dashboard

The main workspace keeps a large track view above the left, front and right
camera feeds. The front feed is marked as the controller input. Camera cards
resize their display without changing the 640 x 400 sensor images.

The toolbar groups driving controls and keeps Emergency stop at the right.
Run controller starts the supplied script; Manual drive returns control to
WASD or the arrows. Pause changes to Resume, and Step is enabled while paused.
The header shows Manual, Autonomous, Paused or Stopped.

The sidebar has three tabs:

- **Overview**: speed, steering, elapsed time, position, controller connection,
  a LiDAR plot, and recent activity.
- **Vision**: the live controller output and stereo depth/validity previews.
- **Setup**: keyboard shortcuts, starting lights, dimensions, and calibration.

Orbit, Follow, Top and Fit control the track preview. Right-drag and mouse
wheel input work inside the track view. The preview shares the existing
World3D and uses its own display camera; the three sensor viewports retain
their calibrated optics and transforms.

The dashboard is implemented in `scripts/simulator_dashboard.gd` with Godot
containers, so cards resize without overlapping. Its slate background, teal
accents, muted text, and reserved red emergency control avoid the previous
large translucent overlays. Long setup information scrolls inside its tab.

While checking the LiDAR plot, integer division in ray-angle calculation was
found to repeat the forward direction. The scan now distributes all 409 rays
around the full circle. The supplied driving controller continues to use its
center camera.

## Verification

Rendered and checked at 1440 x 900, 1280 x 720, and 1080 x 680. The layout
check covers all three tabs, visible camera cards, toolbar bounds, pause,
resume, single-step, Follow, Top, Fit, right-drag orbit, wheel zoom,
emergency stop, and reset. Live controller output was received and displayed.
Screenshots are in `.cache/ui/`, including `before.png`,
`controller_overview.png`, and `controller_vision.png`.

The structural/dimension regression check passed. The reorganized simulator
also completed a recorded full lap in 110.2 s over 33.90 m, passing all seven
ordered checkpoints and crossing the start line. The road audit found no
center or tested footprint samples on grass or red curbs across 880 poses.
See `LAP_VERIFICATION.md` for the run and evidence files.

To repeat the UI check with a live controller:

```powershell
& 'C:\dev\Godot_Installations\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://scripts/capture_ui.gd -- --controller
```
