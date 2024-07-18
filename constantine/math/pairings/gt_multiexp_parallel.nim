# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/named/algebras,
       constantine/math/endomorphisms/split_scalars,
       constantine/math/extension_fields,
       constantine/math/arithmetic,
       constantine/named/zoo_endomorphisms,
       constantine/platforms/abstractions,
       ./cyclotomic_subgroups,
       constantine/threadpool

import ./gt_multiexp {.all.}

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ########################################################### #
#                                                             #
#             Multi-Exponentiation in 𝔾ₜ                      #
#                                                             #
# ########################################################### #

proc bucketAccumReduce_withInit[bits: static int, GT](
       windowProd: ptr GT,
       buckets: ptr GT or ptr UncheckedArray[GT],
       bitIndex: int,  miniMultiExpKind: static MiniMultiExpKind, c: static int,
       elems: ptr UncheckedArray[GT], expos: ptr UncheckedArray[BigInt[bits]], N: int) =
  const numBuckets = 1 shl (c-1)
  let buckets = cast[ptr UncheckedArray[GT]](buckets)
  for i in 0 ..< numBuckets:
    buckets[i].setNeutral()
  bucketAccumReduce(windowProd[], buckets, bitIndex, miniMultiExpKind, c, elems, expos, N)

proc multiexpImpl_vartime_parallel[bits: static int, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT], expos: ptr UncheckedArray[BigInt[bits]],
       N: int, c: static int) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  let miniMultiExpsResults = allocHeapArray(GT, numFullWindows)
  let miniMultiExpsReady   = allocStackArray(FlowVar[bool], numFullWindows)

  let bucketsMatrix = allocHeapArray(GT, numBuckets*numWindows)

  # Algorithm
  # ---------

  block: # 1. Bucket accumulation and reduction
    miniMultiExpsReady[0] = tp.spawnAwaitable bucketAccumReduce_withInit(
                                  miniMultiExpsResults[0].addr,
                                  bucketsMatrix[0].addr,
                                  bitIndex = 0, kBottomWindow, c,
                                  elems, expos, N)

  for w in 1 ..< numFullWindows:
    miniMultiExpsReady[w] = tp.spawnAwaitable bucketAccumReduce_withInit(
                                  miniMultiExpsResults[w].addr,
                                  bucketsMatrix[w*numBuckets].addr,
                                  bitIndex = w*c, kFullWindow, c,
                                  elems, expos, N)

  # Last window is done sync on this thread, directly initializing r
  const excess = bits mod c
  const top = bits-excess

  when top != 0:
    when excess != 0:
      bucketAccumReduce_withInit(
        r,
        bucketsMatrix[numFullWindows*numBuckets].addr,
        bitIndex = top, kTopWindow, c,
        elems, expos, N)
    else:
      r[].setNeutral()

  # 3. Final reduction, r initialized to what would be miniMSMsReady[numWindows-1]
  when excess != 0:
    for w in countdown(numWindows-2, 0):
      for _ in 0 ..< c:
        r[].cyclotomic_square()
      discard sync miniMultiExpsReady[w]
      r[] ~*= miniMultiExpsResults[w]
  elif numWindows >= 2:
    discard sync miniMultiExpsReady[numWindows-2]
    r[] = miniMultiExpsResults[numWindows-2]
    for w in countdown(numWindows-3, 0):
      for _ in 0 ..< c:
        r[].cyclotomic_square()
      discard sync miniMultiExpsReady[w]
      r[] ~*= miniMultiExpsResults[w]

  # Cleanup
  # -------
  miniMultiExpsResults.freeHeap()
  bucketsMatrix.freeHeap()

# Endomorphism acceleration
# -----------------------------------------------------------------------------------------------------------------------

