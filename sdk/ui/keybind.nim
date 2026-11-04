## Keybind chords, conflicts, resets, and honest serialisation of settings state.
##
## Pure logic: no imports, so it compiles and runs headless in the gate. The picker UI
## (apps/desktop) renders whatever this returns. Two rules the whole module exists to keep:
##
## 1. A chord is shown to a person, never as a number: `formatChord` gives "Ctrl+Shift+K".
## 2. Settings pages never present injected state as detected: every reading carries a
##    `Provenance`, and only `pvDetected` may claim hardware was really read.
##
## The key codes below mirror sdk/ui/keys.nim (SDL scancode + 0x4000_0000 for non-ASCII).
## They are repeated rather than imported so this module stays dependency-free; if a code
## moves there, move it here too.

import std/strutils

type
  Chord* = object
    code*: int32               ## SDL key code; a letter/digit is its lower-case ASCII
    ctrl*, shift*, alt*, super*: bool

  ScopeKind* = enum
    skGlobal,                  ## fires wherever Yantra has focus
    skWindow                   ## fires only in `owner`; the same chord may exist elsewhere

  Binding* = object
    id*: string                ## the action, e.g. "tiling.split"
    chord*: Chord              ## the live binding
    deflt*: Chord              ## what reset restores
    scopeKind*: ScopeKind
    owner*: string             ## "" when global; the window id when window-local

  Provenance* = enum
    pvInjected,                ## a value this page made up to fill the field in
    pvReported,                ## the shell told us; we did not read hardware ourselves
    pvDetected                 ## read from the actual device

  NetworkReading* = object
    ssid*, security*: string
    rssi*: int                 ## dBm; meaningless unless `source` is pvDetected
    source*: Provenance

  WifiProfile* = object
    ssid*, password*, security*: string

const
  namedCodes* = [8'i32, 9'i32, 13'i32, 27'i32, 32'i32, 127'i32,
                 0x4000004f'i32, 0x40000050'i32, 0x40000051'i32, 0x40000052'i32,
                 0x4000004a'i32, 0x4000004b'i32, 0x4000004d'i32, 0x4000004e'i32,
                 0x40000031'i32, 0x40000033'i32]
  namedNames* = ["Backspace", "Tab", "Enter", "Escape", "Space", "Delete",
                 "Right", "Left", "Down", "Up", "Home", "PageUp", "End", "PageDown",
                 "Period", "Comma"]
  fKeyBase* = 0x4000003a'i32  ## F1
  fKeyLast* = 0x40000045'i32  ## F12
  redacted* = "<redacted>"    ## the only thing a serialised password may ever be
  keyEscapeCode* = 27'i32      ## the Escape key; never storable as a binding

proc keyName*(code: int32): string =
  ## A name a person can read. Unknown codes stay explicit rather than going blank.
  for i, c in namedCodes:
    if c == code: return namedNames[i]
  if code >= fKeyBase and code <= fKeyLast: return "F" & $(code - fKeyBase + 1)
  if code >= int32('a') and code <= int32('z'): return $char(code).toUpperAscii
  if code >= int32('0') and code <= int32('9'): return $char(code)
  "Key(" & $code & ")"

proc formatChord*(c: Chord): string =
  ## "Ctrl+Shift+K". Modifiers in a fixed order so two equal chords always read the same.
  var parts: seq[string] = @[]
  if c.ctrl: parts.add "Ctrl"
  if c.shift: parts.add "Shift"
  if c.alt: parts.add "Alt"
  if c.super: parts.add "Super"
  parts.add keyName(c.code)
  for i, p in parts:
    if i > 0: result.add "+"
    result.add p

proc sameChord*(a, b: Chord): bool =
  result = a.code == b.code and a.ctrl == b.ctrl and a.shift == b.shift and
           a.alt == b.alt and a.super == b.super

proc scopeLabel*(b: Binding): string =
  if b.scopeKind == skGlobal: "Global"
  else: "This window" & (if b.owner.len > 0: " (" & b.owner & ")" else: "")

proc clash*(a, b: Binding): bool =
  ## True when these two cannot both fire: same chord, and overlapping scopes.
  if not sameChord(a.chord, b.chord): return false
  if a.scopeKind == skGlobal and b.scopeKind == skGlobal: return true
  a.scopeKind == skWindow and b.scopeKind == skWindow and a.owner == b.owner

proc conflictIds*(bs: seq[Binding]; i: int): seq[string] =
  ## The ids already using binding `i`'s chord. Empty when it is free.
  if i < 0 or i >= bs.len: return
  for k, b in bs:
    if k != i and clash(bs[i], b): result.add b.id

proc tryBind*(bs: var seq[Binding]; i: int; c: Chord): (bool, seq[string]) =
  ## Rebind binding `i` to `c`. On a clash it returns (false, the clashing ids) and changes
  ## nothing, so the picker can show the conflict instead of silently stealing the key.
  if i < 0 or i >= bs.len: return (false, @[])
  var probe = bs[i]
  probe.chord = c
  for k, b in bs:
    if k != i and clash(probe, b):
      return (false, @[b.id])
  bs[i].chord = c
  (true, @[])

proc resetBinding*(bs: var seq[Binding]; i: int) =
  if i >= 0 and i < bs.len: bs[i].chord = bs[i].deflt

proc resetAll*(bs: var seq[Binding]) =
  for b in bs.mitems: b.chord = b.deflt

# ---- honest hardware ----------------------------------------------------------------------------

proc configuredReading*(ssid, security: string): NetworkReading =
  ## A reading for a settings page with no device behind it. Stamped pvInjected on purpose,
  ## so nothing downstream can present it as something the hardware reported.
  NetworkReading(ssid: ssid, rssi: 0, security: security, source: pvInjected)

proc claimsHardware*(r: NetworkReading): bool = r.source == pvDetected

proc readingLabel*(r: NetworkReading): string =
  case r.source
  of pvDetected: r.ssid & " · detected"
  of pvReported: r.ssid & " · reported by the shell"
  of pvInjected: r.ssid & " · configured, not detected"

proc serializeWifi*(ps: seq[WifiProfile]): string =
  ## Serialises profiles for saving or logging. The password is replaced by `redacted`
  ## structurally: it is never interpolated, so no code path can leak it.
  result = "wifi:["
  for i, p in ps:
    if i > 0: result.add ","
    result.add "{" & p.ssid & "|" & p.security & "|password=" & redacted & "}"
  result.add "]"
