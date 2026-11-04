#!/usr/bin/env node
// tools/verify-wasm.mjs — does this app module actually run?
//
// WHAT IT PROVES
//   The module in front of you instantiates inside a sandbox with no API keys,
//   no GPU and no network, and the code that runs at instantiation builds a
//   live UI tree through the same protocol the native engine speaks. It reports
//   the size, the sha256 and the node census it measured.
//
// WHAT IT DOES NOT PROVE
//   Pixels. This script never renders and never compares two images. It used to
//   print "155/155 pixel-diff rounds matched" as a literal string; that number
//   was not measured here, so it is gone. A pixel claim needs a renderer and a
//   reference frame; the behaviour suites under web/runner/tests/ check
//   gestures and values instead.
//
// USAGE
//   node tools/verify-wasm.mjs apps/<name>       # a folder holding app.wasm
//   node tools/verify-wasm.mjs path/to/app.wasm  # or a module directly
//
//   Exit code 0 = PASS, 1 = FAIL (with the reason).
//
// The tables judges read are produced by verify_all.sh and tools/os-measure.sh;
// this script is the single-app primitive those two call.

import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const target = process.argv[2] || 'apps/typewriter';

let wasmPath = target;
if (existsSync(join(target, 'app.wasm'))) wasmPath = join(target, 'app.wasm');
else if (existsSync(`${target}.wasm`)) wasmPath = `${target}.wasm`;
else if (!existsSync(wasmPath)) {
  console.error(`[FAIL] no module at: ${target}`);
  console.error('RESULT: FAIL');
  process.exit(1);
}

const absPath = resolve(wasmPath);
const wasmBytes = readFileSync(absPath);
const sha = createHash('sha256').update(wasmBytes).digest('hex');

console.log('Yantra OS · module verifier');
console.log(`  module      ${absPath.replace(ROOT + '/', '')}`);
console.log(`  size        ${wasmBytes.length} bytes (${(wasmBytes.length / 1024).toFixed(1)} KiB)`);
console.log(`  sha256      ${sha}`);
console.log(`  runtime     node ${process.version}, web/runner/runner.js — no keys, no GPU, no network`);

const runnerUrl = pathToFileURL(join(ROOT, 'web', 'runner', 'runner.js')).href;
const t0 = process.hrtime.bigint();
let runner;
try {
  const { YantraWebRunner, K, P } = await import(runnerUrl);
  const module = new WebAssembly.Module(wasmBytes);
  const exported = new Set(WebAssembly.Module.exports(module).map((e) => e.name));
  if (!exported.has('yantra_main')) throw new Error('module exports no yantra_main entrypoint');
  // Keep the runner before initSync so a startup trap can print guest logs.
  runner = new YantraWebRunner();
  runner.initSync(module);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;

  const alive = runner.getNodes().filter((n) => n.alive);
  const root = runner.getRootElement();
  if (!root) throw new Error('the module built no root element');
  if (!alive.length) throw new Error('the module built no nodes');
  const windowNode = alive.find((n) => n.kind === K.WINDOW && n.el === root);
  if (!windowNode) throw new Error('the root element is not a live window node');

  const census = {};
  for (const n of alive) {
    const kind = Object.keys(K).find((k) => K[k] === n.kind) ?? `unknown_${n.kind}`;
    census[kind] = (census[kind] || 0) + 1;
  }
  const censusText = Object.entries(census)
    .sort((a, b) => b[1] - a[1])
    .map(([k, v]) => `${k} ${v}`)
    .join(', ');
  let drawBytes = 0;
  for (const n of alive) if (typeof n.props?.[P.DRAW] === 'string') drawBytes += n.props[P.DRAW].length;

  console.log(`  instantiate ${ms.toFixed(1)} ms`);
  console.log(`  startup     NimMain=${exported.has('NimMain')} _start=${exported.has('_start')} exit=${runner.startExitCode ?? 'returned'} memory=${runner.memory?.buffer.byteLength || 0} bytes`);
  console.log(`  window      ${JSON.stringify(windowNode.props?.[P.TEXT] || '')} (${census.WINDOW} live window)`);
  console.log(`  ui tree     ${alive.length} live nodes: ${censusText}`);
  console.log(`  retained    ${drawBytes} bytes of draw commands`);
  console.log('[PASS] the module instantiates and builds a live UI tree');
  console.log('       (no pixels were compared — this script does not render)');
  console.log('RESULT: PASS');
  process.exit(0);
} catch (err) {
  console.error(`[FAIL] ${err?.message || err}`);
  if (err?.stack) console.error(err.stack);
  if (runner?.logs?.length) console.error(`  guest log   ${JSON.stringify(runner.logs.join(''))}`);
  console.error('RESULT: FAIL');
  process.exit(1);
}
