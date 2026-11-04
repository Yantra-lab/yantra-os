// Handler timing: measures wasm-side ms per key/click/frame via web runner.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { YantraWebRunner } from '../runner.js';
import { K, P, E } from '../protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../../..');
const DT = 0.1;
const scripted = { code: 0, mods: 0, px: 0, py: 0 };
const runner = new YantraWebRunner({});
runner.env.y_key = (w) => (w === 0 ? scripted.code : w === 1 ? scripted.mods : 0);
runner.env.y_node_size = (n, ax) => {
  if (n === 0 && (ax === 7 || ax === 13)) return scripted.px;
  if (n === 0 && (ax === 8 || ax === 14)) return scripted.py;
  return 0;
};
const origInput = runner.env.y_input;
runner.env.y_input = (what, arg) => (what === 7 ? DT : origInput(what, arg));
runner.env.y_layer_read = (id, x, y, w, h, p) => {
  const n = w * h * 4, mem = new Uint8Array(runner.memory.buffer);
  for (let i = 0; i < n; i++) mem[p + i] = (i * 7 + x + y) & 0xff;
  return n;
};
runner.env.y_pick_save = () => 7;
runner.env.y_pick_status = () => 200;
runner.initSync(readFileSync(join(ROOT, 'apps/typewriter/app.wasm')));

const live = () => runner.getNodes().filter((n) => n.alive);
const canvas = live().find((n) => n.kind === K.CANVAS);
const keyNodeId = Number([...runner.handlers.keys()].find((k) => k.endsWith(':' + E.KEY)).split(':')[0]);
const key = (code, mods = 0) => { scripted.code = code; scripted.mods = mods; runner._fire(keyNodeId, E.KEY); };
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(canvas.id, E.FRAME); };
frames(8); // settle (bakes layers once)

const bench = (label, fn) => {
  const t0 = process.hrtime.bigint();
  fn();
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  console.log(label + ': ' + ms.toFixed(2) + 'ms');
  return ms;
};

// warm LTO/caches
for (let i = 0; i < 5; i++) key(97);
let worst = 0;
const t0 = process.hrtime.bigint();
for (let i = 0; i < 50; i++) {
  const s = process.hrtime.bigint();
  key(97 + (i % 26));
  const ms = Number(process.hrtime.bigint() - s) / 1e6;
  if (ms > worst) worst = ms;
}
const avg50 = Number(process.hrtime.bigint() - t0) / 1e6 / 50;
console.log('50x typeChar avg: ' + avg50.toFixed(2) + 'ms, worst: ' + worst.toFixed(2) + 'ms');
bench('carriageReturn (Enter)', () => key(13));
frames(30);
bench('5 settle frames', () => frames(5));
const btn = (t) => live().find((n) => n.kind === K.BUTTON && n.el.textContent === t);
bench('New sheet click', () => btn('New sheet').el.click());
frames(100); // run sheet swap anim to completion
bench('100 anim frames', () => {});
bench('Save letter click (full PNG encode)', () => btn('Save letter').el.click());
console.log(worst < 100 && avg50 < 100 ? 'HANDLER BUDGET OK (<100ms)' : 'HANDLER BUDGET EXCEEDED');
