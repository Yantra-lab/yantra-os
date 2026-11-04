/* nimaccesskit — the engine's tree made visible to screen readers through AccessKit
 * (https://github.com/AccessKit/accesskit-c): Windows UI Automation today, macOS and
 * Linux (AT-SPI) through the same calls later.
 *
 * Screen readers ask on their own threads. So the engine never hands over live objects:
 * it publishes a SNAPSHOT (roles, names, values, bounds, children, focus) under a lock,
 * AccessKit builds its tree from that, and actions a screen reader requests (click,
 * focus) wait in a queue the engine's loop takes from. */
#include <windows.h>
#include <string.h>
#include <stdlib.h>
#include "accesskit.h"

typedef struct {
  uint64_t id;
  int role;               /* see ak_role() */
  char* label;
  char* value;
  double x0, y0, x1, y1;  /* window-client pixels */
  uint64_t* kids;
  int nkids;
  int actions;            /* 1 click, 2 focus */
  int toggled;            /* -1 none, 0 false, 1 true */
} AkNode;

typedef struct {
  AkNode* nodes;
  int n, cap;
  uint64_t root, focus;
} AkSnap;

typedef struct { int action; uint64_t node; } AkReq;

static CRITICAL_SECTION g_lock;
static int g_lockReady = 0;
static AkSnap g_snap;              /* the published tree */
static AkSnap g_next;              /* being built by the engine */
static AkReq g_q[64];
static int g_qn = 0;
static accesskit_windows_subclassing_adapter* g_adapter = NULL;
static void (*g_wake)(void) = NULL;

/* Called (from the screen reader's thread) after an action is queued, so a sleeping
 * event loop comes back to carry it out. */
void ak_set_wake(void (*fn)(void)) { g_wake = fn; }

static void lockInit(void) { if (!g_lockReady) { InitializeCriticalSection(&g_lock); g_lockReady = 1; } }

static char* dupstr(const char* s) {
  if (!s || !s[0]) return NULL;
  size_t n = strlen(s);
  char* r = (char*)malloc(n + 1);
  memcpy(r, s, n + 1);
  return r;
}

static void snapFree(AkSnap* s) {
  for (int i = 0; i < s->n; i++) {
    free(s->nodes[i].label);
    free(s->nodes[i].value);
    free(s->nodes[i].kids);
  }
  s->n = 0;
}

static accesskit_role ak_role(int r) {
  switch (r) {
    case 1: return ACCESSKIT_ROLE_WINDOW;
    case 2: return ACCESSKIT_ROLE_LABEL;
    case 3: return ACCESSKIT_ROLE_BUTTON;
    case 4: return ACCESSKIT_ROLE_TEXT_INPUT;
    case 5: return ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT;
    case 6: return ACCESSKIT_ROLE_CHECK_BOX;
    case 7: return ACCESSKIT_ROLE_IMAGE;
    case 8: return ACCESSKIT_ROLE_VIDEO;
    case 9: return ACCESSKIT_ROLE_DOCUMENT;
    case 10: return ACCESSKIT_ROLE_PANE;
    default: return ACCESSKIT_ROLE_GENERIC_CONTAINER;
  }
}

/* --- building a snapshot (engine thread) --------------------------------------------- */

void ak_begin(void) { lockInit(); snapFree(&g_next); }

void ak_node(uint64_t id, int role, const char* label, const char* value, double x0, double y0, double x1,
             double y1, const uint64_t* kids, int nkids, int actions, int toggled) {
  if (g_next.n == g_next.cap) {
    g_next.cap = g_next.cap ? g_next.cap * 2 : 64;
    g_next.nodes = (AkNode*)realloc(g_next.nodes, sizeof(AkNode) * (size_t)g_next.cap);
  }
  AkNode* n = &g_next.nodes[g_next.n++];
  n->id = id; n->role = role;
  n->label = dupstr(label); n->value = dupstr(value);
  n->x0 = x0; n->y0 = y0; n->x1 = x1; n->y1 = y1;
  n->nkids = nkids;
  n->kids = nkids > 0 ? (uint64_t*)malloc(sizeof(uint64_t) * (size_t)nkids) : NULL;
  if (nkids > 0) memcpy(n->kids, kids, sizeof(uint64_t) * (size_t)nkids);
  n->actions = actions; n->toggled = toggled;
}

