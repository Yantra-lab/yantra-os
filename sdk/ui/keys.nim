## Keys (KEY1): `onKey:` on any node runs for every key that goes down while the focus is in
## that node or under it (and on the window's root for every key), innermost first. Inside,
## `lastKey()` says which; `handled()` stops it there: no outer handler and no built-in action
## (so an app can take Enter, Escape or the arrows from a field).
##
##   column:
##     onKey:
##       let k = lastKey()
##       if k.ctrl and k == 'k': searching.set(true); handled()
##       elif k == keyDown: selected.set(selected.get + 1); handled()

import ../core/runtime

type KeyPress* = object
  code*: int32     ## SDL key code: a letter or digit is its lower-case ASCII code
  mods*: int32     ## modifier bits

const
  keyBackspace* = 8'i32
  keyTab* = 9'i32
  keyEnter* = 13'i32
  keyEscape* = 27'i32
  keySpace* = 32'i32
  keyDelete* = 127'i32
  keyRight* = 0x4000004f'i32
  keyLeft* = 0x40000050'i32
  keyDown* = 0x40000051'i32
  keyUp* = 0x40000052'i32
  keyHome* = 0x4000004a'i32
  keyPageUp* = 0x4000004b'i32
  keyEnd* = 0x4000004d'i32
  keyPageDown* = 0x4000004e'i32
  ## SDL scancodes for the non-ASCII keys an app has to name explicitly. The
  ## period is here because the Image menu's four numeric fields accept it
  ## (they are `type=number` and upstream's own tests type fractions like
  ## "50.5"), and a field that silently dropped the dot would refuse every
  ## fractional entry the Image > Resize dialog documents.
  keyPeriod* = 0x40000031'i32
  keyComma* = 0x40000033'i32

proc lastKey*(): KeyPress = KeyPress(code: yKey(0), mods: yKey(1))
proc handled*() = yKeyHandled()
proc shift*(k: KeyPress): bool = (k.mods and 0x0003) != 0
proc ctrl*(k: KeyPress): bool = (k.mods and 0x0CC0) != 0      ## Ctrl, or Cmd on a Mac
proc alt*(k: KeyPress): bool = (k.mods and 0x0300) != 0
proc `==`*(k: KeyPress; code: int32): bool = k.code == code
proc `==`*(k: KeyPress; c: char): bool =
  k.code == int32(ord(if c in {'A'..'Z'}: char(ord(c) + 32) else: c))
