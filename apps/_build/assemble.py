#!/usr/bin/env python3
"""Assemble a Sutra *cell* into a compilable module — the part of the Atlas a
build needs when there is no database.

An app under apps/<id>/app.nim is not a program. It is a cell: one file of
Sutra that the Atlas wraps in three things before the compiler ever sees it
(host/atlas/build.nim):

  :14-20    the prelude — shebang, four imports, six feature switches
  :351-370  for every `record Name` block, a plain Nim `type Name* = object`
            declaration, emitted BEFORE the cell's own text (:432-440 emit
            every record/type/extend/uses cell before every other cell)
  :500-511  the engine's protocol — yantra_main, yantra_dispatch,
            sutra_refresh, sutra_param_changed

Skipping the prelude or the protocol costs the module every node-building call
(dead-code elimination finds no caller) and it renders almost nothing. Skipping
the record types costs the compile outright: the `record` plugin's output
refers to the type and nothing has declared it, so nimsem says
`undeclared identifier: Entry` / `expected: typedesc[Entry] but got: auto`.

The two transforms below are ports of the Atlas's own procs, name for name:
`withoutOnDelete` (:52-63), `anyOfMarked` (:161-170), `linksMarked` (:172-206),
`recordType` (:351-370). They are ports, not reinventions: a field whose type
is another record (or `User`) is a link to a row and must be written
`Link[User]` in the type as well as in the block, or the two disagree.

Usage:
    python3 assemble.py <cell.nim> <out.nim> [--view Name] [--prelude FILE]

`--view` names the view the engine mounts; the default is the LAST top-level
`view Name` in the file, which is the cell the Atlas mounts (`cells[^1]`).
`--prelude` replaces the built-in 8-line prelude (for comparing against a
different one).
"""

import re
import sys

PRELUDE = """#! sutra
import sutra/prelude, sutraui, yantra/engine, std/[math, strutils, assertions]
{.feature: "assumeSync".}
{.feature: "lenientFloats".}
{.feature: "implicitResult".}
{.feature: "autoclosures".}
{.feature: "canraise".}
{.feature: "implicitRaises".}
"""

# host/atlas/build.nim: the words that are not field names in a record body.
NOT_A_FIELD = ("can", "unique", "check", "search", "index")

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
IDENT_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")


def without_on_delete(line):
    """`customer: Customer on delete keep` -> `customer: Customer` (:52-63)."""
    for words in (" on delete ", " renamed from "):
        at = line.find(words)
        if at < 0:
            continue
        e = at + len(words)
        while e < len(line) and line[e] in IDENT_CHARS:
            e += 1
        line = line[:at] + line[e:]
    return line


def any_of_marked(line, records):
    """`on: Post or Photo` -> `on: AnyLink` (:161-170)."""
    colon = line.find(":")
    if colon <= 0 or " or " not in line:
        return line
    e = len(line)
    while e > 0 and line[e - 1] in "\r\n":
        e -= 1
    parts = line[colon + 1:e].split(" or ")
    for p in parts:
        if p.strip not in records:
            return line
    return line[:colon + 1] + " AnyLink" + line[e:]


def links_marked(source, records):
    """Mark every field whose type is a record (or `User`) as a link (:172-206)."""
    out = []
    for raw in source.splitlines(keepends=True):
        line = any_of_marked(without_on_delete(raw), records)
        colon = line.find(":")
        head = line[:colon].strip() if colon > 0 else ""
        if colon > 0 and line and line[0] == " " and IDENT.match(head) and head not in NOT_A_FIELD:
            i = colon + 1
            while i < len(line) and line[i] == " ":
                i += 1
            j = i
            while j < len(line) and line[j] in IDENT_CHARS:
                j += 1
            t = line[i:j]
            if t == "sealed" and j < len(line) and line[j] == " ":
                k = j
                while k < len(line) and line[k] == " ":
                    k += 1
                e = k
                while e < len(line) and line[e] not in " #=\r\n":
                    e += 1
                out.append(line[:i] + "Sealed[" + line[k:e] + "]" + line[e:])
                continue
            if t == "User" or t in records:
                out.append(line[:i] + "Link[" + t + "]" + line[j:])
                continue
            if t == "seq" and j < len(line) and line[j] == "[":
                k = j + 1
                while k < len(line) and line[k] in IDENT_CHARS:
                    k += 1
                inner = line[j + 1:k]
                if k < len(line) and line[k] == "]" and (inner == "User" or inner in records):
                    out.append(line[:j + 1] + "Link[" + inner + "]" + line[k:])
                    continue
        out.append(line)
    return "".join(out)


