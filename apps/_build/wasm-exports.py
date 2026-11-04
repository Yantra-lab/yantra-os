#!/usr/bin/env python3
"""Read a .wasm module's export and import names without running it.

Why this exists: the engine's whole contract with an app is its export table.
`host/host.nim` calls `yantra_main` to mount an app and `yantra_dispatch` to
hand it an event; a module missing them loads, prints
`crashed=[export not found: yantra_main]`, and draws a nearly empty frame —
which is exactly the failure a build script must catch before a screenshot
does. `node -e "WebAssembly.Module.exports"` also answers this, but python3 is
already required by metrics.py, so the build path needs no second runtime.

Usage:
    python3 wasm-exports.py <module.wasm>              # one line per name
    python3 wasm-exports.py --check yantra_main <m>    # exit 1 if it is absent
    python3 wasm-exports.py --imports <m>              # what the host must provide

Exit status: 0 when the file parses and every --check name is exported,
1 when a name is missing, 2 when the file is not a WebAssembly module.
"""

import sys

WASM_MAGIC = b"\x00asm"


def _uleb(buf, i):
    """Decode an unsigned LEB128 at i -> (value, next index)."""
    result = 0
    shift = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not b & 0x80:
            return result, i
        shift += 7
        if shift > 63:
            raise ValueError("LEB128 too long")


def _name(buf, i):
    """Decode a wasm `name` (a length-prefixed UTF-8 string)."""
    n, i = _uleb(buf, i)
    return buf[i:i + n].decode("utf-8", "replace"), i + n


KIND = {0: "function", 1: "table", 2: "memory", 3: "global", 4: "tag"}


def sections(buf):
    """Yield (section id, payload bytes)."""
    i = 8                       # magic + version
    while i < len(buf):
        sid = buf[i]
        i += 1
        size, i = _uleb(buf, i)
        yield sid, buf[i:i + size]
        i += size


def exports(buf):
    """[(name, kind)] in table order; 0 when the module exports nothing."""
    for sid, body in sections(buf):
        if sid != 7:
            continue
        count, i = _uleb(body, 0)
        out = []
        for _ in range(count):
            name, i = _name(body, i)
            kind = body[i]
            i += 1
            _, i = _uleb(body, i)          # the index the export points at
            out.append((name, KIND.get(kind, "kind%d" % kind)))
        return out
    return []


def imports(buf):
    """[(module, name, kind)] in table order."""
    for sid, body in sections(buf):
        if sid != 2:
            continue
        count, i = _uleb(body, 0)
        out = []
        for _ in range(count):
            mod, i = _name(body, i)
            name, i = _name(body, i)
            kind = body[i]
            i += 1
            if kind == 0:                  # function: a type index
                _, i = _uleb(body, i)
            elif kind == 1:                # table: elemtype + limits
                i += 1
                flags = body[i]
                i += 1
                _, i = _uleb(body, i)
                if flags & 1:
                    _, i = _uleb(body, i)
            elif kind == 2:                # memory: limits
                flags = body[i]
                i += 1
                _, i = _uleb(body, i)
                if flags & 1:
                    _, i = _uleb(body, i)
            elif kind == 3:                # global: valtype + mutability
                i += 2
            elif kind == 4:                # tag: attribute + type index
                i += 1
                _, i = _uleb(body, i)
            out.append((mod, name, KIND.get(kind, "kind%d" % kind)))
        return out
    return []


def main(argv):
    args = argv[1:]
    want = []
    show_imports = False
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag == "--check":
            if not args:
                sys.exit("wasm-exports.py: --check needs a name")
            want.append(args.pop(0))
        elif flag == "--imports":
            show_imports = True
        else:
            sys.exit("wasm-exports.py: unknown flag " + flag)
    if len(args) != 1:
        sys.exit("usage: wasm-exports.py [--check NAME]... [--imports] <module.wasm>")
    path = args[0]
    with open(path, "rb") as fh:
        buf = fh.read()
    if buf[:4] != WASM_MAGIC:
        print("wasm-exports.py: %s is not a WebAssembly module (magic %r)" % (path, buf[:4]),
              file=sys.stderr)
        return 2
    ex = exports(buf)
    names = [n for n, _ in ex]
    if show_imports:
        im = imports(buf)
        print("%d imports: %s" % (len(im), " ".join(sorted({m + "." + n for m, n, _ in im}))))
    else:
        print("%d exports: %s" % (len(ex), " ".join("%s:%s" % (n, k) for n, k in ex)))
    missing = [n for n in want if n not in names]
    for n in missing:
        print("wasm-exports.py: %s does not export `%s`" % (path, n), file=sys.stderr)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
