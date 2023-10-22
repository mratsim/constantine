/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_DATATYPES__
#define __CTT_H_DATATYPES__

#ifdef __cplusplus
extern "C" {
#endif

// Basic Types
// ------------------------------------------------------------------------------------------------

#if defined(__SIZE_TYPE__) && defined(__PTRDIFF_TYPE__)
typedef __SIZE_TYPE__    size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#else
#include <stddef.h>
#endif

#if defined(__UINT8_TYPE__) && defined(__UINT32_TYPE__) && defined(__UINT64_TYPE__)
typedef __UINT8_TYPE__   uint8_t;
typedef __UINT32_TYPE__  uint32_t;
typedef __UINT64_TYPE__  uint64_t;
#else
#include <stdint.h>
#endif

// https://github.com/nim-lang/Nim/blob/v1.6.12/lib/nimbase.h#L318
#if defined(__STDC_VERSION__) && __STDC_VERSION__>=199901
# define bool _Bool
#else
# define bool unsigned char
#endif

typedef size_t           secret_word;
typedef size_t           secret_bool;
typedef uint8_t          byte;

// Sizes
// ------------------------------------------------------------------------------------------------

#define BYTES(bits) ((int) ((bits) + 8 - 1) / 8)
#define WordBitWidth         (sizeof(secret_word)*8)
#define words_required(bits) ((bits+WordBitWidth-1)/WordBitWidth)

// Attributes
// ------------------------------------------------------------------------------------------------

#if defined(_MSC_VER)
#  define ctt_pure __declspec(noalias)
#elif defined(__GNUC__)
#  define ctt_pure __attribute__((pure))
#else
#  define ctt_pure
#endif

#if defined(_MSC_VER)
#  define align(x)  __declspec(align(x))
#else
#  define align(x)  __attribute__((aligned(x)))
#endif

// Initialization
// ------------------------------------------------------------------------------------------------

/** Initializes the library:
 *  - detect CPU features like ADX instructions support (MULX, ADCX, ADOX)
 */
void ctt_NimMain(void);

#ifdef __cplusplus
}
#endif

#endif