/*
 * Yantra mini-libc — implementations.
 *
 * Compile:  clang --target=wasm32-unknown-unknown -nostdlib -ffreestanding
 * Link:     -Wl,--no-entry -Wl,--export-all -Wl,--allow-undefined
 *
 * DESIGN NOTE ON THE ALLOCATOR: this is a bump allocator that never frees.
 * That is not laziness - a sandboxed app module's whole linear memory is
 * reclaimed by the host when the module is dropped, so per-allocation free is
 * pure overhead. `free` is deliberately a no-op, and that is stated here rather
 * than hidden.
 */

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>

/* ====================================================================== */
/* memory primitives                                                       */
/* ====================================================================== */

void *memcpy(void *dest, const void *src, size_t n) {
  unsigned char *d = (unsigned char *)dest;
  const unsigned char *s = (const unsigned char *)src;
  /* wasm bulk-memory; clang emits memory.copy for this idiom. */
  for (size_t i = 0; i < n; i++) d[i] = s[i];
  return dest;
}

void *memmove(void *dest, const void *src, size_t n) {
  unsigned char *d = (unsigned char *)dest;
  const unsigned char *s = (const unsigned char *)src;
  if (d == s || n == 0) return dest;
  if (d < s) {
    for (size_t i = 0; i < n; i++) d[i] = s[i];
  } else {
    for (size_t i = n; i > 0; i--) d[i - 1] = s[i - 1];
  }
  return dest;
}

void *memset(void *s, int c, size_t n) {
  unsigned char *p = (unsigned char *)s;
  for (size_t i = 0; i < n; i++) p[i] = (unsigned char)c;
  return s;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  const unsigned char *a = (const unsigned char *)s1;
  const unsigned char *b = (const unsigned char *)s2;
  for (size_t i = 0; i < n; i++) {
    if (a[i] != b[i]) return (int)a[i] - (int)b[i];
  }
  return 0;
}

void *memchr(const void *s, int c, size_t n) {
  const unsigned char *p = (const unsigned char *)s;
  for (size_t i = 0; i < n; i++) {
    if (p[i] == (unsigned char)c) return (void *)(p + i);
  }
  return 0;
}

/* ====================================================================== */
/* string primitives                                                       */
/* ====================================================================== */

size_t strlen(const char *s) {
  const char *p = s;
  while (*p) p++;
  return (size_t)(p - s);
}

int strcmp(const char *s1, const char *s2) {
  while (*s1 && *s1 == *s2) { s1++; s2++; }
  return (int)(unsigned char)*s1 - (int)(unsigned char)*s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  for (size_t i = 0; i < n; i++) {
    unsigned char a = (unsigned char)s1[i];
    unsigned char b = (unsigned char)s2[i];
    if (a != b) return (int)a - (int)b;
    if (a == 0) return 0;
  }
  return 0;
}

char *strcpy(char *dest, const char *src) {
  char *d = dest;
  while ((*d++ = *src++)) { }
  return dest;
}

char *strncpy(char *dest, const char *src, size_t n) {
  size_t i = 0;
  for (; i < n && src[i]; i++) dest[i] = src[i];
  for (; i < n; i++) dest[i] = '\0';
  return dest;
}

char *strcat(char *dest, const char *src) {
  char *d = dest + strlen(dest);
  while ((*d++ = *src++)) { }
  return dest;
}

char *strchr(const char *s, int c) {
  for (;; s++) {
    if (*s == (char)c) return (char *)s;
    if (!*s) return 0;
  }
}

char *strrchr(const char *s, int c) {
  const char *last = 0;
  for (;; s++) {
    if (*s == (char)c) last = s;
    if (!*s) break;
  }
  return (char *)last;
}

char *strstr(const char *haystack, const char *needle) {
  if (!*needle) return (char *)haystack;
  for (; *haystack; haystack++) {
    const char *h = haystack;
    const char *n = needle;
    while (*h && *n && *h == *n) { h++; n++; }
    if (!*n) return (char *)haystack;
  }
  return 0;
}

/* ====================================================================== */
/* allocator: bump, never frees (see file header)                          */
/* ====================================================================== */

extern unsigned char __heap_base;

static unsigned long yantra_heap_top = 0;

