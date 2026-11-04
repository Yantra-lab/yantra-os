import std/[os, strutils]

const currentDir = currentSourcePath().parentDir().replace('\\', '/')
static:
  if not fileExists(currentDir & "/../build/libminiaudio.a"):
    discard gorge("cmd /c if not exist \"" & currentDir.replace('/', '\\') & "\\..\\build\" mkdir \"" & currentDir.replace('/', '\\') & "\\..\\build\"")
    discard gorge("gcc -O2 -c -DMINIAUDIO_IMPLEMENTATION -x c \"" & currentDir & "/../../../third_party/miniaudio/miniaudio.h\" -o \"" & currentDir & "/../build/miniaudio.o\" && ar rcs \"" & currentDir & "/../build/libminiaudio.a\" \"" & currentDir & "/../build/miniaudio.o\"")
{.passC: "-I" & currentDir & "/../../../third_party/miniaudio".}
{.passL: currentDir & "/../build/libminiaudio.a".}

{.emit: """
#include "miniaudio.h"
#include <stdlib.h>
ma_waveform* y_w_new(void) { return (ma_waveform*)calloc(1, sizeof(ma_waveform)); }
void y_w_del(ma_waveform* p) { if (p) { ma_waveform_uninit(p); free(p); } }
int y_w_init(ma_waveform* p, int f, unsigned int c, unsigned int s, int t, double a, double fr) {
  ma_waveform_config cfg = ma_waveform_config_init((ma_format)f, c, s, (ma_waveform_type)t, a, fr);
  return (int)ma_waveform_init(&cfg, p);
}
int y_w_read(ma_waveform* p, void* o, ma_uint64 n, ma_uint64* r) { return (int)ma_waveform_read_pcm_frames(p, o, n, r); }
int y_w_amp(ma_waveform* p, double a) { return (int)ma_waveform_set_amplitude(p, a); }
int y_w_freq(ma_waveform* p, double f) { return (int)ma_waveform_set_frequency(p, f); }
int y_w_type(ma_waveform* p, int t) { return (int)ma_waveform_set_type(p, (ma_waveform_type)t); }
ma_encoder* y_e_new(void) { return (ma_encoder*)calloc(1, sizeof(ma_encoder)); }
void y_e_del(ma_encoder* p) { if (p) { ma_encoder_uninit(p); free(p); } }
int y_e_init(ma_encoder* p, const char* path, int ef, int f, unsigned int c, unsigned int s) {
  ma_encoder_config cfg = ma_encoder_config_init((ma_encoding_format)ef, (ma_format)f, c, s);
  return (int)ma_encoder_init_file(path, &cfg, p);
}
int y_e_write(ma_encoder* p, const void* i, ma_uint64 n, ma_uint64* w) { return (int)ma_encoder_write_pcm_frames(p, i, n, w); }
ma_decoder* y_d_new(void) { return (ma_decoder*)calloc(1, sizeof(ma_decoder)); }
void y_d_del(ma_decoder* p) { if (p) { ma_decoder_uninit(p); free(p); } }
int y_d_init(ma_decoder* p, const char* path) {
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 1, 0);
  return (int)ma_decoder_init_file(path, &cfg, p);
}
int y_d_init_mem(ma_decoder* p, const void* data, size_t size) {
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 1, 0);
  return (int)ma_decoder_init_memory(data, size, &cfg, p);
}
int y_d_len(ma_decoder* p, ma_uint64* l) { return (int)ma_decoder_get_length_in_pcm_frames(p, l); }
int y_d_read(ma_decoder* p, void* o, ma_uint64 n, ma_uint64* r) { return (int)ma_decoder_read_pcm_frames(p, o, n, r); }
int y_d_seek(ma_decoder* p, ma_uint64 idx) { return (int)ma_decoder_seek_to_pcm_frame(p, idx); }
int y_mix(float* d, const float* s, ma_uint64 n, unsigned int c, float v) { return (int)ma_mix_pcm_frames_f32(d, s, n, c, v); }
ma_spatializer_listener* y_l_new(void) { return (ma_spatializer_listener*)calloc(1, sizeof(ma_spatializer_listener)); }
void y_l_del(ma_spatializer_listener* p) { if (p) { ma_spatializer_listener_uninit(p, NULL); free(p); } }
int y_l_init(ma_spatializer_listener* p, unsigned int c) {
  ma_spatializer_listener_config cfg = ma_spatializer_listener_config_init(c);
  cfg.handedness = ma_handedness_left;
  return (int)ma_spatializer_listener_init(&cfg, NULL, p);
}
void y_l_pos(ma_spatializer_listener* p, float x, float y, float z) { ma_spatializer_listener_set_position(p, x, y, z); }
void y_l_dir(ma_spatializer_listener* p, float x, float y, float z) { ma_spatializer_listener_set_direction(p, x, y, z); }
ma_spatializer* y_s_new(void) { return (ma_spatializer*)calloc(1, sizeof(ma_spatializer)); }
void y_s_del(ma_spatializer* p) { if (p) { ma_spatializer_uninit(p, NULL); free(p); } }
int y_s_init(ma_spatializer* p, unsigned int in, unsigned int out) {
  ma_spatializer_config cfg = ma_spatializer_config_init(in, out);
  cfg.handedness = ma_handedness_left;
  cfg.gainSmoothTimeInFrames = 0;
  return (int)ma_spatializer_init(&cfg, NULL, p);
}
void y_s_pos(ma_spatializer* p, float x, float y, float z) { ma_spatializer_set_position(p, x, y, z); }
int y_s_proc(ma_spatializer* p, ma_spatializer_listener* l, void* o, const void* i, ma_uint64 n) {
  return (int)ma_spatializer_process_pcm_frames(p, l, o, i, n);
}
#include <math.h>
#include <string.h>
/* synthesis (AU1): one voice = a miniaudio waveform or noise source -> a miniaudio
   low/high/band-pass filter -> an attack/release envelope and gain -> an echo -> pan, added into
   the device's stereo mix (or into any buffer, for tests and film export). The engine thread
   sets parameters; the device thread renders, applying them at the next block. */
typedef struct {
  volatile float p[16];              /* parameters, by Y_SYN_* index */
  int wave, filter; float freq, cutoff, q;
  ma_waveform w; ma_noise nz; int srcUp;
  ma_lpf2 lp; ma_hpf2 hp; ma_bpf2 bp; int fUp;
  double lfo; float env, gain;
  float* dbuf; int dlen, dpos;
  float tmp[512];
} ySyn;
enum { Y_SYN_WAVE, Y_SYN_FREQ, Y_SYN_VOL, Y_SYN_FILTER, Y_SYN_CUTOFF, Y_SYN_Q, Y_SYN_PAN, Y_SYN_ATTACK,
       Y_SYN_RELEASE, Y_SYN_ECHO, Y_SYN_ECHOMIX, Y_SYN_ECHOFB, Y_SYN_LFO, Y_SYN_LFODEPTH, Y_SYN_GATE };
ySyn* y_syn_new(void) {
  ySyn* s = (ySyn*)calloc(1, sizeof(ySyn));
  s->p[Y_SYN_FREQ] = 440; s->p[Y_SYN_VOL] = 0.5f; s->p[Y_SYN_CUTOFF] = 1000; s->p[Y_SYN_Q] = 0.707f;
  s->p[Y_SYN_ATTACK] = 0.01f; s->p[Y_SYN_RELEASE] = 0.2f; s->p[Y_SYN_GATE] = 1;
  s->wave = -1; s->filter = -1;
  s->dlen = 48000 * 2;
  s->dbuf = (float*)calloc((size_t)s->dlen, sizeof(float));
  return s;
}
void y_syn_del(ySyn* s) {
  if (!s) return;
  if (s->srcUp == 1) ma_waveform_uninit(&s->w);
  if (s->srcUp == 2) ma_noise_uninit(&s->nz, NULL);
  free(s->dbuf); free(s);
}
void y_syn_set(ySyn* s, int i, float v) { if (s && i >= 0 && i < 16) s->p[i] = v; }
void y_syn_render(ySyn* s, float* out, int frames);
void* y_syn_fn(void) { return (void*)y_syn_render; }
static void y_syn_filter(ySyn* s) {
  int f = (int)s->p[Y_SYN_FILTER];
  float c = s->p[Y_SYN_CUTOFF] < 10 ? 10 : (s->p[Y_SYN_CUTOFF] > 20000 ? 20000 : s->p[Y_SYN_CUTOFF]);
  float q = s->p[Y_SYN_Q] < 0.1f ? 0.1f : s->p[Y_SYN_Q];
  if (f == s->filter && c == s->cutoff && q == s->q) return;
  if (f == 1) {
    ma_lpf2_config k = ma_lpf2_config_init(ma_format_f32, 1, 48000, c, q);
    if (s->filter == 1) ma_lpf2_reinit(&k, &s->lp); else ma_lpf2_init(&k, NULL, &s->lp);
  } else if (f == 2) {
    ma_hpf2_config k = ma_hpf2_config_init(ma_format_f32, 1, 48000, c, q);
    if (s->filter == 2) ma_hpf2_reinit(&k, &s->hp); else ma_hpf2_init(&k, NULL, &s->hp);
  } else if (f == 3) {
    ma_bpf2_config k = ma_bpf2_config_init(ma_format_f32, 1, 48000, c, q);
    if (s->filter == 3) ma_bpf2_reinit(&k, &s->bp); else ma_bpf2_init(&k, NULL, &s->bp);
  }
  s->filter = f; s->cutoff = c; s->q = q;
}
/* adds `frames` stereo frames of this voice into `out` (the device callback's signature) */
void y_syn_render(ySyn* s, float* out, int frames) {
  int wave = (int)s->p[Y_SYN_WAVE];
  if (wave != s->wave) {                       /* 0 sine 1 square 2 triangle 3 saw, 4 white 5 pink 6 brown noise */
    if (s->srcUp == 1) ma_waveform_uninit(&s->w);
    if (s->srcUp == 2) ma_noise_uninit(&s->nz, NULL);
    if (wave >= 4) {
      ma_noise_config k = ma_noise_config_init(ma_format_f32, 1, (ma_noise_type)(wave - 4), 0, 1.0);
      s->srcUp = ma_noise_init(&k, NULL, &s->nz) == MA_SUCCESS ? 2 : 0;
    } else {
      ma_waveform_config k = ma_waveform_config_init(ma_format_f32, 1, 48000, (ma_waveform_type)wave, 1.0, s->p[Y_SYN_FREQ]);
      s->srcUp = ma_waveform_init(&k, &s->w) == MA_SUCCESS ? 1 : 0;
    }
    s->wave = wave; s->freq = -1;
  }
  y_syn_filter(s);
  float att = s->p[Y_SYN_ATTACK] < 0.001f ? 0.001f : s->p[Y_SYN_ATTACK];
  float rel = s->p[Y_SYN_RELEASE] < 0.001f ? 0.001f : s->p[Y_SYN_RELEASE];
  float target = s->p[Y_SYN_GATE] != 0 ? 1.0f : 0.0f;
  float pan = s->p[Y_SYN_PAN] < -1 ? -1 : (s->p[Y_SYN_PAN] > 1 ? 1 : s->p[Y_SYN_PAN]);
  float gl = cosf((pan + 1) * 0.78539816f), gr = sinf((pan + 1) * 0.78539816f);
  int delay = (int)(s->p[Y_SYN_ECHO] * 48000); if (delay >= s->dlen) delay = s->dlen - 1;
  float mix = s->p[Y_SYN_ECHOMIX], fb = s->p[Y_SYN_ECHOFB] > 0.95f ? 0.95f : s->p[Y_SYN_ECHOFB];
  for (int done = 0; done < frames;) {
    int k = frames - done > 512 ? 512 : frames - done;
    if (s->srcUp == 1) {
      float f = s->p[Y_SYN_FREQ];
      if (s->p[Y_SYN_LFO] > 0) {               /* vibrato: the pitch swings by lfoDepth (a fraction) */
        s->lfo += 6.2831853 * s->p[Y_SYN_LFO] * k / 48000.0;
        f *= 1.0f + s->p[Y_SYN_LFODEPTH] * (float)sin(s->lfo);
      }
      if (f != s->freq) { ma_waveform_set_frequency(&s->w, f); s->freq = f; }
      ma_waveform_read_pcm_frames(&s->w, s->tmp, (ma_uint64)k, NULL);
    } else if (s->srcUp == 2) ma_noise_read_pcm_frames(&s->nz, s->tmp, (ma_uint64)k, NULL);
    else memset(s->tmp, 0, sizeof(float) * (size_t)k);
    if (s->filter == 1) ma_lpf2_process_pcm_frames(&s->lp, s->tmp, s->tmp, (ma_uint64)k);
    else if (s->filter == 2) ma_hpf2_process_pcm_frames(&s->hp, s->tmp, s->tmp, (ma_uint64)k);
    else if (s->filter == 3) ma_bpf2_process_pcm_frames(&s->bp, s->tmp, s->tmp, (ma_uint64)k);
    float vol = s->p[Y_SYN_VOL];
    for (int i = 0; i < k; i++) {
      if (s->env < target) { s->env += 1.0f / (att * 48000); if (s->env > target) s->env = target; }
      else if (s->env > target) { s->env -= 1.0f / (rel * 48000); if (s->env < target) s->env = target; }
      s->gain += (vol - s->gain) * 0.002f;      /* ~10 ms glide: volume changes do not click */
      float y = s->tmp[i] * s->env * s->gain;
      if (delay > 0) {
        int j = s->dpos - delay; if (j < 0) j += s->dlen;
        float d = s->dbuf[j];
        s->dbuf[s->dpos] = y + d * fb;
        y += d * mix;
      } else s->dbuf[s->dpos] = 0;
      s->dpos = (s->dpos + 1) % s->dlen;
      out[(done + i) * 2] += y * gl;
      out[(done + i) * 2 + 1] += y * gr;
    }
    done += k;
  }
}
/* one shared playback device (48 kHz stereo float); its callback mixes every source (P3) */
typedef void (*y_src_fn)(void* user, float* out, int frames);
#define Y_MAX_SRC 64
static ma_device g_dev;
static ma_mutex g_srcMu;
static int g_devUp = 0;
static y_src_fn g_srcFn[Y_MAX_SRC];
static void* g_srcUser[Y_MAX_SRC];
static void y_out_cb(ma_device* d, void* out, const void* in, ma_uint32 n) {
  (void)d; (void)in;                /* out starts as silence: sources add into it */
  ma_mutex_lock(&g_srcMu);
  for (int i = 0; i < Y_MAX_SRC; ++i)
    if (g_srcFn[i]) g_srcFn[i](g_srcUser[i], (float*)out, (int)n);
  ma_mutex_unlock(&g_srcMu);
}
int y_out_start(void) {
  if (g_devUp) return g_devUp > 0;
  ma_mutex_init(&g_srcMu);
  ma_device_config c = ma_device_config_init(ma_device_type_playback);
  c.playback.format = ma_format_f32;
  c.playback.channels = 2;
  c.sampleRate = 48000;
  c.dataCallback = y_out_cb;
  if (ma_device_init(NULL, &c, &g_dev) != MA_SUCCESS) { g_devUp = -1; return 0; }
  if (ma_device_start(&g_dev) != MA_SUCCESS) { ma_device_uninit(&g_dev); g_devUp = -1; return 0; }
  g_devUp = 1;
  return 1;
}
int y_out_add(void* fn, void* user) {
  if (g_devUp <= 0) return -1;
  int slot = -1;
  ma_mutex_lock(&g_srcMu);
  for (int i = 0; i < Y_MAX_SRC; ++i) if (!g_srcFn[i]) { g_srcFn[i] = (y_src_fn)fn; g_srcUser[i] = user; slot = i; break; }
  ma_mutex_unlock(&g_srcMu);
  return slot;
}
/* the microphone (Q2): 48 kHz mono float into a 4 s ring the engine drains; peak level for a meter */
#define Y_CAP_N (48000 * 4)
static ma_device g_cap;
static int g_capUp = 0;
static ma_mutex g_capMu;
static float g_capRing[Y_CAP_N];
static int g_capHead = 0, g_capCount = 0;
static volatile float g_capLevel = 0;
static void y_cap_cb(ma_device* d, void* out, const void* in, ma_uint32 n) {
  (void)d; (void)out;
  const float* s = (const float*)in;
  float peak = 0;
  ma_mutex_lock(&g_capMu);
  for (ma_uint32 i = 0; i < n; ++i) {
    float v = s[i] < 0 ? -s[i] : s[i];
    if (v > peak) peak = v;
    if (g_capCount < Y_CAP_N) { g_capRing[(g_capHead + g_capCount) % Y_CAP_N] = s[i]; g_capCount++; }
  }
  ma_mutex_unlock(&g_capMu);
  g_capLevel = peak;
}
int y_cap_start(void) {
  if (g_capUp) return 1;
  ma_mutex_init(&g_capMu);
  ma_device_config c = ma_device_config_init(ma_device_type_capture);
  c.capture.format = ma_format_f32;
  c.capture.channels = 1;
  c.sampleRate = 48000;
  c.dataCallback = y_cap_cb;
  if (ma_device_init(NULL, &c, &g_cap) != MA_SUCCESS) { ma_mutex_uninit(&g_capMu); return 0; }
  if (ma_device_start(&g_cap) != MA_SUCCESS) { ma_device_uninit(&g_cap); ma_mutex_uninit(&g_capMu); return 0; }
  g_capHead = 0; g_capCount = 0;
  g_capUp = 1;
  return 1;
}
int y_cap_read(float* out, int max) {
  if (!g_capUp) return 0;
  ma_mutex_lock(&g_capMu);
  int n = g_capCount < max ? g_capCount : max;
  for (int i = 0; i < n; ++i) out[i] = g_capRing[(g_capHead + i) % Y_CAP_N];
  g_capHead = (g_capHead + n) % Y_CAP_N;
  g_capCount -= n;
  ma_mutex_unlock(&g_capMu);
  return n;
}
float y_cap_level(void) { return g_capUp ? g_capLevel : 0; }
void y_cap_stop(void) {
  if (!g_capUp) return;
  ma_device_uninit(&g_cap);            /* waits for the callback to finish */
  ma_mutex_uninit(&g_capMu);
  g_capUp = 0;
  g_capLevel = 0;
}
void y_out_remove(int slot) {
  if (g_devUp <= 0 || slot < 0 || slot >= Y_MAX_SRC) return;
  ma_mutex_lock(&g_srcMu);      /* once this returns the callback no longer calls it */
  g_srcFn[slot] = NULL;
  g_srcUser[slot] = NULL;
  ma_mutex_unlock(&g_srcMu);
}
""".}

