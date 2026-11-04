/* sdl_shim.c — the slice of SDL3 the Yantra native engine uses: one window, a
 * streaming texture the engine paints into, and events flattened into one small
 * struct so Nim never has to mirror SDL's event union layout. */
#include <SDL3/SDL.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#include <shellapi.h>
#endif

typedef struct {
  int type;          /* see YS_* below */
  float x, y;        /* pointer position in window pixels (not points) */
  int button;        /* 1 left, 2 middle, 3 right */
  int key;           /* SDL_Keycode for key events */
  int mods;          /* SDL_Keymod */
  float wheel;       /* vertical wheel delta, positive = away from the user */
  int w, h;          /* new size in pixels for resize events */
  char text[512];     /* UTF-8 for text input events and file drop paths */
  float dx, dy;      /* raw pointer movement in pixels (motion), also under pointer lock */
} YsEvent;

enum { YS_NONE = 0, YS_QUIT, YS_MOVE, YS_DOWN, YS_UP, YS_WHEEL, YS_KEY, YS_TEXT, YS_RESIZE, YS_EXPOSE, YS_EDITING,
       YS_DROP, YS_MENU, YS_THEME, YS_LINK, YS_KEYUP };


typedef struct {
  SDL_Window* win;
  SDL_Renderer* ren;
  SDL_Texture* tex;
  int tw, th;
  SDL_GLContext gl;  /* set for GPU windows: Skia draws straight into its framebuffer */
} YsWindow;

static int g_initialised = 0;

int ys_init(int headless) {
  if (headless) SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "dummy");
  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) return 0;
  SDL_InitSubSystem(SDL_INIT_GAMEPAD);   /* games: optional, so a failure here is not fatal */
  g_initialised = 1;
  return 1;
}

void ys_quit(void) { if (g_initialised) SDL_Quit(); g_initialised = 0; }

const char* ys_error(void) { return SDL_GetError(); }

YsWindow* ys_window(const char* title, int w, int h) {
  YsWindow* y = (YsWindow*)SDL_calloc(1, sizeof(YsWindow));
  /* created hidden: things that must attach before the first show (accessibility) can;
     ys_show then puts it on screen */
  y->win = SDL_CreateWindow(title, w, h, SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN);
  if (!y->win) { SDL_free(y); return NULL; }
  y->ren = SDL_CreateRenderer(y->win, NULL);
  if (!y->ren) { SDL_DestroyWindow(y->win); SDL_free(y); return NULL; }
  SDL_SetRenderVSync(y->ren, 1);
  SDL_StartTextInput(y->win);
  return y;
}

void ys_destroy(YsWindow* y) {
  if (!y) return;
  if (y->tex) SDL_DestroyTexture(y->tex);
  if (y->ren) SDL_DestroyRenderer(y->ren);
  if (y->gl) SDL_GL_DestroyContext(y->gl);
  SDL_DestroyWindow(y->win);
  SDL_free(y);
}

void ys_pixel_size(YsWindow* y, int* w, int* h) { SDL_GetWindowSizeInPixels(y->win, w, h); }
float ys_density(YsWindow* y) { return SDL_GetWindowPixelDensity(y->win); }
void ys_set_title(YsWindow* y, const char* t) { SDL_SetWindowTitle(y->win, t); }

/* Uploads a 32-bit BGRA/premultiplied frame (Skia's N32 on little-endian) and shows it. */
int ys_present(YsWindow* y, const void* pixels, int w, int h, int pitch) {
  if (!y->tex || y->tw != w || y->th != h) {
    if (y->tex) SDL_DestroyTexture(y->tex);
    y->tex = SDL_CreateTexture(y->ren, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h);
    if (!y->tex) return 0;
    SDL_SetTextureBlendMode(y->tex, SDL_BLENDMODE_NONE);
    y->tw = w; y->th = h;
  }
  if (!SDL_UpdateTexture(y->tex, NULL, pixels, pitch)) return 0;
  SDL_RenderTexture(y->ren, y->tex, NULL, NULL);
  SDL_RenderPresent(y->ren);
  return 1;
}

