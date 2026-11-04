/* nimav — a small C shim over FFmpeg's libraries (libavformat, libavcodec, libswscale,
 * libavutil) for the Yantra engine: encode BGRA frames straight to a video file, and
 * probe a video file. The libraries are linked, not the ffmpeg program. */
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <stdio.h>
#include <string.h>

typedef struct {
  AVFormatContext* fmt;
  AVCodecContext* cc;
  AVStream* st;
  struct SwsContext* sws;
  AVFrame* frame;
  AVPacket* pkt;
  int64_t pts;
  int w, h;
} YavEnc;

static void seterr(char* err, int cap, const char* what, int code) {
  if (!err || cap <= 0) return;
  char buf[128] = {0};
  if (code < 0) av_strerror(code, buf, sizeof buf);
  snprintf(err, (size_t)cap, "%s%s%s", what, code < 0 ? ": " : "", buf);
}

static int drain(YavEnc* e) {
  int r;
  while ((r = avcodec_receive_packet(e->cc, e->pkt)) == 0) {
    av_packet_rescale_ts(e->pkt, e->cc->time_base, e->st->time_base);
    e->pkt->stream_index = e->st->index;
    int w = av_interleaved_write_frame(e->fmt, e->pkt);
    av_packet_unref(e->pkt);
    if (w < 0) return w;
  }
  return (r == AVERROR(EAGAIN) || r == AVERROR_EOF) ? 0 : r;
}

static void freeEnc(YavEnc* e) {
  if (!e) return;
  if (e->sws) sws_freeContext(e->sws);
  if (e->frame) av_frame_free(&e->frame);
  if (e->pkt) av_packet_free(&e->pkt);
  if (e->cc) avcodec_free_context(&e->cc);
  if (e->fmt) {
    if (e->fmt->pb) avio_closep(&e->fmt->pb);
    avformat_free_context(e->fmt);
  }
  av_free(e);
}

/* Opens `path` for writing (the container comes from its extension: .mp4, .mov, .webm,
 * .mkv). H.264 through libx264 when available (quality `crf`, 0-51, lower is better),
 * else the best H.264/MPEG-4 encoder there is. One thread, so output is repeatable. */
void* yav_open(const char* path, int w, int h, int fps, int crf, char* err, int errcap) {
  av_log_set_level(AV_LOG_ERROR);        /* FFmpeg's progress chatter is not ours to print */
  YavEnc* e = av_mallocz(sizeof(YavEnc));
  if (!e) { seterr(err, errcap, "out of memory", 0); return NULL; }
  e->w = w; e->h = h;
  int r = avformat_alloc_output_context2(&e->fmt, NULL, NULL, path);
  if (r < 0 || !e->fmt) { seterr(err, errcap, "unknown container for this file name", r); freeEnc(e); return NULL; }
  const AVCodec* codec = avcodec_find_encoder_by_name("libx264");
  if (!codec) codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  if (!codec) codec = avcodec_find_encoder(AV_CODEC_ID_MPEG4);
  if (!codec) { seterr(err, errcap, "no video encoder in this FFmpeg build", 0); freeEnc(e); return NULL; }
  e->st = avformat_new_stream(e->fmt, NULL);
  e->cc = avcodec_alloc_context3(codec);
  e->cc->width = w;
  e->cc->height = h;
  e->cc->time_base = (AVRational){1, fps};
  e->cc->framerate = (AVRational){fps, 1};
  e->cc->pix_fmt = AV_PIX_FMT_YUV420P;
  e->cc->gop_size = fps * 2;
  e->cc->thread_count = 1;
  if (e->fmt->oformat->flags & AVFMT_GLOBALHEADER) e->cc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
  if (strcmp(codec->name, "libx264") == 0) {
    char c[8]; snprintf(c, sizeof c, "%d", crf);
    av_opt_set(e->cc->priv_data, "crf", c, 0);
    av_opt_set(e->cc->priv_data, "preset", "medium", 0);
  } else {
    e->cc->bit_rate = (int64_t)w * h * fps / 4;
  }
  if ((r = avcodec_open2(e->cc, codec, NULL)) < 0) { seterr(err, errcap, "could not open the encoder", r); freeEnc(e); return NULL; }
  avcodec_parameters_from_context(e->st->codecpar, e->cc);
  e->st->time_base = e->cc->time_base;
  if (!(e->fmt->oformat->flags & AVFMT_NOFILE) && (r = avio_open(&e->fmt->pb, path, AVIO_FLAG_WRITE)) < 0) {
    seterr(err, errcap, "could not create the file", r); freeEnc(e); return NULL;
  }
  if ((r = avformat_write_header(e->fmt, NULL)) < 0) { seterr(err, errcap, "could not write the header", r); freeEnc(e); return NULL; }
  e->frame = av_frame_alloc();
  e->frame->format = AV_PIX_FMT_YUV420P;
  e->frame->width = w;
  e->frame->height = h;
  av_frame_get_buffer(e->frame, 0);
  e->pkt = av_packet_alloc();
  e->sws = sws_getContext(w, h, AV_PIX_FMT_BGRA, w, h, AV_PIX_FMT_YUV420P, SWS_BICUBIC, NULL, NULL, NULL);
  return e;
}

/* Adds one frame of BGRA pixels (Skia's native 32-bit order on little-endian). */
int yav_frame(void* h, const unsigned char* bgra, int stride) {
  YavEnc* e = (YavEnc*)h;
  if (!e) return -1;
  int r = av_frame_make_writable(e->frame);
  if (r < 0) return r;
  const uint8_t* src[1] = {bgra};
  int srcStride[1] = {stride};
  sws_scale(e->sws, src, srcStride, 0, e->h, e->frame->data, e->frame->linesize);
  e->frame->pts = e->pts++;
  if ((r = avcodec_send_frame(e->cc, e->frame)) < 0) return r;
  return drain(e);
}

/* Flushes, writes the trailer and frees everything. 0 on success. */
int yav_close(void* h) {
  YavEnc* e = (YavEnc*)h;
  if (!e) return -1;
  int r = avcodec_send_frame(e->cc, NULL);
  if (r >= 0) r = drain(e);
  int t = av_write_trailer(e->fmt);
  freeEnc(e);
  return r < 0 ? r : t;
}

/* Reads a video file's first video stream: frame count (by reading every packet),
 * width, height, duration in seconds and the codec name. 0 on success. */