proc c_w_new(): pointer {.importc: "y_w_new", nodecl.}
proc c_w_del(p: pointer) {.importc: "y_w_del", nodecl.}
proc c_w_init(p: pointer; f: cint; c, s: cuint; t: cint; a, fr: cdouble): cint {.importc: "y_w_init", nodecl.}
proc c_w_read(p: pointer; o: pointer; n: uint64; r: ptr uint64): cint {.importc: "y_w_read", nodecl.}
proc c_w_amp(p: pointer; a: cdouble): cint {.importc: "y_w_amp", nodecl.}
proc c_w_freq(p: pointer; f: cdouble): cint {.importc: "y_w_freq", nodecl.}
proc c_w_type(p: pointer; t: cint): cint {.importc: "y_w_type", nodecl.}
proc c_e_new(): pointer {.importc: "y_e_new", nodecl.}
proc c_e_del(p: pointer) {.importc: "y_e_del", nodecl.}
proc c_e_init(p: pointer; path: cstring; ef, f: cint; c, s: cuint): cint {.importc: "y_e_init", nodecl.}
proc c_e_write(p: pointer; i: pointer; n: uint64; w: ptr uint64): cint {.importc: "y_e_write", nodecl.}
proc c_d_new(): pointer {.importc: "y_d_new", nodecl.}
proc c_d_del(p: pointer) {.importc: "y_d_del", nodecl.}
proc c_d_init(p: pointer; path: cstring): cint {.importc: "y_d_init", nodecl.}
proc c_d_init_mem(p: pointer; data: pointer; size: csize_t): cint {.importc: "y_d_init_mem", nodecl.}
proc c_d_len(p: pointer; l: ptr uint64): cint {.importc: "y_d_len", nodecl.}
proc c_d_read(p: pointer; o: pointer; n: uint64; r: ptr uint64): cint {.importc: "y_d_read", nodecl.}
proc c_d_seek(p: pointer; idx: uint64): cint {.importc: "y_d_seek", nodecl.}
proc c_mix(d, s: ptr cfloat; n: uint64; c: cuint; v: cfloat): cint {.importc: "y_mix", nodecl.}
proc c_l_new(): pointer {.importc: "y_l_new", nodecl.}
proc c_l_del(p: pointer) {.importc: "y_l_del", nodecl.}
proc c_l_init(p: pointer; c: cuint): cint {.importc: "y_l_init", nodecl.}
proc c_l_pos(p: pointer; x, y, z: cfloat) {.importc: "y_l_pos", nodecl.}
proc c_l_dir(p: pointer; x, y, z: cfloat) {.importc: "y_l_dir", nodecl.}
proc c_s_new(): pointer {.importc: "y_s_new", nodecl.}
proc c_s_del(p: pointer) {.importc: "y_s_del", nodecl.}
proc c_s_init(p: pointer; i, o: cuint): cint {.importc: "y_s_init", nodecl.}
proc c_s_pos(p: pointer; x, y, z: cfloat) {.importc: "y_s_pos", nodecl.}
proc c_s_proc(p, l, o, i: pointer; n: uint64): cint {.importc: "y_s_proc", nodecl.}
proc c_out_start(): cint {.importc: "y_out_start", nodecl.}
proc c_out_add(fn, user: pointer): cint {.importc: "y_out_add", nodecl.}
proc c_out_remove(slot: cint) {.importc: "y_out_remove", nodecl.}
proc c_cap_start(): cint {.importc: "y_cap_start", nodecl.}
proc c_cap_read(o: ptr cfloat; n: cint): cint {.importc: "y_cap_read", nodecl.}
proc c_cap_level(): cfloat {.importc: "y_cap_level", nodecl.}
proc c_cap_stop() {.importc: "y_cap_stop", nodecl.}

