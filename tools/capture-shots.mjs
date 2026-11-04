#!/usr/bin/env node
/**
 * tools/capture-shots.mjs — real, reproducible screenshots of the shipped apps.
 *
 * What it does
 *   Serves this repo over http://127.0.0.1:<ephemeral port>, opens
 *   web/runner/app.html?app=<name> for each app, lets the real .wasm module
 *   paint through web/runner/ (the repo's dependency-free DOM runner), advances
 *   a fixed number of animation frames, and writes a PNG per app to docs/img/.
 *
 * Everything is honest: the picture is whatever the shipped module actually
 * paints. Nothing is drawn by this script; it only takes pictures.
 *
 * Usage
 *   node tools/capture-shots.mjs                # default set: apps that paint DOM through the runner
 *   node tools/capture-shots.mjs --all          # all ten apps (canvas-only ones are reported as blank)
 *   node tools/capture-shots.mjs --only todo
 *   node tools/capture-shots.mjs --apps todo,calc,notes
 *   node tools/capture-shots.mjs --frames 60 --viewport 1440x900
 *   node tools/capture-shots.mjs --all --allow-blank   # write the canvas-only shots too, exit 0
 *
 * Env overrides
 *   PLAYWRIGHT_PATH   path to playwright's entry (index.mjs or index.js) or its package dir
 *   CHROME_PATH       path to a chromium / headless_shell binary
 *
 * Exit code is 0 only when every requested app painted and produced a
 * plausible, non-flat screenshot.
 */

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

// ---------------------------------------------------------------------------
// paths — derived from this file's own location, never from the cwd
// ---------------------------------------------------------------------------

// path.resolve() drops the trailing separator that new URL('..') keeps, so
// prefixes compare correctly below.
const ROOT = path.resolve(fileURLToPath(new URL('..', import.meta.url))); // <repo>/yantra-os
const OUT_DIR = path.join(ROOT, 'docs', 'img');

const PLAYWRIGHT_DEFAULT = '/home/ubuntu/yantra/open/node_modules/playwright/index.mjs';
const CHROME_DEFAULT = '/home/ubuntu/.cache/ms-playwright/chromium-1248/chrome-linux64/chrome';

// ---------------------------------------------------------------------------
// the apps
//   renderer: 'dom'          — the app builds real DOM through web/runner (capturable)
//             'canvas-only'  — the app paints a Draw command list on a canvas node; the
//                              DOM runner has no canvas backend, so only its window
//                              chrome shows. Still real, but nearly empty.
// ---------------------------------------------------------------------------

const APPS = [
  {
    id: 'descent',
    title: 'Gradient Descent',
    what: 'a live loss landscape with steps, learning rate and momentum controls',
    renderer: 'canvas-only',
  },
  {
    id: 'gallery3d',
    title: 'Gallery 3D',
    what: 'a corridor of paintings walked with the keyboard or the on-screen pads',
    renderer: 'canvas-only',
  },
  {
    id: 'calc',
    title: 'Calculator',
    what: 'a 5×4 key grid built from one Nim component, themed with the shared design tokens',
    renderer: 'dom',
  },
  {
    id: 'chess',
    title: "Grandmaster's Study",
    what: 'a full chess study (board, moves, analysis) painted as a Draw command list on a canvas',
    renderer: 'canvas-only',
  },
  {
    id: 'desktop',
    title: 'Desktop Shell',
    what: 'the shell: an Arc sidebar, a Caelestia bar, a shader wallpaper, windows that float or tile',
    renderer: 'dom',
  },
  {
    id: 'dna',
    title: 'Helix DNA',
    what: 'an animated DNA double helix painted on a canvas',
    renderer: 'canvas-only',
  },
  {
    id: 'editor',
    title: 'Yantra Studio IDE',
    what: 'a code editor: file tree, Nim-highlighted pane, minimap — painted on a canvas',
    renderer: 'canvas-only',
  },
  {
    id: 'files',
    title: 'Yantra File Manager',
    what: 'a two-pane file browser painted on a canvas',
    renderer: 'canvas-only',
  },
  {
    id: 'gallery',
    title: 'Galerie Nocturne',
    what: 'a 3D-ish walk-through gallery scene painted on a canvas',
    renderer: 'canvas-only',
  },
  {
    id: 'notes',
    title: 'Notes',
    what: 'a two-pane notebook: grouped note list plus a bound textarea',
    renderer: 'dom',
  },
  {
    id: 'todo',
    title: 'Todos',
    what: 'a task list with add / toggle / filter / clear, a bound input and keyed rows',
    renderer: 'dom',
  },
  {
    id: 'typewriter',
    title: 'Marlowe 44 Typewriter',
    what: 'a letter-writing scene: DOM chrome (sheet number, line/column, keystrokes) over a canvas',
    renderer: 'dom',
  },
];