static void *yantra_sbrk(size_t size) {
  if (yantra_heap_top == 0) {
    yantra_heap_top = (unsigned long)(uintptr_t)&__heap_base;
    yantra_heap_top = (yantra_heap_top + 15UL) & ~15UL;
  }
  unsigned long base = yantra_heap_top;
  yantra_heap_top = (base + (unsigned long)size + 15UL) & ~15UL;   /* keep every block 16-aligned */

  /* Grow wasm linear memory if the bump pointer has run past the current end. */
  unsigned long pages_needed = (yantra_heap_top + 65535UL) / 65536UL;
  unsigned long pages_have = (unsigned long)__builtin_wasm_memory_size(0);
  if (pages_needed > pages_have) {
    __builtin_wasm_memory_grow(0, pages_needed - pages_have);
  }
  return (void *)(uintptr_t)base;
}

void *malloc(size_t size) {
  if (size == 0) size = 1;
  return yantra_sbrk(size);
}

void *calloc(size_t nmemb, size_t size) {
  size_t total = nmemb * size;
  void *p = yantra_sbrk(total);
  memset(p, 0, total);
  return p;
}

void *realloc(void *ptr, size_t size) {
  /* No way to know the old size, so always move. Wasteful but correct. */
  if (ptr == 0) return yantra_sbrk(size);
  void *fresh = yantra_sbrk(size);
  memcpy(fresh, ptr, size);
  return fresh;
}

void free(void *ptr) { (void)ptr; /* see file header */ }

void abort(void) { __builtin_trap(); }

void exit(int status) {
  (void)status;
  __builtin_trap();
}

int atexit(void (*fn)(void)) { (void)fn; return -1; }

/* ====================================================================== */
/* number parsing                                                          */
/* ====================================================================== */

int abs(int j) { return j < 0 ? -j : j; }
long labs(long j) { return j < 0 ? -j : j; }

int atoi(const char *nptr) { return (int)strtol(nptr, 0, 10); }
long atol(const char *nptr) { return strtol(nptr, 0, 10); }

long strtol(const char *nptr, char **endptr, int base) {
  const char *s = nptr;
  while (*s == ' ' || *s == '\t' || *s == '\n') s++;
  int neg = 0;
  if (*s == '-') { neg = 1; s++; } else if (*s == '+') s++;
  if (base == 0) {
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { base = 16; s += 2; }
    else if (s[0] == '0') { base = 8; s++; }
    else base = 10;
  } else if (base == 16 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
    s += 2;
  }
  long acc = 0;
  for (;; s++) {
    int c = (unsigned char)*s;
    int d;
    if (c >= '0' && c <= '9') d = c - '0';
    else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
    else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
    else break;
    if (d >= base) break;
    acc = acc * base + d;
  }
  if (endptr) *endptr = (char *)s;
  return neg ? -acc : acc;
}

double atof(const char *nptr) { return strtod(nptr, 0); }

double strtod(const char *nptr, char **endptr) {
  const char *s = nptr;
  while (*s == ' ' || *s == '\t' || *s == '\n') s++;
  int neg = 0;
  if (*s == '-') { neg = 1; s++; } else if (*s == '+') s++;
  double val = 0.0;
  while (*s >= '0' && *s <= '9') { val = val * 10.0 + (double)(*s - '0'); s++; }
  if (*s == '.') {
    s++;
    double scale = 0.1;
    while (*s >= '0' && *s <= '9') {
      val += (double)(*s - '0') * scale;
      scale *= 0.1;
      s++;
    }
  }
  if (endptr) *endptr = (char *)s;
  return neg ? -val : val;
}

/* ====================================================================== */
/* qsort / bsearch — insertion sort: tiny, and app arrays are small         */
/* ====================================================================== */

static void yantra_swap(unsigned char *a, unsigned char *b, size_t size) {
  for (size_t i = 0; i < size; i++) {
    unsigned char t = a[i]; a[i] = b[i]; b[i] = t;
  }
}

void qsort(void *base, size_t nmemb, size_t size,
           int (*compar)(const void *, const void *)) {
  unsigned char *b = (unsigned char *)base;
  for (size_t i = 1; i < nmemb; i++) {
    size_t j = i;
    while (j > 0 && compar(b + (j - 1) * size, b + j * size) > 0) {
      yantra_swap(b + (j - 1) * size, b + j * size, size);
      j--;
    }
  }
}