int yav_probe(const char* path, int* frames, int* w, int* h, double* seconds, char* codec, int codecCap) {
  av_log_set_level(AV_LOG_ERROR);
  AVFormatContext* fmt = NULL;
  int r = avformat_open_input(&fmt, path, NULL, NULL);
  if (r < 0) return r;
  if ((r = avformat_find_stream_info(fmt, NULL)) < 0) { avformat_close_input(&fmt); return r; }
  int vi = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (vi < 0) { avformat_close_input(&fmt); return vi; }
  AVStream* st = fmt->streams[vi];
  *w = st->codecpar->width;
  *h = st->codecpar->height;
  *seconds = fmt->duration > 0 ? (double)fmt->duration / AV_TIME_BASE : 0;
  const AVCodecDescriptor* d = avcodec_descriptor_get(st->codecpar->codec_id);
  snprintf(codec, (size_t)codecCap, "%s", d ? d->name : "?");
  AVPacket* pkt = av_packet_alloc();
  int n = 0;
  while (av_read_frame(fmt, pkt) >= 0) {
    if (pkt->stream_index == vi) n++;
    av_packet_unref(pkt);
  }
  av_packet_free(&pkt);
  *frames = n;
  avformat_close_input(&fmt);
  return 0;
}

/* --- decoding: a video as frames the engine draws (films with pixel content) ------ */

typedef struct {
  AVFormatContext* fmt;
  AVCodecContext* cc;
  int vi;
  AVFrame* frame;     /* the latest decoded frame */
  AVFrame* next;      /* decoded but not yet due */
  AVPacket* pkt;
  struct SwsContext* sws;
  int swsW, swsH;
  double tb;          /* seconds per pts tick */
  double curT;        /* time of `frame` (-1: none) */
  int hasNext, eof;
} YavDec;

