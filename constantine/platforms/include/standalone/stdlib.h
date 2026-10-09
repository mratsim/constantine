/* Freestanding declarations only — no libc. malloc/free resolve at link time
 * against the embedder's allocator shim. */
#ifndef CTT_STANDALONE_STDLIB_H
#define CTT_STANDALONE_STDLIB_H

#include <stddef.h>

void *malloc(size_t size);
void *calloc(size_t nmemb, size_t size);
void *realloc(void *ptr, size_t size);
void  free(void *ptr);
void *aligned_alloc(size_t alignment, size_t size);

#endif