void *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
              int (*compar)(const void *, const void *)) {
  unsigned char *b = (unsigned char *)base;
  size_t lo = 0, hi = nmemb;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    int c = compar(key, b + mid * size);
    if (c == 0) return b + mid * size;
    if (c < 0) hi = mid; else lo = mid + 1;
  }
  return 0;
}

/* ====================================================================== */
/* stdio — the formatting half is the part Nim actually needs              */
/* ====================================================================== */

/* The FILE* objects: the header keeps `struct _YantraFILE` opaque so app code
 * cannot depend on its layout; here we complete it, because the three stream
 * objects below are real storage. A `struct {...}` member is never read - I/O
 * goes to the host - so an empty-ish struct is the honest representation. */
struct _YantraFILE {
  int yantra_unused; /* no file state exists in a sandbox */
};

static struct _YantraFILE yantra_stdin_obj;
static struct _YantraFILE yantra_stdout_obj;
static struct _YantraFILE yantra_stderr_obj;

FILE *stdin  = &yantra_stdin_obj;
FILE *stdout = &yantra_stdout_obj;
FILE *stderr = &yantra_stderr_obj;

/* Every write goes to the host as a log line — a capability the host can police. */
extern void yantra_log(const char *ptr, int len);

static int yantra_emit(const char *s, size_t n) {
  if (n > 0x7fffffffUL) n = 0x7fffffffUL;
  yantra_log(s, (int)n);
  return (int)n;
}

int fputc(int c, FILE *stream) { (void)stream; char ch = (char)c; yantra_emit(&ch, 1); return c; }
int putchar(int c) { return fputc(c, stdout); }
int fputs(const char *s, FILE *stream) { (void)stream; return yantra_emit(s, strlen(s)); }
int puts(const char *s) { yantra_emit(s, strlen(s)); return yantra_emit("\n", 1); }

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
  (void)stream;
  yantra_emit((const char *)ptr, size * nmemb);
  return nmemb;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
  (void)ptr; (void)size; (void)stream;
  return 0; /* no filesystem in the sandbox */
}

int    fflush(FILE *stream) { (void)stream; return 0; }
int    fclose(FILE *stream) { (void)stream; return 0; }
FILE  *fopen(const char *pathname, const char *mode) { (void)pathname; (void)mode; return 0; }

/* No shared streams exist in a sandbox, so locking is a no-op. They must still be
 * defined: Nim's system.nim emits calls to them. */
void flockfile(FILE *stream) { (void)stream; }
void funlockfile(FILE *stream) { (void)stream; }
int  feof(FILE *stream) { (void)stream; return 0; }
int  ferror(FILE *stream) { (void)stream; return 0; }
int  getc_unlocked(FILE *stream) { (void)stream; return EOF; }
int  putc_unlocked(int c, FILE *stream) { (void)stream; char ch = (char)c; yantra_emit(&ch, 1); return c; }

/* ---- the formatter ---------------------------------------------------- */

typedef struct {
  char  *buf;
  size_t cap;
  size_t len;   /* characters that WOULD have been written */
  int    trunc;
} YantraOut;

static void out_ch(YantraOut *o, char c) {
  if (o->len + 1 < o->cap) {
    o->buf[o->len] = c;
  } else {
    o->trunc = 1;
  }
  o->len++;
}

static void out_str(YantraOut *o, const char *s, size_t n) {
  for (size_t i = 0; i < n; i++) out_ch(o, s[i]);
}

static void out_pad(YantraOut *o, char c, int count) {
  for (int i = 0; i < count; i++) out_ch(o, c);
}

static int utoa_base(unsigned long long v, int base, int upper, char *tmp) {
  const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  int n = 0;
  if (v == 0) { tmp[n++] = '0'; return n; }
  char rev[24];
  int r = 0;
  while (v) { rev[r++] = digits[v % (unsigned)base]; v /= (unsigned)base; }
  for (int i = r - 1; i >= 0; i--) tmp[n++] = rev[i];
  return n;
}