void* yav_dec_open(const char* path, int* w, int* h, double* seconds) {
  av_log_set_level(AV_LOG_ERROR);
  YavDec* d = av_mallocz(sizeof(YavDec));
  if (!d) return NULL;
  if (avformat_open_input(&d->fmt, path, NULL, NULL) < 0) { av_free(d); return NULL; }
  if (avformat_find_stream_info(d->fmt, NULL) < 0) goto fail;
  d->vi = av_find_best_stream(d->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (d->vi < 0) goto fail;
  AVStream* st = d->fmt->streams[d->vi];
  const AVCodec* codec = avcodec_find_decoder(st->codecpar->codec_id);
  if (!codec) goto fail;
  d->cc = avcodec_alloc_context3(codec);
  avcodec_parameters_to_context(d->cc, st->codecpar);
  d->cc->thread_count = 1;
  if (avcodec_open2(d->cc, codec, NULL) < 0) goto fail;
  d->frame = av_frame_alloc();
  d->next = av_frame_alloc();
  d->pkt = av_packet_alloc();
  d->tb = av_q2d(st->time_base);
  d->curT = -1;
  *w = d->cc->width;
  *h = d->cc->height;
  *seconds = d->fmt->duration > 0 ? (double)d->fmt->duration / AV_TIME_BASE
           : (st->duration > 0 ? st->duration * d->tb : 0);
  return d;
fail:
  if (d->cc) avcodec_free_context(&d->cc);
  avformat_close_input(&d->fmt);
  av_free(d);
  return NULL;
}

static double frameTime(YavDec* d, AVFrame* f) {
  int64_t pts = f->best_effort_timestamp != AV_NOPTS_VALUE ? f->best_effort_timestamp : f->pts;
  return pts == AV_NOPTS_VALUE ? 0 : pts * d->tb;
}

/* Decodes the next frame into `out`; 0 ok, <0 at the end. */
static int decodeOne(YavDec* d, AVFrame* out) {
  for (;;) {
    int r = avcodec_receive_frame(d->cc, out);
    if (r == 0) return 0;
    if (r == AVERROR_EOF) return -1;
    if (d->eof) return -1;
    int rd = av_read_frame(d->fmt, d->pkt);
    if (rd < 0) { d->eof = 1; avcodec_send_packet(d->cc, NULL); continue; }
    if (d->pkt->stream_index == d->vi) avcodec_send_packet(d->cc, d->pkt);
    av_packet_unref(d->pkt);
  }
}

/* Writes the frame showing at `t` seconds into `out` (BGRA, outW x outH). Moves forward
 * by decoding; seeks only when `t` jumps back or far ahead. Returns 1 if a frame was
 * written, 0 if there is none (past the end, or an empty file). */
int yav_dec_frame(void* h, double t, unsigned char* out, int outW, int outH) {
  YavDec* d = (YavDec*)h;
  if (!d) return 0;
  if (d->curT >= 0 && (t < d->curT - 1e-6 || t > d->curT + 2.0)) {
    int64_t ts = (int64_t)(t / d->tb);
    av_seek_frame(d->fmt, d->vi, ts, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(d->cc);
    d->hasNext = 0; d->eof = 0; d->curT = -1;
  }
  for (;;) {
    if (!d->hasNext) {
      if (decodeOne(d, d->next) < 0) break;
      d->hasNext = 1;
    }
    double nt = frameTime(d, d->next);
    if (d->curT >= 0 && nt > t + 1e-6) break;        /* not due yet: keep it for later */
    av_frame_unref(d->frame);
    av_frame_move_ref(d->frame, d->next);
    d->hasNext = 0;
    d->curT = nt;
  }
  if (d->curT < 0) return 0;
  if (!d->sws || d->swsW != outW || d->swsH != outH) {
    if (d->sws) sws_freeContext(d->sws);
    d->sws = sws_getContext(d->frame->width, d->frame->height, d->frame->format, outW, outH, AV_PIX_FMT_BGRA,
                            SWS_BILINEAR, NULL, NULL, NULL);
    d->swsW = outW; d->swsH = outH;
  }
  uint8_t* dst[1] = {out};
  int dstStride[1] = {outW * 4};
  sws_scale(d->sws, (const uint8_t* const*)d->frame->data, d->frame->linesize, 0, d->frame->height, dst, dstStride);
  return 1;
}

void yav_dec_close(void* h) {
  YavDec* d = (YavDec*)h;
  if (!d) return;
  if (d->sws) sws_freeContext(d->sws);
  av_frame_free(&d->frame);
  av_frame_free(&d->next);
  av_packet_free(&d->pkt);
  avcodec_free_context(&d->cc);
  avformat_close_input(&d->fmt);
  av_free(d);
}

/* --- playing (P3): one thread demuxes and decodes; audio drives the clock ------------
 * Video frames are converted to BGRA at the size the engine asked for and queued a few
 * ahead; audio is resampled to 48 kHz stereo float into a ring the audio device pulls
 * from (yav_play_audio, on the device's thread). The clock is the media time of the
 * next sample the device will play; with no audio (or none wanted) it is the wall clock. */
#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/time.h>
#include <pthread.h>
#include <time.h>

#define YP_RATE 48000
#define YP_VQ 4                    /* decoded video frames ready ahead */
#define YP_AQ (YP_RATE / 2)        /* audio ring: half a second of stereo frames */
#define YP_AMAX 8192               /* room one decoded audio chunk may need */
#define YP_PQ 1024                 /* video packets waiting for the decoder, at most */

typedef struct YpPkt { AVPacket* p; struct YpPkt* next; } YpPkt;

typedef struct {
  AVFormatContext* fmt;
  AVCodecContext* vc;
  AVCodecContext* ac;
  int vi, ai;
  double vtb;
  struct SwsContext* sws;
  int swsSrcW, swsSrcH, swsSrcF, swsW, swsH;
  SwrContext* swr;
  AVPacket* pkt;
  AVFrame* frm;
  float* tmp; int tmpCap;              /* resampler output */
  /* video: packets waiting, frames ready */
  YpPkt* pq; YpPkt* pqTail; int pqLen;
  uint8_t* vbuf[YP_VQ]; int vw[YP_VQ], vh[YP_VQ]; double vpts[YP_VQ];
  int vhead, vcount;
  int wantW, wantH;                    /* the size the engine draws at */
  int vflushed;                        /* the video decoder was drained at the end */
  /* audio ring (interleaved stereo float) */
  float* ring; int rhead, rcount;
  double apts;                         /* media time of the ring's first frame */
  int aflushed;
  /* clock and state */
  double clockBase; int64_t clockAt;   /* wall clock: media time clockBase at clockAt */
  int audioClock;                      /* the clock follows the audio (else the wall) */
  int wantAudio;                       /* a device pulls our samples (else audio is ignored) */
  double duration, dropBefore;
  int paused, loop, ended, error, eof, quit, seekReq;
  int shown;                           /* a frame was handed out since the last seek */
  int live;                            /* a camera: frames show as they come, the oldest drop */
  AVFrame* swFrm;                      /* a hardware frame copied back to memory (Q10) */
  double seekTo;
  float volume;
  pthread_t th; pthread_mutex_t mu; pthread_cond_t cv;
} YavPlay;

static double ypClockLocked(YavPlay* p) {
  if (p->audioClock) return p->apts;
  if (p->paused) return p->clockBase;
  return p->clockBase + (double)(av_gettime_relative() - p->clockAt) / 1e6;
}

static void ypToWallLocked(YavPlay* p, double t) {
  p->clockBase = t;
  p->clockAt = av_gettime_relative();
}

static void ypClearLocked(YavPlay* p) {
  while (p->pq) { YpPkt* n = p->pq->next; av_packet_free(&p->pq->p); av_free(p->pq); p->pq = n; }
  p->pqTail = NULL; p->pqLen = 0;
  p->vhead = 0; p->vcount = 0;
  p->rhead = 0; p->rcount = 0;
}

static void ypPushFrameLocked(YavPlay* p, AVFrame* f, double t) {
  int slot = (p->vhead + p->vcount) % YP_VQ;
  int w = p->wantW, h = p->wantH;
  if (!p->sws || p->swsSrcW != f->width || p->swsSrcH != f->height || p->swsSrcF != f->format ||
      p->swsW != w || p->swsH != h) {
    if (p->sws) sws_freeContext(p->sws);
    p->sws = sws_getContext(f->width, f->height, f->format, w, h, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
    p->swsSrcW = f->width; p->swsSrcH = f->height; p->swsSrcF = f->format; p->swsW = w; p->swsH = h;
  }
  if (!p->sws) return;
  if (!p->vbuf[slot] || p->vw[slot] * p->vh[slot] < w * h) {
    av_free(p->vbuf[slot]);
    p->vbuf[slot] = av_malloc((size_t)w * h * 4);
    if (!p->vbuf[slot]) return;
  }
  uint8_t* dst[1] = {p->vbuf[slot]};
  int stride[1] = {w * 4};
  sws_scale(p->sws, (const uint8_t* const*)f->data, f->linesize, 0, f->height, dst, stride);
  p->vw[slot] = w; p->vh[slot] = h; p->vpts[slot] = t;
  p->vcount++;
}

static void ypPushAudioLocked(YavPlay* p, const float* s, int n, double t) {
  int skip = 0;                                  /* samples before a seek target */
  if (t < p->dropBefore) skip = (int)((p->dropBefore - t) * YP_RATE);
  if (skip >= n) return;
  if (p->rcount == 0) p->apts = t + (double)skip / YP_RATE;   /* the clock starts at these */
  for (int i = skip; i < n && p->rcount < YP_AQ; ++i) {
    int at = (p->rhead + p->rcount) % YP_AQ;
    p->ring[at * 2] = s[i * 2];
    p->ring[at * 2 + 1] = s[i * 2 + 1];
    p->rcount++;
  }
}

/* Decodes what one packet gives (or drains at the end). Called without the lock. */
static void ypDecodeAudio(YavPlay* p, AVPacket* pkt) {
  if (avcodec_send_packet(p->ac, pkt) < 0 && pkt) return;
  while (avcodec_receive_frame(p->ac, p->frm) == 0) {
    int64_t pts = p->frm->best_effort_timestamp != AV_NOPTS_VALUE ? p->frm->best_effort_timestamp : p->frm->pts;
    double t = pts == AV_NOPTS_VALUE ? -1 : pts * av_q2d(p->fmt->streams[p->ai]->time_base);
    int cap = swr_get_out_samples(p->swr, p->frm->nb_samples);
    if (cap > p->tmpCap) { av_free(p->tmp); p->tmp = av_malloc((size_t)cap * 2 * sizeof(float)); p->tmpCap = p->tmp ? cap : 0; }
    if (!p->tmp) { av_frame_unref(p->frm); continue; }
    uint8_t* out[1] = {(uint8_t*)p->tmp};
    int n = swr_convert(p->swr, out, cap, (const uint8_t**)p->frm->extended_data, p->frm->nb_samples);
    av_frame_unref(p->frm);
    if (n <= 0) continue;
    pthread_mutex_lock(&p->mu);
    if (!p->seekReq) {
      if (t < 0) t = p->apts + (double)p->rcount / YP_RATE;
      ypPushAudioLocked(p, p->tmp, n, t);
    }
    pthread_mutex_unlock(&p->mu);
  }
}

static AVFrame* ypSoftware(AVFrame* f, AVFrame* sw);
static void ypDecodeVideo(YavPlay* p, AVPacket* pkt) {
  if (avcodec_send_packet(p->vc, pkt) < 0 && pkt) return;
  for (;;) {
    pthread_mutex_lock(&p->mu);
    if (p->live && p->vcount >= YP_VQ) { p->vhead = (p->vhead + 1) % YP_VQ; p->vcount--; }   /* never wait on a camera */
    while (p->vcount >= YP_VQ && !p->quit && !p->seekReq) pthread_cond_wait(&p->cv, &p->mu);
    int stop = p->quit || p->seekReq;
    pthread_mutex_unlock(&p->mu);
    if (stop) return;
    if (avcodec_receive_frame(p->vc, p->frm) != 0) return;
    int64_t pts = p->frm->best_effort_timestamp != AV_NOPTS_VALUE ? p->frm->best_effort_timestamp : p->frm->pts;
    double t = pts == AV_NOPTS_VALUE ? 0 : pts * p->vtb;
    pthread_mutex_lock(&p->mu);
    AVFrame* show = ypSoftware(p->frm, p->swFrm);
    if (show && !p->seekReq && t >= p->dropBefore - 0.001) ypPushFrameLocked(p, show, t);
    pthread_mutex_unlock(&p->mu);
    av_frame_unref(p->frm);
  }
}

static void ypSeek(YavPlay* p, double t) {
  /* the lock is held by the caller and released around the FFmpeg calls */
  ypClearLocked(p);
  p->seekReq = 0;
  p->eof = 0; p->ended = 0; p->vflushed = 0; p->aflushed = 0; p->shown = 0;
  p->dropBefore = t;
  p->apts = t;
  ypToWallLocked(p, t);
  pthread_mutex_unlock(&p->mu);
  av_seek_frame(p->fmt, -1, (int64_t)(t * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);
  if (p->vc) avcodec_flush_buffers(p->vc);
  if (p->ac) avcodec_flush_buffers(p->ac);
  pthread_mutex_lock(&p->mu);
}

static void* ypThread(void* arg) {
  YavPlay* p = (YavPlay*)arg;
  pthread_mutex_lock(&p->mu);
  while (!p->quit) {
    if (p->seekReq) { ypSeek(p, p->seekTo); continue; }
    /* 1. decode a waiting video packet while there is room for its frames */
    if (p->vi >= 0 && p->vcount < YP_VQ && (p->pq || (p->eof && !p->vflushed))) {
      YpPkt* k = p->pq;
      if (k) { p->pq = k->next; if (!p->pq) p->pqTail = NULL; p->pqLen--; }
      else p->vflushed = 1;
      pthread_mutex_unlock(&p->mu);
      ypDecodeVideo(p, k ? k->p : NULL);
      if (k) { av_packet_free(&k->p); av_free(k); }
      pthread_mutex_lock(&p->mu);
      continue;
    }
    /* 2. read the next packet while audio has room and video isn't too far ahead */
    int roomA = p->ai < 0 || p->rcount <= YP_AQ - YP_AMAX;
    if (!p->eof && roomA && p->pqLen < YP_PQ) {
      pthread_mutex_unlock(&p->mu);
      int r = av_read_frame(p->fmt, p->pkt);
      if (r < 0) {
        if (p->ai >= 0) ypDecodeAudio(p, NULL);   /* the last samples */
        pthread_mutex_lock(&p->mu);
        p->eof = 1;
        continue;
      }
      if (p->pkt->stream_index == p->ai) {
        ypDecodeAudio(p, p->pkt);
        av_packet_unref(p->pkt);
        pthread_mutex_lock(&p->mu);
      } else if (p->pkt->stream_index == p->vi) {
        YpPkt* k = av_mallocz(sizeof(YpPkt));
        AVPacket* c = k ? av_packet_clone(p->pkt) : NULL;
        av_packet_unref(p->pkt);
        pthread_mutex_lock(&p->mu);
        if (c && !p->seekReq) {
          k->p = c;
          if (p->pqTail) p->pqTail->next = k; else p->pq = k;
          p->pqTail = k;
          p->pqLen++;
        } else { if (c) av_packet_free(&c); av_free(k); }
      } else {
        av_packet_unref(p->pkt);
        pthread_mutex_lock(&p->mu);
      }
      continue;
    }
    /* 3. at the end with everything played: loop or stop */
    if (p->eof && !p->pq && (p->vi < 0 || p->vflushed)) {
      double clock = ypClockLocked(p);
      if (p->rcount == 0 && p->audioClock) { p->audioClock = 0; ypToWallLocked(p, clock); }  /* sound over: the wall goes on */
      int done = p->duration > 0 ? clock >= p->duration - 0.05 : p->vcount == 0 && p->rcount == 0;
      if (done) {
        if (p->loop) { ypSeek(p, 0); if (p->ai >= 0 && !p->error) p->audioClock = p->wantAudio; continue; }
        p->ended = 1;
      }
    }
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    ts.tv_nsec += 20 * 1000000;                   /* look again soon: the clock moves on its own */
    if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
    pthread_cond_timedwait(&p->cv, &p->mu, &ts);
  }
  pthread_mutex_unlock(&p->mu);
  return NULL;
}

#include <libavdevice/avdevice.h>
/* Opens camera number `index` (0 = the first): dshow on Windows, v4l2 on Linux, avfoundation on macOS. */
static int ypOpenCamera(AVFormatContext** fmt, int index) {
  static int reg = 0;
  if (!reg) { avdevice_register_all(); reg = 1; }
#if defined(_WIN32)
  const AVInputFormat* in = av_find_input_format("dshow");
  if (!in) return -1;
  AVDeviceInfoList* list = NULL;
  char url[512] = {0};
  if (avdevice_list_input_sources(in, NULL, NULL, &list) >= 0 && list) {
    int n = 0;
    for (int i = 0; i < list->nb_devices; ++i) {
      AVDeviceInfo* d = list->devices[i];
      int isVideo = 0;
      for (int k = 0; k < d->nb_media_types; ++k) if (d->media_types[k] == AVMEDIA_TYPE_VIDEO) isVideo = 1;
      if (!isVideo) continue;
      if (n++ == index) { snprintf(url, sizeof url, "video=%s", d->device_name); break; }
    }
    avdevice_free_list_devices(&list);
  }
  if (!url[0]) return -1;
#elif defined(__APPLE__)
  const AVInputFormat* in = av_find_input_format("avfoundation");
  char url[32]; snprintf(url, sizeof url, "%d:none", index);
#else
  const AVInputFormat* in = av_find_input_format("v4l2");
  char url[32]; snprintf(url, sizeof url, "/dev/video%d", index);
#endif
  if (!in) return -1;
  AVDictionary* opts = NULL;
  av_dict_set(&opts, "framerate", "30", 0);
  int r = avformat_open_input(fmt, url, in, &opts);
  av_dict_free(&opts);
  return r;
}

#include <libavutil/hwcontext.h>
/* Hardware decoding (Q10): D3D11VA on Windows, VAAPI on Linux, VideoToolbox on macOS, when
 * the codec supports it and the device opens; frames are copied back to memory for sws. */
static enum AVPixelFormat g_hwFormat = AV_PIX_FMT_NONE;
static enum AVPixelFormat ypPickHw(AVCodecContext* c, const enum AVPixelFormat* fmts) {
  enum AVPixelFormat want = (enum AVPixelFormat)(intptr_t)c->opaque;
  for (const enum AVPixelFormat* f = fmts; *f != AV_PIX_FMT_NONE; ++f) if (*f == want) return *f;
  return fmts[0];                                  /* not offered: software */
}
static int ypHardware(AVCodecContext* c, const AVCodec* codec) {
  if (getenv("YANTRA_NO_HWDEC")) return 0;
#if defined(_WIN32)
  enum AVHWDeviceType type = AV_HWDEVICE_TYPE_D3D11VA;
#elif defined(__APPLE__)
  enum AVHWDeviceType type = AV_HWDEVICE_TYPE_VIDEOTOOLBOX;
#else
  enum AVHWDeviceType type = AV_HWDEVICE_TYPE_VAAPI;
#endif
  for (int i = 0;; ++i) {
    const AVCodecHWConfig* cfg = avcodec_get_hw_config(codec, i);
    if (!cfg) return 0;
    if ((cfg->methods & AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX) && cfg->device_type == type) {
      AVBufferRef* dev = NULL;
      if (av_hwdevice_ctx_create(&dev, type, NULL, NULL, 0) < 0) return 0;
      c->hw_device_ctx = dev;
      c->opaque = (void*)(intptr_t)cfg->pix_fmt;
      c->get_format = ypPickHw;
      g_hwFormat = cfg->pix_fmt;
      return 1;
    }
  }
}

static AVCodecContext* ypOpenCodec(AVFormatContext* fmt, int si) {
  AVStream* st = fmt->streams[si];
  const AVCodec* codec = avcodec_find_decoder(st->codecpar->codec_id);
  if (!codec) return NULL;
  AVCodecContext* c = avcodec_alloc_context3(codec);
  if (!c) return NULL;
  avcodec_parameters_to_context(c, st->codecpar);
  c->thread_count = 2;
  int hw = st->codecpar->codec_type == AVMEDIA_TYPE_VIDEO && ypHardware(c, codec);
  if (avcodec_open2(c, codec, NULL) < 0) {
    avcodec_free_context(&c);
    if (!hw) return NULL;
    c = avcodec_alloc_context3(codec);             /* the hardware refused: software after all */
    if (!c) return NULL;
    avcodec_parameters_to_context(c, st->codecpar);
    c->thread_count = 2;
    if (avcodec_open2(c, codec, NULL) < 0) { avcodec_free_context(&c); return NULL; }
  }
  return c;
}

/* A frame still in video memory is copied into `sw` (NV12 etc.); else the frame itself. */
static AVFrame* ypSoftware(AVFrame* f, AVFrame* sw) {
  if (!f->hw_frames_ctx) return f;
  av_frame_unref(sw);
  if (av_hwframe_transfer_data(sw, f, 0) < 0) return NULL;
  sw->pts = f->pts;
  sw->best_effort_timestamp = f->best_effort_timestamp;
  return sw;
}

/* Network sources (HLS .m3u8, DASH .mpd, plain http files) must not hang a close. */
static int ypInterrupt(void* opaque) { return *(volatile int*)opaque; }

/* Opens `path` for playing, paused at 0. w, h: the size video frames are delivered at.
 * audio: 1 when a device will pull samples (yav_play_audio); else sound is ignored and
 * the wall clock drives. NULL if the file has neither a video nor an audio stream. */
void* yav_play_open(const char* path, int w, int h, int audio) {
  av_log_set_level(AV_LOG_ERROR);
  YavPlay* p = av_mallocz(sizeof(YavPlay));
  if (!p) return NULL;
  p->vi = -1; p->ai = -1;
  if (strncmp(path, "camera:", 7) == 0) {       /* Q2: the system camera through libavdevice */
    p->live = 1;
    audio = 0;
    if (ypOpenCamera(&p->fmt, atoi(path + 7)) < 0) { av_free(p); return NULL; }
  } else {
    static int net = 0;
    if (!net) { avformat_network_init(); net = 1; }
    p->fmt = avformat_alloc_context();
    p->fmt->interrupt_callback.callback = ypInterrupt;   /* yav_play_close sets quit: network reads stop */
    p->fmt->interrupt_callback.opaque = &p->quit;
    AVDictionary* o = NULL;
    if (strncmp(path, "http", 4) == 0) {
      av_dict_set(&o, "rw_timeout", "15000000", 0);       /* 15 s without data: give up */
      av_dict_set(&o, "reconnect", "1", 0);
      av_dict_set(&o, "reconnect_streamed", "1", 0);
    }
    int r = avformat_open_input(&p->fmt, path, NULL, &o);
    av_dict_free(&o);
    if (r < 0) { av_free(p); return NULL; }
  }
  if (avformat_find_stream_info(p->fmt, NULL) < 0) goto fail;
  int vi = av_find_best_stream(p->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
  if (vi >= 0 && !(p->fmt->streams[vi]->disposition & AV_DISPOSITION_ATTACHED_PIC)) {
    p->vc = ypOpenCodec(p->fmt, vi);
    if (p->vc) { p->vi = vi; p->vtb = av_q2d(p->fmt->streams[vi]->time_base); }
  }
  int ai = audio ? av_find_best_stream(p->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0) : -1;
  if (ai >= 0) {
    p->ac = ypOpenCodec(p->fmt, ai);
    if (p->ac) {
      AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
      if (swr_alloc_set_opts2(&p->swr, &stereo, AV_SAMPLE_FMT_FLT, YP_RATE, &p->ac->ch_layout,
                              p->ac->sample_fmt, p->ac->sample_rate, 0, NULL) == 0 && swr_init(p->swr) == 0) {
        p->ai = ai;
      } else {
        swr_free(&p->swr);
        avcodec_free_context(&p->ac);
      }
    }
  }
  if (p->vi < 0 && p->ai < 0) {
    /* audio-only file with no device: still playable on the wall clock (voice notes in tests) */
    if (av_find_best_stream(p->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0) < 0) goto fail;
  }
  p->duration = p->fmt->duration > 0 ? (double)p->fmt->duration / AV_TIME_BASE : 0;
  p->pkt = av_packet_alloc();
  p->frm = av_frame_alloc();
  p->swFrm = av_frame_alloc();
  p->ring = av_malloc(sizeof(float) * 2 * YP_AQ);
  if (!p->pkt || !p->frm || !p->ring) goto fail;
  p->wantW = w > 0 ? w : (p->vc ? p->vc->width : 2);
  p->wantH = h > 0 ? h : (p->vc ? p->vc->height : 2);
  p->wantAudio = p->ai >= 0;
  p->audioClock = p->wantAudio;
  p->paused = 1;
  p->volume = 1;
  ypToWallLocked(p, 0);
  pthread_mutex_init(&p->mu, NULL);
  pthread_cond_init(&p->cv, NULL);
  if (pthread_create(&p->th, NULL, ypThread, p) != 0) {
    pthread_mutex_destroy(&p->mu);
    pthread_cond_destroy(&p->cv);
    goto fail;
  }
  return p;
fail:
  if (p->vc) avcodec_free_context(&p->vc);
  if (p->ac) avcodec_free_context(&p->ac);
  if (p->swr) swr_free(&p->swr);
  av_packet_free(&p->pkt);
  av_frame_free(&p->frm);
  av_free(p->ring);
  avformat_close_input(&p->fmt);
  av_free(p);
  return NULL;
}

void yav_play_close(void* h) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  p->quit = 1;
  pthread_cond_broadcast(&p->cv);
  pthread_mutex_unlock(&p->mu);
  pthread_join(p->th, NULL);
  ypClearLocked(p);
  for (int i = 0; i < YP_VQ; ++i) av_free(p->vbuf[i]);
  if (p->sws) sws_freeContext(p->sws);
  if (p->swr) swr_free(&p->swr);
  if (p->vc) avcodec_free_context(&p->vc);
  if (p->ac) avcodec_free_context(&p->ac);
  av_packet_free(&p->pkt);
  av_frame_free(&p->frm);
  av_frame_free(&p->swFrm);
  av_free(p->ring);
  av_free(p->tmp);
  avformat_close_input(&p->fmt);
  pthread_mutex_destroy(&p->mu);
  pthread_cond_destroy(&p->cv);
  av_free(p);
}

void yav_play_pause(void* h, int paused) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  paused = paused != 0;
  if (paused != p->paused) {
    double t = ypClockLocked(p);
    p->paused = paused;
    ypToWallLocked(p, t);
  }
  pthread_cond_broadcast(&p->cv);
  pthread_mutex_unlock(&p->mu);
}

void yav_play_seek(void* h, double t) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  if (t < 0) t = 0;
  if (p->duration > 0 && t > p->duration) t = p->duration;
  p->seekTo = t;
  p->seekReq = 1;
  p->ended = 0;
  if (p->ai >= 0) p->audioClock = p->wantAudio;
  p->apts = t;                                   /* the clock reads the target at once */
  ypToWallLocked(p, t);
  pthread_cond_broadcast(&p->cv);
  pthread_mutex_unlock(&p->mu);
}

void yav_play_set(void* h, int loop, float volume, int w, int hgt) {
  /* loop, volume (0..1, muted = 0) and the size video frames come at (next frames) */
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  p->loop = loop != 0;
  p->volume = volume < 0 ? 0 : volume;
  if (w > 0 && hgt > 0) { p->wantW = w; p->wantH = hgt; }
  pthread_mutex_unlock(&p->mu);
}

/* Mixes up to `frames` stereo frames into `out` (the device's buffer), at the volume;
 * silence when paused or starved. Runs on the audio device's thread. */
void yav_play_audio(void* h, float* out, int frames) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  if (!p->paused && !p->seekReq && p->audioClock) {
    int n = frames < p->rcount ? frames : p->rcount;
    float v = p->volume;
    for (int i = 0; i < n; ++i) {
      int at = (p->rhead + i) % YP_AQ;
      out[i * 2] += p->ring[at * 2] * v;
      out[i * 2 + 1] += p->ring[at * 2 + 1] * v;
    }
    p->rhead = (p->rhead + n) % YP_AQ;
    p->rcount -= n;
    p->apts += (double)n / YP_RATE;
    if (n > 0) pthread_cond_broadcast(&p->cv);
  }
  pthread_mutex_unlock(&p->mu);
}

/* The frame due now into `out` (capacity `cap` bytes): 1 if a newer one was written (its
 * size in *w, *h), 0 if the one shown is still current. */
int yav_play_video(void* h, unsigned char* out, int cap, int* w, int* hgt) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return 0;
  pthread_mutex_lock(&p->mu);
  double clock = ypClockLocked(p);
  int got = -1;
  while (p->vcount > 0 && (p->live || p->vpts[p->vhead] <= clock + 0.004 || (!p->shown && p->paused))) {
    got = p->vhead;                              /* paused: still show the first frame there is */
    p->vhead = (p->vhead + 1) % YP_VQ;
    p->vcount--;
    if (p->paused) break;
  }
  int wrote = 0;
  if (got >= 0 && (long)p->vw[got] * p->vh[got] * 4 <= cap) {
    memcpy(out, p->vbuf[got], (size_t)p->vw[got] * p->vh[got] * 4);
    *w = p->vw[got]; *hgt = p->vh[got];
    wrote = 1;
    p->shown = 1;
  }
  if (got >= 0) pthread_cond_broadcast(&p->cv);
  pthread_mutex_unlock(&p->mu);
  return wrote;
}

