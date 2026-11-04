// The Calculator app (apps/calc/app.wasm) through the web runner: button-driven
// chaining, clear, backspace, percent and sign — the same module the engine runs.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P } from '../runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const runner = await createRunner({ wasmBytes: readFileSync(join(here, '../../../apps/calc/app.wasm')) });
const live = () => runner.getNodes().filter((n) => n.alive);
const texts = () => live().filter((n) => n.kind === K.TEXT).map((n) => n.el.textContent);
const display = () => texts().find((t) => /^-?[\d.]+$/.test(t.trim()));
const tap = (label) => {
  const btn = live().find((n) => n.kind === K.BUTTON && (n.props[P.TEXT] === label || n.el.textContent === label));
  assert.ok(btn, `calc button ${label} found`);
  btn.el.click();
};

assert.strictEqual(display(), '0', 'starts at zero');

// 7 × 6 = 42
for (const k of ['7', '×', '6', '=']) tap(k);
assert.strictEqual(display(), '42', '7 × 6 = 42');

// chaining: 2 + 3 × 4 = evaluates left-to-right as (2+3)×4
tap('C');
for (const k of ['2', '+', '3', '×', '4', '=']) tap(k);
assert.strictEqual(display(), '20', 'chained 2 + 3 × 4 = 20');

// decimals and percent
tap('C');
for (const k of ['1', '.', '5', '+', '2', '.', '5', '=']) tap(k);
assert.strictEqual(display(), '4', '1.5 + 2.5 = 4');
tap('C');
for (const k of ['5', '0', '%']) tap(k);
assert.strictEqual(display(), '0.5', '50% = 0.5');

// sign toggle and backspace
tap('C');
for (const k of ['9', '±']) tap(k);
assert.strictEqual(display(), '-9', '± negates');
tap('C');
for (const k of ['9', '8', '⌫']) tap(k);
assert.strictEqual(display(), '9', 'backspace trims last char');

// divide by zero stays put, clear resets
tap('C');
for (const k of ['8', '÷', '0', '=']) tap(k);
assert.strictEqual(display(), '0', '÷ 0 guards to 0');
tap('C');
assert.strictEqual(display(), '0', 'C resets');

console.log('web runner calc test: all assertions passed');
