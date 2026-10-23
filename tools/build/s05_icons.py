"""Step 5 - app icons: the Explorer mark (Nexus hexagon with chem-arms, lighthouse over waves)
in each Nexus theme's accent on its background, one AppIcon-<THEME> set per theme (the app
switches icon with the theme) plus the default AppIcon (Twilight), and the launch colour.

    python tools/build/s05_icons.py
"""
import json
import math
import re
from pathlib import Path

import cairo

from common import ROOT

ASSETS = ROOT / "ios" / "ExplorerNexus" / "Sources" / "Assets.xcassets"
THEME_SWIFT = ROOT / "ios" / "ExplorerNexus" / "Sources" / "Common" / "Theme.swift"


def themes():
    src = THEME_SWIFT.read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'id: "(\w+)".*?primaryHex: 0x([0-9A-F]{6}).*?backgroundHex: 0x([0-9A-F]{6})', src, re.S):
        out[m.group(1)] = (m.group(2), m.group(3))
    return out


def rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def draw(path, fg, bg, size=1024):
    s = cairo.ImageSurface(cairo.FORMAT_RGB24, size, size)
    c = cairo.Context(s)
    # background: theme background with a soft glow of the accent
    c.set_source_rgb(*bg)
    c.paint()
    g = cairo.RadialGradient(size / 2, size * 0.45, 0, size / 2, size * 0.45, size * 0.62)
    g.add_color_stop_rgba(0, *fg, 0.16)
    g.add_color_stop_rgba(1, *fg, 0.0)
    c.set_source(g)
    c.paint()
    cx, cy = size / 2, size / 2
    r = size / 2.8 * 0.92
    sw = r * 0.07
    c.set_source_rgb(*fg)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.set_line_width(sw)
    for i in range(6):
        a = i * math.pi / 3 - math.pi / 2
        (c.move_to if i == 0 else c.line_to)(cx + r * math.cos(a), cy + r * math.sin(a))
    c.close_path()
    c.stroke()
    for i in (1, 3, 5):
        a = i * math.pi / 3 - math.pi / 2
        x0, y0 = cx + r * math.cos(a), cy + r * math.sin(a)
        x1, y1 = cx + r * 1.32 * math.cos(a), cy + r * 1.32 * math.sin(a)
        c.move_to(x0, y0); c.line_to(x1, y1); c.stroke()
        c.arc(x1, y1, sw * 1.6, 0, 2 * math.pi); c.fill()
    base, top = cy + r * 0.38, cy - r * 0.42
    c.set_line_width(sw * 0.9)
    c.move_to(cx - r * 0.17, base); c.line_to(cx - r * 0.10, top); c.line_to(cx + r * 0.10, top)
    c.line_to(cx + r * 0.17, base); c.close_path(); c.stroke()
    # stripes on the tower
    for k in (0.33, 0.66):
        y = top + (base - top) * k
        half = r * (0.10 + 0.07 * k)
        c.move_to(cx - half, y); c.line_to(cx + half, y); c.stroke()
    c.rectangle(cx - r * 0.08, top - r * 0.16, r * 0.16, r * 0.16); c.fill()
    c.move_to(cx - r * 0.12, top - r * 0.16); c.line_to(cx, top - r * 0.28); c.line_to(cx + r * 0.12, top - r * 0.16); c.stroke()
    c.set_source_rgba(*fg, 0.7)
    c.set_line_width(sw * 0.6)
    for side in (-1, 1):
        c.move_to(cx + side * r * 0.12, top - r * 0.08); c.line_to(cx + side * r * 0.52, top - r * 0.2); c.stroke()
    c.set_source_rgb(*fg)
    c.set_line_width(sw * 0.8)
    for k in range(2):
        y = base + r * (0.12 + k * 0.14)
        x0, x1 = cx - r * 0.5, cx + r * 0.5
        n = 4
        w = (x1 - x0) / n
        c.move_to(x0, y)
        for j in range(n):
            xa = x0 + j * w
            c.curve_to(xa + w * 0.25, y - r * 0.09, xa + w * 0.75, y - r * 0.09, xa + w, y)
        c.stroke()
    s.write_to_png(str(path))


def iconset(name, fg, bg):
    d = ASSETS / f"{name}.appiconset"
    d.mkdir(parents=True, exist_ok=True)
    draw(d / "AppIcon-1024.png", rgb(fg), rgb(bg))
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}}, indent=2))


def main():
    t = themes()
    t["NIGHT_RED"] = ("DD1800", "040000")
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    for tid, (fg, bg) in t.items():
        iconset(f"AppIcon-{tid}", fg, bg)
    iconset("AppIcon", *t["TWILIGHT"])
    lb = ASSETS / "LaunchBackground.colorset"
    lb.mkdir(exist_ok=True)
    r, g, b = (int(t["TWILIGHT"][1][i:i + 2], 16) for i in (0, 2, 4))
    (lb / "Contents.json").write_text(json.dumps({
        "colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {
            "red": f"{r / 255:.3f}", "green": f"{g / 255:.3f}", "blue": f"{b / 255:.3f}", "alpha": "1.000"}}}],
        "info": {"author": "xcode", "version": 1}}, indent=2))
    print(f"{len(t) + 1} icon sets in {ASSETS}")


if __name__ == "__main__":
    main()
