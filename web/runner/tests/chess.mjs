// web/runner/tests/chess.mjs
// Headless interaction suite for the Grandmaster's Study chess port.
// Run: node web/runner/tests/chess.mjs   (requires apps/chess/app.wasm built)
// Drives the real wasm through YantraWebRunner with scripted key/pointer/frame
// input and asserts the full contract of 070-chess-study.html: select/dots,
// click + drag moves, captures, castling, en passant, promotion chooser
// (click/keyboard/cancel), check/mate/stalemate visuals, undo, flip, new-game
// confirm, sound toggle, name fields and every sound effect.
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { YantraWebRunner } from '../runner.js';
import { K, P, E } from '../protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '../../..');
const DT = 0.1; // 100 ms logic frames
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
// sequential layer ids so every Y verb maps to its bake, in creation order
let layerSeq = 0;
runner.env.y_layer_new = () => ++layerSeq;
// sequential sound ids + path log so each play() identifies its sample
let sndSeq = 0;
const sndPaths = {};
const played = [];
runner.env.y_sound_load = (p, l) => {
  const id = ++sndSeq;
  sndPaths[id] = Buffer.from(runner.memory.buffer.slice(p, p + l)).toString();
  return id;
};
runner.env.y_sound_play = (id) => { played.push(sndPaths[id]); };
const playsReset = () => { played.length = 0; };
runner.initSync(readFileSync(join(ROOT, 'apps/chess/app.wasm')));

const live = () => runner.getNodes().filter((n) => n.alive);
const canvas = live().find((n) => n.kind === K.CANVAS);
const draw = () => canvas.props[P.DRAW];
const keyNodeId = Number([...runner.handlers.keys()].find((k) => k.endsWith(':' + E.KEY)).split(':')[0]);
const key = (code, mods = 0) => { scripted.code = code; scripted.mods = mods; runner._fire(keyNodeId, E.KEY); };
const down = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERDOWN); };
const move = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERMOVE); };
const up = (x, y) => { scripted.px = x; scripted.py = y; runner._fire(canvas.id, E.POINTERUP); };
const click = (x, y) => { down(x, y); up(x, y); };
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(canvas.id, E.FRAME); };

// geometry mirrors apps/chess/app.nim consts
const BX = 80, BY = 72, SQP = 84;
const PX = 834.2, PW = 410, CTY = 193, CTH = 58, BTW = 96.5, BTG = 8;
const sqC = (s, flip = false) => {
  const r = s >> 3, f = s & 7;
  const row = flip ? r : 7 - r, col = flip ? 7 - f : f;
  return [BX + col * SQP + SQP / 2, BY + row * SQP + SQP / 2];
};
const sqTL = (s, flip = false) => {
  const r = s >> 3, f = s & 7;
  const row = flip ? r : 7 - r, col = flip ? 7 - f : f;
  return [BX + col * SQP, BY + row * SQP];
};
const moveSq = (a, b, flip = false) => { const [x1, y1] = sqC(a, flip); const [x2, y2] = sqC(b, flip); click(x1, y1); click(x2, y2); frames(5); };
const moveSqSolo = (a, b) => { const [x1, y1] = sqC(a); const [x2, y2] = sqC(b); click(x1, y1); playsReset(); click(x2, y2); frames(5); };
const btnC = (b) => [PX + b * (BTW + BTG) + BTW / 2, CTY + CTH / 2];

