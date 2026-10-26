# Verified full lap

Verified run: `.cache/planning/fullcamera/run_20261025T231211/`.

| Check | Measured evidence |
| --- | --- |
| Result | `LAP_SUCCESS`, normal process exit 0 |
| Elapsed simulation time | 110.200 s |
| Distance traveled | 33.896 m |
| Ordered course checkpoints | 7 of 7 |
| Finish | Forward crossing of the actual starting line |
| Lateral error at crossing | 22.8 mm |
| Heading error at crossing | 1.957 degrees |
| Motor commands | 820 |
| Three-camera sensor bundles saved | 883 |
| Full-resolution camera PNGs | 2,649 at 640 x 400 pixels |
| Recorded center or footprint samples on grass/red curb | 0 of 880 sampled poses |
| Collision, disconnect, course-exit, stall, timeout | None in the verified run |

The car starts on the lower straight, travels around the right side and upper
mission area, passes the visible cube, follows the upper straight and outer
left section, turns through the lower-left hairpin and inner bends, and crosses
the start line moving in its original direction. The supplied script's reverse
recovery remains enabled and was used in tight sections. This is a complete
simulated circuit, not a claim of a forward-only or physical-vehicle lap.

The run directory contains `result.json`, `run_manifest.json`, `run.log`,
`trajectory.jsonl`, `commands.jsonl`, `controller_log.jsonl`, `frames.jsonl`,
all three continuous camera streams as lossless PNGs under `frames/`,
`trajectory.png`, `road_coverage.json`, and `lap_replay.gif`.

The manifest's SHA-256 values match the current active controller,
`scripts/main.gd`, `calibration.json`, and `scenes/course_assembly.tscn`.
Road coverage is independently sampled from the recorded trajectory against
the actual panel textures, placement, and rotations; it is not used to steer.
The trajectory image also shows the complete route inside the painted course.

The structural/dimension regression check passed with 41 panels at 900 mm,
16 panel types, three 640 x 400 cameras, and 409 LiDAR rays. It additionally
checks camera/chassis visibility separation, off-axis projection without
translating the optical center, camera motion synchronization, and ramp pitch
being absent from the flat upper straight.

See `CAMERA_RECONCILIATION.md` for the reproduced blackout cause and
`CONTROLLER_CHANGES.md` for changes from the preserved pasted controller.

To repeat the recorded verification:

```powershell
& 'C:\dev\Godot_Installations\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --path C:\dev\jajucha-simulator --script res://scripts/run_lap_monitor.gd
```

To open a visible live run with the controller already started:

```powershell
& 'C:\dev\Godot_Installations\4.7.2-stable\Godot_v4.7.2-stable_win64.exe' --path C:\dev\jajucha-simulator --script res://scripts/run_with_supplied_controller.gd
```

## Fresh release-candidate run (2026-10-26)

The supplied controller completed another local run under Godot 4.7.2-stable.
The monitor reported `LAP_SUCCESS`, all seven ordered checkpoints, 32.253 m
travel, 92.025 s simulation time, and a forward start-line crossing 42.5 mm
forward and 25.3 mm lateral from the line. Final heading error was 3.00°.
The run output is under the ignored
`.cache/release-lap/evidence/laps/run_20261026T070207/` directory. The lap
monitor's independent artwork sampler checked 760 trajectory samples: zero
centerline samples off-road and zero vehicle-footprint samples touching grass
or red curb. This was a source-development run using local Python 3.12.4; it
does not verify the packaged Python 3.12.15 runtime or an installed
application.

## Historical bundled-runtime source run (2026-10-26)

Historical run: `build/release-candidate/node-lap-windowed/evidence/laps/run_20261026T083238/`. Its recorded `main.gd` SHA-256 is `c3700d55bc210b279004a98d55b86d0041fe129ed2020c3762732d717a9a0f88`, which differs from the current source. It is not evidence that the current simulator passes.

| Check | Measured evidence |
| --- | --- |
| Result | `LAP_SUCCESS`, exit 0 |
| Runtime | Bundled CPython 3.12.15, Godot 4.7.2-stable, visible renderer |
| Elapsed simulation time | 91.675 s |
| Distance traveled | 32.146 m |
| Ordered course checkpoints | 7 of 7 |
| Finish | Forward crossing of the start line |
| Forward distance at crossing | 21.3 mm |
| Lateral error at crossing | 5.2 mm |
| Heading error at crossing | 3.486 degrees |
| Motor commands | 694 |
| Recorded trajectory samples | 718 |
| Centerline samples off road | 0 |
| Footprint samples touching grass or red curb | 0 |

