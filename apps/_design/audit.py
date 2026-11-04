#!/usr/bin/env python3
"""audit.py — the design system's mechanical checker.

Reads a Yantra app source (Nim-syntax or Sutra-syntax, they look the same to this
script) and reports, per rule id from `skills/yantra/reference/25-frontend-craft-rules.md`:

  T1  a text size outside the eight-step scale
  T5  a font weight outside {400,500,600,700,800}
  S1  a gap / pad / margin outside the 4-pt rhythm
  R1  a radius outside {6,10,16}
  M1  a duration outside {120,180,280,360}
  X1  an app with no `hover:`/`pressed:`/`focused:` state block at all
  X2  an app with interactive controls but no `focused:` block
  C1  a text/border colour pair, on one statement, under its floor

It is deliberately a READER, not a compiler: it finds values, it does not type-check.
A clean run means "the numbers are on the system", not "the app is beautiful".

Usage
  python3 apps/_design/audit.py apps/arcade/app.nim            one app
  python3 apps/_design/audit.py apps/*/app.nim                 every app
  python3 apps/_design/audit.py --json apps/*/app.nim          machine-readable
  python3 apps/_design/audit.py --quiet apps/*/app.nim         totals only

Exit code 0 when every rule passes in every file, 1 otherwise. That is what makes
this usable as a check-every-commit hook.
"""
import argparse
import json
import re
import sys

# ── the tokens, mirrored from design.nim (kept in sync by hand; the source of
# truth is design.nim and a drift here is a bug in this file, not a new rule) ──
TYPE_SCALE = {11, 12, 14, 16, 20, 26, 34, 46}
WEIGHTS = {400, 500, 600, 700, 800}
RHYTHM = {4, 8, 12, 16, 24, 32, 48}
# S1b — an optical 1–2 px between a micro-label and its own value is allowed; it is
# the one place the 4-pt grid is wrong, and the app must be able to say so.
RHYTHM_OPTICAL = {1, 2}
RADII = {0, 6, 10, 16}   # 0 = deliberately square (the Terminal theme)
MOTION = {120, 180, 280, 360}
CONTRAST_BODY, CONTRAST_LARGE, CONTRAST_UI = 4.5, 3.0, 3.0

# Sizes that are legitimately not the app's own: the engine's defaults are a
# starting point, and a `Path` node defaults to 24.
IGNORE = object()

RE_SIZE = re.compile(r"\b(?:size|fontSize|fontsize)\s*[=(]\s*(\d+)")
RE_SIZE_IMPER = re.compile(r"\.fontSize\(\s*(\d+)")
RE_WEIGHT = re.compile(r"\bweight\s*=\s*(\d+)")
RE_WEIGHT_IMPER = re.compile(r"pFontWeight\s*,\s*(\d+)")
RE_SPACE = re.compile(r"\b(?:gap|pad|padX|padY|padTop|padRight|padBottom|padLeft|margin|"
                      r"marginX|marginY|marginTop|marginRight|marginBottom|marginLeft|spacing)\s*=\s*(\d+)")
RE_SPACE_IMPER = re.compile(r"\.(?:gap|pad|padAll)\(\s*(\d+)")
RE_RADIUS = re.compile(r"\bradius\s*=\s*(\d+)")
RE_RADIUS_IMPER = re.compile(r"\.radius\(\s*(\d+)")
RE_TRANSITION = re.compile(r"\btransition\s*=\s*(\d+)")
RE_MS = re.compile(r"\b(\d+)\s*\.ms\b")

# a colour literal, in either syntax the repo uses
RE_HEX = re.compile(r"0x([0-9A-Fa-f]{6,8})\b")
RE_HASH = re.compile(r"#([0-9A-Fa-f]{6,8})\b")
# `color = X` and `fill = Y` on the same statement is the pair worth judging
RE_TEXTCOL = re.compile(r"\b(?:color|textColor|colour)\s*=\s*(0x[0-9A-Fa-f]{6,8}|#[0-9A-Fa-f]{6,8})")
RE_FILLCOL = re.compile(r"\bfill\s*=\s*(0x[0-9A-Fa-f]{6,8}|#[0-9A-Fa-f]{6,8})")
RE_BORDER = re.compile(r"\bborderColor\s*=\s*(0x[0-9A-Fa-f]{6,8}|#[0-9A-Fa-f]{6,8})")
RE_HOVER = re.compile(r"^\s*hover\s*:", re.M)
RE_PRESSED = re.compile(r"^\s*pressed\s*:", re.M)
RE_FOCUSED = re.compile(r"^\s*focused\s*:", re.M)
RE_INTERACTIVE = re.compile(r"\b(button|Button|input|Input|textArea|TextArea|checkbox|Checkbox|"
                            r"switch|Switch|radio|Radio|slider|Slider)\b")


