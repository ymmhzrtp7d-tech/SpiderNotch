#!/usr/bin/env python3
"""
SpiderNotch character art generator.

Draws every built-in character as an SVG (all original designs), renders its
three faces (open, blink, happy) and saves one PNG "strip" per character
(the three faces side by side) plus Library.json, the list the app reads.

    python3 make_characters.py OUTPUT_FOLDER [--only cat,dog] [--preview sheet.png]

Needs Python 3 with Pillow, and rsvg-convert (on a Mac: brew install librsvg).

To add a character: write a function like the ones below, decorate it with
@character(...), run this script, and copy the output into
SpiderNotch/Resources/Characters. The app picks it up automatically.
The art is drawn without a white sticker edge: the app adds the edge (or
not) itself, depending on the "Border" setting.
"""

import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

SIZE = 400          # each face is drawn on a 400 x 400 canvas
CX, CY, R = 200, 232, 136
FACES = ("open", "blink", "happy")

CATEGORIES = [
    ("classic", "Classic", "sparkles"),
    ("pets", "Pets", "pawprint.fill"),
    ("farm", "Farm", "leaf.fill"),
    ("forest", "Forest", "tree.fill"),
    ("wild", "Jungle & Savanna", "sun.max.fill"),
    ("water", "Water & Ice", "drop.fill"),
    ("night", "Night & Spooky", "moon.stars.fill"),
    ("fantasy", "Dinos & Fantasy", "wand.and.stars"),
]

REGISTRY = []


def character(cid, name, category):
    def wrap(fn):
        REGISTRY.append((cid, name, category, fn))
        return fn
    return wrap


# ── Tiny SVG helpers ───────────────────────────────────────────────────────

def f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def ellipse(x, y, rx, ry, fill, opacity=1.0, extra=""):
    o = "" if opacity >= 1 else f' opacity="{f(opacity)}"'
    return f'<ellipse cx="{f(x)}" cy="{f(y)}" rx="{f(rx)}" ry="{f(ry)}" fill="{fill}"{o} {extra}/>'


def circle(x, y, r, fill, opacity=1.0):
    return ellipse(x, y, r, r, fill, opacity)


def path(d, fill="none", stroke=None, width=0, opacity=1.0, cap="round", extra=""):
    s = f' stroke="{stroke}" stroke-width="{f(width)}" stroke-linecap="{cap}" stroke-linejoin="round"' if stroke else ""
    o = "" if opacity >= 1 else f' opacity="{f(opacity)}"'
    return f'<path d="{d}" fill="{fill}"{s}{o} {extra}/>'


def rotate(svg, angle, x, y):
    return f'<g transform="rotate({f(angle)} {f(x)} {f(y)})">{svg}</g>'


def mirror(svg, x=CX):
    return f'<g transform="translate({f(2 * x)} 0) scale(-1 1)">{svg}</g>'


def both(svg):
    """The shape and its mirror image (for ears, cheeks, horns...)."""
    return svg + mirror(svg)


class Art:
    """Collects one face of one character, layer by layer."""

    def __init__(self, cid, face):
        self.cid = cid
        self.face = face
        self.defs = []
        self.layers = []
        self.count = 0

    def gradient(self, light, base, dark, cx=0.36, cy=0.3, r=0.85):
        self.count += 1
        gid = f"{self.cid}{self.count}"
        self.defs.append(
            f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">'
            f'<stop offset="0" stop-color="{light}"/><stop offset="0.55" stop-color="{base}"/>'
            f'<stop offset="1" stop-color="{dark}"/></radialGradient>')
        return f"url(#{gid})"

    def add(self, *items):
        for item in items:
            if isinstance(item, (list, tuple)):
                self.add(*item)
            elif item:
                self.layers.append(item)

    def svg(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
                f'viewBox="0 0 {SIZE} {SIZE}"><defs>{"".join(self.defs)}</defs>{"".join(self.layers)}</svg>')


# ── Shared face parts ──────────────────────────────────────────────────────

INK = "#2A2236"
LIGHT_INK = "#F6F0FA"


def gloss(x=CX - 58, y=CY - 82, rx=34, ry=17, angle=-28):
    return rotate(ellipse(x, y, rx, ry, "#FFFFFF", 0.26), angle, x, y)


def head(a, colors, x=CX, y=CY, rx=R, ry=R - 8, shine=True):
    light, base, dark = colors
    a.add(ellipse(x, y, rx, ry, a.gradient(light, base, dark)))
    if shine:
        a.add(gloss(x - rx * 0.42, y - ry * 0.62, rx * 0.25, ry * 0.13))


