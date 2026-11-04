#!/usr/bin/env node
// tools/make-icon.mjs — dependency-free ICO builder for the exe icon.
// Reads assets/brand/yantra-icon.png, writes render/native/yantra.ico with
// 16/32/48/256 px PNG-compressed entries (Vista+). Pure Node (zlib only):
// decode PNG32 (non-interlaced RGB/RGBA), box-downscale, re-encode.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync, deflateSync } from "node:zlib";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");

function crcTable() {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
}
const CRC_T = crcTable();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_T[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function decodePng(buf) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!buf.subarray(0, 8).equals(sig)) throw new Error("not a PNG");
  let pos = 8, w = 0, h = 0, bitDepth = 0, colorType = 0, idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString("ascii", pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      w = data.readUInt32BE(0); h = data.readUInt32BE(4);
      bitDepth = data[8]; colorType = data[9];
      const interlace = data[12];
      if (bitDepth !== 8 || ![2, 6].includes(colorType) || interlace !== 0)
        throw new Error(`unsupported PNG: depth=${bitDepth} color=${colorType} interlace=${interlace}`);
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }
    pos += 12 + len;
  }
  const ch = colorType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = w * ch;
  const px = Buffer.alloc(w * h * 4);
  let prev = Buffer.alloc(stride);
  let p = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[p++];
    const cur = raw.subarray(p, p + stride);
    p += stride;
    const out = px.subarray(y * w * 4, (y + 1) * w * 4);
    for (let i = 0; i < stride; i++) {
      const a = cur[i];
      const b = prev[i];
      const c = i >= ch ? prev[i - ch] : 0;
      const d = i >= ch ? cur[i - ch] : 0;
      let v = a;
      if (f === 1) v = (a + d) & 0xff;
      else if (f === 2) v = (a + b) & 0xff;
      else if (f === 3) v = (a + ((b + d) >> 1)) & 0xff;
      else if (f === 4) {
        const pp = b + d - c;
        const pa = Math.abs(pp - b), pb = Math.abs(pp - d), pc = Math.abs(pp - c);
        v = (a + (pa <= pb && pa <= pc ? b : pb <= pc ? d : c)) & 0xff;
      }
      const pix = (i / ch) | 0, comp = i % ch;
      if (comp < 3) out[pix * 4 + comp] = v;
      else if (ch === 4 && comp === 3) out[pix * 4 + 3] = v;
    }
    if (ch === 3) for (let i = 0; i < w; i++) out[i * 4 + 3] = 255;
    prev = Buffer.alloc(stride);
    for (let i = 0; i < stride; i++) {
      // prev must hold UNFILTERED bytes for the next row's predictor:
      // re-derive them from the final pixel values just written.
      const pix = (i / ch) | 0, comp = i % ch;
      prev[i] = comp < 3 ? out[pix * 4 + comp] : ch === 4 && comp === 3 ? out[pix * 4 + 3] : 255;
    }
  }
  return { w, h, px };
}

function scaleDown(src, size) {
  const { w, h, px } = src;
  const out = Buffer.alloc(size * size * 4);
  const sx = w / size, sy = h / size;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const x0 = Math.floor(x * sx), x1 = Math.min(w, Math.ceil((x + 1) * sx));
      const y0 = Math.floor(y * sy), y1 = Math.min(h, Math.ceil((y + 1) * sy));
      let r = 0, g = 0, b = 0, a = 0, n = 0;
      for (let yy = y0; yy < y1; yy++)
        for (let xx = x0; xx < x1; xx++) {
          const o = (yy * w + xx) * 4;
          r += px[o]; g += px[o + 1]; b += px[o + 2]; a += px[o + 3]; n++;
        }
      const o = (y * size + x) * 4;
      out[o] = Math.round(r / n); out[o + 1] = Math.round(g / n);
      out[o + 2] = Math.round(b / n); out[o + 3] = Math.round(a / n);
    }
  }
  return { w: size, h: size, px: out };
}

function encodePng(img) {
  const { w, h, px } = img;
  const stride = w * 4;
  const raw = Buffer.alloc(h * (stride + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (stride + 1)] = 0;
    px.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const src = decodePng(readFileSync(join(ROOT, "assets/brand/yantra-icon.png")));
console.log(`[icon] source ${src.w}x${src.h}`);
const entries = [];
for (const size of [16, 32, 48, 256]) {
  const png = encodePng(scaleDown(src, size));
  entries.push({ size, png });
  console.log(`[icon] ${size}x${size}: ${png.length} bytes`);
}
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(entries.length, 4);
let offset = 6 + 16 * entries.length;
const dir = Buffer.alloc(16 * entries.length);
entries.forEach((e, i) => {
  const o = i * 16;
  dir[o] = e.size >= 256 ? 0 : e.size;
  dir[o + 1] = e.size >= 256 ? 0 : e.size;
  dir[o + 4] = 1;
  dir.writeUInt16LE(32, o + 6);
  dir.writeUInt32LE(e.png.length, o + 8);
  dir.writeUInt32LE(offset, o + 12);
  offset += e.png.length;
});
writeFileSync(
  join(ROOT, "render/native/yantra.ico"),
  Buffer.concat([header, dir, ...entries.map((e) => e.png)])
);
console.log("[icon] wrote render/native/yantra.ico");
