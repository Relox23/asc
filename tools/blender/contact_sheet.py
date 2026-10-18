#!/usr/bin/env python3
"""Tile asset preview renders into one labelled sheet: contact_sheet.py <dir> <out.png> [cols]"""
import pathlib
import sys

from PIL import Image, ImageDraw

src = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 5
files = sorted(src.glob("*.png"))
if not files:
    sys.exit("no renders")
tile = Image.open(files[0]).size[0]
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tile, rows * (tile + 22)), (24, 24, 28))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB")
    x, y = (i % cols) * tile, (i // cols) * (tile + 22)
    sheet.paste(im, (x, y + 22))
    d.text((x + 6, y + 5), f.stem, fill=(240, 240, 240))
sheet.save(out)
print(out, len(files), "assets")
