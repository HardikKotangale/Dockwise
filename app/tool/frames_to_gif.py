#!/usr/bin/env python3
"""Turns the frames recorded by readme_gifs_test.dart into the GIFs in ../docs.

    cd app && flutter test tool/readme_gifs_test.dart && python3 tool/frames_to_gif.py
"""
import glob
import os
import sys

from PIL import Image

FRAMES = "build/readme_frames"
OUT = "../docs"
FPS = 15
SCENES = {
    "page-dots": "page-dots.gif",
    "summary": "summary-cards.gif",
    "clock-rotate": "clock-rotate.gif",
    "weather-pages": "weather-pages.gif",
    "music-buttons": "music-buttons.gif",
    "flip-clock": "flip-clock.gif",
    "weather-scenes": "weather-scenes.gif",
    "low-battery": "low-battery-prompt.gif",
    "timer-horse": "timer-horse.gif",
    "timer-touchdown": "timer-touchdown.gif",
    "timer-type": "timer-type.gif",
    "summary-widgets": "summary-widgets.gif",
}
# a narrower picture for the busy ones keeps the file small
WIDTHS = {"weather-scenes": 340, "weather-pages": 420, "timer-type": 400, "timer-touchdown": 400, "timer-horse": 440, "summary-widgets": 480}
WIDTH = 520  # px: small enough for a README, sharp enough to read


def build(scene: str, name: str) -> None:
    files = sorted(glob.glob(f"{FRAMES}/{scene}/*.png"))
    if not files:
        sys.exit(f"no frames for {scene}: run the recorder first")
    frames = []
    width = WIDTHS.get(scene, WIDTH)
    for f in files:
        im = Image.open(f).convert("RGB")
        h = round(im.height * width / im.width)
        frames.append(im.resize((width, h), Image.LANCZOS))
    # one shared palette keeps the file small and the colours steady
    sheet = Image.new("RGB", (width, frames[0].height * min(len(frames), 8)))
    for i, im in enumerate(frames[:: max(1, len(frames) // 8)][:8]):
        sheet.paste(im, (0, i * im.height))
    palette = sheet.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    quant = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in frames]
    path = os.path.join(OUT, name)
    quant[0].save(
        path,
        save_all=True,
        append_images=quant[1:],
        duration=round(1000 / FPS),
        loop=0,
        optimize=True,
        disposal=1,
    )
    print(f"{name}: {len(frames)} frames, {os.path.getsize(path) / 1024:.0f} KB")


if __name__ == "__main__":
    # with names (python3 tool/frames_to_gif.py timer-horse ...) only those
    only = sys.argv[1:]
    for scene, name in SCENES.items():
        if not only or scene in only:
            build(scene, name)