proc applyEndomorphism_parallel[bits: static int, GT](
       tp: Threadpool,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]],
       N: int): auto =
  ## Decompose (elems, expos) into mini-scalars
  ## Returns a new triplet (endoElems, endoExpos, N)
  ## endoElems and endoExpos MUST be freed afterwards

  const M = when Gt is Fp6:  2
            elif Gt is Fp12: 4
            else: {.error: "Unconfigured".}

  const L = Fr[Gt.Name].bits().computeEndoRecodedLength(M)
  let splitExpos   = allocHeapArray(array[M, BigInt[L]], N)
  let endoBasis    = allocHeapArray(array[M, GT], N)

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {elems, expos, splitExpos, endoBasis}

      var negateElems {.noinit.}: array[M, SecretBool]
      splitExpos[i].decomposeEndo(negateElems, expos[i], Fr[Gt.Name].bits(), Gt.Name, G2) # 𝔾ₜ has same decomposition as 𝔾₂
      if negateElems[0].bool:
        endoBasis[i][0].cyclotomic_inv(elems[i])
      else:
        endoBasis[i][0] = elems[i]

      cast[ptr array[M-1, GT]](endoBasis[i][1].addr)[].computeEndomorphisms(elems[i])
      for m in 1 ..< M:
        if negateElems[m].bool:
          endoBasis[i][m].cyclotomic_inv()

  let endoElems  = cast[ptr UncheckedArray[GT]](endoBasis)
  let endoExpos = cast[ptr UncheckedArray[BigInt[L]]](splitExpos)

  return (endoElems, endoExpos, M*N)

template withEndo[exponentsBits: static int, GT](
           multiExpProc: untyped,
           tp: Threadpool,
           r: ptr GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           N: int, c: static int) =
  when Gt.Name.hasEndomorphismAcceleration() and
        EndomorphismThreshold <= exponentsBits and
        exponentsBits <= Fr[Gt.Name].bits():
    let (endoElems, endoExpos, endoN) = applyEndomorphism_parallel(tp, elems, expos, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # TODO: bench
    multiExpProc(tp, r, endoElems, endoExpos, endoN, c)
    freeHeap(endoElems)
    freeHeap(endoExpos)
  else:
    multiExpProc(tp, r, elems, expos, N, c)

# Algorithm selection
# -----------------------------------------------------------------------------------------------------------------------

proc multiexp_dispatch_vartime_parallel[bits: static int, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]], N: int) =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # TODO: benchmark

  case c
  of  2: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  2)
  of  3: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  3)
  of  4: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  4)
  of  5: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  5)
  of  6: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  6)
  of  7: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  7)
  of  8: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  8)
  of  9: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  9)
  of 10: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 10)
  of 11: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 11)
  of 12: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 12)
  of 13: withEndo(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 13)
  of 14: multiExpImpl_vartime_parallel(tp, r, elems, expos, N, c = 14)
  of 15: multiExpImpl_vartime_parallel(tp, r, elems, expos, N, c = 15)

  of 16..17: multiExpImpl_vartime_parallel(tp, r, elems, expos, N, c = 16)
  else:
    unreachable()

proc multiExp_vartime_parallel*[bits: static int, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]],
       len: int) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  tp.multiExp_dispatch_vartime_parallel(r, elems, expos, len)

proc multiExp_vartime_parallel*[bits: static int, GT](
       tp: Threadpool,
       r: var GT,
       elems: openArray[GT],
       expos: openArray[BigInt[bits]]) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  tp.multiExp_dispatch_vartime_parallel(r.addr, elems.asUnchecked(), expos.asUnchecked(), N)

proc multiExp_vartime_parallel*[F, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[F],
       len: int) {.meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let n = cast[int](len)
  let expos_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< n:
      captures: {expos, expos_big}
      expos_big[i].fromField(expos[i])
  tp.multiExp_vartime_parallel(r, elems, expos_big, n)

  freeHeapAligned(expos_big)

proc multiExp_vartime_parallel*[GT](
       tp: Threadpool,
       r: var GT,
       elems: openArray[GT],
       expos: openArray[Fr]) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  tp.multiExp_vartime_parallel(r.addr, elems.asUnchecked(), expos.asUnchecked(), N)