/* Fixed-precision decimal. Deliberately simple: UI values, not scientific use. */
static void fmt_float(YantraOut *o, double v, int prec, int force_sign) {
  if (v != v) { out_str(o, "nan", 3); return; }
  if (v > 1.7976931348623157e308) { out_str(o, "inf", 3); return; }
  if (v < -1.7976931348623157e308) { out_str(o, "-inf", 4); return; }

  unsigned long long whole;
  double frac;

  if (v < 0) { out_ch(o, '-'); v = -v; }
  else if (force_sign) out_ch(o, '+');

  whole = (unsigned long long)v;
  frac = v - (double)whole;

  char tmp[32];
  int n = utoa_base(whole, 10, 0, tmp);
  out_str(o, tmp, (size_t)n);

  if (prec > 0) {
    out_ch(o, '.');
    for (int i = 0; i < prec; i++) {
      frac *= 10.0;
      int d = (int)frac;
      if (d > 9) d = 9;
      if (d < 0) d = 0;
      out_ch(o, (char)('0' + d));
      frac -= (double)d;
    }
  }
}

int vsnprintf(char *str, size_t size, const char *format, va_list ap) {
  YantraOut o;
  o.buf = str; o.cap = size; o.len = 0; o.trunc = 0;

  for (const char *p = format; *p; p++) {
    if (*p != '%') { out_ch(&o, *p); continue; }

    p++;
    if (*p == '%') { out_ch(&o, '%'); continue; }

    /* flags */
    int left = 0, zero = 0, plus = 0;
    for (;; p++) {
      if (*p == '-') left = 1;
      else if (*p == '0') zero = 1;
      else if (*p == '+') plus = 1;
      else if (*p == ' ' || *p == '#') { /* accepted, ignored */ }
      else break;
    }

    /* width */
    int width = 0;
    while (*p >= '0' && *p <= '9') { width = width * 10 + (*p - '0'); p++; }

    /* precision */
    int prec = -1;
    if (*p == '.') {
      p++;
      prec = 0;
      while (*p >= '0' && *p <= '9') { prec = prec * 10 + (*p - '0'); p++; }
    }

    /* length modifiers — ignored on wasm32 (int and long are both 32-bit) */
    while (*p == 'l' || *p == 'h' || *p == 'z' || *p == 'j' || *p == 't') p++;

    char tmp[64];
    int n = 0;
    int numeric = 0;

    switch (*p) {
      case 'd': case 'i': {
        int v = va_arg(ap, int);
        unsigned int uv;
        if (v < 0) { tmp[n++] = '-'; uv = (unsigned int)(-(long)v); }
        else { if (plus) tmp[n++] = '+'; uv = (unsigned int)v; }
        char d[24]; int dn = utoa_base(uv, 10, 0, d);
        for (int i = 0; i < dn; i++) tmp[n++] = d[i];
        numeric = 1;
        break;
      }
      case 'u': {
        char d[24]; int dn = utoa_base((unsigned long long)va_arg(ap, unsigned int), 10, 0, d);
        for (int i = 0; i < dn; i++) tmp[n++] = d[i];
        numeric = 1;
        break;
      }
      case 'x': case 'X': {
        char d[24]; int dn = utoa_base((unsigned long long)va_arg(ap, unsigned int), 16, *p == 'X', d);
        for (int i = 0; i < dn; i++) tmp[n++] = d[i];
        numeric = 1;
        break;
      }
      case 'p': {
        tmp[n++] = '0'; tmp[n++] = 'x';
        char d[24]; int dn = utoa_base((unsigned long long)(uintptr_t)va_arg(ap, void *), 16, 0, d);
        for (int i = 0; i < dn; i++) tmp[n++] = d[i];
        numeric = 1;
        break;
      }
      case 'c': {
        tmp[n++] = (char)va_arg(ap, int);
        break;
      }
      case 's': {
        const char *s = va_arg(ap, const char *);
        if (!s) s = "(null)";
        size_t sl = strlen(s);
        if (prec >= 0 && (size_t)prec < sl) sl = (size_t)prec;
        out_str(&o, s, sl);
        /* pad for width */
        if (width > (int)sl && !left) out_pad(&o, ' ', width - (int)sl);
        if (width > (int)sl && left)  out_pad(&o, ' ', width - (int)sl);
        continue;
      }
      case 'f': case 'F': case 'g': case 'G': case 'e': case 'E': {
        double v = va_arg(ap, double);
        int fp = (prec >= 0) ? prec : 6;
        /* Temporarily format into tmp so width padding applies uniformly. */
        YantraOut sub;
        sub.buf = tmp; sub.cap = sizeof(tmp); sub.len = 0; sub.trunc = 0;
        fmt_float(&sub, v, fp, plus);
        n = (int)sub.len; if (n > (int)sizeof(tmp)) n = (int)sizeof(tmp);
        /* tmp is not NUL-terminated by the writer; ok, we carry n. */
        if (width > n && !left) out_pad(&o, ' ', width - n);
        out_str(&o, tmp, (size_t)n);
        if (width > n && left) out_pad(&o, ' ', width - n);
        continue;
      }
      default:
        out_ch(&o, '%');
        out_ch(&o, *p);
        continue;
    }

    /* Emit a numeric/char buffer with width + zero padding. */
    if (width > n && !left) out_pad(&o, (zero && numeric) ? '0' : ' ', width - n);
    out_str(&o, tmp, (size_t)n);
    if (width > n && left) out_pad(&o, ' ', width - n);
  }

  if (size > 0) {
    size_t term = (o.len < size) ? o.len : size - 1;
    str[term] = '\0';
  }
  return (int)o.len;
}

