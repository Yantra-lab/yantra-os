## The system: battery, volume, network — what a control centre shows. The app must declare
## `needs("system")`. Every reading is -1 (or "") when this machine does not have or tell it:
## show nothing then, never a made-up value. Windows and Linux (host/sys_win.c, sys_linux.c).

import runtime

proc ySys(op, arg: int32): int32 {.importc: "y_sys", cdecl.}
proc ySysText(op, buf, cap: int32): int32 {.importc: "y_sys_text", cdecl.}

type NetKind* = enum
  netUnknown = -1, netOffline = 0, netWired = 1, netWifi = 2

proc battery*(): int = int(ySys(1, 0))            ## percent 0-100, or -1 (no battery)
proc charging*(): int = int(ySys(2, 0))           ## 1 on mains power, 0 on battery, -1 unknown
proc volume*(): int = int(ySys(3, 0))             ## the output's volume 0-100, or -1
proc setVolume*(pct: int): bool = ySys(4, int32(clamp(pct, 0, 100))) == 1
proc muted*(): int = int(ySys(5, 0))              ## 1 muted, 0 not, -1 unknown
proc setMuted*(on: bool): bool = ySys(6, int32(ord(on))) == 1
proc netKind*(): NetKind =
  let v = ySys(7, 0)
  if v in 0'i32 .. 2'i32: NetKind(v) else: netUnknown

proc sysText(op: int32): string =
  let n = ySysText(op, 0, 0)
  if n <= 0: return ""
  result = newString(n)
  discard ySysText(op, cast[int32](cast[uint](addr result[0])), n)

proc wifiName*(): string = sysText(1)   ## the connected Wi-Fi network's name, or ""
proc userName*(): string = sysText(2)   ## who is signed in to this computer, or ""
proc hostName*(): string = sysText(3)   ## this computer's name, or ""
proc osName*(): string = sysText(4)     ## "Windows", or the Linux distribution's name, or ""

proc uptime*(): int = int(ySys(8, 0))       ## seconds since the machine started, or -1
proc cpuUse*(): int = int(ySys(9, 0))       ## CPU use 0-100 since the last reading, or -1
proc memoryUse*(): int = int(ySys(10, 0))   ## memory in use 0-100, or -1
proc diskUse*(): int = int(ySys(11, 0))     ## the system disk's use 0-100, or -1