def cheeks(a, y=CY + 44, dx=86, rx=21, ry=13, color="#FF8FB4"):
    if a.face == "happy":
        rx, ry = rx * 1.15, ry * 1.15
    g = a.gradient(color, color, color)
    a.count += 1
    gid = f"{a.cid}c{a.count}"
    a.defs.append(f'<radialGradient id="{gid}"><stop offset="0" stop-color="{color}" stop-opacity="0.85"/>'
                  f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>')
    a.add(ellipse(CX - dx, y, rx, ry, f"url(#{gid})"), ellipse(CX + dx, y, rx, ry, f"url(#{gid})"))


def eyes(a, y=CY + 4, dx=50, size=1.0, style="dark", line=INK, iris="#9BD86A"):
    for x in (CX - dx, CX + dx):
        s = size
        if a.face == "open":
            if style == "dark":
                a.add(ellipse(x, y, 14.5 * s, 18.5 * s, "#231C33"),
                      circle(x - 4.5 * s, y - 6.5 * s, 5.8 * s, "#FFFFFF"),
                      circle(x + 4.8 * s, y + 6.5 * s, 2.5 * s, "#FFFFFF", 0.9))
            elif style == "sclera":
                a.add(ellipse(x, y, 18 * s, 20 * s, "#FFFFFF"),
                      ellipse(x + 1.5 * s, y + 2.5 * s, 11.5 * s, 13.5 * s, "#231C33"),
                      circle(x - 2.5 * s, y - 3.5 * s, 4.6 * s, "#FFFFFF"),
                      circle(x + 5.5 * s, y + 8 * s, 2 * s, "#FFFFFF", 0.9))
            elif style == "iris":
                a.add(ellipse(x, y, 17 * s, 19 * s, iris),
                      ellipse(x, y + 1 * s, 6.5 * s, 14 * s, "#17131F"),
                      circle(x - 5 * s, y - 6 * s, 4.6 * s, "#FFFFFF"),
                      circle(x + 5 * s, y + 7 * s, 2 * s, "#FFFFFF", 0.9))
        elif a.face == "blink":
            a.add(path(f"M {f(x - 14 * s)} {f(y)} Q {f(x)} {f(y + 12 * s)} {f(x + 14 * s)} {f(y)}",
                       stroke=line, width=5.5 * s))
        else:
            a.add(path(f"M {f(x - 14 * s)} {f(y + 5 * s)} Q {f(x)} {f(y - 13 * s)} {f(x + 14 * s)} {f(y + 5 * s)}",
                       stroke=line, width=6 * s))


def mouth(a, y=CY + 46, style="w", size=1.0, line=INK, x=CX, happy=True):
    s = size
    if a.face == "happy" and happy:
        w = 15 * s
        d = (f"M {f(x - w)} {f(y)} Q {f(x)} {f(y - 2 * s)} {f(x + w)} {f(y)} "
             f"Q {f(x + w * 0.92)} {f(y + 21 * s)} {f(x)} {f(y + 22 * s)} "
             f"Q {f(x - w * 0.92)} {f(y + 21 * s)} {f(x - w)} {f(y)} Z")
        a.add(path(d, fill="#5B2234"), ellipse(x, y + 14.5 * s, 8.5 * s, 5.5 * s, "#FF7D98"))
        return
    if style == "w":
        a.add(path(f"M {f(x - 13 * s)} {f(y)} Q {f(x - 6.5 * s)} {f(y + 9 * s)} {f(x)} {f(y + 1 * s)} "
                   f"Q {f(x + 6.5 * s)} {f(y + 9 * s)} {f(x + 13 * s)} {f(y)}", stroke=line, width=4.5 * s))
    elif style == "smile":
        a.add(path(f"M {f(x - 14 * s)} {f(y)} Q {f(x)} {f(y + 13 * s)} {f(x + 14 * s)} {f(y)}",
                   stroke=line, width=4.8 * s))
    elif style == "wide":
        a.add(path(f"M {f(x - 30 * s)} {f(y)} Q {f(x)} {f(y + 18 * s)} {f(x + 30 * s)} {f(y)}",
                   stroke=line, width=5 * s))
    elif style == "o":
        a.add(ellipse(x, y + 4 * s, 6 * s, 7 * s, "#5B2234"))


def cat_nose(a, y=CY + 30, color="#FF8AA8", size=1.0):
    s = size
    d = (f"M {f(CX - 8 * s)} {f(y - 3 * s)} Q {f(CX)} {f(y - 7 * s)} {f(CX + 8 * s)} {f(y - 3 * s)} "
         f"Q {f(CX + 5 * s)} {f(y + 5 * s)} {f(CX)} {f(y + 6 * s)} Q {f(CX - 5 * s)} {f(y + 5 * s)} {f(CX - 8 * s)} {f(y - 3 * s)} Z")
    a.add(path(d, fill=color))


def dark_nose(a, y=CY + 30, rx=12, ry=8, color="#2B2230"):
    a.add(ellipse(CX, y, rx, ry, color), ellipse(CX - rx * 0.35, y - ry * 0.35, rx * 0.33, ry * 0.28, "#FFFFFF", 0.45))


def whiskers(a, y=CY + 40, color="#5A4A50", spread=1.0):
    for side in (-1, 1):
        for i, (dy, tilt) in enumerate(((-8, -7), (2, 0), (12, 7))):
            x1 = CX + side * 58 * spread
            x2 = CX + side * 108 * spread
            a.add(path(f"M {f(x1)} {f(y + dy)} L {f(x2)} {f(y + dy + tilt)}", stroke=color, width=2.6, opacity=0.6))


def tri_ear(a, x, y, w, h, outer, inner=None, tilt=0, tip=None):
    """A pointy ear: (x, y) is the middle of its base."""
    d = f"M {f(x - w / 2)} {f(y)} Q {f(x - w * 0.18)} {f(y - h * 0.9)} {f(x)} {f(y - h)} Q {f(x + w * 0.18)} {f(y - h * 0.9)} {f(x + w / 2)} {f(y)} Z"
    svg = path(d, fill=outer)
    if tip:
        dt = f"M {f(x - w * 0.16)} {f(y - h * 0.72)} Q {f(x)} {f(y - h * 1.02)} {f(x + w * 0.16)} {f(y - h * 0.72)} Q {f(x)} {f(y - h * 0.62)} {f(x - w * 0.16)} {f(y - h * 0.72)} Z"
        svg += path(dt, fill=tip)
    if inner:
        di = f"M {f(x - w * 0.27)} {f(y)} Q {f(x - w * 0.1)} {f(y - h * 0.7)} {f(x)} {f(y - h * 0.78)} Q {f(x + w * 0.1)} {f(y - h * 0.7)} {f(x + w * 0.27)} {f(y)} Z"
        svg += path(di, fill=inner)
    return rotate(svg, tilt, x, y)


def round_ear(x, y, r, outer, inner=None, inner_scale=0.58):
    svg = circle(x, y, r, outer)
    if inner:
        svg += circle(x, y + r * 0.08, r * inner_scale, inner)
    return svg


# ── The characters ─────────────────────────────────────────────────────────

# Classic ----------------------------------------------------------------------

@character("spider", "Spider", "classic")
def spider(a):
    legs_left = [
        [(205, 262), (122, 182), (74, 236)],
        [(184, 306), (90, 276), (48, 338)],
        [(184, 362), (94, 388), (66, 456)],
        [(208, 414), (144, 470), (136, 542)],
    ]
    legs = []
    for leg in legs_left:
        legs.append(leg)
        legs.append([(640 - x, y) for x, y in leg])
    k = 0.62
    def tx(x, y):
        return (x - 320) * k + CX, (y - 330) * k + CY - 6
    body = a.gradient("#6A6FC2", "#3A3C7A", "#1D1D45")
    leg_fill = "#2D2F66"
    for leg in legs:
        pts = " ".join(f"{f(tx(x, y)[0])},{f(tx(x, y)[1])}" for x, y in leg)
        a.add(f'<polyline points="{pts}" fill="none" stroke="{leg_fill}" stroke-width="{f(24 * k)}" stroke-linecap="round" stroke-linejoin="round"/>')
        ex, ey = tx(*leg[-1])
        a.add(circle(ex, ey, 15 * k, "#2A2C5C"))
    bx, by = tx(320, 330)
    a.add(circle(bx, by, 150 * k, body))
    a.add(rotate(ellipse(bx - 58 * k, by - 94 * k, 40 * k, 20 * k, "#FFFFFF", 0.2), -28, bx - 58 * k, by - 94 * k))
    cheeks(a, y=by + 64 * k, dx=98 * k, rx=30 * k, ry=18 * k)
    ey = by - 8 * k
    for ex in (bx - 54 * k, bx + 54 * k):
        if a.face == "open":
            a.add(ellipse(ex, ey, 41 * k, 47 * k, "#FFFFFF"),
                  ellipse(ex + 7 * k * (1 if ex < bx else -1), ey + 11 * k, 27 * k, 32 * k, "#15152F"),
                  circle(ex - 4 * k * (1 if ex < bx else -1) - 6 * k, ey - 4 * k, 10.5 * k, "#FFFFFF"),
                  circle(ex + 16 * k, ey + 26 * k, 4.5 * k, "#FFFFFF"))
        elif a.face == "blink":
            a.add(path(f"M {f(ex - 30 * k)} {f(ey + 4 * k)} Q {f(ex)} {f(ey + 30 * k)} {f(ex + 30 * k)} {f(ey + 4 * k)}",
                       stroke=LIGHT_INK, width=9 * k))
        else:
            a.add(path(f"M {f(ex - 30 * k)} {f(ey + 18 * k)} Q {f(ex)} {f(ey - 26 * k)} {f(ex + 30 * k)} {f(ey + 18 * k)}",
                       stroke=LIGHT_INK, width=10 * k))
    my = by + 62 * k
    if a.face == "happy":
        a.add(path(f"M {f(bx - 30 * k)} {f(my - 8 * k)} Q {f(bx)} {f(my - 8 * k)} {f(bx + 30 * k)} {f(my - 8 * k)} "
                   f"Q {f(bx + 28 * k)} {f(my + 36 * k)} {f(bx)} {f(my + 38 * k)} Q {f(bx - 28 * k)} {f(my + 36 * k)} {f(bx - 30 * k)} {f(my - 8 * k)} Z",
                   fill="#2B0F2E", stroke="#F6E8F2", width=5 * k))
        a.add(ellipse(bx, my + 23 * k, 15 * k, 9 * k, "#FF7FAA"))
    else:
        a.add(path(f"M {f(bx - 24 * k)} {f(my)} Q {f(bx)} {f(my + 22 * k)} {f(bx + 24 * k)} {f(my)}",
                   stroke="#F6E8F2", width=7 * k))
        a.add(path(f"M {f(bx - 14 * k)} {f(my + 7 * k)} L {f(bx - 11 * k)} {f(my + 18 * k)} L {f(bx - 7 * k)} {f(my + 9 * k)} Z", fill="#F6E8F2"))
        a.add(path(f"M {f(bx + 14 * k)} {f(my + 7 * k)} L {f(bx + 11 * k)} {f(my + 18 * k)} L {f(bx + 7 * k)} {f(my + 9 * k)} Z", fill="#F6E8F2"))


# Pets -------------------------------------------------------------------------

def cat_like(a, colors, ear, inner, stripes=None, muzzle=None, eye_style="dark", iris="#9BD86A",
             line=INK, nose="#FF8AA8", whisker="#5A4A50"):
    a.add(both(tri_ear(a, CX - 88, CY - 70, 92, 112, ear, inner, tilt=-14)))
    head(a, colors, rx=R + 8, ry=R - 14)
    if stripes:
        for dx, h in ((-22, 34), (0, 42), (22, 34)):
            a.add(path(f"M {CX + dx} {CY - 118} L {CX + dx * 0.8} {CY - 118 + h}", stroke=stripes, width=9, opacity=0.8))
        for side in (-1, 1):
            for dy in (-6, 12):
                a.add(path(f"M {CX + side * 144} {CY + dy} L {CX + side * 116} {CY + dy + 4}", stroke=stripes, width=8, opacity=0.75))
    if muzzle:
        a.add(ellipse(CX - 22, CY + 42, 34, 26, muzzle), ellipse(CX + 22, CY + 42, 34, 26, muzzle))
    cheeks(a)
    eyes(a, style=eye_style, iris=iris, line=line)
    cat_nose(a, color=nose)
    mouth(a, y=CY + 38, line=line)
    whiskers(a, color=whisker)


@character("cat", "Ginger Cat", "pets")
def cat(a):
    cat_like(a, ("#FFC982", "#F59A3A", "#D9741C"), "#F28B2C", "#FFB3C4", stripes="#D46A12", muzzle="#FFE2BD")


@character("kitten", "Gray Kitten", "pets")
def kitten(a):
    cat_like(a, ("#E4E8EF", "#B8BFCB", "#8E96A6"), "#A9B1BF", "#FFC2D1", stripes="#7D8697", muzzle="#F7F8FB")


@character("puppy", "Puppy", "pets")
def puppy(a):
    ear = "#9A643C"
    for side in (-1, 1):
        x = CX + side * 118
        d = (f"M {x - side * 26} {CY - 96} Q {x + side * 40} {CY - 110} {x + side * 44} {CY - 20} "
             f"Q {x + side * 46} {CY + 52} {x + side * 8} {CY + 46} Q {x - side * 24} {CY + 38} {x - side * 26} {CY - 96} Z")
        a.add(path(d, fill=ear))
    head(a, ("#FFF0D6", "#F2D3A2", "#D6AE72"), rx=R - 4, ry=R - 10)
    a.add(ellipse(CX + 52, CY + 2, 34, 30, "#C98F55", 0.9))  # patch around one eye
    a.add(ellipse(CX, CY + 44, 48, 34, "#FFF8EC"))
    cheeks(a, dx=92)
    eyes(a)
    dark_nose(a, y=CY + 32)
    mouth(a, y=CY + 44)
    if a.face == "open":
        a.add(ellipse(CX + 6, CY + 58, 8, 10, "#FF7D98"))


@character("shiba", "Shiba", "pets")
def shiba(a):
    a.add(both(tri_ear(a, CX - 84, CY - 72, 86, 96, "#E98B3A", "#FFE9CF", tilt=-12)))
    head(a, ("#FFC27D", "#F09A45", "#D2752A"), rx=R + 4, ry=R - 12)
    a.add(path(f"M {CX - 120} {CY + 4} Q {CX - 70} {CY - 10} {CX} {CY + 14} Q {CX + 70} {CY - 10} {CX + 120} {CY + 4} "
               f"Q {CX + 110} {CY + 110} {CX} {CY + 118} Q {CX - 110} {CY + 110} {CX - 120} {CY + 4} Z", fill="#FFF4E4"))
    a.add(ellipse(CX - 50, CY - 34, 9, 6, "#FFF4E4"), ellipse(CX + 50, CY - 34, 9, 6, "#FFF4E4"))
    cheeks(a, dx=90)
    eyes(a, y=CY + 2)
    dark_nose(a, y=CY + 34, rx=11, ry=7)
    mouth(a, y=CY + 44)


@character("bunny", "Bunny", "pets")
def bunny(a):
    for side in (-1, 1):
        x = CX + side * 48
        ear = ellipse(x, CY - 150, 30, 82, "#F4EDF4") + ellipse(x, CY - 144, 16, 62, "#FFB9CC")
        a.add(rotate(ear, side * 8, x, CY - 90))
    head(a, ("#FFFFFF", "#F4EEF4", "#D9CDDA"), y=CY + 18, rx=R - 4, ry=R - 22)
    cheeks(a, y=CY + 60)
    eyes(a, y=CY + 22)
    cat_nose(a, y=CY + 50, color="#FF8AA8", size=0.8)
    a.add(path(f"M {CX} {CY + 55} L {CX} {CY + 63}", stroke=INK, width=4))
    mouth(a, y=CY + 62, size=0.8)


@character("hamster", "Hamster", "pets")
def hamster(a):
    a.add(round_ear(CX - 92, CY - 96, 30, "#E9A75A", "#FFC4CF"), round_ear(CX + 92, CY - 96, 30, "#E9A75A", "#FFC4CF"))
    head(a, ("#FFD9A0", "#F3B567", "#D9914A"), rx=R + 6, ry=R - 10)
    a.add(path(f"M {CX - 140} {CY + 10} Q {CX - 130} {CY + 118} {CX} {CY + 124} Q {CX + 130} {CY + 118} {CX + 140} {CY + 10} "
               f"Q {CX + 80} {CY + 32} {CX} {CY + 22} Q {CX - 80} {CY + 32} {CX - 140} {CY + 10} Z", fill="#FFF6EA"))
    a.add(ellipse(CX, CY - 70, 16, 34, "#FFF0DA", 0.8))
    cheeks(a, y=CY + 50, dx=94, rx=26, ry=16)
    eyes(a, y=CY + 2, dx=54)
    cat_nose(a, y=CY + 30, color="#FF8AA8", size=0.7)
    mouth(a, y=CY + 38, size=0.75)


@character("mouse", "Mouse", "pets")
def mouse(a):
    a.add(round_ear(CX - 104, CY - 92, 56, "#AEB2C2", "#FFC1D0", 0.62), round_ear(CX + 104, CY - 92, 56, "#AEB2C2", "#FFC1D0", 0.62))
    head(a, ("#E2E4EC", "#BFC3D0", "#9599AA"), rx=R - 2, ry=R - 16)
    cheeks(a)
    eyes(a)
    cat_nose(a, y=CY + 30, color="#FF7EA0")
    mouth(a, y=CY + 38)
    whiskers(a, color="#6A6A7A")


# Farm -------------------------------------------------------------------------

@character("cow", "Cow", "farm")
def cow(a):
    horn = "#F4E1B5"
    a.add(both(rotate(path(f"M {CX - 70} {CY - 96} Q {CX - 96} {CY - 150} {CX - 74} {CY - 162} Q {CX - 64} {CY - 130} {CX - 44} {CY - 112} Z", fill=horn), -6, CX - 70, CY - 110)))
    for side in (-1, 1):
        ear = ellipse(CX + side * 150, CY - 40, 46, 22, "#FFFFFF") + ellipse(CX + side * 154, CY - 40, 28, 12, "#FFB6C6")
        a.add(rotate(ear, side * 18, CX + side * 150, CY - 40))
    head(a, ("#FFFFFF", "#F2F1F6", "#D3D1DD"), ry=R - 4)
    a.add(path(f"M {CX + 30} {CY - 128} Q {CX + 96} {CY - 120} {CX + 110} {CY - 60} Q {CX + 70} {CY - 40} {CX + 40} {CY - 70} Q {CX + 20} {CY - 100} {CX + 30} {CY - 128} Z", fill="#2E2A36"))
    a.add(ellipse(CX - 92, CY + 6, 26, 32, "#2E2A36"))
    a.add(ellipse(CX, CY + 58, 82, 52, "#FFB9CA"), ellipse(CX - 30, CY + 58, 9, 13, "#E0809A"), ellipse(CX + 30, CY + 58, 9, 13, "#E0809A"))
    eyes(a, y=CY - 8, dx=48)
    cheeks(a, y=CY + 26, dx=100, rx=17, ry=11)
    if a.face == "happy":
        a.add(path(f"M {CX - 22} {CY + 86} Q {CX} {CY + 104} {CX + 22} {CY + 86}", stroke="#B3546E", width=5))


@character("pig", "Piglet", "farm")
def pig(a):
    for side in (-1, 1):
        ear = path(f"M {CX + side * 60} {CY - 108} Q {CX + side * 128} {CY - 150} {CX + side * 134} {CY - 82} Q {CX + side * 100} {CY - 70} {CX + side * 60} {CY - 108} Z", fill="#F590B0")
        a.add(ear)
    head(a, ("#FFD9E5", "#FFB4CB", "#E888A8"), rx=R + 4, ry=R - 10)
    a.add(ellipse(CX, CY + 38, 44, 30, "#FF9AB9"), ellipse(CX - 14, CY + 38, 7, 11, "#C9587C"), ellipse(CX + 14, CY + 38, 7, 11, "#C9587C"))
    eyes(a, y=CY - 6, dx=56)
    cheeks(a, y=CY + 34, dx=96)
    mouth(a, y=CY + 76, style="smile", size=0.8)


@character("sheep", "Sheep", "farm")
def sheep(a):
    wool = []
    for i in range(14):
        ang = math.pi + i * (math.pi * 2 / 14)
        wool.append(circle(CX + math.cos(ang) * 132, CY - 4 + math.sin(ang) * 120, 38, "#FFFFFF"))
    a.add(ellipse(CX, CY - 4, 140, 128, "#F6F3F0"))
    a.add(wool)
    for side in (-1, 1):
        a.add(rotate(ellipse(CX + side * 112, CY + 6, 34, 15, "#E8D5C0"), side * 24, CX + side * 112, CY + 6))
    a.add(ellipse(CX, CY + 22, 86, 96, a.gradient("#FFF6E8", "#F3E1C8", "#DCC3A2")))
    for i in range(5):
        a.add(circle(CX - 44 + i * 22, CY - 70 + (i % 2) * 6, 22, "#FFFFFF"))
    eyes(a, y=CY + 18, dx=34, size=0.9)
    cheeks(a, y=CY + 52, dx=58, rx=15, ry=10)
    dark_nose(a, y=CY + 52, rx=9, ry=6, color="#6B4E3D")
    mouth(a, y=CY + 60, size=0.75)


@character("chicken", "Hen", "farm")
def chicken(a):
    a.add(circle(CX - 26, CY - 132, 22, "#F2484B"), circle(CX, CY - 144, 26, "#F2484B"), circle(CX + 28, CY - 130, 21, "#F2484B"))
    head(a, ("#FFFFFF", "#F6F4F2", "#DCD6D0"), ry=R - 4)
    cheeks(a, y=CY + 34, dx=90)
    eyes(a, y=CY - 4, dx=52)
    beak_y = CY + 26
    if a.face == "happy":
        a.add(path(f"M {CX - 26} {beak_y} L {CX + 26} {beak_y} L {CX} {beak_y - 18} Z", fill="#FFB02E"))
        a.add(path(f"M {CX - 24} {beak_y + 4} L {CX + 24} {beak_y + 4} L {CX} {beak_y + 24} Z", fill="#F3901A"))
    else:
        a.add(path(f"M {CX - 26} {beak_y} Q {CX} {beak_y - 20} {CX + 26} {beak_y} Q {CX} {beak_y + 26} {CX - 26} {beak_y} Z", fill="#FFAA2A"))
    a.add(ellipse(CX + 6, beak_y + 36, 12, 18, "#F2484B"))


@character("chick", "Chick", "farm")
def chick(a):
    for dx, h in ((-14, 46), (0, 58), (14, 46)):
        a.add(rotate(ellipse(CX + dx, CY - 128, 9, h * 0.5, "#FFD23F"), dx * 1.6, CX + dx, CY - 110))
    head(a, ("#FFF4A8", "#FFE04D", "#F5B700"), rx=R, ry=R - 4)
    cheeks(a, y=CY + 34, dx=88)
    eyes(a, y=CY - 2, dx=50)
    beak_y = CY + 28
    if a.face == "happy":
        a.add(path(f"M {CX - 20} {beak_y - 4} L {CX + 20} {beak_y - 4} L {CX} {beak_y - 18} Z", fill="#FF8A1F"))
        a.add(path(f"M {CX - 18} {beak_y} L {CX + 18} {beak_y} L {CX} {beak_y + 18} Z", fill="#F06A0E"))
    else:
        a.add(path(f"M {CX - 18} {beak_y - 6} Q {CX} {beak_y - 20} {CX + 18} {beak_y - 6} Q {CX} {beak_y + 16} {CX - 18} {beak_y - 6} Z", fill="#FF8A1F"))


@character("duck", "Duck", "farm")
def duck(a):
    a.add(path(f"M {CX - 4} {CY - 128} Q {CX + 14} {CY - 170} {CX + 34} {CY - 150} Q {CX + 12} {CY - 146} {CX + 10} {CY - 124} Z", fill="#F0EEF5"))
    head(a, ("#FFFFFF", "#F2F1F7", "#D1CFDD"), ry=R - 4)
    cheeks(a, y=CY + 30, dx=96)
    eyes(a, y=CY - 6, dx=54)
    by = CY + 36
    a.add(path(f"M {CX - 46} {by - 10} Q {CX} {by - 34} {CX + 46} {by - 10} Q {CX + 52} {by + 12} {CX} {by + 16} Q {CX - 52} {by + 12} {CX - 46} {by - 10} Z", fill="#FF9D2E"))
    a.add(path(f"M {CX - 40} {by + 2} Q {CX} {by + (16 if a.face == 'happy' else 8)} {CX + 40} {by + 2}", stroke="#D96F12", width=4))
    a.add(ellipse(CX - 12, by - 14, 4, 2.6, "#C2620E"), ellipse(CX + 12, by - 14, 4, 2.6, "#C2620E"))


# Forest -----------------------------------------------------------------------

@character("fox", "Fox", "forest")
def fox(a):
    a.add(both(tri_ear(a, CX - 86, CY - 64, 98, 128, "#F0782C", "#FFE7D2", tilt=-16, tip="#3B2A2E")))
    head(a, ("#FFB37A", "#F38234", "#D2611A"), rx=R + 10, ry=R - 14)
    a.add(path(f"M {CX - 146} {CY + 6} Q {CX - 80} {CY + 6} {CX} {CY + 46} Q {CX + 80} {CY + 6} {CX + 146} {CY + 6} "
               f"Q {CX + 120} {CY + 110} {CX} {CY + 120} Q {CX - 120} {CY + 110} {CX - 146} {CY + 6} Z", fill="#FFF5EA"))
    cheeks(a, y=CY + 46, dx=92)
    eyes(a, y=CY - 6, dx=54)
    dark_nose(a, y=CY + 40, rx=11, ry=8)
    mouth(a, y=CY + 50)


@character("bear", "Bear", "forest")
def bear(a):
    a.add(round_ear(CX - 100, CY - 98, 38, "#A0683F", "#E8B98C"), round_ear(CX + 100, CY - 98, 38, "#A0683F", "#E8B98C"))
    head(a, ("#C99467", "#A9703F", "#7F4F27"), rx=R + 2, ry=R - 8)
    a.add(ellipse(CX, CY + 44, 56, 42, "#F0D3AD"))
    cheeks(a, y=CY + 30, dx=92)
    eyes(a, y=CY - 6, dx=52)
    dark_nose(a, y=CY + 30, rx=14, ry=10)
    mouth(a, y=CY + 44)


@character("panda", "Panda", "forest")
def panda(a):
    a.add(round_ear(CX - 98, CY - 100, 38, "#26232D"), round_ear(CX + 98, CY - 100, 38, "#26232D"))
    head(a, ("#FFFFFF", "#F4F4F7", "#D6D6DE"), rx=R + 2, ry=R - 8)
    for side in (-1, 1):
        a.add(rotate(ellipse(CX + side * 52, CY + 4, 30, 38, "#26232D"), side * -24, CX + side * 52, CY + 4))
    cheeks(a, y=CY + 46, dx=92)
    eyes(a, y=CY + 2, dx=52, style="sclera", size=0.8, line=LIGHT_INK)
    dark_nose(a, y=CY + 36, rx=13, ry=9)
    mouth(a, y=CY + 48)


@character("raccoon", "Raccoon", "forest")
def raccoon(a):
    a.add(both(tri_ear(a, CX - 86, CY - 78, 80, 84, "#8F8E9E", "#3F3C4A", tilt=-12)))
    head(a, ("#C9C8D4", "#A3A2B2", "#7B7A8C"), rx=R + 6, ry=R - 10)
    a.add(path(f"M {CX - 130} {CY - 6} Q {CX - 60} {CY - 40} {CX} {CY - 10} Q {CX + 60} {CY - 40} {CX + 130} {CY - 6} "
               f"Q {CX + 110} {CY + 40} {CX + 56} {CY + 30} Q {CX + 20} {CY + 24} {CX} {CY + 30} "
               f"Q {CX - 20} {CY + 24} {CX - 56} {CY + 30} Q {CX - 110} {CY + 40} {CX - 130} {CY - 6} Z", fill="#3B3846"))
    a.add(ellipse(CX, CY + 54, 50, 36, "#F2F1F6"), ellipse(CX - 50, CY - 44, 22, 8, "#F2F1F6"), ellipse(CX + 50, CY - 44, 22, 8, "#F2F1F6"))
    cheeks(a, y=CY + 50, dx=96)
    eyes(a, y=CY + 4, dx=52, style="sclera", size=0.78, line=LIGHT_INK)
    dark_nose(a, y=CY + 44, rx=11, ry=8)
    mouth(a, y=CY + 56)


@character("deer", "Fawn", "forest")
def deer(a):
    antler = "#B5865A"
    for side in (-1, 1):
        x0 = CX + side * 46
        d = (f"M {x0} {CY - 110} Q {x0 + side * 6} {CY - 160} {x0 + side * 30} {CY - 190} "
             f"M {x0 + side * 4} {CY - 150} Q {x0 - side * 18} {CY - 170} {x0 - side * 16} {CY - 190} "
             f"M {x0 + side * 18} {CY - 172} Q {x0 + side * 42} {CY - 170} {x0 + side * 56} {CY - 160}")
        a.add(path(d, stroke=antler, width=13))
    for side in (-1, 1):
        ear = path(f"M {CX + side * 100} {CY - 70} Q {CX + side * 170} {CY - 110} {CX + side * 178} {CY - 64} Q {CX + side * 150} {CY - 36} {CX + side * 100} {CY - 50} Z", fill="#C47E4C")
        ear += path(f"M {CX + side * 112} {CY - 64} Q {CX + side * 160} {CY - 92} {CX + side * 164} {CY - 64} Q {CX + side * 144} {CY - 48} {CX + side * 112} {CY - 56} Z", fill="#FFD9C0")
        a.add(ear)
    head(a, ("#E5AE7E", "#CC8A55", "#A86634"), rx=R - 4, ry=R - 6)
    for x, y, r in ((-30, -96, 7), (-8, -108, 6), (18, -100, 7), (36, -84, 5), (-46, -78, 5)):
        a.add(circle(CX + x, CY + y, r, "#FFF2E0"))
    a.add(ellipse(CX, CY + 50, 54, 40, "#FFF2E0"))
    cheeks(a, y=CY + 36, dx=90)
    eyes(a, y=CY - 2, dx=50)
    dark_nose(a, y=CY + 36, rx=12, ry=8)
    mouth(a, y=CY + 48)


@character("hedgehog", "Hedgehog", "forest")
def hedgehog(a):
    spikes = []
    n = 17
    for i in range(n):
        ang = math.radians(196 + i * (148 / (n - 1)))
        bx, by = CX + math.cos(ang) * 120, CY - 6 + math.sin(ang) * 112
        tx, ty = CX + math.cos(ang) * 182, CY - 6 + math.sin(ang) * 170
        nx, ny = -math.sin(ang) * 22, math.cos(ang) * 22
        spikes.append(path(f"M {f(bx - nx)} {f(by - ny)} L {f(tx)} {f(ty)} L {f(bx + nx)} {f(by + ny)} Z", fill="#7A5236"))
    a.add(ellipse(CX, CY - 6, 150, 140, "#8B6040"))
    a.add(spikes)
    a.add(round_ear(CX - 84, CY - 72, 20, "#E8C9A4", "#FFB9C8"), round_ear(CX + 84, CY - 72, 20, "#E8C9A4", "#FFB9C8"))
    head(a, ("#FFF0DC", "#F2D8B6", "#D9B68D"), y=CY + 14, rx=R - 18, ry=R - 30)
    cheeks(a, y=CY + 54, dx=80)
    eyes(a, y=CY + 14, dx=46)
    dark_nose(a, y=CY + 44, rx=10, ry=7)
    mouth(a, y=CY + 54, size=0.85)


@character("squirrel", "Squirrel", "forest")
def squirrel(a):
    tail = path(f"M {CX + 70} {CY + 100} Q {CX + 210} {CY + 80} {CX + 186} {CY - 60} Q {CX + 168} {CY - 170} {CX + 96} {CY - 150} "
                f"Q {CX + 150} {CY - 110} {CX + 140} {CY - 40} Q {CX + 130} {CY + 40} {CX + 70} {CY + 100} Z", fill="#C66A2E")
    a.add(tail)
    a.add(both(tri_ear(a, CX - 80, CY - 84, 64, 84, "#D9763A", "#FFD6BE", tilt=-8)))
    a.add(both(path(f"M {CX - 82} {CY - 168} Q {CX - 92} {CY - 186} {CX - 74} {CY - 192}", stroke="#A9531F", width=7)))
    head(a, ("#F4A66A", "#DD8040", "#B65F22"), rx=R - 6, ry=R - 12)
    a.add(ellipse(CX - 62, CY + 40, 44, 34, "#FFF0DE"), ellipse(CX + 62, CY + 40, 44, 34, "#FFF0DE"), ellipse(CX, CY + 50, 40, 32, "#FFF0DE"))
    cheeks(a, y=CY + 40, dx=84)
    eyes(a, y=CY - 4, dx=48)
    dark_nose(a, y=CY + 32, rx=9, ry=6.5, color="#5A3424")
    mouth(a, y=CY + 42, size=0.85)
    if a.face != "happy":
        a.add(path(f"M {CX - 7} {CY + 49} L {CX - 7} {CY + 60} L {CX + 7} {CY + 60} L {CX + 7} {CY + 49}", fill="#FFFFFF", stroke="#D9D2CC", width=1.5))


# Jungle & savanna --------------------------------------------------------------

@character("lion", "Lion", "wild")
def lion(a):
    n = 16
    for i in range(n):
        ang = i * 2 * math.pi / n
        x, y = CX + math.cos(ang) * 138, CY + math.sin(ang) * 130
        a.add(circle(x, y, 46, "#C96A22" if i % 2 else "#DE8432"))
    a.add(ellipse(CX, CY, 150, 142, "#D27628"))
    a.add(round_ear(CX - 84, CY - 86, 26, "#F2B547", "#FFE0A8"), round_ear(CX + 84, CY - 86, 26, "#F2B547", "#FFE0A8"))
    head(a, ("#FFE08A", "#F7C44F", "#DDA02C"), rx=R - 22, ry=R - 28)
    a.add(ellipse(CX - 22, CY + 40, 30, 24, "#FFF3D2"), ellipse(CX + 22, CY + 40, 30, 24, "#FFF3D2"))
    cheeks(a, y=CY + 34, dx=78, rx=17, ry=11)
    eyes(a, y=CY - 6, dx=44, size=0.92)
    cat_nose(a, y=CY + 26, color="#7A4A2A")
    mouth(a, y=CY + 36)


@character("tiger", "Tiger", "wild")
def tiger(a):
    a.add(round_ear(CX - 98, CY - 92, 34, "#F08A2C", "#FFF1E0"), round_ear(CX + 98, CY - 92, 34, "#F08A2C", "#FFF1E0"))
    head(a, ("#FFB866", "#F48B2E", "#D86A14"), rx=R + 8, ry=R - 12)
    stripe = "#2E2430"
    for dx, h in ((-24, 30), (0, 40), (24, 30)):
        a.add(path(f"M {CX + dx} {CY - 120} L {CX + dx * 0.8} {CY - 120 + h}", stroke=stripe, width=9))
    for side in (-1, 1):
        for dy, ln in ((-16, 36), (6, 30), (28, 22)):
            a.add(path(f"M {CX + side * 146} {CY + dy} Q {CX + side * (146 - ln * 0.6)} {CY + dy - 2} {CX + side * (146 - ln)} {CY + dy + 6}", stroke=stripe, width=8))
    a.add(path(f"M {CX - 96} {CY + 20} Q {CX - 40} {CY + 6} {CX} {CY + 26} Q {CX + 40} {CY + 6} {CX + 96} {CY + 20} "
               f"Q {CX + 80} {CY + 104} {CX} {CY + 108} Q {CX - 80} {CY + 104} {CX - 96} {CY + 20} Z", fill="#FFF6EA"))
    a.add(ellipse(CX - 50, CY - 40, 18, 8, "#FFF6EA"), ellipse(CX + 50, CY - 40, 18, 8, "#FFF6EA"))
    cheeks(a, y=CY + 44, dx=90)
    eyes(a, y=CY - 4, dx=52)
    cat_nose(a, y=CY + 32, color="#E86E8E")
    mouth(a, y=CY + 42)
    whiskers(a, y=CY + 48, color="#7D6060")


@character("monkey", "Monkey", "wild")
def monkey(a):
    a.add(round_ear(CX - 134, CY + 4, 38, "#8A5A3A", "#F2C9A4"), round_ear(CX + 134, CY + 4, 38, "#8A5A3A", "#F2C9A4"))
    head(a, ("#B27D55", "#8E5C3A", "#6A4026"), rx=R - 6, ry=R - 8)
    a.add(path(f"M {CX} {CY - 40} Q {CX - 30} {CY - 76} {CX - 66} {CY - 56} Q {CX - 108} {CY - 26} {CX - 84} {CY + 26} "
               f"Q {CX - 100} {CY + 104} {CX} {CY + 110} Q {CX + 100} {CY + 104} {CX + 84} {CY + 26} "
               f"Q {CX + 108} {CY - 26} {CX + 66} {CY - 56} Q {CX + 30} {CY - 76} {CX} {CY - 40} Z", fill="#F6D2AE"))
    a.add(path(f"M {CX - 10} {CY - 126} Q {CX} {CY - 150} {CX + 18} {CY - 140}", stroke="#6A4026", width=8))
    cheeks(a, y=CY + 40, dx=74, rx=16, ry=10)
    eyes(a, y=CY - 12, dx=42, size=0.95)
    a.add(ellipse(CX - 8, CY + 34, 4, 3, "#6A4026"), ellipse(CX + 8, CY + 34, 4, 3, "#6A4026"))
    mouth(a, y=CY + 52, style="smile", size=1.2)


@character("elephant", "Elephant", "wild")
def elephant(a):
    for side in (-1, 1):
        ear = ellipse(CX + side * 124, CY - 4, 70, 90, "#8FA9BD") + ellipse(CX + side * 128, CY, 47, 64, "#FFC6D3")
        a.add(rotate(ear, side * -8, CX + side * 124, CY - 4))
    head(a, ("#C7D7E3", "#9EB6C7", "#7A95AA"), rx=R - 14, ry=R - 12)
    trunk = (f"M {CX - 20} {CY + 20} Q {CX - 26} {CY + 110} {CX + 14} {CY + 132} Q {CX + 40} {CY + 140} {CX + 44} {CY + 118} "
             f"Q {CX + 30} {CY + 120} {CX + 22} {CY + 104} Q {CX + 18} {CY + 70} {CX + 20} {CY + 20} Z")
    a.add(path(trunk, fill="#A5BCCC"))
    for y in (CY + 58, CY + 76, CY + 94):
        a.add(path(f"M {CX - 16} {y} Q {CX} {y + 4} {CX + 16} {y}", stroke="#7F99AC", width=3.5))
    cheeks(a, y=CY + 34, dx=76, rx=17, ry=11)
    eyes(a, y=CY - 14, dx=44, size=0.95)
    if a.face == "happy":
        a.add(path(f"M {CX - 46} {CY + 40} Q {CX - 34} {CY + 56} {CX - 24} {CY + 44}", stroke=INK, width=4.5),
              path(f"M {CX + 46} {CY + 40} Q {CX + 34} {CY + 56} {CX + 24} {CY + 44}", stroke=INK, width=4.5))


@character("giraffe", "Giraffe", "wild")
def giraffe(a):
    for side in (-1, 1):
        x = CX + side * 38
        a.add(path(f"M {x} {CY - 108} L {x + side * 6} {CY - 170}", stroke="#E3B44A", width=14), circle(x + side * 6, CY - 176, 14, "#8B5A2B"))
        ear = ellipse(CX + side * 120, CY - 76, 40, 18, "#F2C14E") + ellipse(CX + side * 124, CY - 76, 24, 9, "#FFD9C2")
        a.add(rotate(ear, side * 26, CX + side * 120, CY - 76))
    head(a, ("#FFE79A", "#F7CF5C", "#DDAA2C"), rx=R - 12, ry=R - 6)
    for x, y, rx, ry in ((-70, -60, 22, 16), (66, -70, 18, 14), (-90, 14, 14, 18), (92, 6, 16, 14), (-20, -96, 14, 10), (26, -100, 12, 9)):
        a.add(ellipse(CX + x, CY + y, rx, ry, "#C9822F"))
    a.add(ellipse(CX, CY + 56, 66, 44, "#FFF0C8"), ellipse(CX - 22, CY + 50, 6, 4, "#9C6A34"), ellipse(CX + 22, CY + 50, 6, 4, "#9C6A34"))
    cheeks(a, y=CY + 26, dx=84)
    eyes(a, y=CY - 10, dx=46)
    mouth(a, y=CY + 70, style="smile", size=0.8)


@character("zebra", "Zebra", "wild")
def zebra(a):
    for i, dx in enumerate((-30, -12, 6, 24)):
        a.add(rotate(ellipse(CX + dx, CY - 138, 13, 30, "#2C2834"), dx * 0.6, CX + dx, CY - 120))
    a.add(both(tri_ear(a, CX - 80, CY - 86, 54, 82, "#F4F3F7", "#2C2834", tilt=-20)))
    head(a, ("#FFFFFF", "#F2F2F6", "#D4D3DD"), rx=R - 8, ry=R - 4)
    for side in (-1, 1):
        for dy in (-60, -24, 12):
            a.add(path(f"M {CX + side * 128} {CY + dy} Q {CX + side * 96} {CY + dy - 8} {CX + side * 82} {CY + dy + 10}", stroke="#2C2834", width=12))
    for dx in (-26, 0, 26):
        a.add(path(f"M {CX + dx} {CY - 128} Q {CX + dx * 1.2} {CY - 100} {CX + dx * 0.9} {CY - 76}", stroke="#2C2834", width=10))
    a.add(ellipse(CX, CY + 66, 62, 42, "#56505E"), ellipse(CX - 22, CY + 60, 7, 5, "#2C2834"), ellipse(CX + 22, CY + 60, 7, 5, "#2C2834"))
    cheeks(a, y=CY + 26, dx=88)
    eyes(a, y=CY - 6, dx=48)
    if a.face == "happy":
        a.add(path(f"M {CX - 20} {CY + 82} Q {CX} {CY + 96} {CX + 20} {CY + 82}", stroke="#F6F0FA", width=4.5))


@character("hippo", "Hippo", "wild")
def hippo(a):
    a.add(round_ear(CX - 88, CY - 108, 20, "#9D8BBE", "#F7B6CB"), round_ear(CX + 88, CY - 108, 20, "#9D8BBE", "#F7B6CB"))
    head(a, ("#CFC1E6", "#AE9CCF", "#8B78B0"), y=CY - 30, rx=R - 18, ry=R - 34)
    a.add(ellipse(CX, CY + 54, R + 6, 74, a.gradient("#E2D7F2", "#C3B3E0", "#9F8BC4")))
    a.add(ellipse(CX - 40, CY + 32, 9, 12, "#7D6A9E"), ellipse(CX + 40, CY + 32, 9, 12, "#7D6A9E"))
    cheeks(a, y=CY + 60, dx=98)
    eyes(a, y=CY - 52, dx=44, size=0.85)
    if a.face == "happy":
        a.add(path(f"M {CX - 60} {CY + 70} Q {CX} {CY + 120} {CX + 60} {CY + 70} Z", fill="#5B2234"))
        a.add(path(f"M {CX - 30} {CY + 76} L {CX - 30} {CY + 92} L {CX - 18} {CY + 92} L {CX - 18} {CY + 80} Z", fill="#FFFFFF"))
        a.add(path(f"M {CX + 30} {CY + 76} L {CX + 30} {CY + 92} L {CX + 18} {CY + 92} L {CX + 18} {CY + 80} Z", fill="#FFFFFF"))
    else:
        a.add(path(f"M {CX - 50} {CY + 80} Q {CX} {CY + 104} {CX + 50} {CY + 80}", stroke="#6E5C90", width=5))


@character("koala", "Koala", "wild")
def koala(a):
    for side in (-1, 1):
        a.add(circle(CX + side * 116, CY - 70, 58, "#9DA6B4"), circle(CX + side * 120, CY - 66, 36, "#F6F3F7"))
    head(a, ("#D3D8E0", "#AAB2BF", "#858E9E"), rx=R + 2, ry=R - 10)
    cheeks(a, y=CY + 40, dx=90)
    eyes(a, y=CY - 4, dx=56, size=0.9)
    a.add(ellipse(CX, CY + 30, 26, 34, "#3A3442"), ellipse(CX - 8, CY + 18, 8, 6, "#FFFFFF", 0.35))
    mouth(a, y=CY + 70, size=0.85)


@character("sloth", "Sloth", "wild")
def sloth(a):
    head(a, ("#D9C2A0", "#BFA27A", "#977A55"), rx=R + 2, ry=R - 6)
    a.add(ellipse(CX, CY + 16, 118, 92, "#F2E5CF"))
    for side in (-1, 1):
        a.add(rotate(ellipse(CX + side * 52, CY + 6, 40, 22, "#6E553C"), side * 22, CX + side * 52, CY + 6))
    a.add(path(f"M {CX - 40} {CY - 80} Q {CX} {CY - 96} {CX + 40} {CY - 80}", stroke="#977A55", width=6, opacity=0.6))
    cheeks(a, y=CY + 52, dx=86)
    eyes(a, y=CY + 6, dx=52, style="sclera", size=0.72, line=LIGHT_INK)
    dark_nose(a, y=CY + 40, rx=14, ry=9, color="#4A3828")
    mouth(a, y=CY + 54, style="smile", size=1.1)


# Water & ice ------------------------------------------------------------------

@character("penguin", "Penguin", "water")
def penguin(a):
    head(a, ("#5B6C94", "#34405F", "#1E2740"), rx=R, ry=R - 2)
    a.add(path(f"M {CX} {CY - 40} Q {CX - 40} {CY - 92} {CX - 84} {CY - 60} Q {CX - 122} {CY - 24} {CX - 104} {CY + 40} "
               f"Q {CX - 80} {CY + 116} {CX} {CY + 120} Q {CX + 80} {CY + 116} {CX + 104} {CY + 40} "
               f"Q {CX + 122} {CY - 24} {CX + 84} {CY - 60} Q {CX + 40} {CY - 92} {CX} {CY - 40} Z", fill="#FFFFFF"))
    cheeks(a, y=CY + 44, dx=72)
    eyes(a, y=CY + 2, dx=44)
    by = CY + 34
    if a.face == "happy":
        a.add(path(f"M {CX - 18} {by - 4} L {CX + 18} {by - 4} L {CX} {by - 16} Z", fill="#FFA12B"))
        a.add(path(f"M {CX - 16} {by} L {CX + 16} {by} L {CX} {by + 16} Z", fill="#F07F12"))
    else:
        a.add(path(f"M {CX - 18} {by - 6} Q {CX} {by - 18} {CX + 18} {by - 6} Q {CX} {by + 14} {CX - 18} {by - 6} Z", fill="#FFA12B"))


@character("frog", "Frog", "water")
def frog(a):
    for side in (-1, 1):
        a.add(circle(CX + side * 68, CY - 82, 50, a.gradient("#B6F08C", "#7BD150", "#4FA833")))
    head(a, ("#B6F08C", "#7BD150", "#4FA833"), y=CY + 10, rx=R + 16, ry=R - 26)
    for side in (-1, 1):
        x = CX + side * 68
        if a.face == "open":
            a.add(circle(x, CY - 84, 34, "#FFFFFF"), ellipse(x + side * -2, CY - 80, 18, 22, "#231C33"),
                  circle(x - 6, CY - 90, 7, "#FFFFFF"), circle(x + 6, CY - 72, 3, "#FFFFFF"))
        elif a.face == "blink":
            a.add(path(f"M {x - 22} {CY - 84} Q {x} {CY - 66} {x + 22} {CY - 84}", stroke=INK, width=6))
        else:
            a.add(path(f"M {x - 22} {CY - 76} Q {x} {CY - 102} {x + 22} {CY - 76}", stroke=INK, width=6.5))
    cheeks(a, y=CY + 40, dx=104, rx=24, ry=14)
    a.add(ellipse(CX - 14, CY + 2, 4, 3, "#2F6B22"), ellipse(CX + 14, CY + 2, 4, 3, "#2F6B22"))
    if a.face == "happy":
        a.add(path(f"M {CX - 62} {CY + 34} Q {CX} {CY + 100} {CX + 62} {CY + 34} Z", fill="#5B2234"), ellipse(CX, CY + 66, 20, 9, "#FF7D98"))
    else:
        mouth(a, y=CY + 34, style="wide", size=1.8)


@character("seal", "Seal", "water")
def seal(a):
    head(a, ("#F2F6FA", "#CFDBE6", "#A7B8C8"), rx=R + 4, ry=R - 10)
    a.add(ellipse(CX - 24, CY + 40, 34, 26, "#FFFFFF"), ellipse(CX + 24, CY + 40, 34, 26, "#FFFFFF"))
    for side in (-1, 1):
        for dx, dy in ((14, -4), (26, 8), (12, 12)):
            a.add(circle(CX + side * (24 + dx), CY + 36 + dy, 2.6, "#7C8DA0"))
    cheeks(a, y=CY + 34, dx=96)
    eyes(a, y=CY - 8, dx=52, size=1.1)
    dark_nose(a, y=CY + 24, rx=13, ry=9)
    mouth(a, y=CY + 40, size=0.9)


@character("whale", "Whale", "water")
def whale(a):
    for dx, r in ((-22, 13), (0, 17), (22, 13)):
        a.add(circle(CX + dx, CY - 150 + abs(dx) * 0.5, r, "#8FD3FF"))
    a.add(path(f"M {CX} {CY - 116} L {CX} {CY - 140}", stroke="#8FD3FF", width=10))
    head(a, ("#8CC8F5", "#5AA4E3", "#3B7FC4"), rx=R + 14, ry=R - 20)
    a.add(path(f"M {CX - 130} {CY + 40} Q {CX} {CY + 78} {CX + 130} {CY + 40} Q {CX + 100} {CY + 118} {CX} {CY + 118} Q {CX - 100} {CY + 118} {CX - 130} {CY + 40} Z", fill="#DFF1FF"))
    for x in (-50, -20, 10, 40):
        a.add(path(f"M {CX + x} {CY + 74} L {CX + x + 6} {CY + 104}", stroke="#B7DAF5", width=4))
    cheeks(a, y=CY + 28, dx=90)
    eyes(a, y=CY - 10, dx=56)
    mouth(a, y=CY + 34, style="smile", size=1.0)


@character("octopus", "Octopus", "water")
def octopus(a):
    col = ("#FFB7D9", "#F48BC0", "#D8649F")
    for i in range(6):
        x = CX - 100 + i * 40
        curl = 1 if i % 2 else -1
        a.add(path(f"M {x - 16} {CY + 50} Q {x - 18} {CY + 120} {x + curl * 14} {CY + 140} Q {x + curl * 30} {CY + 150} {x + curl * 24} {CY + 128} "
                   f"Q {x + 14} {CY + 110} {x + 16} {CY + 50} Z", fill="#E978B2"))
    head(a, col, y=CY - 16, rx=R - 6, ry=R - 4)
    for x, y, r in ((-62, -86, 9), (-40, -110, 6), (56, -90, 8)):
        a.add(circle(CX + x, CY + y, r, "#FFD4E9", 0.9))
    cheeks(a, y=CY + 24, dx=84)
    eyes(a, y=CY - 18, dx=46)
    mouth(a, y=CY + 24, style="smile", size=0.9)


@character("axolotl", "Axolotl", "water")
def axolotl(a):
    for side in (-1, 1):
        for i, ang in enumerate((-40, -10, 20)):
            x0, y0 = CX + side * 116, CY - 20 + i * 34
            a.add(rotate(ellipse(x0 + side * 34, y0, 38, 12, "#F06A9C"), side * ang, x0, y0))
            for k in range(3):
                a.add(rotate(circle(x0 + side * (14 + k * 16), y0 - 8, 6, "#F48AB3"), side * ang, x0, y0))
    head(a, ("#FFD3E2", "#FFAFCB", "#EE87AD"), rx=R + 2, ry=R - 16)
    cheeks(a, y=CY + 34, dx=92, color="#FF6E9F")
    eyes(a, y=CY - 6, dx=58, size=0.82)
    mouth(a, y=CY + 30, style="wide", size=1.25)


@character("turtle", "Turtle", "water")
def turtle(a):
    shell = a.gradient("#8BD27A", "#5DAE4C", "#3D8432")
    a.add(path(f"M {CX - 146} {CY + 120} Q {CX - 150} {CY + 20} {CX} {CY + 14} Q {CX + 150} {CY + 20} {CX + 146} {CY + 120} Z", fill=shell))
    a.add(path(f"M {CX - 150} {CY + 120} Q {CX} {CY + 140} {CX + 150} {CY + 120} Q {CX} {CY + 112} {CX - 150} {CY + 120} Z", fill="#F2D27A"))
    for x, y in ((-84, 92), (0, 70), (84, 92), (-42, 104), (42, 104)):
        a.add(ellipse(CX + x, CY + y, 24, 15, "#9EE08A", 0.85))
    head(a, ("#D4F0B2", "#ABDB82", "#86BE5E"), y=CY - 34, rx=R - 32, ry=R - 38)
    cheeks(a, y=CY - 4, dx=68, rx=17, ry=11)
    eyes(a, y=CY - 40, dx=40, size=0.9)
    mouth(a, y=CY - 4, style="smile", size=0.9)


# Night & spooky ---------------------------------------------------------------

@character("bat", "Bat", "night")
def bat(a):
    wing = "#4B3D66"
    for side in (-1, 1):
        d = (f"M {CX + side * 90} {CY - 20} Q {CX + side * 170} {CY - 90} {CX + side * 194} {CY - 44} "
             f"Q {CX + side * 172} {CY - 34} {CX + side * 180} {CY - 6} Q {CX + side * 156} {CY - 4} {CX + side * 160} {CY + 24} "
             f"Q {CX + side * 132} {CY + 14} {CX + side * 120} {CY + 40} Z")
        a.add(path(d, fill=wing))
    a.add(both(tri_ear(a, CX - 80, CY - 70, 92, 118, "#6C5B8A", "#F3A8C4", tilt=-18)))
    head(a, ("#9585B5", "#6C5B8A", "#4B3D66"), rx=R - 6, ry=R - 12)
    cheeks(a, y=CY + 40, dx=82)
    eyes(a, y=CY - 2, dx=48, style="sclera", size=0.95, line=LIGHT_INK)
    my = CY + 40
    if a.face == "happy":
        mouth(a, y=my, line=LIGHT_INK)
    else:
        a.add(path(f"M {CX - 18} {my} Q {CX} {my + 14} {CX + 18} {my}", stroke=LIGHT_INK, width=4.5))
        a.add(path(f"M {CX - 10} {my + 4} L {CX - 7} {my + 15} L {CX - 3} {my + 6} Z", fill="#FFFFFF"),
              path(f"M {CX + 10} {my + 4} L {CX + 7} {my + 15} L {CX + 3} {my + 6} Z", fill="#FFFFFF"))


@character("blackcat", "Black Cat", "night")
def blackcat(a):
    cat_like(a, ("#5A5670", "#36334A", "#1E1C2C"), "#2E2B40", "#F59BB8", eye_style="iris", iris="#C6E86A",
             line=LIGHT_INK, nose="#F59BB8", whisker="#CFC8E0")


@character("owl", "Owl", "night")
def owl(a):
    a.add(both(tri_ear(a, CX - 86, CY - 92, 62, 70, "#8C6A9E", None, tilt=-30)))
    head(a, ("#B898C8", "#8C6A9E", "#694B7C"), rx=R + 2, ry=R - 4)
    a.add(circle(CX - 54, CY - 8, 50, "#F6E9FA"), circle(CX + 54, CY - 8, 50, "#F6E9FA"))
    a.add(path(f"M {CX - 110} {CY + 60} Q {CX} {CY + 30} {CX + 110} {CY + 60} Q {CX + 80} {CY + 126} {CX} {CY + 128} Q {CX - 80} {CY + 126} {CX - 110} {CY + 60} Z", fill="#D9C2E4"))
    for x, y in ((-40, 80), (0, 90), (40, 80), (-20, 106), (20, 106)):
        a.add(path(f"M {CX + x - 8} {CY + y} Q {CX + x} {CY + y + 8} {CX + x + 8} {CY + y}", stroke="#A889B8", width=3.5))
    cheeks(a, y=CY + 40, dx=96)
    eyes(a, y=CY - 6, dx=54, size=1.25)
    by = CY + 34
    a.add(path(f"M {CX - 14} {by - 10} Q {CX} {by - 16} {CX + 14} {by - 10} Q {CX + 6} {by + 10} {CX} {by + 14} Q {CX - 6} {by + 10} {CX - 14} {by - 10} Z", fill="#FFB02E"))


@character("ghost", "Ghost", "night")
def ghost(a):
    d = (f"M {CX - 122} {CY + 60} L {CX - 122} {CY - 20} Q {CX - 122} {CY - 150} {CX} {CY - 150} Q {CX + 122} {CY - 150} {CX + 122} {CY - 20} "
         f"L {CX + 122} {CY + 96} Q {CX + 100} {CY + 132} {CX + 76} {CY + 104} Q {CX + 52} {CY + 136} {CX + 26} {CY + 106} "
         f"Q {CX} {CY + 138} {CX - 26} {CY + 106} Q {CX - 52} {CY + 136} {CX - 76} {CY + 104} Q {CX - 100} {CY + 132} {CX - 122} {CY + 96} Z")
    a.add(path(d, fill=a.gradient("#FFFFFF", "#F1EEF8", "#CFC8E2")))
    a.add(gloss(CX - 62, CY - 104, 30, 14))
    for side in (-1, 1):
        a.add(rotate(ellipse(CX + side * 132, CY + 10, 18, 34, "#ECE8F5"), side * -30, CX + side * 132, CY + 10))
    cheeks(a, y=CY + 18, dx=74)
    eyes(a, y=CY - 26, dx=44, size=1.05)
    mouth(a, y=CY + 12, style="o")


# Dinos & fantasy --------------------------------------------------------------

@character("dino", "Dino", "fantasy")
def dino(a):
    for i, (dx, h) in enumerate(((-58, 34), (-20, 46), (20, 46), (58, 34))):
        a.add(path(f"M {CX + dx - 20} {CY - 120 + abs(dx) * 0.4} L {CX + dx} {CY - 120 - h + abs(dx) * 0.4} L {CX + dx + 20} {CY - 120 + abs(dx) * 0.4} Z", fill="#FFB347"))
    head(a, ("#A6E39D", "#6CC66A", "#47A048"), rx=R + 12, ry=R - 14)
    for x, y, r in ((-86, -50, 10), (-60, -80, 7), (84, -60, 9), (100, -26, 6)):
        a.add(circle(CX + x, CY + y, r, "#58B257"))
    a.add(ellipse(CX, CY + 54, 92, 46, "#DDF6D2"))
    a.add(ellipse(CX - 22, CY + 30, 5, 4, "#3B8A3A"), ellipse(CX + 22, CY + 30, 5, 4, "#3B8A3A"))
    cheeks(a, y=CY + 28, dx=100)
    eyes(a, y=CY - 18, dx=56)
    if a.face == "happy":
        a.add(path(f"M {CX - 56} {CY + 46} Q {CX} {CY + 104} {CX + 56} {CY + 46} Z", fill="#5B2234"))
        for x in (-34, -12, 12, 34):
            a.add(path(f"M {CX + x - 7} {CY + 48} L {CX + x} {CY + 60} L {CX + x + 7} {CY + 48} Z", fill="#FFFFFF"))
    else:
        a.add(path(f"M {CX - 50} {CY + 52} Q {CX} {CY + 78} {CX + 50} {CY + 52}", stroke="#2F6B2E", width=5))
        a.add(path(f"M {CX - 28} {CY + 58} L {CX - 22} {CY + 68} L {CX - 16} {CY + 62} Z", fill="#FFFFFF"))
        a.add(path(f"M {CX + 28} {CY + 58} L {CX + 22} {CY + 68} L {CX + 16} {CY + 62} Z", fill="#FFFFFF"))


@character("triceratops", "Triceratops", "fantasy")
def triceratops(a):
    frill = a.gradient("#A8F0E8", "#6FD6CB", "#3EAFA3")
    n = 9
    for i in range(n):
        ang = math.radians(180 + i * 180 / (n - 1))
        a.add(circle(CX + math.cos(ang) * 150, CY - 10 + math.sin(ang) * 140, 30, "#4FC2B6"))
    a.add(ellipse(CX, CY - 10, 156, 146, frill))
    for x in (-60, 0, 60):
        a.add(circle(CX + x, CY - 110 + abs(x) * 0.5, 10, "#FFE08A", 0.9))
    for side in (-1, 1):
        a.add(path(f"M {CX + side * 44} {CY - 62} Q {CX + side * 60} {CY - 140} {CX + side * 36} {CY - 160} Q {CX + side * 30} {CY - 110} {CX + side * 18} {CY - 76} Z", fill="#FFF3D6"))
    head(a, ("#C4B3F2", "#9C86E0", "#7861C4"), y=CY + 20, rx=R - 26, ry=R - 30)
    a.add(path(f"M {CX - 14} {CY + 40} Q {CX} {CY - 10} {CX + 14} {CY + 40} Z", fill="#FFF3D6"))
    cheeks(a, y=CY + 52, dx=74, rx=17, ry=11)
    eyes(a, y=CY + 8, dx=46, size=0.92)
    mouth(a, y=CY + 70, style="smile", size=1.0)


@character("dragon", "Dragon", "fantasy")
def dragon(a):
    wing = "#6E5AB8"
    for side in (-1, 1):
        d = (f"M {CX + side * 96} {CY - 40} Q {CX + side * 190} {CY - 140} {CX + side * 196} {CY - 40} "
             f"Q {CX + side * 170} {CY - 54} {CX + side * 166} {CY - 20} Q {CX + side * 140} {CY - 36} {CX + side * 120} {CY + 10} Z")
        a.add(path(d, fill=wing))
    for side in (-1, 1):
        a.add(path(f"M {CX + side * 52} {CY - 100} Q {CX + side * 80} {CY - 160} {CX + side * 104} {CY - 168} Q {CX + side * 86} {CY - 130} {CX + side * 80} {CY - 96} Z", fill="#FFE6A8"))
    head(a, ("#B7A6F7", "#8C76E6", "#664FC4"), rx=R + 2, ry=R - 10)
    for dx in (-18, 0, 18):
        a.add(path(f"M {CX + dx - 10} {CY - 120} L {CX + dx} {CY - 144} L {CX + dx + 10} {CY - 120} Z", fill="#FF9FC6"))
    a.add(ellipse(CX, CY + 52, 70, 42, "#D9CFFF"))
    a.add(ellipse(CX - 18, CY + 40, 5, 4, "#5B45A8"), ellipse(CX + 18, CY + 40, 5, 4, "#5B45A8"))
    cheeks(a, y=CY + 30, dx=96)
    eyes(a, y=CY - 10, dx=52)
    mouth(a, y=CY + 58, style="smile", size=1.0)


@character("unicorn", "Unicorn", "fantasy")
def unicorn(a):
    mane = ["#FFB5D8", "#C9B5FF", "#A8DAFF", "#B8F0D0"]
    for i, (x, y, r) in enumerate(((-110, -60, 40), (-122, 0, 36), (-108, 58, 32), (-60, -104, 36), (-10, -124, 32))):
        a.add(circle(CX + x, CY + y, r, mane[i % len(mane)]))
    a.add(both(tri_ear(a, CX - 70, CY - 96, 50, 64, "#FFFFFF", "#FFC7DD", tilt=-14)))
    head(a, ("#FFFFFF", "#F6F2FB", "#DCD2EA"), rx=R - 6, ry=R - 8)
    horn = f"M {CX - 18} {CY - 112} L {CX} {CY - 190} L {CX + 18} {CY - 112} Z"
    a.add(path(horn, fill=a.gradient("#FFF6C8", "#FFD86A", "#F2B533")))
    for t in (0.3, 0.55, 0.78):
        y = CY - 112 - 78 * t
        w = 18 * (1 - t)
        a.add(path(f"M {CX - w} {y + 6} L {CX + w} {y - 4}", stroke="#E5A520", width=3))
    for i, (x, y, r) in enumerate(((-44, -112, 26), (-80, -84, 22))):
        a.add(circle(CX + x, CY + y, r, mane[(i + 1) % len(mane)]))
    a.add(ellipse(CX, CY + 56, 62, 40, "#FCE7F3"))
    a.add(ellipse(CX - 18, CY + 50, 5, 4, "#D58AB0"), ellipse(CX + 18, CY + 50, 5, 4, "#D58AB0"))
    cheeks(a, y=CY + 28, dx=86)
    eyes(a, y=CY - 6, dx=48)
    mouth(a, y=CY + 66, style="smile", size=0.85)


@character("alien", "Alien", "fantasy")
def alien(a):
    for side in (-1, 1):
        a.add(path(f"M {CX + side * 40} {CY - 110} Q {CX + side * 56} {CY - 160} {CX + side * 70} {CY - 176}", stroke="#8BDB6A", width=8),
              circle(CX + side * 72, CY - 180, 14, "#FF8FC6"))
    a.add(path(f"M {CX} {CY - 128} Q {CX + 146} {CY - 130} {CX + 140} {CY - 10} Q {CX + 130} {CY + 100} {CX} {CY + 124} "
               f"Q {CX - 130} {CY + 100} {CX - 140} {CY - 10} Q {CX - 146} {CY - 130} {CX} {CY - 128} Z", fill=a.gradient("#D4FFB8", "#9EE87A", "#6DC24A")))
    a.add(gloss(CX - 66, CY - 92, 30, 14))
    for side in (-1, 1):
        x = CX + side * 56
        if a.face == "open":
            a.add(rotate(ellipse(x, CY - 2, 34, 44, "#1E1A2B"), side * -24, x, CY - 2),
                  circle(x - 10, CY - 16, 9, "#FFFFFF"), circle(x + 10, CY + 14, 4, "#FFFFFF", 0.9))
        elif a.face == "blink":
            a.add(path(f"M {x - 26} {CY} Q {x} {CY + 18} {x + 26} {CY}", stroke=INK, width=6.5))
        else:
            a.add(path(f"M {x - 26} {CY + 8} Q {x} {CY - 20} {x + 26} {CY + 8}", stroke=INK, width=7))
    cheeks(a, y=CY + 50, dx=82)
    mouth(a, y=CY + 62, style="smile", size=0.9)


# ── Rendering ──────────────────────────────────────────────────────────────

def render_character(cid, fn, out_dir, tmp):
    frames = []
    for face in FACES:
        art = Art(cid, face)
        fn(art)
        svg_path = Path(tmp) / f"{cid}-{face}.svg"
        png_path = Path(tmp) / f"{cid}-{face}.png"
        svg_path.write_text(art.svg())
        subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), str(svg_path), "-o", str(png_path)], check=True)
        frames.append(Image.open(png_path).convert("RGBA"))
    # One shared crop for all faces, so they line up exactly.
    boxes = [im.getchannel("A").point(lambda v: 255 if v > 6 else 0).getbbox() for im in frames]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    pad = 3
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(SIZE, box[2] + pad), min(SIZE, box[3] + pad))
    w, h = box[2] - box[0], box[3] - box[1]
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        strip.paste(im.crop(box), (i * w, 0))
    strip.save(Path(out_dir) / f"{cid}.png", optimize=True)
    return strip, w, h


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    out_dir = Path(args[0])
    out_dir.mkdir(parents=True, exist_ok=True)
    only = None
    preview = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    if "--preview" in args:
        preview = Path(args[args.index("--preview") + 1])

    manifest = {
        "version": 1,
        "categories": [{"id": c, "name": n, "symbol": s} for c, n, s in CATEGORIES],
        "characters": [],
    }
    strips = []
    with tempfile.TemporaryDirectory() as tmp:
        for cid, name, category, fn in REGISTRY:
            manifest["characters"].append({
                "id": cid, "name": name, "category": category,
                "image": f"{cid}.png", "faces": list(FACES),
            })
            if only and cid not in only:
                continue
            strip, w, h = render_character(cid, fn, out_dir, tmp)
            strips.append((cid, strip, w, h))
            print(f"{cid:12s} {w}x{h}")
    if not only:
        (out_dir / "Library.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"{len(manifest['characters'])} characters")

    if preview:
        cell = 150
        cols = 9
        rows = math.ceil(len(strips) * 3 / cols)
        sheet = Image.new("RGBA", (cols * cell, rows * cell), (40, 40, 48, 255))
        k = 0
        for cid, strip, w, h in strips:
            for i in range(3):
                im = strip.crop((i * w, 0, (i + 1) * w, h))
                im.thumbnail((cell - 12, cell - 12), Image.LANCZOS)
                x = (k % cols) * cell + (cell - im.width) // 2
                y = (k // cols) * cell + (cell - im.height) // 2
                sheet.alpha_composite(im, (x, y))
                k += 1
        sheet.save(preview)


if __name__ == "__main__":
    main()
