// The Notes app (apps/notes/app.wasm) through the web runner: list, search,
// select and edit — the same module the native engine runs.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P, E } from '../runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const runner = await createRunner({ wasmBytes: readFileSync(join(here, '../../../apps/notes/app.wasm')) });
const live = () => runner.getNodes().filter((n) => n.alive);
const texts = () => live().filter((n) => n.kind === K.TEXT).map((n) => n.el.textContent);
const inputs = () => live().filter((n) => n.kind === K.INPUT);
const searchBox = () => inputs().find((n) => n.el.placeholder === 'Search notes');
const titleBox = () => inputs().find((n) => n.el.placeholder !== 'Search notes');
const button = (t) => live().find((n) => n.kind === K.BUTTON && n.el.textContent === t);
const typeInto = (node, value) => {
  node.el.value = value;
  node.el.dispatchEvent({ type: 'input' });
};

// seeded list renders all three notes
for (const t of ['Pitch outline', 'Demo script', 'Questions to expect']) {
  assert.ok(texts().includes(t), `seeded note listed: ${t}`);
}

// search narrows the list (title or body), clearing restores it
typeInto(searchBox(), 'questions');
assert.ok(texts().includes('Questions to expect'), 'search hit stays');
assert.ok(!texts().includes('Pitch outline'), 'search miss hides');
assert.ok(!texts().includes('Demo script'), 'search miss hides (2)');
typeInto(searchBox(), 'zzz-no-such-note');
assert.ok(texts().includes('No notes match.'), 'empty state on no hits');
typeInto(searchBox(), '');
for (const t of ['Pitch outline', 'Demo script', 'Questions to expect']) {
  assert.ok(texts().includes(t), `cleared search restores: ${t}`);
}

// New inserts a selected row; editing the title input saves into the list
button('New').el.click();
assert.ok(texts().includes('Untitled'), 'new note appears');
typeInto(titleBox(), 'My edited title');
assert.ok(texts().includes('My edited title'), 'edited title saves into the list');

// selecting another row loads its title into the editor (the innermost
// clickable column carrying the row text is the NoteRow itself)
const pitch = live().find((n) => n.kind === K.COLUMN &&
  n.el.textContent.includes('Pitch outline') && runner.handlers.has(`${n.id}:${E.CLICK}`));
assert.ok(pitch, 'pitch row found');
pitch.el.click();
assert.strictEqual(titleBox().el.value, 'Pitch outline', 'select loads title into editor');

console.log('web runner notes test: all assertions passed');
