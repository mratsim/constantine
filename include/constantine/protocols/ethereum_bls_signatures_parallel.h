/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_BLS_SIGNATURES_PARALLEL__
#define __CTT_H_ETHEREUM_BLS_SIGNATURES_PARALLEL__

#include "constantine/core/datatypes.h"
#include "constantine/core/threadpool.h"
#include "constantine/protocols/ethereum_bls_signatures.h"

#ifdef __cplusplus
extern "C" {
#endif

// Ethereum BLS signatures parallel interface
// ------------------------------------------------------------------------------------------------

/**
 *  Verify that all (pubkey, message, signature) triplets are valid
 *  returns `true` if all signatures are valid, `false` if at least one is invalid.
 *
 *  For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 *  Input:
 *  - Public keys initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_pubkey
 *  - Messages as an anonymous struct of `(data = byte*, length = size_t)` pairs
 *    (the `View` type on the Nim side uses `int` for the length field, which depends on the
 *    system)
 *  - Signatures initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_signature
 *  - `len`: number of elements in `pubkey`, `messages`, `sig` arrays
 *
 *  In particular, the public keys and signature are assumed to be on curve subgroup checked.
 *
 *  To avoid splitting zeros and rogue keys attack:
 *  1. Cryptographically-secure random bytes must be provided.
 *  2. Augmentation or Proof of possessions must used for each public keys.
 *
 *  The secureRandomBytes will serve as input not under the attacker control to foil potential splitting zeros inputs.
 *  The scheme assumes that the attacker cannot
 *  resubmit 2^64 times forged (publickey, message, signature) triplets
 *  against the same `secureRandomBytes`
*/
ctt_eth_bls_status ctt_eth_bls_batch_verify_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_bls_pubkey pubkey[],
	const ctt_span messages[],
        const ctt_eth_bls_signature sig[],
        size_t len,
        const byte secure_random_bytes[32]
    ) __attribute__((warn_unused_result));


#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_BLS_SIGNATURES_PARALLEL__
