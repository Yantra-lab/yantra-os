// web/runner/tests/typewriter.mjs
// Headless interaction suite for the Marlowe 44 typewriter port.
// Run: node web/runner/tests/typewriter.mjs   (requires apps/typewriter/app.wasm built)
// Drives the real wasm through YantraWebRunner with scripted key/pointer/frame
// input and asserts every interaction in apps/typewriter/TASK.md: typing,
// shift/lock, space/tab/backspace/enter, margin bell+lock, ribbon, sound
// toggle, animated new sheet, virtual keys incl. BS/TAB/SHIFT/LOCK, hover,
// lever, prop click/drag, tick animation, and PNG save byte-validity.
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
import { inflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { YantraWebRunner } from '../runner.js';
import { K, P, E } from '../protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../../..');
const DT = 0.1; // 100 ms logic frames: same coverage as the dev probe, ~4x faster
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
let savedBytes = null, savedName = '', saveHandler = -1;
runner.env.y_layer_read = (id, x, y, w, h, p) => {
  const n = w * h * 4;
  const mem = new Uint8Array(runner.memory.buffer);
  for (let i = 0; i < n; i++) mem[p + i] = (i * 7 + x + y) & 0xff;
  return n;
};
runner.env.y_pick_save = (dp, dl, np, nl, fp, fl, h) => {
  savedBytes = Buffer.from(runner.memory.buffer.slice(dp, dp + dl));
  savedName = Buffer.from(runner.memory.buffer.slice(np, np + nl)).toString();
  saveHandler = h;
  return 7;
};
runner.env.y_pick_status = () => 200;
runner.initSync(readFileSync(join(ROOT, 'apps/typewriter/app.wasm')));

const live = () => runner.getNodes().filter((n) => n.alive);
const canvas = live().find((n) => n.kind === K.CANVAS);
const draw = () => canvas.props[P.DRAW];
const btn = (t) => live().find((n) => n.kind === K.BUTTON && n.el.textContent === t);
const tagVal = (t) => live().find((n) => n.kind === K.TEXT && n.el.textContent === t);
const keyNodeId = Number([...runner.handlers.keys()].find((k) => k.endsWith(':' + E.KEY)).split(':')[0]);
const store = () => runner._storeMap.get('yantra:app:marlowe44.letter.v1');
const tail = () => store().split('|')[1].split(',').map(Number);
const nStrokes = () => (store().split('|')[0].match(/;/g) || []).length;
const key = (code, mods = 0) => { scripted.code = code; scripted.mods = mods; runner._fire(keyNodeId, E.KEY); };
const tap = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERDOWN); };
const move = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERMOVE); };
const release = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERUP); };
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(canvas.id, E.FRAME); };

let pass = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); pass++; };
// Persist is debounced (350ms trailing write, HTML rhythm): keystrokes update
// live state immediately but the store lags one debounce window. Settle before
// any assert that reads store()/tail()/nStrokes().
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const settle = () => sleep(600);

assert.ok(canvas, 'scene canvas exists');
ok(draw().length > 1000, 'scene painted');
for (const t of ['Black', 'Red', 'Sound', 'New sheet', 'Save letter']) assert.ok(btn(t), `button "${t}"`);
pass++;
ok(!!tagVal('No. 1') && !!tagVal('6 / 26') && !!tagVal('27 / 48'), 'fresh-letter tag');
const n0 = nStrokes();

const colorOf = (t) => live().find((n) => n.kind === K.BUTTON && n.el.textContent === t).props[P.COLOR];
btn('Red').el.click();
ok(colorOf('Red') === 0xFFFAF0 && colorOf('Black') === 0x16110F, 'Red ribbon pressed');
btn('Black').el.click();
ok(colorOf('Black') === 0xFFFAF0 && colorOf('Red') === 0x16110F, 'Black ribbon pressed');

let d = draw();
key(97);
await settle();
ok(nStrokes() === n0 + 1 && tail()[1] === 27, `'a' stamped, col 26->27`);
ok(draw() !== d, 'pDraw changed after keystroke');
ok(!!tagVal('28 / 48'), 'tag Column live-updates');
key(97, 1);
await settle();
ok(store().includes(';A,27,5,0;') && tail()[1] === 28, 'shift+A capital');
key(32);
await settle();
ok(tail()[1] === 29 && nStrokes() === n0 + 2, 'space advances, no stamp');
key(9);
await settle();
ok(tail()[1] === 30, 'tab stop');
key(8);
await settle();
ok(tail()[1] === 29 && nStrokes() === n0 + 2, 'backspace, no erase');
for (let i = 0; i < 25; i++) key(120);
await settle();
ok(tail()[1] === 48 && tail()[4] === 1, 'margin lock + bell');
ok(!!tagVal('49 / 48'), 'locked column tag');
d = draw();
key(13);
ok(tail()[1] === 0 && tail()[2] === 6 && tail()[4] === 0, 'return homes carriage');
ok(!!tagVal('7 / 26') && !!tagVal('1 / 48'), 'tag follows return');
frames(1);
ok(draw() !== d, 'carriage glides across frames');

