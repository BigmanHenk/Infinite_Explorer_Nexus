"""Stitch rendered tiles around a point into one PNG for checking.

    python tools/build/preview.py z lon lat [tiles=3] [out.png]
"""
import io
import math
import sqlite3
import sys

from PIL import Image

from common import WORK, TILE_PX

z = int(sys.argv[1]); lon = float(sys.argv[2]); lat = float(sys.argv[3])
r = int(sys.argv[4]) if len(sys.argv) > 4 else 3
out = sys.argv[5] if len(sys.argv) > 5 else str(WORK / "preview.png")
n = 2 ** z
cx = int((lon + 180) / 360 * n)
s = math.sin(math.radians(lat))
cy = int((0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n)
db = sqlite3.connect(WORK / "map.sqlite")
im = Image.new("RGB", ((2 * r + 1) * TILE_PX, (2 * r + 1) * TILE_PX), (255, 0, 255))
for dy in range(-r, r + 1):
    for dx in range(-r, r + 1):
        row = db.execute("SELECT data FROM tiles WHERE z=? AND x=? AND y=?", (z, cx + dx, cy + dy)).fetchone()
        if row:
            im.paste(Image.open(io.BytesIO(row[0])).convert("RGB"), ((dx + r) * TILE_PX, (dy + r) * TILE_PX))
im.save(out)
print(out, im.size)
