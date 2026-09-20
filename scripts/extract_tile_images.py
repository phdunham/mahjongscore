#!/usr/bin/env python3
"""Crop the 42 tile photos out of the scanned cheat sheet.

Usage:
    python3 scripts/extract_tile_images.py <cheat_sheet.png> [--contact out.png]

Writes Sources/MahjongUI/Resources/Tiles/tile-<notation>.jpg (300 px wide).

The sheet has text labels ("West", "Blue Flowers", ...) printed over the lower
edge of the wind, dragon, and flower tiles. Labels are pure white boxes (the
scanned tile face is off-white), so they are detected per tile and covered,
from the label's top edge down, with a blank-tile template. The template is
built from the 27 suit tiles: artwork is always darker than the tile face, so
a high per-pixel percentile across tiles leaves just the face, with its real
edge shading and rounded corners. It is tone-matched to each tile before use.

Tile boxes are fixed pixel coordinates in the 7200x5314 scan, measured from
the dark seams between tiles.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None

OUT_DIR = Path(__file__).resolve().parent.parent / "Sources/MahjongUI/Resources/Tiles"
OUT_SIZE = (300, 408)     # every tile is normalised to this
WORK_SIZE = (600, 816)    # patching happens at 2x, then downsampled
INSET = 10  # px trimmed from every side to drop the seam shadow

SUIT_COLS = [(940, 1547), (1575, 2191), (2218, 2838), (2863, 3485), (3511, 4135),
             (4156, 4781), (4805, 5424), (5451, 6077), (6104, 6707)]
SUIT_ROWS = {"m": (492, 1326), "s": (1346, 2184), "p": (2204, 3040)}

WIND_ROW = (3066, 3878)
# Sheet order is West, South, East, North.
WIND_COLS = {"Ww": (950, 1565), "Sw": (1583, 2211), "Ew": (2227, 2857), "Nw": (2876, 3492)}

DRAGON_ROW = (3928, 4766)
# Sheet order is White, Red, Green.
DRAGON_COLS = {"Wd": (1614, 2236), "Rd": (2250, 2883), "Gd": (2902, 3504)}

FLOWER_COLS = [(4159, 4787), (4802, 5431), (5450, 6081), (6102, 6702)]
SEASON_ROW = (3066, 3878)   # "Blue flowers" 1-4 = 春夏秋冬 = 1f-4f
PLANT_ROW = (3928, 4766)    # "Red flowers" 1-4 = 梅蘭菊竹 = 5f-8f


def tile_boxes():
    boxes = {}
    for suit, (y0, y1) in SUIT_ROWS.items():
        for rank, (x0, x1) in enumerate(SUIT_COLS, start=1):
            boxes[f"{rank}{suit}"] = (x0, y0, x1, y1)
    for name, (x0, x1) in WIND_COLS.items():
        boxes[name] = (x0, WIND_ROW[0], x1, WIND_ROW[1])
    for name, (x0, x1) in DRAGON_COLS.items():
        boxes[name] = (x0, DRAGON_ROW[0], x1, DRAGON_ROW[1])
    for i, (x0, x1) in enumerate(FLOWER_COLS, start=1):
        boxes[f"{i}f"] = (x0, SEASON_ROW[0], x1, SEASON_ROW[1])
        boxes[f"{i + 4}f"] = (x0, PLANT_ROW[0], x1, PLANT_ROW[1])
    return boxes


def blank_template(suit_tiles: list[Image.Image]) -> np.ndarray:
    """A clean, art-free tile face: 80th-percentile per pixel across suit tiles."""
    stack = np.stack([np.asarray(t, dtype=np.float32) for t in suit_tiles])
    return np.percentile(stack, 80, axis=0)


def label_rect(tile: Image.Image):
    """Bounding box (x0, top, x1) of a pure-white label in the lower half, or None."""
    a = np.asarray(tile).astype(np.int16)
    h, w, _ = a.shape
    pure = a.min(axis=2) >= 251
    rows = np.where(pure[h // 2:, :].mean(axis=1) > 0.12)[0]
    if len(rows) < 20:
        return None
    top = h // 2 + int(rows[0])
    cols = np.where(pure[top:, :].mean(axis=0) > 0.25)[0]
    if len(cols) == 0:
        return None
    return max(0, int(cols[0]) - 12), max(0, top - 12), min(w, int(cols[-1]) + 12)


def paint_out_label(tile: Image.Image, template: np.ndarray) -> tuple[Image.Image, bool]:
    rect = label_rect(tile)
    if rect is None:
        return tile, False
    x0, top, x1 = rect
    a = np.asarray(tile, dtype=np.float32)
    h, w, _ = a.shape

    # Tone-match the template to this tile using face-like pixels (bright,
    # unsaturated, not label-white) in a ring hugging the patch: the band
    # just above it, plus whatever tile is visible to its left and right.
    ring = np.zeros((h, w), dtype=bool)
    ring[max(0, top - 50):top, x0:x1] = True
    ring[top:, max(0, x0 - 50):x0] = True
    ring[top:, x1:min(w, x1 + 50)] = True
    lo, hi = a.min(axis=2), a.max(axis=2)
    face = ring & (lo > 150) & (hi - lo < 30) & (lo < 251)
    gain = np.ones(3, dtype=np.float32)
    if face.sum() > 300:
        gain = np.median(a[face], axis=0) / np.median(template[face], axis=0)
    fill = np.clip(template * gain, 0, 255)

    out = a.copy()
    out[top:, x0:x1] = fill[top:, x0:x1]
    patched = Image.fromarray(out.astype(np.uint8))
    mask = Image.new("L", (w, h), 0)
    mask.paste(255, (x0, top, x1, h))
    mask = mask.filter(ImageFilter.GaussianBlur(14))
    return Image.composite(patched, tile, mask), True


def mirror_top_over_label(tile: Image.Image) -> Image.Image:
    rect = label_rect(tile)
    if rect is None:
        return tile
    _, top, _ = rect
    a = np.asarray(tile)
    out = a.copy()
    out[top:] = a[::-1][top:]          # row y takes the pixels of row (h-1-y)
    mirrored = Image.fromarray(out)
    mask = Image.new("L", tile.size, 0)
    mask.paste(255, (0, top, tile.width, tile.height))
    return Image.composite(mirrored, tile, mask.filter(ImageFilter.GaussianBlur(6)))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sheet = Image.open(sys.argv[1]).convert("RGB")
    contact_path = None
    if "--contact" in sys.argv:
        contact_path = sys.argv[sys.argv.index("--contact") + 1]

    crops = {}
    for name, (x0, y0, x1, y1) in tile_boxes().items():
        crop = sheet.crop((x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET))
        crops[name] = crop.resize(WORK_SIZE, Image.LANCZOS)

    template = blank_template([crops[f"{r}{s}"] for s in "msp" for r in range(1, 10)])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tiles = {}
    for name, crop in crops.items():
        if name == "Wd":
            # The label hides the bottom edge of the White dragon's frame.
            # The frame is vertically symmetric, so rebuild it from the top.
            crop, patched = mirror_top_over_label(crop), True
        else:
            crop, patched = paint_out_label(crop, template)
        crop = crop.resize(OUT_SIZE, Image.LANCZOS)
        crop.save(OUT_DIR / f"tile-{name}.jpg", quality=88)
        tiles[name] = crop
        if patched:
            print(f"{name}: label painted out")
    print(f"wrote {len(tiles)} tiles to {OUT_DIR}")

    if contact_path:
        order = ([f"{r}{s}" for s in "msp" for r in range(1, 10)]
                 + ["Ew", "Sw", "Ww", "Nw", "Rd", "Gd", "Wd"]
                 + [f"{i}f" for i in range(1, 9)])
        cw, ch = 150, 205
        sheet_img = Image.new("RGB", (9 * cw, 5 * ch), (60, 60, 60))
        for i, name in enumerate(order):
            row, col = (i // 9, i % 9) if i < 27 else ((3, i - 27) if i < 34 else (4, i - 34))
            sheet_img.paste(tiles[name].resize((cw - 6, ch - 6)), (col * cw + 3, row * ch + 3))
        sheet_img.save(contact_path)
        print("contact sheet:", contact_path)


if __name__ == "__main__":
    main()
