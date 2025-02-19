/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_KECCAK256__
#define __CTT_H_KECCAK256__

#include "constantine/core/datatypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { ctt_align(64) uint64_t state[5*5]; } ctt_keccak256_context;

/** Initialize or reinitialize a Keccak256 context.
 */
void ctt_keccak256_init(ctt_keccak256_context* ctx);

/** Append a message to a Keccak256 context
 *  for incremental Keccak256 computation
 *
 *  Security note: the tail of your message might be stored
 *  in an internal buffer.
 *  if sensitive content is used, ensure that
 *  `ctx.finish(...)` and `ctx.clear()` are called as soon as possible.
 *  Additionally ensure that the message(s) passed were stored
 *  in memory considered secure for your threat model.
 *
 *  For passwords and secret keys, you MUST NOT use raw Keccak256
 *  use a Key Derivation Function instead (KDF)
 */
void ctt_keccak256_update(ctt_keccak256_context* ctx, const byte* message, size_t message_len);

/** Finalize a Keccak256 computation and output the
 *  message digest to the `digest` buffer.
 *
 *  Security note: this does not clear the internal buffer.
 *  if sensitive content is used, use "ctx.clear()"
 *  and also make sure that the message(s) passed were stored
 *  in memory considered secure for your threat model.
 *
 *  For passwords and secret keys, you MUST NOT use raw Keccak256
 *  use a Key Derivation Function instead (KDF)
 */
void ctt_keccak256_finish(ctt_keccak256_context* ctx, byte digest[32]);

/** Clear the context internal buffers
 *  Security note:
 *  For passwords and secret keys, you MUST NOT use raw Keccak256
 *  use a Key Derivation Function instead (KDF)
 */
void ctt_keccak256_clear(ctt_keccak256_context* ctx);

/** Compute the Keccak256 hash of message
 *  and store the result in digest.
 *  Optionally, clear the memory buffer used.
 */
void ctt_keccak256_hash(byte digest[32], const byte* message, size_t message_len, ctt_bool clear_memory);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_KECCAK256__
