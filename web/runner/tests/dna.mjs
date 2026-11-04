// web/runner/tests/dna.mjs
// Headless interaction suite for the Helix DNA port.
// Run: node web/runner/tests/dna.mjs   (requires apps/dna/app.wasm built)
// Drives the real wasm through YantraWebRunner with scripted key/pointer/frame
// input and asserts the full contract of 052-dna-helix.html: drag-rotate with
// inertia, hover pick + tooltip + strip highlight, ann hover, zoom buttons and
// keys, auto-rotate toggle, reset, panel scroll, sequence input + validation +
// random + stats, the unzip/replicate/rejoin state machine with captions, and
// the dark theme toggle.
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { YantraWebRunner } from '../runner.js';
import { K, P, E } from '../protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../../..');
const DT = 0.1; // 100 ms logic frames (clamped to 50 ms inside tickPlay)
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
let layerSeq = 0;
runner.env.y_layer_new = () => ++layerSeq;
runner.initSync(readFileSync(join(ROOT, 'apps/dna/app.wasm')));

const live = () => runner.getNodes().filter((n) => n.alive);
const canvas = live().find((n) => n.kind === K.CANVAS);
const draw = () => canvas.props[P.DRAW];
const norm = () => draw().replace(/\d+\.\d+/g, (n) => (+n).toFixed(1));
const keyNodeId = Number([...runner.handlers.keys()].find((k) => k.endsWith(':' + E.KEY)).split(':')[0]);
const key = (code, mods = 0) => { scripted.code = code; scripted.mods = mods; runner._fire(keyNodeId, E.KEY); };
const down = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERDOWN); };
const move = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERMOVE); };
const up = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERUP); };
const click = (x, y) => { down(x, y); up(x, y); };
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(canvas.id, E.FRAME); };

let passed = 0;
const ok = (c, m) => { assert(c, m); passed++; console.log('ok - ' + m); };

const SUN = 'M10 1.8v2M10 16.2v2M1.8 10h2M16.2 10h2M4.2 4.2l1.4 1.4M14.4 14.4l1.4 1.4M4.2 15.8l1.4-1.4M14.4 5.6l1.4-1.4';
const MOON = 'M16.5 12.4A7 7 0 0 1 7.6 3.5a7 7 0 1 0 8.9 8.9Z';
const PAUSE = 'M7 4.5v11M13 4.5v11';
const PLAY = 'M6.5 4.2L15.5 10L6.5 15.8L6.5 4.2';
const DARKBG = String(0xFF0B1220 >>> 0);
const LIGHTBG = String(0xFFF7F9FB >>> 0);
const FOCUS = String(0xFF1B6FD8 >>> 0);
const HL = String(((((Math.round(0.16 * 255) << 24) | (27 << 16) | (111 << 8) | 216)) >>> 0));

// --- rest frame: light theme, pause icon, no caption, no tooltip ------------
{
  const d = draw();
  ok(d.includes(SUN) && !d.includes(MOON), 'rest: sun icon, light theme');
  ok(d.includes(PAUSE) && !d.includes(PLAY), 'rest: pause icon (auto-rotating)');
  ok(d.includes(LIGHTBG), 'rest: light background fill present');
  ok(!d.includes('Hydrogen bonds break'), 'rest: no caption');
  ok(!/pair \d+ of \d+/.test(d), 'rest: no tooltip');
  ok(d.includes('Top strand, read') && d.includes('Adenine (A)'), 'rest: below-fold panel drawn');
  ok(d.includes('Unzip & replicate'), 'rest: unzip label');
}

// --- theme toggle -----------------------------------------------------------
click(1239, 30);
{
  const d = draw();
  ok(d.includes(MOON) && !d.includes(SUN), 'theme: moon icon after toggle');
  ok(d.includes(DARKBG), 'theme: dark background fill present');
}
click(1239, 30);
{
  const d = draw();
  ok(d.includes(SUN) && !d.includes(MOON), 'theme: sun icon after toggle back');
  ok(d.includes(LIGHTBG), 'theme: light background restored');
}

// --- auto-rotate toggle + settle ---------------------------------------------
click(52, 766); // play button
{
  const d = draw();
  ok(d.includes(PLAY) && !d.includes(PAUSE), 'play: triangle icon when paused');
}
frames(80); // let spinV decay so later asserts are stable

// --- hover pick: scan the viz for a rung ------------------------------------
let hx = -1, hy = -1;
{
  let found = false;
  for (let gy = 100; gy <= 720 && !found; gy += 35) {
    for (let gx = 40; gx <= 820 && !found; gx += 35) {
      move(gx, gy);
      if (/pair \d+ of \d+/.test(draw())) { found = true; hx = gx; hy = gy; }
    }
  }
  ok(found, `pick: tooltip found at (${hx},${hy})`);
  const d = draw();
  ok(d.includes('hydrogen bonds') && d.includes(HL), 'pick: tooltip text + strip highlight');
}
move(430, 120); // title area: helix unlikely under the cursor
ok(!/pair \d+ of \d+/.test(draw()), 'pick: tooltip clears off the helix');