void ys_cursor(int kind) {
  static SDL_Cursor* cursors[3] = {0};
  SDL_SystemCursor ids[3] = {SDL_SYSTEM_CURSOR_DEFAULT, SDL_SYSTEM_CURSOR_POINTER, SDL_SYSTEM_CURSOR_TEXT};
  if (kind < 0 || kind > 2) kind = 0;
  if (!cursors[kind]) cursors[kind] = SDL_CreateSystemCursor(ids[kind]);
  if (cursors[kind]) SDL_SetCursor(cursors[kind]);
}

unsigned long long ys_ticks_ms(void) { return SDL_GetTicks(); }

/* Pointer lock (games): the pointer hides and stays put; motion still reports raw movement. */
void ys_pointer_lock(YsWindow* w, int on) { if (w && w->win) SDL_SetWindowRelativeMouseMode(w->win, on != 0); }

/* The first gamepad's state: 6 axes (left x/y, right x/y, triggers; -1..1, triggers 0..1) and a
   button bitmask (SDL_GamepadButton order). 0 if none is connected. */
int ys_gamepad(float* axes, int* buttons) {
  static SDL_Gamepad* pad = NULL;
  if (pad && !SDL_GamepadConnected(pad)) { SDL_CloseGamepad(pad); pad = NULL; }
  if (!pad) {
    int n = 0;
    SDL_JoystickID* ids = SDL_GetGamepads(&n);
    if (ids && n > 0) pad = SDL_OpenGamepad(ids[0]);
    SDL_free(ids);
    if (!pad) return 0;
  }
  for (int i = 0; i < 6; i++) axes[i] = SDL_GetGamepadAxis(pad, (SDL_GamepadAxis)i) / 32767.0f;
  int b = 0;
  for (int i = 0; i < 26 && i < SDL_GAMEPAD_BUTTON_COUNT; i++) if (SDL_GetGamepadButton(pad, (SDL_GamepadButton)i)) b |= 1 << i;
  *buttons = b;
  return 1;
}

static Uint32 ys_user_event(void) {
  static Uint32 t = 0;
  if (!t) t = SDL_RegisterEvents(1);
  return t;
}

static void fill(YsEvent* o, const SDL_Event* e, float density) {
  memset(o, 0, sizeof(*o));
  switch (e->type) {
    case SDL_EVENT_QUIT: case SDL_EVENT_WINDOW_CLOSE_REQUESTED: o->type = YS_QUIT; break;
    case SDL_EVENT_MOUSE_MOTION:
      o->type = YS_MOVE; o->x = e->motion.x * density; o->y = e->motion.y * density;
      o->dx = e->motion.xrel * density; o->dy = e->motion.yrel * density; break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
      o->type = e->type == SDL_EVENT_MOUSE_BUTTON_DOWN ? YS_DOWN : YS_UP;
      o->x = e->button.x * density; o->y = e->button.y * density; o->button = e->button.button; break;
    case SDL_EVENT_MOUSE_WHEEL: o->type = YS_WHEEL; o->wheel = e->wheel.y; o->x = e->wheel.mouse_x * density; o->y = e->wheel.mouse_y * density; break;
    case SDL_EVENT_KEY_DOWN: o->type = YS_KEY; o->key = (int)e->key.key; o->mods = (int)e->key.mod; o->button = e->key.repeat; break;
    case SDL_EVENT_KEY_UP: o->type = YS_KEYUP; o->key = (int)e->key.key; o->mods = (int)e->key.mod; break;
    case SDL_EVENT_TEXT_INPUT:
      o->type = YS_TEXT;
      if (e->text.text) { strncpy(o->text, e->text.text, sizeof(o->text) - 1); }
      break;
    case SDL_EVENT_TEXT_EDITING:           /* an input method's word in progress (IME) */
      o->type = YS_EDITING;
      if (e->edit.text) { strncpy(o->text, e->edit.text, sizeof(o->text) - 1); }
      o->button = e->edit.start;         /* the cursor inside it, in characters */
      break;
    case SDL_EVENT_DROP_FILE:
      o->type = YS_DROP; o->x = e->drop.x * density; o->y = e->drop.y * density;
      if (e->drop.data) { strncpy(o->text, e->drop.data, sizeof(o->text) - 1); }
      break;
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED: o->type = YS_RESIZE; o->w = e->window.data1; o->h = e->window.data2; break;
    case SDL_EVENT_WINDOW_EXPOSED: o->type = YS_EXPOSE; break;
    case SDL_EVENT_SYSTEM_THEME_CHANGED: o->type = YS_THEME; break;
    default:
      if (e->type == ys_user_event() && e->user.code == 1) { o->type = YS_MENU; o->button = (int)(intptr_t)e->user.data1; break; }
      if (e->type == ys_user_event() && e->user.code == 2) { o->type = YS_LINK; break; }
      o->type = YS_NONE; break;
  }
}