const DEFAULT_IDS = APPS.filter((a) => a.renderer === 'dom').map((a) => a.id);

// ---------------------------------------------------------------------------
// tiny CLI
// ---------------------------------------------------------------------------

const USAGE = `
capture-shots — screenshot the Yantra OS apps through web/runner/

  node tools/capture-shots.mjs [options]

Options
  --only <name>       capture exactly one app (e.g. --only todo)
  --apps a,b,c        capture this list (comma separated)
  --all               capture all ${APPS.length} apps, including the canvas-only ones
  --allow-blank       also write the PNG of a blank window, and do not fail on it
  --frames <n>        animation frames to advance before the shot (default 60)
  --viewport <WxH>    viewport size (default 1440x900, deviceScaleFactor 1)
  -h, --help          this text

Default set (${DEFAULT_IDS.join(', ')}).
Exit code 0 only if every requested app painted a non-blank screenshot.
`.trim();

function die(msg) {
  console.error(`capture-shots: ${msg}`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = {
    only: null,
    apps: null,
    all: false,
    allowBlank: false,
    frames: 60,
    width: 1440,
    height: 900,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => {
      const v = argv[++i];
      if (v == null || v.startsWith('--')) die(`${a} needs a value`);
      return v;
    };
    if (a === '--only') opts.only = val();
    else if (a === '--apps') opts.apps = val().split(',').map((s) => s.trim()).filter(Boolean);
    else if (a === '--all') opts.all = true;
    else if (a === '--allow-blank') opts.allowBlank = true;
    else if (a === '--frames') {
      opts.frames = Number(val());
      if (!Number.isFinite(opts.frames) || opts.frames < 0) die('--frames needs a non-negative number');
    } else if (a === '--viewport') {
      const m = /^(\d+)x(\d+)$/.exec(val());
      if (!m) die('--viewport needs WxH, e.g. 1440x900');
      opts.width = Number(m[1]);
      opts.height = Number(m[2]);
    } else if (a === '--help' || a === '-h') {
      console.log(USAGE);
      process.exit(0);
    } else die(`unknown flag "${a}" (try --help)`);
  }
  if (opts.only && opts.apps) die('use either --only or --apps, not both');
  const known = new Set(APPS.map((a) => a.id));
  const wanted = opts.only ? [opts.only] : opts.apps ? opts.apps : opts.all ? APPS.map((a) => a.id) : DEFAULT_IDS;
  for (const id of wanted) if (!known.has(id)) die(`unknown app "${id}" — known: ${[...known].join(', ')}`);
  opts.ids = [...new Set(wanted)];
  return opts;
}

// ---------------------------------------------------------------------------
// playwright + chromium discovery (known-good defaults, env-overridable)
// ---------------------------------------------------------------------------

function fileCandidates(p) {
  if (!p) return [];
  const out = [];
  try {
    if (fs.statSync(p).isDirectory()) {
      for (const f of ['index.mjs', 'index.js']) out.push(path.join(p, f));
      const pkgPath = path.join(p, 'package.json');
      if (fs.existsSync(pkgPath)) {
        try {
          const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
          const entry = typeof pkg.module === 'string' ? pkg.module : typeof pkg.main === 'string' ? pkg.main : null;
          if (entry) out.push(path.join(p, entry));
        } catch {
          /* ignore a malformed package.json */
        }
      }
    } else {
      out.push(p);
    }
  } catch {
    out.push(p);
  }
  return out;
}

async function loadPlaywright() {
  const candidates = [
    ...fileCandidates(process.env.PLAYWRIGHT_PATH),
    ...fileCandidates(PLAYWRIGHT_DEFAULT),
    ...fileCandidates('/home/ubuntu/yantra/open/node_modules/playwright/index.js'),
  ];
  const tried = [];
  for (const cand of [...new Set(candidates)]) {
    if (!fs.existsSync(cand)) {
      tried.push(`${cand} (missing)`);
      continue;
    }
    try {
      const mod = await import(pathToFileURL(cand).href);
      const chromium = mod.chromium || mod.default?.chromium;
      if (!chromium) {
        tried.push(`${cand} (no "chromium" export)`);
        continue;
      }
      return { chromium, from: cand };
    } catch (e) {
      tried.push(`${cand} (${e.message.split('\n')[0]})`);
    }
  }
  throw new Error(
    'could not load playwright. Set PLAYWRIGHT_PATH to playwright/index.mjs.\n  tried:\n    ' + tried.join('\n    '),
  );
}

function findChromeCandidates() {
  const out = [];
  const add = (p) => {
    if (p && !out.includes(p)) out.push(p);
  };
  for (const c of fileCandidates(process.env.CHROME_PATH)) add(c);
  if (process.env.CHROME_PATH) return out;
  add(CHROME_DEFAULT);
  // discover whatever the local playwright cache actually has, newest first
  const cacheDirs = [path.join(os.homedir(), '.cache', 'ms-playwright'), '/root/.cache/ms-playwright'];
  for (const cache of cacheDirs) {
    let names = [];
    try {
      names = fs.readdirSync(cache);
    } catch {
      continue;
    }
    names.sort().reverse();
    for (const n of names) {
      if (n.startsWith('chromium_headless_shell')) {
        add(path.join(cache, n, 'chrome-headless-shell-linux64', 'chrome-headless-shell'));
        add(path.join(cache, n, 'chrome-linux', 'headless_shell'));
      }
      if (n.startsWith('chromium')) {
        add(path.join(cache, n, 'chrome-linux64', 'chrome'));
        add(path.join(cache, n, 'chrome-linux', 'chrome'));
      }
    }
  }
  return out;
}

const LAUNCH_ARGS = ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--hide-scrollbars', '--force-device-scale-factor=1'];

async function launchChromium(chromium, log) {
  const chromePaths = findChromeCandidates().filter((p) => fs.existsSync(p));
  const isShell = (p) => /headless/i.test(path.basename(p));
  const headless = chromePaths.filter(isShell);
  const full = chromePaths.filter((p) => !isShell(p));
  const attempts = [];
  for (const p of full) {
    attempts.push({ label: `${p} [--headless=new]`, opts: { executablePath: p, args: [...LAUNCH_ARGS, '--headless=new'] } });
    attempts.push({ label: p, opts: { executablePath: p, args: LAUNCH_ARGS } });
  }
  attempts.push({ label: 'playwright default chromium', opts: { args: LAUNCH_ARGS } });
  for (const p of headless) {
    attempts.push({ label: `${p} [headless shell]`, opts: { executablePath: p, args: LAUNCH_ARGS } });
  }
  const errors = [];
  for (const a of attempts) {
    try {
      const browser = await chromium.launch({ ...a.opts, timeout: 45000 });
      log(`chromium: launched ${a.label}`);
      return { browser, label: a.label, executablePath: a.opts.executablePath || '(playwright default)' };
    } catch (e) {
      const msg = String(e.message || e).split('\n').slice(0, 3).join(' / ');
      errors.push(`${a.label}: ${msg}`);
      log(`chromium: launch failed — ${a.label}: ${msg}`);
    }
  }
  throw new Error('could not launch chromium. Tried:\n  ' + errors.join('\n  '));
}

// ---------------------------------------------------------------------------
// static server (127.0.0.1, ephemeral port)
// ---------------------------------------------------------------------------

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

async function startServer() {
  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, 'http://127.0.0.1');
      let rel = decodeURIComponent(url.pathname);
      if (rel.endsWith('/')) rel += 'index.html';
      const file = path.resolve(ROOT, '.' + rel);
      if (file !== ROOT && !file.startsWith(ROOT + path.sep)) {
        res.writeHead(403, { 'content-type': 'text/plain' });
        res.end('forbidden');
        return;
      }
      const st = await fsp.stat(file).catch(() => null);
      if (!st || !st.isFile()) {
        res.writeHead(404, { 'content-type': 'text/plain' });
        res.end('not found: ' + rel);
        return;
      }
      const body = await fsp.readFile(file);
      res.writeHead(200, {
        'content-type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'content-length': body.length,
        'cache-control': 'no-store',
      });
      res.end(req.method === 'HEAD' ? undefined : body);
    } catch (e) {
      res.writeHead(500, { 'content-type': 'text/plain' });
      res.end(String(e && e.stack ? e.stack : e));
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  return { server, port };
}