def srgb_lin(c):
    s = c / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    return (0.2126 * srgb_lin((rgb >> 16) & 0xFF)
            + 0.7152 * srgb_lin((rgb >> 8) & 0xFF)
            + 0.0722 * srgb_lin(rgb & 0xFF))


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_colour(tok):
    tok = tok.strip()
    if tok.startswith("#"):
        v = int(tok[1:], 16)
    elif tok.startswith("0x") or tok.startswith("0X"):
        v = int(tok[2:], 16)
    else:
        return None
    if v > 0xFFFFFF:      # 0xAARRGGBB — contrast is judged on the opaque form
        v &= 0xFFFFFF
    return v


def audit_file(path, text):
    """Returns [(rule, line_no, message)]."""
    out = []
    lines = text.splitlines()

    def scan(regex, rule, legal, label, imper=None, optical=()):
        rx = [regex] if imper is None else [regex, imper]
        for i, ln in enumerate(lines, 1):
            for r in rx:
                for m in r.finditer(ln):
                    v = int(m.group(1))
                    if v in optical and label == "spacing":
                        continue
                    if legal is not None and v not in legal:
                        out.append((rule, i, "%s %d is off the system (%s legal)"
                                    % (label, v, ", ".join(str(x) for x in sorted(legal)))))

    scan(RE_SIZE, "T1", TYPE_SCALE, "text size", RE_SIZE_IMPER)
    scan(RE_WEIGHT, "T5", WEIGHTS, "font weight", RE_WEIGHT_IMPER)
    scan(RE_SPACE, "S1", RHYTHM, "spacing", RE_SPACE_IMPER, RHYTHM_OPTICAL)
    scan(RE_RADIUS, "R1", RADII, "radius", RE_RADIUS_IMPER)
    scan(RE_TRANSITION, "M1", MOTION, "transition")
    scan(RE_MS, "M1", MOTION, "duration")

    hover, pressed, focused = bool(RE_HOVER.search(text)), bool(RE_PRESSED.search(text)), bool(RE_FOCUSED.search(text))
    interactive = bool(RE_INTERACTIVE.search(text))
    if interactive and not (hover or pressed or focused):
        out.append(("X1", 0, "has interactive controls but no hover:/pressed:/focused: block at all"))
    elif interactive and not focused:
        out.append(("X2", 0, "has interactive controls but no focused: block (X2: focus must be visible)"))

    # a text colour beside a fill on the same statement is a pair we can judge
    for i, ln in enumerate(lines, 1):
        tc = RE_TEXTCOL.search(ln)
        fc = RE_FILLCOL.search(ln)
        if tc and fc:
            ink, bg = parse_colour(tc.group(1)), parse_colour(fc.group(1))
            if ink is not None and bg is not None:
                r = contrast(ink, bg)
                # a size on the same statement decides which floor applies
                sz = RE_SIZE.search(ln)
                px = int(sz.group(1)) if sz else 14
                wt = RE_WEIGHT.search(ln)
                weight = int(wt.group(1)) if wt else 400
                # C2 by WCAG 2.2 SC 1.4.3: large is 24 px, or 19+ px bold (14 pt at 96 dpi)
                large = px >= 24 or (px >= 19 and weight >= 700)
                need = CONTRAST_LARGE if large else CONTRAST_BODY
                if r < need:
                    out.append(("C1", i, "text %s on fill %s is %.2f:1, floor %.1f:1"
                                % (tc.group(1), fc.group(1), r, need)))
        bc = RE_BORDER.search(ln)
        fc2 = RE_FILLCOL.search(ln)
        if bc and fc2:
            b, bg = parse_colour(bc.group(1)), parse_colour(fc2.group(1))
            if b is not None and bg is not None:
                r = contrast(b, bg)
                if r < CONTRAST_UI:
                    out.append(("C3", i, "border %s on fill %s is %.2f:1, floor %.1f:1"
                                % (bc.group(1), fc2.group(1), r, CONTRAST_UI)))
    return out


def main():
    ap = argparse.ArgumentParser(description="Check a Yantra app against the design rules.")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    report = {}
    total = 0
    for p in a.files:
        try:
            text = open(p, encoding="utf-8").read()
        except OSError as e:
            print("audit: cannot read %s (%s)" % (p, e), file=sys.stderr)
            continue
        found = audit_file(p, text)
        report[p] = found
        total += len(found)

    if a.json:
        print(json.dumps({p: [{"rule": r, "line": n, "message": m} for r, n, m in v]
                          for p, v in report.items()}, indent=2))
    elif a.quiet:
        for p, v in report.items():
            print("%-46s %s" % (p, "PASS" if not v else "%d findings" % len(v)))
        print("audit: %d file(s), %d finding(s)" % (len(report), total))
    else:
        for p, v in report.items():
            print("== %s" % p)
            if not v:
                print("   PASS")
            for r, n, m in v:
                loc = ("%s:%d" % (p, n)) if n else p
                print("   %-3s %s  %s" % (r, loc, m))
        print("audit: %d file(s), %d finding(s)" % (len(report), total))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