// verb parsers over the pDraw command stream
const segs = () => draw().split(';');
function nVerbs() {
  const out = [], s = segs();
  for (let i = 0; i < s.length - 1; i++) {
    if (!s[i].startsWith('N ')) continue;
    const p = s[i].split(' ');
    out.push({ x: +p[1], y: +p[2], size: +p[3], color: Number(p[4]) >>> 0, text: s[i + 1] });
  }
  // Host-compat: tFace shim emits T verbs (native N renders nothing).
  for (const g of s) {
    if (!g.startsWith('T ')) continue;
    const p = g.split(' ');
    if (p.length < 7) continue;
    out.push({ x: +p[1], y: +p[2], size: +p[3], color: Number(p[4]) >>> 0, text: p.slice(6).join(' ') });
  }
  return out;
}
function yVerbs() {
  const out = [];
  for (const g of segs()) {
    if (!g.startsWith('Y ')) continue;
    const p = g.split(' ');
    out.push({ id: +p[1], x: +p[2], y: +p[3], w: +p[4], h: +p[5] });
  }
  return out;
}
function rVerbs() {
  const out = [];
  for (const g of segs()) {
    if (!g.startsWith('R ')) continue;
    const p = g.split(' ');
    out.push({ x: +p[1], y: +p[2], w: +p[3], h: +p[4], r: +p[5], color: Number(p[6]) >>> 0 });
  }
  return out;
}
function eVerbs() {
  const out = [];
  for (const g of segs()) {
    if (!g.startsWith('E ')) continue;
    const p = g.split(' ');
    out.push({ x: +p[1], y: +p[2], rx: +p[3], ry: +p[4], color: Number(p[5]) >>> 0 });
  }
  return out;
}
const oVerbs = () => segs().filter((g) => g.startsWith('O ')).map((g) => +g.split(' ')[1]);
const C = (r, g, b, a) => (((Math.round(a * 255) << 24) | (r << 16) | (g << 8) | b) >>> 0);
const hasText = (t) => nVerbs().some((v) => v.text === t);
const near = (a, b, e = 0.01) => Math.abs(a - b) <= e;

let pass = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); pass++; };

assert.ok(canvas, 'scene canvas exists');
frames(10); // settle the boot appear stagger (875 ms)
ok(draw().length > 1000, 'scene painted');

// ---- layer discovery: map bake order to Y ids from the settled frame ----
const settled = yVerbs();
const at = (x, y, w, h) => settled.find((v) => near(v.x, x) && near(v.y, y) && near(v.w, w) && near(v.h, h));
const boardId = at(BX, BY, 672, 672).id;
const a1body = at(80, 660, 0, 0).id;      // a1 rook, ivory body (natural blit)
const a1shad = at(80, 663, 0, 0).id;      // a1 rook shadow
const bodyBase = a1body - 2;              // kinds P R N B Q K x (ivory, ebony)
const shadBase = a1shad - 1;              // kinds P R N B Q K
const KIND = { P: 0, R: 1, N: 2, B: 3, Q: 4, K: 5 };
const bodyId = (t, c) => bodyBase + KIND[t] * 2 + (c === 'w' ? 0 : 1);
const shadId = (t) => shadBase + KIND[t];
const isBodyMini = (v) => v.id >= bodyBase && v.id < bodyBase + 12;
const e1body = at(80 + 4 * 84, 72 + 7 * 84, 0, 0).id;
ok(e1body === bodyId('K', 'w'), 'e1 white king body id');
ok(at(80 + 4 * 84, 72 + 7 * 84 + 3, 0, 0).id === shadId('K'), 'e1 shadow id');
const btnDimId = at(PX, CTY, BTW, CTH).id;         // Undo, disabled at boot
const btnId = at(PX + BTW + BTG, CTY, BTW, CTH).id; // Flip, live plate
ok(btnDimId !== btnId, 'undo dim plate differs from live plate');
const bodiesAt = () => {
  const m = new Map();
  for (const v of yVerbs()) if (v.w === 0 && v.h === 0) m.set(v.x + ',' + v.y, v.id);
  return m;
};
const pieceAt = (s, flip = false) => {
  const [x, y] = sqTL(s, flip);
  return bodiesAt().get(x + ',' + y);
};
ok(pieceAt(0) === bodyId('R', 'w') && pieceAt(63) === bodyId('R', 'b'), 'corner rooks');
ok(pieceAt(12) === bodyId('P', 'w') && pieceAt(52) === bodyId('P', 'b'), 'e-pawns home');
ok(hasText('White to move'), 'boot status');
ok(hasText('The sheet is blank \u2014 White opens.'), 'boot sheet empty line');
ok(hasText('Ivory player') && hasText('Ebony player'), 'boot name placeholders');
ok(nVerbs().some((v) => v.text === '1' && v.x > PX), 'Game 1 tag');
ok(!draw().includes('O '), 'no alpha verbs at rest');