void yav_play_status(void* h, double* clock, double* dur, int* ended, int* hasVideo, int* hasAudio) {
  YavPlay* p = (YavPlay*)h;
  if (!p) return;
  pthread_mutex_lock(&p->mu);
  *clock = ypClockLocked(p);
  if (p->duration > 0 && *clock > p->duration) *clock = p->duration;
  *dur = p->duration;
  *ended = p->ended;
  *hasVideo = p->vi >= 0;
  *hasAudio = p->ai >= 0;
  pthread_mutex_unlock(&p->mu);
}

/* The loudness of `path` in `n` equal slices of its length: the peak |sample| of each,
 * 0..1 (a voice note's waveform). Returns how many were filled; *seconds its length. */
int yav_waveform(const char* path, int n, float* peaks, double* seconds) {
  if (n <= 0 || !peaks) return 0;
  memset(peaks, 0, sizeof(float) * (size_t)n);
  AVFormatContext* fmt = NULL;
  av_log_set_level(AV_LOG_ERROR);
  if (avformat_open_input(&fmt, path, NULL, NULL) < 0) return 0;
  int filled = 0;
  AVCodecContext* ac = NULL;
  SwrContext* swr = NULL;
  AVPacket* pkt = av_packet_alloc();
  AVFrame* frm = av_frame_alloc();
  float* tmp = NULL; int tmpCap = 0;
  if (avformat_find_stream_info(fmt, NULL) < 0) goto done;
  int ai = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
  if (ai < 0) goto done;
  ac = ypOpenCodec(fmt, ai);
  if (!ac) goto done;
  AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
  const int rate = 8000;                         /* enough for a peak envelope */
  if (swr_alloc_set_opts2(&swr, &mono, AV_SAMPLE_FMT_FLT, rate, &ac->ch_layout, ac->sample_fmt,
                          ac->sample_rate, 0, NULL) != 0 || swr_init(swr) != 0) goto done;
  double dur = fmt->duration > 0 ? (double)fmt->duration / AV_TIME_BASE : 0;
  *seconds = dur;
  int64_t total = dur > 0 ? (int64_t)(dur * rate) : 0;
  int64_t at = 0;
  int eof = 0;
  for (;;) {
    if (!eof) {
      if (av_read_frame(fmt, pkt) < 0) { eof = 1; avcodec_send_packet(ac, NULL); }
      else { if (pkt->stream_index == ai) avcodec_send_packet(ac, pkt); av_packet_unref(pkt); }
    }
    while (avcodec_receive_frame(ac, frm) == 0) {
      int cap = swr_get_out_samples(swr, frm->nb_samples);
      if (cap > tmpCap) { av_free(tmp); tmp = av_malloc(sizeof(float) * (size_t)cap); tmpCap = tmp ? cap : 0; }
      if (!tmp) { av_frame_unref(frm); continue; }
      uint8_t* o[1] = {(uint8_t*)tmp};
      int got = swr_convert(swr, o, cap, (const uint8_t**)frm->extended_data, frm->nb_samples);
      av_frame_unref(frm);
      for (int i = 0; i < got; ++i, ++at) {
        int b = total > 0 ? (int)(at * n / total) : 0;
        if (b >= n) b = n - 1;
        float v = tmp[i] < 0 ? -tmp[i] : tmp[i];
        if (v > peaks[b]) peaks[b] = v;
        if (b + 1 > filled) filled = b + 1;
      }
    }
    if (eof) break;
  }
  if (total == 0 && at > 0) *seconds = (double)at / rate;
done:
  av_free(tmp);
  if (swr) swr_free(&swr);
  if (ac) avcodec_free_context(&ac);
  av_packet_free(&pkt);
  av_frame_free(&frm);
  avformat_close_input(&fmt);
  return filled > 0 ? n : 0;
}

