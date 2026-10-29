#!/usr/bin/env python3
"""Generates the application icons of every platform from the two sources
in assets/icon (validated by the project owner on 29 Oct 2026: motif of the
official logo, without the text, on white). Run by hand when the icon
changes (needs Pillow); the results are committed, so the CI only copies
them (tool/patch_*.py).

  python3 tool/make_app_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

SRC = Path("assets/icon/icon-1024.png")
FG = Path("assets/icon/icon-foreground-1024.png")
OUT = Path("assets/icon/generated")

ANDROID = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def resized(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def round_mask(img: Image.Image) -> Image.Image:
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def main() -> None:
    icon = Image.open(SRC).convert("RGB")
    fg = Image.open(FG).convert("RGBA")
    for name, k in ANDROID.items():
        d = OUT / "android" / f"mipmap-{name}"
        d.mkdir(parents=True, exist_ok=True)
        resized(icon, int(48 * k)).save(d / "ic_launcher.png", optimize=True)
        resized(round_mask(icon), int(48 * k)).save(d / "ic_launcher_round.png", optimize=True)
        resized(fg, int(108 * k)).save(d / "ic_launcher_foreground.png", optimize=True)
    web = OUT / "web"
    web.mkdir(parents=True, exist_ok=True)
    for s in (192, 512):
        resized(icon, s).save(web / f"Icon-{s}.png", optimize=True)
        maskable = Image.new("RGBA", (1024, 1024), (255, 255, 255, 255))
        maskable.alpha_composite(fg)
        resized(maskable.convert("RGB"), s).save(web / f"Icon-maskable-{s}.png", optimize=True)
    resized(icon, 32).save(web / "favicon.png", optimize=True)
    win = OUT / "windows"
    win.mkdir(parents=True, exist_ok=True)
    icon.save(win / "app_icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    resized(icon, 256).save(OUT / "sarcade-256.png", optimize=True)
    print(f"icons written to {OUT}")


if __name__ == "__main__":
    main()
