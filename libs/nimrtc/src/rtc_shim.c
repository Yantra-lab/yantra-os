/* nimrtc — voice calls over WebRTC through libdatachannel (Q11): one peer connection with
 * one Opus audio track. Signaling (the SDP offer/answer and ICE candidates) comes out as
 * events for the app to carry to the other side (over its WebSocket); Opus frames go out
 * RTP-packetised by libdatachannel; incoming RTP payloads are queued for the engine to
 * decode, and decoded audio waits in a jitter ring the audio device pulls from. */
#include <rtc/rtc.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define YR_EVENTS 256
#define YR_PACKETS 256
#define YR_PT 111
#define YR_RING (48000 * 2)                /* 1 s of stereo frames */

typedef struct {
  int pc, tr, open, state;
  pthread_mutex_t mu;
  char* ev[YR_EVENTS]; int evHead, evCount;
  uint8_t pk[YR_PACKETS][1500]; int pkLen[YR_PACKETS]; int pkHead, pkCount;
  uint32_t ts;
  float ring[YR_RING * 2]; int rHead, rCount;
  int started;                              /* playback waits for 60 ms of audio first (jitter) */
} YCall;

static void pushEvent(YCall* c, const char* kind, const char* a, const char* b) {
  size_t n = strlen(kind) + (a ? strlen(a) : 0) + (b ? strlen(b) : 0) + 3;
  char* s = (char*)malloc(n);
  if (!s) return;
  snprintf(s, n, "%s\t%s\t%s", kind, a ? a : "", b ? b : "");
  pthread_mutex_lock(&c->mu);
  if (c->evCount < YR_EVENTS) { c->ev[(c->evHead + c->evCount) % YR_EVENTS] = s; c->evCount++; s = NULL; }
  pthread_mutex_unlock(&c->mu);
  free(s);
}

static void RTC_API onDescription(int pc, const char* sdp, const char* type, void* ptr) {
  (void)pc; pushEvent((YCall*)ptr, "sdp", type, sdp);
}
static void RTC_API onCandidate(int pc, const char* cand, const char* mid, void* ptr) {
  (void)pc; pushEvent((YCall*)ptr, "cand", mid, cand);
}
static void RTC_API onState(int pc, rtcState st, void* ptr) {
  (void)pc;
  YCall* c = (YCall*)ptr;
  c->state = (int)st;
  char n[8]; snprintf(n, sizeof n, "%d", (int)st);   /* 0 new 1 connecting 2 connected 3 disconnected 4 failed 5 closed */
  pushEvent(c, "state", n, "");
}
static void RTC_API onOpen(int id, void* ptr) { (void)id; ((YCall*)ptr)->open = 1; }
static void RTC_API onMessage(int id, const char* msg, int size, void* ptr) {
  (void)id;
  YCall* c = (YCall*)ptr;
  const uint8_t* b = (const uint8_t*)msg;
  if (size < 12 || (b[0] >> 6) != 2 || (b[1] & 0x7F) != YR_PT) return;   /* RTP, our Opus payload only (not RTCP) */
  int off = 12 + 4 * (b[0] & 0x0F);
  if (b[0] & 0x10) {                                                      /* a header extension */
    if (size < off + 4) return;
    off += 4 + 4 * ((b[off + 2] << 8) | b[off + 3]);
  }
  int n = size - off;
  if (b[0] & 0x20) n -= b[size - 1];                                      /* padding */
  if (n <= 0 || n > 1500) return;
  pthread_mutex_lock(&c->mu);
  if (c->pkCount < YR_PACKETS) {
    int at = (c->pkHead + c->pkCount) % YR_PACKETS;
    memcpy(c->pk[at], b + off, (size_t)n);
    c->pkLen[at] = n;
    c->pkCount++;
  }
  pthread_mutex_unlock(&c->mu);
}

static void setupTrack(YCall* c, int tr) {
  c->tr = tr;
  rtcSetUserPointer(tr, c);
  rtcPacketizerInit pi;
  memset(&pi, 0, sizeof pi);
  pi.ssrc = (uint32_t)(rand() | 1);
  pi.cname = "yantra";
  pi.payloadType = YR_PT;
  pi.clockRate = 48000;
  rtcSetOpusPacketizer(tr, &pi);
  rtcChainRtcpSrReporter(tr);
  rtcChainRtcpReceivingSession(tr);
  rtcSetOpenCallback(tr, onOpen);
  rtcSetMessageCallback(tr, onMessage);
}

static void RTC_API onTrack(int pc, int tr, void* ptr) {   /* the answerer: the offer's audio track */
  (void)pc;
  YCall* c = (YCall*)ptr;
  if (c->tr <= 0) setupTrack(c, tr);
}

/* A call. offerer = 1 starts it (an offer comes out as an "sdp" event); 0 waits for the
 * other side's offer (yrtc_remote). iceServers: "stun:…\nturn:user:pass@…" or "". */
