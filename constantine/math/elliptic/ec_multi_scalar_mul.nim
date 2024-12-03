# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/named/algebras,
       ./ec_multi_scalar_mul_scheduler,
       constantine/math/endomorphisms/split_scalars,
       constantine/math/extension_fields,
       constantine/named/zoo_endomorphisms,
       constantine/platforms/abstractions
export bestBucketBitSize, abstractions

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ########################################################### #
#                                                             #
#             Multi Scalar Multiplication                     #
#                                                             #
# ########################################################### #

# Multi-scalar-multiplication is the primary bottleneck in all zero-knowledge proofs and polynomial commmitment schemes.
# In particular, those are at the heart of zk-rollups to bundle a large amount of blockchain transactions.
# They may have to add tens of millions of elliptic curve points to generate proofs,
# requiring powerful machines, GPUs or even FPGAs implementations.
#
# Multi-scalar multiplication does a linear combination of
#   R = [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
#
# The current iteration is a reference baseline before evaluating and adding various optimizations
# (scalar recoding, change of coordinate systems, bucket sizing, sorting ...)
#
# See the litterature references at the top of `ec_multi_scalar_mul_scheduler.nim`

func multiScalarMulImpl_reference_vartime[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc].} =
  ## Inner implementation of MSM, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4

  # Prologue
  # --------
  const numBuckets = 1 shl c - 1 # bucket 0 is unused
  const numWindows = bits.ceilDiv_vartime(c)

  let miniMSMs = allocHeapArrayAligned(EC, numWindows, alignment = 64)
  let buckets = allocHeapArrayAligned(EC, numBuckets, alignment = 64)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our points in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setNeutral()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
    for j in 0 ..< N:
      let b = cast[int](coefs[j].getWindowAt(w*c, c))
      if b == 0: # bucket 0 is unused, no need to add [0]Pⱼ
        continue
      else:
        buckets[b-1] ~+= points[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-MSM
    #   [1]S₁ + [2]S₂ + [3]S₃ + ... + [2ᶜ-1]S₂c₋₁
    var accumBuckets{.noInit.}, miniMSM{.noInit.}: EC
    accumBuckets = buckets[numBuckets-1]
    miniMSM = buckets[numBuckets-1]

    # Example with c = 3, 2³ = 8
    for k in countdown(numBuckets-2, 0):
      accumBuckets ~+= buckets[k] # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
      miniMSM ~+= accumBuckets    # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

    miniMSMs[w] = miniMSM

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c doublings + 1 addition per window
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r ~+= miniMSMs[w]

  # Cleanup
  # -------
  buckets.freeHeapAligned()
  miniMSMs.freeHeapAligned()

func multiScalarMul_reference_dispatch_vartime[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       N: int) {.tags:[VarTime, HeapAlloc].} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = false, useManualTuning = false)

  case c
  of  2: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  2)
  of  3: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  3)
  of  4: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  4)
  of  5: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  5)
  of  6: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  6)
  of  7: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  7)
  of  8: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  8)
  of  9: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c =  9)
  of 10: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 10)
  of 11: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 11)
  of 12: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 12)
  of 13: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 13)
  of 14: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 14)
  of 15: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 15)

  of 16..20: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 16)
  else:
    unreachable()

func multiScalarMul_reference_vartime*[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       N: int) {.tags:[VarTime, HeapAlloc].} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  multiScalarMul_reference_dispatch_vartime(r, coefs, points, N)

func multiScalarMul_reference_vartime*[EC, ECaff](r: var EC, coefs: openArray[BigInt], points: openArray[ECaff]) {.tags:[VarTime, HeapAlloc].} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len
  let N = points.len
  multiScalarMul_reference_dispatch_vartime(r, coefs.asUnchecked(), points.asUnchecked(), N)

func multiScalarMul_reference_vartime*[F, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[F],
       points: ptr UncheckedArray[ECaff],
       len: int) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  let n = cast[int](len)
  let coefs_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)
  coefs_big.batchFromField(coefs, n)
  r.multiScalarMul_reference_vartime(coefs_big, points, n)

  coefs_big.freeHeapAligned()