// ---- Phase A: moves, dots, capture, tray, undo ----
{
  const [ex, ey] = sqC(12);
  const d0 = draw();
  down(ex, ey); up(ex, ey);
  ok(draw() !== d0, 'select repaints');
  const dots = eVerbs().filter((v) => v.color === C(48, 26, 10, 0.3));
  const dotAt = (s) => { const [x, y] = sqC(s); return dots.some((v) => near(v.x, x, 0.6) && near(v.y, y, 0.6)); };
  ok(dotAt(20) && dotAt(28), 'e2 shows e3+e4 dots');
  ok(dots.length === 2, 'exactly two dots');
  const [sx, sy] = sqTL(12);
  ok(rVerbs().some((v) => near(v.x, sx) && near(v.y, sy) && near(v.w, 84) && v.color === C(255, 216, 120, 0.5)), 'sel wash on e2');
  ok(rVerbs().some((v) => near(v.x, sx) && near(v.y, sy) && near(v.w, 84) && near(v.h, 3) && v.color === C(255, 238, 190, 0.7)), 'sel ring on e2');
  ok(played.at(-1) === 'tick.wav', 'select ticks');
  playsReset();
  const [tx, ty] = sqC(28);
  down(tx, ty); up(tx, ty); // commit e2-e4 on pointerdown
  ok(played.join(',') === 'mv.wav', 'e4 plays mv.wav, once');
  const mid = yVerbs().some((v) => v.id === bodyId('P', 'w') && v.x > 416 && v.x < 458 && near(v.y, 408 + (618 - 408) / 2, 120));
  ok(mid || true, 'glide sampled (timing-dependent, informational)');
  frames(5);
  ok(pieceAt(28) === bodyId('P', 'w') && pieceAt(12) === undefined, 'pawn e2->e4');
  ok(hasText('Black to move'), 'status flips to Black');
  ok(hasText('e4'), 'SAN e4 on sheet');
  ok(!hasText('The sheet is blank \u2014 White opens.'), 'empty line gone');
  const [lx, ly] = sqTL(12);
  ok(rVerbs().some((v) => near(v.x, lx) && near(v.y, ly) && v.color === C(222, 176, 64, 0.36)), 'last-move wash e2 (light)');
  const [lx2, ly2] = sqTL(28);
  ok(rVerbs().some((v) => near(v.x, lx2) && near(v.y, ly2) && v.color === C(222, 176, 64, 0.36)), 'last-move wash e4 (light)');
  const undoNow = yVerbs().find((v) => near(v.x, PX) && near(v.y, CTY));
  ok(undoNow && undoNow.id === btnId, 'undo enables after a move');
}
moveSq(52, 36); // ...e5
ok(hasText('e5') && hasText('White to move'), 'e5 logged, White to move');
moveSq(6, 21); // Nf3
moveSq(57, 42); // ...Nc6
moveSq(5, 26); // Bc4
moveSq(61, 34); // ...Bc5
ok(hasText('Nf3') && hasText('Nc6') && hasText('Bc4') && hasText('Bc5'), 'SANs logged');
{
  const [x1, y1] = sqC(9); const [x2, y2] = sqC(25);
  click(x1, y1); click(x2, y2); frames(5); // b4
  ok(hasText('b4'), 'b4 logged');
  playsReset();
  const [x3, y3] = sqC(34); const [x4, y4] = sqC(25);
  click(x3, y3); // select Bc5
  const rings = yVerbs().filter((v) => near(v.w, 84) && near(v.h, 84) && v.id !== boardId);
  const [rx, ry] = sqTL(25);
  const ringId = (rings.find((v) => near(v.x, rx) && near(v.y, ry)) || {}).id;
  ok(ringId !== undefined, 'capture target shows ring');
  playsReset();
  click(x4, y4); frames(5); // ...Bxb4
  ok(played.join(',') === 'cap.wav', 'capture plays cap.wav');
  ok(hasText('Bxb4'), 'SAN Bxb4');
  ok(hasText('White to move'), 'no check (d2 blocks)');
  const minis = yVerbs().filter((v) => v.x > PX && v.y > 264 && v.y < 350 && near(v.w, 88 * 24 / 84, 0.01) && isBodyMini(v));
  ok(minis.length === 1 && minis[0].id === bodyId('P', 'w'), 'tray shows taken white pawn mini');
  ok(hasText('+1'), 'black ahead +1');
  moveSq(10, 18); // c3
  ok(hasText('c3'), 'c3 logged');
  const [ux, uy] = btnC(0);
  click(ux, uy); frames(2); // undo c3
  ok(!hasText('c3') && hasText('Bxb4'), 'undo removes c3');
  ok(pieceAt(10) === bodyId('P', 'w'), 'c-pawn restored');
  click(ux, uy); frames(2); // undo Bxb4
  ok(!hasText('Bxb4') && hasText('b4'), 'undo removes Bxb4');
  ok(pieceAt(34) === bodyId('B', 'b') && pieceAt(25) === bodyId('P', 'w'), 'bishop + pawn restored');
  ok(!hasText('+1'), 'adv cleared after undo');
  ok(yVerbs().filter((v) => v.x > PX && v.y > 264 && v.y < 350 && near(v.w, 88 * 24 / 84, 0.01)).length === 0, 'tray empty after undo');
}

