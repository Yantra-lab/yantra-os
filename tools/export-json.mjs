#!/usr/bin/env node
// tools/export-json.mjs — export a running Yantra app as a JSON document.
//
// WHAT THIS IS
//   Every Yantra app is a `.wasm` module. This tool loads that module in the
//   repo's own web runner (web/runner/runner.js), lets it build its UI tree,
//   steps a number of frames so canvas-driven apps paint, and then writes down
//   what the module actually built:
//
//     apps/<name>/app.yantra.json   the full exported document (nodes, layout
//                                   parameters, source site of each node, the
//                                   retained draw command string, provenance)
//     apps/<name>/app.json          the launcher manifest (id, name, icon,
//                                   tint, grants) plus the measured facts
//
//   Nothing here is authored by hand: the node tree, the parameters, the draw
//   commands and every byte count/sha256 come from the shipped module and its
//   files. The four design fields of the manifest (name, icon, tint, grants)
//   are carried over from the existing app.json, because they are a design
//   choice, not a measurement.
//
// WHAT IT IS NOT
//   It is not a decompiler: this is level L1 of the JSON parallel (docs in the
//   private repo), the structured public twin of the app — nodes, wires,
//   parameters, permissions. It does not turn wasm back into Nim, and the JSON
//   is not executable on its own.
//
// USAGE
//   node tools/export-json.mjs                 # every app in apps/*/app.wasm
//   node tools/export-json.mjs calc            # one app (by folder name)
//   node tools/export-json.mjs --check         # exit 1 if a committed export is stale
//   node tools/export-json.mjs --check calc    # one app
//   node tools/export-json.mjs --measure       # measurement only, no writes (JSON on stdout)
//
//   Env: YANTRA_EXPORT_FRAMES (default 30), YANTRA_EXPORT_TIMEOUT_MS (default 120000),
//        YANTRA_EXPORT_DRAW_CHARS (draw preview length, default 4000)
//
// Each app is exported in its own child process, so one slow or crashing module
// cannot take the run down with it.

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APPS_DIR = join(ROOT, 'apps');
const FRAMES = Number(process.env.YANTRA_EXPORT_FRAMES || 30);
const DRAW_CHARS = Number(process.env.YANTRA_EXPORT_DRAW_CHARS || 4000);
const TIMEOUT = Number(process.env.YANTRA_EXPORT_TIMEOUT_MS || 120000);

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const bytes = (p) => statSync(p).size;
const lines = (p) => readFileSync(p, 'utf8').split('\n').length - 1;

// The apps that ship a module. Discovery, not a hand-written list: a folder
// without app.wasm is not an app we can export.
function discover() {
  return readdirSync(APPS_DIR)
    .filter((d) => existsSync(join(APPS_DIR, d, 'app.wasm')))
    .sort();
}

// ---- one app ------------------------------------------------------------