func multiScalarMul_reference_vartime*[EC, ECaff](
       r: var EC,
       coefs: openArray[Fr],
       points: openArray[ECaff]) {.tags:[VarTime, Alloca, HeapAlloc], inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  debug: doAssert coefs.len == points.len
  let N = points.len
  multiScalarMul_reference_vartime(r, coefs.asUnchecked(), points.asUnchecked(), N)

# ########################################################### #
#                                                             #
#                 Multi Scalar Multiplication                 #
#                     Optimized versions                      #
#                                                             #
# ########################################################### #
#
# Multi-Scalar-Mul is the largest bottleneck in Zero-Knowledge-Proofs protocols
# There are ways to avoid FFTs, none to avoid Multi-Scalar-Multiplication
# Hence optimizing it is worth millions, see https://zprize.io

func accumulate[EC, ECaff](buckets: ptr UncheckedArray[EC], val: SecretWord, negate: SecretBool, point: ECaff) {.inline, meter.} =
  let val = BaseType(val)
  if val == 0: # Skip [0]P
    return
  elif negate.bool:
    buckets[val-1] ~-= point
  else:
    buckets[val-1] ~+= point

func bucketReduce[EC](r: var EC, buckets: ptr UncheckedArray[EC], numBuckets: static int) {.meter.} =
  # We interleave reduction with zero-ing the bucket to use instruction-level parallelism

  var accumBuckets{.noInit.}: typeof(r)
  accumBuckets = buckets[numBuckets-1]
  r = buckets[numBuckets-1]
  buckets[numBuckets-1].setNeutral()

  for k in countdown(numBuckets-2, 0):
    accumBuckets ~+= buckets[k]
    r ~+= accumBuckets
    buckets[k].setNeutral()

type MiniMsmKind* = enum
  kTopWindow
  kFullWindow
  kBottomWindow

func bucketAccumReduce*[bits: static int, EC, ECaff](
       r: var EC,
       buckets: ptr UncheckedArray[EC],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff], N: int) =

  const excess = bits mod c
  const top = bits - excess

  # 1. Bucket Accumulation
  var curVal, nextVal: SecretWord
  var curNeg, nextNeg: SecretBool

  template getSignedWindow(j : int): tuple[val: SecretWord, neg: SecretBool] =
    when miniMsmKind == kBottomWindow: coefs[j].getSignedBottomWindow(c)
    elif miniMsmKind == kTopWindow:    coefs[j].getSignedTopWindow(top, excess)
    else:                              coefs[j].getSignedFullWindowAt(bitIndex, c)

  (curVal, curNeg) = getSignedWindow(0)
  for j in 0 ..< N-1:
    (nextVal, nextNeg) = getSignedWindow(j+1)
    if nextVal.BaseType != 0:
      # In cryptography, points are indistinguishable from random
      # hence, without prefetching, accessing the next bucket is a guaranteed cache miss
      prefetchLarge(buckets[nextVal.BaseType-1].addr, Write, HighTemporalLocality, maxCacheLines = 2)
    buckets.accumulate(curVal, curNeg, points[j])
    curVal = nextVal
    curNeg = nextNeg
  buckets.accumulate(curVal, curNeg, points[N-1])

  # 2. Bucket Reduction
  r.bucketReduce(buckets, numBuckets = 1 shl (c-1))

func miniMSM[bits: static int, EC, ECaff](
       r: var EC,
       buckets: ptr UncheckedArray[EC],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff], N: int) {.meter.} =
  ## Apply a mini-Multi-Scalar-Multiplication on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs

  var windowSum{.noInit.}: typeof(r)
  windowSum.bucketAccumReduce(
    buckets, bitIndex, miniMsmKind, c,
    coefs, points, N)

  # 3. Mini-MSM on the slice [bitIndex, bitIndex+window)
  r ~+= windowSum
  when miniMsmKind != kBottomWindow:
    for _ in 0 ..< c:
      r.double()

