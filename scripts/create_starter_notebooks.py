"""Create checked-in starter notebooks from the authoritative controller source."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "notebooks"


def markdown(text: str) -> dict:
    return {"cell_type": "markdown", "metadata": {}, "source": text.splitlines(keepends=True)}


def code(text: str) -> dict:
    return {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": text.splitlines(keepends=True)}


def save(name: str, cells: list[dict]) -> None:
    document = {
        "cells": cells,
        "metadata": {
            "kernelspec": {"display_name": "Python 3 (Jajucha Simulator)", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.12.15"},
        },
        "nbformat": 4,
        "nbformat_minor": 5,
    }
    (OUT / name).write_text(json.dumps(document, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    save("Getting_Started.ipynb", [
        markdown("# Jajucha Simulator API\n\nThis local notebook controls the simulator only. It does not connect to a physical car. Cells run only when you choose **Run cell** or **Run all**.\n"),
        markdown("## Read a camera image\n\nEach camera image is a 640 × 400 BGR NumPy array. This first call waits for a fresh simulator frame.\n"),
        code("from jchm import camera\nimport cv2\n\nimage = camera.get_image('center')\nprint(image.shape, image.dtype)\ncamera.show_image(image)\n"),
        markdown("## LiDAR and motor units\n\nLiDAR angles are degrees, ranges are millimetres. The motor API uses the same controller convention as the supplied Jajucha script. Start at low speed and keep Emergency stop (F8) available.\n"),
        code("from jchm import lidar, control\n\nangles_deg, ranges_mm = lidar.get_lidar()\nprint(len(angles_deg), 'rays')\nlidar.show_lidar(angles_deg, ranges_mm)\n\n# Example low-speed command: left servo, right servo, motor\n# control.set_motor(0, 0, 2)\n"),
    ])
    controller_path = ROOT / "python_bridge" / "user_supplied_controller.py"
    controller = controller_path.read_text(encoding="utf-8")
    verified_controller_path = ROOT / "python_bridge" / "verified_lap_controller.py"
    verified_controller = verified_controller_path.read_text(encoding="utf-8")
    save("User_Supplied_Controller.ipynb", [
        markdown("# User Supplied Controller\n\nThis notebook contains the supplied controller without edits. It is a continuous driving loop and may not complete the simulator's full track. Run only when ready; stop with **Stop** or **F8 Emergency stop**.\n"),
        code(controller),
    ])
    save("Verified_Lap_Controller.ipynb", [
        markdown("# Supplied Lap Controller Sample\n\nThis notebook is a separate copy of the user-supplied controller. The simulator is ready, but this controller is not certified to complete the full track. Run it as an editable example only; stop it with **Stop** or global **F8 Emergency stop**.\n"),
        code(verified_controller),
    ])


if __name__ == "__main__":
    main()
