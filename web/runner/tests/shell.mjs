// Test the shell (examples/shell/shell.wasm) through the web runner:
// opens apps in appView sandboxes, interacts with child app, and switches themes.
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P, E } from '../runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const shellWasmPath = join(here, '../../../examples/shell/shell.wasm');
if (!existsSync(shellWasmPath)) {
  console.error('FAIL: shell.wasm missing');
  process.exit(1);
}

const appResolver = (name) => {
  const p = join(here, `../../../examples/shell/${name}.wasm`);
  if (!existsSync(p)) throw new Error(`Missing child app: ${p}`);
  return readFileSync(p);
};

const shell = await createRunner({
  wasmBytes: readFileSync(shellWasmPath),
  appResolver
});

const live = (r = shell) => r.getNodes().filter((n) => n.alive);
const findByText = (t, r = shell) => live(r).find((n) => (n.props[P.TEXT] === t || n.el?.textContent === t) && (n.kind === K.TEXT || n.kind === K.BUTTON));
const clickNode = (node, runner = shell) => {
  assert(node, 'node must exist to click');
  let cur = node;
  while (cur && !runner.handlers.has(`${cur.id}:${E.CLICK}`) && cur.parent >= 0) {
    cur = runner.nodes[cur.parent];
  }
  if (cur?.el?.click) cur.el.click();
  else node.el.click();
};

// 1. Initial shell state
const homeTitle = findByText('Good evening.');
assert.ok(homeTitle, 'the shell starts on Home');

// 2. Open Calculator
const calcCard = findByText('Calculator');
assert.ok(calcCard, 'Calculator card/entry found in shell');
clickNode(calcCard);

// 3. Check AppView created and child runner instantiated
const appViewNode = live().find((n) => n.kind === K.APPVIEW && n.props[P.SOURCE] === 'calc');
assert.ok(appViewNode, 'AppView node created for calc');
const calcRunner = appViewNode.childRunner;
assert.ok(calcRunner, 'childRunner instantiated for calc');

// 4. Click 7 × 6 = in Calculator
const clickCalc = (label) => {
  const btn = live(calcRunner).find((n) => (n.kind === K.BUTTON || n.kind === K.TEXT) && (n.props[P.TEXT] === label || n.el?.textContent === label));
  assert.ok(btn, `calc button ${label} found`);
  clickNode(btn, calcRunner);
};

for (const k of ['7', '×', '6', '=']) clickCalc(k);
const calcTexts = live(calcRunner).filter((n) => n.kind === K.TEXT).map((n) => n.el?.textContent);
assert.ok(calcTexts.includes('42'), `calculator shows 42 (got: ${calcTexts.join(', ')})`);

// 5. Switch to Paper theme in Shell
const homeBtn = findByText('Home');
assert.ok(homeBtn, 'Home button found in shell');
clickNode(homeBtn);

const paperSwatch = findByText('Paper');
assert.ok(paperSwatch, 'Paper theme swatch found in Home');
clickNode(paperSwatch);

// 6. Assert theme passed to child app and child re-styled to Paper bg (0xF6F4EF)
assert.strictEqual(shell.nodes[0].props[P.THEME], 'Paper', 'shell theme is Paper');
assert.strictEqual(calcRunner.nodes[0].props[P.THEME], 'Paper', 'calc theme is Paper');
const calcBg = calcRunner.nodes[0].props[P.COLOR];
assert.strictEqual(calcBg & 0xffffff, 0xf6f4ef, `calc window background re-styled to Paper (got: 0x${(calcBg & 0xffffff).toString(16)})`);

console.log('PASS test_shell: shell, appView, calc interaction, and theme passing verified');