/* Waits up to `timeout_ms` for an event (-1 = forever, 0 = poll). Returns 1 if one was read. */
int ys_wait(YsWindow* y, YsEvent* out, int timeout_ms) {
  SDL_Event e;
  int got = timeout_ms == 0 ? SDL_PollEvent(&e) : SDL_WaitEventTimeout(&e, timeout_ms);
  if (!got) return 0;
  fill(out, &e, y ? SDL_GetWindowPixelDensity(y->win) : 1.0f);
  return 1;
}

/* Test support: push a synthetic event through SDL's own queue. */
void ys_push_click(float x, float y, int down) {
  SDL_Event e; memset(&e, 0, sizeof(e));
  e.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
  e.button.button = SDL_BUTTON_LEFT; e.button.x = x; e.button.y = y; e.button.down = down;
  SDL_PushEvent(&e);
}

void ys_push_text(const char* s) {
  SDL_Event e; memset(&e, 0, sizeof(e));
  e.type = SDL_EVENT_TEXT_INPUT; e.text.text = SDL_strdup(s);
  SDL_PushEvent(&e);
}

void ys_push_drop(const char* s, float x, float y) {
  SDL_Event e; memset(&e, 0, sizeof(e));
  e.type = SDL_EVENT_DROP_FILE; e.drop.data = SDL_strdup(s); e.drop.x = x; e.drop.y = y;
  SDL_PushEvent(&e);
}

/* The system clipboard (UTF-8). The returned text is freed with ys_free. */
int ys_clipboard_set(const char* s) { return SDL_SetClipboardText(s) ? 1 : 0; }
char* ys_clipboard_get(void) { return SDL_GetClipboardText(); }
void ys_free(void* p) { SDL_free(p); }

/* A window with an OpenGL context for GPU drawing (Skia's GL backend draws into its
 * default framebuffer; ys_gl_swap shows the frame). `hidden` makes an off-screen one
 * for tests. NULL if there is no usable OpenGL. */
YsWindow* ys_gl_window(const char* title, int w, int h, int hidden) {
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
  YsWindow* y = (YsWindow*)SDL_calloc(1, sizeof(YsWindow));
  SDL_WindowFlags f = SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN;
  (void)hidden;                          /* always created hidden; ys_show shows it */
  y->win = SDL_CreateWindow(title, w, h, f);
  if (!y->win) { SDL_free(y); return NULL; }
  y->gl = SDL_GL_CreateContext(y->win);
  if (!y->gl) { SDL_DestroyWindow(y->win); SDL_free(y); return NULL; }
  SDL_GL_MakeCurrent(y->win, y->gl);
  SDL_GL_SetSwapInterval(1);
  if (!hidden) SDL_StartTextInput(y->win);
  return y;
}

