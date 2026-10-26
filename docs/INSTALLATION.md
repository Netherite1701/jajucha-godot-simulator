# Windows installation

The release installer is named `JajuchaGodotSimulator-win-x64-Setup.exe`. It
uses Velopack's per-user Windows installation, creates a Start-menu shortcut,
and registers a regular Windows uninstall entry. Administrator access is not
required.

## Windows publisher warning

The first release is unsigned. Windows SmartScreen can display an unknown
publisher warning. Compare the installer SHA-256 with `SHA256SUMS.txt` attached
to the release before continuing. No publisher name is shown because there is
no signing certificate.

## Data locations

- Notebooks: `%USERPROFILE%\Documents\JajuchaSimulator\Notebooks`
- Settings, autosave recovery, logs, and recordings:
  `%LOCALAPPDATA%\JajuchaGodotSimulatorData`
- Installed program files: Velopack's per-user application folder under
  `%LOCALAPPDATA%`

Updates and repair do not replace user data. A normal uninstall leaves both
notebooks and the local data folder intact. Remove them yourself only if you
want to erase your work.

## Updates

The launcher is configured to check the stable GitHub feed at startup and every
six hours. Checks are also available from Setup. Updates require your approval:
**Update and restart** saves recovery data, stops the car, closes the notebook
kernel, and applies the package; **Later** keeps the current version.

The update source points to `Netherite1701/jajucha-godot-simulator`. Two-version
upgrade, recovery, and corrupted-download behavior have not yet been qualified
against a live release.

## Diagnostics

From PowerShell, run `JajuchaGodotSimulator.exe --self-test` to check the
installed track, sensors, Python executable, and starter notebooks. The JSON
report is written to `%LOCALAPPDATA%\JajuchaGodotSimulatorData\evidence`.
Run `JajuchaGodotSimulator.exe --self-test-lap` to run the supplied lap controller sample with camera rendering enabled. It records the machine-readable lap result and camera data under `evidence\laps`. In the recorded installed run the sample stopped at 5 of 7 checkpoints; it is not a successful lap example. The diagnostic takes about 90 simulated seconds and displays the simulator window while it runs.