func msmImpl_vartime[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # Setup
  # -----
  const numBuckets = 1 shl (c-1)

  let buckets = allocHeapArrayAligned(EC, numBuckets, alignment = 64)
  for i in 0 ..< numBuckets:
    buckets[i].setNeutral()

  # Algorithm
  # ---------
  const excess = bits mod c
  const top = bits - excess
  var w = top
  r.setNeutral()

  when top != 0:      # Prologue
    when excess != 0:
      r.miniMSM(buckets, w, kTopWindow, c, coefs, points, N)
      w -= c
    else:
      # If c divides bits exactly, the signed windowed recoding still needs to see an extra 0
      # Since we did r.setNeutral() earlier, this is a no-op
      discard

  while w != 0:       # Steady state
    r.miniMSM(buckets, w, kFullWindow, c, coefs, points, N)
    w -= c

  block:              # Epilogue
    r.miniMSM(buckets, w, kBottomWindow, c, coefs, points, N)

  # Cleanup
  # -------
  buckets.freeHeapAligned()

# Multi scalar multiplication with batched affine additions
# -----------------------------------------------------------------------------------------------------------------------

func schedAccumulate*[NumBuckets, QueueLen, F, G; bits: static int](
       sched: ptr Scheduler[NumBuckets, QueueLen, F, G],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], N: int) {.meter.} =

  const excess = bits mod c
  const top = bits - excess
  static: doAssert miniMsmKind != kTopWindow, "The top window is smaller in bits which increases collisions in scheduler."

  sched.bucketInit()

  var curSP, nextSP: ScheduledPoint

  template getSignedWindow(j : int): tuple[val: SecretWord, neg: SecretBool] =
    when miniMsmKind == kBottomWindow: coefs[j].getSignedBottomWindow(c)
    elif miniMsmKind == kTopWindow:    coefs[j].getSignedTopWindow(top, excess)
    else:                              coefs[j].getSignedFullWindowAt(bitIndex, c)

  curSP = scheduledPointDescriptor(0, getSignedWindow(0))
  for j in 0 ..< N-1:
    nextSP = scheduledPointDescriptor(j+1, getSignedWindow(j+1))
    sched.prefetch(nextSP)
    sched.schedule(curSP)
    curSP = nextSP
  sched.schedule(curSP)
  sched.flushPendingAndReset()

func miniMSM_affine[NumBuckets, QueueLen, EC, ECaff; bits: static int](
       r: var EC,
       sched: ptr Scheduler[NumBuckets, QueueLen, EC, ECaff],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], N: int) {.meter.} =
  ## Apply a mini-Multi-Scalar-Multiplication on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs

  # 1. Bucket Accumulation
  sched.schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  # 2. Bucket Reduction
  var windowSum{.noInit.}: EC
  windowSum.bucketReduce(sched.buckets)

  # 3. Mini-MSM on the slice [bitIndex, bitIndex+window)
  r ~+= windowSum

  when miniMsmKind != kBottomWindow:
    for _ in 0 ..< c:
      r.double()

func msmAffineImpl_vartime[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff],
       N: int, c: static int) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # Setup
  # -----
  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  let buckets = allocHeapAligned(Buckets[numBuckets, EC, ECaff], alignment = 64)
  let sched = allocHeapAligned(Scheduler[numBuckets, queueLen, EC, ECaff], alignment = 64)
  sched.init(points, buckets, 0, numBuckets.int32)

  # Algorithm
  # ---------
  const excess = bits mod c
  const top = bits - excess
  var w = top
  r.setNeutral()

  when top != 0:      # Prologue
    when excess != 0:
      # The top might use only a few bits, the affine scheduler would likely have significant collisions
      for i in 0 ..< numBuckets:
        sched.buckets.pt[i].setNeutral()
      r.miniMSM(sched.buckets.pt.asUnchecked(), w, kTopWindow, c, coefs, points, N)
      w -= c
    else:
      # If c divides bits exactly, the signed windowed recoding still needs to see an extra 0
      # Since we did r.setNeutral() earlier, this is a no-op
      discard

  while w != 0:       # Steady state
    r.miniMSM_affine(sched, w, kFullWindow, c, coefs, N)
    w -= c

  block:              # Epilogue
    r.miniMSM_affine(sched, w, kBottomWindow, c, coefs, N)

  # Cleanup
  # -------
  sched.freeHeapAligned()
  buckets.freeHeapAligned()

