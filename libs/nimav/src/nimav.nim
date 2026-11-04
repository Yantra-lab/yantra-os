## nimav — video in and out for Yantra through FFmpeg's libraries (libavformat,
## libavcodec, libswscale, libavutil; MSYS2 `mingw-w64-x86_64-ffmpeg`). Linked, not run
## as a program. Today: encode engine frames to a file, and probe a file.

{.compile: "av_shim.c".}
{.passL: "-lavdevice -lavformat -lavcodec -lswscale -lswresample -lavutil -lpthread".}

type
  Encoder* = object
    h: pointer
    width*, height*, fps*: int
    frames*: int
  VideoInfo* = object
    frames*, width*, height*: int
    seconds*: float
    codec*: string
  AvError* = object of CatchableError

proc yav_open(path: cstring; w, h, fps, crf: cint; err: cstring; errcap: cint): pointer {.importc, cdecl.}
proc yav_frame(h: pointer; bgra: pointer; stride: cint): cint {.importc, cdecl.}
proc yav_close(h: pointer): cint {.importc, cdecl.}
proc yav_probe(path: cstring; frames, w, h: ptr cint; seconds: ptr cdouble; codec: cstring; cap: cint): cint {.importc, cdecl.}

proc openEncoder*(path: string; width, height, fps: int; crf = 18): Encoder =
  ## A video file to write frames into; the container follows the extension (.mp4, .mov,
  ## .mkv, .webm). Width and height must be even for H.264.
  var err = newString(256)
  let h = yav_open(path.cstring, cint(width), cint(height), cint(fps), cint(crf), err.cstring, cint(err.len))
  if h == nil:
    raise newException(AvError, "cannot write " & path & ": " & $err.cstring)
  Encoder(h: h, width: width, height: height, fps: fps)

proc addFrame*(e: var Encoder; bgra: pointer; stride: int) =
  ## One frame of BGRA pixels, `stride` bytes per row.
  if yav_frame(e.h, bgra, cint(stride)) < 0: raise newException(AvError, "encoding a frame failed")
  inc e.frames

proc close*(e: var Encoder) =
  ## Finishes the file. Always call it: the file is not playable before.
  if e.h == nil: return
  let r = yav_close(e.h)
  e.h = nil
  if r < 0: raise newException(AvError, "finishing the video failed")

proc probe*(path: string): VideoInfo =
  ## What a video file holds (frames counted by reading every packet).
  var f, w, h: cint
  var s: cdouble
  var codec = newString(64)
  if yav_probe(path.cstring, addr f, addr w, addr h, addr s, codec.cstring, cint(codec.len)) != 0:
    raise newException(AvError, "cannot read " & path)
  VideoInfo(frames: int(f), width: int(w), height: int(h), seconds: float(s), codec: $codec.cstring)

# --- decoding ------------------------------------------------------------------------

type Decoder* = ref object
  h: pointer
  width*, height*: int
  seconds*: float

proc yav_dec_open(path: cstring; w, h: ptr cint; seconds: ptr cdouble): pointer {.importc, cdecl.}
proc yav_dec_frame(h: pointer; t: cdouble; outp: pointer; outW, outH: cint): cint {.importc, cdecl.}
proc yav_dec_close(h: pointer) {.importc, cdecl.}

proc openDecoder*(path: string): Decoder =
  ## A video file to read frames from; nil if it cannot be opened.
  var w, h: cint
  var s: cdouble
  let p = yav_dec_open(path.cstring, addr w, addr h, addr s)
  if p == nil: return nil
  Decoder(h: p, width: int(w), height: int(h), seconds: float(s))

proc frameAt*(d: Decoder; seconds: float; outp: pointer; outW, outH: int): bool =
  ## The frame showing at `seconds`, scaled to outW x outH BGRA into `outp`.
  ## False past the end. Moving forward is cheap; jumping back seeks.
  d != nil and d.h != nil and yav_dec_frame(d.h, seconds, outp, cint(outW), cint(outH)) == 1