// --- annotation hover --------------------------------------------------------
move(898, 344); // ann row 2 pin
{
  const d = draw();
  ok(d.includes(FOCUS), 'ann: focus pin + leader when hovering row 2');
}
move(430, 120);
ok(!draw().includes(FOCUS), 'ann: focus clears off the row');

// --- drag rotate + inertia ---------------------------------------------------
{
  const d0 = norm();
  down(400, 400);
  for (let i = 1; i <= 10; i++) move(400 + i * 10, 400);
  const d1 = norm();
  ok(d1 !== d0, 'drag: helix rotates during drag');
  up(500, 400);
  frames(3);
  ok(norm() !== d1, 'drag: inertia carries spin after release');
  frames(80); // settle again
}

// --- keyboard view controls ---------------------------------------------------
{
  const d0 = norm();
  key(0x40000050); // Left
  ok(norm() !== d0, 'key: ArrowLeft rotates');
  const d1 = norm();
  key(0x40000052); // Up
  frames(10);
  ok(norm() !== d1, 'key: ArrowUp tilts');
  const d2 = norm();
  key(43); // '+'
  frames(10);
  ok(norm() !== d2, 'key: + zooms in');
  key(32); // space: resume auto-rotate
  ok(draw().includes(PAUSE), 'key: space resumes auto-rotate');
  key(32); // space: pause again
  ok(draw().includes(PLAY), 'key: space pauses again');
  frames(80);
}

// --- zoom buttons + reset -----------------------------------------------------
{
  click(178, 766); // reset zeroes spinV exactly; settle zoom/tilt chases to exact rest
  frames(60);
  const d0 = norm();
  click(136, 766); // zoom in
  frames(60);
  const d1 = norm();
  ok(d1 !== d0, 'zoom: zoom-in button changes the view');
  click(94, 766); // zoom out
  frames(60);
  click(178, 766); // reset
  frames(60);
  ok(norm() === d0, 'reset: view returns exactly to the settled frame');
}

// --- panel scroll ---------------------------------------------------------------
{
  const d0 = norm();
  down(1000, 700);
  move(1000, 100);
  up(1000, 100);
  ok(norm() !== d0, 'scroll: panel drag scrolls the content');
  ok(draw().includes('t 0.00 -600.00;'), 'scroll: translate carries -600');
}

// --- sequence input --------------------------------------------------------------
click(1000, 350); // seqIn (page 929..971 shifted by -600)
key(97); // 'a' -> appends A, length 25
{
  const d = draw();
  ok(d.includes('25 bp'), 'seq: typing A grows the helix to 25 bp');
}
key(120); // 'x' -> invalid
{
  const d = draw();
  ok(d.includes('Only A, T, G'), 'seq: invalid letter warns');
}
key(8); key(8); // backspace x2 -> back to 23
{
  const d = draw();
  ok(d.includes('23 bp'), 'seq: backspace shrinks the helix');
}
ok(draw().includes('Type A, T, G or C (2 to 40'), 'seq: message resets after valid edit');
key(13); // Enter blurs
click(1200, 350); // Random button
frames(20);
{
  const d = draw();
  ok(/Length [\s\S]{0,80} bp/.test(d), 'seq: random rebuilds the strip');
  ok(d.includes('Type A, T, G or C (2 to 40'), 'seq: random resets the message');
}

// --- unzip sweep: click down the panel until the caption fires ------------------
let unzied = false;
for (let y = 380; y <= 770 && !unzied; y += 30) {
  click(1070, y);
  frames(2);
  if (draw().includes('Hydrogen bonds break')) unzied = true;
}
ok(unzied, 'unzip: caption appears after clicking Unzip & replicate');
frames(25); // mt > 1.1 -> synth
ok(draw().includes('Free nucleotides pair'), 'unzip: synth caption follows');
ok(!/pair \d+ of \d+/.test(draw()), 'unzip: hover pick disabled while replicating');
frames(100); // mt > 4.62 -> done
{
  const d = draw();
  ok(d.includes('semi-conservative replication'), 'unzip: done caption');
  ok(d.includes('Rejoin strands'), 'unzip: label becomes Rejoin strands');
}
// rejoin sweep
let rejoined = false;
for (let y = 380; y <= 770 && !rejoined; y += 30) {
  click(1070, y);
  frames(2);
  if (draw().includes('Returning to the original')) rejoined = true;
}
ok(rejoined, 'rejoin: caption appears after clicking Rejoin strands');
frames(65); // mt > 2.9 -> duplex
{
  const d = draw();
  ok(!d.includes('Returning to the original'), 'rejoin: caption clears at the end');
  ok(d.includes('Unzip & replicate'), 'rejoin: label restored');
}

// --- scroll home ------------------------------------------------------------------
down(1000, 100);
move(1000, 700);
up(1000, 700);
move(430, 120);
ok(!draw().includes('t 0 -'), 'scroll: back at the top');

console.log(`\n${passed} assertions passed.`);