type
  AudioFormat* = enum formatUnknown = 0, formatU8 = 1, formatS16 = 2, formatS24 = 3, formatS32 = 4, formatF32 = 5
  WaveformType* = enum waveSine = 0, waveSquare = 1, waveTriangle = 2, waveSawtooth = 3
  EncodingFormat* = enum encodingUnknown = 0, encodingWav = 1, encodingFlac = 2, encodingMp3 = 3, encodingVorbis = 4
  Waveform* = ref object
    raw: pointer
  Encoder* = ref object
    raw: pointer
  Decoder* = ref object
    raw: pointer
    bytes: string ## a decoder made from memory reads these for as long as it lives
  SpatializerListener* = ref object
    raw: pointer
  Spatializer* = ref object
    raw: pointer

proc newWaveform*(format: AudioFormat; channels, sampleRate: int; waveType: WaveformType; amplitude, frequency: float64): Waveform =
  let p = c_w_new()
  if p != nil and c_w_init(p, format.cint, channels.cuint, sampleRate.cuint, waveType.cint, amplitude.cdouble, frequency.cdouble) == 0: Waveform(raw: p)
  else: (if p != nil: c_w_del(p)); nil

proc free*(wave: Waveform) = (if wave != nil and wave.raw != nil: (c_w_del(wave.raw); wave.raw = nil))

