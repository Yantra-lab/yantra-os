// web/runner/runner.js — runs a Yantra app module (.wasm) in a web page.
// Speaks protocol v2 and parity with E5 engine styling, layout, appView & themes.
import { K, P, E } from './protocol.mjs';
import { hostImports, YantraExit } from './hostimports.mjs';
import { paintCommands, makeLayer } from './paint2d.mjs';
export { K, P, E };

class MiniElement {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.style = {};
    this.children = [];
    this.parentElement = null;
    this._text = '';
    this._listeners = new Map();
    this.value = '';
    this.checked = false;
    this.type = '';
    this.placeholder = '';
    this.className = '';
    this.attributes = {};
  }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); }
  set textContent(v) { this._text = String(v); this.children = []; }
  get innerText() { return this.textContent; }
  set innerText(v) { this.textContent = v; }
  appendChild(child) { return this.insertBefore(child, null); }
  insertBefore(child, ref) {
    if (child.parentElement) child.parentElement.removeChild(child);
    const i = ref ? this.children.indexOf(ref) : -1;
    if (i < 0) this.children.push(child); else this.children.splice(i, 0, child);
    child.parentElement = this;
    return child;
  }
  removeChild(child) {
    const i = this.children.indexOf(child);
    if (i >= 0) this.children.splice(i, 1);
    child.parentElement = null;
    return child;
  }
  remove() { this.parentElement?.removeChild(this); }
  setAttribute(k, v) { this.attributes[k] = String(v); }
  addEventListener(type, fn) {
    if (!this._listeners.has(type)) this._listeners.set(type, []);
    this._listeners.get(type).push(fn);
  }
  dispatchEvent(ev) {
    ev.preventDefault ??= () => { ev.defaultPrevented = true; };
    let cur = this;
    while (cur) {
      for (const fn of cur._listeners.get(ev.type) || []) fn(ev);
      if (ev.cancelBubble || ev.bubbles === false) break;
      cur = cur.parentElement;
    }
    return !ev.defaultPrevented;
  }
  click() { this.dispatchEvent({ type: 'click' }); }
}

const hasDom = typeof document !== 'undefined' && typeof document.createElement === 'function';
const createElement = (tag) => (hasDom ? document.createElement(tag) : new MiniElement(tag));

const THEME = `
.y-window{background:#0B0B10;color:#F5F5F7;font:15px/1.35 "Segoe UI",system-ui,-apple-system,sans-serif;display:flex;flex-direction:column;box-sizing:border-box;overflow:auto;max-width:100%;min-height:100%}
.y-window *{box-sizing:border-box}
.y-col{display:flex;flex-direction:column}
.y-row{display:flex;flex-direction:row;align-items:center}
.y-group{display:contents}
.y-stack{display:grid;position:relative}
.y-stack>*{grid-area:1/1}
.y-appview{display:flex;flex:1;position:relative;min-width:0;min-height:0}
.y-path{display:inline-flex;align-items:center;justify-content:center}
.y-text{white-space:pre-wrap;min-width:0}
.y-button{font:inherit;font-weight:600;color:#F5F5F7;background:#26262E;border:0;border-radius:8px;padding:9px 14px;cursor:pointer;flex:none}
.y-button:hover{filter:brightness(1.12)}
.y-button:active{filter:brightness(.85)}
.y-input{font:inherit;color:#F5F5F7;background:#15151B;border:1px solid #2C2C35;border-radius:8px;padding:11px 12px;min-width:80px;outline:none}
.y-input:focus{border-color:#FFB23E;box-shadow:0 0 0 .5px #FFB23E}
.y-input::placeholder{color:#55555E}
.y-check{display:flex;align-items:center;gap:10px;cursor:pointer;min-width:0}
.y-check input{appearance:none;width:18px;height:18px;margin:0;border:1.5px solid #55555E;border-radius:5px;flex:none;display:grid;place-content:center;cursor:pointer}
.y-check input:checked{background:#FFB23E;border-color:#FFB23E}
.y-check input:checked::after{content:"";width:9px;height:5px;border:2.3px solid #1A1206;border-top:0;border-right:0;transform:translateY(-1px) rotate(-45deg)}
.y-check input:checked+span{color:#8C8C96}
.y-spacer{flex:1}
`;

function injectTheme() {
  if (!hasDom || document.getElementById('yantra-theme')) return;
  const s = document.createElement('style');
  s.id = 'yantra-theme';
  s.textContent = THEME;
  document.head.appendChild(s);
}

export function colorCss(v) {
  if (typeof v !== 'number') return String(v ?? '');
  const a = (v >>> 24) & 0xff;
  const r = (v >>> 16) & 0xff, g = (v >>> 8) & 0xff, b = v & 0xff;
  if (a === 0) return '#' + (v & 0xffffff).toString(16).padStart(6, '0');
  return `rgba(${r}, ${g}, ${b}, ${Math.round((a / 255) * 100) / 100})`;
}

const px = (v) => (typeof v === 'number' ? `${v}px` : String(v));

function decodeString(memory, ptr, len) {
  if (!memory || ptr <= 0 || len <= 0) return '';
  return new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
}

