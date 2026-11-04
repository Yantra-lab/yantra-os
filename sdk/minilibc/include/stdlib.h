/*
 * Yantra mini-libc — stdlib.h
 *
 * Nim's --mm:arc on standalone wasm brings its own bump allocator (the
 * `theHeap`/`bumpPointer` globals Nim exports), so malloc is rarely reached.
 * It is provided anyway so that any stdlib path that references it links.
 *
 * The allocator here is a simple bump allocator over a fixed arena; `free` is a
 * no-op. That is deliberate and honest: a sandboxed app module is short-lived and
 * the host reclaims the whole linear memory when the module is dropped. A real
 * allocator would be dead weight. If a module ever needs long-lived free/realloc
 * churn, that is the signal to move it to WASI instead.
 */
#ifndef YANTRA_STDLIB_H
#define YANTRA_STDLIB_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

void  *malloc(size_t size);
void  *calloc(size_t nmemb, size_t size);
void  *realloc(void *ptr, size_t size);
void   free(void *ptr);

void   abort(void);
void   exit(int status);
int    atexit(void (*fn)(void));

int    atoi(const char *nptr);
long   atol(const char *nptr);
double atof(const char *nptr);
long   strtol(const char *nptr, char **endptr, int base);

int    abs(int j);
long   labs(long j);

void   qsort(void *base, size_t nmemb, size_t size,
             int (*compar)(const void *, const void *));
void  *bsearch(const void *key, const void *base, size_t nmemb, size_t size,
               int (*compar)(const void *, const void *));

double strtod(const char *nptr, char **endptr);

#ifdef __cplusplus
}
#endif

#endif /* YANTRA_STDLIB_H */