void ys_gl_swap(YsWindow* y) { SDL_GL_SwapWindow(y->win); }

/* The window's native handle (HWND on Windows): accessibility adapters attach to it. */
void* ys_native_handle(YsWindow* y) {
  return SDL_GetPointerProperty(SDL_GetWindowProperties(y->win), SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
}

/* Wakes a loop sleeping in ys_wait (safe from any thread): e.g. a screen reader acted. */
void ys_wake(void) {
  SDL_Event e; memset(&e, 0, sizeof(e));
  e.type = SDL_EVENT_USER;
  SDL_PushEvent(&e);
}

/* Puts a window on screen (windows are created hidden). */
void ys_show(YsWindow* y) { SDL_ShowWindow(y->win); SDL_RaiseWindow(y->win); }

/* Where the text cursor is (window points): the input method puts its candidates there. */
void ys_set_text_area(YsWindow* y, int x, int yy, int w, int h, int cursor) {
  SDL_Rect r = {x, yy, w, h};
  SDL_SetTextInputArea(y->win, &r, cursor);
}

/* Test support: an input method composing `s` with the cursor at `start`. */
void ys_push_editing(const char* s, int start) {
  SDL_Event e; memset(&e, 0, sizeof(e));
  e.type = SDL_EVENT_TEXT_EDITING; e.edit.text = SDL_strdup(s); e.edit.start = start; e.edit.length = 0;
  SDL_PushEvent(&e);
}

/* --- OS integration (Q8) --------------------------------------------------------------

 * Frameless windows with drag regions, window buttons, the system theme and accent,
 * opening URLs, a native menubar, deep links into the running app, a taskbar badge. */
#define YS_MAX_REGIONS 64
static SDL_FRect g_drag[YS_MAX_REGIONS], g_nodrag[YS_MAX_REGIONS];
static int g_nDrag = 0, g_nNoDrag = 0, g_frameless = 0;

static SDL_HitTestResult hitTest(SDL_Window* win, const SDL_Point* p, void* data) {
  (void)data;
  int w, h;
  SDL_GetWindowSize(win, &w, &h);
  const int edge = 6;
  if (g_frameless && !(SDL_GetWindowFlags(win) & SDL_WINDOW_MAXIMIZED)) {   /* resize from the edges */
    int l = p->x < edge, r = p->x >= w - edge, t = p->y < edge, b = p->y >= h - edge;
    if (t && l) return SDL_HITTEST_RESIZE_TOPLEFT;
    if (t && r) return SDL_HITTEST_RESIZE_TOPRIGHT;
    if (b && l) return SDL_HITTEST_RESIZE_BOTTOMLEFT;
    if (b && r) return SDL_HITTEST_RESIZE_BOTTOMRIGHT;
    if (t) return SDL_HITTEST_RESIZE_TOP;
    if (b) return SDL_HITTEST_RESIZE_BOTTOM;
    if (l) return SDL_HITTEST_RESIZE_LEFT;
    if (r) return SDL_HITTEST_RESIZE_RIGHT;
  }
  SDL_FPoint q = {(float)p->x, (float)p->y};
  for (int i = 0; i < g_nNoDrag; ++i) if (SDL_PointInRectFloat(&q, &g_nodrag[i])) return SDL_HITTEST_NORMAL;
  for (int i = 0; i < g_nDrag; ++i) if (SDL_PointInRectFloat(&q, &g_drag[i])) return SDL_HITTEST_DRAGGABLE;
  return SDL_HITTEST_NORMAL;
}

/* No system frame: the app draws its own title bar. */
void ys_set_frameless(YsWindow* y, int frameless) {
  g_frameless = frameless;
  SDL_SetWindowBordered(y->win, !frameless);
  SDL_SetWindowHitTest(y->win, hitTest, NULL);
}

/* Where the window can be dragged by (and, inside those, what stays clickable), in points. */
void ys_set_regions(const float* drag, int nDrag, const float* noDrag, int nNoDrag) {
  g_nDrag = nDrag < YS_MAX_REGIONS ? nDrag : YS_MAX_REGIONS;
  g_nNoDrag = nNoDrag < YS_MAX_REGIONS ? nNoDrag : YS_MAX_REGIONS;
  for (int i = 0; i < g_nDrag; ++i) g_drag[i] = (SDL_FRect){drag[4 * i], drag[4 * i + 1], drag[4 * i + 2], drag[4 * i + 3]};
  for (int i = 0; i < g_nNoDrag; ++i) g_nodrag[i] = (SDL_FRect){noDrag[4 * i], noDrag[4 * i + 1], noDrag[4 * i + 2], noDrag[4 * i + 3]};
}

/* 1 minimise, 2 maximise / restore, 3 close, 4 fullscreen on / off. */
void ys_window_op(YsWindow* y, int op) {
  if (op == 1) SDL_MinimizeWindow(y->win);
  else if (op == 2) { if (SDL_GetWindowFlags(y->win) & SDL_WINDOW_MAXIMIZED) SDL_RestoreWindow(y->win); else SDL_MaximizeWindow(y->win); }
  else if (op == 3) { SDL_Event e; memset(&e, 0, sizeof e); e.type = SDL_EVENT_QUIT; SDL_PushEvent(&e); }
  else if (op == 4) SDL_SetWindowFullscreen(y->win, !(SDL_GetWindowFlags(y->win) & SDL_WINDOW_FULLSCREEN));
}

/* 0 unknown, 1 light, 2 dark. */
int ys_system_theme(void) {
  SDL_SystemTheme t = SDL_GetSystemTheme();
  return t == SDL_SYSTEM_THEME_LIGHT ? 1 : t == SDL_SYSTEM_THEME_DARK ? 2 : 0;
}

/* Opens a URL with the system (the browser, the mail app). */
int ys_open_url(const char* url) { return SDL_OpenURL(url) ? 1 : 0; }

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dwmapi.h>
#include <shobjidl.h>

static HWND hwndOf(YsWindow* y) {
  return (HWND)SDL_GetPointerProperty(SDL_GetWindowProperties(y->win), SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
}

/* The accent colour (0xAARRGGBB), or 0. */
unsigned ys_accent_color(void) {
  DWORD c = 0; BOOL opaque = FALSE;
  if (SUCCEEDED(DwmGetColorizationColor(&c, &opaque))) return (unsigned)c | 0xFF000000u;
  return 0;
}

/* Menus: "File|New:1|Open:2|-|Quit:3;Edit|Copy:4" — WM_COMMAND ids come back as YS_MENU. */
static bool SDLCALL menuHook(void* data, MSG* msg) {
  (void)data;
  if (msg->message == WM_COMMAND && HIWORD(msg->wParam) == 0) {
    SDL_Event e; memset(&e, 0, sizeof e);
    e.type = ys_user_event(); e.user.code = 1; e.user.data1 = (void*)(intptr_t)LOWORD(msg->wParam);
    SDL_PushEvent(&e);
  }
  return true;
}

static void wide(const char* s, int n, wchar_t* out, int cap) {
  int k = MultiByteToWideChar(CP_UTF8, 0, s, n, out, cap - 1);
  out[k < 0 ? 0 : k] = 0;
}

void ys_set_menu(YsWindow* y, const char* spec) {
  HWND h = hwndOf(y);
  if (!h) return;
  HMENU old = GetMenu(h);
  if (!spec || !spec[0]) { SetMenu(h, NULL); if (old) DestroyMenu(old); return; }
  HMENU bar = CreateMenu();
  const char* p = spec;
  while (*p) {
    const char* end = strchr(p, ';'); if (!end) end = p + strlen(p);
    HMENU sub = CreatePopupMenu();
    const char* q = p; const char* bar1 = memchr(q, '|', end - q); if (!bar1) bar1 = end;
    wchar_t title[128]; wide(q, (int)(bar1 - q), title, 128);
    q = bar1;
    while (q < end) {
      ++q;                                   /* past '|' */
      const char* e2 = memchr(q, '|', end - q); if (!e2) e2 = end;
      if (e2 - q == 1 && *q == '-') AppendMenuW(sub, MF_SEPARATOR, 0, NULL);
      else {
        const char* colon = NULL;
        for (const char* c = q; c < e2; ++c) if (*c == ':') colon = c;
        wchar_t item[128]; wide(q, (int)((colon ? colon : e2) - q), item, 128);
        AppendMenuW(sub, MF_STRING, colon ? (UINT_PTR)atoi(colon + 1) : 0, item);
      }
      q = e2;
    }
    AppendMenuW(bar, MF_POPUP, (UINT_PTR)sub, title);
    p = *end ? end + 1 : end;
  }
  SetMenu(h, bar);
  if (old) DestroyMenu(old);
  SDL_SetWindowsMessageHook(menuHook, NULL);
}

/* The taskbar badge: a red dot with `count` on the app's taskbar button (0 = none). */
void ys_set_badge(YsWindow* y, int count) {
  static ITaskbarList3* tb = NULL;
  HWND h = hwndOf(y);
  if (!h) return;
  if (!tb) {
    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(CoCreateInstance(&CLSID_TaskbarList, NULL, CLSCTX_INPROC_SERVER, &IID_ITaskbarList3, (void**)&tb))) { tb = NULL; return; }
    tb->lpVtbl->HrInit(tb);
  }
  if (count <= 0) { tb->lpVtbl->SetOverlayIcon(tb, h, NULL, L""); return; }
  const int S = 16;
  BITMAPINFO bi; memset(&bi, 0, sizeof bi);
  bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER); bi.bmiHeader.biWidth = S; bi.bmiHeader.biHeight = -S;
  bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32; bi.bmiHeader.biCompression = BI_RGB;
  void* bits = NULL;
  HDC dc = CreateCompatibleDC(NULL);
  HBITMAP col = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
  HGDIOBJ was = SelectObject(dc, col);
  memset(bits, 0, S * S * 4);
  HBRUSH red = CreateSolidBrush(RGB(0xE5, 0x39, 0x35));
  HGDIOBJ wb = SelectObject(dc, red);
  SelectObject(dc, GetStockObject(NULL_PEN));
  Ellipse(dc, 0, 0, S + 1, S + 1);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(255, 255, 255));
  HFONT f = CreateFontW(count > 9 ? -9 : -11, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
  HGDIOBJ wf = SelectObject(dc, f);
  wchar_t num[8]; if (count > 99) wcscpy(num, L"99"); else wsprintfW(num, L"%d", count);
  RECT rc = {0, 0, S, S};
  DrawTextW(dc, num, -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(dc, wf); DeleteObject(f);
  SelectObject(dc, wb); DeleteObject(red);
  unsigned* px = (unsigned*)bits;          /* GDI leaves alpha 0: make the drawn circle opaque */
  for (int i = 0; i < S * S; ++i) if (px[i] & 0x00FFFFFF) px[i] |= 0xFF000000u;
  SelectObject(dc, was);
  HBITMAP mask = CreateBitmap(S, S, 1, 1, NULL);
  ICONINFO ii = {TRUE, 0, 0, mask, col};
  HICON icon = CreateIconIndirect(&ii);
  wchar_t desc[32]; wsprintfW(desc, L"%d new", count);
  tb->lpVtbl->SetOverlayIcon(tb, h, icon, desc);
  DestroyIcon(icon); DeleteObject(mask); DeleteObject(col); DeleteDC(dc);
}

/* Deep links: `ys_link_listen("app")` makes a hidden window a second launch can find;
 * `ys_link_send("app", url)` hands it the URL (then the second launch exits). */
static char g_link[4096];
static LRESULT CALLBACK linkProc(HWND h, UINT m, WPARAM w, LPARAM l) {
  if (m == WM_COPYDATA) {
    COPYDATASTRUCT* cd = (COPYDATASTRUCT*)l;
    size_t n = cd->cbData < sizeof g_link - 1 ? cd->cbData : sizeof g_link - 1;
    memcpy(g_link, cd->lpData, n); g_link[n] = 0;
    SDL_Event e; memset(&e, 0, sizeof e); e.type = ys_user_event(); e.user.code = 2;
    SDL_PushEvent(&e);
    return TRUE;
  }
  return DefWindowProcW(h, m, w, l);
}
static void linkClass(const char* app, wchar_t* out) {
  wchar_t a[96]; wide(app, -1, a, 96);
  wsprintfW(out, L"YantraLink-%s", a);
}
int ys_link_listen(const char* app) {
  wchar_t cls[128]; linkClass(app, cls);
  WNDCLASSW wc; memset(&wc, 0, sizeof wc);
  wc.lpfnWndProc = linkProc; wc.hInstance = GetModuleHandleW(NULL); wc.lpszClassName = cls;
  RegisterClassW(&wc);
  return CreateWindowExW(0, cls, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, wc.hInstance, NULL) != NULL;
}
int ys_link_send(const char* app, const char* url) {
  wchar_t cls[128]; linkClass(app, cls);
  HWND h = FindWindowExW(HWND_MESSAGE, NULL, cls, NULL);
  if (!h) return 0;
  COPYDATASTRUCT cd = {1, (DWORD)strlen(url), (PVOID)url};
  return SendMessageW(h, WM_COPYDATA, 0, (LPARAM)&cd) ? 1 : 0;
}
const char* ys_link_take(void) { return g_link; }

/* `scheme://…` opens `exe` with the URL as its last argument (per user, no admin rights). */
int ys_register_scheme(const char* scheme, const char* command) {
  wchar_t ws[64], cmd[1024], key[256];
  wide(scheme, -1, ws, 64); wide(command, -1, cmd, 1024);
  wsprintfW(key, L"Software\\Classes\\%s", ws);
  HKEY k;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key, 0, NULL, 0, KEY_WRITE, NULL, &k, NULL) != ERROR_SUCCESS) return 0;
  wchar_t desc[96]; wsprintfW(desc, L"URL:%s", ws);
  RegSetValueExW(k, NULL, 0, REG_SZ, (const BYTE*)desc, (DWORD)((wcslen(desc) + 1) * 2));
  RegSetValueExW(k, L"URL Protocol", 0, REG_SZ, (const BYTE*)L"", 2);
  HKEY c;
  int ok = RegCreateKeyExW(k, L"shell\\open\\command", 0, NULL, 0, KEY_WRITE, NULL, &c, NULL) == ERROR_SUCCESS;
  if (ok) { RegSetValueExW(c, NULL, 0, REG_SZ, (const BYTE*)cmd, (DWORD)((wcslen(cmd) + 1) * 2)); RegCloseKey(c); }
  RegCloseKey(k);
  return ok;
}
#else
unsigned ys_accent_color(void) { return 0; }
void ys_set_menu(YsWindow* y, const char* spec) { (void)y; (void)spec; }
void ys_set_badge(YsWindow* y, int count) { (void)y; (void)count; }
int ys_link_listen(const char* app) { (void)app; return 0; }
int ys_link_send(const char* app, const char* url) { (void)app; (void)url; return 0; }
const char* ys_link_take(void) { return ""; }
int ys_register_scheme(const char* scheme, const char* command) { (void)scheme; (void)command; return 0; }
#endif

