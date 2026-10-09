/* Freestanding declarations only — the symbols below are defined by the
 * embedder (see platforms/standalone_stdio.c), which routes them to the
 * platform's trap/panic path. */
#ifndef CTT_STANDALONE_STDIO_H
#define CTT_STANDALONE_STDIO_H

#include <stddef.h>

typedef struct CTT_FILE CTT_FILE;
#define FILE CTT_FILE

extern FILE *stderr;

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream);
int    fflush(FILE *stream);

#endif