/* The length of a video or audio file in seconds (0 unknown, -1 not a media file). */
double yav_duration(const char* path) {
  AVFormatContext* fmt = NULL;
  av_log_set_level(AV_LOG_ERROR);
  if (avformat_open_input(&fmt, path, NULL, NULL) < 0) return -1;
  double d = -1;
  if (avformat_find_stream_info(fmt, NULL) >= 0)
    d = fmt->duration > 0 ? (double)fmt->duration / AV_TIME_BASE : 0;
  avformat_close_input(&fmt);
  return d;
}

/* --- recording (Q2): float samples in, Opus/OGG (.ogg, .opus) or AAC (.m4a) out --------- */
#include <libavutil/audio_fifo.h>

typedef struct {
  AVFormatContext* fmt;
  AVCodecContext* cc;
  AVStream* st;
  SwrContext* swr;
  AVAudioFifo* fifo;
  AVFrame* frm;
  AVPacket* pkt;
  int64_t pts;
  int inRate, inCh;
} YavRec;

static int recDrain(YavRec* r) {
  int e;
  while ((e = avcodec_receive_packet(r->cc, r->pkt)) == 0) {
    av_packet_rescale_ts(r->pkt, r->cc->time_base, r->st->time_base);
    r->pkt->stream_index = r->st->index;
    av_interleaved_write_frame(r->fmt, r->pkt);
    av_packet_unref(r->pkt);
  }
  return (e == AVERROR(EAGAIN) || e == AVERROR_EOF) ? 0 : e;
}