// ---------------------------------------------------------------------------
// page work
// ---------------------------------------------------------------------------

function rafTicks(page, n) {
  return page.evaluate(async (count) => {
    const raf = () => new Promise((r) => requestAnimationFrame(r));
    await raf();
    await raf();
    for (let i = 0; i < count; i++) await raf();
  }, n);
}

const withTimeout = (promise, ms, label) =>
  Promise.race([
    promise,
    new Promise((_, reject) => {
      const t = setTimeout(() => reject(new Error(`${label} timed out after ${ms} ms`)), ms);
      if (t.unref) t.unref();
    }),
  ]);

/** Decode the PNG in the browser and measure it: how many colours, how much
 *  contrast, how much of the app window is actually painted. No vision model. */
async function measurePng(page, pngBuffer, windowRect) {
  const b64 = pngBuffer.toString('base64');
  return page.evaluate(
    async ({ data, rect }) => {
      const img = await new Promise((ok, no) => {
        const i = new Image();
        i.onload = () => ok(i);
        i.onerror = () => no(new Error('PNG failed to decode in the browser'));
        i.src = 'data:image/png;base64,' + data;
      });
      const canvas = document.createElement('canvas');
      canvas.width = img.width;
      canvas.height = img.height;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      ctx.drawImage(img, 0, 0);
      const px = ctx.getImageData(0, 0, img.width, img.height).data;

      const measure = (x0, y0, x1, y1) => {
        const w = Math.max(0, x1 - x0);
        const h = Math.max(0, y1 - y0);
        const n = w * h;
        if (!n) return null;
        const hist = new Map();
        for (let y = y0; y < y1; y++) {
          for (let x = x0; x < x1; x++) {
            const i = (y * img.width + x) * 4;
            const k = ((px[i] >> 4) << 8) | ((px[i + 1] >> 4) << 4) | (px[i + 2] >> 4);
            hist.set(k, (hist.get(k) || 0) + 1);
          }
        }
        let modalKey = 0;
        let modalN = -1;
        for (const [k, v] of hist) if (v > modalN) ((modalN = v), (modalKey = k));
        const mr = ((modalKey >> 8) & 15) * 17;
        const mg = ((modalKey >> 4) & 15) * 17;
        const mb = (modalKey & 15) * 17;
        let sum = 0;
        let sum2 = 0;
        let ink = 0;
        for (let y = y0; y < y1; y++) {
          for (let x = x0; x < x1; x++) {
            const i = (y * img.width + x) * 4;
            const r = px[i];
            const g = px[i + 1];
            const b = px[i + 2];
            const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            sum += lum;
            sum2 += lum * lum;
            if (Math.abs(r - mr) > 12 || Math.abs(g - mg) > 12 || Math.abs(b - mb) > 12) ink++;
          }
        }
        let edges = 0;
        for (let y = Math.max(1, y0); y < y1; y++) {
          for (let x = Math.max(1, x0); x < x1; x++) {
            const i = (y * img.width + x) * 4;
            if (Math.abs(px[i] - px[i - 4]) + Math.abs(px[i + 1] - px[i - 3]) + Math.abs(px[i + 2] - px[i - 2]) > 24) edges++;
          }
        }
        const mean = sum / n;
        return {
          width: w,
          height: h,
          colors: hist.size,
          meanLum: +mean.toFixed(1),
          sdLum: +Math.sqrt(Math.max(0, sum2 / n - mean * mean)).toFixed(2),
          inkPct: +((100 * ink) / n).toFixed(2),
          edgePct: +((100 * edges) / n).toFixed(2),
        };
      };

      const area = { x0: 0, y0: 0, x1: img.width, y1: img.height };
      const clip = rect
        ? {
            x0: Math.max(0, Math.min(img.width, Math.round(rect.x))),
            y0: Math.max(0, Math.min(img.height, Math.round(rect.y))),
            x1: Math.max(0, Math.min(img.width, Math.round(rect.x + rect.width))),
            y1: Math.max(0, Math.min(img.height, Math.round(rect.y + rect.height))),
          }
        : area;
      return { page: measure(area.x0, area.y0, area.x1, area.y1), window: measure(clip.x0, clip.y0, clip.x1, clip.y1) };
    },
    { data: b64, rect: windowRect },
  );
}

