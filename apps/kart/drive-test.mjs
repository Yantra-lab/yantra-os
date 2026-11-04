// Focused driving/state checks against the real release module.
// Run from yantra-os: node apps/kart/drive-test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { YantraWebRunner } from '../../web/runner/runner.js';
import { K, P, E } from '../../web/runner/protocol.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const wasmBytes = readFileSync(join(HERE, 'app.wasm'));
const runner = new YantraWebRunner({});
let DT = 1 / 60;
const held = new Set();
const baseInput = runner.env.y_input;
runner.env.y_input = (what, arg) => {
  if (what === 7) return DT;
  if (what === 0 && held.has(arg)) return 1;
  return baseInput(what, arg);
};
runner.initSync(wasmBytes);
const live = () => runner.getNodes().filter((n) => n.alive);
const scene = live().find((n) => n.kind === K.CANVAS);
assert.ok(scene, 'live canvas');
const draw = () => scene.props[P.DRAW];
const frames = (n) => { for (let i = 0; i < n; i++) runner._fire(scene.id, E.FRAME); };
const tap = (label) => {
  const button = live().find((n) => n.kind === K.BUTTON && n.props[P.TEXT] === label);
  assert.ok(button, `button ${label}`);
  button.el.click();
};
const capture = (re, name) => {
  const m = draw().match(re);
  assert.ok(m, `${name} telemetry present`);
  return m[1];
};
const speed = () => Number(capture(/N 43\.00 671\.00 [\d.]+ \d+ \d+ Arial;(\d+);/, 'speed'));
const metres = () => Number(capture(/N 948\.00 620\.00 [\d.]+ \d+ \d+ Arial;(\d+) \/ 1500 M;/, 'distance'));
const time = () => capture(/N 1158\.00 78\.00 [\d.]+ \d+ \d+ Arial;(\d\d:\d\d\.\d\d);/, 'clock');
const lean = () => Number(capture(/o (-?\d+\.\d+);/, 'steering lean'));
const KEY = { up: 0x40000052, down: 0x40000051, left: 0x40000050, right: 0x4000004f, space: 32 };
const down = (...keys) => keys.forEach((k) => held.add(k));
const up = (...keys) => keys.forEach((k) => held.delete(k));
let passed = 0;
const ok = (condition, message) => { assert.ok(condition, message); passed++; console.log(`ok ${passed} - ${message}`); };
const launch = () => { tap('LAUNCH'); frames(185); };

ok(live().length === 10, 'ten live nodes: window, stage, canvas, pedal row and six driving buttons');
ok(draw().includes('THE NIGHT IS YOURS.'), 'grid presents the race-start state');
launch();
tap('GAS'); // disable the armed throttle: ArrowUp must provide real acceleration.
frames(30);
const coast0 = speed();
frames(30);
ok(speed() < coast0, `throttle-off coasting slows the kart (${coast0} -> ${speed()} km/h)`);
down(KEY.up); frames(240); up(KEY.up);
const accelerated = speed();
ok(accelerated > coast0 + 20, `ArrowUp accelerates the kart (to ${accelerated} km/h)`);
const metres0 = metres();
frames(30);
ok(metres() > metres0, `lap distance advances with real movement (${metres0} -> ${metres()} m)`);
const freeSpeed = speed();
frames(30);
ok(speed() < freeSpeed, 'releasing ArrowUp removes throttle');
down(KEY.down); frames(18); up(KEY.down);
ok(speed() < freeSpeed - 20, `ArrowDown brakes hard (${freeSpeed} -> ${speed()} km/h)`);
const brakeBefore = speed();
tap('BRAKE'); frames(12);
ok(speed() < brakeBefore, `BRAKE pointer control drives braking state (${brakeBefore} -> ${speed()} km/h)`);

// Steering changes the actual chase-car lean and camera-relative lateral state.
down(KEY.up, KEY.left); frames(22); up(KEY.left);
ok(lean() > 0.02, `ArrowLeft creates left body lean (${lean()} deg)`);
down(KEY.right); frames(42); up(KEY.right, KEY.up); frames(4);
ok(lean() < -0.02, `ArrowRight reverses body lean (${lean()} deg)`);

launch();
down(KEY.up, KEY.right, KEY.space); frames(150);
up(KEY.right, KEY.space); frames(1); up(KEY.up);
ok(draw().includes('MINI-TURBO  /  3'), 'held steering + Space charges and releases a level-three mini-turbo');
frames(95);
ok(!draw().includes('MINI-TURBO') && draw().includes('DRIFT  /  SPACE'), 'released mini-turbo expires after its timed duration');
launch();
down(KEY.up, KEY.left); frames(120);
tap('DRIFT'); frames(55); tap('DRIFT'); frames(1); up(KEY.up, KEY.left);
ok(draw().includes('MINI-TURBO  /  1') || draw().includes('MINI-TURBO  /  2'), 'DRIFT pointer toggle charges and releases a mini-turbo');

// Full three-lap race, using the same app physics and no direct memory writes.
tap('LAUNCH');
DT = 0.1;
let raceFrames = 0;
while (!draw().includes('STAGE WON') && raceFrames < 1200) { frames(1); raceFrames++; }
ok(draw().includes('STAGE WON'), `three measured laps reach the finish (${raceFrames / 10} simulated seconds including countdown)`);
ok(draw().includes('BEST LAP  '), 'finish records a real best lap time');
ok(!draw().includes('TIME EXPIRED'), `three laps finish inside the stage limit (${time()})`);
const finishTime = time();
frames(20);
ok(time() === finishTime, `finish freezes the race clock (${finishTime})`);
tap('LAUNCH');
ok(draw().includes('HOLD YOUR LINE'), 'LAUNCH restarts through the countdown state');
ok(metres() === 0 && speed() === 0 && time() === '00:00.00', 'restart resets distance, speed and clock');
frames(185);
ok(draw().includes('STAGE LIVE'), 'restarted race returns to live driving');
console.log(`\n${passed} assertions passed; module ${wasmBytes.length} bytes; finish ${finishTime}.`);
process.exit(0);
