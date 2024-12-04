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
       ./cyclotomic_subgroups, ./gt_prj,
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

proc bucketAccumReduce_withInit[bits: static int, GtAcc, GtElt](
       windowProd: ptr GtAcc,
       buckets: ptr GtAcc or ptr UncheckedArray[GtAcc],
       bitIndex: int,  miniMultiExpKind: static MiniMultiExpKind, c: static int,
       elems: ptr UncheckedArray[GtElt], expos: ptr UncheckedArray[BigInt[bits]], N: int) =
  const numBuckets = 1 shl (c-1)
  let buckets = cast[ptr UncheckedArray[GtAcc]](buckets)
  for i in 0 ..< numBuckets:
    buckets[i].setNeutral()
  bucketAccumReduce(windowProd[], buckets, bitIndex, miniMultiExpKind, c, elems, expos, N)

proc multiexpImpl_vartime_parallel[bits: static int, GtAcc, GtElt](
       tp: Threadpool,
       r: ptr GtAcc,
       elems: ptr UncheckedArray[GtElt], expos: ptr UncheckedArray[BigInt[bits]],
       N: int, c: static int) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  let miniMultiExpsResults = allocHeapArray(GtAcc, numFullWindows)
  let miniMultiExpsReady   = allocStackArray(FlowVar[bool], numFullWindows)

  let bucketsMatrix = allocHeapArrayAligned(GtAcc, numBuckets*numWindows, alignment = 64)

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
  const msmKind = if top == 0: kBottomWindow
                  elif excess == 0: kFullWindow
                  else: kTopWindow

  bucketAccumReduce_withInit(
    r,
    bucketsMatrix[numFullWindows*numBuckets].addr,
    bitIndex = top, msmKind, c,
    elems, expos, N)

  # 3. Final reduction
  for w in countdown(numFullWindows-1, 0):
    for _ in 0 ..< c:
      r[].cyclotomic_square()
    discard sync miniMultiExpsReady[w]
    r[] ~*= miniMultiExpsResults[w]

  # Cleanup
  # -------
  miniMultiExpsResults.freeHeap()
  bucketsMatrix.freeHeapAligned()

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

  const M = when Gt.Name.getEmbeddingDegree() == 6:  2
            elif Gt.Name.getEmbeddingDegree() == 12: 4
            else: {.error: "Unconfigured".}

  const L = Fr[Gt.Name].bits().computeEndoRecodedLength(M)
  let splitExpos   = allocHeapArrayAligned(array[M, BigInt[L]], N, alignment = 64)
  let endoBasis    = allocHeapArrayAligned(array[M, GT], N, alignment = 64)

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
    endoElems.freeHeapAligned()
    endoExpos.freeHeapAligned()
  else:
    multiExpProc(tp, r, elems, expos, N, c)

# Torus acceleration
# -----------------------------------------------------------------------------------------------------------------------

proc paraNaiveConversion[F](
  tp: Threadpool,
  dst: ptr UncheckedArray[T2Aff[F]],
  src: ptr UncheckedArray[QuadraticExt[F]],
  N: int) =

  # Cryptic error
  #   Error: cannot use symbol of kind 'param' as a 'let'
  # if we inline the following in the `withTorus` template

  # TODO: Parallel Montgomery batch inversion

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {dst, src}
      # TODO: Parallel batch conversion
      fromGT_vartime(dst[i], src[i])

template withTorus[exponentsBits: static int, GT](
           multiExpProc: untyped,
           tp: Threadpool,
           r: ptr GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           len: int, c: static int) =
  static: doAssert Gt is QuadraticExt, "GT was: " & $Gt
  type F = typeof(elems[0].c0)
  var elemsTorus = allocHeapArrayAligned(T2Aff[F], len, alignment = 64)
  paraNaiveConversion(tp, elemsTorus, elems, len)
  var r_torus {.noInit.}: T2Prj[F]
  multiExpProc(tp, r_torus.addr, elemsTorus, expos, len, c)
  r[].fromTorus2_vartime(r_torus)
  elemsTorus.freeHeapAligned()

# Combined accel
# -----------------------------------------------------------------------------------------------------------------------

# Endomorphism acceleration on a torus can be implemented through either of the following approaches:
# - First convert to Torus then apply endomorphism acceleration
# - or apply endomorphism acceleration then convert to Torus
#
# The first approach minimizes memory as we use a compressed torus representation and is easier to compose (no withEndoTorus)
# the second approach reuses Constantine's Frobenius implementation.
# It's unsure which one is more efficient, but difference is dwarfed by the rest of the compute.

