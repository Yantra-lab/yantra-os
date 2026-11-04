// web/runner/paint2d.mjs — the retained draw list, painted on a real canvas.
//
// Every Yantra app paints itself by emitting a command string: `R x y w h radius
// argb` for a rounded rect, `E cx cy rx ry argb` for an ellipse, `T x y size argb
// weight text` for a run of type, and so on. On the native engine that string is
// parsed by the Skia shim (libs/nimskia/src/skia_shim.cpp, `runCmds`) and drawn by
// Skia. In a browser it was parsed by nobody — the web runner created a plain
// <div> for a canvas node and dropped the string on the floor, so every
// canvas-drawn app painted only its window background.
//
// This file is the second consumer of that command stream. It is a port of
// `runCmds` onto Canvas2D: the same verbs, the same argument order, the same
// "pending" state (a gradient or a blur applies to the next shape only), the same
// save/restore stack for alpha and blend mode.
//
// Known differences, stated rather than hidden:
//   * `H` with an SkSL shader body cannot be compiled here (no SkSL in a browser),
//     so a shader rect draws nothing. `stats.unsupported` counts them.
//   * `z` (fractal noise) is implemented here with a deterministic value-noise
//     fBm rather than Skia's SkPerlinNoiseShader, so the grain is equivalent in
//     kind, not identical pixel for pixel.
//   * Skia's round joins and caps on strokes are mirrored; antialiasing and font
//     rasterisation differ because the rasterisers differ.
//
// Determinism: nothing in here uses Math.random. The same command string and the
// same seed always produce the same pixels, which is what the screenshot tool
// relies on.

const BLEND = [
  'copy', 'copy', 'destination-over', 'source-over', 'destination-over',
  'source-in', 'destination-in', 'source-out', 'destination-out', 'source-atop',
  'destination-atop', 'xor', 'lighter', 'multiply', 'screen', 'overlay', 'darken',
  'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference',
  'exclusion', 'multiply', 'hue', 'saturation', 'color', 'luminosity',
];

export function argbToCss(v) {
  const n = v >>> 0;
  const a = (n >>> 24) & 0xff;
  const r = (n >>> 16) & 0xff;
  const g = (n >>> 8) & 0xff;
  const b = n & 0xff;
  return `rgba(${r},${g},${b},${Math.round((a / 255) * 10000) / 10000})`;
}

// Deterministic 2-D value noise with fBm, in [0, 1].
function makeNoise(seed) {
  let s = (Math.floor(seed * 2654435761) ^ 0x9e3779b9) >>> 0;
  const rand = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const N = 256;
  const grid = new Float32Array(N * N);
  for (let i = 0; i < N * N; i += 1) grid[i] = rand();
  const smooth = (t) => t * t * (3 - 2 * t);
  const at = (x, y) => grid[((y & (N - 1)) * N + (x & (N - 1)))];
  return (x, y) => {
    const x0 = Math.floor(x), y0 = Math.floor(y);
    const fx = smooth(x - x0), fy = smooth(y - y0);
    const a = at(x0, y0), b = at(x0 + 1, y0), c = at(x0, y0 + 1), d = at(x0 + 1, y0 + 1);
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
  };
}

function noiseRectTexture(w, h, fx, fy, octaves, seed, c0, c1) {
  const cw = Math.max(1, Math.min(512, Math.round(w)));
  const ch = Math.max(1, Math.min(512, Math.round(h)));
  const cv = document.createElement('canvas');
  cv.width = cw; cv.height = ch;
  const ctx = cv.getContext('2d');
  const img = ctx.createImageData(cw, ch);
  const noise = makeNoise(seed || 0.5);
  const a0 = (c0 >>> 24) & 0xff, r0 = (c0 >>> 16) & 0xff, g0 = (c0 >>> 8) & 0xff, b0 = c0 & 0xff;
  const a1 = (c1 >>> 24) & 0xff, r1 = (c1 >>> 16) & 0xff, g1 = (c1 >>> 8) & 0xff, b1 = c1 & 0xff;
  const oct = Math.max(1, octaves | 0);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      let v = 0, amp = 1, norm = 0, f = 1;
      for (let o = 0; o < oct; o += 1) {
        v += amp * noise((x / cw) * fx * cw * f, (y / ch) * fy * ch * f);
        norm += amp; amp *= 0.5; f *= 2;
      }
      v = v / norm;
      const i = (y * cw + x) * 4;
      img.data[i] = r0 + v * (r1 - r0);
      img.data[i + 1] = g0 + v * (g1 - g0);
      img.data[i + 2] = b0 + v * (b1 - b0);
      img.data[i + 3] = a0 + v * (a1 - a0);
    }
  }
  ctx.putImageData(img, 0, 0);
  return cv;
}

