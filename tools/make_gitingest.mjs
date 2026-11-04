import fs from 'fs';
import path from 'path';

const repoRoot = 'C:\\Users\\Sanskar\\DEV\\yantra-os';

const commonFiles = [
  'docs/spec/core.md',
  'docs/apis.md',
  'skills/yantra/SKILL.md',
  'skills/yantra/reference/02-language-core.md',
  'skills/yantra/reference/03-node-and-prop-reference.md',
  'skills/yantra/reference/09-canvas-and-draw.md',
  'skills/yantra/reference/11-input-pointer-and-keys.md',
  'skills/web-to-yantra/DOM-EVENTS-TO-SDL3.md',
  'skills/web-to-yantra/HTML5-CANVAS-TO-SKIA.md',
  'sdk/yantra.nim',
  'sdk/ui/dsl.nim',
  'sdk/ui/paint.nim',
  'sdk/core/signals.nim',
  'sdk/panicoverride.nim'
];

const apps = [
  {
    name: 'typewriter',
    title: 'Marlowe 44 Typewriter',
    files: [
      'apps/typewriter/029-typewriter-letters.txt',
      'apps/typewriter/029-typewriter-letters.html',
      'apps/typewriter/app.nim',
      'apps/typewriter/TASK.md'
    ]
  },
  {
    name: 'chess',
    title: "Grandmaster's Study Chess",
    files: [
      'apps/chess/070-chess-study.txt',
      'apps/chess/070-chess-study.html',
      'apps/chess/app.nim',
      'apps/chess/engine.nim',
      'apps/chess/play.nim'
    ]
  },
  {
    name: 'dna',
    title: 'Helix 3D DNA Visualizer',
    files: [
      'apps/dna/052-dna-helix.txt',
      'apps/dna/052-dna-helix.html',
      'apps/dna/app.nim',
      'apps/dna/play.nim'
    ]
  },
  {
    name: 'gallery',
    title: 'Galerie Nocturne 3D Virtual Gallery',
    files: [
      'apps/gallery/039-virtual-gallery.txt',
      'apps/gallery/039-virtual-gallery.html',
      'apps/gallery/app.nim'
    ]
  }
];

function buildIngest(title, fileList, outputPath) {
  let out = '';
  out += `================================================================\n`;
  out += `YANTRA OS REPOSITORY INGEST: ${title}\n`;
  out += `Purpose: 1:1 Interactive Porting from HTML Reference to Native Nim WASM\n`;
  out += `Generated: ${new Date().toISOString()}\n`;
  out += `================================================================\n\n`;

  out += `DIRECTORY SUMMARY / FILE LIST:\n`;
  for (const rel of fileList) {
    const full = path.join(repoRoot, rel);
    if (fs.existsSync(full)) {
      const sz = fs.statSync(full).size;
      out += `  - ${rel} (${(sz / 1024).toFixed(1)} KB)\n`;
    } else {
      out += `  - ${rel} [MISSING]\n`;
    }
  }
  out += `\n`;

  for (const rel of fileList) {
    const full = path.join(repoRoot, rel);
    if (!fs.existsSync(full)) continue;
    const content = fs.readFileSync(full, 'utf8');

    out += `================================================================\n`;
    out += `FILE: ${rel}\n`;
    out += `================================================================\n`;
    out += content;
    out += `\n\n`;
  }

  fs.writeFileSync(outputPath, out, 'utf8');
  const totalSz = fs.statSync(outputPath).size;
  console.log(`Wrote ${outputPath} (${(totalSz / 1024).toFixed(1)} KB)`);
}

// 1. Build individual per-app ingests
for (const app of apps) {
  const appFileList = [...commonFiles, ...app.files];
  const outPath = path.join(repoRoot, `gitingest_${app.name}.txt`);
  buildIngest(`App ${app.title}`, appFileList, outPath);
}

// 2. Build master ingest with all apps
const allFiles = [...commonFiles];
for (const app of apps) {
  for (const f of app.files) {
    if (!allFiles.includes(f)) allFiles.push(f);
  }
}
const masterOut = path.join(repoRoot, 'gitingest_all_apps.txt');
buildIngest('All 4 Flagship Apps & Core SDK', allFiles, masterOut);

// 3. Build delta ingest: everything in all apps EXCEPT whatever is in typewriter ingest
const twFiles = new Set([...commonFiles, ...apps.find(a => a.name === 'typewriter').files]);
const nonTwFiles = [];
for (const app of apps) {
  if (app.name === 'typewriter') continue;
  for (const f of app.files) {
    if (!twFiles.has(f) && !nonTwFiles.includes(f)) {
      nonTwFiles.push(f);
    }
  }
}
const deltaOut = path.join(repoRoot, 'gitingest_except_typewriter.txt');
buildIngest('All Apps Except Typewriter (Non-Duplicate Delta for Agent)', nonTwFiles, deltaOut);