int snprintf(char *str, size_t size, const char *format, ...) {
  va_list ap; va_start(ap, format);
  int r = vsnprintf(str, size, format, ap);
  va_end(ap);
  return r;
}

int vsprintf(char *str, const char *format, va_list ap) {
  return vsnprintf(str, (size_t)-1, format, ap);
}

int sprintf(char *str, const char *format, ...) {
  va_list ap; va_start(ap, format);
  int r = vsnprintf(str, (size_t)-1, format, ap);
  va_end(ap);
  return r;
}

int printf(const char *format, ...) {
  char buf[512];
  va_list ap; va_start(ap, format);
  int r = vsnprintf(buf, sizeof(buf), format, ap);
  va_end(ap);
  size_t n = strlen(buf);
  yantra_emit(buf, n);
  return r;
}

int fprintf(FILE *stream, const char *format, ...) {
  (void)stream;
  char buf[512];
  va_list ap; va_start(ap, format);
  int r = vsnprintf(buf, sizeof(buf), format, ap);
  va_end(ap);
  yantra_emit(buf, strlen(buf));
  return r;
}

/* ====================================================================== */
/* math — see math.h for why only these need real implementations          */
/* ====================================================================== */

static const double YANTRA_PI = 3.14159265358979323846;

/* |x| < 1; converges fast enough for UI easing. */
static double yantra_atan_series(double x) {
  double x2 = x * x;
  double term = x;
  double sum = x;
  for (int k = 1; k < 24; k++) {
    term *= -x2;
    sum += term / (double)(2 * k + 1);
  }
  return sum;
}

double atan(double x) {
  if (x > 1.0)  return  YANTRA_PI / 2.0 - yantra_atan_series(1.0 / x);
  if (x < -1.0) return -YANTRA_PI / 2.0 - yantra_atan_series(1.0 / x);
  return yantra_atan_series(x);
}

double atan2(double y, double x) {
  if (x > 0) return atan(y / x);
  if (x < 0) return y >= 0 ? atan(y / x) + YANTRA_PI : atan(y / x) - YANTRA_PI;
  if (y > 0) return YANTRA_PI / 2.0;
  if (y < 0) return -YANTRA_PI / 2.0;
  return 0.0;
}

static double yantra_sin_core(double x) {
  double x2 = x * x;
  double term = x;
  double sum = x;
  for (int k = 1; k < 16; k++) {
    term *= -x2 / (double)((2 * k) * (2 * k + 1));
    sum += term;
  }
  return sum;
}

static double yantra_wrap_pi(double x) {
  double two_pi = 2.0 * YANTRA_PI;
  long long k = (long long)(x / two_pi);
  x -= (double)k * two_pi;
  if (x >  YANTRA_PI) x -= two_pi;
  if (x < -YANTRA_PI) x += two_pi;
  return x;
}

double sin(double x) { return yantra_sin_core(yantra_wrap_pi(x)); }
double cos(double x) { return yantra_sin_core(yantra_wrap_pi(x + YANTRA_PI / 2.0)); }
double tan(double x) { double c = cos(x); return c == 0.0 ? 0.0 : sin(x) / c; }

