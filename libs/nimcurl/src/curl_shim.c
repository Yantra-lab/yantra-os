/* nimcurl: many HTTP requests at once on one thread, through libcurl's multi interface.
   The caller starts requests, then polls; nothing blocks. */
#include <curl/curl.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  int id;
  CURL* easy;
  char* body; size_t len, cap, max;
  int tooBig;
  char err[CURL_ERROR_SIZE];
  struct curl_slist* headers;
  char* sendBody;
} Req;

typedef struct {
  CURLM* multi;
  Req** reqs; int n, cap;
  int nextId;
} Fetcher;

static size_t onData(char* p, size_t sz, size_t nm, void* ud) {
  Req* r = (Req*)ud;
  size_t k = sz * nm;
  if (r->len + k > r->max) { r->tooBig = 1; return 0; }       /* over the limit: stop */
  if (r->len + k + 1 > r->cap) {
    size_t c = r->cap ? r->cap : 16384;
    while (c < r->len + k + 1) c *= 2;
    char* b = (char*)realloc(r->body, c);
    if (!b) return 0;
    r->body = b; r->cap = c;
  }
  memcpy(r->body + r->len, p, k);
  r->len += k;
  return k;
}

void* yc_new(void) {
  static int inited = 0;
  if (!inited) { curl_global_init(CURL_GLOBAL_DEFAULT); inited = 1; }
  Fetcher* f = (Fetcher*)calloc(1, sizeof(Fetcher));
  f->multi = curl_multi_init();
  f->nextId = 1;
  return f;
}

/* protocols: "https" or "http,https". Redirects are not followed: the caller sees the 3xx.
   method: "GET", "POST", "PUT", "PATCH", "DELETE"; headers: "Name: value" lines split by 
;
   body: sent as is (bodyLen bytes). */
int yc_request(void* h, const char* method, const char* url, const char* protocols, const char* headers,
               const char* body, long bodyLen, long timeoutMs, long maxBytes);