proc close*(d: Decoder) =
  if d != nil and d.h != nil:
    yav_dec_close(d.h)
    d.h = nil

# --- playing (P3): a decode thread per file; audio drives the clock -------------------------

type MediaPlayer* = ref object
  h: pointer
  hasVideo*, hasAudio*: bool

proc yav_play_open(path: cstring; w, h, audio: cint): pointer {.importc, cdecl.}
proc yav_play_close(h: pointer) {.importc, cdecl.}
proc yav_play_pause(h: pointer; paused: cint) {.importc, cdecl.}
proc yav_play_seek(h: pointer; t: cdouble) {.importc, cdecl.}
proc yav_play_set(h: pointer; loop: cint; volume: cfloat; w, hgt: cint) {.importc, cdecl.}
proc yav_play_video(h: pointer; outp: pointer; cap: cint; w, hgt: ptr cint): cint {.importc, cdecl.}
proc yav_play_status(h: pointer; clock, dur: ptr cdouble; ended, hasVideo, hasAudio: ptr cint) {.importc, cdecl.}
proc yav_play_audio(h: pointer; outp: ptr cfloat; frames: cint) {.importc, cdecl.}
proc yav_waveform(path: cstring; n: cint; peaks: ptr cfloat; seconds: ptr cdouble): cint {.importc, cdecl.}

proc openPlayer*(path: string; width, height: int; audio: bool): MediaPlayer =
  ## Opens a video or audio file, paused at 0, on its own decode thread. Video frames come
  ## at width x height (BGRA). `audio`: a device will pull its sound (`audioPull`), which
  ## then drives the clock; otherwise sound is skipped and the wall clock drives. nil if
  ## the file has nothing playable.
  let h = yav_play_open(path.cstring, cint(width), cint(height), cint(ord(audio)))
  if h == nil: return nil
  result = MediaPlayer(h: h)
  var c, d: cdouble
  var e, v, a: cint
  yav_play_status(h, addr c, addr d, addr e, addr v, addr a)
  result.hasVideo = v != 0
  result.hasAudio = a != 0

proc close*(p: MediaPlayer) =
  ## Stops its thread. Remove it from the audio device first.
  if p != nil and p.h != nil:
    yav_play_close(p.h)
    p.h = nil
proc setPaused*(p: MediaPlayer; paused: bool) = (if p != nil and p.h != nil: yav_play_pause(p.h, cint(ord(paused))))
proc seek*(p: MediaPlayer; seconds: float) = (if p != nil and p.h != nil: yav_play_seek(p.h, seconds))
proc configure*(p: MediaPlayer; loop: bool; volume: float32; width, height: int) =
  ## Loop at the end, the volume (0 = muted), and the size the next video frames come at.
  if p != nil and p.h != nil: yav_play_set(p.h, cint(ord(loop)), volume, cint(width), cint(height))
proc nextFrame*(p: MediaPlayer; outp: pointer; cap: int; w, h: var int): bool =
  ## The frame due now into `outp` (cap bytes); false if the one shown is still current.
  if p == nil or p.h == nil: return false
  var cw, ch: cint
  result = yav_play_video(p.h, outp, cint(cap), addr cw, addr ch) == 1
  if result: (w = int(cw); h = int(ch))
proc status*(p: MediaPlayer): tuple[time, duration: float, ended: bool] =
  if p == nil or p.h == nil: return
  var c, d: cdouble
  var e, v, a: cint
  yav_play_status(p.h, addr c, addr d, addr e, addr v, addr a)
  (float(c), float(d), e != 0)
proc audioPull*(): pointer = cast[pointer](yav_play_audio)
  ## The C function an audio device calls with the player's handle (`handle`).
proc handle*(p: MediaPlayer): pointer = p.h