static accesskit_tree_update* buildUpdate(void* userdata) {
  (void)userdata;
  EnterCriticalSection(&g_lock);
  if (g_snap.n == 0) {                     /* nothing published yet: a tree must still hold its root */
    accesskit_tree_update* e = accesskit_tree_update_with_capacity_and_focus(1, g_snap.root);
    accesskit_tree_update_set_tree_info(e, accesskit_tree_info_new(g_snap.root));
    accesskit_tree_update_push_node(e, g_snap.root, accesskit_node_new(ACCESSKIT_ROLE_WINDOW));
    LeaveCriticalSection(&g_lock);
    return e;
  }
  accesskit_tree_update* u = accesskit_tree_update_with_capacity_and_focus((size_t)g_snap.n, g_snap.focus);
  accesskit_tree_update_set_tree_info(u, accesskit_tree_info_new(g_snap.root));
  for (int i = 0; i < g_snap.n; i++) {
    AkNode* s = &g_snap.nodes[i];
    accesskit_node* n = accesskit_node_new(ak_role(s->role));
    if (s->label) accesskit_node_set_label(n, s->label);
    if (s->value) accesskit_node_set_value(n, s->value);
    accesskit_rect r = {s->x0, s->y0, s->x1, s->y1};
    accesskit_node_set_bounds(n, r);
    if (s->nkids > 0) accesskit_node_set_children(n, (size_t)s->nkids, s->kids);
    if (s->actions & 1) accesskit_node_add_action(n, ACCESSKIT_ACTION_CLICK);
    if (s->actions & 2) accesskit_node_add_action(n, ACCESSKIT_ACTION_FOCUS);
    if (s->toggled >= 0) accesskit_node_set_toggled(n, s->toggled ? ACCESSKIT_TOGGLED_TRUE : ACCESSKIT_TOGGLED_FALSE);
    accesskit_tree_update_push_node(u, s->id, n);
  }
  LeaveCriticalSection(&g_lock);
  return u;
}

/* Publishes the snapshot built since ak_begin and tells AccessKit (if a screen reader or
 * another UI Automation client is listening). */
void ak_publish(uint64_t root, uint64_t focus) {
  lockInit();
  EnterCriticalSection(&g_lock);
  AkSnap old = g_snap;
  g_snap = g_next;
  g_snap.root = root;
  g_snap.focus = focus;
  g_next = old;
  LeaveCriticalSection(&g_lock);
  snapFree(&g_next);
  if (g_adapter) {
    accesskit_windows_queued_events* ev = accesskit_windows_subclassing_adapter_update_if_active(g_adapter, buildUpdate, NULL);
    if (ev) accesskit_windows_queued_events_raise(ev);
  }
}

/* --- the window adapter and actions ---------------------------------------------------- */

static void onAction(accesskit_action_request* req, void* userdata) {
  (void)userdata;
  EnterCriticalSection(&g_lock);
  if (g_qn < 64) {
    int a = req->action == ACCESSKIT_ACTION_CLICK ? 1 : req->action == ACCESSKIT_ACTION_FOCUS ? 2 : 0;
    if (a) { g_q[g_qn].action = a; g_q[g_qn].node = req->target_node; g_qn++; }
  }
  LeaveCriticalSection(&g_lock);
  accesskit_action_request_free(req);
  if (g_wake) g_wake();
}

static accesskit_tree_update* onActivate(void* userdata) { return buildUpdate(userdata); }

/* Attaches to a window (its HWND): from now on UI Automation sees the published tree. */
int ak_attach(void* hwnd) {
  lockInit();
  if (g_adapter || !hwnd) return g_adapter != NULL;
  g_adapter = accesskit_windows_subclassing_adapter_new((HWND)hwnd, onActivate, NULL, onAction, NULL);
  return g_adapter != NULL;
}

void ak_detach(void) {
  if (g_adapter) accesskit_windows_subclassing_adapter_free(g_adapter);
  g_adapter = NULL;
}

/* The next action a screen reader asked for: 1 click, 2 focus (0 = none waiting). */
int ak_take_action(uint64_t* node) {
  lockInit();
  EnterCriticalSection(&g_lock);
  int a = 0;
  if (g_qn > 0) {
    a = g_q[0].action;
    *node = g_q[0].node;
    memmove(g_q, g_q + 1, sizeof(AkReq) * (size_t)(g_qn - 1));
    g_qn--;
  }
  LeaveCriticalSection(&g_lock);
  return a;
}

/* For tests: the published snapshot's size and one node's label/role. */
int ak_published_count(void) { lockInit(); EnterCriticalSection(&g_lock); int n = g_snap.n; LeaveCriticalSection(&g_lock); return n; }