export class YantraWebRunner {
  constructor(options = {}) {
    this.targetElement = options.targetElement || null;
    this.appResolver = options.appResolver || null;
    this.nodes = [];
    this.handlers = new Map();
    this.logs = [];
    this.memory = null;
    this.instance = null;
    this.rootElement = null;
    this.layers = new Map();      // retained bitmaps an app keeps (newLayer)
    this.images = new Map();      // decoded images for the `I` verb
    this.buffers = new Map();     // raw RGBA from newBuffer (the `X` verb)
    this.paintStats = { ops: 0, unsupported: 0, paints: 0 };
    injectTheme();

    this.env = {
      y_node_create: (kind) => this._create(kind),
      y_node_child: (p, c) => this._insert(p, c, -1),
      y_node_insert: (p, c, before) => this._insert(p, c, before),
      y_node_remove: (n) => this._remove(n),
      y_node_set_i32: (n, p, v) => this._setProp(n, p, v),
      y_node_set_f32: (n, p, v) => this._setProp(n, p, v),
      y_node_set_str: (n, p, ptr, len) => this._setProp(n, p, decodeString(this.memory, ptr, len)),
      y_node_get_str: (n, p, buf, cap) => this._getStr(n, p, buf, cap),
      y_node_on: (n, ev, handler) => this._on(n, ev, handler),
      y_key: () => 0, y_key_handled: () => {},
      y_node_size: (n, axis) => { const el = this.nodes[n] && this.nodes[n].el; if (!el || !el.getBoundingClientRect) return 0; const r = el.getBoundingClientRect(); return axis === 0 ? r.width : r.height; },
      yantra_log: (ptr, len) => this.logs.push(decodeString(this.memory, ptr, len)),
      yantra_get_dt: () => 0.016,
      y_after: (ms, handler) => { setTimeout(() => this.dispatch(handler), Math.max(0, ms)); },
      y_fetch: (u, ul, handler) => this._fetch(decodeString(this.memory, u, ul), handler),
      y_fetch_ex: (r, rl, handler) => this._fetchEx(decodeString(this.memory, r, rl), handler),
      y_ws_open: (u, ul, handler) => this._wsOpen(decodeString(this.memory, u, ul), handler),
      y_ws_send: (id, d, l) => this._wsSend(id, new Uint8Array(this.memory.buffer, d, l).slice()),
      y_ws_close: (id) => this._wsClose(id),
      y_ws_event: (id) => (this._wsEv && this._wsEv.has(id)) ? this._wsEv.get(id)[0] : 0,
      y_ws_data: (id, buf, cap) => this._copyOut(this._wsEv && this._wsEv.get(id), buf, cap),
      y_fetch_status: (id) => (this._fetched && this._fetched.has(id)) ? this._fetched.get(id)[0] : -1,
      y_fetch_body: (id, buf, cap) => this._fetchBody(id, buf, cap),
      y_store_get: (k, kl, buf, cap) => this._storeGet(decodeString(this.memory, k, kl), buf, cap),
      y_store_set: (k, kl, v, vl) => this._storeSet(decodeString(this.memory, k, kl), v, vl),
      y_file_read: (pathPtr, pathLen, outBuf, outCap) => -1,
      y_sound_load: (p, l) => 1,
      y_sound_play: (id) => {},
      y_sound_stop: (id) => {},
      y_sound_volume: (id, v) => {},
      y_pick_open: (filterPtr, filterLen, handler) => -1,
      y_pick_save: (dataPtr, dataLen, namePtr, nameLen, filterPtr, filterLen, handler) => -1,
      y_pick_status: (id) => -1,
      y_pick_body: (id, buf, cap) => -1,
      y_drop_data: (buf, cap) => -1,
      y_drop_name: (buf, cap) => -1,
      y_notify: (tp, tl, bp, bl) => 0,
      y_text_measure: (p, l, fp, fl, size, weight) => {
        const s = decodeString(this.memory, p, l);
        if (!s) return 0;
        const fam = decodeString(this.memory, fp, fl);
        if (hasDom) {
          if (!this._measureCtx) this._measureCtx = document.createElement('canvas').getContext('2d');
          this._measureCtx.font = `${weight > 0 ? weight : 400} ${size}px ${fam ? `"${fam}", ` : ''}system-ui, sans-serif`;
          return this._measureCtx.measureText(s).width;
        }
        return s.length * size * 0.5;  // no fonts outside a browser; say so in the docs
      },
      y_open_url: (urlPtr, urlLen) => 0,
      y_phys: () => {},
      y_phys_hit: () => -1,
      y_layer_new: (id, w, h) => { this._layer(id, w, h); return id; },
      y_layer_draw: (id, p, n) => this._layerDraw(id, p, n),
      y_layer_filter: (id, kind, amount) => this._layerFilter(id, kind, amount),
      y_layer_read: (id, x, y, w, h, p) => this._layerRead(id, x, y, w, h, p),
      y_layer_write: (id, x, y, w, h, p) => this._layerWrite(id, x, y, w, h, p),
      y_layer_free: (id) => { this.layers.delete(id); },
      y_input: (what, arg) => {
        if (what >= 13 && what <= 17) {
          const d = new Date();
          switch (what) {
            case 13: return d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
            case 14: return (d.getDay() + 6) % 7;
            case 15: return d.getDate();
            case 16: return d.getMonth() + 1;
            case 17: return d.getFullYear();
          }
        }
        return 0.0;
      },
      y_buf: () => {},
      y_bone: () => 0.0,
      // The agent and the control centre, served honestly: a browser tab has no
      // model and cannot reach the machine, so `ready` is 0 and `sys` is -1
      // ("not known", the SDK's own marker) rather than a fabricated reading.
      // A module that needs them (the desktop asks with needs("ai", "system"))
      // would otherwise not link at all.
      y_ai: () => 0,            // no model in the browser runner yet: refused
      y_ai_ready: () => 0,
      y_sys: () => -1,          // the browser runner does not reach the system
      y_sys_text: () => -1,
    };
  }

