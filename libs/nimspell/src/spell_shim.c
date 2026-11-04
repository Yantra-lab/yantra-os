/* nimspell — the Windows spell checker (ISpellChecker, Windows 8+) for Yantra's text fields
 * (Q9). Other systems: no spelling errors, no suggestions. Text is UTF-8 on our side. */
#include <string.h>
#ifdef _WIN32
#define COBJMACROS
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00   /* the spell checker API is declared for Windows 8+ targets */
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000000
#endif
#include <windows.h>
#include <stdlib.h>
#include <initguid.h>   /* the spell checker's GUIDs are defined here (not in libuuid) */
#include <spellcheck.h>

static ISpellChecker* g_sc = NULL;

int ysp_open(const char* lang) {
  if (g_sc) return 1;
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  ISpellCheckerFactory* f = NULL;
  if (FAILED(CoCreateInstance(&CLSID_SpellCheckerFactory, NULL, CLSCTX_INPROC_SERVER, &IID_ISpellCheckerFactory, (void**)&f))) return 0;
  wchar_t tag[32];
  MultiByteToWideChar(CP_UTF8, 0, lang && lang[0] ? lang : "en-US", -1, tag, 32);
  BOOL ok = FALSE;
  ISpellCheckerFactory_IsSupported(f, tag, &ok);
  if (!ok) MultiByteToWideChar(CP_UTF8, 0, "en-US", -1, tag, 32);
  HRESULT hr = ISpellCheckerFactory_CreateSpellChecker(f, tag, &g_sc);
  ISpellCheckerFactory_Release(f);
  return SUCCEEDED(hr) && g_sc ? 1 : 0;
}

static int u16ToByte(const char* s, int len, int u16) {
  int u = 0, i = 0;
  while (i < len && u < u16) {
    unsigned char c = (unsigned char)s[i];
    int n = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
    u += n == 4 ? 2 : 1;
    i += n;
  }
  return i > len ? len : i;
}

/* Misspelled words in `s`: up to `max` (start, end) byte pairs into `out`; how many. */
int ysp_check(const char* s, int len, int* out, int max) {
  if (!g_sc || len <= 0) return 0;
  int wn = MultiByteToWideChar(CP_UTF8, 0, s, len, NULL, 0);
  wchar_t* w = (wchar_t*)malloc(sizeof(wchar_t) * (wn + 1));
  if (!w) return 0;
  MultiByteToWideChar(CP_UTF8, 0, s, len, w, wn);
  w[wn] = 0;
  IEnumSpellingError* errs = NULL;
  int n = 0;
  if (SUCCEEDED(ISpellChecker_Check(g_sc, w, &errs)) && errs) {
    ISpellingError* e = NULL;
    while (n < max && IEnumSpellingError_Next(errs, &e) == S_OK && e) {
      ULONG st = 0, ln = 0;
      ISpellingError_get_StartIndex(e, &st);
      ISpellingError_get_Length(e, &ln);
      out[2 * n] = u16ToByte(s, len, (int)st);
      out[2 * n + 1] = u16ToByte(s, len, (int)(st + ln));
      n++;
      ISpellingError_Release(e);
      e = NULL;
    }
    IEnumSpellingError_Release(errs);
  }
  free(w);
  return n;
}

/* Suggestions for `word`, one per line, into `out` (cap bytes); the bytes written. */
int ysp_suggest(const char* word, char* out, int cap) {
  if (!g_sc || !word || cap <= 0) return 0;
  wchar_t w[256];
  MultiByteToWideChar(CP_UTF8, 0, word, -1, w, 256);
  IEnumString* sugs = NULL;
  int at = 0;
  if (SUCCEEDED(ISpellChecker_Suggest(g_sc, w, &sugs)) && sugs) {
    LPOLESTR s = NULL;
    ULONG got = 0;
    int k = 0;
    while (k < 8 && IEnumString_Next(sugs, 1, &s, &got) == S_OK && got == 1) {
      char buf[512];
      int b = WideCharToMultiByte(CP_UTF8, 0, s, -1, buf, sizeof buf, NULL, NULL);
      CoTaskMemFree(s);
      if (b > 1 && at + b < cap) {
        if (at > 0) out[at++] = '\n';
        memcpy(out + at, buf, (size_t)b - 1);
        at += b - 1;
      }
      k++;
    }
    IEnumString_Release(sugs);
  }
  if (at < cap) out[at] = 0;
  return at;
}

/* Tells the checker a word is right from now on (Add to dictionary). */
void ysp_add(const char* word) {
  if (!g_sc || !word) return;
  wchar_t w[256];
  MultiByteToWideChar(CP_UTF8, 0, word, -1, w, 256);
  ISpellChecker_Add(g_sc, w);
}
#else
int ysp_open(const char* lang) { (void)lang; return 0; }
int ysp_check(const char* s, int len, int* out, int max) { (void)s; (void)len; (void)out; (void)max; return 0; }
int ysp_suggest(const char* word, char* out, int cap) { (void)word; if (cap > 0) out[0] = 0; return 0; }
void ysp_add(const char* word) { (void)word; }
#endif
