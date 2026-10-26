"""Extract the 41 full-size 900 mm panel artworks from the supplied assembly plan."""
from __future__ import annotations

from collections import Counter
from pathlib import Path

import cv2
import fitz
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
DEST = ROOT / "assets" / "panels"
PDF = next(DOCS.glob("*트랙 제작 매뉴얼*.pdf"))
MAP = (
    "GAAAFFNPPQ.",
    "A.....QPPO.",
    "ALBK.....JI",
    "CDJK......B",
    "DDJK......A",
    "JJ.HDDAMAAM",
)
EXPECTED = {
    "A": 9, "B": 2, "C": 1, "D": 5, "F": 2, "G": 1, "H": 1,
    "I": 1, "J": 5, "K": 3, "L": 1, "M": 2, "N": 1, "O": 1,
    "P": 4, "Q": 2,
}


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    document = fitz.open(PDF)
    page = document[1]
    scale = 3.0
    rendered = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=False)
    sheet = Image.frombytes("RGB", (rendered.width, rendered.height), rendered.samples)

    # Page 2's printed 11 x 6 assembly is cropped at its visible panel-grid
    # bounds. The 2x source-render coordinates below are scaled to 3x.
    x0, y0 = 136.0, 181.0
    cell_2x = 128.1
    crop_margin_2x = 4.0  # trim the assembly's white cell separators
    counts: Counter[str] = Counter()
    generated_letters: set[str] = set()
    for row, letters in enumerate(MAP):
        for column, letter in enumerate(letters):
            if letter == ".":
                continue
            counts[letter] += 1
            # The first occurrence of each type is the canonical, unrotated
            # artwork. Later occurrences are represented by GridMap rotations.
            if letter in generated_letters:
                continue
            generated_letters.add(letter)
            left = round((x0 + column * cell_2x + crop_margin_2x) * scale / 2.0)
            top = round((y0 + row * cell_2x + crop_margin_2x) * scale / 2.0)
            right = round((x0 + (column + 1) * cell_2x - crop_margin_2x) * scale / 2.0)
            bottom = round((y0 + (row + 1) * cell_2x - crop_margin_2x) * scale / 2.0)
            rgb = np.array(sheet.crop((left, top, right, bottom)).resize((500, 500), Image.Resampling.LANCZOS), copy=True)
            # The page's panel-table outline survives the crop on some cell
            # edges. Extend the neighboring artwork over those thin gutters.
            edge_width = 3
            for side in ("left", "right", "top", "bottom"):
                edge = {
                    "left": rgb[:, :edge_width],
                    "right": rgb[:, -edge_width:],
                    "top": rgb[:edge_width, :],
                    "bottom": rgb[-edge_width:, :],
                }[side]
                edge_gray = cv2.cvtColor(edge, cv2.COLOR_RGB2GRAY)
                active = edge_gray.mean(axis=1 if side in ("left", "right") else 0) > 90
                if float(active.mean()) > 0.90:
                    if side == "left":
                        rgb[:, :edge_width] = rgb[:, edge_width:edge_width + 1]
                    elif side == "right":
                        rgb[:, -edge_width:] = rgb[:, -edge_width - 1:-edge_width]
                    elif side == "top":
                        rgb[:edge_width, :] = rgb[edge_width:edge_width + 1, :]
                    else:
                        rgb[-edge_width:, :] = rgb[-edge_width - 1:-edge_width, :]
            # The assembly drawing overlays a panel ID and drop shadow on
            # each road piece. Replace the centered editorial mark with local
            # asphalt so the in-simulator road has no tile lettering.
            gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
            mask = np.zeros((500, 500), dtype=np.uint8)
            center = gray[170:330, 170:330]
            mask[170:330, 170:330] = np.where(center >= 220, 255, 0).astype(np.uint8)
            mask = cv2.dilate(mask, np.ones((15, 15), dtype=np.uint8), iterations=1)
            sample = rgb[170:330, 170:330][mask[170:330, 170:330] == 0]
            asphalt = np.median(sample, axis=0).astype(np.uint8)
            cleaned = rgb.copy()
            cleaned[mask > 0] = asphalt
            output = DEST / f"{letter}.png"
            Image.fromarray(cleaned).save(output, optimize=True)
    if sum(counts.values()) != 41:
        raise SystemExit(f"Assembly diagram has {sum(counts.values())} occupied panels, expected 41: {counts}")
    if counts != Counter(EXPECTED):
        raise SystemExit(f"Assembly panel counts differ from the manual inventory: {counts}")
    print("Extracted 16 unique panel textures from the manual assembly page.")


if __name__ == "__main__":
    main()
