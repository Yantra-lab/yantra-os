#!/usr/bin/env python3
"""measure.py — the project's frame metric, plus the two checks it cannot make.

`docs/DEMO-READY.md` §7 defines the frame statistic: width, height, distinct
colours on a 3-pixel sample, and ink fraction. That statistic is honest but
nearly blind: a texture swap can repaint 40 % of the frame and barely move the
colour count (the lead measured 16.97 % of pixels changing while colours moved
517 -> 506). So this script also reports, for a region or a pair of frames:

  * `--box X,Y,W,H`   the §7 statistic on ONE node's laid-out box, plus the
                      sha256 of that region's raw RGB — the asset's own
                      fingerprint, which changes whenever the pixels change;
  * two frames        the fraction of pixels that differ, and the mean absolute
                      channel difference, so "it changed" is a number not a mood.

Get the box from the engine itself, never by eye:
  /tmp/stage1/yantra --screenshot=/tmp/x.png --frames=8 --script="boxes" <abs>/app.wasm
prints `box <id> kind=<K> x=.. y=.. w=.. h=..`; K 5 = Image, 9 = Model,
8 = Scene3D.

Usage
  ./measure.py frame.png
  ./measure.py frame.png --box 16,63,480,500
  ./measure.py before.png after.png
"""
import argparse
import hashlib
import sys

from PIL import Image


def section7(im):
    """docs/DEMO-READY.md §7, verbatim — same sampling, same thresholds."""
    im = im.convert("RGB")
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
    return w, h, len(cols), nb / n


def region_sha(im):
    """A fingerprint of the region's pixels: same bytes -> same hash, always."""
    return hashlib.sha256(im.convert("RGB").tobytes()).hexdigest()


def one(path: str, box=None) -> int:
    im = Image.open(path).convert("RGB")
    if box:
        im = im.crop(box)
    w, h, cols, ink = section7(im)
    data = open(path, "rb").read()
    where = f"region {box[2] - box[0]}x{box[3] - box[1]} at {box[0]},{box[1]}" if box else "whole frame"
    print(f"{path}  [{where}]")
    print(f"  {w}x{h}  colours={cols}  ink={ink:.4f}  "
          f"file={len(data)} B  file_sha256={hashlib.sha256(data).hexdigest()}")
    print(f"  region_sha256={region_sha(im)}")
    return 0


def two(a: str, b: str) -> int:
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        print(f"different sizes: {ia.size} vs {ib.size}", file=sys.stderr)
        return 2
    pa, pb = ia.load(), ib.load()
    w, h = ia.size
    changed = total = 0
    acc = 0
    for y in range(h):
        for x in range(w):
            ca, cb = pa[x, y], pb[x, y]
            if ca != cb:
                changed += 1
                acc += sum(abs(ca[i] - cb[i]) for i in range(3))
            total += 1
    print(f"{a}  ->  {b}")
    print(f"  changed {changed}/{total} px = {changed / total:.4%}   "
          f"mean |dRGB| over changed = {acc / max(changed, 1):.1f}")
    for p in (a, b):
        w2, h2, cols, ink = section7(Image.open(p))
        print(f"  §7 {p}: {w2}x{h2} colours={cols} ink={ink:.4f}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--box", help="X,Y,W,H — one node's box, from --script=\"boxes\"")
    a = ap.parse_args()
    box = None
    if a.box:
        parts = [int(v) for v in a.box.split(",")]
        if len(parts) != 4:
            print("--box needs X,Y,W,H", file=sys.stderr)
            return 2
        box = (parts[0], parts[1], parts[0] + parts[2], parts[1] + parts[3])
    if len(a.paths) == 2:
        return two(a.paths[0], a.paths[1])
    return one(a.paths[0], box)


if __name__ == "__main__":
    sys.exit(main())
