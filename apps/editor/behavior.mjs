// Focused UI checks for the module built from app.nim. Run from any directory:
//   node apps/editor/behavior.mjs
// Each scenario gets a fresh wasm instance; the dependency-free Node DOM is a
// protocol harness, not a browser or a substitute for the native render proof.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P, E } from '../../web/runner/runner.js';

const here = dirname(fileURLToPath(import.meta.url));
const ownText = (n) => n.el?.textContent || n.props[P.TEXT] || '';

async function boot() {
  const runner = await createRunner({ wasmBytes: readFileSync(join(here, 'app.wasm')) });
  const live = () => runner.getNodes().filter((n) => n.alive);
  const texts = () => live().filter((n) => n.kind === K.TEXT).map(ownText);
  const button = (label) => {
    const found = live().find((n) => n.kind === K.BUTTON && ownText(n) === label);
    assert.ok(found, `button exists: ${label}`);
    return found;
  };
  const textarea = () => {
    const found = live().find((n) => n.kind === K.TEXTAREA);
    assert.ok(found, 'the live edit buffer exists');
    return found;
  };
  const searchBox = () => {
    const found = live().find((n) => n.kind === K.INPUT && n.el?.placeholder === 'Search files');
    assert.ok(found, 'file search is a real input');
    return found;
  };
  const typeInto = (node, value) => {
    node.el.value = value;
    node.props[P.VALUE] = value;
    runner._fire(node.id, E.INPUT);
  };
  const click = (label) => {
    // Choose the current handler. The tiny Node DOM retains listeners from an
    // older render; the native proof separately supplies real pointer input.
    runner._fire(button(label).id, E.CLICK);
  };
  return {
    live, texts, button, textarea, searchBox, typeInto, click,
    value: () => textarea().props[P.VALUE] || '',
  };
}

// The event sequence edit -> comment -> save -> edit -> revert is one real state machine.
{
  console.log('[scenario] editing');
  const s = await boot();
  assert.strictEqual(s.value(), '## no document yet — type below.', 'the empty-database buffer boots');
  assert.ok(s.texts().includes('Saved'), 'the initial buffer is clean');
  assert.strictEqual(s.button('Save').props[P.FONTFAMILY], 'Noto Sans');

  s.typeInto(s.textarea(), 'let answer = 42\nreturn answer');
  assert.strictEqual(s.value(), 'let answer = 42\nreturn answer');
  assert.ok(s.texts().includes('answer'), 'the edited identifier is re-tokenised');
  assert.ok(s.texts().includes('2 lines'), 'line count follows the edit');
  assert.ok(s.texts().includes('Unsaved'), 'editing marks the buffer dirty');
  const codeToken = s.live().find((n) => n.kind === K.TEXT && ownText(n) === 'let');
  assert.strictEqual(codeToken.props[P.FONTFAMILY], 'DejaVu Sans Mono');

  s.click('Comment');
  const commented = '# let answer = 42\nreturn answer';
  assert.strictEqual(s.value(), commented, 'Comment changes the current line');
  s.click('Save');
  assert.strictEqual(s.value(), commented, 'Save preserves the buffer byte for byte');
  assert.ok(!s.texts().includes('Unsaved') && s.texts().includes('Saved'), 'Save clears dirty state');

  s.typeInto(s.textarea(), `${s.value()}\n# draft`);
  assert.ok(s.texts().includes('Ln 2, Col 14'), 'line and column derive from the changed byte');
  s.click('Revert');
  assert.strictEqual(s.value(), commented, 'Revert restores the saved buffer');
  assert.ok(s.texts().includes('Saved'), 'Revert restores clean status');
}

// Search handles an empty result and exposes a working clear action.
{
  console.log('[scenario] search');
  const s = await boot();
  s.typeInto(s.searchBox(), 'not-a-file');
  assert.ok(s.texts().includes('No matching files'), 'search explains an empty result');
  s.click('Clear search');
  assert.strictEqual(s.searchBox().props[P.VALUE] || '', '', 'Clear search resets the query');
}

console.log('editor behavior: all scenarios passed (edit/tokenise/comment/save/revert, search, fonts)');