btn('Sound').el.click();
ok(!!btn('Muted'), 'Sound->Muted');
btn('Muted').el.click();
ok(!!btn('Sound'), 'Muted->Sound');
btn('Red').el.click(); key(122); await settle(); btn('Black').el.click();
ok(store().includes(';z,0,6,1;'), 'red ink stamps');

tap(640, 762);
await settle();
ok(tail()[1] === 2 && nStrokes() === n0 + 2 + 25 + 1, 'virtual spacebar');
tap(433, 708);
await settle();
ok(store().includes(';a,2,6,0;') && tail()[1] === 3, `virtual 'a'`);
frames(2);
tap(443, 456);
ok(tail()[1] === 0 && tail()[2] === 7, 'lever returns carriage');

tap(395, 675);
await settle();
ok(tail()[1] === 5, 'virtual TAB');
tap(909, 642);
await settle();
ok(tail()[1] === 4 && nStrokes() === n0 + 2 + 25 + 1 + 1, 'virtual BS');
tap(338, 740);
tap(433, 708);
await settle();
ok(store().includes(';A,4,7,0;') && tail()[1] === 5, 'shift+tap capital, clears');
tap(433, 708);
await settle();
ok(store().includes(';a,5,7,0;') && tail()[1] === 6, 'lowercase again');
tap(380, 708);
tap(613, 740);
await settle();
ok(store().includes(';B,6,7,0;') && tail()[1] === 7, 'lock+tap capital');
tap(380, 708);
tap(613, 740);
await settle();
ok(store().includes(';b,7,7,0;') && tail()[1] === 8, 'tap after unlock lowercase');
tap(338, 740);
tap(624, 642);
await settle();
ok(store().includes(';_,8,7,0;') && tail()[1] === 9, 'shift+6 stamps underscore');

d = draw(); move(433, 708);
ok(draw() !== d, 'hover repaints cap');
d = draw(); move(10, 10);
ok(draw() !== d, 'leaving key repaints');

d = draw();
tap(125, 602); release(125, 602);
ok(draw() !== d, 'pencil click toasts');
d = draw();
tap(155, 435); move(185, 455); release(185, 455);
ok(draw() !== d, 'card drag moves prop');

d = draw(); frames(3);
ok(draw() !== d, 'ambient animation advances');
frames(30);
ok(draw() !== d, 'long-run frames settle without crashing');

d = draw();
btn('New sheet').el.click();
btn('New sheet').el.click();
ok(tail()[0] === 1, 'busy guard holds sheet 1 during pull');
frames(2);
ok(draw() !== d, 'pull-out animates');
frames(8);
ok(tail()[0] === 2 && tail()[1] === 0 && tail()[2] === 0 && nStrokes() === 0, 'swap homes machine');
ok(!!tagVal('No. 2'), 'tag Sheet follows');
frames(8);
btn('New sheet').el.click(); frames(18);
ok(tail()[0] === 3, 'busy clears');

btn('Save letter').el.click();
ok(savedBytes !== null && saveHandler >= 0, 'save invoked with bytes');
runner.dispatch(saveHandler);
frames(2);
ok([...savedBytes.subarray(0, 8)].join(',') === '137,80,78,71,13,10,26,10', 'PNG signature');
ok(savedBytes.readUInt32BE(16) === 1200 && savedBytes.readUInt32BE(20) === 1552, 'PNG is 1200x1552');
ok(savedName === 'marlowe44-letter-sheet3.png', 'filename carries sheet no');
let off = 8; const idat = [];
while (off < savedBytes.length) {
  const len = savedBytes.readUInt32BE(off);
  const typ = savedBytes.subarray(off + 4, off + 8).toString();
  if (typ === 'IDAT') idat.push(savedBytes.subarray(off + 8, off + 8 + len));
  if (typ === 'IEND') break;
  off += 12 + len;
}
const raw = inflateSync(Buffer.concat(idat));
ok(raw.length === 1552 * (1200 * 4 + 1), 'IDAT inflates to full RGBA');
ok(raw[0] === 0 && raw[1] === 0 && raw[2] === 7 && raw[3] === 14 && raw[4] === 21, 'pixels round-trip');

console.log(`typewriter: ${pass} assertions passed`);