async function exportOne(name) {
  const dir = join(APPS_DIR, name);
  const wasmPath = join(dir, 'app.wasm');
  const nimPath = join(dir, 'app.nim');
  const wasmBytes = readFileSync(wasmPath);

  const { YantraWebRunner, K, P, E } = await import(
    'file://' + join(ROOT, 'web', 'runner', 'runner.js').replace(/\\/g, '/')
  );

  const rev = (enumObj, v) => Object.keys(enumObj).find((k) => enumObj[k] === v) ?? `unknown_${v}`;
  const COLOR_KEYS = /(COLOR|TINT|BG|BACKGROUND|FILL|STROKE|ACCENT)$/;
  const hex = (n) => '#' + (n >>> 0).toString(16).toUpperCase().padStart(6, '0').slice(-6);
  // The guest passes f32s, so 0.8 arrives as 0.800000011920929. Four decimals
  // keeps the document readable without inventing precision that is not there.
  const tidy = (v) => (typeof v === 'number' && !Number.isInteger(v) ? Math.round(v * 1e4) / 1e4 : v);

  // Frames: a canvas app paints inside its tick, so a snapshot taken at
  // instantiation would show an almost empty draw string. We drive the same
  // frame event the engine and the interaction tests drive.
  const runner = new YantraWebRunner({});
  const baseInput = runner.env.y_input;
  runner.env.y_input = (what, arg) => (what === 7 ? 1 / 60 : baseInput(what, arg));

  // Layers: the runner stubs the retained-layer imports by default, so a layer
  // id would be allocated and thrown away. Capture them instead.
  const layers = [];
  runner.env.y_layer_new = () => {
    layers.push({ draws: 0, bytes: 0 });
    return layers.length;
  };
  runner.env.y_layer_draw = (id, ...args) => {
    const l = layers[id - 1];
    if (!l) return;
    l.draws += 1;
    l.bytes += args.reduce((n, a) => n + String(a ?? '').length, 0);
  };

  runner.initSync(wasmBytes);

  const canvas = runner.getNodes().find((n) => n.alive && n.kind === K.CANVAS);
  const tickTarget = canvas ?? runner.getNodes().find((n) => n.alive && n.kind === K.WINDOW);
  let framesStepped = 0;
  if (tickTarget) {
    for (let i = 0; i < FRAMES; i += 1) {
      runner._fire(tickTarget.id, E.FRAME);
      framesStepped += 1;
    }
  }

  const nodes = runner.getNodes().filter((n) => n.alive);
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const key = (id) => `n${id}`;

  // A node's own text, not its children's: MiniElement keeps it in _text.
  const ownText = (n) => {
    const own = n.el?._text;
    if (own) return String(own);
    if (typeof n.props[P.TEXT] === 'string') return n.props[P.TEXT];
    return '';
  };

  const out = {};
  let drawBytesTotal = 0;
  const windowNode = nodes.find((n) => n.kind === K.WINDOW);

  for (const n of nodes) {
    const kind = rev(K, n.kind);
    const params = {};
    for (const [k, v] of Object.entries(n.props)) {
      const pName = rev(P, Number(k));
      if (pName === 'DRAW') continue; // handled below, it is the big one
      if (pName === 'SITE') continue; // promoted to its own field
      if (pName === 'TEXT' && kind === 'WINDOW') continue; // it is the title
      if (COLOR_KEYS.test(pName) && typeof v === 'number' && v >= 0) {
        params[pName] = hex(v);
      } else {
        params[pName] = tidy(v);
      }
    }

    const entry = { kind };
    const site = n.props[P.SITE];
    if (typeof site === 'string') entry.site = site;
    if (Object.keys(params).length) entry.params = params;
    const text = ownText(n);
    if (text) entry.text = text;
    const parent = byId.get(n.parent);
    if (parent) entry.parent = key(parent.id);
    if (n.children?.length) {
      entry.children = n.children.filter((c) => byId.has(c)).map(key);
    }

    // The retained draw command string: the app's own paint programme. For
    // canvas apps this is the pixel-heavy surface, so it is kept (preview +
    // hash + size) rather than dropped.
    const draw = n.props[P.DRAW];
    if (typeof draw === 'string' && draw.length) {
      drawBytesTotal += draw.length;
      entry.draw_bytes = draw.length;
      entry.draw_sha256 = sha256(Buffer.from(draw, 'utf8'));
      entry.draw = draw.length <= DRAW_CHARS ? draw : draw.slice(0, DRAW_CHARS) + '…';
      if (draw.length > DRAW_CHARS) entry.draw_truncated = true;
    }

    out[key(n.id)] = entry;
  }

  const title = windowNode?.props?.[P.TEXT];
  const doc = {
    $yantra: '2026.11',
    app: `y:@yantra/${name}`,
    name: (readManifest(dir, name).name) || name,
    exported: {
      by: 'tools/export-json.mjs',
      from: `apps/${name}/app.wasm, instantiated and stepped ${framesStepped} frame(s)`,
      runner: 'web/runner/runner.js',
      protocol: 'v2',
      frames_stepped: framesStepped,
      note: 'L1 structured twin: nodes, parameters and the retained draw commands, read from the running module. Not executable on its own, and not restorable to the Nim source.',
    },
    window: {
      title: typeof title === 'string' && title ? title : name,
      width: windowNode?.props?.[P.WIDTH] ?? null,
      height: windowNode?.props?.[P.HEIGHT] ?? null,
      ...(typeof windowNode?.props?.[P.COLOR] === 'number'
        ? { bg: hex(windowNode.props[P.COLOR]) }
        : {}),
    },
    stats: {
      nodes: nodes.length,
      layers: layers.length,
      layer_draw_calls: layers.reduce((n, l) => n + l.draws, 0),
      draw_command_bytes: drawBytesTotal,
    },
    nodes: out,
    provenance: {
      source: existsSync(nimPath)
        ? { path: `apps/${name}/app.nim`, lines: lines(nimPath), bytes: bytes(nimPath), sha256: sha256(readFileSync(nimPath)) }
        : null,
      module: { path: `apps/${name}/app.wasm`, bytes: wasmBytes.length, sha256: sha256(wasmBytes) },
      build: `./tools/build-wasm.sh apps/${name}/app.nim apps/${name}/app.wasm --release`,
    },
    verify: {
      command: `node tools/verify-wasm.mjs apps/${name}`,
      proves: 'the module instantiates with no keys and no GPU, and builds a live UI tree',
      does_not_prove: 'pixel equality against any reference render',
    },
  };

  return { doc, size: wasmBytes.length, nodes: nodes.length };
}

