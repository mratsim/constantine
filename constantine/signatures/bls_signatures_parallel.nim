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
  # Standard library
  std/atomics,
  # Constantine
  ../threadpool/[threadpool, partitioners],
  ../platforms/[abstractions, allocs, views],
  ../serialization/endians,
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
       secureRandomBytes: array[32, byte]): bool {.noInline, genCharAPI.} =
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

  # Stage 0a: Setup per-thread accumulators
  debug: doAssert pubkeys.len <= 1 shl 32
  let N = pubkeys.len.uint32
  let numAccums = min(N, tp.numThreads.uint32)
  let accums = allocHeapArray(BLSBatchSigAccumulator[H, FF1, FF2, Fpk, ECP_ShortW_Jac[Sig.F, Sig.G], k], numAccums)

  # Stage 0b: Setup synchronization
  var currentItem {.noInit.}: Atomic[uint32]
  var terminateSignal {.noInit.}: Atomic[bool]
  currentItem.store(0, moRelaxed)
  terminateSignal.store(false, moRelaxed)

  # Stage 1: Accumulate partial pairings (Miller Loops)
  # ---------------------------------------------------
  proc accumulate(
         ctx: ptr BLSBatchSigAccumulator,
         pubkeys: ptr UncheckedArray[Pubkey],
         messages: ptr UncheckedArray[Msg],
         signatures: ptr UncheckedArray[Sig],
         N: uint32,
         domainSepTag: View[byte],
         secureRandomBytes: ptr array[32, byte],
         accumSepTag: array[sizeof(int), byte],
         terminateSignal: ptr Atomic[bool],
         currentItem: ptr Atomic[uint32]): bool {.nimcall, gcsafe.} =
    ctx[].init(
      domainSepTag.toOpenArray(),
      secureRandomBytes[],
      accumSepTag)

    while not terminateSignal[].load(moRelaxed):
      let i = currentItem[].fetchAdd(1, moRelaxed)
      if i >= N:
        break

      if not ctx[].update(pubkeys[i], messages[i], signatures[i]):
        terminateSignal[].store(true, moRelaxed)
        return false

    ctx[].handover()
    return true

  # Stage 2: Schedule work
  # ---------------------------------------------------
  let partialStates = allocStackArray(Flowvar[bool], numAccums)
  for id in 0 ..< numAccums:
    partialStates[id] = tp.spawn accumulate(
      accums[id].addr,
      pubkeys.asUnchecked(),
      messages.asUnchecked(),
      signatures.asUnchecked(),
      N,
      domainSepTag.toView(),
      secureRandomBytes.unsafeAddr,
      id.uint.toBytes(bigEndian),
      terminateSignal.addr,
      currentItem.addr)

  # Stage 3: Reduce partial pairings
  # --------------------------------
  # Linear merge with latency hiding, we could consider a parallel logarithmic merge via a binary tree merge / divide-and-conquer
  block HappyPath: # sync must be called even if result is false in the middle to avoid tasks leaking
    result = sync partialStates[0]
    for i in 1 ..< numAccums:
      result = result and sync partialStates[i]
      if result: # As long as no error is returned, accumulate
        result = result and accums[0].merge(accums[i])
    if not result: # Don't proceed to final exponentiation if there is already an error
      break HappyPath

    result = accums[0].finalVerify()

  freeHeap(accums)