static void recFree(YavRec* r) {
  if (!r) return;
  if (r->swr) swr_free(&r->swr);
  if (r->fifo) av_audio_fifo_free(r->fifo);
  av_frame_free(&r->frm);
  av_packet_free(&r->pkt);
  if (r->cc) avcodec_free_context(&r->cc);
  if (r->fmt) { if (r->fmt->pb) avio_closep(&r->fmt->pb); avformat_free_context(r->fmt); }
  av_free(r);
}

/* Starts a recording of `ch`-channel float audio at `rate` Hz into `path`. */
void* yav_rec_open(const char* path, int rate, int ch, char* err, int errcap) {
  av_log_set_level(AV_LOG_ERROR);
  YavRec* r = av_mallocz(sizeof(YavRec));
  if (!r) return NULL;
  r->inRate = rate; r->inCh = ch;
  int e = avformat_alloc_output_context2(&r->fmt, NULL, NULL, path);
  if (e < 0 || !r->fmt) { seterr(err, errcap, "unknown container for this file name", e); recFree(r); return NULL; }
  size_t n = strlen(path);
  int aac = n > 4 && (strcmp(path + n - 4, ".m4a") == 0 || strcmp(path + n - 4, ".aac") == 0);
  const AVCodec* codec = aac ? avcodec_find_encoder(AV_CODEC_ID_AAC) : avcodec_find_encoder_by_name("libopus");
  if (!codec && !aac) codec = avcodec_find_encoder(AV_CODEC_ID_OPUS);
  if (!codec) { seterr(err, errcap, "no encoder for this format in this FFmpeg build", 0); recFree(r); return NULL; }
  r->st = avformat_new_stream(r->fmt, NULL);
  r->cc = avcodec_alloc_context3(codec);
  r->cc->sample_rate = 48000;
  const void* cfg = NULL;                             /* opus: 48k; aac: nearly anything */
  int ncfg = 0;
  if (avcodec_get_supported_config(r->cc, codec, AV_CODEC_CONFIG_SAMPLE_RATE, 0, &cfg, &ncfg) >= 0 && cfg && ncfg > 0) {
    const int* rates = (const int*)cfg;
    int ok = 0;
    for (int q = 0; q < ncfg; ++q) if (rates[q] == 48000) ok = 1;
    if (!ok) r->cc->sample_rate = rates[0];
  }
  av_channel_layout_default(&r->cc->ch_layout, ch);
  r->cc->sample_fmt = AV_SAMPLE_FMT_FLTP;
  cfg = NULL; ncfg = 0;
  if (avcodec_get_supported_config(r->cc, codec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, &cfg, &ncfg) >= 0 && cfg && ncfg > 0)
    r->cc->sample_fmt = ((const enum AVSampleFormat*)cfg)[0];
  r->cc->bit_rate = aac ? 96000 : 32000;             /* voice */
  r->cc->time_base = (AVRational){1, r->cc->sample_rate};
  r->cc->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;   /* FFmpeg's own opus encoder, if no libopus */
  if (r->fmt->oformat->flags & AVFMT_GLOBALHEADER) r->cc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
  if ((e = avcodec_open2(r->cc, codec, NULL)) < 0) { seterr(err, errcap, "could not open the encoder", e); recFree(r); return NULL; }
  avcodec_parameters_from_context(r->st->codecpar, r->cc);
  r->st->time_base = r->cc->time_base;
  AVChannelLayout inL;
  av_channel_layout_default(&inL, ch);
  if (swr_alloc_set_opts2(&r->swr, &r->cc->ch_layout, r->cc->sample_fmt, r->cc->sample_rate, &inL, AV_SAMPLE_FMT_FLT,
                          rate, 0, NULL) < 0 || swr_init(r->swr) < 0) { seterr(err, errcap, "resampler", 0); recFree(r); return NULL; }
  r->fifo = av_audio_fifo_alloc(r->cc->sample_fmt, ch, 4096);
  r->frm = av_frame_alloc();
  r->pkt = av_packet_alloc();
  if ((e = avio_open(&r->fmt->pb, path, AVIO_FLAG_WRITE)) < 0) { seterr(err, errcap, "could not create the file", e); recFree(r); return NULL; }
  if ((e = avformat_write_header(r->fmt, NULL)) < 0) { seterr(err, errcap, "could not write the header", e); recFree(r); return NULL; }
  return r;
}

