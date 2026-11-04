## The C math library, which an app's `std/math` calls into (`sqrt`, `pow`,
## `sin`...): pure functions on numbers, safe for any sandbox. Both hosts, the
## engine (host.nim) and the Vajra runtime (vajra/runtime.nim), offer exactly
## this table, so an app computes the same everywhere.

import std/math
import ../libs/nimwasmtime/src/nimwasmtime/raw

type MathImport* = tuple[name: string; arity: int; wide: bool; cb: WasmFuncCallback]
  ## `arity` numbers in, one out; `wide` is float64 (`sqrt`), else float32 (`sqrtf`)

template math1(name, fn: untyped; T: typedesc; field: untyped) =
  proc name(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
      nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
    let a = cast[ptr UncheckedArray[WasmVal]](args)
    var v = a[0]
    v.`of`.field = T(fn(a[0].`of`.field))
    cast[ptr UncheckedArray[WasmVal]](results)[0] = v
    nil

template math2(name, fn: untyped; T: typedesc; field: untyped) =
  proc name(env: pointer; caller: ptr WasmCaller; args: ptr WasmVal;
      nargs: csize_t; results: ptr WasmVal; nresults: csize_t): ptr WasmTrap {.cdecl.} =
    let a = cast[ptr UncheckedArray[WasmVal]](args)
    var v = a[0]
    v.`of`.field = T(fn(a[0].`of`.field, a[1].`of`.field))
    cast[ptr UncheckedArray[WasmVal]](results)[0] = v
    nil

math1(sqrtf, sqrt, float32, f32);   math1(sqrt64, sqrt, float64, f64)
math1(cbrtf, cbrt, float32, f32);   math1(cbrt64, cbrt, float64, f64)
math1(sinf, sin, float32, f32);     math1(sin64, sin, float64, f64)
math1(cosf, cos, float32, f32);     math1(cos64, cos, float64, f64)
math1(tanf, tan, float32, f32);     math1(tan64, tan, float64, f64)
math1(asinf, arcsin, float32, f32); math1(asin64, arcsin, float64, f64)
math1(acosf, arccos, float32, f32); math1(acos64, arccos, float64, f64)
math1(atanf, arctan, float32, f32); math1(atan64, arctan, float64, f64)
math1(sinhf, sinh, float32, f32);   math1(sinh64, sinh, float64, f64)
math1(coshf, cosh, float32, f32);   math1(cosh64, cosh, float64, f64)
math1(tanhf, tanh, float32, f32);   math1(tanh64, tanh, float64, f64)
math1(expf, exp, float32, f32);     math1(exp64, exp, float64, f64)
math1(logf, ln, float32, f32);      math1(log64, ln, float64, f64)
math1(log2f, log2, float32, f32);   math1(log2_64, log2, float64, f64)
math1(log10f, log10, float32, f32); math1(log10_64, log10, float64, f64)
math1(floorf, floor, float32, f32); math1(floor64, floor, float64, f64)
math1(ceilf, ceil, float32, f32);   math1(ceil64, ceil, float64, f64)
math1(roundf, round, float32, f32); math1(round64, round, float64, f64)
math1(truncf, trunc, float32, f32); math1(trunc64, trunc, float64, f64)
math1(fabsf, abs, float32, f32);    math1(fabs64, abs, float64, f64)
math2(powf, pow, float32, f32);     math2(pow64, pow, float64, f64)
math2(atan2f, arctan2, float32, f32); math2(atan2_64, arctan2, float64, f64)
math2(fmodf, `mod`, float32, f32);  math2(fmod64, `mod`, float64, f64)
math2(hypotf, hypot, float32, f32); math2(hypot64, hypot, float64, f64)
math2(copysignf, copySign, float32, f32); math2(copysign64, copySign, float64, f64)

proc mathImports*(): seq[MathImport] = @[
  ("sqrtf", 1, false, sqrtf), ("sqrt", 1, true, sqrt64), ("cbrtf", 1, false, cbrtf), ("cbrt", 1, true, cbrt64),
  ("sinf", 1, false, sinf), ("sin", 1, true, sin64), ("cosf", 1, false, cosf), ("cos", 1, true, cos64),
  ("tanf", 1, false, tanf), ("tan", 1, true, tan64), ("asinf", 1, false, asinf), ("asin", 1, true, asin64),
  ("acosf", 1, false, acosf), ("acos", 1, true, acos64), ("atanf", 1, false, atanf), ("atan", 1, true, atan64),
  ("sinhf", 1, false, sinhf), ("sinh", 1, true, sinh64), ("coshf", 1, false, coshf), ("cosh", 1, true, cosh64),
  ("tanhf", 1, false, tanhf), ("tanh", 1, true, tanh64), ("expf", 1, false, expf), ("exp", 1, true, exp64),
  ("logf", 1, false, logf), ("log", 1, true, log64), ("log2f", 1, false, log2f), ("log2", 1, true, log2_64),
  ("log10f", 1, false, log10f), ("log10", 1, true, log10_64), ("floorf", 1, false, floorf), ("floor", 1, true, floor64),
  ("ceilf", 1, false, ceilf), ("ceil", 1, true, ceil64), ("roundf", 1, false, roundf), ("round", 1, true, round64),
  ("truncf", 1, false, truncf), ("trunc", 1, true, trunc64), ("fabsf", 1, false, fabsf), ("fabs", 1, true, fabs64),
  ("powf", 2, false, powf), ("pow", 2, true, pow64), ("atan2f", 2, false, atan2f), ("atan2", 2, true, atan2_64),
  ("fmodf", 2, false, fmodf), ("fmod", 2, true, fmod64), ("hypotf", 2, false, hypotf), ("hypot", 2, true, hypot64),
  ("copysignf", 2, false, copysignf), ("copysign", 2, true, copysign64)]
