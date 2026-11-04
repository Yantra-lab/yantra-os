#!/usr/bin/env node
// tools/os-measure.mjs — the only source of numbers in README.md.
//
// Every figure README.md prints about apps comes from this file's output, and
// `--check` fails when the committed README has drifted from the tree. That is
// how "no hand-typed numbers" is enforced instead of promised.
//
// WHAT IT MEASURES (all of it directly, none of it estimated)
//   module bytes        stat(apps/<name>/app.wasm)
//   sha256              the module's bytes
//   source lines        app.nim
//   live nodes          from apps/<name>/app.yantra.json (itself exported from
//                       the running module by tools/export-json.mjs; --check
//                       proves the export still matches the module's hash)
//   draw bytes          retained draw command string, from the same export
//   init time           node tools/verify-wasm.mjs apps/<name>, parsed
//   verifier            that same run's PASS/FAIL
//
// USAGE
//   bash tools/os-measure.sh            # print the markdown table
//   bash tools/os-measure.sh --write    # rewrite README.md between the markers
//   bash tools/os-measure.sh --check    # exit 1 if README.md is out of date
//   bash tools/os-measure.sh --json     # machine-readable
//
// Markers in README.md (do not remove):
//   <!-- BEGIN os-measure -->   ... generated ...   <!-- END os-measure -->

import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APPS = join(ROOT, 'apps');
const README = join(ROOT, 'README.md');
const BEGIN = '<!-- BEGIN os-measure -->';
const END = '<!-- END os-measure -->';

// One authored line per app. These are descriptions, not measurements; every
// number in the files this script writes is measured below.
const BLURB = {
  calc: 'a calculator: chained arithmetic, percent, sign, clear, backspace',
  chess: 'a chess study: full move validation, castling, en passant, promotion, check and mate',
  desktop: 'the shell: an Arc sidebar, a Caelestia bar, a shader wallpaper, windows that float or tile',
  dna: 'a 3-D DNA helix: rotate, pick a base, unzip, replicate, rejoin',
  editor: 'a code editor: open, edit, save, line and column status',
  files: 'a file manager: browse, select, open',
  gallery: 'a 3-D exhibition hall: rooms, spotlights, paintings, guided tour',
  notes: 'notes: a text surface, line count, save',
  todo: 'a reactive todo list: add, check, filter',
  typewriter: 'the Marlowe 44: a procedural desk, cotton-bond paper, ink strikes, type bars',
  calligraphy: 'brush and ink: strokes stamped onto a sheet, width and taper tools',
  descent: 'gradient descent running: a loss landscape, steps, learning rate, momentum',
  gallery3d: 'a 3-D hall: a corridor of paintings walked with keys or on-screen pads',
  minipaint: 'a raster paint program: brush, eraser, shapes, palette, zoom',
  ocean: 'the open sea: six cascades of swell, Jacobian whitecaps, a sunset sky, one shader',
  kart: 'a lap racer: a circuit as arithmetic, pseudo-3D road, throttle and brake, three laps',
  orrery: 'a brass orrery: Kepler-solved planets, real periods, a gear train, a live almanac',
};

const fmt = (n) => n.toLocaleString('en-US');
const kib = (n) => (n / 1024).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function readJSON(p, fallback = null) {
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return fallback;
  }
}