  _alive(n) { return n >= 0 && n < this.nodes.length && this.nodes[n].alive; }

  _create(kind) {
    const id = this.nodes.length;
    let el;
    switch (kind) {
      case K.WINDOW: el = createElement('div'); el.className = 'y-window'; break;
      case K.COLUMN: case K.PANEL: el = createElement('div'); el.className = 'y-col'; el.style.display = 'flex'; el.style.flexDirection = 'column'; break;
      case K.ROW: el = createElement('div'); el.className = 'y-row'; el.style.display = 'flex'; el.style.flexDirection = 'row'; break;
      case K.GROUP: el = createElement('div'); el.className = 'y-group'; el.style.display = 'contents'; break;
      case K.GRID: el = createElement('div'); el.className = 'y-grid'; el.style.display = 'grid'; el.style.alignItems = 'stretch'; break;
      case K.STACK: el = createElement('div'); el.className = 'y-stack'; el.style.display = 'grid'; el.style.position = 'relative'; break;
      case K.TEXT: el = createElement('span'); el.className = 'y-text'; break;
      case K.BUTTON: el = createElement('button'); el.className = 'y-button'; el.type = 'button'; break;
      case K.INPUT: el = createElement('input'); el.className = 'y-input'; el.type = 'text'; break;
      case K.CHECKBOX: {
        el = createElement('label'); el.className = 'y-check';
        const box = createElement('input'); box.type = 'checkbox';
        const span = createElement('span');
        el.appendChild(box); el.appendChild(span);
        el._box = box; el._span = span;
        break;
      }
      case K.SPACER: el = createElement('div'); el.className = 'y-spacer'; break;
      case K.APPVIEW: el = createElement('div'); el.className = 'y-appview'; el.style.display = 'flex'; el.style.position = 'relative'; break;
      case K.PATH: el = createElement('div'); el.className = 'y-path'; break;
      case K.CANVAS: {
        // A canvas is a canvas: the node draws a retained command list, so it needs
        // something that can rasterise one. In a browser that is a real <canvas>.
        el = createElement('canvas');
        el.className = 'y-canvas';
        el.style.display = 'block';
        if (el.width === undefined) el.width = 320;
        if (el.height === undefined) el.height = 200;
        break;
      }
      default: el = createElement('div');
    }
    const node = { id, kind, props: {}, children: [], parent: -1, alive: true, el, _hovered: false, _pressed: false, _focused: false };
    this.nodes.push(node);

    el.addEventListener?.('mouseenter', () => { node._hovered = true; this._updateStyles(id); });
    el.addEventListener?.('mouseleave', () => { node._hovered = false; node._pressed = false; this._updateStyles(id); });
    el.addEventListener?.('mousedown', () => { node._pressed = true; this._updateStyles(id); });
    el.addEventListener?.('mouseup', () => { node._pressed = false; this._updateStyles(id); });
    el.addEventListener?.('focus', () => { node._focused = true; this._updateStyles(id); });
    el.addEventListener?.('blur', () => { node._focused = false; this._updateStyles(id); });

    if (kind === K.WINDOW && !this.rootElement) {
      this.rootElement = el;
      this.targetElement?.appendChild?.(el);
    }
    if (kind === K.INPUT) {
      el.addEventListener('input', () => {
        this.nodes[id].props[P.VALUE] = el.value;
        this._fire(id, E.INPUT);
      });
      el.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') this._fire(id, E.SUBMIT); });
    }
    if (kind === K.CHECKBOX) {
      el.addEventListener('click', (ev) => {
        ev.preventDefault?.();
        this._fire(id, E.CHANGE);
        this._fire(id, E.CLICK);
        if (this._alive(id)) el._box.checked = !!this.nodes[id].props[P.CHECKED];
      });
    }
    return id;
  }

  _insert(p, c, before) {
    if (!this._alive(p) || !this._alive(c) || p === c) return;
    const parent = this.nodes[p], child = this.nodes[c];
    if (child.parent >= 0) {
      const old = this.nodes[child.parent].children;
      const i = old.indexOf(c);
      if (i >= 0) old.splice(i, 1);
    }
    const i = before >= 0 ? parent.children.indexOf(before) : -1;
    if (i < 0) parent.children.push(c); else parent.children.splice(i, 0, c);
    child.parent = p;
    parent.el.insertBefore(child.el, i < 0 ? null : this.nodes[before].el);
  }

