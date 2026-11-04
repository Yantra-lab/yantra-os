// web/runner/tests/gallery.mjs
// Headless interaction suite for the Galerie Nocturne port.
// Run: node web/runner/tests/gallery.mjs   (requires apps/gallery/app.wasm built)
// Drives the real wasm through YantraWebRunner with scripted key/pointer/frame
// input and asserts the contract of 039-virtual-gallery.html: WASD/arrows walk,
// strafe, drag-look, click-to-approach, click-to-walk, detail card + nav,
// step prev/next, Escape/backspace step-back, digit shortcuts, Home, Space,
// pad tap + hold, VIEW pill, index buttons, minimap marks, and the live
// minimap (camera dot, cone rotation, position readout).
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { YantraWebRunner } from '../runner.js';
import { K, P, E } from '../protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../../..');
const DT = 0.1; // 100 ms logic frames (clamped to 50 ms inside tick)
const scripted = { code: 0, mods: 0, px: 0, py: 0 };
const held = new Set();
const runner = new YantraWebRunner({});
runner.env.y_key = (w) => (w === 0 ? scripted.code : w === 1 ? scripted.mods : 0);
runner.env.y_node_size = (n, ax) => {
  if (n === 0 && (ax === 7 || ax === 13)) return scripted.px;
  if (n === 0 && (ax === 8 || ax === 14)) return scripted.py;
  return 0;
};
const origInput = runner.env.y_input;
runner.env.y_input = (what, arg) => {
  if (what === 7) return DT;
  if (what === 0 && held.has(arg)) return 1;
  return origInput(what, arg);
};
let layerSeq = 0;
runner.env.y_layer_new = () => ++layerSeq;
// capture the 640x400 corridor raster: the room renders into layer pixels,
// which the draw string only references by handle
const layerPx = {};
runner.env.y_layer_write = (id, x, y, w, h, p) => {
  if (w === 640 && h === 400) layerPx.corridor = Buffer.from(runner.memory.buffer.slice(p, p + w * h * 4));
};
runner.initSync(readFileSync(join(ROOT, 'apps/gallery/app.wasm')));
const corrHash = () => {
  const b = layerPx.corridor;
  if (!b) return '';
  let h1 = 0x811c9dc5;
  for (let i = 0; i < b.length; i += 97) { h1 ^= b[i]; h1 = Math.imul(h1, 0x01000193); }
  return (h1 >>> 0).toString(16);
};

const live = () => runner.getNodes().filter((n) => n.alive);
const scene = live().find((n) => n.kind === K.CANVAS);
const draw = () => scene.props[P.DRAW];
const keyNodeId = Number([...runner.handlers.keys()].find((k) => k.endsWith(':' + E.KEY)).split(':')[0]);
const key = (code, mods = 0) => { scripted.code = code; scripted.mods = mods; runner._fire(keyNodeId, E.KEY); };
const down = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(scene.id, E.POINTERDOWN); };
const move = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(scene.id, E.POINTERMOVE); };
const up = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(scene.id, E.POINTERUP); };
const click = (x, y) => { down(x, y); up(x, y); };
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(scene.id, E.FRAME); };
const hold = (code) => held.add(code);
const release = (code) => held.delete(code);

let passed = 0;
const ok = (c, m) => { assert(c, m); passed++; console.log('ok - ' + m); };

const GOLDHI = (0xFFF1DC9A) >>> 0;
// camera dot: the only E verb with the gold-hi color and the 3.91 radius
const camDot = () => {
  const m = draw().match(new RegExp(`E ([\\d.]+) ([\\d.]+) 3\\.91 3\\.91 ${GOLDHI}`));
  return m ? { x: +m[1], y: +m[2] } : null;
};
// cone rotation: the frame draw's only 'o ' verb (the mosaic one is baked)
const coneRot = () => {
  const ms = [...draw().matchAll(/o (-?[\d.]+);/g)];
  return ms.length === 1 ? +ms[0][1] : null;
};
// project a world point to CSS px at rot=0/ly=0 (mirrors project())
const project0 = (wx, wy, wz, ox = 0, oy = 0, oz = 160) => {
  const dx = wx - ox, dy = wy - oy, dz = wz - oz;
  return [641 - 768 * (dx / dz), 401 - 768 * (dy / dz)];
};