proc readPcmFrames*(wave: Waveform; framesOut: pointer; frameCount: int): int =
  if wave != nil and wave.raw != nil and frameCount > 0:
    var readCount: uint64
    if c_w_read(wave.raw, framesOut, frameCount.uint64, readCount.addr) == 0: readCount.int else: 0
  else: 0

proc setAmplitude*(wave: Waveform; amplitude: float64) = (if wave != nil and wave.raw != nil: discard c_w_amp(wave.raw, amplitude.cdouble))
proc setFrequency*(wave: Waveform; frequency: float64) = (if wave != nil and wave.raw != nil: discard c_w_freq(wave.raw, frequency.cdouble))
proc setType*(wave: Waveform; waveType: WaveformType) = (if wave != nil and wave.raw != nil: discard c_w_type(wave.raw, waveType.cint))

proc newEncoder*(filePath: string; encoding: EncodingFormat; format: AudioFormat; channels, sampleRate: int): Encoder =
  let p = c_e_new()
  if p != nil and c_e_init(p, filePath.cstring, encoding.cint, format.cint, channels.cuint, sampleRate.cuint) == 0: Encoder(raw: p)
  else: (if p != nil: c_e_del(p)); nil

proc free*(enc: Encoder) = (if enc != nil and enc.raw != nil: (c_e_del(enc.raw); enc.raw = nil))