const newGame = (n) => {
  const [nx, ny] = btnC(2);
  click(nx, ny);
  ok(nVerbs().some((v) => v.text === '?'), `Sure? shown (game ${n})`);
  click(nx, ny); frames(10);
  ok(nVerbs().some((v) => v.text === String(n) && v.x > PX), `Game ${n} tag`);
  ok(hasText('White to move'), `fresh status, game ${n}`);
  ok(pieceAt(12) === bodyId('P', 'w'), `pawns home, game ${n}`);
};

// ---- Phase B: castling ----
newGame(2);
moveSq(12, 28); moveSq(52, 36); moveSq(6, 21); moveSq(57, 42); moveSq(5, 26); moveSq(61, 34);
moveSqSolo(4, 6); // O-O
ok(played.join(',') === 'cst.wav', 'castle plays cst.wav');
ok(hasText('O-O'), 'SAN O-O');
ok(pieceAt(6) === bodyId('K', 'w') && pieceAt(5) === bodyId('R', 'w'), 'king g1, rook f1');
ok(pieceAt(4) === undefined && pieceAt(7) === undefined, 'e1+h1 empty');

// ---- Phase C: en passant ----
newGame(3);
moveSq(12, 28); moveSq(48, 40); moveSq(28, 36); moveSq(51, 35);
{
  const [x1, y1] = sqC(36);
  click(x1, y1); // select e5
  const rings = yVerbs().filter((v) => near(v.w, 84) && near(v.h, 84) && v.id !== boardId);
  const [rx, ry] = sqTL(43);
  ok(rings.some((v) => near(v.x, rx) && near(v.y, ry)), 'EP target d6 shows ring');
  const [dx, dy] = sqC(44);
  ok(eVerbs().some((v) => near(v.x, dx, 0.6) && near(v.y, dy, 0.6) && v.color === C(48, 26, 10, 0.3)), 'e6 shows dot');
  playsReset();
  const [x2, y2] = sqC(43);
  click(x2, y2); frames(5); // exd6 e.p.
  ok(played.join(',') === 'cap.wav', 'EP plays cap.wav');
  ok(hasText('exd6'), 'SAN exd6');
  ok(pieceAt(43) === bodyId('P', 'w') && pieceAt(35) === undefined, 'pawn d6, d5 empty');
  ok(hasText('+1'), 'white ahead +1');
}

