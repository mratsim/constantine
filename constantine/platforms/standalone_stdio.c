/* Freestanding stdio backing for the Nim runtime's out-of-memory path.
 * A freestanding target has no console: writing is a no-op and exit traps. */
#include "include/standalone/stdio.h"

FILE *stderr = 0;

size_t fwrite(const void *ptr, size_t size, size_t nmemb, FILE *stream) {
  (void)ptr; (void)size; (void)stream;
  return nmemb;
}

int fflush(FILE *stream) {
  (void)stream;
  return 0;
}

__attribute__((noreturn)) void exit(int code) {
  (void)code;
  __builtin_trap();
  __builtin_unreachable();
}
