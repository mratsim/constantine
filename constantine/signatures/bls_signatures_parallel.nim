# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                   BLS Signatures
#                  Parallel edition
#
# ############################################################

when not compileOption("threads"):
  {.error: "This requires --threads:on compilation flag".}

# Import all bls_signature including private fields and reexport
import ./bls_signatures{.all.}
export bls_signatures

import
  ../threadpool/threadpool,
  ../platforms/[abstractions, allocs, views],
  ../hashes,
  ../math/ec_shortweierstrass

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# Parallelized Batch Verifier
# ----------------------------------------------------------------------
# Parallel pairing computation requires the following steps
#
# Assuming we have N (public key, message, signature) triplets to verify
# on P processor/threads.
# We want B batches with B = (idle) P
# Each processing W work items with W = N/B or N/B + 1
#
# Step 0: Initialize an accumulator per thread.
# Step 1: Compute partial pairings, W work items per thread. (~190μs - Miller loops)
# Step 2: Merge the B partial pairings                       (~1.3μs - Fp12 multiplications)
# Step 4: Final verification                                 (~233μs - Final Exponentiation)
#
# (Timings are per operation on a 2.6GHz, turbo 5Ghz i9-11980HK CPU for BLS12-381 pairings.)
#
# We rely on the lazy tree splitting
# of Constantine's threadpool to only split computation if there is an idle worker.
# We force the base case for splitting to be 2 for efficiency but
# the actual base case auto-adapts to runtime conditions
# and may be 100 for example if all other threads are busy.
#
# In Ethereum consensus, blocks may require up to 6 verifications:
# - block proposals signatures
# - randao reveal signatures
# - proposer slashings signatures
# - attester slashings signatures
# - attestations signatures
# - validator exits signatures
# not counting deposits signatures which may be invalid
#
# And signature verification is the bottleneck for fast syncing and may reduce sync speed
# by hours or days.

proc batchVerify_parallel*[Msg, Pubkey, Sig](
       tp: Threadpool,
       pubkeys: openArray[Pubkey],
       messages: openArray[Msg],
       signatures: openArray[Sig],
       H: type CryptoHash,
       k: static int,
       domainSepTag: openArray[byte],
       secureRandomBytes: array[32, byte]): bool {.genCharAPI.} =
  ## Verify that all (pubkey, message, signature) triplets are valid
  ##
  ## Returns false if there is at least one incorrect signature
  ##
  ## Assumes pubkeys and signatures have been checked for non-infinity and group-checked.
  ##
  ## This requires cryptographically-secure generated random bytes
  ## for scalar blinding
  ## to defend against forged signatures that would not
  ## verify individually but would verify while aggregated.
  ## I.e. we need an input that is not under the attacker control.
  ##
  ## The blinding scheme also assumes that the attacker cannot
  ## resubmit 2^64 times forged (publickey, message, signature) triplets
  ## against the same `secureRandomBytes`
  if tp.numThreads == 1:
    return batchVerify(pubkeys, messages, signatures, H, k, domainSepTag, secureRandomBytes)

  if pubkeys.len == 0:
    return false

  if pubkeys.len != messages.len or  pubkeys.len != signatures.len:
    return false

  type FF1 = Pubkey.F
  type FF2 = Sig.F
  type FpK = Sig.F.C.getGT()
  type Acc = BLSBatchSigAccumulator[H, FF1, FF2, Fpk, ECP_ShortW_Jac[Sig.F, Sig.G], k]
  type BlsCompute = tuple[status: bool, accumulator: Acc]

  let N = pubkeys.len
  let pubkeys = pubkeys.asUnchecked()
  let messages = messages.asUnchecked()
  let signatures = signatures.asUnchecked()
  let dstLen = domainSepTag.len
  let domainSepTag = domainSepTag.toView()
  let secureRandomBytes = secureRandomBytes.unsafeAddr

  mixin globalBlsCompute

  tp.parallelFor i in 0 ..< N:
    stride: 2 # Min threshold seems to be at least 2 Miller Loop per worker thread
    captures: {pubkeys, messages, signatures, N, domainSepTag, secureRandomBytes}
    reduceInto(globalBlsCompute: tuple[status: bool, accumulator: ptr Acc]):
      prologue:
        var workerAcc = allocHeap(Acc)
        workerAcc[].init(
              domainSepTag.toOpenArray(),
              secureRandomBytes[],
              # We don't have access to `i` in the prologue so `accumSepTag`
              # cannot be initialized on an unique per-thread value,
              # however the merging is not under control of a potential attacker
              # and would change the accumulator separation tag.
              accumSepTag = "leaf")
        var workerStatusOk = true
      forLoop:
        if workerStatusOk:
          workerStatusOk = workerAcc[].update(pubkeys[i], messages[i], signatures[i])
      merge(remoteBls: Future[BlsCompute]):
        let (remoteStatus, remoteAcc) = sync(remoteBls)
        if workerStatusOk:
          workerStatusOk = remoteStatus
        if workerStatusOk:
          workerStatusOk = workerAcc[].merge(remoteAcc[])
        freeHeap(remoteAcc)
      epilogue:
        workerAcc[].handover()
        return (workerStatusOk, workerAcc)

  let (status, globalAcc) = sync(globalBlsCompute)
  result = status
  if result:
    result = globalAcc[].finalVerify()
  freeHeap(globalAcc)