// 4. Build Skia, Host Engine, Desktop Shell, Window Manager, Language Core & Flagship Apps (no spec docs)
const fullSystemFiles = [
  // Flagship Apps & Original Opus HTML Reference Files Being Emulated
  'apps/typewriter/029-typewriter-letters.txt',
  'apps/typewriter/029-typewriter-letters.html',
  'apps/typewriter/app.nim',
  'apps/typewriter/port-notes.md',

  'apps/chess/070-chess-study.txt',
  'apps/chess/070-chess-study.html',
  'apps/chess/app.nim',
  'apps/chess/engine.nim',
  'apps/chess/play.nim',
  'apps/chess/port-notes.md',

  'apps/dna/052-dna-helix.txt',
  'apps/dna/052-dna-helix.html',
  'apps/dna/app.nim',
  'apps/dna/play.nim',
  'apps/dna/port-notes.md',

  'apps/gallery/039-virtual-gallery.txt',
  'apps/gallery/039-virtual-gallery.html',
  'apps/gallery/app.nim',
  'apps/gallery/port-notes.md',

  // Real Skia & Host Engine
  'render/native/engine.nim',
  'host/host.nim',
  'render/native/yantra_run.nim',
  'libs/nimskia/src/nimskia.nim',
  'libs/nimskia/src/skia_shim.cpp',
  'protocol/wire.nim',

  // Desktop Shell & Window Manager (Caelestia port in progress)
  'apps/desktop/app.nim',
  'apps/desktop/tiling.nim',
  'apps/desktop/catalog.nim',
  'apps/desktop/config.nim',
  'apps/desktop/state.nim',
  'apps/desktop/ui.nim',
  'apps/desktop/settings.nim',
  // Studio IDE + File Manager (bundle set, v1-DSL port in progress)
  'apps/editor/app.nim',
  'apps/files/app.nim',

  // Language Core Implementation in Code (NO language spec docs)
  'sdk/yantra.nim',
  'sdk/ui/dsl.nim',
  'sdk/ui/paint.nim',
  'sdk/core/signals.nim',
  'sdk/core/runtime.nim',
  'sdk/core/persist.nim',
  'sdk/core/ai.nim',
  'sdk/core/sysinfo.nim',
  'sdk/panicoverride.nim'
];

const masterSysOut = path.join(repoRoot, 'gitingest_master.txt');
buildIngest('Master System Ingest: Flagship Apps, HTML References, Skia Engine, Host & Desktop Window Manager', fullSystemFiles, masterSysOut);

// Keep gitingest_engine_host_desktop.txt in sync as requested
const engineOut = path.join(repoRoot, 'gitingest_engine_host_desktop.txt');
fs.copyFileSync(masterSysOut, engineOut);
console.log(`Synced ${engineOut}`);

// 5. Desktop Store + Hot Reload bundle for Argon (reinvent desktop + Monaco-like editor)
const desktopStoreFiles = [
  // Store shell (Caelestia port of agent/claude/DESK in progress)
  'apps/desktop/app.nim',
  'apps/desktop/app.json',
  'apps/desktop/tiling.nim',
  'apps/desktop/catalog.nim',
  'apps/desktop/config.nim',
  'apps/desktop/state.nim',
  'apps/desktop/ui.nim',
  'apps/desktop/settings.nim',
  'apps/editor/app.nim',
  'apps/editor/app.json',
  'apps/files/app.nim',
  'apps/files/app.json',
  // Hot reload (edit every app in real time)
  'render/native/devwatch.nim',
  'render/native/liveedit.nim',
  'render/native/yantra_run.nim',
  // Build + run (Windows + Linux real app, no lame CLI)
  'tools/build-wasm.sh',
  'tools/build-wasm.bat',
  'tools/apps-index.sh',
  'tools/verify-wasm.mjs',
  'run.sh',
  'run_yantra.bat',
  'run_yantra.sh',
  // Engine + host contracts
  'render/native/engine.nim',
  'host/host.nim',
  'libs/nimskia/src/nimskia.nim',
  'libs/nimskia/src/skia_shim.cpp',
  'protocol/wire.nim',
  // Language + UI contracts
  'sdk/yantra.nim',
  'sdk/ui/dsl.nim',
  'sdk/ui/paint.nim',
  'sdk/core/signals.nim',
  'sdk/core/runtime.nim',
  'sdk/core/persist.nim',
  'sdk/core/ai.nim',
  'sdk/core/sysinfo.nim',
  'sdk/panicoverride.nim',
  // Store inventory (every app Argon must support)
  'apps/typewriter/app.json',
  'apps/chess/app.json',
  'apps/dna/app.json',
  'apps/gallery/app.json',
  'apps/calc/app.json',
  'apps/notes/app.json',
  'apps/todo/app.json',
];
const desktopOut = path.join(repoRoot, 'gitingest_desktop_store.txt');
buildIngest('Desktop Store + Hot Reload: shell, tiling, catalog, devwatch/liveedit, yantra_run, build/run, engine/host, SDK, app manifests', desktopStoreFiles, desktopOut);