// ---- manifest ------------------------------------------------------------

// The manifest's design fields (name, icon, tint, grants) are authored; keep
// them. Everything else in the file is measured and rewritten.
function readManifest(dir, name) {
  const p = join(dir, 'app.json');
  const fallback = { id: name, name, icon: name.slice(0, 1).toUpperCase(), tint: '#8E8E93', grants: [] };
  if (!existsSync(p)) return fallback;
  try {
    const j = JSON.parse(readFileSync(p, 'utf8'));
    return { ...fallback, ...j };
  } catch {
    return fallback;
  }
}

function writeManifest(name, doc, design) {
  const dir = join(APPS_DIR, name);
  const manifest = {
    id: design.id || name,
    name: design.name || name,
    icon: design.icon ?? name.slice(0, 1).toUpperCase(),
    tint: design.tint ?? '#8E8E93',
    grants: Array.isArray(design.grants) ? design.grants : [],
    window: doc.window,
    module: doc.provenance.module,
    source: doc.provenance.source,
    nodes: doc.stats.nodes,
    document: 'app.yantra.json',
    generated: 'tools/export-json.mjs',
  };
  writeFileSync(join(dir, 'app.json'), JSON.stringify(manifest, null, 2) + '\n');
}

// ---- driver --------------------------------------------------------------

function measureOnly() {
  const rows = [];
  for (const name of discover()) {
    const dir = join(APPS_DIR, name);
    const docPath = join(dir, 'app.yantra.json');
    const doc = existsSync(docPath) ? JSON.parse(readFileSync(docPath, 'utf8')) : null;
    rows.push({
      app: name,
      wasm_bytes: bytes(join(dir, 'app.wasm')),
      wasm_sha256: sha256(readFileSync(join(dir, 'app.wasm'))),
      nim_lines: existsSync(join(dir, 'app.nim')) ? lines(join(dir, 'app.nim')) : null,
      nodes: doc?.stats?.nodes ?? null,
      layers: doc?.stats?.layers ?? null,
      draw_bytes: doc?.stats?.draw_command_bytes ?? null,
      exported: doc !== null,
    });
  }
  return rows;
}