int yc_start(void* h, const char* url, const char* protocols, long timeoutMs, long maxBytes) {
  return yc_request(h, "GET", url, protocols, "", "", 0, timeoutMs, maxBytes);
}
int yc_request(void* h, const char* method, const char* url, const char* protocols, const char* headers,
               const char* body, long bodyLen, long timeoutMs, long maxBytes) {
  Fetcher* f = (Fetcher*)h;
  Req* r = (Req*)calloc(1, sizeof(Req));
  r->easy = curl_easy_init();
  if (!r->easy) { free(r); return 0; }
  r->max = (size_t)maxBytes;
  r->id = f->nextId++;
  curl_easy_setopt(r->easy, CURLOPT_URL, url);
  curl_easy_setopt(r->easy, CURLOPT_PROTOCOLS_STR, protocols);
  curl_easy_setopt(r->easy, CURLOPT_FOLLOWLOCATION, 0L);
  curl_easy_setopt(r->easy, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(r->easy, CURLOPT_TIMEOUT_MS, timeoutMs);
  curl_easy_setopt(r->easy, CURLOPT_CONNECTTIMEOUT_MS, timeoutMs < 10000 ? timeoutMs : 10000L);
  curl_easy_setopt(r->easy, CURLOPT_USERAGENT, "Yantra/0.1");
  curl_easy_setopt(r->easy, CURLOPT_ACCEPT_ENCODING, "");
  curl_easy_setopt(r->easy, CURLOPT_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA);
  curl_easy_setopt(r->easy, CURLOPT_WRITEFUNCTION, onData);
  curl_easy_setopt(r->easy, CURLOPT_WRITEDATA, r);
  curl_easy_setopt(r->easy, CURLOPT_ERRORBUFFER, r->err);
  curl_easy_setopt(r->easy, CURLOPT_PRIVATE, r);
  if (strcmp(method, "GET") != 0) curl_easy_setopt(r->easy, CURLOPT_CUSTOMREQUEST, method);
  if (bodyLen > 0 || strcmp(method, "POST") == 0) {
    r->sendBody = (char*)malloc(bodyLen + 1);
    if (bodyLen > 0) memcpy(r->sendBody, body, bodyLen);
    curl_easy_setopt(r->easy, CURLOPT_POSTFIELDSIZE, bodyLen);
    curl_easy_setopt(r->easy, CURLOPT_POSTFIELDS, r->sendBody);
    if (strcmp(method, "POST") != 0) curl_easy_setopt(r->easy, CURLOPT_CUSTOMREQUEST, method);
  }
  const char* p = headers;
  while (p && *p) {
    const char* e = strchr(p, '\n');
    size_t n = e ? (size_t)(e - p) : strlen(p);
    if (n > 0 && n < 8192) {
      char line[8192]; memcpy(line, p, n); line[n] = 0;
      r->headers = curl_slist_append(r->headers, line);
    }
    p = e ? e + 1 : NULL;
  }
  if (r->headers) curl_easy_setopt(r->easy, CURLOPT_HTTPHEADER, r->headers);
  if (f->n == f->cap) {
    f->cap = f->cap ? f->cap * 2 : 8;
    f->reqs = (Req**)realloc(f->reqs, sizeof(Req*) * f->cap);
  }
  f->reqs[f->n++] = r;
  curl_multi_add_handle(f->multi, r->easy);
  return r->id;
}

int yc_pending(void* h) { return ((Fetcher*)h)->n; }

static void drop(Fetcher* f, Req* r) {
  for (int i = 0; i < f->n; i++)
    if (f->reqs[i] == r) { f->reqs[i] = f->reqs[--f->n]; break; }
  curl_multi_remove_handle(f->multi, r->easy);
  curl_easy_cleanup(r->easy);
  free(r->body);
  free(r->sendBody);
  if (r->headers) curl_slist_free_all(r->headers);
  free(r);
}

/* Moves transfers along; returns the id of one finished request (0: none yet). Its
   status, body and error are copied out; call again until it returns 0. */
int yc_poll(void* h, int* status, char** body, long* len, char* err, int errcap) {
  Fetcher* f = (Fetcher*)h;
  int running = 0;
  curl_multi_perform(f->multi, &running);
  int left = 0;
  CURLMsg* m;
  while ((m = curl_multi_info_read(f->multi, &left))) {
    if (m->msg != CURLMSG_DONE) continue;
    Req* r = NULL;
    curl_easy_getinfo(m->easy_handle, CURLINFO_PRIVATE, (char**)&r);
    long code = 0;
    curl_easy_getinfo(m->easy_handle, CURLINFO_RESPONSE_CODE, &code);
    int id = r->id;
    *status = (m->data.result == CURLE_OK) ? (int)code : 0;
    err[0] = 0;
    if (m->data.result != CURLE_OK) {
      const char* e = r->tooBig ? "response too big" : (r->err[0] ? r->err : curl_easy_strerror(m->data.result));
      strncpy(err, e, errcap - 1); err[errcap - 1] = 0;
    }
    *body = (char*)malloc(r->len + 1);
    if (r->len) memcpy(*body, r->body, r->len);
    (*body)[r->len] = 0;
    *len = (long)r->len;
    drop(f, r);
    return id;
  }
  return 0;
}

void yc_free_body(char* b) { free(b); }

/* Waits up to `ms` for network activity (for callers with nothing else to do). */
void yc_wait(void* h, int ms) { int n = 0; curl_multi_poll(((Fetcher*)h)->multi, NULL, 0, ms, &n); }

void yc_cancel(void* h, int id) {
  Fetcher* f = (Fetcher*)h;
  for (int i = 0; i < f->n; i++) if (f->reqs[i]->id == id) { drop(f, f->reqs[i]); return; }
}

void yc_close(void* h) {
  Fetcher* f = (Fetcher*)h;
  while (f->n) drop(f, f->reqs[0]);
  curl_multi_cleanup(f->multi);
  free(f->reqs);
  free(f);
}

/* --- WebSockets: connect through the multi (no blocking handshake), then frames ------------ */

typedef struct {
  CURLM* multi;
  CURL* easy;
  int state;                 /* 0 connecting, 1 open, 2 closed */
  char err[CURL_ERROR_SIZE];
  char* msg; size_t len, cap; /* a message being put together from fragments */
  long maxBytes;
} Ws;

void* yc_ws_open(const char* url, const char* protocols, long timeoutMs, long maxBytes) {
  static int inited = 0;
  if (!inited) { curl_global_init(CURL_GLOBAL_DEFAULT); inited = 1; }
  Ws* w = (Ws*)calloc(1, sizeof(Ws));
  w->maxBytes = maxBytes;
  w->multi = curl_multi_init();
  w->easy = curl_easy_init();
  curl_easy_setopt(w->easy, CURLOPT_URL, url);
  curl_easy_setopt(w->easy, CURLOPT_PROTOCOLS_STR, protocols);
  curl_easy_setopt(w->easy, CURLOPT_CONNECT_ONLY, 2L);
  curl_easy_setopt(w->easy, CURLOPT_NOSIGNAL, 1L);
  curl_easy_setopt(w->easy, CURLOPT_CONNECTTIMEOUT_MS, timeoutMs);
  curl_easy_setopt(w->easy, CURLOPT_USERAGENT, "Yantra/0.1");
  curl_easy_setopt(w->easy, CURLOPT_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA);
  curl_easy_setopt(w->easy, CURLOPT_ERRORBUFFER, w->err);
  curl_multi_add_handle(w->multi, w->easy);
  return w;
}

/* One event: 0 nothing, 1 opened, 2 a whole message (text or binary) in *data/*len,
   3 closed (err says why, "" if it closed cleanly). Call until it returns 0. */
int yc_ws_poll(void* h, char** data, long* len, char* err, int errcap) {
  Ws* w = (Ws*)h;
  err[0] = 0;
  if (w->state == 0) {
    int running = 0, left = 0;
    curl_multi_perform(w->multi, &running);
    CURLMsg* m;
    while ((m = curl_multi_info_read(w->multi, &left))) {
      if (m->msg != CURLMSG_DONE) continue;
      if (m->data.result == CURLE_OK) { w->state = 1; return 1; }
      w->state = 2;
      strncpy(err, w->err[0] ? w->err : curl_easy_strerror(m->data.result), errcap - 1);
      return 3;
    }
    return 0;
  }
  if (w->state != 1) return 0;
  for (;;) {
    char buf[16384];
    size_t got = 0;
    const struct curl_ws_frame* meta = NULL;
    CURLcode rc = curl_ws_recv(w->easy, buf, sizeof(buf), &got, &meta);
    if (rc == CURLE_AGAIN) return 0;
    if (rc != CURLE_OK) {
      w->state = 2;
      strncpy(err, curl_easy_strerror(rc), errcap - 1);
      return 3;
    }
    if (meta && (meta->flags & CURLWS_CLOSE)) { w->state = 2; return 3; }
    if (meta && (meta->flags & CURLWS_PING)) continue;          /* curl answers pings itself */
    if (w->len + got > (size_t)w->maxBytes) { w->state = 2; strncpy(err, "message too big", errcap - 1); return 3; }
    if (w->len + got + 1 > w->cap) {
      size_t c = w->cap ? w->cap : 16384;
      while (c < w->len + got + 1) c *= 2;
      w->msg = (char*)realloc(w->msg, c); w->cap = c;
    }
    memcpy(w->msg + w->len, buf, got);
    w->len += got;
    if (meta && meta->bytesleft == 0 && !(meta->flags & CURLWS_CONT)) {
      *data = (char*)malloc(w->len + 1);
      memcpy(*data, w->msg, w->len); (*data)[w->len] = 0;
      *len = (long)w->len;
      w->len = 0;
      return 2;
    }
  }
}

int yc_ws_send(void* h, const char* data, long len, int binary) {
  Ws* w = (Ws*)h;
  if (w->state != 1) return 0;
  size_t sent = 0, off = 0;
  while (off < (size_t)len) {
    CURLcode rc = curl_ws_send(w->easy, data + off, (size_t)len - off, &sent, 0, binary ? CURLWS_BINARY : CURLWS_TEXT);
    if (rc == CURLE_AGAIN) { curl_multi_poll(w->multi, NULL, 0, 5, NULL); continue; }
    if (rc != CURLE_OK) return 0;
    off += sent;
    if (len == 0) break;
  }
  return 1;
}

int yc_ws_state(void* h) { return ((Ws*)h)->state; }

void yc_ws_close(void* h) {
  Ws* w = (Ws*)h;
  if (w->state == 1) { size_t sent; curl_ws_send(w->easy, "", 0, &sent, 0, CURLWS_CLOSE); }
  curl_multi_remove_handle(w->multi, w->easy);
  curl_easy_cleanup(w->easy);
  curl_multi_cleanup(w->multi);
  free(w->msg);
  free(w);
}