const KEY = { up: 0x40000052, down: 0x40000051, left: 0x40000050, right: 0x4000004f, home: 0x4000004a, enter: 13, esc: 27, space: 32, bs: 8 };

// --- boot: 24 bake steps + veil clear -----------------------------------------
frames(30);
{
  const d = draw();
  ok(d.includes('Y '), 'boot: corridor layer blitted');
  ok(d.includes('FLOOR PLAN') && d.includes('VIEW') && d.includes('APPROACH'), 'boot: HUD drawn');
  ok(d.includes('Entrance'), 'boot: position readout starts at Entrance');
  ok(d.includes('Evening at Port Salin'), 'boot: nearest work is No. I');
  const dot = camDot();
  ok(dot && Math.abs(dot.x - 77.93) < 1 && Math.abs(dot.y - 694.6) < 1, `boot: camera dot at start (${dot && dot.x},${dot && dot.y})`);
}

// --- hold W: walk forward --------------------------------------------------------
{
  const d0 = camDot();
  hold(119); frames(12); release(119);
  frames(25);
  const d1 = camDot();
  ok(d1.x > d0.x + 5, `walk: W moves the camera forward (${d0.x} -> ${d1.x})`);
  ok(!draw().includes('Entrance') && draw().includes('1.8 m'), 'walk: readout becomes 1.8 m');
}

// --- hold D: strafe right ----------------------------------------------------------
{
  const d0 = camDot();
  hold(100); frames(10); release(100);
  frames(25);
  const d1 = camDot();
  ok(d1.y > d0.y + 3, `strafe: D strafes right (${d0.y} -> ${d1.y})`);
}

// --- hold ArrowRight: turn past 25 degrees locks to the right wall ------------------
hold(KEY.right); frames(15); release(KEY.right);
frames(25);
ok(draw().includes('Composition for a Quiet Street'), 'turn: facing right offers No. II');

// --- Home: back to the entrance -------------------------------------------------------
key(KEY.home);
frames(50);
{
  const dot = camDot();
  ok(dot && Math.abs(dot.x - 77.93) < 2 && Math.abs(dot.y - 694.6) < 2, 'home: camera returns to start');
  ok(draw().includes('Entrance'), 'home: readout back to Entrance');
  ok(draw().includes('Evening at Port Salin'), 'home: nearest back to No. I');
}

// --- drag-look: immediate parallax + eased yaw -------------------------------------------
move(640, 400); frames(40); // settle the look dead centre
{
  const h0 = corrHash();
  ok(h0 !== '', 'drag: corridor raster captured');
  down(640, 400); move(440, 400);
  ok(corrHash() !== h0, 'drag: mouse move re-renders parallax immediately');
  up(440, 400);
  frames(40);
  ok(draw().includes('Composition for a Quiet Street'), 'drag: yaw right offers No. II');
  const r = coneRot();
  ok(r !== null && Math.abs(r - 36) < 2, `drag: cone shows +36 deg (got ${r})`);
  ok(corrHash() !== h0, 'drag: yaw changes the rendered room');
}
key(KEY.home); frames(50);

// --- click a painting: project work 0, sweep 3x3 ------------------------------------------
move(640, 400); frames(40);
{
  const [px, py] = project0(-298.5, -22, -330);
  let hit = false;
  for (let gy = -1; gy <= 1 && !hit; gy++) {
    for (let gx = -1; gx <= 1 && !hit; gx++) {
      click(px + gx * 25, py + gy * 25);
      if (draw().includes('No. I / VIII')) hit = true;
    }
  }
  ok(hit, `click: painting I approached at ~(${px.toFixed(0)},${py.toFixed(0)})`);
}
frames(60); // glide + card slide
{
  const d = draw();
  ok(d.includes('Evening at Port Salin') && d.includes('STEP BACK'), 'detail: card shows title + nav');
  ok(!d.includes('FLOOR PLAN') && !d.includes('VIEW'), 'detail: plan + pad hidden');
}

