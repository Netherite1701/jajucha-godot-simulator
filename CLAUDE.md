# CLAUDE.md

Guide for AI coding agents working in this repository.

## Orientation
- `docs/REPO_MAP.md`: what every top-level folder is, what's tracked, and what's local-only and regenerable.
- `README.md`: install, source development, project layout.
- Core simulation: `scripts/main.gd` (world, vehicle, sensors, notebook bridge). Track data: `scripts/course_data.gd`. Notebook API: `python_bridge/jchm.py`. Parameters: `calibration.json`.

## Manuals: read the digest, never the PDFs
- `docs/manual/` is a page-cited English digest of the official Korean documents (car manual, 2026 competition manual, track build manual, track summary, signs). Start at `docs/manual/README.md`.
- The PDFs aren't in the repo. Don't search for or open them. If a fact is missing from the digest, say so instead of guessing.
- **The car manual is ground truth** for vehicle facts: steering 2° per unit, ±10 units per front wheel, independent servos; 65 mm wheels; 5.13 cm/s per speed unit. Measurements and tuning fill gaps the manual leaves; they never override it. See "Where the simulator differs" in `docs/manual/README.md`.
- Cite simulator code by function name or `calibration.json` key, not by line number.

## Checks
`$GODOT` = the Godot 4.7.2 console executable.

```
$GODOT --headless --path . --script res://tests/smoke_test.gd
python tests/notebook_host_smoke.py -v
```

The full camera lap monitor (`res://scripts/run_lap_monitor.gd`) needs the normal renderer, not `--headless`.

## Working rules
- Use cheaper subagents (Haiku/Sonnet) for bulk work: reading many pages, inventories, mechanical edits, first drafts. Keep the main model for decisions and review.
- Never stage or commit someone's uncommitted work-in-progress without asking. Check `git status` first and stage files by explicit path.
- `release/v0.1.0/` is the frozen published record. CI reads `release/qualification.json`, `release/versions.json` and `docs/RELEASE_NOTES_0.1.0.md`.
- `release/evidence-archive/`, `build/` and `.cache/` are local-only. Don't cite new files there from tracked docs without saying they're local-only.
- `python_bridge/user_supplied_original.txt` is local-only and must not be published.