void* yrtc_call(int offerer, const char* iceServers) {
  YCall* c = (YCall*)calloc(1, sizeof(YCall));
  if (!c) return NULL;
  pthread_mutex_init(&c->mu, NULL);
  const char* servers[8];
  char buf[2048] = {0};
  int ns = 0;
  if (iceServers) {
    strncpy(buf, iceServers, sizeof buf - 1);
    for (char* s = strtok(buf, "\n"); s && ns < 8; s = strtok(NULL, "\n")) servers[ns++] = s;
  }
  rtcConfiguration cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.iceServers = servers;
  cfg.iceServersCount = ns;
  c->pc = rtcCreatePeerConnection(&cfg);
  if (c->pc < 0) { free(c); return NULL; }
  rtcSetUserPointer(c->pc, c);
  rtcSetLocalDescriptionCallback(c->pc, onDescription);
  rtcSetLocalCandidateCallback(c->pc, onCandidate);
  rtcSetStateChangeCallback(c->pc, onState);
  rtcSetTrackCallback(c->pc, onTrack);
  if (offerer) {
    rtcTrackInit ti;
    memset(&ti, 0, sizeof ti);
    ti.direction = RTC_DIRECTION_SENDRECV;
    ti.codec = RTC_CODEC_OPUS;
    ti.payloadType = YR_PT;
    ti.ssrc = (uint32_t)(rand() | 1);
    ti.mid = "audio";
    ti.name = "yantra";
    ti.msid = "yantra";
    ti.trackId = "voice";
    int tr = rtcAddTrackEx(c->pc, &ti);
    if (tr < 0) { rtcDeletePeerConnection(c->pc); free(c); return NULL; }
    setupTrack(c, tr);
    rtcSetLocalDescription(c->pc, "offer");
  }
  return c;
}

/* The other side's description: type "offer" or "answer". An offer makes our answer. */
int yrtc_remote(YCall* c, const char* type, const char* sdp) {
  return c && rtcSetRemoteDescription(c->pc, sdp, type) >= 0 ? 1 : 0;
}
int yrtc_candidate(YCall* c, const char* cand, const char* mid) {
  return c && rtcAddRemoteCandidate(c->pc, cand, mid) >= 0 ? 1 : 0;
}

/* The next signaling event, "sdp\ttype\tsdp" / "cand\tmid\tcandidate" / "state\tn\t" (free
 * it with yrtc_free), or NULL. */
char* yrtc_next_event(YCall* c) {
  char* s = NULL;
  pthread_mutex_lock(&c->mu);
  if (c->evCount > 0) { s = c->ev[c->evHead]; c->evHead = (c->evHead + 1) % YR_EVENTS; c->evCount--; }
  pthread_mutex_unlock(&c->mu);
  return s;
}
void yrtc_free(char* s) { free(s); }
int yrtc_state(YCall* c) { return c ? c->state : 5; }

/* One Opus frame of `samples` (at 48 kHz) out. 1 sent, 0 not yet (the track isn't open). */
int yrtc_send_opus(YCall* c, const uint8_t* data, int len, int samples) {
  if (!c || !c->open || c->tr <= 0) return 0;
  rtcSetTrackRtpTimestamp(c->tr, c->ts);
  c->ts += (uint32_t)samples;
  return rtcSendMessage(c->tr, (const char*)data, len) >= 0 ? 1 : 0;
}

/* The next received Opus frame into `out`; its length, or 0. */
int yrtc_next_packet(YCall* c, uint8_t* out, int cap) {
  int n = 0;
  pthread_mutex_lock(&c->mu);
  if (c->pkCount > 0) {
    n = c->pkLen[c->pkHead] <= cap ? c->pkLen[c->pkHead] : 0;
    if (n) memcpy(out, c->pk[c->pkHead], (size_t)n);
    c->pkHead = (c->pkHead + 1) % YR_PACKETS;
    c->pkCount--;
  }
  pthread_mutex_unlock(&c->mu);
  return n;
}

/* Decoded audio (stereo float, 48 kHz) in / out: the device pulls with yrtc_play_pull. */
void yrtc_play_push(YCall* c, const float* s, int frames) {
  pthread_mutex_lock(&c->mu);
  for (int i = 0; i < frames; ++i) {
    if (c->rCount >= YR_RING) { c->rHead = (c->rHead + 1) % YR_RING; c->rCount--; }   /* too far behind: drop the oldest */
    int at = (c->rHead + c->rCount) % YR_RING;
    c->ring[2 * at] = s[2 * i];
    c->ring[2 * at + 1] = s[2 * i + 1];
    c->rCount++;
  }
  pthread_mutex_unlock(&c->mu);
}
void yrtc_play_pull(void* user, float* out, int frames) {
  YCall* c = (YCall*)user;
  pthread_mutex_lock(&c->mu);
  if (!c->started && c->rCount >= 48000 * 60 / 1000) c->started = 1;
  if (c->started) {
    int n = frames < c->rCount ? frames : c->rCount;
    for (int i = 0; i < n; ++i) {
      int at = (c->rHead + i) % YR_RING;
      out[2 * i] += c->ring[2 * at];
      out[2 * i + 1] += c->ring[2 * at + 1];
    }
    c->rHead = (c->rHead + n) % YR_RING;
    c->rCount -= n;
    if (c->rCount == 0) c->started = 0;       /* ran dry: build up a little again */
  }
  pthread_mutex_unlock(&c->mu);
}

void yrtc_close(YCall* c) {
  if (!c) return;
  if (c->tr > 0) rtcDeleteTrack(c->tr);
  rtcDeletePeerConnection(c->pc);
  for (int i = 0; i < c->evCount; ++i) free(c->ev[(c->evHead + i) % YR_EVENTS]);
  pthread_mutex_destroy(&c->mu);
  free(c);
}
