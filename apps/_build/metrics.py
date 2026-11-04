#!/usr/bin/env python3
"""The project's official frame metric — docs/DEMO-READY.md §7, verbatim.

    from PIL import Image
    im = Image.open(path).convert('RGB'); w, h = im.size; px = im.load()
    cols, nb, n = set(), 0, 0
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            c = px[x, y]; cols.add(c); n += 1
            if sum(c) > 24: nb += 1
    print(w, h, len(cols), nb / n)     # width, height, distinct colours (3-px sample), ink fraction

Four numbers, and what each one is good for:

  WxH       the frame the engine actually produced. A module that asks for a
            1280x816 window is still drawn onto the engine's 1440x900 surface,
            so this is the surface, not the app.
  colours   distinct RGB triples on a 3-pixel grid. This is the metric parity is
            judged by: a rebuild that loses a shader, a texture or a font
            rasteriser loses colours, and nothing else changes the count as
            sharply. Two modules with the same count are not *proven* identical
            (compare the PNG sha256 for that), but two modules whose counts
            differ are proven different.
  ink       the fraction of sampled pixels brighter than sum(RGB) > 24, i.e. not
            black. It catches the failure the colour count cannot see: a frame
            that keeps its palette but loses its geometry still has the same
            colours and half the ink.

Usage:
    python3 metrics.py <shot.png> [more.png ...]

Prints one line per file:

    path size_bytes WxH colours ink

`size_bytes` is the PNG file's size, so one line carries the whole record of a
frame — the path, what the file weighs, what it is and what is in it. shot.sh
prints exactly this line, so a table built from shot.sh output never needs a
second command to be reproducible.
"""

import os
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the box has PIL 12.3; say so if not
    sys.exit("metrics.py: Pillow is not installed (need `python3 -m pip install pillow`)")


def measure(path):
    """(width, height, distinct_colours, ink_fraction) for one frame."""
    im = Image.open(path).convert('RGB')
    w, h = im.size
    px = im.load()
    cols, nb, n = set(), 0, 0
    for y in range(0, h, 3):
        for x in range(0, w, 3):
            c = px[x, y]
            cols.add(c)
            n += 1
            if sum(c) > 24:
                nb += 1
    return w, h, len(cols), (nb / n if n else 0.0)


def main(argv):
    if len(argv) < 2:
        sys.exit("usage: metrics.py <shot.png> [more.png ...]")
    bad = 0
    for path in argv[1:]:
        if not os.path.isfile(path):
            print("metrics.py: no such file: " + path, file=sys.stderr)
            bad = 1
            continue
        w, h, colours, ink = measure(path)
        print("%s %d %dx%d %d %.3f" % (path, os.path.getsize(path), w, h, colours, ink))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv))