# Endomorphism acceleration
# -----------------------------------------------------------------------------------------------------------------------

proc applyEndomorphism[bits: static int, ECaff](
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       N: int): auto =
  ## Decompose (coefs, points) into mini-scalars
  ## Returns a new triplet (endoCoefs, endoPoints, N)
  ## endoCoefs and endoPoints MUST be freed afterwards

  const M = when ECaff.F is Fp:  2
            elif ECaff.F is Fp2: 4
            else: {.error: "Unconfigured".}
  const G = when ECaff isnot EC_ShortW_Aff: G1
            else: ECaff.G

  const L = ECaff.getScalarField().bits().computeEndoRecodedLength(M)
  let splitCoefs   = allocHeapArrayAligned(array[M, BigInt[L]], N, alignment = 64)
  let endoBasis    = allocHeapArrayAligned(array[M, ECaff], N, alignment = 64)

  for i in 0 ..< N:
    var negatePoints {.noinit.}: array[M, SecretBool]
    splitCoefs[i].decomposeEndo(negatePoints, coefs[i], ECaff.getScalarField().bits(), ECaff.getName(), G)
    if negatePoints[0].bool:
      endoBasis[i][0].neg(points[i])
    else:
      endoBasis[i][0] = points[i]

    cast[ptr array[M-1, ECaff]](endoBasis[i][1].addr)[].computeEndomorphisms(points[i])
    for m in 1 ..< M:
      if negatePoints[m].bool:
        endoBasis[i][m].neg()

  let endoCoefs = cast[ptr UncheckedArray[BigInt[L]]](splitCoefs)
  let endoPoints  = cast[ptr UncheckedArray[ECaff]](endoBasis)

  return (endoCoefs, endoPoints, M*N)