async function captureApp(ctx, baseUrl, app, opts, log) {
  const page = await ctx.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(e.message.split('\n')[0]));
  page.on('console', (m) => {
    if (m.type() === 'error') pageErrors.push('console: ' + m.text().slice(0, 200));
  });

  const result = { app, state: 'fail', reason: '', status: '', windowRect: null, png: null, bytes: 0 };

  try {
    const wasmPath = path.join(ROOT, 'apps', app.id, 'app.wasm');
    result.wasmBytes = fs.existsSync(wasmPath) ? fs.statSync(wasmPath).size : 0;

    await withTimeout(
      page.goto(`${baseUrl}/web/runner/app.html?app=${app.id}`, { waitUntil: 'load', timeout: 30000 }),
      40000,
      `loading ${app.id}`,
    );

    // the module is loaded when the runner says so (app.html writes `#status`)
    await withTimeout(
      page.waitForFunction(
        () => /loaded|error|could not/i.test(document.getElementById('status')?.textContent || ''),
        null,
        { timeout: 30000, polling: 100 },
      ),
      35000,
      `waiting for ${app.id} to load`,
    );
    result.status = (await page.textContent('#status')) || '';
    if (/error|could not/i.test(result.status)) {
      result.reason = `runner reported: ${result.status.trim()}`;
      return result;
    }

    // ... and when the app itself has mounted a window
    await withTimeout(
      page.waitForFunction(() => !!document.querySelector('#app .y-window'), null, { timeout: 15000, polling: 50 }),
      20000,
      `waiting for ${app.id} to mount its window`,
    );
    result.windowRect = await page.evaluate(() => {
      const el = document.querySelector('#app .y-window');
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    });

    // at least 2 animation frames, then a fixed run of frames so animated scenes
    // are mid-motion rather than caught at frame 0
    await rafTicks(page, opts.frames);
    await page.waitForTimeout(150);

    const shot = await page.screenshot({ type: 'png' }); // viewport, not full page
    result.png = shot;
    result.bytes = shot.length;

    result.measure = await measurePng(page, shot, result.windowRect);
    const w = result.measure.window;
    const tooSmall = shot.length <= 3000;
    const tooFlat = !w || w.colors < 8 || w.sdLum < 2.5 || w.inkPct < 0.5;
    result.state = tooSmall || tooFlat ? 'blank' : 'ok';
    if (tooSmall) result.reason = `screenshot is only ${shot.length} bytes`;
    else if (tooFlat) result.reason = 'app window painted no content (flat / single colour)';
    if (result.state === 'blank' && app.renderer === 'canvas-only') {
      result.reason =
        'loads, but paints only its window background: the app draws a canvas Draw list and web/runner has no canvas backend';
    }
    return result;
  } catch (e) {
    result.reason = `error: ${e.message}`;
    if (pageErrors.length) result.reason += ` [page: ${pageErrors.slice(0, 2).join(' | ')}]`;
    return result;
  } finally {
    await page.close().catch(() => {});
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

const log = (msg) => console.log(msg);

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const todo = APPS.filter((a) => opts.ids.includes(a.id));

  if (!fs.existsSync(path.join(ROOT, 'web', 'runner', 'app.html'))) {
    die(`no web/runner/app.html under ${ROOT}`);
  }
  await fsp.mkdir(OUT_DIR, { recursive: true });

  log(`repo:      ${ROOT}`);
  log(`out:       ${OUT_DIR}`);
  log(`viewport:  ${opts.width}x${opts.height} @1x, ${opts.frames} animation frames per app`);
  log(`apps:      ${todo.map((a) => a.id).join(', ')}`);

  const { chromium, from } = await loadPlaywright();
  log(`playwright from: ${from}`);

  const { browser, label: browserLabel, executablePath } = await launchChromium(chromium, log);

  const { server, port } = await startServer();
  const baseUrl = `http://127.0.0.1:${port}`;
  log(`server:    ${baseUrl} -> ${ROOT}`);

  const ctx = await browser.newContext({
    viewport: { width: opts.width, height: opts.height },
    deviceScaleFactor: 1,
    colorScheme: 'dark',
  });

  const results = [];
  try {
    for (const app of todo) {
      process.stdout.write(`capturing ${app.id} … `);
      const r = await captureApp(ctx, baseUrl, app, opts, log);
      console.log(
        r.state === 'ok' ? 'ok' : r.state === 'blank' ? `blank (${r.reason})` : `FAILED (${r.reason})`,
      );
      if (r.png && (r.state === 'ok' || opts.allowBlank)) {
        const file = path.join(OUT_DIR, `${app.id}.png`);
        await fsp.writeFile(file, r.png);
        r.file = file;
        r.sha256 = crypto.createHash('sha256').update(r.png).digest('hex');
      }
      results.push(r);
    }
  } finally {
    await ctx.close().catch(() => {});
    await browser.close().catch(() => {});
    await new Promise((r) => server.close(r));
  }

  // ---- cross-app sanity: two different apps with byte-identical PNGs is suspicious
  const bySize = new Map();
  for (const r of results) {
    if (!r.bytes) continue;
    if (!bySize.has(r.bytes)) bySize.set(r.bytes, []);
    bySize.get(r.bytes).push(r.app.id);
  }
  const suspicious = [...bySize.entries()].filter(([, ids]) => ids.length > 1);
  for (const [size, ids] of suspicious) {
    console.error(`WARNING: identical PNG byte size (${size}) for ${ids.join(' and ')} — suspiciously flat output`);
  }

  // ---- table
  const rows = results.map((r) => ({
    app: r.app.id,
    wasm: r.wasmBytes ? `${r.wasmBytes} B` : '-',
    file: r.file ? path.relative(ROOT, r.file) : '(not written)',
    png: r.png ? `${r.bytes} B` : '-',
    pixels: r.measure?.page ? `${r.measure.page.width}x${r.measure.page.height}` : '-',
    ink: r.measure?.window ? `${r.measure.window.inkPct}%` : '-',
    colours: r.measure?.window ? String(r.measure.window.colors) : '-',
    state: r.state,
  }));
  const cols = ['app', 'wasm', 'file', 'png', 'pixels', 'ink', 'colours', 'state'];
  const widths = {};
  for (const c of cols) widths[c] = Math.max(c.length, ...rows.map((r) => String(r[c]).length));
  const line = (vals) => vals.map((v, i) => String(v).padEnd(widths[cols[i]])).join(' | ');
  console.log('');
  console.log(line(cols));
  console.log(cols.map((c) => '-'.repeat(widths[c])).join('-+-'));
  for (const r of rows) console.log(line(cols.map((c) => r[c])));

  // ---- manifest + summary
  const failed = results.filter((r) => r.state === 'fail');
  const blank = results.filter((r) => r.state === 'blank');
  const manifest = {
    note: 'Screenshots taken by tools/capture-shots.mjs from the shipped apps/*/app.wasm through web/runner/. Not the native Skia renderer.',
    viewport: `${opts.width}x${opts.height}@1x`,
    frames: opts.frames,
    runner: 'web/runner/app.html',
    playwright: from,
    chromium: executablePath,
    launch: browserLabel,
    apps: results.map((r) => ({
      app: r.app.id,
      title: r.app.title,
      renderer: r.app.renderer,
      state: r.state,
      reason: r.reason || undefined,
      wasmBytes: r.wasmBytes,
      file: r.file ? path.relative(ROOT, r.file) : undefined,
      pngBytes: r.bytes || undefined,
      width: r.measure?.page?.width,
      height: r.measure?.page?.height,
      windowInkPct: r.measure?.window?.inkPct,
      windowColors: r.measure?.window?.colors,
      sha256: r.sha256,
    })),
  };
  await fsp.writeFile(path.join(OUT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  console.log('');
  console.log(`manifest:  ${path.relative(ROOT, path.join(OUT_DIR, 'manifest.json'))}`);

  if (failed.length) {
    console.error(`\n${failed.length} app(s) failed: ${failed.map((r) => `${r.app.id} (${r.reason})`).join('; ')}`);
  }
  const blockingBlank = opts.allowBlank ? [] : blank;
  if (blockingBlank.length) {
    console.error(`\n${blockingBlank.length} app(s) rendered blank: ${blockingBlank.map((r) => r.app.id).join(', ')}`);
    console.error('  (canvas-only apps cannot paint through the DOM runner; pass --allow-blank to accept them)');
  }
  const bad = failed.length + blockingBlank.length + suspicious.length;
  if (bad) {
    console.error(`\ncapture-shots: FAILED (${bad} problem${bad === 1 ? '' : 's'})`);
    process.exitCode = 1;
  } else {
    console.log(`\ncapture-shots: ${results.length}/${results.length} apps captured, all non-blank.`);
    process.exitCode = 0;
  }
}

main().catch((e) => {
  console.error(`capture-shots: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