double asin(double x) {
  if (x >= 1.0)  return  YANTRA_PI / 2.0;
  if (x <= -1.0) return -YANTRA_PI / 2.0;
  return atan(x / __builtin_sqrt(1.0 - x * x));
}

double acos(double x) { return YANTRA_PI / 2.0 - asin(x); }

/* exp via range reduction: e^x = 2^k * e^r, r in [-ln2/2, ln2/2] */
double exp(double x) {
  if (x > 709.0) return 1.7976931348623157e308;
  if (x < -709.0) return 0.0;
  const double ln2 = 0.6931471805599453;
  long long k = (long long)(x / ln2 + (x >= 0 ? 0.5 : -0.5));
  double r = x - (double)k * ln2;
  double term = 1.0, sum = 1.0;
  for (int i = 1; i < 20; i++) {
    term *= r / (double)i;
    sum += term;
  }
  /* scale by 2^k by repeated doubling (no ldexp) */
  long long kk = k < 0 ? -k : k;
  for (long long i = 0; i < kk; i++) sum = (k < 0) ? sum * 0.5 : sum * 2.0;
  return sum;
}

double log(double x) {
  if (x <= 0.0) return -1.7976931348623157e308;
  const double ln2 = 0.6931471805599453;
  int k = 0;
  while (x >= 2.0) { x *= 0.5; k++; }
  while (x < 1.0)  { x *= 2.0; k--; }
  /* log(x) for x in [1,2) via atanh series: 2*atanh((x-1)/(x+1)) */
  double z = (x - 1.0) / (x + 1.0);
  double z2 = z * z;
  double term = z, sum = z;
  for (int i = 1; i < 24; i++) {
    term *= z2;
    sum += term / (double)(2 * i + 1);
  }
  return 2.0 * sum + (double)k * ln2;
}

double log2(double x) { return log(x) / 0.6931471805599453; }
double log10(double x) { return log(x) / 2.302585092994046; }
double pow(double base, double exponent) {
  if (exponent == 0.0) return 1.0;
  if (base == 0.0) return 0.0;
  return exp(exponent * log(base));
}

double sinh(double x) { double e = exp(x); return (e - 1.0 / e) * 0.5; }
double cosh(double x) { double e = exp(x); return (e + 1.0 / e) * 0.5; }
double tanh(double x) { double e = exp(2.0 * x); return (e - 1.0) / (e + 1.0); }
double hypot(double x, double y) { return __builtin_sqrt(x * x + y * y); }

/* fmod: binary power-of-two reduction. Cannot use __builtin_fmod - on wasm that
 * lowers to a libcall to `fmod`, which is this function. */
double fmod(double x, double y) {
  if (y == 0.0) return 0.0;
  double ay = y < 0.0 ? -y : y;
  double r  = x < 0.0 ? -x : x;
  if (r < ay) return x;
  double d = ay;
  while (d <= r / 2.0) d *= 2.0;   /* largest ay*2^k that is <= r */
  while (d >= ay) {
    if (r >= d) r -= d;
    d *= 0.5;
  }
  return x < 0.0 ? -r : r;
}

double fmod_slow(double x, double y) { return fmod(x, y); }

/* round / roundf: C round is "half away from zero", which wasm's f64.nearest
 * (half-to-even) cannot express, so clang lowers __builtin_round to a libcall
 * named `round` — and with -nostdlib the module then defines `round` as a stub
 * that calls itself, recursing until the stack walks off linear memory. That
 * is why round(float64) trapped and round(float32) (an f32.nearest instruction)
 * did not. floor/ceil/trunc lower to instructions, but they are defined here
 * too so no future lowering can reintroduce the hole. */
double round(double x) {
  if (x >= 0.0) return (double)(long long)(x + 0.5);
  return -(double)(long long)(-x + 0.5);
}
float roundf(float x) {
  if (x >= 0.0f) return (float)(long long)(x + 0.5f);
  return -(float)(long long)(-x + 0.5f);
}
double floor(double x) { return __builtin_floor(x); }
double ceil(double x)  { return __builtin_ceil(x); }
double trunc(double x) { return __builtin_trunc(x); }
float floorf(float x)  { return __builtin_floorf(x); }
float ceilf(float x)   { return __builtin_ceilf(x); }
float truncf(float x)  { return __builtin_truncf(x); }
