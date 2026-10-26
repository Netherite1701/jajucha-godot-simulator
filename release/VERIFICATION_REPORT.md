# Jajucha Godot Simulator v0.1.0 — Verification report

Status: **Windows x64 package built and installed for verification.** The exact Setup below was installed and exercised from an isolated C: location. Its SHA-256 is `ad037d946b75e6b17773ee3db6b9f3bbb6a7504d42f44618f79dd7eb939523eb` (203,772,790 bytes).

## Verified on this exact Setup

- Packaged structural self-test: 7/7.
- Bundled CPython notebook host suite: 5/5.
- Notebook UI E2E: passed, including persistent variables, recovery, save/reload, stdin, images, cancellation, restart, completion, and Korean text.
- Controls and shutdown: passed, including editor input isolation, F8 emergency stop, queue clearing, and host/kernel shutdown.
- The installer installed and launched from the isolated C: directory.
- Lap road coverage: 687 samples, zero centerline off-road samples and zero footprint touches of grass or red curb.

## Bundled controller result

The supplied controller is included unchanged (SHA-256 `71bef94864c91d1286ed586d216938e21750335bf23747c852f36b83de726136`). Its installed lap check stopped after 5 of 7 checkpoints at 26.329 m near the lower-left hairpin exit. It did not crash or leave the road; the controller stopped finding a path and did not finish. The release makes no full-lap claim for that sample controller. The simulator and notebook features passed their separate checks above.

Compact test evidence is in `evidence/installed-verification-2026-10-26/`. The full camera capture is retained locally and omitted from this release bundle.

## Remaining external qualification items

- A separate clean Windows account, standard-user profile, and offline first launch were not verified.
- Data preservation through uninstall/reinstall was not repeated on this exact Setup.
- Two-version updater recovery remains untested; the repository has just been created and has no prior published version.
- Redistribution permission for the original manual-derived track artwork is not documented.
- The target public repository has been created. This report records qualification state before the release assets are published.

The package and checksums are in this `v0.1.0` folder. See `qualification.json` for the exact gate status.