  _kill(n) {
    const node = this.nodes[n];
    node.alive = false;
    node.childRunner = null;
    for (const c of node.children) this._kill(c);
    node.children = [];
  }

  _remove(n) {
    if (!this._alive(n)) return;
    const node = this.nodes[n];
    if (node.parent >= 0) {
      const sib = this.nodes[node.parent].children;
      const i = sib.indexOf(n);
      if (i >= 0) sib.splice(i, 1);
    }
    node.el.remove?.();
    this._kill(n);
  }

  _on(n, ev, handler) {
    if (!this._alive(n)) return;
    this.handlers.set(`${n}:${ev}`, handler);
    const node = this.nodes[n];
    if (ev === E.CLICK && node.kind !== K.CHECKBOX && node.kind !== K.INPUT && !node._clickWired) {
      // Views refresh their handler table without replacing the DOM element.
      // One DOM listener must read the latest handler, not accumulate another
      // dispatch on every render (which also makes MiniElement clicks recurse).
      node._clickWired = true;
      node.el.addEventListener('click', () => this._fire(n, E.CLICK));
    }
    if (ev === E.RESIZE && !node._resizeWired && typeof ResizeObserver === 'function') {
      // container queries (Q1): the app hears its node's size, as on the native engine
      node._resizeWired = true;
      new ResizeObserver(() => this._fire(n, E.RESIZE)).observe(node.el);
    }
  }

  _fire(n, ev) {
    const h = this.handlers.get(`${n}:${ev}`);
    if (h !== undefined) this.dispatch(h);
  }

  _getStr(n, p, buf, cap) {
    const v = this._alive(n) ? String(this.nodes[n].props[p] ?? '') : '';
    const bytes = new TextEncoder().encode(v);
    if (this.memory && buf > 0 && cap > 0) {
      new Uint8Array(this.memory.buffer, buf, Math.min(cap, bytes.length)).set(bytes.subarray(0, cap));
    }
    return bytes.length;
  }

