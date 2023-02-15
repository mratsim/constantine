# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./ec_multi_scalar_mul_scheduler
export bestBucketBitSize

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

func multiScalarMulImpl_reference_vartime[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) =
  ## Inner implementation of MSM, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4

  # Prologue
  # --------
  const numBuckets = 1 shl c - 1 # bucket 0 is unused
  const numWindows = (bits + c - 1) div c
  type EC = typeof(r)

  let miniMSMs = allocHeapArray(EC, numWindows)
  let buckets = allocHeapArray(EC, numBuckets)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our points in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setInf()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
    for j in 0 ..< N:
      let b = cast[int](coefs[j].getWindowAt(w*c, c))
      if b == 0: # bucket 0 is unused, no need to add [0]Pⱼ
        continue
      else:
        buckets[b-1] += points[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-MSM
    #   [1]S₁ + [2]S₂ + [3]S₃ + ... + [2ᶜ-1]S₂c₋₁
    var accumBuckets{.noInit.}, miniMSM{.noInit.}: EC
    accumBuckets = buckets[numBuckets-1]
    miniMSM = buckets[numBuckets-1]

    # Example with c = 3, 2³ = 8
    for k in countdown(numBuckets-2, 0):
      accumBuckets += buckets[k] # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
      miniMSM += accumBuckets    # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

    miniMSMs[w] = miniMSM

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c doublings + 1 addition per window
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r += miniMSMs[w]

  # Cleanup
  # -------
  buckets.freeHeap()
  miniMSMs.freeHeap()

func multiScalarMul_reference_vartime*[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff]) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  let N = points.len
  let coefs = coefs.asUnchecked()
  let points = points.asUnchecked()
  let c = bestBucketBitSize(N, BigInt.bits, useSignedBuckets = false)

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
  of 16: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 16)
  of 17: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 17)
  of 18: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 18)
  of 19: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 19)
  of 20: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 20)
  of 21: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 21)
  of 22: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 22)
  of 23: multiScalarMulImpl_reference_vartime(r, coefs, points, N, c = 23)
  else:
    unreachable()

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

func accumulate[F, G](buckets: ptr UncheckedArray[ECP_ShortW_JacExt[F, G]], val: SecretWord, negate: SecretBool, point: ECP_ShortW_Aff[F, G]) {.inline, meter.} =
  let val = BaseType(val)
  if val == 0: # Skip [0]P
    return
  elif negate.bool:
    buckets[val-1] -= point
  else:
    buckets[val-1] += point

func bucketReduce[EC](r: var EC, buckets: ptr UncheckedArray[EC], numBuckets: static int) {.meter.} =
  # We interleave reduction with zero-ing the bucket to use instruction-level parallelism

  var accumBuckets{.noInit.}: typeof(r)
  accumBuckets = buckets[numBuckets-1]
  r = buckets[numBuckets-1]
  buckets[numBuckets-1].setInf()

  for k in countdown(numBuckets-2, 0):
    accumBuckets += buckets[k]
    r += accumBuckets
    buckets[k].setInf()

type MiniMsmKind = enum
  kTopWindow
  kFullWindow
  kBottomWindow

func miniMSM_jacext[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       buckets: ptr UncheckedArray[ECP_ShortW_JacExt[F, G]],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) {.meter.} =
  ## Apply a mini-Multi-Scalar-Multiplication on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs

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
  var sliceSum{.noinit.}: ECP_ShortW_JacExt[F, G]
  sliceSum.bucketReduce(buckets, numBuckets = 1 shl (c-1))

  # 3. Mini-MSM on the slice [bitIndex, bitIndex+window)
  var windowSum{.noInit.}: typeof(r)
  windowSum.fromJacobianExtended_vartime(sliceSum)
  r += windowSum

  when miniMsmKind != kBottomWindow:
    for _ in 0 ..< c:
      r.double()