proc waveform*(path: string; buckets: int): tuple[peaks: seq[float32], seconds: float] =
  ## The peak loudness (0..1) of each of `buckets` equal slices of the file's sound.
  if buckets <= 0: return
  result.peaks = newSeq[float32](buckets)
  var s: cdouble
  if yav_waveform(path.cstring, cint(buckets), cast[ptr cfloat](addr result.peaks[0]), addr s) == 0:
    result.peaks.setLen(0)
  result.seconds = float(s)

proc yav_duration(path: cstring): cdouble {.importc, cdecl.}
proc mediaSeconds*(path: string): float = float(yav_duration(path.cstring))
  ## A video or audio file's length (0 unknown, -1 not a media file). Opens and closes it.

# --- recording (Q2) --------------------------------------------------------------------------
type Recorder* = ref object
  h: pointer
proc yav_rec_open(path: cstring; rate, ch: cint; err: cstring; errcap: cint): pointer {.importc, cdecl.}
proc yav_rec_write(h: pointer; s: ptr cfloat; frames: cint): cint {.importc, cdecl.}
proc yav_rec_close(h: pointer): cint {.importc, cdecl.}
proc openRecorder*(path: string; rate, channels: int; err: var string): Recorder =
  ## A new audio file: Opus in OGG for .ogg/.opus, AAC for .m4a. nil (and `err`) if it can't.
  var e = newString(256)
  let h = yav_rec_open(path.cstring, cint(rate), cint(channels), e.cstring, 256)
  if h == nil:
    err = $e.cstring
    return nil
  Recorder(h: h)
proc write*(r: Recorder; samples: openArray[float32]; frames: int): bool =
  r != nil and r.h != nil and frames > 0 and yav_rec_write(r.h, unsafeAddr samples[0], cint(frames)) == 0
proc finish*(r: Recorder): bool =
  ## Flushes and closes the file.
  if r == nil or r.h == nil: return false
  result = yav_rec_close(r.h) == 0
  r.h = nil

# --- Opus frames for calls (Q11) ---------------------------------------------------------------
type OpusCodec* = ref object
  h: pointer
proc yav_opus_encoder(bitrate: cint): pointer {.importc, cdecl.}
proc yav_opus_encode(h: pointer; pcm: ptr cfloat; n: cint; outp: pointer; cap: cint): cint {.importc, cdecl.}
proc yav_opus_decoder(): pointer {.importc, cdecl.}
proc yav_opus_decode(h: pointer; data: pointer; len: cint; outp: ptr cfloat; cap: cint): cint {.importc, cdecl.}
proc yav_opus_close(h: pointer) {.importc, cdecl.}
proc opusEncoder*(bitrate = 32000): OpusCodec =
  ## Voice: 20 ms frames of 48 kHz mono float in, Opus packets out. nil without an Opus encoder.
  let h = yav_opus_encoder(cint(bitrate))
  if h != nil: OpusCodec(h: h) else: nil
proc opusDecoder*(): OpusCodec =
  let h = yav_opus_decoder()
  if h != nil: OpusCodec(h: h) else: nil
proc encode*(c: OpusCodec; pcm: openArray[float32]; outp: var array[1500, uint8]): int =
  ## 960 samples -> the packet's length in `outp` (0: none yet).
  int(yav_opus_encode(c.h, unsafeAddr pcm[0], cint(pcm.len), addr outp[0], 1500))
proc decode*(c: OpusCodec; data: openArray[uint8]; n: int; outp: var seq[float32]): int =
  ## One packet -> stereo float frames at the start of `outp` (sized for 120 ms): how many.
  if outp.len < 48000 * 2 div 8: outp.setLen(48000 * 2 div 8)
  int(yav_opus_decode(c.h, unsafeAddr data[0], cint(n), addr outp[0], cint(outp.len div 2)))
proc close*(c: OpusCodec) = (if c != nil and c.h != nil: (yav_opus_close(c.h); c.h = nil))
