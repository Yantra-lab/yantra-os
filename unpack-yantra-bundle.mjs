#!/usr/bin/env node
// unpack-yantra-bundle.mjs
// Extracts all <!-- FILE: relative/path --> fenced code blocks from
// YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md into the yantra-os repository root.
//
// Usage:
//   node unpack-yantra-bundle.mjs YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md /path/to/yantra-os

import fs from "node:fs";
import path from "node:path";

const bundlePath = process.argv[2] || "YANTRA_COMPLETE_IMPLEMENTATION_BUNDLE.md";
const targetRoot = path.resolve(process.argv[3] || ".");

if (!fs.existsSync(bundlePath)) {
  console.error(`[unpack] Bundle file not found: ${bundlePath}`);
  process.exit(1);
}

const raw = fs.readFileSync(bundlePath, "utf8");
const regex = /<!--\s*FILE:\s*([^\s]+)\s*-->\s*\r?\n```[^\r\n]*\r?\n([\s\S]*?)\r?\n```/g;

let match;
let count = 0;
while ((match = regex.exec(raw)) !== null) {
  const relPath = match[1].trim();
  const content = match[2];
  const fullPath = path.join(targetRoot, relPath);
  fs.mkdirSync(path.dirname(fullPath), { recursive: true });
  fs.writeFileSync(fullPath, content + "\n", "utf8");
  if (relPath.endsWith(".sh") || relPath.endsWith(".mjs")) {
    try { fs.chmodSync(fullPath, 0o755); } catch {}
  }
  console.log(`[unpack] Wrote ${relPath} (${Buffer.byteLength(content, "utf8")} bytes)`);
  count++;
}

console.log(`[unpack] Done! Extracted ${count} files into ${targetRoot}`);