typedef void (*YsFileCallback)(void* userdata, const char* path);

typedef struct { YsFileCallback cb; void* ud; } YsDialogReq;
static char g_mock_open[1024] = {0}, g_mock_save[1024] = {0};
static int g_mock_open_active = 0, g_mock_save_active = 0;

static void SDLCALL on_dlg_done(void* userdata, const char* const* filelist, int filter) {
  (void)filter;
  YsDialogReq* req = (YsDialogReq*)userdata;
  const char* path = (filelist && *filelist && **filelist) ? *filelist : "";
  if (req) { if (req->cb) req->cb(req->ud, path); free(req); }
}

void ys_show_open_file(void* win, const char* filters, YsFileCallback cb, void* ud) {
  (void)filters;
  if (g_mock_open_active) { if (cb) cb(ud, g_mock_open); return; }
  YsWindow* y = (YsWindow*)win;
  YsDialogReq* req = (YsDialogReq*)malloc(sizeof(YsDialogReq));
  if (req) { req->cb = cb; req->ud = ud; SDL_ShowOpenFileDialog(on_dlg_done, req, y ? y->win : NULL, NULL, 0, NULL, false); }
}

void ys_show_save_file(void* win, const char* default_name, const char* filters, YsFileCallback cb, void* ud) {
  (void)filters;
  if (g_mock_save_active) { if (cb) cb(ud, g_mock_save); return; }
  YsWindow* y = (YsWindow*)win;
  YsDialogReq* req = (YsDialogReq*)malloc(sizeof(YsDialogReq));
  if (req) { req->cb = cb; req->ud = ud; SDL_ShowSaveFileDialog(on_dlg_done, req, y ? y->win : NULL, NULL, 0, default_name); }
}

