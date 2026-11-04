## nimrtc — voice calls over WebRTC through libdatachannel (Q11; MSYS2
## `mingw-w64-x86_64-libdatachannel`). One peer connection, one Opus audio track; the app
## carries the signaling (SDP and ICE candidates) to the other side itself.
when defined(yantraRtc):
  {.compile: "rtc_shim.c".}
  {.passL: "-ldatachannel".}
else:
  {.compile: "rtc_stub.c".}    # no libdatachannel on this build: calls never start

type Call* = ref object
  h: pointer

proc yrtc_call(offerer: cint; ice: cstring): pointer {.importc, cdecl.}
proc yrtc_remote(c: pointer; typ, sdp: cstring): cint {.importc, cdecl.}
proc yrtc_candidate(c: pointer; cand, mid: cstring): cint {.importc, cdecl.}
proc yrtc_next_event(c: pointer): cstring {.importc, cdecl.}
proc yrtc_free(s: cstring) {.importc, cdecl.}
proc yrtc_state(c: pointer): cint {.importc, cdecl.}
proc yrtc_send_opus(c: pointer; data: pointer; len, samples: cint): cint {.importc, cdecl.}
proc yrtc_next_packet(c: pointer; outp: pointer; cap: cint): cint {.importc, cdecl.}
proc yrtc_play_push(c: pointer; s: ptr cfloat; frames: cint) {.importc, cdecl.}
proc yrtc_play_pull(user: pointer; outp: ptr cfloat; frames: cint) {.importc, cdecl.}
proc yrtc_close(c: pointer) {.importc, cdecl.}

proc newCall*(offerer: bool; iceServers = ""): Call =
  ## A call; the offerer's offer comes out of `nextEvent`. iceServers: "stun:…" lines.
  let h = yrtc_call(cint(ord(offerer)), iceServers.cstring)
  if h != nil: Call(h: h) else: nil
proc setRemote*(c: Call; typ, sdp: string): bool = yrtc_remote(c.h, typ.cstring, sdp.cstring) == 1
proc addCandidate*(c: Call; cand, mid: string): bool = yrtc_candidate(c.h, cand.cstring, mid.cstring) == 1
proc nextEvent*(c: Call): string =
  ## "sdp\ttype\tsdp", "cand\tmid\tcandidate", "state\tn\t" (2 connected, 3 disconnected,
  ## 4 failed, 5 closed), or "" when there is none.
  let s = yrtc_next_event(c.h)
  if s == nil: return ""
  result = $s
  yrtc_free(s)
proc state*(c: Call): int = int(yrtc_state(c.h))
proc sendOpus*(c: Call; data: openArray[uint8]; n, samples: int): bool =
  n > 0 and yrtc_send_opus(c.h, unsafeAddr data[0], cint(n), cint(samples)) == 1
proc nextPacket*(c: Call; outp: var array[1500, uint8]): int = int(yrtc_next_packet(c.h, addr outp[0], 1500))
proc playPush*(c: Call; stereo: openArray[float32]; frames: int) =
  if frames > 0: yrtc_play_push(c.h, unsafeAddr stereo[0], cint(frames))
proc playPull*(): pointer = cast[pointer](yrtc_play_pull)   ## the audio device source for `handle`
proc handle*(c: Call): pointer = c.h
proc close*(c: Call) = (if c != nil and c.h != nil: (yrtc_close(c.h); c.h = nil))
