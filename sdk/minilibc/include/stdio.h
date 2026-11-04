/*
 * Yantra mini-libc — stdio.h
 *
 * THE INTERESTING ONE. A sandboxed app module has no console and no files, so
 * almost all of stdio is meaningless. What Nim's stdlib genuinely reaches for is
 * the *formatting* half: `snprintf` is how numbers and floats become strings.
 * That is the only reason this header exists.
 *
 * The FILE* surface is a minimal stub so that any reference links; writes go
 * nowhere (the host captures app output through the `yantra_log` import instead,
 * which is a capability the host can actually police).
 */
#ifndef YANTRA_STDIO_H
#define YANTRA_STDIO_H

#include <stddef.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EOF (-1)

/* Opaque. The module never really does file I/O; these exist to link. */
typedef struct _YantraFILE FILE;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

int    printf(const char *format, ...);
int    fprintf(FILE *stream, const char *format, ...);
int    sprintf(char *str, const char *format, ...);
int    snprintf(char *str, size_t size, const char *format, ...);
int    vsnprintf(char *str, size_t size, const char *format, va_list ap);
int    vsprintf(char *str, const char *format, va_list ap);
int    puts(const char *s);
int    fputs(const char *s, FILE *stream);
int    fputc(int c, FILE *stream);
int    putchar(int c);

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream);
int    fflush(FILE *stream);
int    fclose(FILE *stream);
FILE  *fopen(const char *pathname, const char *mode);

/* Nim's system.nim calls these around its string formatting. On a sandbox with no
 * shared streams they are meaningless, but they must exist or the module will not
 * compile: "call to undeclared function 'flockfile'". */
void   flockfile(FILE *stream);
void   funlockfile(FILE *stream);
int    feof(FILE *stream);
int    ferror(FILE *stream);
int    getc_unlocked(FILE *stream);
int    putc_unlocked(int c, FILE *stream);

#ifdef __cplusplus
}
#endif

#endif /* YANTRA_STDIO_H */