The manifest records controller SHA-256
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`,
main script SHA-256
`c3700d55bc210b279004a98d55b86d0041fe129ed2020c3762732d717a9a0f88`, and
the course/calibration hashes. Continuous frame capture was disabled for this
run to limit release-test disk use; the simulator cameras and sensor stream
remained active, and the monitor retained periodic camera snapshots plus the
full trajectory and independent artwork-coverage report. This verifies the
bundled runtime in a source checkout. It does not replace a fresh-profile
installed-app test.

## Setup-installed candidate attempts (2026-10-26)

The exact Velopack Setup artifact was installed into temporary directories on
C: and its bundled app was run with the unchanged supplied controller. Three
attempts stalled, including a run from the current Setup artifact, so the
installed lap gate is not passed:

| Run | Result | Checkpoints | Distance | Stop location |
| --- | --- | ---: | ---: | --- |
| `build/release-candidate/installed-lap-direct/evidence/laps/run_20261026T084105/` | `LAP_STALLED` | 2 of 7 | 13.806 m | x=1.654, z=-1.162 m |
| `build/release-candidate/installed-lap-retry/evidence/laps/run_20261026T084219/` | `LAP_STALLED` | 0 of 7 | 5.824 m | x=4.795, z=2.623 m |
| `build/release-candidate/installed-final-data/evidence/laps/run_20261026T090215/` | `LAP_STALLED` | 2 of 7 | 13.685 m | x=1.682, z=-1.158 m |
| `release/evidence/installed-lap-2026-10-26/` | `LAP_STALLED` | 2 of 7 | 13.607 m | x=1.709, z=-1.073 m |

The latest run came from Setup artifact SHA-256
`7498741c2bfb091fd8634efa3f99b27a802ec376ea25263fad9018fa1a1d7efd`. Its
manifest confirms the unchanged controller hash
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`. The
independent road sampler checked 433 trajectory poses: zero centerline samples
were off road and zero vehicle-footprint samples touched grass or red curb,
despite the incomplete lap.

These results are recorded to keep the release report accurate. The controller
file was not changed. The source-export bundled-runtime run remains a separate
success; it does not override either installed result.


## Current notebook-path source replay (2026-10-26)

The current source completed the unchanged controller through the bundled
CPython 3.12.15 IPython notebook kernel, using Godot 4.7.2-stable. It passed
all seven ordered checkpoints, traveled 33.082 m, and crossed the start line
forward 37.2 mm beyond it, with 47.0 mm lateral error and 0.622 degrees of
heading error. The run issued 746 motor commands over 100.8 seconds of
simulation time. Independent artwork coverage checked 811 trajectory samples:
zero centerline samples were off-road and zero vehicle-footprint samples
touched grass or red curb.

