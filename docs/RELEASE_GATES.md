# v0.1.0 release gates

The v0.1.0 release must not be published as stable until every gate below has
written evidence. The CI release workflow validates a built artifact and then
publishes that same artifact; it does not rebuild during publication.

## Required evidence

- [ ] Godot 4.7.2 Windows x64 export template installed and release export succeeds.
- [ ] Python 3.12.15 is built from its official source archive with the pinned
  SHA-256; `requirements.lock` hashes are enforced.
- [ ] Launcher, Velopack installer/feed, dependency notices, and checksums are built.
- [ ] Notebook smoke suite passes: state, execution order, cancellation,
  infinite-loop interruption, errors, stdin, images, Korean, filenames,
  save/reload, autosave recovery, and restart.
- [ ] Editor typing cannot actuate or reset the vehicle; F8 works during a
  hung kernel; child kernel exits with the app.
- [ ] Installed app runs on a fresh Windows profile as a standard user with
  developer runtimes removed from `PATH`, including offline after download.
- [ ] Uninstall/reinstall and update preserve notebooks/settings. Exercise
  Later, approved update, corrupted/interrupted downloads, and previous-version recovery.
- [ ] Installed verified lap notebook crosses seven checkpoints and the start
  line, with zero collisions and passing road coverage.
- [ ] Windows publisher warning and SHA-256 verification guide are present.
- [ ] Public redistribution rights for every manual-derived track texture
  are documented, or those textures are replaced with original artwork.
- [ ] Publish the validated installer, Velopack feed and packages, checksums,
  release notes, install guide, and verification report to the separate
  `Netherite1701/jajucha-godot-simulator` repository.

## Current local verification

The following local checks passed on 2026-10-26:

- Godot 4.7.2 Windows x64 export completed with the matching official release
  template. The latest local output was 109,717,400 bytes. This was not an installer
  or clean-profile installation test.
- `tests/smoke_test.gd`: 41 track cells, 900 mm tiles, 16 tile types, three
  640 x 400 cameras, and 409 LiDAR rays.
- `tests/notebook_workspace_smoke.gd`: notebook save/reload, Korean text,
  no execution on open, and recovery prompt.
- `tests/notebook_storage_smoke.gd`: atomic replacement.
- `tests/control_input_smoke.gd`: keyboard controls and shortcuts are isolated
  in the Code workspace, while F8 stops motion and clears queued notebook work.
- `tests/notebook_host_smoke.py -v`: persistent kernel state, sensor API,
  text input, image output, exceptions, and interruption (3 tests).
- The exported app's `--self-test` mode passed all seven structural checks.
- The exported app's `--self-test-lap` mode ran with bundled CPython 3.12.15,
  passed all seven ordered checkpoints, crossed the start line forward, and
  recorded zero off-road center/footprint samples. Exact evidence is in
  `docs/LAP_VERIFICATION.md`.
- The exact Setup artifact installed into a temporary C: folder and passed
  the installed launcher's structural self-test. Velopack uninstall removed
  that installation; the local app-data self-test report remained byte-identical.
- The launcher compiled after the UI-thread dispatch fix. The full
  self-contained Velopack candidate, update package, portable archive, and
  checksums are in `build/release-candidate/dist/`.

The bundled CPython runtime also passed all three IPython host smoke checks.
The checked-in Windows workflow pins the Godot binaries/templates, .NET SDK,
CPython source hash, Velopack CLI, and application dependency hashes, then
uploads the package it builds as a candidate artifact. Public publishing
additionally requires every entry in `release/qualification.json` to be marked
passed with evidence.
No clean-profile standard-user install, offline first run, reinstall retention,
two-version GitHub update, or successful installed-controller lap has been
demonstrated yet.

## Current release blockers

The local Godot export template was downloaded and hash-verified, but is not
included in source control. The supplied controller has stalled in three
Setup-installed lap runs, including a run from the current Setup artifact, so
that qualification gate remains false. The
manual-derived panel texture redistribution rights have not been identified.
The public repository has now been created and the owner account authenticated.
The installed supplied-controller run still fails its full-lap gate, artwork
redistribution rights are undocumented, and clean-profile/offline and
two-version update checks remain unverified. These are still recorded as
qualification blockers in `release/qualification.json`.
