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
# We want B batches with B = P
# Each processing W work items with W = N/B or N/B + 1
#
# Step 0: Initialize an accumulator per thread.
# Step 1: Compute partial pairings, W work items per thread.
# Step 2: Merge the B partial pairings
#
# For step 2 we have 2 strategies.
#
# Strategy A: a simple linear merge
# ```
# for i in 1 ..< P:
#   accums[0].merge(accums[i])
# ```
# which requires P operations.
#
# Strategy B: A divide-and-conquer algorithm
# We binary split the merge until we hit the base case:
# ```
# accums[i].merge(accums[i+1])
# ```
#
# As pairing merge (Fp12 multiplication) is costly
# (~10000 CPU cycles on Skylake-X with ADCX/ADOX instructions)
# and for Ethereum we would at least have 6 sets:
# - block proposals signatures
# - randao reveal signatures
# - proposer slashings signatures
# - attester slashings signatures
# - attestations signatures
# - validator exits signatures
# not counting deposits signatures which may be invalid
# The merging would be 60k cycles if linear
# or 10k * log2(6) = 30k cycles if divide-and-conquer on 6+ cores
# Note that as the tree processing progresses, less threads are required
# for full parallelism so even with less than 6 cores, the speedup should be important.
# But on the other side, it's hard to utilize all cores of a high-core count machine.
#
# Note 1: a pairing is about 3400k cycles so the optimization is only noticeable
# when we do multi-block batches,
# for example batching 20 blocks would require 1200k cycles for a linear merge.
#
# Note 2: Skylake-X is a very recent family, with bigint instructions MULX/ADCX/ADOX,
# multiply everything by 2~3 on a Raspberry Pi
# and scale by core frequency.
#
# Note 3: 3M cycles is 1ms at 3GHz.

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

  # Stage 0: Setup per-thread accumulators
  let N = pubkeys.len
  let numAccums = min(N, tp.numThreads)
  let accums = allocHeapArray(BLSBatchSigAccumulator[H, FF1, FF2, Fpk, ECP_ShortW_Jac[Sig.F, Sig.G], k], numAccums)
  let chunkingDescriptor = balancedChunksPrioNumber(0, N, numAccums)
  let
    pubkeysView = pubkeys.toView()
    messagesView = messages.toView()
    signaturesView = signatures.toView()
    dstView = domainSepTag.toView()


  # Stage 1: Accumulate partial pairings (Miller Loops)
  # ---------------------------------------------------
  proc accumChunk(
         ctx: ptr BLSBatchSigAccumulator,
         pubkeys: View[Pubkey],
         messages: View[Msg],
         signatures: View[Sig],
         domainSepTag: View[byte],
         secureRandomBytes: array[32, byte],
         accumSepTag: array[sizeof(int), byte]): bool {.nimcall, gcsafe, tags: [Alloca, VarTime].} =
    ctx[].init(
      domainSepTag.toOpenArray(),
      secureRandomBytes,
      accumSepTag)

    for i in 0 ..< pubkeys.len:
      if not ctx[].update(pubkeys[i], messages[i], signatures[i]):
        return false

    return true

  let partialStates = allocStackArray(Flowvar[bool], numAccums)
  for (id, start, size) in items(chunkingDescriptor):
    partialStates[id] = tp.spawn accumChunk(
      accums[id].addr,
      pubkeysView.chunk(start, size),
      messagesView.chunk(start, size),
      signaturesView.chunk(start, size),
      dstView,
      secureRandomBytes,
      id.uint.toBytes(bigEndian))

  # Note: to avoid memory leaks, even if there is a `false` partial state
  #       (for example due to a point at infinit),
  #       we still need to call `sync` on all tasks.

  # Stage 2: Reduce partial pairings
  # --------------------------------
  if true: # numAccums < 4: # Linear merge
    result = sync partialStates[0]
    for i in 1 ..< numAccums:
      result = result and sync partialStates[i]
      if result: # As long as no error is returned, accumulate
        result = result and accums[0].merge(accums[i])
    if not result: # Don't proceed to final exponentiation if there is already an error
      return false

  else: # Parallel logarithmic merge via recursive divide-and-conquer
    proc treeMergeAccums(
           tp: Threadpool,
           partialStates: ptr UncheckedArray[FlowVar[bool]],
           accums: ptr UncheckedArray[BLSBatchSigAccumulator[H, FF1, FF2, Fpk, ECP_ShortW_Jac[Sig.F, Sig.G], k]],
           start, stopEx: int): bool {.nimcall, gcsafe.} =
      let mid = (start + stopEx) shr 1
      if stopEx - start == 1:
        # Odd number of batches
        return true
      elif stopEx-start == 2:
        # Leaf node
        result = sync partialStates[start]
        result = result and sync partialStates[stopEx-1]
        if not result: # If an error was returned, no need to accumulate
          return false
        return accums[start].merge(accums[stopEx-1])

      # Subtree puts partial reduction in "start"
      let leftOkFV = tp.spawn treeMergeAccums(tp, partialStates, accums, start, mid)
      # Subtree puts partial reduction in "mid"
      let rightOkFV = treeMergeAccums(tp, partialStates, accums, mid, stopEx)

      # Wait for all subtrees, important: don't shortcut booleans as future/flowvar memory is released on sync
      let leftOk = sync(leftOkFV)
      let rightOk = rightOkFV
      if not leftOk or not rightOk:
        return false
      return accums[start].merge(accums[mid])

    let ok = tp.treeMergeAccums(partialStates, accums, start = 0, stopEx = numAccums)
    if not ok:
      return false

  return accums[0].finalVerify()