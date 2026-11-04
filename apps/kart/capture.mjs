// Capture the shipped kart wasm through the repository's real browser runner.
// Usage from yantra-os: node apps/kart/capture.mjs [animation frames]
import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { chromium } from '/home/ubuntu/yantra/open/node_modules/playwright/index.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const OUT = path.join(ROOT, 'proofs');
const frames = Math.max(1, Number(process.argv[2] || 540));
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const server = http.createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const file = path.resolve(ROOT, '.' + (pathname === '/' ? '/web/runner/app.html' : pathname));
    if (!file.startsWith(ROOT + path.sep)) throw new Error('bad path');
    const data = await fsp.readFile(file);
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  } catch {
    res.writeHead(404); res.end('not found');
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = server.address().port;
const browser = await chromium.launch({
  executablePath: '/home/ubuntu/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome',
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});
const errors = [];
try {
  const page = await browser.newPage({ viewport: { width: 1320, height: 900 }, deviceScaleFactor: 1, colorScheme: 'dark' });
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(`http://127.0.0.1:${port}/proofs/__capture`, { waitUntil: 'load' });
  await page.setContent('<html><body style="margin:0;background:#050507"><div id="app"></div></body></html>');
  await page.evaluate(async (appUrl) => {
    const { createRunner } = await import('/web/runner/runner.js');
    const { K, E } = await import('/web/runner/protocol.mjs');
    const wasmBytes = await (await fetch(appUrl)).arrayBuffer();
    const runner = await createRunner({ wasmBytes, targetElement: document.getElementById('app') });
    const scene = runner.getNodes().find((n) => n.alive && n.kind === K.CANVAS);
    const baseInput = runner.env.y_input;
    runner.env.y_input = (what, arg) => what === 7 ? 1 / 60 : baseInput(what, arg);
    // Physics always runs. Only the redundant intermediate browser rasterisation is
    // deferred; the final proof is painted from the final retained command list.
    const paint = runner._paintCanvas.bind(runner);
    window.__fastCapture = false;
    runner._paintCanvas = (node) => { if (!window.__fastCapture) paint(node); };
    window.__paintNow = () => paint(scene);
    window.__drive = async (count) => {
      for (let i = 0; i < count; i++) {
        runner._fire(scene.id, E.FRAME);
        if (i % 30 === 29) await new Promise(requestAnimationFrame);
      }
    };
  }, '/apps/kart/app.wasm');
  await page.addStyleTag({ content: '#app > .y-window { border-radius: 0 !important; box-shadow: none !important; }' });
  const shot = async (name) => {
    const target = path.join(OUT, name);
    await page.locator('#app .y-window').screenshot({ path: target });
    const png = await fsp.readFile(target);
    const rect = await page.locator('#app .y-window').boundingBox();
    console.log(`${path.relative(ROOT, target)} ${rect.width}x${rect.height} ${png.length} B sha256 ${crypto.createHash('sha256').update(png).digest('hex')}`);
  };
  await shot('kart-grid.png');
  await page.evaluate(() => { window.__fastCapture = true; });
  await page.getByRole('button', { name: 'LAUNCH', exact: true }).click();
  await page.evaluate((n) => window.__drive(n), frames);
  await page.evaluate(() => { window.__fastCapture = false; window.__paintNow(); });
  await shot('kart.png');
  if (errors.length) throw new Error(errors.join(' | '));
  console.log(`capture: real app.wasm, LAUNCH pointer tap, ${frames} deterministic 1/60 s module frames; final retained list painted; page errors 0`);
} finally {
  await browser.close();
  await new Promise((resolve) => server.close(resolve));
}
