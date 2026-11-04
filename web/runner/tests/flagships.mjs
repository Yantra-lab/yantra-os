// Real Sutra artifacts: startup globals, guest state, retained drawing, clicks,
// pointer dispatches, frames and the layer-write memory boundary.
// Optional: node web/runner/tests/flagships.mjs /path/ink.wasm /path/poster.wasm
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { YantraWebRunner, K, P, E } from '../runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
assert.ok(args.length === 0 || args.length === 2, 'pass both ink.wasm and poster.wasm, or neither');
const inkPath = args[0] ? resolve(args[0]) : join(here, '../../../apps/ink/app.wasm');
const posterPath = args[1] ? resolve(args[1]) : join(here, '../../../apps/poster/app.wasm');
let passed = 0;
const check = (condition, message) => { assert.ok(condition, message); passed++; console.log(`ok ${passed} - ${message}`); };
const live = (r) => r.getNodes().filter((n) => n.alive);
const canvas = (r) => {
  const n = live(r).find((n) => n.kind === K.CANVAS);
  assert.ok(n, 'live canvas');
  return n;
};
const text = (r) => live(r).filter((n) => n.kind === K.TEXT).map((n) => n.props[P.TEXT]).join('\n');
const click = (r, label) => {
  const button = live(r).find((n) => n.kind === K.BUTTON && n.props[P.TEXT] === label);
  assert.ok(button, `button ${label}`);
  button.el.click();
};
const boot = (path, setup) => {
  const bytes = readFileSync(path);
  const runner = new YantraWebRunner();
  setup?.(runner);
  runner.initSync(bytes);
  console.log(`module ${path} (${bytes.length} bytes)`);
  return runner;
};

{
  const r = boot(posterPath);
  check(live(r).length === 76, 'poster builds its 76 live nodes after _start');
  check(r.nodes[0].kind === K.WINDOW && r.nodes[0].props[P.TEXT] === 'Poster', 'poster has a real window');
  check(canvas(r).props[P.DRAW].includes('HAUS RASTER'), 'poster emits its retained sheet drawing');
  check(canvas(r).el.width === 640 && canvas(r).el.height === 824, 'poster canvas backing store matches its sheet');
  const initial = canvas(r).props[P.DRAW];
  check(text(r).includes('Signal paper + ink  /  density 02'), 'poster initial state is edition 0417 / Signal');
  click(r, 'Grid  /  off');
  check(text(r).includes('Grid  /  on') || live(r).some((n) => n.props[P.TEXT] === 'Grid  /  on'), 'a real click toggles the grid control once');
  check(canvas(r).props[P.DRAW] !== initial, 'the grid click changes the retained drawing');
  click(r, 'COBALT');
  check(text(r).includes('Cobalt paper + ink'), 'palette click updates guest state');
  click(r, 'Reset to edition 0417');
  check(canvas(r).props[P.DRAW] === initial, 'reset restores the original poster bytes');
}

{
  let px = 400, py = 400;
  const writes = [];
  const r = boot(inkPath, (runner) => {
    runner.env.y_node_size = (_n, axis) => axis === 7 ? px : axis === 8 ? py : 0;
    const original = runner._layerWrite.bind(runner);
    runner._layerWrite = (id, x, y, w, h, ptr) => {
      writes.push(new Uint8Array(runner.memory.buffer, ptr, w * h * 4).slice());
      return original(id, x, y, w, h, ptr);
    };
  });
  const initial = Buffer.from(writes[0] || []);
  check(live(r).length === 21, 'ink builds its 21 live nodes after _start');
  check(r.nodes[0].kind === K.WINDOW && r.nodes[0].props[P.TEXT] === 'Ink', 'ink has a real window');
  check(writes.length === 1 && initial.length === 168 * 108 * 4, 'initial art crosses y_layer_write with a full RGBA lattice');
  check(initial.every((v, i) => i % 4 !== 3 || v === 255), 'every guest-written dye pixel is opaque');
  check(canvas(r).props[P.DRAW].includes('touch the water'), 'ink emits its retained washi drawing');
  check(canvas(r).el.width === 1280 && canvas(r).el.height === 816, 'ink canvas backing store matches its simulation view');
  check(text(r).includes('SUMI · GENTLE · 0 drops · 0 stirs · frame 0'), 'ink initial state is visible');

  r._fire(canvas(r).id, E.POINTERDOWN);
  check(text(r).includes('1 drops'), 'pointerDown adds a real dye drop');
  check(writes.length === 2 && !initial.equals(writes[1]), 'the drop changes guest RGBA memory before the FFI copy');
  px = 520; py = 460;
  r._fire(canvas(r).id, E.POINTERMOVE);
  check(text(r).includes('SUMI · GENTLE · 1 drops · 1 stirs · frame 0'), 'pointerMove stirs while held');
  r._fire(canvas(r).id, E.POINTERUP);
  px = 600; py = 480;
  r._fire(canvas(r).id, E.POINTERMOVE);
  check(text(r).includes('SUMI · GENTLE · 1 drops · 1 stirs · frame 0'), 'pointerMove after pointerUp does not stir');
  const beforeFrame = writes.length;
  const frameNode = live(r).find((n) => r.handlers.has(`${n.id}:${E.FRAME}`));
  assert.ok(frameNode, 'the Stack owns the frame handler');
  r._fire(frameNode.id, E.FRAME);
  check(text(r).includes('frame 1'), 'a frame advances simulation state');
  check(writes.length === beforeFrame + 1, 'the frame writes a freshly simulated RGBA lattice');
  click(r, 'CURRENT');
  check(text(r).includes('CURRENT · 1 drops'), 'a real pigment-panel click changes flow state');
  click(r, 'NEW SHEET');
  check(text(r).includes('SUMI · CURRENT · 0 drops · 0 stirs · frame 0'), 'NEW SHEET resets simulation counters');
  check(initial.equals(writes.at(-1)), 'NEW SHEET restores the initial guest pixel bytes');
}

console.log(`flagship web behavior: ${passed} assertions passed`);