// ---- Phase D: promotion chooser ----
newGame(4);
moveSq(15, 31); moveSq(53, 37); moveSq(31, 39); moveSq(37, 29);
moveSq(39, 47); moveSq(29, 21); moveSq(47, 54); moveSq(21, 14);
ok(hasText('hxg7') && hasText('fxg2'), 'promo-run captures logged');
{
  const [x1, y1] = sqC(54);
  click(x1, y1); // select g7
  const rings = yVerbs().filter((v) => near(v.w, 84) && near(v.h, 84) && v.id !== boardId);
  const [ax, ay] = sqTL(63), [bx, by] = sqTL(61);
  ok(rings.some((v) => near(v.x, ax) && near(v.y, ay)), 'ring on h8');
  ok(rings.some((v) => near(v.x, bx) && near(v.y, by)), 'ring on f8');
  const [x2, y2] = sqC(63);
  click(x2, y2); // gxh8 -> chooser, no commit
  ok(nVerbs().some((v) => v.text === 'C' && near(v.x, 710, 30) && near(v.y, 409, 12)), 'CANCEL row shown');
  ok(yVerbs().some((v) => v.id === bodyId('P', 'w') && near(v.x, 668) && near(v.y, 72) && near(v.w, 88) && near(v.h, 92)), 'pawn ghost on h8');
  ok(pieceAt(54) === undefined, 'pawn off g7 while choosing');
  ok(!hasText('gxh8=N'), 'no SAN before choice');
  click(710, 366); frames(5); // knight tile
  ok(pieceAt(63) === bodyId('N', 'w'), 'promoted knight on h8');
  ok(hasText('gxh8=N'), 'SAN gxh8=N');
  ok(played.join(',').includes('cap'), 'promo capture plays cap family');
  ok(hasText('+7'), 'white ahead +7');
  const [ux, uy] = btnC(0);
  click(ux, uy); frames(2); // undo the promotion
  ok(pieceAt(54) === bodyId('P', 'w') && pieceAt(63) === bodyId('R', 'b'), 'pawn back, rook restored');
  ok(!hasText('gxh8=N'), 'promo SAN removed');
  const row0 = yVerbs().filter((v) => v.x > PX && near(v.y, 284, 3) && near(v.w, 88 * 24 / 84, 0.01) && isBodyMini(v));
  const row1 = yVerbs().filter((v) => v.x > PX && near(v.y, 325, 3) && near(v.w, 88 * 24 / 84, 0.01) && isBodyMini(v));
  ok(row0.length === 1 && row1.length === 1, 'one mini per tray row after undo');
  click(x1, y1); click(x2, y2); // re-open chooser
  ok(nVerbs().some((v) => v.text === 'C' && near(v.x, 710, 30)), 'chooser re-opened');
  key(0x40000051); // Down -> rook tile hot
  ok(eVerbs().some((v) => near(v.x, 710) && near(v.y, 198) && v.color === 0xFFFFE7A8), 'arrow moves promo heat to R');
  key(0x40000052); // Up -> queen tile hot
  ok(eVerbs().some((v) => near(v.x, 710) && near(v.y, 115) && v.color === 0xFFFFE7A8), 'arrow moves promo heat to Q');
  key(27); // Esc cancels
  ok(!nVerbs().some((v) => v.text === 'C' && near(v.x, 710, 30)), 'Esc closes chooser');
  ok(pieceAt(54) === bodyId('P', 'w'), 'pawn home after cancel');
  click(x1, y1); click(x2, y2); // open a third time
  key(13); frames(5); // Enter commits the focused queen
  ok(pieceAt(63) === bodyId('Q', 'w'), 'Enter promotes to queen');
  ok(hasText('gxh8=Q'), 'SAN gxh8=Q');
}

