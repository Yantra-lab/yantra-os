// Verify the mini-libc-backed Nim stdlib module actually EXECUTES correctly.
// A file size proves nothing. Every one of these numbers is checked against a
// value computed independently in JS.
import { readFileSync } from 'node:fs';

const buf = readFileSync(process.argv[2]);
const mod = await WebAssembly.compile(buf);

console.log('imports :', WebAssembly.Module.imports(mod).map(i => `${i.module}.${i.name}`).join(', ') || '(none)');
console.log('size    :', buf.length, 'bytes');

// The mini-libc routes every stdio write to the host through `yantra_log`. That is
// the capability boundary: the sandbox cannot print to a console, it can only ask
// the host to log. Capture the calls here so we can see what the app "printed".
const logLines = [];
const imports = {
  env: {
    yantra_log: (ptr, len) => {
      const mem = new Uint8Array(inst.exports.memory.buffer, ptr, len);
      logLines.push(new TextDecoder().decode(mem));
    },
  },
};

const inst = await WebAssembly.instantiate(mod, imports);
const { greet, formatNumber, sumSquares, useMath } = inst.exports;

const checks = [];
function check(label, got, want) {
  const ok = got === want;
  checks.push(ok);
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${label}: got ${got}, want ${want}`);
}

// "hello, sandbox #5 - built without a libc" -> 40 chars
// (hand-counted: 16 for "hello, sandbox #", 1 for the digit, 23 for the suffix)
check('greet(5) strlen', greet(5), 40);
check('greet(0) strlen', greet(0), 40);

// "pi is about " (12) + "3.14" (4) = 16  -- exercises the mini snprintf/$float
check('formatNumber(3.14)', formatNumber(3.14), 16);

// 1+4+9+16 = 30 -- exercises seq + heap allocation
check('sumSquares(4)', sumSquares(4), 30);
check('sumSquares(10)', sumSquares(10), 385);

// sqrt(16)=4 + pow(2,3)=8 + sin(0)=0 + cos(0)=1 = 13 -- exercises the math layer
check('useMath(16)', useMath(16), 13);

console.log('\nhost log captured:', logLines.length ? logLines : '(none - expected, nothing was printed)');
const passed = checks.filter(Boolean).length;
console.log(`\n=== ${passed}/${checks.length} checks passed ===`);
if (passed !== checks.length) process.exit(1);