function checkOne(name) {
  const dir = join(APPS_DIR, name);
  const docPath = join(dir, 'app.yantra.json');
  if (!existsSync(docPath)) return `${name}: app.yantra.json is missing`;
  const committed = JSON.parse(readFileSync(docPath, 'utf8'));
  // Cheap drift check: the source and module hashes must still match.
  const nimPath = join(dir, 'app.nim');
  const nimSha = existsSync(nimPath) ? sha256(readFileSync(nimPath)) : null;
  const wasmSha = sha256(readFileSync(join(dir, 'app.wasm')));
  if (committed.provenance?.module?.sha256 !== wasmSha) return `${name}: app.wasm changed since the export`;
  if (committed.provenance?.source && committed.provenance.source.sha256 !== nimSha) {
    return `${name}: app.nim changed since the export`;
  }
  return null;
}

async function main() {
  const args = process.argv.slice(2);
  const flags = args.filter((a) => a.startsWith('--'));
  const named = args.filter((a) => !a.startsWith('--'));

  if (flags.includes('--measure')) {
    process.stdout.write(JSON.stringify(measureOnly(), null, 2) + '\n');
    return;
  }

  if (flags.includes('--check')) {
    const targets = named.length ? named : discover();
    const bad = [];
    for (const name of targets) {
      const problem = checkOne(name);
      if (problem) bad.push(problem);
    }
    if (bad.length) {
      console.log('export-json: STALE');
      for (const b of bad) console.log('  ' + b);
      process.exit(1);
    }
    console.log(`export-json: ${targets.length} export(s) match their source and module`);
    return;
  }

  // Child mode: one app, write its files.
  if (flags.includes('--child')) {
    const name = named[0];
    const dir = join(APPS_DIR, name);
    const design = readManifest(dir, name);
    const { doc } = await exportOne(name);
    writeFileSync(join(dir, 'app.yantra.json'), JSON.stringify(doc, null, 2) + '\n');
    writeManifest(name, doc, design);
    console.log(
      `${name.padEnd(11)} ${String(doc.stats.nodes).padStart(4)} nodes  ` +
        `${String(doc.stats.layers).padStart(3)} layers  ` +
        `${String(doc.stats.draw_command_bytes).padStart(7)} draw B  -> app.yantra.json`
    );
    // The runner keeps a timer alive (the web page's animation loop), so a
    // child would sit there after finishing and the parent would time it out.
    process.exit(0);
  }

  // Parent mode: run each app in its own process so a hang costs one app.
  const targets = named.length ? named : discover();
  let failed = 0;
  for (const name of targets) {
    try {
      const out = execFileSync(process.execPath, [fileURLToPath(import.meta.url), '--child', name], {
        cwd: ROOT,
        timeout: TIMEOUT,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      process.stdout.write(out);
    } catch (err) {
      failed += 1;
      const detail = (err.stderr || err.message || '').toString().split('\n').slice(0, 3).join(' | ');
      // A module that traps cannot be exported. Say so in its place rather than
      // leaving yesterday's document standing beside today's binary.
      const dir = join(APPS_DIR, name);
      const wasmPath = join(dir, 'app.wasm');
      const nimPath = join(dir, 'app.nim');
      const design = readManifest(dir, name);
      const doc = {
        $yantra: '2026.11',
        app: `y:@yantra/${name}`,
        name: design.name || name,
        export_failed: detail || 'the module did not run',
        nodes: {},
        provenance: {
          source: existsSync(nimPath)
            ? { path: `apps/${name}/app.nim`, lines: lines(nimPath), bytes: bytes(nimPath), sha256: sha256(readFileSync(nimPath)) }
            : null,
          module: { path: `apps/${name}/app.wasm`, bytes: bytes(wasmPath), sha256: sha256(readFileSync(wasmPath)) },
        },
        note: 'This module traps in the host, so nothing was read from it. The document records the module it failed on, not a tree.',
      };
      writeFileSync(join(dir, 'app.yantra.json'), JSON.stringify(doc, null, 2) + '\n');
      console.log(`${name.padEnd(11)} FAILED — ${detail}`);
    }
  }
  console.log(`export-json: ${targets.length - failed}/${targets.length} apps exported`);
  if (failed) process.exit(1);
}

await main();
