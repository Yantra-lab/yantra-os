## nimqt — marshaling between Nim values and QVariant.
##
## The Nim-side Variant ref owns one heap QVariant (created by the low-level
## binding constructors) and releases it exactly once in the destructor hook.

import QtCore

type
  VariantObj* = object
    h: ptr QVariant     ## heap QVariant owned when owns == true
    owns*: bool
  Variant* = ref VariantObj

proc `=destroy`*(v: var VariantObj) {.inline.} =
  ## Releases the owned heap QVariant exactly once. Declared immediately
  ## after the type so it wins the race against implicit destructor lifting.
  if v.owns and v.h != nil:
    v.owns = false
    variantDispose(v.h)
  v.h = nil

proc allocVar(h: ptr QVariant): Variant {.inline.} =
  new(result)
  result.h = h
  result.owns = true

proc newVariant*(): Variant {.inline.} =
  ## Invalid (empty) variant — mirrors QVariant() default construction.
  allocVar(qvariantNewInvalid())

proc newVariant*(b: bool): Variant {.inline.} = allocVar(qvariantNewBool(b))
proc newVariant*(i: int32): Variant {.inline.} = allocVar(qvariantNewInt(cint(i)))
proc newVariant*(i: int64): Variant {.inline.} = allocVar(qvariantNewLongLong(clonglong(i)))
proc newVariant*(u: uint32): Variant {.inline.} = allocVar(qvariantNewUInt(cuint(u)))
proc newVariant*(f: float64): Variant {.inline.} = allocVar(qvariantNewDouble(cdouble(f)))
proc newVariant*(f: float32): Variant {.inline.} = allocVar(qvariantNewFloat(cfloat(f)))

proc newVariantString*(s: string): Variant {.inline.} =
  let qs = toQString(s)
  result = allocVar(qvariantNewString(qs))

proc newVariant*(s: string): Variant {.inline.} = newVariantString(s)
  ## Convenience overload so `newVariant("text")` works alongside the numeric and
  ## bool overloads above. NOTE: this proc was originally found at the TOP of this
  ## file, above `import QtCore` and above the definition of `newVariantString`, so
  ## the module would not compile at all ("cannot export: QtCore" / undeclared
  ## identifiers). It has been moved here, where it belongs.

proc newVariantUrl*(u: QUrl): Variant {.inline.} = allocVar(qvariantNewUrl(u))

proc newVariantFromRaw*(h: QVariant): Variant {.inline.} =
  ## Wraps a fresh heap copy of the given low-level QVariant value.
  allocVar(qvariantCopyNew(h))

proc rawPtr*(v: Variant): ptr QVariant {.inline.} =
  ## Address of the owned heap QVariant (for ptr-based FFI calls).
  v.h

proc deref*(v: Variant): QVariant {.inline.} =
  ## The wrapped low-level QVariant value (a copy; safe to pass by value).
  v.h[]

# ---------------------------------------------------------------------------
# Accessors (each returns fresh copies; nothing aliases Qt memory)
# ---------------------------------------------------------------------------

proc isValid*(v: Variant): bool {.inline.} = variantIsValid(v.h[])
proc isNullV*(v: Variant): bool {.inline.} = variantIsNull(v.h[])

proc typeName*(v: Variant): string {.inline.} = variantTypeName(v.h[])
proc toString*(v: Variant): string {.inline.} = variantToString(v.h[]).toString()
proc toInt32*(v: Variant): int32 {.inline.} = int32(variantToInt(v.h[]))
proc toInt64V*(v: Variant): int64 {.inline.} = int64(variantToLongLong(v.h[]))
proc toUint32*(v: Variant): uint32 {.inline.} = uint32(variantToUInt(v.h[]))
proc toFloat*(v: Variant): float64 {.inline.} = variantToDouble(v.h[])
proc toBoolV*(v: Variant): bool {.inline.} = variantToBool(v.h[])

proc `$`*(v: Variant): string {.inline.} = v.toString()

proc fromVariant*[T](v: Variant; t: typedesc[T]): T =
  ## Typed extraction; compile error for unsupported types.
  when T is bool: v.toBoolV()
  elif T is int32: v.toInt32()
  elif T is int64: v.toInt64V()
  elif T is int: int(v.toInt64V())
  elif T is uint32: v.toUint32()
  elif T is float32: float32(v.toFloat())
  elif T is float64: v.toFloat()
  elif T is float: v.toFloat()
  elif T is string: v.toString()
  else:
    {.error: "nimqt.fromVariant: unsupported target type " & $T.}

# ---------------------------------------------------------------------------
# Destructor declared above (right after the type) to win the binding race
# against implicit lifting.
# ---------------------------------------------------------------------------

export QtCore