func multiScalarMulJacExt_vartime[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) {.meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # Setup
  # -----
  const numBuckets = 1 shl (c-1)
  type EcBucket = ECP_ShortW_JacExt[F, G]

  let buckets = allocHeapArray(EcBucket, numBuckets)
  zeroMem(buckets[0].addr, sizeof(EcBucket) * numBuckets)

  # Algorithm
  # ---------
  const excess = bits mod c
  const top = bits - excess
  var w = top
  r.setInf()

  if excess != 0 and w != 0: # Prologue
    r.miniMSM_jacext(buckets, w, kTopWindow, c, coefs, points, N)
    w -= c

  while w != 0:              # Steady state
    r.miniMSM_jacext(buckets, w, kFullWindow, c, coefs, points, N)
    w -= c

  block:                     # Epilogue
    r.miniMSM_jacext(buckets, w, kBottomWindow, c, coefs, points, N)

  # Cleanup
  # -------
  buckets.freeHeap()

func miniMSM_affine[NumBuckets, QueueLen, F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       sched: var Scheduler[NumBuckets, QueueLen, F, G],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], N: int) {.meter.} =
  ## Apply a mini-Multi-Scalar-Multiplication on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs

  const excess = bits mod c
  const top = bits - excess
  static: doAssert miniMsmKind != kTopWindow, "The top window is smaller in bits which increases collisions in scheduler."

  sched.buckets[].init()

  # 1. Bucket Accumulation
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

  # 2. Bucket Reduction
  var sliceSum{.noInit.}: ECP_ShortW_JacExt[F, G]
  sliceSum.bucketReduce(sched.buckets[])

  # 3. Mini-MSM on the slice [bitIndex, bitIndex+window)
  var windowSum{.noInit.}: typeof(r)
  windowSum.fromJacobianExtended_vartime(sliceSum)
  r += windowSum

  when miniMsmKind != kBottomWindow:
    for _ in 0 ..< c:
      r.double()

func multiScalarMulAffine_vartime[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) {.meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # Setup
  # -----
  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  const schedQueueLen = max(32, queueLen)
  let buckets = allocHeap(Buckets[numBuckets, F, G])
  buckets[].init()
  let sched = allocHeap(Scheduler[numBuckets, schedQueueLen, F, G])
  sched[].init(points, buckets, 0, numBuckets.int32)

  # Algorithm
  # ---------
  const excess = bits mod c
  const top = bits - excess
  var w = top
  r.setInf()

  if excess != 0 and w != 0: # Prologue
    # The top might use only a few bits, the affine scheduler would likely have significant collisions
    zeroMem(sched.buckets.ptJacExt.addr, buckets.ptJacExt.sizeof())
    r.miniMSM_jacext(sched.buckets.ptJacExt.asUnchecked(), w, kTopWindow, c, coefs, points, N)
    w -= c

  while w != 0:              # Steady state
    r.miniMSM_affine(sched[], w, kFullWindow, c, coefs, N)
    w -= c

  block:                     # Epilogue
    r.miniMSM_affine(sched[], w, kBottomWindow, c, coefs, N)

  # Cleanup
  # -------
  sched.freeHeap()
  buckets.freeHeap()

func multiScalarMul_vartime*[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff]) {.meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  let N = points.len
  let coefs = coefs.asUnchecked()
  let points = points.asUnchecked()
  let c = bestBucketBitSize(N, BigInt.bits, useSignedBuckets = true)

  case c
  of  2: multiScalarMulJacExt_vartime(r, coefs, points, N, c =  2)
  of  3: multiScalarMulJacExt_vartime(r, coefs, points, N, c =  3)
  of  4: multiScalarMulJacExt_vartime(r, coefs, points, N, c =  4)
  of  5: multiScalarMulJacExt_vartime(r, coefs, points, N, c =  5)
  of  6: multiScalarMulAffine_vartime(r, coefs, points, N, c =  6)
  of  7: multiScalarMulAffine_vartime(r, coefs, points, N, c =  7)
  of  8: multiScalarMulAffine_vartime(r, coefs, points, N, c =  8)
  of  9: multiScalarMulAffine_vartime(r, coefs, points, N, c =  9)
  of 10: multiScalarMulAffine_vartime(r, coefs, points, N, c = 10)
  of 11: multiScalarMulAffine_vartime(r, coefs, points, N, c = 11)
  of 12: multiScalarMulAffine_vartime(r, coefs, points, N, c = 12)
  of 13: multiScalarMulAffine_vartime(r, coefs, points, N, c = 13)
  of 14: multiScalarMulAffine_vartime(r, coefs, points, N, c = 14)
  of 15: multiScalarMulAffine_vartime(r, coefs, points, N, c = 15)
  of 16: multiScalarMulAffine_vartime(r, coefs, points, N, c = 16)
  of 17: multiScalarMulAffine_vartime(r, coefs, points, N, c = 17)
  of 18: multiScalarMulAffine_vartime(r, coefs, points, N, c = 18)
  of 19: multiScalarMulAffine_vartime(r, coefs, points, N, c = 19)
  of 20: multiScalarMulAffine_vartime(r, coefs, points, N, c = 20)
  of 21: multiScalarMulAffine_vartime(r, coefs, points, N, c = 21)
  of 22: multiScalarMulAffine_vartime(r, coefs, points, N, c = 22)
  of 23: multiScalarMulAffine_vartime(r, coefs, points, N, c = 23)
  else:
    unreachable()