static int recEncode(YavRec* r, int flush) {
  int fs = r->cc->frame_size > 0 ? r->cc->frame_size : 1024;
  while (av_audio_fifo_size(r->fifo) >= fs || (flush && av_audio_fifo_size(r->fifo) > 0)) {
    int n = av_audio_fifo_size(r->fifo) < fs ? av_audio_fifo_size(r->fifo) : fs;
    av_frame_unref(r->frm);
    r->frm->nb_samples = n;
    r->frm->format = r->cc->sample_fmt;
    av_channel_layout_copy(&r->frm->ch_layout, &r->cc->ch_layout);
    r->frm->sample_rate = r->cc->sample_rate;
    if (av_frame_get_buffer(r->frm, 0) < 0) return -1;
    av_audio_fifo_read(r->fifo, (void**)r->frm->data, n);
    r->frm->pts = r->pts;
    r->pts += n;
    if (avcodec_send_frame(r->cc, r->frm) < 0) return -1;
    if (recDrain(r) < 0) return -1;
  }
  return 0;
}

/* Adds `frames` interleaved float frames. 0 ok, <0 error. */
int yav_rec_write(void* h, const float* samples, int frames) {
  YavRec* r = (YavRec*)h;
  if (!r || frames <= 0) return r ? 0 : -1;
  int cap = swr_get_out_samples(r->swr, frames);
  uint8_t** out = NULL;
  if (av_samples_alloc_array_and_samples(&out, NULL, r->cc->ch_layout.nb_channels, cap, r->cc->sample_fmt, 0) < 0) return -1;
  const uint8_t* in[1] = {(const uint8_t*)samples};
  int got = swr_convert(r->swr, out, cap, in, frames);
  if (got > 0) av_audio_fifo_write(r->fifo, (void**)out, got);
  av_freep(&out[0]);
  av_freep(&out);
  return recEncode(r, 0);
}