proc writePcmFrames*(enc: Encoder; framesIn: pointer; frameCount: int): int =
  if enc != nil and enc.raw != nil and frameCount > 0:
    var written: uint64
    if c_e_write(enc.raw, framesIn, frameCount.uint64, written.addr) == 0: written.int else: 0
  else: 0

proc newDecoder*(filePath: string): Decoder =
  let p = c_d_new()
  if p != nil and c_d_init(p, filePath.cstring) == 0: Decoder(raw: p)
  else: (if p != nil: c_d_del(p)); nil

proc newDecoderFromMemory*(bytes: string): Decoder =
  ## A decoder over encoded audio (wav, mp3, flac) already in memory: a sound that
  ## lives in Postgres never touches a file.
  if bytes.len == 0: return nil
  result = Decoder(raw: c_d_new(), bytes: bytes)
  if result.raw == nil or c_d_init_mem(result.raw, addr result.bytes[0], csize_t(bytes.len)) != 0:
    if result.raw != nil: c_d_del(result.raw)
    return nil

proc free*(dec: Decoder) = (if dec != nil and dec.raw != nil: (c_d_del(dec.raw); dec.raw = nil))

proc lengthInPcmFrames*(dec: Decoder): int =
  if dec != nil and dec.raw != nil:
    var total: uint64
    discard c_d_len(dec.raw, total.addr); total.int
  else: 0

