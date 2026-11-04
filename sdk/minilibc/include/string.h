/*
 * Yantra mini-libc — string.h
 *
 * WHY THIS EXISTS: Nim's --os:standalone target compiles the program with
 * -nostdlib -ffreestanding. clang still supplies stddef.h/stdint.h/stdbool.h/
 * limits.h/float.h as compiler headers, so pure arithmetic compiles fine - but
 * the first use of a Nim string pulls in <string.h>, which does not exist.
 * This header (plus minilibc.c) is the smallest thing that closes that gap.
 *
 * Size matters: this is for shipping app modules. wasi-libc would work but costs
 * far more bytes than an app that only needs memcpy and strlen.
 */
#ifndef YANTRA_STRING_H
#define YANTRA_STRING_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void  *memcpy(void *dest, const void *src, size_t n);
void  *memmove(void *dest, const void *src, size_t n);
void  *memset(void *s, int c, size_t n);
int    memcmp(const void *s1, const void *s2, size_t n);
void  *memchr(const void *s, int c, size_t n);

size_t strlen(const char *s);
int    strcmp(const char *s1, const char *s2);
int    strncmp(const char *s1, const char *s2, size_t n);
char  *strcpy(char *dest, const char *src);
char  *strncpy(char *dest, const char *src, size_t n);
char  *strcat(char *dest, const char *src);
char  *strchr(const char *s, int c);
char  *strrchr(const char *s, int c);
char  *strstr(const char *haystack, const char *needle);
char  *strdup(const char *s);

#ifdef __cplusplus
}
#endif

#endif /* YANTRA_STRING_H */
