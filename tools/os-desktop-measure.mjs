#!/usr/bin/env node
// tools/os-desktop-measure.mjs — the desktop's line of measure.tsv, measured from the tree.
//
// WHY ITS OWN TOOL
//   The other eleven apps are Sutra cells: tools/os-measure.sh imports them into the
//   Atlas, has the Sutra compiler build them, and screenshots them. The desktop is the
//   SDK's own shell — one Nim source file built by tools/build-wasm.sh — so it is not
//   in that pipeline. Its numbers still must come from the files and from nowhere else,
//   which is what this script does: every figure below is read or measured here.
//
// WHAT IT MEASURES (nothing is typed)
//   source lines / bytes     apps/desktop/app.nim
//   module bytes / sha256    apps/desktop/app.wasm
//   proof w, h, bytes        proofs/desktop.png (decoded: zlib + PNG unfilter, no deps)
//   proof unique colours     the same decoded pixels
//
// USAGE
//   node tools/os-desktop-measure.mjs           print the row
//   node tools/os-desktop-measure.mjs --write   rewrite the desktop line of measure.tsv
//
// The proof PNG itself is drawn by the real engine:
//   render/native/build/sutra_shot apps/desktop/app.wasm proofs/desktop.png 1280 800 1 1
//   render/native/build/sutra_shot apps/desktop/app.wasm proofs/desktop-open.png 1280 800 1 1 "New Tab"
// (YANTRA_DATA pointed at an empty folder, so the desk starts with no windows.)

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { inflateSync } from 'node:zlib';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'apps/desktop/app.nim');
const WASM = join(ROOT, 'apps/desktop/app.wasm');
const PNG = join(ROOT, 'proofs/desktop.png');
const TSV = join(ROOT, 'measure.tsv');
const CAPABILITY = 'The shell: an Arc sidebar, a Caelestia bar, a shader wallpaper, windows that float or tile';

// --- a PNG decoder small enough to read: 8-bit truecolour, filter + zlib ----------
function decodePNG(path) {
  const b = readFileSync(path);
  if (b.readUInt32BE(0) !== 0x89504e47) throw new Error(`${path}: not a PNG`);
  let i = 8;
  let w = 0, h = 0, depth = 0, ctype = 0, interlace = 0;
  const idat = [];
  while (i < b.length) {
    const len = b.readUInt32BE(i);
    const type = b.toString('ascii', i + 4, i + 8);
    const body = b.subarray(i + 8, i + 8 + len);
    if (type === 'IHDR') {
      w = body.readUInt32BE(0); h = body.readUInt32BE(4);
      depth = body[8]; ctype = body[9]; interlace = body[12];
    } else if (type === 'IDAT') idat.push(body);
    else if (type === 'IEND') break;
    i += 12 + len;
  }
  if (depth !== 8 || (ctype !== 2 && ctype !== 6) || interlace !== 0)
    throw new Error(`${path}: only 8-bit RGB/RGBA, non-interlaced (this file: depth ${depth}, type ${ctype}, interlace ${interlace})`);
  const bpp = ctype === 6 ? 4 : 3;
  const stride = w * bpp;
  const raw = inflateSync(Buffer.concat(idat));
  const out = Buffer.alloc(h * stride);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const cur = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0;
      const up = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      if (f === 1) v += a;
      else if (f === 2) v += up;
      else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) {
        const p = a + up - c;
        const pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c);
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? up : c);
      } else if (f !== 0) throw new Error(`${path}: bad filter ${f}`);
      cur[x] = v & 0xff;
    }
    cur.copy(out, y * stride);
    prev = cur;
  }
  const seen = new Set();
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const o = y * stride + x * bpp;
      seen.add((out[o] << 16) | (out[o + 1] << 8) | out[o + 2]);
    }
  }
  return { w, h, colours: seen.size };
}

for (const p of [SRC, WASM, PNG]) if (!existsSync(p)) throw new Error(`missing ${p}`);
const text = readFileSync(SRC, 'utf8');
const lines = text.split('\n').length - 1;
const wasm = readFileSync(WASM);
const png = decodePNG(PNG);

const row = [
  'desktop', lines, wasm.length, wasm.length,
  createHash('sha256').update(wasm).digest('hex'),
  'proofs/desktop.png', png.w, png.h, readFileSync(PNG).length, png.colours, CAPABILITY,
].join('\t');

const args = process.argv.slice(2);
if (args.includes('--write')) {
  const tsv = readFileSync(TSV, 'utf8').split('\n');
  const at = tsv.findIndex((l) => l.startsWith('desktop\t'));
  if (at < 0) throw new Error('measure.tsv has no desktop row');
  tsv[at] = row;
  writeFileSync(TSV, tsv.join('\n'));
  console.log('os-desktop-measure: rewrote the desktop row of measure.tsv');
}
console.log(row);
