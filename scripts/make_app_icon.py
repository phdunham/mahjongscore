#!/usr/bin/env python3
"""Build the app icons from the East wind tile in the cheat-sheet scan.

Usage:
    python3 scripts/make_app_icon.py <cheat_sheet.png>

Writes:
    Assets/AppIcon/AppIcon-mac-1024.png   rounded square with margin (macOS grid)
    Assets/AppIcon/AppIcon.icns           for the .app bundle (build-app.sh)
    Sources/MahjongScoreApp/Resources/AppIcon.png   512 px, Dock icon under `swift run`
    iOS/MahjongScoreiOS/Assets.xcassets/AppIcon.appiconset/   full-bleed 1024 (iOS masks it)
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_tile_images as tiles  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FELT_TOP, FELT_BOTTOM = (34, 120, 84), (16, 78, 54)


def east_wind(sheet: Image.Image, height: int) -> Image.Image:
    """The East tile, label painted out, with rounded corners, at `height` px."""
    boxes = tiles.tile_boxes()
    crop = lambda n: sheet.crop(tuple(
        v + d for v, d in zip(boxes[n], (tiles.INSET, tiles.INSET, -tiles.INSET, -tiles.INSET))
    )).resize((900, 1224), Image.LANCZOS)
    tile = mirror_top_into_label(crop("Ew"))
    tile = tile.resize((round(height * 900 / 1224), height), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", tile.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *tile.size), radius=round(height * 0.075), fill=255)
    tile.putalpha(mask)
    return tile


def mirror_top_into_label(tile: Image.Image) -> Image.Image:
    """Cover the printed label with the tile's own (blank) top edge, mirrored.

    At icon size the blank-template patch used for the in-app tiles shows as a
    faint rectangle. East's top margin is empty, so its mirror image is a
    seamless stand-in for the hidden bottom margin, real shading included.
    """
    import numpy as np
    rect = tiles.label_rect(tile)
    if rect is None:
        return tile
    x0, top, x1 = rect
    a = np.asarray(tile, dtype=np.float32)
    h, w, _ = a.shape
    flipped = a[::-1]

    # Tone-match the mirrored strip to the pixels just above the label.
    above, above_src = a[top - 40:top, x0:x1], flipped[top:top + 40, x0:x1]
    gain = np.median(above.reshape(-1, 3), axis=0) / np.median(above_src.reshape(-1, 3), axis=0)
    out = a.copy()
    out[top:, x0:x1] = np.clip(flipped[top:, x0:x1] * gain, 0, 255)

    patched = Image.fromarray(out.astype("uint8"))
    mask = Image.new("L", (w, h), 0)
    mask.paste(255, (x0, top, x1, h))
    return Image.composite(patched, tile, mask.filter(ImageFilter.GaussianBlur(18)))


def felt(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(FELT_TOP, FELT_BOTTOM))
        for x in range(size):
            px[x, y] = (*c, 255)
    return img


def place_tile(canvas: Image.Image, tile: Image.Image):
    x = (canvas.width - tile.width) // 2
    y = (canvas.height - tile.height) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (x, y + round(canvas.height * 0.018)), tile.split()[3])
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(canvas.height * 0.022)))
    canvas.alpha_composite(tile, (x, y))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sheet = Image.open(sys.argv[1]).convert("RGB")

    # macOS: 824 px rounded square centred on a transparent 1024 canvas.
    body = felt(824)
    place_tile(body, east_wind(sheet, 640))
    mask = Image.new("L", body.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 824, 824), radius=185, fill=255)
    body.putalpha(mask)
    mac = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    mac.alpha_composite(body, (100, 100))

    out = ROOT / "Assets/AppIcon"
    out.mkdir(parents=True, exist_ok=True)
    mac.save(out / "AppIcon-mac-1024.png")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for pt in (16, 32, 128, 256, 512):
            mac.resize((pt, pt), Image.LANCZOS).save(iconset / f"icon_{pt}x{pt}.png")
            mac.resize((pt * 2, pt * 2), Image.LANCZOS).save(iconset / f"icon_{pt}x{pt}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out / "AppIcon.icns")], check=True)

    res = ROOT / "Sources/MahjongScoreApp/Resources"
    res.mkdir(parents=True, exist_ok=True)
    mac.resize((512, 512), Image.LANCZOS).save(res / "AppIcon.png")

    # iOS: opaque, full-bleed, square — the system applies the corner mask.
    ios = felt(1024)
    place_tile(ios, east_wind(sheet, 760))
    appiconset = ROOT / "iOS/MahjongScoreiOS/Assets.xcassets/AppIcon.appiconset"
    appiconset.mkdir(parents=True, exist_ok=True)
    ios.convert("RGB").save(appiconset / "AppIcon-1024.png")
    (appiconset / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal",
                    "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    (appiconset.parent / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("icons written")


if __name__ == "__main__":
    main()