def record_type(source):
    """A record block's type as plain Nim (:351-370)."""
    lines = source.splitlines()
    name = lines[0].split()[1]
    out = ["type " + name + "* = object", "  id*: string"]
    for raw in lines[1:]:
        if raw.strip() == "open":
            out.append("  vjdoc*: Doc")          # its document (book §3.6)
        line = without_on_delete(raw)
        colon = line.find(":")
        if colon <= 0 or not line or line[0] != " ":
            continue
        head = line[:colon].strip()
        if not IDENT.match(head) or head in NOT_A_FIELD:
            continue
        typ = line[colon + 1:]
        for cut in (" #", "="):
            at = typ.find(cut)
            if at >= 0:
                typ = typ[:at]
        out.append("  " + head + "*: " + typ.strip())
    return "\n".join(out) + "\n"


def blocks(src, keyword):
    """Every top-level `keyword Name` and its span: [(name, first, last)]."""
    lines = src.splitlines()
    found = []
    i = 0
    while i < len(lines):
        m = re.match(r"^" + keyword + r" +([A-Za-z_][A-Za-z0-9_]*)", lines[i])
        if not m:
            i += 1
            continue
        j = i + 1
        while j < len(lines) and (lines[j] == "" or lines[j][0] in " \t"):
            j += 1
        while j > i + 1 and lines[j - 1].strip() == "":
            j -= 1
        found.append((m.group(1), i, j))
        i = j
    return found


def top_level_views(src):
    return re.findall(r"(?m)^view +([A-Za-z_][A-Za-z0-9_]*)", src)


def epilogue(src, view):
    """The four procs the host calls, minus any the cell already writes."""
    def has(name):
        return ('exportc: "%s"' % name) in src
    out = []
    if view and not has("yantra_main"):
        out.append('proc yantra_main() {.exportc: "yantra_main".} =')
        out.append('  vjMount("%s", proc (p: int32) = %s(VjParent(p)))' % (view, view))
    if not has("yantra_dispatch"):
        out.append('proc yantra_dispatch(h: int32) {.exportc: "yantra_dispatch".} = vjDispatch(h)')
    if view and not has("sutra_refresh"):
        out.append('proc sutra_refresh() {.exportc: "sutra_refresh".} = vjRedraw()')
    if view and not has("sutra_param_changed"):
        out.append('proc sutra_param_changed(i: int32) {.exportc: "sutra_param_changed".} = '
                   'vjParamChanged(i)')
    return "\n".join(out) + "\n" if out else ""


def assemble(src, view, prelude):
    """The whole module text: prelude, record types, the cell, the protocol."""
    found = blocks(src, "record")
    names = [n for n, _, _ in found]
    lines = src.splitlines(keepends=True)
    marked = {}                     # first line -> the marked block's lines
    text = [prelude]
    if names:
        text.append("\n# ── the records' types, declared before the cell that uses them\n")
        for _, first, last in found:
            block = "".join(lines[first:last])
            text.append(record_type(links_marked(block, names)) + "\n")
            marked[first] = links_marked(block, names).splitlines(keepends=True)
    # The cell's own text, with each record block links-marked exactly as the
    # Atlas emits it (:484-491) — the block and its type must agree, or the
    # plugin's generated accessors disagree with the declared field.
    for _, first, last in reversed(found):
        lines[first:last] = marked[first]
    text.append("\n# ── the cell\n")
    text.append("".join(lines))
    text.append("\n# ── the engine protocol (host/atlas/build.nim:500-511)\n")
    text.append(epilogue(src, view))
    return "".join(text)


def main(argv):
    args = argv[1:]
    view = None
    prelude = PRELUDE
    pos = []
    while args:
        a = args.pop(0)
        if a == "--view":
            view = args.pop(0)
        elif a == "--prelude":
            with open(args.pop(0)) as fh:
                prelude = fh.read()
        elif a.startswith("--"):
            sys.exit("assemble.py: unknown flag " + a)
        else:
            pos.append(a)
    if len(pos) != 2:
        sys.exit("usage: assemble.py <cell.nim> <out.nim> [--view Name] [--prelude FILE]")
    cell, out = pos
    with open(cell) as fh:
        src = fh.read()
    if view is None:
        views = top_level_views(src)
        if not views:
            sys.exit("assemble.py: %s has no top-level `view`; pass --view Name" % cell)
        view = views[-1]
    if view not in top_level_views(src):
        sys.exit("assemble.py: %s declares no `view %s`" % (cell, view))
    with open(out, "w") as fh:
        fh.write(assemble(src, view, prelude))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
