/* Freestanding: alloca is a compiler builtin. */
#ifndef CTT_STANDALONE_ALLOCA_H
#define CTT_STANDALONE_ALLOCA_H

#include <stddef.h>

#define alloca(size) __builtin_alloca(size)

#endif