proc readPcmFrames*(dec: Decoder; framesOut: pointer; frameCount: int): int =
  if dec != nil and dec.raw != nil and frameCount > 0:
    var readCount: uint64
    if c_d_read(dec.raw, framesOut, frameCount.uint64, readCount.addr) == 0: readCount.int else: 0
  else: 0

proc seekToPcmFrame*(dec: Decoder; frameIndex: int) = (if dec != nil and dec.raw != nil and frameIndex >= 0: discard c_d_seek(dec.raw, frameIndex.uint64))

proc mixPcmFrames*(dst: var openArray[float32]; src: openArray[float32]; frameCount: int; channels: int = 1; volume: float32 = 1.0f32) =
  if frameCount > 0 and dst.len > 0 and src.len > 0:
    discard c_mix(dst[0].addr, src[0].unsafeAddr, frameCount.uint64, channels.cuint, volume.cfloat)

proc newSpatializerListener*(channelsOut: int): SpatializerListener =
  let p = c_l_new()
  if p != nil and c_l_init(p, channelsOut.cuint) == 0: SpatializerListener(raw: p)
  else: (if p != nil: c_l_del(p)); nil

proc free*(listener: SpatializerListener) = (if listener != nil and listener.raw != nil: (c_l_del(listener.raw); listener.raw = nil))
proc setPosition*(listener: SpatializerListener; x, y, z: float32) = (if listener != nil and listener.raw != nil: c_l_pos(listener.raw, x.cfloat, y.cfloat, z.cfloat))
proc setDirection*(listener: SpatializerListener; x, y, z: float32) = (if listener != nil and listener.raw != nil: c_l_dir(listener.raw, x.cfloat, y.cfloat, z.cfloat))