The exact single Python code cell in `notebooks/Verified_Lap_Controller.ipynb`
is byte-for-byte identical to
`python_bridge/user_supplied_controller.py` (SHA-256
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`). The
monitor currently reads the unchanged supplied source file; the identity check
confirms the notebook cell being shipped is the same program. The run manifest
records current `main.gd` SHA-256
`aea3b778bade535baf9c20c03c81f4c66e4b6b2466fdd9bf9edbbc47793b467d` and
execution backend `bundled IPython notebook kernel`.

Machine-readable evidence (result, road coverage, manifest, logs, commands,
and trajectory; camera recordings omitted) is in
`release/evidence/current-notebook-lap-2026-10-26/`. Earlier current-source and
installed failures documented above came from older builds and do not replace
this source pass.

### Exact Setup diagnostic before the connection fix

Setup SHA-256
`4e675d867273f14d32fcad120c8b5ecd76930f50899f38334f2181a9ec69420f`
installed and launched successfully, but its lap stopped at 18.035 m after
three checkpoints. The controller log identifies `WinError 10048` while the
bridge tried to open another TCP socket for a motor command. This was simulator
RPC connection churn; the supplied controller still has SHA-256
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`. The
bridge now reuses one authenticated connection and the bundled host suite
passes a 500-command regression case. A new Setup build and installed replay
were then completed as described below.

### Exact Setup pass after the connection fix

The rebuilt Setup artifact, SHA-256
`4da5b5ca0b123859c547128c8e8075468db9dbbbb98577cee273a945f511cd15`, was
installed into an isolated C: folder and completed the same notebook-path lap
with the unchanged supplied controller. It passed all seven ordered gates,
traveled 34.281 m, and crossed the start line forward by 6.6 mm, with 37.5 mm
lateral error and 7.927 degrees heading error. The run took 110.3 seconds of
simulation time and issued 780 motor commands. Independent artwork coverage
checked 840 trajectory samples: zero centerline samples were off road and zero
vehicle-footprint samples touched grass or red curb.

The run manifest confirms the bundled IPython notebook kernel and controller
SHA-256 `71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`.
The complete camera capture is retained at
`%LOCALAPPDATA%\JajuchaGodotSimulatorData\evidence\laps\run_20261026T100518`
with 448 PNG images. Compact machine-readable evidence, excluding camera
recordings, is in `release/evidence/installed-notebook-lap-2026-10-26/`.

## Latest fully tested Setup candidate (2026-10-26): failed lap gate

The exact Setup artifact SHA-256
`8d48b67a09e974b250684dc84031bfb8f747fe84ddb4eb439d4769098ebca99b` installed
successfully into an isolated C: location. Its lap used the supplied
controller unchanged: the packaged notebook cell is byte-for-byte identical
to the source, SHA-256
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`. It
stalled after two of seven checkpoints and 13.426 m, at `(x=1.621, z=-1.267)`
with yaw 118.10°. The independent sampler checked 440 poses; the center and
vehicle footprint remained on the road, but the car did not finish. This
candidate **fails the release lap gate**.

The same exact installed candidate passed its 7/7 structural self-test, 5/5
bundled Python host tests, control/kernel shutdown test, and 24 reported
notebook UI checks. Velopack uninstall and reinstall both exited successfully,
and isolated notebook and local-data sentinels remained byte-identical.
Compact evidence is in
`release/evidence/installed-original-controller-2026-10-26/`.

An additional source run confirmed the lap monitor can load the first code cell
from the actual `.ipynb` and record its hash. That source run temporarily used
a corridor-threshold experiment and stalled after one checkpoint; it is not
evidence that the exact supplied controller passes. The monitor change has not
yet been built into and verified from a new Setup artifact.

The earlier `4da5b5...` Setup pass above remains historical evidence for that
exact older track build. It does not replace the latest candidate's failure.

## Newest installed Setup candidate (2026-10-26): failed lap gate

Setup SHA-256 `1b1bbd2400c7b5ce8965630b3bff7931739c3639aaadc8158077a52894b7c762` stalled after 2 of 7 ordered gates and 13.765 m at `(x=1.642, z=-1.024)`. The run manifest records the unchanged supplied controller hash `71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`. Road coverage sampled 466 poses; no vehicle footprint touched grass or curb, but the lap did not finish.

This installed candidate passed its 7/7 structural checks, 5/5 bundled-host tests, control/shutdown checks, and notebook workspace end-to-end checks. It remains unqualified for release because full-lap completion and other gates are still open. Evidence: `release/evidence/installed-notebook-cell-2026-10-26/`.

The earlier `4da5b5...` full lap remains evidence for its older track build only; this newer candidate supersedes it for release readiness.

## Current installed Setup repeatability (2026-10-26)

Current Setup SHA-256:
`8bf34026f44954a0555b8d02dcb6475fd1c196ec8c9446f503489079be7b8edd`.
It contains the unchanged supplied controller (SHA-256
`71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`), a
20 Hz sensor sample cadence, and a simulation-only 35 degree steering tune.

Two runs were made from the same installed Setup. The first passed all seven
ordered gates in 33.634 m; 870 trajectory samples showed no off-road or
red-curb footprint. The repeat stalled after five gates at 27.236 m; 769
samples likewise showed no off-road or curb contact. On the failed run the
controller repeatedly reported `경로 못 찾음` at the lower-left hairpin exit;
its BEV free-space mask had no valid corridor close to the vehicle. It issued
zero motor commands and then repeated its configured reverse recovery without
regaining a path. This candidate is therefore not qualified for a full-lap
release gate despite the one successful run.

Full camera captures and raw run files are preserved at
`build/release-candidate-steering35-20hz/test-user-profile/lap-data/evidence/laps/run_20261026T125230/`
and
`build/release-candidate-steering35-20hz/test-user-profile/repeat2-data/evidence/laps/run_20261026T125434/`.
Compact copies are under
`release/evidence/installed-steering35-20hz-2026-10-26/`.

A separate source-only test kept the current 20 Hz cadence and 35 degree
steering tune but reduced the simulator speed cap to 0.40 m/s. The first run
passed all seven gates (33.119 m; 845 coverage samples and zero grass/curb
contacts); the repeat stalled after two gates at 14.061 m. The speed change is
not adopted because it did not make the controller repeatable. Results and
compact evidence are in `release/evidence/steering-tuning-2026-10-26/speed040-source/`;
full camera captures remain in the two source run folders listed there.

## Latest exact installed candidate: lower-left hairpin stall (2026-10-26)

Setup SHA-256: `ad037d946b75e6b17773ee3db6b9f3bbb6a7504d42f44618f79dd7eb939523eb`.

The installed Setup reached five of seven ordered gates and stalled at 26.329 m near the lower-left hairpin exit. It remained at the same pose with zero speed through the remaining run. Commands around the stall oscillated through large steering changes and forward, reverse, and zero speeds. The run did not reach the final two gates or cross the start line. Independent road coverage checked 687 trajectory samples and found zero centerline off-road samples and zero vehicle-footprint grass or curb contacts. The supplied controller was unchanged (SHA-256 `71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`). This is a controller route-following/recovery failure and the candidate fails the lap release gate.

The same exact Setup passed structural 7/7, notebook-host 5/5, notebook UI E2E, and control/shutdown checks. Compact evidence is in `release/evidence/package-candidate-notebook-fix-2026-10-26/`. Full camera output is preserved at `build/release-candidate-notebook-completion/installed-test-data/lap1/evidence/laps/run_20261026T132340/`.