proc applyEndoTorus_parallel[bits: static int, GT](
       tp: Threadpool,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]],
       N: int): auto =
  ## Decompose (elems, expos) into mini-scalars
  ## and apply Torus conversion
  ## Returns a new triplet (endoTorusElems, endoTorusExpos, N)
  ## endoTorusElems and endoTorusExpos MUST be freed afterwards

  const M = when Gt.Name.getEmbeddingDegree() == 6:  2
            elif Gt.Name.getEmbeddingDegree() == 12: 4
            else: {.error: "Unconfigured".}

  const L = Fr[Gt.Name].bits().computeEndoRecodedLength(M)
  let splitExpos   = allocHeapArrayAligned(array[M, BigInt[L]], N, alignment = 64)
  let endoBasis    = allocHeapArrayAligned(array[M, GT], N, alignment = 64)

  type F = typeof(elems[0].c0)
  let endoTorusBasis = allocHeapArrayAligned(array[M, T2Aff[F]], N, alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {elems, expos, splitExpos, endoBasis, endoTorusBasis}

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

      # TODO: we batch-torus convert M by M
      # but we could parallel batch convert over the whole range
      endoTorusBasis[i].batchFromGT_vartime(endoBasis[i])

  let endoTorusElems  = cast[ptr UncheckedArray[T2Aff[F]]](endoTorusBasis)
  let endoExpos = cast[ptr UncheckedArray[BigInt[L]]](splitExpos)
  endoBasis.freeHeapAligned()

  return (endoTorusElems, endoExpos, M*N)

template withEndoTorus[exponentsBits: static int, GT](
           multiExpProc: untyped,
           tp: Threadpool,
           r: ptr GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           N: int, c: static int) =
  when Gt.Name.hasEndomorphismAcceleration() and
        EndomorphismThreshold <= exponentsBits and
        exponentsBits <= Fr[Gt.Name].bits():
    let (endoTorusElems, endoExpos, endoN) = applyEndoTorus_parallel(tp, elems, expos, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # TODO: bench
    type F = typeof(elems[0].c0)
    var r_torus {.noInit.}: T2Prj[F]
    multiExpProc(tp, r_torus.addr, endoTorusElems, endoExpos, endoN, c)
    r[].fromTorus2_vartime(r_torus)
    endoTorusElems.freeHeapAligned()
    endoExpos.freeHeapAligned()
  else:
    withTorus(multiExpProc, r, elems, expos, N, c)

# Algorithm selection
# -----------------------------------------------------------------------------------------------------------------------

proc multiexp_dispatch_vartime_parallel[bits: static int, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]], N: int,
       useTorus: static bool) =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # TODO: benchmark

  when useTorus:
    case c
    of  2: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  2)
    of  3: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  3)
    of  4: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  4)
    of  5: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  5)
    of  6: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  6)
    of  7: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  7)
    of  8: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  8)
    of  9: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c =  9)
    of 10: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 10)
    of 11: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 11)
    of 12: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 12)
    of 13: withEndoTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 13)
    of 14: withTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 14)
    of 15: withTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 15)

    of 16..17: withTorus(multiExpImpl_vartime_parallel, tp, r, elems, expos, N, c = 16)
    else:
      unreachable()
  else:
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
       len: int,
       useTorus: static bool = false) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  tp.multiExp_dispatch_vartime_parallel(r, elems, expos, len, useTorus)

proc multiExp_vartime_parallel*[bits: static int, GT](
       tp: Threadpool,
       r: var GT,
       elems: openArray[GT],
       expos: openArray[BigInt[bits]],
       useTorus: static bool = false) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  tp.multiExp_dispatch_vartime_parallel(r.addr, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)

proc multiExp_vartime_parallel*[F, GT](
       tp: Threadpool,
       r: ptr GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[F],
       len: int,
       useTorus: static bool = false) {.meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let n = cast[int](len)
  let expos_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< n:
      captures: {expos, expos_big}
      expos_big[i].fromField(expos[i])
  tp.multiExp_vartime_parallel(r, elems, expos_big, n, useTorus)

  expos_big.freeHeapAligned()

proc multiExp_vartime_parallel*[GT](
       tp: Threadpool,
       r: var GT,
       elems: openArray[GT],
       expos: openArray[Fr],
       useTorus: static bool = false) {.meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  tp.multiExp_vartime_parallel(r.addr, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)
