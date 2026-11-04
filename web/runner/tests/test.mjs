import { readFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { createRunner, K, P } from '../runner.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const wasmPath = join(__dirname, '../../../examples/counter.wasm');

const stat = statSync(wasmPath);
console.log(`counter.wasm size: ${stat.size} bytes`);
assert(stat.size > 0, 'counter.wasm must not be empty');

const wasmBytes = readFileSync(wasmPath);
const runner = await createRunner({ wasmBytes });

const nodes = runner.getNodes();
const rootEl = runner.getRootElement();

assert(nodes.length >= 4, 'expected at least 4 nodes (window, column, text, button)');
assert(rootEl !== null, 'expected a root element');

// Find nodes
const winNode = nodes.find(n => n.kind === K.WINDOW);
const colNode = nodes.find(n => n.kind === K.COLUMN);
const txtNode = nodes.find(n => n.kind === K.TEXT);
const btnNode = nodes.find(n => n.kind === K.BUTTON);

assert(winNode, 'window node exists');
assert(colNode, 'column node exists');
assert(txtNode, 'text node exists');
assert(btnNode, 'button node exists');

// Assert DOM mapping
assert.strictEqual(winNode.el.tagName.toLowerCase(), 'div', 'window maps to div');
assert.strictEqual(colNode.el.tagName.toLowerCase(), 'div', 'column maps to div');
assert.strictEqual(colNode.el.style.display, 'flex', 'column is display: flex');
assert.strictEqual(colNode.el.style.flexDirection, 'column', 'column has flex-direction: column');
assert.strictEqual(txtNode.el.tagName.toLowerCase(), 'span', 'text maps to span');
assert.strictEqual(btnNode.el.tagName.toLowerCase(), 'button', 'button maps to button');

// Assert initial values
assert.strictEqual(txtNode.el.textContent, 'Clicked 0 times', 'initial text is "Clicked 0 times"');
assert.strictEqual(btnNode.el.textContent, 'Click me', 'button text is "Click me"');

// First click
btnNode.el.click();
assert.strictEqual(txtNode.el.textContent, 'Clicked 1 times', 'after first click text is "Clicked 1 times"');

// Second click
btnNode.el.click();
assert.strictEqual(txtNode.el.textContent, 'Clicked 2 times', 'after second click text is "Clicked 2 times"');

console.log('web runner test: all assertions passed');
