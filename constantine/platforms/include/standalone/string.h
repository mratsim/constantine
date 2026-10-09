/* Freestanding declarations only — no libc. Implementations are provided at
 * link time by the compiler runtime (Zig compiler_rt / LLVM builtins). */
#ifndef CTT_STANDALONE_STRING_H
#define CTT_STANDALONE_STRING_H

#include <stddef.h>

void *memcpy(void *restrict dest, const void *restrict src, size_t n);
void *memmove(void *dest, const void *src, size_t n);
void *memset(void *dest, int c, size_t n);
int   memcmp(const void *s1, const void *s2, size_t n);
size_t strlen(const char *s);

#endif
