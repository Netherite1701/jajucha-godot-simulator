# Jajucha Godot Simulator 0.1.0

- Windows 10/11 x64 simulator with the 41-tile competition track and three calibrated-resolution camera feeds.
- In-app Python notebook cells with persistent IPython state, standard `.ipynb` save/open, recovery autosave, and a bundled `jchm` camera, LiDAR, and control API.
- Separate kernel process, loopback authentication, interruption, and a global F8 emergency stop.
- Sensor, display, and motor calls reuse the authenticated loopback session during long notebook runs.
- Per-user installation and user-approved stable updates through GitHub Releases.
- No Godot or system Python installation is required.

This first build is unsigned. See `INSTALLATION.md` and `THIRD_PARTY_NOTICES.md` before installing or redistributing it.


## Known limitations

- The supplied lap-controller sample stopped at 5 of 7 checkpoints in the installed run; the simulator itself completed the structural, notebook, and control checks listed in VERIFICATION_REPORT.md.
- Fresh-profile/offline installation and two-version update recovery have not yet been verified.
- This first release is unsigned and includes manual-derived panel artwork whose redistribution terms are undocumented.

