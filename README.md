# Jajucha Competition Simulator

The v0.1.0 assets are uploaded to a draft release while qualification checks continue. The permanent link will activate when the stable release is published.

[Download the latest Windows installer](https://github.com/Netherite1701/jajucha-godot-simulator/releases/latest/download/JajuchaGodotSimulator-win-x64-Setup.exe)

Godot 4.7.2 simulator for Windows 10/11 x64. It models the 2026 track construction manual's 41-cell GridMap and full-size 900 × 900 mm panel textures, each with 3 mm foamboard thickness. The track remains editable in `scenes/course_assembly.tscn` through the reusable mesh library.

## Install

The Windows package bundles the simulator, a private Python 3.12.15 runtime, and the locked notebook dependencies. It does not need Godot or Python on `PATH`. The first release is unsigned, so Windows may display an unknown publisher warning. See [the installation guide](docs/INSTALLATION.md).

The app includes **Drive** and **Code** workspaces. Notebook cells run only when you select Run; opening a notebook never runs its code. The kernel runs in a separate IPython process. Example notebooks are in `notebooks/`.

Save notebooks under `Documents\JajuchaSimulator\Notebooks`. Recovery data, settings, logs, and recordings are stored under `%LOCALAPPDATA%\JajuchaGodotSimulatorData`, outside the update folder.

For diagnostics, run `JajuchaGodotSimulator.exe --self-test` from PowerShell to write `evidence\self-test.json`. Run `--self-test-lap` to open the renderer-backed lap monitor; it writes the lap result and sensor recordings under the same `evidence\laps` folder. The lap check needs the normal Godot renderer because the controller reads live camera images.

## Source development

Open this folder in Godot 4.7.2 or run `launch_godot.ps1`. The toolbar's **Run controller** launches the supplied camera-only controller through a loopback `jchm` shim. Development can set `JAJUCHA_PYTHON` to a Python 3.12 executable. Installed builds use the bundled interpreter. The original pasted controller source is preserved locally as `python_bridge/user_supplied_original.txt` and is excluded from public export.

The notebook's `jchm.camera` gives BGR `uint8` images at 640 × 400; `jchm.lidar` returns degree and millimetre arrays; `jchm.control.set_motor` uses the existing controller's servo and motor convention. F8 triggers a global emergency stop. Space stops while the Drive workspace is active.

## Track and calibration

See [calibration.json](calibration.json) for the machine-readable register and [implementation notes](docs/IMPLEMENTATION_NOTES.md) for sources and limits. Dimensions are in metres. The track layout follows the manual's illustrated assembly; its type I/J inventory conflict and provisional vehicle dimensions are documented. Optical height measurements conflict (99.009 mm versus a 75 mm photo estimate); side camera extrinsics are not physically calibrated. Stereo depth is a simulator estimate, not a measurement of actual distance.

## Developer checks

Run the structural dimension check:

```powershell
& 'C:\dev\Godot_Installations\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/smoke_test.gd
```

Run notebook host tests with loopback access:

```powershell
python tests\notebook_host_smoke.py -v
```

For a full camera-recorded circuit, run:

```powershell
& 'C:\dev\Godot_Installations\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe' --path . --script res://scripts/run_lap_monitor.gd
```

The lap monitor requires all seven ordered checkpoints, more than 30 m of travel, and a forward start-line crossing within 22 cm and 30 degrees. It records sensor images and machine-readable evidence in `.cache/`, which is excluded from distribution.

## Project layout

- `scenes/main.tscn`: simulation, sensors, dashboard.
- `scenes/course_assembly.tscn`: editor-visible 41-tile GridMap.
- `scripts/notebook_workspace.gd`: in-app notebook cells and `.ipynb` files.
- `python_bridge/notebook_host.py`: authenticated session host and IPython manager.
- `python_bridge/jchm.py`: notebook-facing camera, LiDAR and control API.
- `python_bridge/run_python_controller.py`: legacy source-development controller bridge.
- `launcher/`: self-contained .NET updater shell using Velopack.
- `requirements.in` / `requirements.lock`: pinned dependency input and hashes.
- `notebooks/`: quick-start and verified-lap notebook examples.

See [verification and release gates](docs/RELEASE_GATES.md) before creating a public release. Third-party artwork and dependencies are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).