/**
 * Paint one retained draw list.
 * @param {CanvasRenderingContext2D} ctx
 * @param {string} cmds  the command string the app emitted
 * @param {object} opts  { width, height, tMs, layers:Map, buffers:Map, images:Map, onImage }
 * @returns {{ops:number, unsupported:number}} what was drawn, and what this port cannot draw yet
 */
export function paintCommands(ctx, cmds, opts = {}) {
  const width = opts.width || ctx.canvas.width;
  const height = opts.height || ctx.canvas.height;
  const layers = opts.layers || new Map();
  const buffers = opts.buffers || new Map();
  const images = opts.images || new Map();
  let unsupported = 0;
  let ops = 0;

  let alpha = 1;
  const alphaStack = [];
  let blend = 3; // SrcOver
  const blendStack = [];
  let depth = 0;
  let evenOdd = false;
  let pendingGradient = null;
  let pendingBlur = 0;

  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, width, height);
  ctx.clip();

  const fillStyleFor = (argb) => (pendingGradient || argbToCss(argb));

  // --- a tiny scanner over the command string ------------------------------
  let p = 0;
  const n = cmds.length;
  const isNumStart = (c) => (c >= '0' && c <= '9') || c === '-' || c === '+' || c === '.';
  const skipSpace = () => { while (p < n && (cmds[p] === ' ' || cmds[p] === '\n' || cmds[p] === '\r')) p += 1; };
  const num = () => {
    skipSpace();
    const start = p;
    while (p < n && isNumStart(cmds[p])) p += 1;
    const t = cmds.slice(start, p);
    return t === '' ? 0 : parseFloat(t);
  };
  // A trailing field runs to the next unescaped ';'.
  const rest = () => {
    let out = '';
    while (p < n) {
      const c = cmds[p];
      if (c === '\\' && cmds[p + 1] === ';') { out += ';'; p += 2; continue; }
      if (c === ';') break;
      out += c; p += 1;
    }
    return out;
  };
  const peek = () => { skipSpace(); return p < n ? cmds[p] : ''; };

  // The `W` verb is two verbs: radialRect (11 numbers) and soft blur (1 number).
  // The `H` verb is two verbs: an SkSL shader rect (5 numbers then source) and a
  // linear gradient (4 numbers, a stop count, then stops). Both are decided by
  // what the next token looks like, exactly as the runCmds definition intends.
  const looksNumeric = () => { skipSpace(); return p < n && isNumStart(cmds[p]); };

  const applyBlur = () => {
    if (pendingBlur > 0) {
      ctx.filter = `blur(${pendingBlur}px)`;
      pendingBlur = 0;
      return true;
    }
    return false;
  };
  const clearBlur = (applied) => { if (applied) ctx.filter = 'none'; };
  const beginShape = () => {
    ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
    ctx.globalCompositeOperation = BLEND[blend] || 'source-over';
    return applyBlur();
  };
  const rounded = (x, y, w, h, r) => {
    ctx.beginPath();
    const rad = Math.max(0, Math.min(r, Math.min(Math.abs(w), Math.abs(h)) / 2));
    if (rad > 0) ctx.roundRect(x, y, w, h, rad);
    else ctx.rect(x, y, w, h);
  };

  while (p < n) {
    const op = cmds[p];
    p += 1;
    if (op === ';' || op === ' ' || op === '\n') continue;
    ops += 1;
    switch (op) {
      case 'M': ctx.moveTo(num(), num()); break;
      case 'L': ctx.lineTo(num(), num()); break;
      case 'Q': { const a = num(), b = num(), x = num(), y = num(); ctx.quadraticCurveTo(a, b, x, y); break; }
      case 'C': { const a = num(), b = num(), c = num(), d = num(), x = num(), y = num(); ctx.bezierCurveTo(a, b, c, d, x, y); break; }
      case 'A': {
        const cx = num(), cy = num(), rad = num(), st = num(), sw = num();
        ctx.moveTo(cx + rad * Math.cos((st * Math.PI) / 180), cy + rad * Math.sin((st * Math.PI) / 180));
        ctx.arc(cx, cy, rad, (st * Math.PI) / 180, ((st + sw) * Math.PI) / 180, sw < 0);
        break;
      }
      case 'Z': ctx.closePath(); break;
      case 'F': {
        const c = num();
        const blurred = beginShape();
        ctx.fillStyle = fillStyleFor(c);
        ctx.fill(evenOdd ? 'evenodd' : 'nonzero');
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'f': evenOdd = num() !== 0; break;
      case 'S': {
        const c = num(), w = num();
        const blurred = beginShape();
        ctx.strokeStyle = fillStyleFor(c);
        ctx.lineWidth = w > 0 ? w : 1;
        ctx.lineJoin = 'round'; ctx.lineCap = 'round';
        ctx.stroke();
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'R': {
        const x = num(), y = num(), w = num(), h = num(), rad = num(), c = num();
        const blurred = beginShape();
        rounded(x, y, w, h, rad);
        ctx.fillStyle = fillStyleFor(c);
        ctx.fill();
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'B': {
        const x = num(), y = num(), w = num(), h = num(), rad = num(), c = num(), sw = num();
        const blurred = beginShape();
        rounded(x, y, w, h, rad);
        ctx.strokeStyle = fillStyleFor(c);
        ctx.lineWidth = sw > 0 ? sw : 1;
        ctx.stroke();
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'E': {
        const cx = num(), cy = num(), rx = num(), ry = num(), c = num();
        const blurred = beginShape();
        ctx.beginPath();
        ctx.ellipse(cx, cy, Math.abs(rx), Math.abs(ry), 0, 0, Math.PI * 2);
        ctx.fillStyle = fillStyleFor(c);
        ctx.fill();
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'U': {
        const x = num(), y = num(), w = num(), h = num(), rad = num();
        const x1 = num(), y1 = num(), x2 = num(), y2 = num();
        const c0 = num(), c1 = num();
        const blurred = beginShape();
        const g = ctx.createLinearGradient(x1, y1, x2, y2);
        g.addColorStop(0, argbToCss(c0));
        g.addColorStop(1, argbToCss(c1));
        rounded(x, y, w, h, rad);
        ctx.fillStyle = g;
        ctx.fill();
        clearBlur(blurred);
        break;
      }
      case 'W': {
        const first = num();
        if (looksNumeric()) {
          const y = first, x = NaN; // keep the naming honest below
          void x; void y;
          // radialRect: W x y w h corner cx cy rad c0 c1 (we already ate `x`)
          const yy = num(), w = num(), h = num(), corner = num();
          const cx = num(), cy = num(), rad = num();
          const c0 = num(), c1 = num();
          const blurred = beginShape();
          const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(0.01, rad));
          g.addColorStop(0, argbToCss(c0));
          g.addColorStop(1, argbToCss(c1));
          rounded(first, yy, w, h, corner);
          ctx.fillStyle = g;
          ctx.fill();
          clearBlur(blurred);
        } else {
          pendingBlur = Math.max(0, first);
        }
        break;
      }
      case 'G': {
        const x1 = num(), y1 = num(), x2 = num(), y2 = num(), c = num(), w = num();
        const blurred = beginShape();
        ctx.strokeStyle = fillStyleFor(c);
        ctx.lineWidth = w > 0 ? w : 1;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
        ctx.stroke();
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'z': {
        const x = num(), y = num(), w = num(), h = num(), rad = num();
        const fx = num(), fyRaw = num(), oct = num(), seed = num();
        const c0 = num(), c1 = num();
        const fy = fyRaw > 0 ? fyRaw : fx;
        if (w > 0 && h > 0) {
          const tex = noiseRectTexture(w, h, fx || 0.05, fy || 0.05, oct, seed, c0, c1);
          const blurred = beginShape();
          rounded(x, y, w, h, rad);
          ctx.clip();
          ctx.drawImage(tex, x, y, w, h);
          clearBlur(blurred);
        }
        break;
      }
      case 'H': {
        const x = num(), y = num(), w = num(), h = num();
        if (looksNumeric()) {
          // linear gradient: H x0 y0 x1 y1 n (color pos)...
          const y1 = num();
          void y1;
          const x0 = x, y0 = y, x1 = w, y2 = h;
          const count = num() | 0;
          const g = ctx.createLinearGradient(x0, y0, x1, y2);
          for (let i = 0; i < Math.min(16, Math.max(0, count)); i += 1) {
            const col = num();
            const pos = num();
            g.addColorStop(Math.max(0, Math.min(1, pos)), argbToCss(col));
          }
          pendingGradient = g;
        } else {
          // shaderRect: 5th number is the corner radius, then SkSL source.
          const rad = num();
          rest();
          unsupported += 1;
          void rad;
        }
        break;
      }
      case 'T': {
        const x = num(), y = num(), size = num(), c = num(), weight = num();
        const s = rest();
        const blurred = beginShape();
        ctx.fillStyle = fillStyleFor(c);
        ctx.font = `${weight > 0 ? weight : 400} ${size}px "DejaVu Sans", system-ui, sans-serif`;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        ctx.fillText(s, x, y);
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'N': {
        const x = num(), y = num(), size = num(), c = num(), weight = num();
        // family and text are two ';'-separated fields with no space between them
        const family = rest();
        if (peek() === ';') p += 1;
        const s = rest();
        const blurred = beginShape();
        ctx.fillStyle = fillStyleFor(c);
        const fam = family.trim() ? `"${family}", ` : '';
        ctx.font = `${weight > 0 ? weight : 400} ${size}px ${fam}system-ui, sans-serif`;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        ctx.fillText(s, x, y);
        pendingGradient = null;
        clearBlur(blurred);
        break;
      }
      case 'I': {
        const x = num(), y = num(), w = num(), h = num();
        num(); // fit
        const file = rest().trim();
        const cached = images.get(file);
        if (cached && cached.complete && cached.naturalWidth) {
          ctx.drawImage(cached, x, y, w || cached.naturalWidth, h || cached.naturalHeight);
        } else if (!cached && typeof Image !== 'undefined') {
          const img = new Image();
          img.onload = () => { images.set(file, img); opts.onImage?.(); };
          img.onerror = () => { images.set(file, { complete: false, naturalWidth: 0 }); };
          images.set(file, img);
          img.src = file;
        }
        break;
      }
      case 'Y': {
        const id = num() | 0, x = num(), y = num(), w = num(), h = num();
        const layer = layers.get(id);
        if (layer) {
          const cv = layer.canvas;
          const dw = w > 0 ? w : cv.width;
          const dh = h > 0 ? h : cv.height;
          ctx.save();
          ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
          ctx.globalCompositeOperation = BLEND[blend] || 'source-over';
          ctx.drawImage(cv, x, y, dw, dh);
          ctx.restore();
        }
        break;
      }
      case 'X': {
        const id = num() | 0, pw = num() | 0, ph = num() | 0;
        const x = num(), y = num(), w = num(), h = num();
        const px = buffers.get(id);
        if (px && pw > 0 && ph > 0 && px.length >= pw * ph * 4) {
          const cv = document.createElement('canvas');
          cv.width = pw; cv.height = ph;
          const c2 = cv.getContext('2d');
          const img = c2.createImageData(pw, ph);
          img.data.set(px.subarray(0, pw * ph * 4));
          c2.putImageData(img, 0, 0);
          ctx.drawImage(cv, x, y, w > 0 ? w : pw, h > 0 ? h : ph);
        }
        break;
      }
      case 'V': {
        const x = num(), y = num(), scale = num(), sw = num(), c = num();
        const d = rest();
        const blurred = beginShape();
        ctx.save();
        ctx.translate(x, y);
        if (scale !== 1 && scale !== 0) ctx.scale(scale, scale);
        try {
          const path2 = new Path2D(d);
          if (sw > 0) {
            ctx.strokeStyle = fillStyleFor(c);
            ctx.lineWidth = sw;
            ctx.lineJoin = 'round'; ctx.lineCap = 'round';
            ctx.stroke(path2);
          } else {
            ctx.fillStyle = fillStyleFor(c);
            ctx.fill(path2, evenOdd ? 'evenodd' : 'nonzero');
          }
        } catch { unsupported += 1; }
        pendingGradient = null;
        ctx.restore();
        clearBlur(blurred);
        break;
      }
      case 'K': { const x = num(), y = num(), w = num(), h = num(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip(); break; }
      case 'k': num(); ctx.clip(evenOdd ? 'evenodd' : 'nonzero'); break; // clipPath: the path built so far
      case 'P': ctx.save(); alphaStack.push(alpha); blendStack.push(blend); depth += 1; break;
      case 'p': if (depth > 0) { ctx.restore(); alpha = alphaStack.pop(); blend = blendStack.pop(); depth -= 1; } break;
      case 'b': blend = num() | 0; break;
      case 't': { const x = num(), y = num(); ctx.translate(x, y); break; }
      case 's': { const x = num(), y = num(); ctx.scale(x, y === 0 ? x : y); break; }
      case 'o': ctx.rotate((num() * Math.PI) / 180); break;
      case 'O': alpha *= Math.max(0, Math.min(1, num())); break;
      default: break; // unknown verb: skipped, so a newer app still draws on an older host
    }
    // advance past this command's terminator
    skipSpace();
    if (p < n && cmds[p] === ';') p += 1;
  }

  while (depth-- > 0) ctx.restore();
  ctx.restore();
  return { ops, unsupported };
}

/** One offscreen bitmap an app draws into over time (`newLayer`). */
export function makeLayer(w, h) {
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(w));
  canvas.height = Math.max(1, Math.round(h));
  const ctx = canvas.getContext('2d');
  return { canvas, ctx, filters: [] };
}