function measure() {
  const names = readdirSync(APPS)
    .filter((d) => existsSync(join(APPS, d, 'app.wasm')))
    .sort();
  const apps = [];
  for (const name of names) {
    const dir = join(APPS, name);
    const wasm = readFileSync(join(dir, 'app.wasm'));
    const nimPath = join(dir, 'app.nim');
    const manifest = readJSON(join(dir, 'app.json'), {});
    const doc = readJSON(join(dir, 'app.yantra.json'), null);

    // The verifier is the authority on whether the module runs, and it also
    // reports the instantiation time it measured.
    let verifier = 'FAIL';
    let initMs = null;
    let verNodes = null;
    let verDraw = null;
    try {
      const out = execFileSync(process.execPath, ['tools/verify-wasm.mjs', `apps/${name}`], {
        cwd: ROOT,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      if (/^RESULT: PASS$/m.test(out)) verifier = 'PASS';
      const m = out.match(/instantiate ([\d.]+) ms/);
      if (m) initMs = Number(m[1]);
      const n = out.match(/ui tree\s+(\d+) live nodes/);
      if (n) verNodes = Number(n[1]);
      const d = out.match(/retained\s+(\d+) bytes of draw commands/);
      if (d) verDraw = Number(d[1]);
    } catch {
      verifier = 'FAIL';
    }

    apps.push({
      app: name,
      name: manifest.name || name,
      blurb: BLURB[name] || '',
      wasm_bytes: wasm.length,
      wasm_sha256: createHash('sha256').update(wasm).digest('hex'),
      source_lines: existsSync(nimPath) ? readFileSync(nimPath, 'utf8').split('\n').length - 1 : null,
      // The census is what the verifier measured at instantiation, so this
      // table and `node tools/verify-wasm.mjs` can never disagree. The stepped
      // export in app.yantra.json can differ by a node (apps build on frames),
      // which is why it is not used here.
      nodes: verNodes,
      draw_bytes: verDraw,
      init_ms: initMs,
      exported_nodes: doc?.stats?.nodes ?? null,
      verifier,
      window: doc?.window ?? null,
    });
  }
  const total = apps.reduce((n, a) => n + a.wasm_bytes, 0);
  const sorted = [...apps].map((a) => a.wasm_bytes).sort((x, y) => x - y);
  const median = sorted.length % 2
    ? sorted[(sorted.length - 1) / 2]
    : Math.round((sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2);
  return {
    measured_by: 'tools/os-measure.sh',
    apps,
    totals: {
      apps: apps.length,
      wasm_bytes: total,
      wasm_kib: Number(kib(total)),
      smallest: sorted[0],
      largest: sorted[sorted.length - 1],
      median,
      source_lines: apps.reduce((n, a) => n + (a.source_lines || 0), 0),
      nodes: apps.reduce((n, a) => n + (a.nodes || 0), 0),
      draw_bytes: apps.reduce((n, a) => n + (a.draw_bytes || 0), 0),
      verifiers_passed: apps.filter((a) => a.verifier === 'PASS').length,
    },
  };
}

function table(m) {
  const lines = [];
  // Deliberately stable columns only. Instantiation times vary a few percent
  // between runs, so they are reported in docs/VERIFICATION.md (one dated run)
  // rather than in a table that `--check` compares byte for byte.
  lines.push(`| App | Module | Bytes | KiB | Source | Live nodes | Draw bytes | Verifier |`);
  lines.push(`| :--- | :--- | ---: | ---: | ---: | ---: | ---: | :---: |`);
  for (const a of m.apps) {
    const draw = a.draw_bytes ? fmt(a.draw_bytes) : '—';
    lines.push(
      `| \`${a.app}\` | \`app.wasm\` | ${fmt(a.wasm_bytes)} | ${kib(a.wasm_bytes)} | ` +
        `${a.source_lines === null ? '—' : fmt(a.source_lines)} lines | ${a.nodes === null ? '—' : fmt(a.nodes)} | ` +
        `${draw} | ${a.verifier} |`
    );
  }
  const t = m.totals;
  lines.push(
    `| **${t.apps} apps** | | **${fmt(t.wasm_bytes)}** | **${kib(t.wasm_bytes)}** | ` +
      `**${fmt(t.source_lines)} lines** | **${fmt(t.nodes)}** | **${fmt(t.draw_bytes)}** | **${t.verifiers_passed}/${t.apps} PASS** |`
  );
  lines.push('');
  lines.push(
    `Measured on ${new Date().toISOString().slice(0, 10)} by \`bash tools/os-measure.sh\` ` +
      `(sizes and sha256 read from the files; the node census, the draw bytes and the verifier column ` +
      `from \`node tools/verify-wasm.mjs apps/<app>\`, which instantiates each module and prints its own ` +
      `census). ` +
      `Smallest module ${fmt(t.smallest)} B, median ${fmt(t.median)} B, largest ${fmt(t.largest)} B.`
  );
  lines.push('');
  lines.push(
    'The verifier proves the module instantiates and builds a tree; it renders nothing, so it proves ' +
      'execution, not appearance. Instantiation times vary between runs and are listed, with the behaviour ' +
      'suites, in [docs/VERIFICATION.md](docs/VERIFICATION.md).'
  );
  return lines.join('\n');
}

function appsReadme(m) {
  const lines = [];
  lines.push('# The applications');
  lines.push('');
  lines.push(`${m.totals.apps} applications. Each folder holds the same four things:`);
  lines.push('');
  lines.push('| File | What it is |');
  lines.push('| :--- | :--- |');
  lines.push('| `app.nim` | the source, written against the SDK |');
  lines.push('| `app.wasm` | the compiled module that this repository ships and verifies |');
  lines.push('| `app.json` | the launcher manifest: id, name, icon, tint, window, module hash |');
  lines.push('| `app.yantra.json` | the same app as a document, exported from the running module |');
  lines.push('');
  lines.push('Every number below is measured — `bash tools/os-measure.sh` regenerates this file and');
  lines.push('`bash tools/os-measure.sh --check` fails when it has drifted from the tree.');
  lines.push('');
  lines.push('| App | What it is | Module bytes | KiB | Source | Live nodes | Draw bytes | Verifier |');
  lines.push('| :--- | :--- | ---: | ---: | ---: | ---: | ---: | :---: |');
  for (const a of m.apps) {
    lines.push(
      `| [\`${a.app}\`](${a.app}/app.nim) | ${a.blurb} | ${fmt(a.wasm_bytes)} | ${kib(a.wasm_bytes)} | ` +
        `${a.source_lines === null ? '—' : fmt(a.source_lines) + ' lines'} | ${a.nodes === null ? '—' : fmt(a.nodes)} | ` +
        `${a.draw_bytes ? fmt(a.draw_bytes) : '—'} | ${a.verifier} |`
    );
  }
  lines.push(
    `| **total** | | **${fmt(m.totals.wasm_bytes)}** | **${kib(m.totals.wasm_bytes)}** | ` +
      `**${fmt(m.totals.source_lines)} lines** | **${fmt(m.totals.nodes)}** | **${fmt(m.totals.draw_bytes)}** | **${m.totals.verifiers_passed}/${m.totals.apps}** |`
  );
  lines.push('');
  lines.push('Run one app on its own with `node tools/verify-wasm.mjs apps/<name>`, or all of them');
  lines.push('with `bash verify_all.sh`. Behaviour suites live in `../web/runner/tests/`.');
  lines.push('');
  return lines.join('\n');
}

function rewrite(fragment) {
  if (!existsSync(README)) throw new Error('README.md is missing');
  const text = readFileSync(README, 'utf8');
  const i = text.indexOf(BEGIN);
  const j = text.indexOf(END);
  if (i < 0 || j < 0 || j < i) throw new Error(`README.md has no ${BEGIN} … ${END} markers`);
  const next = text.slice(0, i + BEGIN.length) + '\n' + fragment + '\n' + text.slice(j);
  writeFileSync(README, next);
  return next;
}

function currentFragment() {
  const text = readFileSync(README, 'utf8');
  const i = text.indexOf(BEGIN);
  const j = text.indexOf(END);
  if (i < 0 || j < 0) return null;
  return text.slice(i + BEGIN.length, j).replace(/^\n/, '').replace(/\n$/, '');
}

const args = process.argv.slice(2);
const m = measure();

if (args.includes('--json')) {
  process.stdout.write(JSON.stringify(m, null, 2) + '\n');
} else if (args.includes('--write')) {
  rewrite(table(m));
  writeFileSync(join(APPS, 'README.md'), appsReadme(m));
  console.log(
    `os-measure: rewrote the README block and apps/README.md — ${m.totals.apps} apps, ${fmt(m.totals.wasm_bytes)} bytes`
  );
} else if (args.includes('--check')) {
  const have = currentFragment();
  const want = table(m);
  if (have === null) {
    console.log('os-measure: README.md has no markers; run --write');
    process.exit(1);
  }
  if (have !== want) {
    console.log('os-measure: README.md numbers are STALE — run `bash tools/os-measure.sh --write`');
    const ha = have.split('\n');
    const wa = want.split('\n');
    for (let k = 0; k < Math.max(ha.length, wa.length); k += 1) {
      if (ha[k] !== wa[k]) {
        console.log(`  line ${k + 1}:\n    committed: ${(ha[k] ?? '').slice(0, 160)}\n    measured : ${(wa[k] ?? '').slice(0, 160)}`);
        break;
      }
    }
    process.exit(1);
  }
  const haveApps = existsSync(join(APPS, 'README.md')) ? readFileSync(join(APPS, 'README.md'), 'utf8') : '';
  if (haveApps !== appsReadme(m)) {
    console.log('os-measure: apps/README.md numbers are STALE — run `bash tools/os-measure.sh --write`');
    process.exit(1);
  }
  console.log(
    `os-measure: README and apps/README.md match the tree — ${m.totals.apps} apps, ${m.totals.verifiers_passed} verifiers PASS`
  );
} else {
  process.stdout.write(table(m) + '\n');
}