/* Finishes the file (flushes the encoder, writes the trailer). 0 ok. */
int yav_rec_close(void* h) {
  YavRec* r = (YavRec*)h;
  if (!r) return -1;
  recEncode(r, 1);
  avcodec_send_frame(r->cc, NULL);
  recDrain(r);
  int e = av_write_trailer(r->fmt);
  recFree(r);
  return e < 0 ? e : 0;
}

/* --- Opus frames for calls (Q11): 20 ms of 48 kHz mono float <-> one Opus packet -------- */
typedef struct { AVCodecContext* cc; AVFrame* f; AVPacket* p; SwrContext* swr; } YavOpus;

void* yav_opus_encoder(int bitrate) {
  const AVCodec* codec = avcodec_find_encoder_by_name("libopus");
  if (!codec) codec = avcodec_find_encoder(AV_CODEC_ID_OPUS);
  if (!codec) return NULL;
  YavOpus* o = av_mallocz(sizeof(YavOpus));
  o->cc = avcodec_alloc_context3(codec);
  o->cc->sample_rate = 48000;
  av_channel_layout_default(&o->cc->ch_layout, 1);
  o->cc->sample_fmt = AV_SAMPLE_FMT_FLT;
  { const void* sf = NULL; int nsf = 0;                 /* FFmpeg 8: the codec's formats via this call */
    if (avcodec_get_supported_config(o->cc, codec, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, &sf, &nsf) >= 0 && sf && nsf > 0)
      o->cc->sample_fmt = ((const enum AVSampleFormat*)sf)[0]; }
  o->cc->bit_rate = bitrate > 0 ? bitrate : 32000;
  o->cc->time_base = (AVRational){1, 48000};
  o->cc->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;
  av_opt_set(o->cc->priv_data, "application", "voip", 0);
  av_opt_set(o->cc->priv_data, "frame_duration", "20", 0);
  if (avcodec_open2(o->cc, codec, NULL) < 0) { avcodec_free_context(&o->cc); av_free(o); return NULL; }
  AVChannelLayout mono = AV_CHANNEL_LAYOUT_MONO;
  swr_alloc_set_opts2(&o->swr, &o->cc->ch_layout, o->cc->sample_fmt, 48000, &mono, AV_SAMPLE_FMT_FLT, 48000, 0, NULL);
  swr_init(o->swr);
  o->f = av_frame_alloc();
  o->p = av_packet_alloc();
  return o;
}

/* 960 mono samples in; the packet (<= cap bytes) out: its length, 0 none yet, <0 error. */
int yav_opus_encode(void* h, const float* pcm, int n, unsigned char* out, int cap) {
  YavOpus* o = (YavOpus*)h;
  if (!o) return -1;
  av_frame_unref(o->f);
  o->f->nb_samples = n;
  o->f->format = o->cc->sample_fmt;
  av_channel_layout_copy(&o->f->ch_layout, &o->cc->ch_layout);
  o->f->sample_rate = 48000;
  if (av_frame_get_buffer(o->f, 0) < 0) return -1;
  const uint8_t* in[1] = {(const uint8_t*)pcm};
  swr_convert(o->swr, o->f->data, n, in, n);
  if (avcodec_send_frame(o->cc, o->f) < 0) return -1;
  int r = avcodec_receive_packet(o->cc, o->p);
  if (r == AVERROR(EAGAIN)) return 0;
  if (r < 0) return -1;
  int len = o->p->size <= cap ? o->p->size : 0;
  if (len) memcpy(out, o->p->data, (size_t)len);
  av_packet_unref(o->p);
  return len;
}

void* yav_opus_decoder(void) {
  const AVCodec* codec = avcodec_find_decoder_by_name("libopus");
  if (!codec) codec = avcodec_find_decoder(AV_CODEC_ID_OPUS);
  if (!codec) return NULL;
  YavOpus* o = av_mallocz(sizeof(YavOpus));
  o->cc = avcodec_alloc_context3(codec);
  o->cc->sample_rate = 48000;
  av_channel_layout_default(&o->cc->ch_layout, 2);
  if (avcodec_open2(o->cc, codec, NULL) < 0) { avcodec_free_context(&o->cc); av_free(o); return NULL; }
  o->f = av_frame_alloc();
  o->p = av_packet_alloc();
  return o;
}

/* One Opus packet in; up to `cap` stereo float frames out: how many. */
int yav_opus_decode(void* h, const unsigned char* data, int len, float* out, int cap) {
  YavOpus* o = (YavOpus*)h;
  if (!o || len <= 0) return 0;
  av_packet_unref(o->p);
  if (av_new_packet(o->p, len) < 0) return 0;
  memcpy(o->p->data, data, (size_t)len);
  if (avcodec_send_packet(o->cc, o->p) < 0) return 0;
  int total = 0;
  while (avcodec_receive_frame(o->cc, o->f) == 0) {
    if (!o->swr) {
      AVChannelLayout stereo = AV_CHANNEL_LAYOUT_STEREO;
      swr_alloc_set_opts2(&o->swr, &stereo, AV_SAMPLE_FMT_FLT, 48000, &o->f->ch_layout, o->f->format, o->f->sample_rate, 0, NULL);
      swr_init(o->swr);
    }
    uint8_t* dst[1] = {(uint8_t*)(out + 2 * total)};
    int got = swr_convert(o->swr, dst, cap - total, (const uint8_t**)o->f->extended_data, o->f->nb_samples);
    if (got > 0) total += got;
    av_frame_unref(o->f);
  }
  return total;
}

void yav_opus_close(void* h) {
  YavOpus* o = (YavOpus*)h;
  if (!o) return;
  if (o->swr) swr_free(&o->swr);
  av_frame_free(&o->f);
  av_packet_free(&o->p);
  avcodec_free_context(&o->cc);
  av_free(o);
}