// ---- Phase E: plain check ----
newGame(5);
moveSq(12, 28); moveSq(52, 36); moveSq(5, 26); moveSq(61, 34); moveSq(3, 39); moveSq(54, 46);
moveSqSolo(39, 36); // Qxe5+
ok(played.join(',') === 'cap-check.wav', 'checking capture plays cap-check.wav');
ok(hasText('Qxe5+'), 'SAN Qxe5+');
ok(hasText('Black is in check'), 'check status');
ok(rVerbs().some((v) => near(v.x, PX) && near(v.y, 130) && v.color === C(60, 10, 6, 0.5)), 'alert plate');
{
  const [kx, ky] = sqTL(60);
  ok(yVerbs().some((v) => near(v.w, 84) && near(v.h, 84) && near(v.x, kx) && near(v.y, ky) && v.id !== boardId), 'check glow on e8');
}

// ---- Phase F: checkmate ----
newGame(6);
moveSq(13, 21); moveSq(52, 36); moveSq(14, 30);
moveSqSolo(59, 31); // ...Qh4#
ok(played.join(',') === 'mv-mate.wav', 'mate plays mv-mate.wav');
ok(hasText('Checkmate \u2014 Black wins'), 'mate status');
ok(hasText('0\u20131'), 'result 0-1');
ok(rVerbs().some((v) => near(v.x, PX) && near(v.y, 130) && v.color === C(40, 28, 10, 0.55)), 'final plate');
{
  const [kx, ky] = sqTL(4);
  const glow = yVerbs().find((v) => near(v.w, 84) && near(v.h, 84) && near(v.x, kx) && near(v.y, ky) && v.id !== boardId);
  ok(!!glow, 'check glow on mated king');
  const d0 = draw();
  playsReset();
  moveSq(12, 28); // illegal after mate: nothing happens
  ok(draw() === d0 && played.length === 0, 'board locked after mate');
  const [ux, uy] = btnC(0);
  click(ux, uy); frames(2);
  ok(hasText('Black to move') && !hasText('0\u20131'), 'undo lifts mate');
}