static void set_mock(char* dst, int* act, const char* src, size_t sz) {
  *act = (src != NULL);
  if (src) { strncpy(dst, src, sz - 1); dst[sz - 1] = '\0'; } else dst[0] = '\0';
}
void ys_set_mock_open_file(const char* p) { set_mock(g_mock_open, &g_mock_open_active, p, sizeof(g_mock_open)); }
void ys_set_mock_save_file(const char* p) { set_mock(g_mock_save, &g_mock_save_active, p, sizeof(g_mock_save)); }

static char g_last_notify_title[512] = {0};
static char g_last_notify_body[1024] = {0};
static int g_notify_count = 0;

void ys_show_notification(void* win, const char* title, const char* body) {
  if (title) { strncpy(g_last_notify_title, title, sizeof(g_last_notify_title) - 1); g_last_notify_title[sizeof(g_last_notify_title) - 1] = '\0'; }
  else g_last_notify_title[0] = '\0';
  if (body) { strncpy(g_last_notify_body, body, sizeof(g_last_notify_body) - 1); g_last_notify_body[sizeof(g_last_notify_body) - 1] = '\0'; }
  else g_last_notify_body[0] = '\0';
  g_notify_count++;

#if defined(_WIN32)
  NOTIFYICONDATAW nid;
  memset(&nid, 0, sizeof(nid));
  nid.cbSize = sizeof(NOTIFYICONDATAW);
  HWND hwnd = NULL;
  if (win) {
    YsWindow* y = (YsWindow*)win;
    if (y && y->win) {
      hwnd = (HWND)SDL_GetPointerProperty(SDL_GetWindowProperties(y->win), SDL_PROP_WINDOW_WIN32_HWND_POINTER, NULL);
    }
  }
  if (!hwnd) hwnd = GetDesktopWindow();
  nid.hWnd = hwnd;
  nid.uID = 1001;
  nid.uFlags = NIF_INFO | NIF_TIP;
  nid.dwInfoFlags = NIIF_INFO;
  if (title) MultiByteToWideChar(CP_UTF8, 0, title, -1, nid.szInfoTitle, 64);
  if (body) MultiByteToWideChar(CP_UTF8, 0, body, -1, nid.szInfo, 256);
  Shell_NotifyIconW(NIM_ADD, &nid);
#endif
}

const char* ys_last_notify_title(void) { return g_last_notify_title; }
const char* ys_last_notify_body(void) { return g_last_notify_body; }
int ys_notify_count(void) { return g_notify_count; }