// --- detail keys ----------------------------------------------------------------------------
key(KEY.right);
ok(draw().includes('No. II / VIII'), 'detail: Right steps to No. II');
key(KEY.left);
ok(draw().includes('No. I / VIII'), 'detail: Left steps back to No. I');
key(KEY.esc);
frames(30);
{
  const d = draw();
  ok(!d.includes('/ VIII'), 'esc: card gone after step-back');
  ok(d.includes('FLOOR PLAN'), 'esc: plan back in corridor');
}

// --- digits + Escape ----------------------------------------------------------------------------
key(51); // '3'
ok(draw().includes('No. III / VIII'), 'digit: 3 approaches No. III');
key(KEY.esc); frames(30);
ok(!draw().includes('/ VIII'), 'esc: back to corridor');

// --- index button VIII (the fixed 5-7 range) -------------------------------------------------------
click(279.15, 749.8);
ok(draw().includes('No. VIII / VIII') && draw().includes('Tessellated Sun'), 'idx: button VIII approaches No. VIII');
key(KEY.esc); frames(30);

// --- minimap mark -------------------------------------------------------------------------------
click(128, 667);
ok(draw().includes('No. I / VIII'), 'mark: plan mark approaches No. I');
key(KEY.esc); frames(30);

// --- card nav buttons ------------------------------------------------------------------------------
key(50); // '2'
frames(60);
click(1174.8, 596); // NEXT
ok(draw().includes('No. III / VIII'), 'card: NEXT steps forward');
frames(60);
click(934.8, 596); // PREV
ok(draw().includes('No. II / VIII'), 'card: PREV steps back');
frames(60);
click(1054.8, 596); // STEP BACK
frames(30);
ok(!draw().includes('/ VIII') && draw().includes('FLOOR PLAN'), 'card: STEP BACK returns');

// --- space / backspace -------------------------------------------------------------------------------
key(KEY.space); // cam sits 260 short of work II after the card step-back
ok(draw().includes('No. II / VIII'), 'space: approaches nearest in corridor');
key(KEY.bs); frames(30);
ok(!draw().includes('/ VIII'), 'backspace: steps back from detail');

// --- pad tap: forward step ------------------------------------------------------------------------------
click(546, 742.8);
frames(60);
ok(draw().includes('2.7 m'), 'pad: tap fwd steps 240 units (2.7 m)');

// --- pad hold: back moves while held, no tap-step on release ----------------------------------------------
{
  const d0 = camDot();
  down(600, 742.8); frames(8); up(600, 742.8);
  frames(25);
  const d1 = camDot();
  ok(d1.x < d0.x - 3, `pad: hold back walks back (${d0.x} -> ${d1.x})`);
  ok(draw().includes('2.1 m'), 'pad: hold moves without a tap-step on release');
}

// --- pad VIEW pill ------------------------------------------------------------------------------------------
click(767, 742.8);
ok(draw().includes('No. II / VIII'), 'pad: VIEW approaches nearest');
key(KEY.esc); frames(30);

// --- pad tap left: -45 deg -------------------------------------------------------------------------------
click(492, 742.8);
frames(40);
{
  const r = coneRot();
  ok(r !== null && Math.abs(r - -45) < 2, `pad: tap left turns to -45 (got ${r})`);
}
key(KEY.home); frames(50);

// --- floor click: walks ------------------------------------------------------------------------------
{
  click(640, 790);
  frames(40);
  const d = draw();
  ok(!d.includes('Entrance') || d.includes('/ VIII'), 'click: stage click walks or approaches');
}

console.log(`\n${passed} assertions passed.`);
