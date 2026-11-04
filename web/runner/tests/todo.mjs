// The Todos app (apps/todo/app.wasm) through the web runner: the same module the
// native engine runs, driven the way a user would in a page.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P, E } from '../runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const runner = await createRunner({ wasmBytes: readFileSync(join(here, '../../../apps/todo/app.wasm')) });
const live = () => runner.getNodes().filter((n) => n.alive);
const labels = () => live().filter((n) => n.kind === K.CHECKBOX).map((n) => n.el._span.textContent);
const button = (t) => live().find((n) => n.kind === K.BUTTON && n.el.textContent === t);
const check = (t) => live().find((n) => n.kind === K.CHECKBOX && n.el._span.textContent === t);
const input = () => live().find((n) => n.kind === K.INPUT);
const texts = () => live().filter((n) => n.kind === K.TEXT).map((n) => n.el.textContent);

assert.deepStrictEqual(labels(), ['Write the pitch', 'Record the demo', 'Apply to IITM IC'], 'starts with three rows');
assert.ok(texts().includes('2 left'), 'shows the count');
assert.strictEqual(input().el.placeholder, 'What needs doing?');

// type and press Enter
input().el.value = 'Ship the demo';
input().el.dispatchEvent({ type: 'input' });
input().el.dispatchEvent({ type: 'keydown', key: 'Enter' });
assert.deepStrictEqual(labels(), ['Write the pitch', 'Record the demo', 'Apply to IITM IC', 'Ship the demo'], 'Enter adds a row');
assert.strictEqual(input().el.value, '', 'the input clears');
assert.ok(texts().includes('3 left'));

// check one off: controlled, so the app's state decides
check('Write the pitch').el.click();
assert.strictEqual(check('Write the pitch').el._box.checked, true, 'checked after click');
assert.ok(texts().includes('2 left'));

// filters
button('Active').el.click();
assert.deepStrictEqual(labels(), ['Apply to IITM IC', 'Ship the demo']);
button('Done').el.click();
assert.deepStrictEqual(labels(), ['Write the pitch', 'Record the demo']);
button('All').el.click();
assert.deepStrictEqual(labels().length, 4, 'all rows back');

// delete via each row's x affordance (the ROW sibling of the checkbox carrying a click handler)
for (const t of [...labels()]) {
  const boxNode = check(t); // K.CHECKBOX node; its parent is the TodoRow
  const del = live().find((n) => n.kind === K.ROW && n.parent === boxNode.parent && runner.handlers.has(`${n.id}:${E.CLICK}`));
  assert.ok(del, `delete row found for ${t}`);
  del.el.click();
}
assert.deepStrictEqual(labels(), []);
assert.ok(texts().includes('Nothing here.'), 'empty state');
assert.ok(texts().includes('0 left'));
const removed = runner.getNodes().filter((n) => !n.alive).length;
assert.ok(removed >= 4, `removed rows leave the tree (${removed} removed)`);

console.log('web runner todo test: all assertions passed');
