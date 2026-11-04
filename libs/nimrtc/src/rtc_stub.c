/* nimrtc loopback stub for environments without libdatachannel.
 * Allows in-process testing of call signaling and state transitions. */
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#define MAX_EVENTS 16

typedef struct {
  int offerer;
  int state;
  char* ev[MAX_EVENTS];
  int head, count;
} StubCall;

static void queueEvent(StubCall* c, const char* s) {
  if (c->count < MAX_EVENTS) {
    c->ev[(c->head + c->count) % MAX_EVENTS] = strdup(s);
    c->count++;
  }
}

void* yrtc_call(int offerer, const char* ice) {
  (void)ice;
  StubCall* c = (StubCall*)calloc(1, sizeof(StubCall));
  if (!c) return NULL;
  c->offerer = offerer;
  c->state = 1;
  if (offerer) {
    queueEvent(c, "sdp\toffer\tmock_sdp_offer");
    queueEvent(c, "cand\t0\tcandidate:mock");
  }
  return c;
}

int yrtc_remote(void* ptr, const char* t, const char* s) {
  (void)s;
  StubCall* c = (StubCall*)ptr;
  if (!c) return 0;
  if (strcmp(t, "offer") == 0) {
    queueEvent(c, "sdp\tanswer\tmock_sdp_answer");
    c->state = 2;
    queueEvent(c, "state\t2\t");
  } else if (strcmp(t, "answer") == 0) {
    c->state = 2;
    queueEvent(c, "state\t2\t");
  }
  return 1;
}

int yrtc_candidate(void* ptr, const char* a, const char* m) {
  (void)ptr; (void)a; (void)m;
  return 1;
}

char* yrtc_next_event(void* ptr) {
  StubCall* c = (StubCall*)ptr;
  if (!c || c->count == 0) return NULL;
  char* s = c->ev[c->head];
  c->head = (c->head + 1) % MAX_EVENTS;
  c->count--;
  return s;
}

void yrtc_free(char* s) {
  free(s);
}

int yrtc_state(void* ptr) {
  StubCall* c = (StubCall*)ptr;
  return c ? c->state : 5;
}

int yrtc_send_opus(void* c, void* d, int n, int s) { (void)c; (void)d; (void)n; (void)s; return 0; }
int yrtc_next_packet(void* c, void* o, int cap) { (void)c; (void)o; (void)cap; return 0; }
void yrtc_play_push(void* c, float* s, int f) { (void)c; (void)s; (void)f; }
void yrtc_play_pull(void* u, float* o, int f) { (void)u; for (int i = 0; i < f * 2; i++) o[i] = 0; }

void yrtc_close(void* ptr) {
  StubCall* c = (StubCall*)ptr;
  if (!c) return;
  while (c->count > 0) {
    free(c->ev[c->head]);
    c->head = (c->head + 1) % MAX_EVENTS;
    c->count--;
  }
  free(c);
}
