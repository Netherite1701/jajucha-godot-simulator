"""Copy installed distribution license files into a release staging folder."""
from __future__ import annotations

import importlib.metadata
import re
import shutil
import sys
from pathlib import Path


def safe_name(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: write_runtime_licenses.py DESTINATION")
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    for distribution in importlib.metadata.distributions():
        name = distribution.metadata.get("Name", "unknown")
        candidates = []
        for item in distribution.files or []:
            base = Path(item.name).name.lower()
            if base in {"license", "license.txt", "license.md", "copying", "notice", "notice.txt"}:
                source = Path(distribution.locate_file(item))
                if source.is_file():
                    candidates.append(source)
        if not candidates:
            continue
        package_dir = destination / safe_name(name)
        package_dir.mkdir(exist_ok=True)
        for number, source in enumerate(candidates):
            target_name = source.name if number == 0 else f"{number}-{source.name}"
            shutil.copy2(source, package_dir / target_name)


if __name__ == "__main__":
    main()