template withEndo[coefsBits: static int, EC, ECaff](
           msmProc: untyped,
           r: var EC,
           coefs: ptr UncheckedArray[BigInt[coefsBits]],
           points: ptr UncheckedArray[ECaff],
           N: int, c: static int) =
  when hasEndomorphismAcceleration(EC.getName()) and
        EndomorphismThreshold <= coefsBits and
        coefsBits <= EC.getScalarField().bits() and
        # computeEndomorphism assumes they can be applied to affine repr
        # but this is not the case for Bandersnatch/wagon
        # instead Twisted Edwards MSM should be overloaded for Projective/ProjectiveExtended
        EC.getName() notin {Bandersnatch, Banderwagon}:
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism(coefs, points, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # but it has no significant impact on performance
    msmProc(r, endoCoefs, endoPoints, endoN, c)
    endoCoefs.freeHeapAligned()
    endoPoints.freeHeapAligned()
  else:
    msmProc(r, coefs, points, N, c)

# Algorithm selection
# -----------------------------------------------------------------------------------------------------------------------

func msm_dispatch_vartime[bits: static int, F, G](
       r: var (EC_ShortW_Jac[F, G] or EC_ShortW_Prj[F, G]),
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[EC_ShortW_Aff[F, G]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # but it has no significant impact on performance

  case c
  of  2: withEndo(msmImpl_vartime, r, coefs, points, N, c =  2)
  of  3: withEndo(msmImpl_vartime, r, coefs, points, N, c =  3)
  of  4: withEndo(msmImpl_vartime, r, coefs, points, N, c =  4)
  of  5: withEndo(msmImpl_vartime, r, coefs, points, N, c =  5)
  of  6: withEndo(msmImpl_vartime, r, coefs, points, N, c =  6)
  of  7: withEndo(msmImpl_vartime, r, coefs, points, N, c =  7)
  of  8: withEndo(msmImpl_vartime, r, coefs, points, N, c =  8)

  of  9: withEndo(msmAffineImpl_vartime, r, coefs, points, N, c =  9)
  of 10: withEndo(msmAffineImpl_vartime, r, coefs, points, N, c = 10)
  of 11: withEndo(msmAffineImpl_vartime, r, coefs, points, N, c = 11)
  of 12: withEndo(msmAffineImpl_vartime, r, coefs, points, N, c = 12)
  of 13: withEndo(msmAffineImpl_vartime, r, coefs, points, N, c = 13)
  of 14: msmAffineImpl_vartime(r, coefs, points, N, c = 14)
  of 15: msmAffineImpl_vartime(r, coefs, points, N, c = 15)

  of 16..17: msmAffineImpl_vartime(r, coefs, points, N, c = 16)
  else:
    unreachable()

func msm_dispatch_vartime[bits: static int, F](
       r: var EC_TwEdw_Prj[F], coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[EC_TwEdw_Aff[F]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # TODO: tune for Twisted Edwards
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # but it has no significant impact on performance

  case c
  of  2: withEndo(msmImpl_vartime, r, coefs, points, N, c =  2)
  of  3: withEndo(msmImpl_vartime, r, coefs, points, N, c =  3)
  of  4: withEndo(msmImpl_vartime, r, coefs, points, N, c =  4)
  of  5: withEndo(msmImpl_vartime, r, coefs, points, N, c =  5)
  of  6: withEndo(msmImpl_vartime, r, coefs, points, N, c =  6)
  of  7: withEndo(msmImpl_vartime, r, coefs, points, N, c =  7)
  of  8: withEndo(msmImpl_vartime, r, coefs, points, N, c =  8)
  of  9: withEndo(msmImpl_vartime, r, coefs, points, N, c =  9)
  of 10: withEndo(msmImpl_vartime, r, coefs, points, N, c = 10)
  of 11: withEndo(msmImpl_vartime, r, coefs, points, N, c = 11)
  of 12: withEndo(msmImpl_vartime, r, coefs, points, N, c = 12)
  of 13: withEndo(msmImpl_vartime, r, coefs, points, N, c = 13)
  of 14: msmImpl_vartime(r, coefs, points, N, c = 14)
  of 15: msmImpl_vartime(r, coefs, points, N, c = 15)

  of 16..17: msmImpl_vartime(r, coefs, points, N, c = 16)
  else:
    unreachable()

func multiScalarMul_vartime*[bits: static int, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       len: int) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁

  msm_dispatch_vartime(r, coefs, points, len)

func multiScalarMul_vartime*[bits: static int, EC, ECaff](
       r: var EC,
       coefs: openArray[BigInt[bits]],
       points: openArray[ECaff]) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  debug: doAssert coefs.len == points.len
  let N = points.len
  msm_dispatch_vartime(r, coefs.asUnchecked(), points.asUnchecked(), N)

func multiScalarMul_vartime*[F, EC, ECaff](
       r: var EC,
       coefs: ptr UncheckedArray[F],
       points: ptr UncheckedArray[ECaff],
       len: int) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁

  let n = cast[int](len)
  let coefs_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)
  coefs_big.batchFromField(coefs, n)
  r.multiScalarMul_vartime(coefs_big, points, n)

  coefs_big.freeHeapAligned()

func multiScalarMul_vartime*[EC, ECaff](
       r: var EC,
       coefs: openArray[Fr],
       points: openArray[ECaff]) {.tags:[VarTime, Alloca, HeapAlloc], inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  debug: doAssert coefs.len == points.len
  let N = points.len
  multiScalarMul_vartime(r, coefs.asUnchecked(), points.asUnchecked(), N)