  // Saved values (N1): the app's own keys in localStorage (a Map where there is none).
  _store() {
    if (!this._storeMap) this._storeMap = (typeof localStorage !== 'undefined') ? null : new Map();
    return this._storeMap;
  }
  _storeKey(k) { return `yantra:${this.appName || 'app'}:${k}`; }
  _storeGet(key, buf, cap) {
    const m = this._store();
    const v = m ? m.get(this._storeKey(key)) : localStorage.getItem(this._storeKey(key));
    if (v === undefined || v === null) return -1;
    const bytes = Uint8Array.from(v, (c) => c.charCodeAt(0));
    if (this.memory && buf > 0 && cap > 0) {
      new Uint8Array(this.memory.buffer, buf, Math.min(cap, bytes.length)).set(bytes.subarray(0, cap));
    }
    return bytes.length;
  }
  _storeSet(key, val, len) {
    if (!/^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}$/.test(key) || len < 0 || len > (1 << 20)) return 0;
    const bytes = len > 0 ? new Uint8Array(this.memory.buffer, val, len) : new Uint8Array(0);
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    const m = this._store();
    try { if (m) m.set(this._storeKey(key), s); else localStorage.setItem(this._storeKey(key), s); } catch { return 0; }
    return 1;
  }

  // Network (F1): the same rule as the native host (host/host.nim netAllowed): only the
  // hosts the window lists, https (plain http only to this machine), no redirects.
  _netAllowed(url) {
    const w = this.nodes[0];
    const allow = (w && w.props && typeof w.props[P.NET] === 'string') ? w.props[P.NET] : '';
    const m = /^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)/i.exec(url);
    if (!m || m[2].includes('@') || m[2].startsWith('[')) return false;
    const scheme = m[1].toLowerCase();
    const host = m[2].replace(/:\d+$/, '').toLowerCase();
    if (!/^[a-z0-9.-]+$/.test(host)) return false;
    const local = host === 'localhost' || host === '127.0.0.1';
    if (!(scheme === 'https' || scheme === 'wss' || ((scheme === 'http' || scheme === 'ws') && local))) return false;
    return allow.split(/[,\s]+/).some((a) => {
      a = a.trim().toLowerCase();
      if (!a || a === '*') return false;
      return a === host || (a.startsWith('*.') && host.endsWith(a.slice(1)) && host.length > a.length - 1);
    });
  }
  // the same request form and rules as the native host (host.nim parseRequest)
  _fetchEx(req, handler) {
    const LF = String.fromCharCode(10);
    const lines = req.split(LF);
    const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];
    const hostOnly = ['host', 'content-length', 'transfer-encoding', 'connection', 'upgrade'];
    if (lines.length < 2 || !methods.includes(lines[0])) return 0;
    const headers = {};
    let i = 2;
    for (; i < lines.length && lines[i].length > 0; i++) {
      const k = lines[i].indexOf(':');
      if (k <= 0 || hostOnly.includes(lines[i].slice(0, k).trim().toLowerCase())) return 0;
      headers[lines[i].slice(0, k).trim()] = lines[i].slice(k + 1).trim();
    }
    const body = i < lines.length ? lines.slice(i + 1).join(LF) : '';
    const opts = { method: lines[0], headers };
    if (body.length > 0 || lines[0] === 'POST') opts.body = body;
    return this._fetch(lines[1], handler, opts);
  }
  _copyOut(ev, buf, cap) {
    if (!ev) return -1;
    const bytes = ev[1];
    if (this.memory && buf > 0 && cap > 0) new Uint8Array(this.memory.buffer, buf, Math.min(cap, bytes.length)).set(bytes.subarray(0, cap));
    return bytes.length;
  }
  // WebSockets (W1): the same net rule; ws only to this machine
  _wsOpen(url, handler) {
    if (typeof WebSocket !== 'function' || !/^wss?:/i.test(url) || !this._netAllowed(url)) return 0;
    this._ws = this._ws || new Map(); this._wsEv = this._wsEv || new Map();
    if (this._ws.size >= 8) return 0;
    this._nextFetch = (this._nextFetch || 0) + 1;
    const id = this._nextFetch;
    const enc = new TextEncoder();
    const sock = new WebSocket(url); sock.binaryType = 'arraybuffer';
    const fire = (kind, bytes) => {
      if (!this._ws.has(id)) return;
      this._wsEv.set(id, [kind, bytes]);
      try { this.dispatch(handler); } finally { this._wsEv.delete(id); }
      if (kind === 3) this._ws.delete(id);
    };
    const entry = { sock, queue: [] };
    sock.onopen = () => { for (const m of entry.queue) sock.send(m); entry.queue = []; fire(1, new Uint8Array(0)); };
    sock.onmessage = (ev) => fire(2, typeof ev.data === 'string' ? enc.encode(ev.data) : new Uint8Array(ev.data));
    sock.onclose = (ev) => fire(3, enc.encode(ev.wasClean ? '' : 'closed'));
    this._ws.set(id, entry);
    return id;
  }
  _wsSend(id, bytes) {
    const e = this._ws && this._ws.get(id);
    if (!e) return 0;
    const text = new TextDecoder().decode(bytes);
    if (e.sock.readyState === 1) e.sock.send(text); else e.queue.push(text);
    return 1;
  }
  _wsClose(id) {
    const e = this._ws && this._ws.get(id);
    if (e) { this._ws.delete(id); e.sock.close(); }
  }
  _fetch(url, handler, opts) {
    if (!this._netAllowed(url) || typeof fetch !== 'function') return 0;
    this._fetched = this._fetched || new Map();
    this._nextFetch = (this._nextFetch || 0) + 1;
    const id = this._nextFetch;
    const done = (status, bytes) => {
      this._fetched.set(id, [status, bytes]);
      try { this.dispatch(handler); } finally { this._fetched.delete(id); }
    };
    fetch(url, Object.assign({ redirect: 'manual' }, opts || {}))
      .then(async (r) => done(r.status, new Uint8Array(await r.arrayBuffer())))
      .catch((e) => done(0, new TextEncoder().encode(String(e && e.message || e))));
    return id;
  }
  _fetchBody(id, buf, cap) {
    if (!this._fetched || !this._fetched.has(id)) return -1;
    const bytes = this._fetched.get(id)[1];
    if (this.memory && buf > 0 && cap > 0) {
      new Uint8Array(this.memory.buffer, buf, Math.min(cap, bytes.length)).set(bytes.subarray(0, cap));
    }
    return bytes.length;
  }

  _updateStyles(n) {
    if (!this._alive(n)) return;
    const node = this.nodes[n], p = node.props, st = node.el.style, k = node.kind;

    // Fill / Background
    let fill = undefined;
    if (node._pressed && p[P.PRESSFILL] !== undefined) fill = colorCss(p[P.PRESSFILL]);
    else if (node._focused && p[P.FOCUSFILL] !== undefined) fill = colorCss(p[P.FOCUSFILL]);
    else if (node._hovered && p[P.HOVERFILL] !== undefined) fill = colorCss(p[P.HOVERFILL]);
    else if (p[P.GRADANGLE] !== undefined && p[P.GRADANGLE] >= 0) {
      fill = `linear-gradient(${p[P.GRADANGLE]}deg, ${colorCss(p[P.GRADFROM] ?? 0)}, ${colorCss(p[P.GRADTO] ?? 0)})`;
    } else if (p[P.COLOR] !== undefined && k !== K.TEXT && k !== K.CHECKBOX) {
      fill = colorCss(p[P.COLOR]);
    }
    if (fill !== undefined) st.background = fill;

    // Color (text)
    let col = undefined;
    if (node._pressed && p[P.PRESSCOLOR] !== undefined) col = colorCss(p[P.PRESSCOLOR]);
    else if (node._focused && p[P.FOCUSCOLOR] !== undefined) col = colorCss(p[P.FOCUSCOLOR]);
    else if (node._hovered && p[P.HOVERCOLOR] !== undefined) col = colorCss(p[P.HOVERCOLOR]);
    else if (p[P.TEXTCOLOR] !== undefined) col = colorCss(p[P.TEXTCOLOR]);
    else if (p[P.COLOR] !== undefined && (k === K.TEXT || k === K.CHECKBOX)) col = colorCss(p[P.COLOR]);
    if (col !== undefined) st.color = col;

    // Border
    let bc = undefined;
    if (node._pressed && p[P.PRESSBORDER] !== undefined) bc = colorCss(p[P.PRESSBORDER]);
    else if (node._focused && p[P.FOCUSBORDER] !== undefined) bc = colorCss(p[P.FOCUSBORDER]);
    else if (node._hovered && p[P.HOVERBORDER] !== undefined) bc = colorCss(p[P.HOVERBORDER]);
    else if (p[P.BORDERCOLOR] !== undefined) bc = colorCss(p[P.BORDERCOLOR]);
    if (bc !== undefined) { st.borderColor = bc; st.borderStyle = 'solid'; }

    // Opacity
    let op = undefined;
    if (node._pressed && p[P.PRESSOPACITY] !== undefined) op = String(p[P.PRESSOPACITY]);
    else if (node._focused && p[P.FOCUSOPACITY] !== undefined) op = String(p[P.FOCUSOPACITY]);
    else if (node._hovered && p[P.HOVEROPACITY] !== undefined) op = String(p[P.HOVEROPACITY]);
    else if (p[P.OPACITY] !== undefined) op = String(p[P.OPACITY]);
    if (op !== undefined) st.opacity = op;

    // Shadow
    if (p[P.SHADOWCOLOR] !== undefined) {
      const sx = px(p[P.SHADOWX] || 0), sy = px(p[P.SHADOWY] || 0), sb = px(p[P.SHADOWBLUR] || 0);
      st.boxShadow = `${sx} ${sy} ${sb} ${colorCss(p[P.SHADOWCOLOR])}`;
    }
  }

  _setProp(n, prop, val) {
    if (!this._alive(n)) return;
    const node = this.nodes[n];
    node.props[prop] = val;
    const el = node.el, st = el.style, k = node.kind;

    switch (prop) {
      case P.TEXT:
        if (k === K.CHECKBOX) el._span.textContent = val;
        else if (k === K.WINDOW) el.setAttribute?.('aria-label', val);
        else if (k !== K.INPUT) el.textContent = val;
        break;
      case P.VALUE: if (k === K.INPUT && el.value !== val) el.value = val; break;
      case P.PLACEHOLDER: el.placeholder = val; break;
      case P.CHECKED: if (k === K.CHECKBOX) el._box.checked = !!val; break;
      case P.FONTSIZE: st.fontSize = px(val); break;
      case P.FONTWEIGHT: st.fontWeight = String(val); break;
      case P.SPACING: st.gap = px(val); break;
      case P.GRIDCOLS: st.gridTemplateColumns = String(val).split(/\s+/).filter(Boolean).map(t => /^[0-9.]+$/.test(t) ? t + 'px' : t).join(' '); break;
      case P.SPAN: st.gridColumn = 'span ' + Math.max(1, val | 0); break;
      case P.PADTOP: st.paddingTop = px(val); break;
      case P.PADRIGHT: st.paddingRight = px(val); break;
      case P.PADBOTTOM: st.paddingBottom = px(val); break;
      case P.PADLEFT: st.paddingLeft = px(val); break;
      case P.MARGINTOP: st.marginTop = px(val); break;
      case P.MARGINRIGHT: st.marginRight = px(val); break;
      case P.MARGINBOTTOM: st.marginBottom = px(val); break;
      case P.MARGINLEFT: st.marginLeft = px(val); break;
      case P.RADIUS: st.borderRadius = px(val); break;
      case P.BORDERWIDTH: st.borderWidth = px(val); st.borderStyle = 'solid'; break;
      case P.WIDTH:
        st.width = px(val);
        if (k === K.CANVAS && node.props[P.CANVASWIDTH] === undefined && val > 0) {
          el.width = Math.round(val);
          this._paintCanvas(node);
        }
        break;
      case P.HEIGHT:
        st.height = px(val);
        if (k === K.CANVAS && node.props[P.CANVASHEIGHT] === undefined && val > 0) {
          el.height = Math.round(val);
          this._paintCanvas(node);
        }
        break;
      case P.MINWIDTH: st.minWidth = px(val); break;
      case P.MINHEIGHT: st.minHeight = px(val); break;
      case P.MAXWIDTH: st.maxWidth = px(val); break;
      case P.MAXHEIGHT: st.maxHeight = px(val); break;
      case P.FLEXGROW: st.flexGrow = String(val); st.minWidth = '0'; break;
      case P.FLEXSHRINK: st.flexShrink = String(val); break;
      case P.VISIBLE: st.display = val ? '' : 'none'; break;
      case P.ALIGN: st.textAlign = ['left', 'center', 'right'][val] || 'left'; break;
      case P.ALIGNITEMS: st.alignItems = ['flex-start', 'center', 'flex-end', 'stretch'][val] || String(val); break;
      case P.JUSTIFY: st.justifyContent = ['flex-start', 'center', 'flex-end', 'space-between', 'space-around', 'space-evenly'][val] || String(val); break;
      case P.WRAP: st.flexWrap = val ? 'wrap' : 'nowrap'; break;
      case P.ABSOLUTE: if (val) st.position = 'absolute'; break;
      case P.INSETTOP: st.top = px(val); break;
      case P.INSETRIGHT: st.right = px(val); break;
      case P.INSETBOTTOM: st.bottom = px(val); break;
      case P.INSETLEFT: st.left = px(val); break;
      case P.ZINDEX: st.zIndex = String(val); break;
      case P.SCROLL: if (val) st.overflow = 'auto'; break;
      case P.CLIP: if (val) st.overflow = 'hidden'; break;
      case P.CURSOR: st.cursor = typeof val === 'string' ? val : (val === 1 ? 'pointer' : 'default'); break;
      case P.FONTFAMILY: st.fontFamily = String(val); break;
      case P.LINEHEIGHT: st.lineHeight = String(val); break;
      case P.PATHDATA:
        if (k === K.PATH) {
          el.innerHTML = `<svg viewBox="0 0 24 24" width="24" height="24" style="display:block"><path d="${val}" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
        }
        break;
      case P.DRAW:
        if (k === K.CANVAS) this._paintCanvas(node);
        break;
      case P.CANVASWIDTH:
      case P.CANVASHEIGHT:
        if (k === K.CANVAS) {
          const w = k === K.CANVAS ? (prop === P.CANVASWIDTH ? val : node.props[P.CANVASWIDTH]) : val;
          void w;
          const cw = prop === P.CANVASWIDTH ? val : node.props[P.CANVASWIDTH];
          const ch = prop === P.CANVASHEIGHT ? val : node.props[P.CANVASHEIGHT];
          if (el.width !== undefined && cw > 0) el.width = Math.round(cw);
          if (el.height !== undefined && ch > 0) el.height = Math.round(ch);
          this._paintCanvas(node);
        }
        break;
      case P.SOURCE:
        if (k === K.APPVIEW && val) {
          this._loadAppView(n, val);
        }
        break;
      case P.THEME:
        if (n === 0) {
          for (const c of this.nodes) {
            if (c.alive && c.kind === K.APPVIEW && c.childRunner) {
              c.childRunner.sendTheme(val);
            }
          }
        }
        break;
      default: break;
    }
    this._updateStyles(n);
  }

  // Paint one canvas node's retained command list. Called whenever the app sets a
  // new DRAW string, which is how an animated scene advances.
  _paintCanvas(node) {
    const el = node.el;
    const draw = node.props[P.DRAW];
    if (typeof draw !== 'string' || !draw.length) return;
    if (!el || typeof el.getContext !== 'function') return;
    const ctx = el.getContext('2d');
    if (!ctx) return;
    const w = el.width || node.props[P.CANVASWIDTH] || 0;
    const h = el.height || node.props[P.CANVASHEIGHT] || 0;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const r = paintCommands(ctx, draw, {
      width: w,
      height: h,
      layers: this.layers,
      buffers: this.buffers,
      images: this.images,
      onImage: () => this._paintCanvas(node),
    });
    this.paintStats.paints += 1;
    this.paintStats.ops = r.ops;
    this.paintStats.unsupported = r.unsupported;
  }

  // ---- retained layers (newLayer / draw / filter / read / write / free) ----
  _layer(id, w, h) {
    if (!this.layers.has(id)) {
      if (hasDom) this.layers.set(id, makeLayer(w, h));
      else this.layers.set(id, { canvas: null, ctx: null, filters: [] });
    }
    return this.layers.get(id);
  }

  _layerDraw(id, ptr, len) {
    const L = this.layers.get(id);
    if (!L || !L.ctx) return;
    const cmds = this._readStr(ptr, len);
    if (!cmds) return;
    const r = paintCommands(L.ctx, cmds, {
      width: L.canvas.width,
      height: L.canvas.height,
      layers: this.layers,
      buffers: this.buffers,
      images: this.images,
    });
    this.paintStats.ops = r.ops;
  }

  // Filter enum order in sdk/ui/paint.nim:
  //   blur, brightness, contrast, saturation, invert, greyscale, sepia, fade
  _layerFilter(id, kind, amount) {
    const L = this.layers.get(id);
    if (!L || !L.ctx || !hasDom) return;
    const css = [
      () => `blur(${Math.max(0, amount)}px)`,
      () => `brightness(${Math.max(0, 1 + amount)})`,
      () => `contrast(${Math.max(0, amount)})`,
      () => `saturate(${Math.max(0, amount)})`,
      () => 'invert(1)',
      () => 'grayscale(1)',
      () => 'sepia(1)',
      () => `opacity(${Math.max(0, Math.min(1, amount))})`,
    ][kind | 0];
    if (!css) return;
    const tmp = document.createElement('canvas');
    tmp.width = L.canvas.width; tmp.height = L.canvas.height;
    const tctx = tmp.getContext('2d');
    tctx.filter = css();
    tctx.drawImage(L.canvas, 0, 0);
    L.ctx.setTransform(1, 0, 0, 1, 0, 0);
    L.ctx.clearRect(0, 0, L.canvas.width, L.canvas.height);
    L.ctx.drawImage(tmp, 0, 0);
    L.filters.push({ kind, amount });
  }

  _layerRead(id, x, y, w, h, ptr) {
    const L = this.layers.get(id);
    if (!L || !L.ctx || w <= 0 || h <= 0) return 0;
    const data = L.ctx.getImageData(x, y, w, h).data;
    if (this.memory && ptr > 0 && ptr + data.length <= this.memory.buffer.byteLength) {
      new Uint8Array(this.memory.buffer, ptr, data.length).set(data);
      return data.length;
    }
    return 0;
  }

  _layerWrite(id, x, y, w, h, ptr) {
    const L = this.layers.get(id);
    if (!L || !L.ctx || w <= 0 || h <= 0) return;
    const bytes = new Uint8Array(this.memory.buffer, ptr, w * h * 4).slice();
    const img = L.ctx.createImageData(w, h);
    img.data.set(bytes);
    L.ctx.putImageData(img, x, y);
  }

  _loadAppView(nodeId, src) {
    const node = this.nodes[nodeId];
    if (!node || !this.appResolver) return;
    try {
      const bytes = this.appResolver(src);
      if (bytes) {
        const child = new YantraWebRunner({
          targetElement: node.el,
          appResolver: this.appResolver
        });
        node.childRunner = child;
        child.initSync(bytes);
        const th = this.nodes[0]?.props[P.THEME];
        if (th) child.sendTheme(th);
      }
    } catch (e) {
      console.error(`AppView failed to load "${src}":`, e);
    }
  }

  sendTheme(themeName) {
    if (!themeName) return;
    if (this.nodes[0]) this.nodes[0].props[P.THEME] = themeName;
    if (this.instance) {
      const { yantra_theme_buf, yantra_theme } = this.instance.exports;
      if (typeof yantra_theme_buf === 'function' && typeof yantra_theme === 'function') {
        const p = yantra_theme_buf();
        const b = new TextEncoder().encode(themeName);
        if (this.memory && p > 0) {
          new Uint8Array(this.memory.buffer, p, b.length).set(b);
          yantra_theme(b.length);
        }
      }
    }
    for (const c of this.nodes) {
      if (c.alive && c.kind === K.APPVIEW && c.childRunner) {
        c.childRunner.sendTheme(themeName);
      }
    }
  }

  dispatch(handler) {
    this.instance?.exports?.yantra_dispatch?.(handler);
  }

  // Bytes in and out of the guest's linear memory: the same two primitives every
  // host import needs (host/host.nim readStr / writeStr).
  _readStr(ptr, len) {
    if (!this.memory || ptr < 0 || len <= 0) return '';
    const size = this.memory.buffer.byteLength;
    if (ptr + len > size) return '';
    return new TextDecoder().decode(new Uint8Array(this.memory.buffer, ptr, len));
  }

  _writeStr(ptr, cap, s) {
    if (!this.memory || ptr < 0 || cap <= 0) return 0;
    const b = new TextEncoder().encode(s);
    const n = Math.min(cap, b.length);
    const size = this.memory.buffer.byteLength;
    if (ptr + n > size) return 0;
    new Uint8Array(this.memory.buffer, ptr, n).set(b.subarray(0, n));
    return n;
  }

  initSync(wasmSource) {
    const mod = wasmSource instanceof WebAssembly.Module ? wasmSource : new WebAssembly.Module(wasmSource instanceof Uint8Array ? wasmSource : new Uint8Array(wasmSource));
    // The math library, the Sutra runtime and the pixel buffers are the host's
    // job too (host/host.nim importTable); without them a Sutra-era module does
    // not even link in a browser.
    const env = Object.assign({}, this.env, hostImports(this));
    const inst = new WebAssembly.Instance(mod, { env });
    this.instance = inst;
    this.memory = inst.exports.memory;
    inst.exports.NimMain?.();
    // Sutra/Nimony keeps its top-level globals in `_start`, separately from the
    // older SDK's NimMain. Skipping it leaves sequences and strings zeroed, so
    // otherwise valid modules fail later with a bounds assert or a memory trap.
    if (inst.exports._start) {
      try {
        inst.exports._start();
      } catch (err) {
        // Native callMain accepts nim_exit's distinguished trap here and still
        // calls yantra_main. Preserve that contract, but never swallow a real
        // wasm/JS trap; keep the code visible to verifiers and embedders.
        if (!(err instanceof YantraExit)) throw err;
        this.startExitCode = err.code;
      }
    }
    inst.exports.yantra_main?.();
    return this;
  }

  async init(wasmSource) {
    return this.initSync(wasmSource);
  }

  getNodes() { return this.nodes; }
  getRootElement() { return this.rootElement; }
}

export async function createRunner(opts = {}) {
  const runner = new YantraWebRunner(opts);
  if (opts.wasmBytes) runner.initSync(opts.wasmBytes);
  return runner;
}
