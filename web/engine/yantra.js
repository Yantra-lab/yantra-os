// The Yantra engine in a browser page. build/engine.js is engine.nim built with emscripten; this
// file gives it a canvas, input and the app. Apps are compiled here first (browsers refuse to
// compile big modules synchronously), and their imports are stubs that call back into the engine:
// the arguments go through a small buffer laid out as the host's WasmVal (16 bytes: kind at 0,
// value at 8), exactly what the desktop host receives from wasmtime.

const SDL = {Backspace: 8, Tab: 9, Enter: 13, Escape: 27, Delete: 127, ArrowRight: 0x4000004f,
  ArrowLeft: 0x40000050, ArrowDown: 0x40000051, ArrowUp: 0x40000052, Home: 0x4000004a,
  PageUp: 0x4000004b, End: 0x4000004d, PageDown: 0x4000004e};
const CURSORS = ['default', 'pointer', 'text'];

export async function runYantra(canvas, appUrl) {
  const Module = {canvas, ywApps: [], ywKeys: {}, locateFile: p => new URL('build/' + p, import.meta.url).href};
  // 1. the app: compiled and instantiated before the engine asks for it
  const bytes = await (await fetch(appUrl)).arrayBuffer();
  const mod = await WebAssembly.compile(bytes);
  const rec = {imports: WebAssembly.Module.imports(mod).filter(i => i.kind === 'function')
                 .map(i => ({name: i.name, slot: -1, nres: 0}))};
  const env = {};
  let scratch = 0;
  rec.imports.forEach((imp, i) => {
    env[imp.name] = (...args) => {
      if (imp.slot < 0) throw new Error('import ' + imp.name + ' was not bound');
      if (!scratch) scratch = Module._malloc(16 * 16);
      const res = scratch + 16 * 8;
      for (let k = 0; k < args.length; k++) {
        const p = scratch + 16 * k;
        const t = (imp.fmask >> k) & 1 ? 2 : 0;           // the declared kind, not the value's look
        Module.HEAPU8[p] = t;
        if (t === 2) Module.HEAPF32[(p + 8) >> 2] = args[k]; else Module.HEAP32[(p + 8) >> 2] = args[k];
      }
      Module._yw_invoke(imp.slot, scratch, args.length, res, imp.nres);
      if (imp.nres === 0) return;
      return Module.HEAPU8[res] === 2 ? Module.HEAPF32[(res + 8) >> 2] : Module.HEAP32[(res + 8) >> 2];
    };
  });
  rec.inst = await WebAssembly.instantiate(mod, {env});
  const key = '/apps/' + appUrl.split('/').pop();
  Module.ywKeys[key] = rec;
  Module.ywTake = k => {
    const r = Module.ywKeys[k];
    if (!r) return -1;
    delete Module.ywKeys[k];
    Module.ywApps.push(r);
    return Module.ywApps.length - 1;
  };
  // 2. drawing
  const ctx = canvas.getContext('2d');
  let img = null;
  Module.ywPresent = (px, w, h) => {
    if (!img || img.width !== w || img.height !== h) img = ctx.createImageData(w, h);
    img.data.set(Module.HEAPU8.subarray(px, px + w * h * 4));   // Skia's wasm N32 is already RGBA
    ctx.putImageData(img, 0, 0);
  };
  Module.ywCursor = k => { canvas.style.cursor = CURSORS[k] || 'default'; };

  // 3. the engine
  const createEngine = (await import('./build/engine.js?' + Date.now())).default;
  await createEngine(Module);
  const size = () => {
    const r = canvas.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(r.width * dpr));
    canvas.height = Math.max(1, Math.round(r.height * dpr));
    return [Math.round(r.width), Math.round(r.height), dpr];
  };
  const [w, h, dpr] = size();
  const cstr = s => { const n = Module.lengthBytesUTF8(s) + 1, p = Module._malloc(n); Module.stringToUTF8(s, p, n); return p; };
  const path = cstr(key);
  const t0 = performance.now();
  if (!Module._yw_start(path, w, h, dpr)) console.warn('yantra: the app crashed while starting');
  console.log('yantra: engine + app started in ' + (performance.now() - t0).toFixed(1) + ' ms');
  const titleBuf = Module._malloc(256);
  Module._yw_title(titleBuf, 256);
  document.title = Module.UTF8ToString(titleBuf) || document.title;

  new ResizeObserver(() => { const [w, h, d] = size(); Module._yw_resize(w, h, d); }).observe(canvas);
  const pos = ev => { const r = canvas.getBoundingClientRect(); return [ev.clientX - r.left, ev.clientY - r.top]; };
  canvas.addEventListener('pointermove', ev => Module._yw_pointer(0, ...pos(ev)));
  canvas.addEventListener('pointerdown', ev => { if (ev.button === 0) { canvas.focus(); Module._yw_pointer(1, ...pos(ev)); } });
  // touch: a finger that moves more than a few pixels scrolls instead of pressing (phones)
  let touch = null;
  canvas.style.touchAction = 'none';
  canvas.addEventListener('pointerdown', ev => { if (ev.pointerType === 'touch') touch = {y: ev.clientY, moved: false}; });
  canvas.addEventListener('pointermove', ev => {
    if (!touch || ev.pointerType !== 'touch') return;
    const dy = ev.clientY - touch.y;
    if (!touch.moved && Math.abs(dy) < 8) return;
    if (!touch.moved) { touch.moved = true; Module._yw_pointer(2, -1, -1); }   // let go of the press, off every node
    Module._yw_pointer(0, ...pos(ev));
    Module._yw_wheel(dy / 40);
    touch.y = ev.clientY;
  });
  canvas.addEventListener('pointerup', ev => {
    const dragged = touch && touch.moved; touch = null;
    if (ev.button === 0 && !dragged) Module._yw_pointer(2, ...pos(ev));
  });
  canvas.addEventListener('wheel', ev => { ev.preventDefault(); Module._yw_pointer(0, ...pos(ev)); Module._yw_wheel(-ev.deltaY / 40); }, {passive: false});
  // the keyboard goes to a hidden textarea over the canvas: typed text, IME composition, phone
  // keyboards and paste all arrive as input events there; editing keys go to the engine as keys
  const kb = document.createElement('textarea');
  kb.setAttribute('autocapitalize', 'off'); kb.setAttribute('autocomplete', 'off'); kb.spellcheck = false;
  kb.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;opacity:0;border:0;padding:0;resize:none';
  document.body.appendChild(kb);
  canvas.addEventListener('pointerup', () => { if (Module._yw_focused()) kb.focus({preventScroll: true}); });
  const text = s => { const p = cstr(s); Module._yw_text(p); Module._free(p); };
  kb.addEventListener('input', ev => {
    if (ev.isComposing) return;
    if (kb.value) text(kb.value);
    kb.value = '';
  });
  kb.addEventListener('compositionend', () => { if (kb.value) text(kb.value); kb.value = ''; });
  const onKey = ev => {
    const mods = (ev.shiftKey ? 1 : 0) | (ev.ctrlKey ? 0x40 : 0) | (ev.altKey ? 0x100 : 0) | (ev.metaKey ? 0x400 : 0);
    if (ev.isComposing) return;
    if (ev.key in SDL) { Module._yw_key(SDL[ev.key], mods); ev.preventDefault(); return; }
    if (ev.key.length === 1 && (ev.ctrlKey || ev.metaKey)) {
      const k = ev.key.toLowerCase();
      if (k === 'v') return;                               // the paste event brings the text
      Module._yw_key(k.charCodeAt(0), mods); ev.preventDefault();
    }
  };
  kb.addEventListener('keydown', onKey);
  canvas.tabIndex = 0;
  canvas.addEventListener('keydown', ev => { onKey(ev); if (ev.key.length === 1 && !ev.ctrlKey && !ev.metaKey) { text(ev.key); ev.preventDefault(); } });
  kb.addEventListener('paste', ev => { ev.preventDefault(); Module.ywClip = ev.clipboardData.getData('text'); Module._yw_key(118, 0x40); });

  // 4. frames: tick every animation frame; paint only when the engine says something changed
  let blink = performance.now(), firstPaint = 0;
  const frame = now => {
    const f0 = performance.now();
    if (Module._yw_frame(now - t0) && !firstPaint) {
      console.log('yantra: first paint took ' + (performance.now() - f0).toFixed(1) + ' ms');
      firstPaint = performance.now() - t0;
      console.log('yantra: first frame ' + firstPaint.toFixed(1) + ' ms after start');
    }
    if (now - blink > 530 && Module._yw_focused()) { Module._yw_blink(); blink = now; }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
  return Module;
}
