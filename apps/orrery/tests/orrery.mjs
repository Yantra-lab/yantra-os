// Exercise the rebuilt module through the release web runner. Assertions read
// the actual retained drawing, including its computed Julian-day readout.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert/strict';
import { YantraWebRunner, K, P, E } from '../../../web/runner/runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const runner = new YantraWebRunner({});
const baseInput = runner.env.y_input;
runner.env.y_input = (what, arg) => (what === 7 ? 1 / 60 : baseInput(what, arg));
runner.initSync(readFileSync(join(here, '../app.wasm')));
const live = () => runner.getNodes().filter((n) => n.alive);
const buttons = () => live().filter((n) => n.kind === K.BUTTON);
const canvas = () => live().find((n) => n.kind === K.CANVAS);
const draw = () => canvas().props[P.DRAW];
const frameIds = live().map((n) => n.id);
function tick(n) {
  for (let frame = 0; frame < n; frame += 1) {
    for (const id of frameIds) runner._fire(id, E.FRAME);
  }
}
function clockDays() {
  const match = /CLOCK \+([0-9.]+) DAYS/.exec(draw());
  assert.ok(match, 'live clock readout exists in draw commands');
  return Number(match[1]);
}
function tap(label) {
  const node = buttons().find((n) => n.props[P.TEXT] === label || n.el.textContent === label);
  assert.ok(node, `button ${label} exists`);
  node.el.click();
  return node;
}

assert.equal(buttons().length, 15, '8 planets + 7 transport controls');
assert.ok(draw().includes('01 JANUARY'), 'starts on 1 January 1774');
assert.ok(draw().includes('IN CANCER 13°'), 'Earth cartouche shows its computed zodiac sign');
assert.equal(clockDays(), 0, 'initial clock is the 1774 epoch');
const initialDraw = draw();
tick(90);
assert.notEqual(draw(), initialDraw, '90 frame ticks redraw the instrument');
assert.equal(clockDays(), 1.5, '90 fixed 1/60-second ticks advance exactly 1.5 days');
assert.ok(draw().includes('02 JANUARY'), 'calendar advances to 2 January');
const dayState = draw();

tap('HALT');
const halted = clockDays();
const haltedDraw = draw();
tick(120);
assert.equal(clockDays(), halted, 'HALT freezes the simulated Julian day');
assert.equal(draw(), haltedDraw, 'HALT freezes the whole mechanical drawing');
console.log(`motion: 90 day/s ticks = ${clockDays()} simulated days; 120 halted ticks = 0`);

tap('1 YEAR / S');
const beforeYear = clockDays();
tick(366);
assert.ok(clockDays() - beforeYear > 2200, `year/s advances years, got ${clockDays() - beforeYear}`);
console.log(`motion: 366 year/s ticks = ${(clockDays() - beforeYear).toFixed(1)} additional days`);

const beforeStep = clockDays();
tap('+ 7 DAYS');
const afterPlus = clockDays();
assert.equal(afterPlus, beforeStep + 7, '+ 7 DAYS changes the clock by exactly seven');
const plusDraw = draw();
tick(90);
assert.equal(draw(), plusDraw, 'date stepping also latches HALT');
tap('- 7 DAYS');
assert.ok(clockDays() < afterPlus, '- 7 DAYS winds backward');
assert.equal(afterPlus - clockDays(), 7, 'backward step is exactly seven days');

tap('SATURN');
assert.ok(draw().includes('10755.884 d'), 'Saturn selection puts its sidereal period in the cartouche');
const saturnButton = buttons().find((n) => n.props[P.TEXT] === 'SATURN');
assert.ok(saturnButton, 'Saturn button exists');
assert.equal((saturnButton.props[P.COLOR] >>> 0) & 0xFFFFFF, 0xFFE29A, 'selected planet has the brass highlight');

tap('1774 EPOCH');
assert.equal(clockDays(), 0, 'epoch button restores the initial Julian day');
assert.ok(draw().includes('01 JANUARY'), 'epoch restores the initial civil date');
assert.ok(draw().includes('IN CANCER 13°'), 'epoch restores Earth and its original computed sign');
const earthButton = buttons().find((n) => n.props[P.TEXT] === 'EARTH');
assert.equal((earthButton.props[P.COLOR] >>> 0) & 0xFFFFFF, 0xFFE29A, 'Earth highlight is restored');
const epochDraw = draw();
tap('1 DAY / S');
tick(90);
assert.ok(clockDays() > 0, 'day/s resumes from a halted epoch');
assert.notEqual(draw(), epochDraw, 'resumed motion differs from the epoch drawing');

console.log('orrery interaction test: all assertions passed');
