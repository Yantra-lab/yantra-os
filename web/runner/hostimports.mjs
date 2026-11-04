// web/runner/hostimports.mjs — the host contract, as the web runner serves it.
//
// The native host (host/host.nim + host/sutra/runtime.nim) hands an app a fixed
// table of imports: the y_* UI calls, the plain C math library (host/wasmmath.nim),
// and the Sutra runtime (print, exit, clock, clock zone, route, query). A module
// that imports one the host does not provide will not link, in a browser as on
// the engine.
//
// This file is the browser's half of that contract. It is deliberately small and
// says what it cannot do: there is no Postgres in a browser tab, so `sutra_query`
// answers with the same "no database" marker the SDK itself uses for a program
// built without one (sdk/sutra/sutra/prelude.nim:67), and the app falls back to
// its empty state instead of pretending it has rows.

// An empty result set is the wire format's way of saying "no rows": rows are
// separated by \x1e, fields by \x1f, and an error starts with \x15
// (sdk/sutra/sutra/prelude.nim:58). The browser has no Postgres, so every table
// it is asked about is empty — the app draws its empty state instead of failing.
const NO_ROWS = '';

// `nim_exit` is a non-local exit, not a function that returns to the guest.
// The native host raises its distinguished "vajra: exit" trap here too.
export class YantraExit extends Error {
  constructor(code) {
    super(`module exited with code ${code | 0}`);
    this.name = 'YantraExit';
    this.code = code | 0;
  }
}

// A table with no rows still answers `select count(*)`: zero, as one row with one
// field. Encoded the way the SDK reads it ( between rows,  between fields).
function respond(sql) {
  const s = sql.trim().toLowerCase();
  if (/^select\s+count\s*\(\*?\)/.test(s)) return '0';
  if (/^select\s+coalesce\(atlas\.my_zone/.test(s)) return '';
  return NO_ROWS;
}

// host/wasmmath.nim mathImports(): same names, same arities, same widths.
const MATH1_F32 = ['sqrtf', 'cbrtf', 'sinf', 'cosf', 'tanf', 'asinf', 'acosf', 'atanf', 'sinhf',
  'coshf', 'tanhf', 'expf', 'logf', 'log2f', 'log10f', 'floorf', 'ceilf', 'roundf', 'truncf', 'fabsf'];
const MATH1_F64 = ['sqrt', 'cbrt', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh',
  'cosh', 'tanh', 'exp', 'log', 'log2', 'log10', 'floor', 'ceil', 'round', 'trunc', 'fabs'];
const MATH2_F32 = ['powf', 'atan2f', 'fmodf', 'hypotf', 'copysignf'];
const MATH2_F64 = ['pow', 'atan2', 'fmod', 'hypot', 'copysign'];

const FN = {
  sqrt: Math.sqrt, cbrt: Math.cbrt, sin: Math.sin, cos: Math.cos, tan: Math.tan,
  asin: Math.asin, acos: Math.acos, atan: Math.atan, sinh: Math.sinh, cosh: Math.cosh,
  tanh: Math.tanh, exp: Math.exp, log: Math.log, log2: Math.log2, log10: Math.log10,
  floor: Math.floor, ceil: Math.ceil, round: Math.round, trunc: Math.trunc, fabs: Math.abs,
  pow: Math.pow, atan2: Math.atan2, fmod: (a, b) => a % b, hypot: Math.hypot,
  copysign: (a, b) => (Math.sign(b) < 0 ? -Math.abs(a) : Math.abs(a)),
};

/**
 * The imports a Sutra-era module asks for, served honestly in a browser.
 * @param {object} runner the YantraWebRunner (needs .memory, .logs, ._read/_write)
 */
export function hostImports(runner) {
  const env = {};

  // ---- the C math library (f32 variants round, as float does) ----
  for (const name of MATH1_F32) {
    const f = FN[name.replace(/f$/, '')];
    env[name] = (a) => Math.fround(f(a));
  }
  for (const name of MATH1_F64) env[name] = FN[name];
  for (const name of MATH2_F32) {
    const f = FN[name.replace(/f$/, '')];
    env[name] = (a, b) => Math.fround(f(a, b));
  }
  for (const name of MATH2_F64) env[name] = FN[name];

  // ---- the Sutra runtime ----
  let pending = '';
  const params = [];

  const readStr = (ptr, len) => runner._readStr(ptr, len);
  const writeStr = (ptr, cap, s) => runner._writeStr(ptr, cap, s);

  env.nim_write = (fd, ptr, len) => {
    runner.logs.push(readStr(ptr, len));
    return len;
  };
  env.nim_exit = (code) => {
    runner.exitCode = code | 0;
    throw new YantraExit(code);
  };

  // No Postgres in a tab: an empty table, not an invented one.
  env.sutra_query = (sqlPtr, sqlLen, argsPtr, argsLen) => {
    runner.lastQuery = { sql: readStr(sqlPtr, sqlLen), args: readStr(argsPtr, argsLen) };
    (runner.queries || (runner.queries = [])).push(runner.lastQuery);
    return (pending = respond(runner.lastQuery.sql)).length;
  };
  env.sutra_fetch = () => (pending = '\x15this runner has no network for the app').length;
  env.sutra_take = (dst, cap) => {
    const n = writeStr(dst, cap, pending);
    pending = '';
    return n;
  };
  env.sutra_now = () => BigInt(Date.now()) * 1000n;
  env.sutra_utc_offset = () => -new Date().getTimezoneOffset() * 60;
  env.sutra_location = (dst, cap) => writeStr(dst, cap, runner.location || '/');
  env.sutra_navigated = (ptr, len) => { runner.location = readStr(ptr, len); };
  env.sutra_param = (ptr, len) => {
    const f = readStr(ptr, len).split('\x1f');
    if (f.length === 5) params.push({ view: f[0], name: f[1], value: f[2], lo: f[3], hi: f[4] });
  };
  env.sutra_param_value = (i) => {
    pending = params[i] && params[i].value != null ? params[i].value : '';
    return pending.length;
  };

  // ---- pixel buffers (scene3d's newBuffer + setData) ----
  env.y_buf = (id, ptr, len) => {
    if (!runner.buffers) runner.buffers = new Map();
    runner.buffers.set(id | 0, len > 0 ? new Uint8Array(runner.memory.buffer, ptr, len).slice() : new Uint8Array(0));
  };

  return env;
}