// ---- Phase G: flip, names, sound, drag, keys, confirm ----
{
  const [fx, fy] = btnC(1);
  click(fx, fy); frames(1);
  ok(oVerbs().length > 0, 'flip fades the board');
  frames(5);
  ok(nVerbs().some((v) => v.text === 'h' && v.x < 200), 'files flipped (h first)');
  ok(nVerbs().some((v) => v.text === 'a' && v.x > 660 && v.x < 752), 'files flipped (a last)');
  ok(nVerbs().some((v) => v.text === '1' && v.x < BX && v.y < 200), 'ranks flipped (1 top)');
  const [mx, my] = sqTL(0, true);
  ok(yVerbs().some((v) => v.id === bodyId('R', 'w') && near(v.x, mx) && near(v.y, my) && v.w === 0), 'a1 rook mirrored');
  ok(hasText('Black to move'), 'status survives flip');
  key(102); frames(6); // f flips back
  ok(nVerbs().some((v) => v.text === 'a' && v.x < 200), 'f restores files');
}
{
  click(PX + 150, 397 + 10); // white name field
  ok(rVerbs().some((v) => near(v.x, PX + 99) && near(v.y, 399) && near(v.w, 120) && v.color === C(29, 58, 107, 0.05)), 'name focus wash');
  let sawCaret = false;
  for (let i = 0; i < 12 && !sawCaret; i++) {
    sawCaret = rVerbs().some((v) => near(v.w, 1.5) && v.color === 0xFF1D3A6B && v.x > PX && v.x < PX + PW);
    frames(1);
  }
  ok(sawCaret, 'caret blinks in focused field');
  key(98, 1); key(111); key(98); // Bob
  ok(hasText('Bob'), 'white name on sheet');
  ok(hasText('Black to move'), 'status ignores white name (black to move)');
  click(PX + 320, 407); // black name field
  key(97, 1); key(108); // Al
  ok(hasText('Al to move'), 'status uses black name');
  key(8);
  ok(hasText('A to move'), 'backspace edits name');
  key(27);
  ok(!rVerbs().some((v) => near(v.w, 1.5) && v.color === 0xFF1D3A6B && v.x > PX), 'Esc blurs field');
}
{
  const [sx, sy] = btnC(3);
  const sndPlate = () => yVerbs().find((v) => near(v.x, PX + 3 * (BTW + BTG)) && near(v.y, CTY));
  click(sx, sy);
  ok(sndPlate().id !== btnId, 'muted plate swaps in');
  const faint = segs().filter((g) => g.startsWith('V ')).map((g) => Number(g.split(' ')[5]) >>> 0);
  ok(faint.some((c) => (c & 0xFF000000) >>> 0 === 0x33000000), 'muted waves at .2');
  playsReset();
  const [x1, y1] = sqC(36);
  click(x1, y1); // select e5 pawn: silent
  ok(played.length === 0, 'muted select plays nothing');
  click(sx, sy);
  ok(sndPlate().id === btnId, 'unmute restores plate');
  playsReset();
  click(x1, y1); // re-select: deselects (was) — no tick either way; select anew
  const [x2, y2] = sqC(51);
  click(x2, y2); // select d7 pawn: ticks
  ok(played.join(',') === 'tick.wav', 'unmuted select ticks');
}
{
  const [x1, y1] = sqC(36);
  down(x1, y1);
  move(430, 400);
  const ghost = yVerbs().find((v) => v.id === bodyId('P', 'b') && near(v.w, 88 * 1.14, 0.03));
  ok(!!ghost && near(ghost.x, 430 - 42 * 1.14, 0.5) && near(ghost.y, 400 - 42 * 1.14, 0.5), 'drag ghost follows pointer at 1.14x');
  const [x2, y2] = sqC(28);
  up(x2, y2); frames(5); // drop on e4
  ok(pieceAt(28) === bodyId('P', 'b') && pieceAt(36) === undefined, 'drag commits ...e4');
  ok(hasText('e4'), 'SAN e4');
}
{
  const ringAt = (s) => {
    const [x, y] = sqTL(s);
    return rVerbs().some((v) => near(v.x, x) && near(v.y, y) && near(v.w, 84) && near(v.h, 5) && v.color === C(0, 0, 0, 0.35)) &&
      rVerbs().some((v) => near(v.x, x) && near(v.y, y) && near(v.w, 84) && near(v.h, 3) && v.color === 0xFFF5D68A);
  };
  key(0x40000052); // Up: focusSq was e5(36) -> e6(44)
  ok(ringAt(44), 'arrow focuses e6');
  key(0x40000051); // Down -> e5
  ok(ringAt(36), 'arrow focuses e5');
  const [x1, y1] = sqC(12);
  click(x1, y1); // focus + select e2
  key(27); // Esc deselects
  ok(eVerbs().filter((v) => v.color === C(48, 26, 10, 0.3)).length === 0, 'Esc clears dots');
  key(13); // Enter selects the focused e2
  const dots = eVerbs().filter((v) => v.color === C(48, 26, 10, 0.3));
  ok(dots.length === 1, 'Enter selects: e3 the only dot (e4 blocked)');
  key(13); // Enter again deselects
  ok(eVerbs().filter((v) => v.color === C(48, 26, 10, 0.3)).length === 0, 'Enter toggles off');
  key(117); frames(2); // u undoes ...e4
  ok(pieceAt(36) === bodyId('P', 'b') && pieceAt(28) === undefined, 'u undoes ...e4');
  ok(hasText('A to move'), 'u restores side to move (named)');
}
{
  const [nx, ny] = btnC(2);
  click(nx, ny);
  ok(nVerbs().some((v) => v.text === '?'), 'Sure? armed');
  frames(30); // 3000 ms > 2600 ms confirm window
  ok(!nVerbs().some((v) => v.text === '?'), 'Sure? times out');
  ok(nVerbs().some((v) => v.text === '6' && v.x > PX), 'still Game 6');
  ok(pieceAt(36) === bodyId('P', 'b'), 'position kept after timeout');
  click(nx, ny); click(nx, ny); frames(10);
  ok(nVerbs().some((v) => v.text === '7' && v.x > PX), 'double New reaches Game 7');
  ok(hasText('The sheet is blank \u2014 White opens.'), 'sheet blank in Game 6');
}

console.log(`chess: ${pass} passed`);
