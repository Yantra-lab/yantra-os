#!/usr/bin/env python3
"""Make the PLACEHOLDER poster — the frame we measure before the GPU fleet has an
artefact, so that the swap to a real one is a controlled change of one file.

It is deliberately NOT a generated image: no model produced it, so PROVENANCE.tsv
says `placeholder:hand-made` rather than naming a model it never saw. Every pixel
is a formula, so re-running this script reproduces the same bytes.

    ./placeholder.py apps/_assets/demo/assets/poster.png
"""
import sys
from PIL import Image, ImageDraw

W = H = 512


def main(out: str) -> int:
    im = Image.new("RGB", (W, H), (11, 13, 18))
    px = im.load()
    for y in range(H):
        for x in range(W):
            # a diagonal two-tone ramp: unique, countable, and obviously not a photo
            t = (x + y) / (W + H - 2)
            if (x // 32 + y // 32) % 2 == 0:
                px[x, y] = (int(18 + 60 * t), int(28 + 74 * t), int(46 + 92 * t))
            else:
                px[x, y] = (int(10 + 30 * t), int(14 + 36 * t), int(22 + 44 * t))
    d = ImageDraw.Draw(im)
    d.rectangle([24, 24, W - 24, H - 24], outline=(232, 236, 242), width=2)
    d.rectangle([0, H // 2 - 40, W, H // 2 + 40], fill=(8, 10, 14))
    d.text((W // 2 - 96, H // 2 - 18), "PLACEHOLDER", fill=(232, 236, 242))
    d.text((W // 2 - 132, H // 2 + 2), "no gpu-fleet artefact yet", fill=(142, 154, 174))
    d.text((24, H - 44), "apps/_assets/demo", fill=(142, 154, 174))
    im.save(out, "PNG", optimize=True)
    print(f"{out} {W}x{H} {len(open(out, 'rb').read())} B")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1
                  else "apps/_assets/demo/assets/poster.png"))