proc newSpatializer*(channelsIn, channelsOut: int): Spatializer =
  let p = c_s_new()
  if p != nil and c_s_init(p, channelsIn.cuint, channelsOut.cuint) == 0: Spatializer(raw: p)
  else: (if p != nil: c_s_del(p)); nil

proc free*(spat: Spatializer) = (if spat != nil and spat.raw != nil: (c_s_del(spat.raw); spat.raw = nil))
proc setPosition*(spat: Spatializer; x, y, z: float32) = (if spat != nil and spat.raw != nil: c_s_pos(spat.raw, x.cfloat, y.cfloat, z.cfloat))

proc processPcmFrames*(spat: Spatializer; listener: SpatializerListener; framesOut, framesIn: pointer; frameCount: int) =
  if spat != nil and spat.raw != nil and listener != nil and listener.raw != nil and frameCount > 0:
    discard c_s_proc(spat.raw, listener.raw, framesOut, framesIn, frameCount.uint64)

# --- playback (P3): one device, many sources mixed in its callback --------------------------

proc startAudioOut*(): bool = c_out_start() == 1
  ## Opens the default playback device (48 kHz, stereo, float) once; false if there is none.
proc addAudioSource*(fn, user: pointer): int = int(c_out_add(fn, user))
  ## `fn(user, out: ptr float32, frames: cint)` (cdecl, C: it runs on the device's thread)
  ## adds `frames` stereo frames into `out`. -1 without a device or when 64 are playing.
proc removeAudioSource*(slot: int) = c_out_remove(cint(slot))
  ## After this returns the device never calls that source again.

# --- the microphone (Q2) ------------------------------------------------------------------
proc startCapture*(): bool = c_cap_start() == 1
  ## Opens the default microphone (48 kHz mono float) once; false if there is none.
proc readCapture*(buf: var seq[float32]): int =
  ## Moves what was captured since the last call into `buf` (up to its length); how many samples.
  if buf.len == 0: return 0
  int(c_cap_read(addr buf[0], cint(buf.len)))
proc captureLevel*(): float32 = float32(c_cap_level())
  ## The peak of the last captured buffer, 0..1 (a level meter).
proc stopCapture*() = c_cap_stop()

# --- synthesis (AU1): a voice built from miniaudio's generators and filters -----------------
type
  Synth* = distinct pointer
  SynthParam* = enum
    spWave, spFreq, spVolume, spFilter, spCutoff, spResonance, spPan, spAttack, spRelease,
    spEcho, spEchoMix, spEchoFeedback, spLfo, spLfoDepth, spGate
proc c_syn_new(): pointer {.importc: "y_syn_new", nodecl.}
proc c_syn_del(p: pointer) {.importc: "y_syn_del", nodecl.}
proc c_syn_set(p: pointer; i: cint; v: cfloat) {.importc: "y_syn_set", nodecl.}
proc c_syn_render(p: pointer; o: ptr cfloat; n: cint) {.importc: "y_syn_render", nodecl.}
proc c_syn_fn(): pointer {.importc: "y_syn_fn", nodecl.}
proc newSynth*(): Synth = Synth(c_syn_new())
  ## A voice: wave (0 sine, 1 square, 2 triangle, 3 saw, 4 white, 5 pink, 6 brown noise) ->
  ## filter (0 none, 1 low-, 2 high-, 3 band-pass at cutoff Hz, resonance Q) -> envelope
  ## (attack/release s, gate 1 on) and volume -> echo (seconds, mix, feedback) -> pan -1..1.
proc set*(s: Synth; p: SynthParam; v: float32) = c_syn_set(pointer(s), cint(ord(p)), v)
proc render*(s: Synth; stereo: var seq[float32]; frames: int) =
  ## Adds `frames` stereo frames into `stereo` (48 kHz), e.g. for tests or a film's audio.
  stereo.setLen(max(stereo.len, frames * 2))
  if frames > 0: c_syn_render(pointer(s), addr stereo[0], cint(frames))
proc play*(s: Synth): int = addAudioSource(c_syn_fn(), pointer(s))
  ## Into the playback device's mix (startAudioOut first); the slot for `stop`, or -1.
proc free*(s: Synth) = c_syn_del(pointer(s))
