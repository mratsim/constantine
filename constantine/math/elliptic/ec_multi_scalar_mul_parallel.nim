# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./ec_multi_scalar_mul_scheduler,
       ./ec_multi_scalar_mul,
       ./ec_endomorphism_accel,
       ../extension_fields,
       ../constants/zoo_endomorphisms,
       ../../platforms/threadpool/threadpool
export bestBucketBitSize

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ########################################################### #
#                                                             #
#             Parallel Multi Scalar Multiplication            #
#                                                             #
# ########################################################### #
#
# Writeup
#
# Recall the reference implementation in pseudocode
#
# func multiScalarMulImpl_reference_vartime
#
#   c          <- fn(numPoints)  with `fn` a function that minimizes the total number of Elliptic Curve additions
#                                in the order of log2(numPoints) - 3
#   numWindows <- ⌈coefBits/c⌉
#   numBuckets <- 2ᶜ⁻¹
#   r          <- ∅              (The elliptic curve infinity point)
#
#   miniMSMs[0..<numWindows]  <- ∅
#
#   // 0.a MiniMSMs accumulation
#   for w in 0 ..< numWindows:
#
#     // 1.a Bucket accumulation
#     buckets[0..<numBuckets] <- ∅
#     for j in 0 ..< numPoints:
#       b <- coefs[j].getWindowAt(w*c, c)
#       buckets[b] += points[j]
#
#     // 1.r Bucket reduction
#     accumBuckets <- ∅
#     for k in countdown(numBuckets-1, 0):
#       accumBuckets += buckets[k]
#       miniMSMs[w] += accumBuckets
#
#   // 0.r MiniMSM reduction
#   for w in countdown(numWindows-1, 0):
#     for _ in 0 ..< c:
#       r.double()
#     r += miniMSMs[w]
#
#   return r
#
# A comprehensive mapping: inputSize, c, numBuckets is in ec_multi_scalar_mul_scheduler.nim
#
# -------inputs-------    c      ----buckets----   queue length  collision map bytes  num collisions   collision %
#  2^5              32    5      2^4          16           -108                    8            -216       -675.0%
# 2^10            1024    9      2^8         256             52                   32             208         20.3%
# 2^13            8192   11     2^10        1024            180                  128            1440         17.6%
# 2^16           65536   14     2^13        8192            432                 1024            3456          5.3%
# 2^18          262144   16     2^15       32768            640                 4096            5120          2.0% <- ~10MB of buckets
# 2^20         1048576   17     2^16       65536            756                 8192           12096          1.2%
# 2^26        67108864   23     2^22     4194304           1620               524288           25920          0.0%
#
# The coef bits is usually between 128 to 377 depending on endomorphisms and the elliptic curve.
#
# Starting from 64 points, parallelism seems to always be beneficial (serial takes over 1 ms on laptop)
#
# There are 2 parallelism opportunities:
# - 0.a MiniMSMs accumulation is straightforward as there are no data dependencies at all.
# - 1.a Buckets accumulation needs to be parallelized over buckets and not points to avoid synchronization between threads.
#
# We can parallelize the reductions but they would require extra doublings to "place the reduction" at the right bits.
# Example:
#   let's say we compute the binary number 0b11010110
#   Each 1 is add+double, each 0 is just double.
#   We can split the computation in parallel 0b1101 << 4 and 0b0110
#   but now we need 4 extra doublings to shift the high part in the correct place.
# Alternatively we can do "latency hiding", we start the computation before all results are available, and wait for the next part to finish.
#
# Now, with a small c, say 1024 inputs, c=9, the outer parallelism is large: 14 to 28 for 128-bit to 256-bit coefs.
# For large c, say 262k inputs, c=16, the outer parallelism is small:         8 to 16 for 128-bit to 256-bit coefs.
#
# Zero Knowledge protocols need to operate on millions of points, so we want to fully occupy high-end CPUs
# - AMD EPYC 9654 96C/192T on 2 sockets hence 384 threads
# - Intel Xeon Platinum 8490H 60C/120T on 8 sockets hence 960 threads
#
# Inner parallelism has a multiplicative factor on parallelism exposed
# Impact in order of importance of a high chunking factor:
# + the more parallelism opportunities we offer.
# - the more collision we have when setting up sparse vector affine addition
# + the more fine-grained the bucket reduction can be interleaved
# - the more passes over the data there are.
# - the more memory we used
#
# Hence do we want inner parallelism to be
# - a fraction of the number of threads?
# - a multiple of the number of threads?
# - a fraction of the number of buckets?
#
# Back to latency hiding,
# 1. The reductions can be done bottom bits to top bits or top bits to bottom bits.
#    Often bits/c has remainder top bits that are smaller so top to bottom would allow
#    to start the reduction while the rest of the windows are still being processed.
# 2. a thread processes its own tasks in a LIFO manner.
#    But thieves steal tasks in FIFO manner.
#
# Due to 1, it's probable best to reduce in staggered manner from top to bottom.
# But then in which order to issue accumulations?
# 1. Do we schedule the top bits first, in hope they would be stolen. (FIFO thefts)
# 2. or do we schedule the top bits last, so that once we reduce, we directly schedule a related task. (LIFO dequeueing)
#
# Lastly we can go further on latency hiding for the inner parallelism,
# having decreasing range sizes so that the top ranges are ready earlier for interleaving reduction.

# Parallel spawn wrappers
# -----------------------
#
# When spawning:
# - The borrow checker prevents capturing var parameters so we need raw pointers
# - We need a dummy return value (a bool for example) for the task to be awaitable
# - static parameters are not supported (?). They disappear in the codegen
#   but the threadpool will serialize them nonetheless.
#
# So we need wrappers to address all those needs

# Parallel MSM Jacobian Extended
# ------------------------------

template wrapperGenAccumReduce_jacext(miniMsmKind: untyped, c: static int) =
  proc `accumReduce _ miniMsmKind _ jacext`(
          windowSum: ptr ECP_ShortW[F, G],
          buckets: ptr ECP_ShortW_JacExt[F, G] or ptr UncheckedArray[ECP_ShortW_JacExt[F, G]],
          bitIndex: int, coefs: ptr UncheckedArray[BigInt[bits]],
          points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
          N: int): bool {.nimcall, used.} =
    const numBuckets = 1 shl (c-1)
    let buckets = cast[ptr UncheckedArray[ECP_ShortW_JacExt[F, G]]](buckets)
    zeroMem(buckets, sizeof(ECP_ShortW_JacExt[F, G]) * numBuckets)
    bucketAccumReduce_jacext(windowSum[], buckets, bitIndex, miniMsmKind, c, coefs, points, N)
    return true

proc msmJacExt_vartime_parallel*[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  type EC = typeof(r)
  let miniMSMsResults = allocHeapArray(EC, numFullWindows)
  let miniMSMsReady   = allocStackArray(FlowVar[bool], numFullWindows)

  wrapperGenAccumReduce_jacext(kFullWindow, c)
  wrapperGenAccumReduce_jacext(kBottomWindow, c)
  wrapperGenAccumReduce_jacext(kTopWindow, c)

  let bucketsMatrix = allocHeapArray(ECP_ShortW_JacExt[F, G], numBuckets*numWindows)

  # Algorithm
  # ---------

  block: # 1. Bucket accumulation and reduction
    miniMSMsReady[0] = tp.spawn accumReduce_kBottomWindow_jacext(
                                  miniMSMsResults[0].addr,
                                  bucketsMatrix[0].addr,
                                  bitIndex = 0, coefs, points, N)

  for w in 1 ..< numFullWindows:
    miniMSMsReady[w] = tp.spawn accumReduce_kFullWindow_jacext(
                                  miniMSMsResults[w].addr,
                                  bucketsMatrix[w*numBuckets].addr,
                                  bitIndex = w*c, coefs, points, N)

  # Last window is done sync on this thread, directly initializing r
  const excess = bits mod c
  const top = bits-excess

  when top != 0:
    when excess != 0:
      zeroMem(bucketsMatrix[(numWindows-1)*numBuckets].addr, sizeof(ECP_ShortW_JacExt[F, G]) * numBuckets)
      r.bucketAccumReduce_jacext(
          cast[ptr UncheckedArray[ECP_ShortW_JacExt[F, G]]](bucketsMatrix[(numWindows-1)*numBuckets].addr),
          bitIndex = top, kTopWindow, c,
          coefs, points, N)
    else:
      r.setInf()

  # 3. Final reduction, r initialized to what would be miniMSMsReady[numWindows-1]
  when excess != 0:
    for w in countdown(numWindows-2, 0):
      for _ in 0 ..< c:
        r.double()
      discard sync miniMSMsReady[w]
      r += miniMSMsResults[w]
  elif numWindows >= 2:
    discard sync miniMSMsReady[numWindows-2]
    r = miniMSMsResults[numWindows-2]
    for w in countdown(numWindows-3, 0):
      for _ in 0 ..< c:
        r.double()
      discard sync miniMSMsReady[w]
      r += miniMSMsResults[w]

  # Cleanup
  # -------
  miniMSMsResults.freeHeap()
  bucketsMatrix.freeHeap()

# Parallel MSM Affine
# ------------------------------

proc bucketAccumReduce_parallel[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G],
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int)

template wrapperGenAccumulate(miniMsmKind: static MiniMsmKind, c: static int) =
  proc accumulate(
        sched: ptr Scheduler, bitIndex: int,
        coefs: ptr UncheckedArray[BigInt[bits]], N: int): bool {.nimcall.} =
    schedAccumulate(sched[], bitIndex, miniMsmKind, c, coefs, N)
    return true

template wrapperGenAccumReduce(miniMsmKind: untyped, c: static int) =
  proc `accumReduce _ miniMsmKind`(
          tp: Threadpool, windowSum: ptr ECP_ShortW[F, G],
          bitIndex: int, coefs: ptr UncheckedArray[BigInt[bits]],
          points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
          N: int): bool {.nimcall.} =
    bucketAccumReduce_parallel(tp, windowSum[], bitIndex, miniMsmKind, c, coefs, points, N)
    return true

proc bucketAccumReduce_parallel[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G],
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int) =

  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  const outerParallelism = bits div c # It's actually ceilDiv instead of floorDiv, but the last iteration might be too small

  var innerParallelism = 1'i32
  while outerParallelism*innerParallelism < tp.numThreads:
    innerParallelism = innerParallelism shl 1

  let numChunks = 1'i32 # innerParallelism # TODO: unfortunately trying to expose more parallelism slows down the performance
  let chunkSize = int32(numBuckets) shr log2_vartime(cast[uint32](numChunks)) # Both are power of 2 so exact division
  let chunksReadiness = allocStackArray(FlowVar[bool], numChunks-1)           # Last chunk is done on this thread

  let buckets = allocHeap(Buckets[numBuckets, F, G])
  let scheds = allocHeapArray(Scheduler[numBuckets, queueLen, F, G], numChunks)

  buckets[].init()

  wrapperGenAccumulate(miniMsmKind, c)

  block: # 1. Bucket Accumulation
    for chunkID in 0'i32 ..< numChunks-1:
      let idx = chunkID*chunkSize
      scheds[chunkID].init(points, buckets, idx, idx+chunkSize)
      chunksReadiness[chunkID] = tp.spawn accumulate(scheds[chunkID].addr, bitIndex, coefs, N)
    # Last bucket is done sync on this thread
    scheds[numChunks-1].init(points, buckets, (numChunks-1)*chunkSize, int32 numBuckets)
    scheds[numChunks-1].schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  block: # 2. Bucket reduction
    var windowSum{.noInit.}: ECP_ShortW_JacExt[F, G]
    var accumBuckets{.noinit.}: ECP_ShortW_JacExt[F, G]

    if kAffine in buckets.status[numBuckets-1]:
      if kJacExt in buckets.status[numBuckets-1]:
        accumBuckets.madd_vartime(buckets.ptJacExt[numBuckets-1], buckets.ptAff[numBuckets-1])
      else:
        accumBuckets.fromAffine(buckets.ptAff[numBuckets-1])
    elif kJacExt in buckets.status[numBuckets-1]:
      accumBuckets = buckets.ptJacExt[numBuckets-1]
    else:
      accumBuckets.setInf()
    windowSum = accumBuckets
    buckets[].reset(numBuckets-1)

    var nextBatch = numBuckets-1-chunkSize
    var nextFutureIdx = numChunks-2

    for k in countdown(numBuckets-2, 0):
      if k == nextBatch:
        discard sync(chunksReadiness[nextFutureIdx])
        nextBatch -= chunkSize
        nextFutureIdx -= 1

      if kAffine in buckets.status[k]:
        if kJacExt in buckets.status[k]:
          var t{.noInit.}: ECP_ShortW_JacExt[F, G]
          t.madd_vartime(buckets.ptJacExt[k], buckets.ptAff[k])
          accumBuckets += t
        else:
          accumBuckets += buckets.ptAff[k]
      elif kJacExt in buckets.status[k]:
        accumBuckets += buckets.ptJacExt[k]

      buckets[].reset(k)
      windowSum += accumBuckets

    r.fromJacobianExtended_vartime(windowSum)

  # Cleanup
  # ----------------
  scheds.freeHeap()
  buckets.freeHeap()

proc msmAffine_vartime_parallel*[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  type EC = typeof(r)
  let miniMSMsResults = allocHeapArray(EC, numFullWindows)
  let miniMSMsReady   = allocStackArray(Flowvar[bool], numFullWindows)

  wrapperGenAccumReduce(kFullWindow, c)
  wrapperGenAccumReduce(kBottomWindow, c)

  # Algorithm
  # ---------

  block: # 1. Bucket accumulation and reduction
    miniMSMsReady[0] = tp.spawn accumReduce_kBottomWindow(
                                  tp, miniMSMsResults[0].addr,
                                  bitIndex = 0, coefs, points, N)

  for w in 1 ..< numFullWindows:
    miniMSMsReady[w] = tp.spawn accumReduce_kFullWindow(
                                  tp, miniMSMsResults[w].addr,
                                  bitIndex = w*c, coefs, points, N)

  # Last window is done sync on this thread, directly initializing r
  const excess = bits mod c
  const top = bits-excess

  when top != 0:
    when excess != 0:
      let buckets = allocHeapArray(ECP_ShortW_JacExt[F, G], numBuckets)
      zeroMem(buckets[0].addr, sizeof(ECP_ShortW_JacExt[F, G]) * numBuckets)
      r.bucketAccumReduce_jacext(buckets, bitIndex = top, kTopWindow, c,
                                coefs, points, N)
      buckets.freeHeap()
    else:
      r.setInf()

  # 3. Final reduction, r initialized to what would be miniMSMsReady[numWindows-1]
  when excess != 0:
    for w in countdown(numWindows-2, 0):
      for _ in 0 ..< c:
        r.double()
      discard sync miniMSMsReady[w]
      r += miniMSMsResults[w]
  elif numWindows >= 2:
    discard sync miniMSMsReady[numWindows-2]
    r = miniMSMsResults[numWindows-2]
    for w in countdown(numWindows-3, 0):
      for _ in 0 ..< c:
        r.double()
      discard sync miniMSMsReady[w]
      r += miniMSMsResults[w]

  # Cleanup
  # -------
  miniMSMsResults.freeHeap()

proc applyEndomorphism_parallel[bits: static int, F, G](
       tp: Threadpool,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int): auto =
  ## Decompose (coefs, points) into mini-scalars
  ## Returns a new triplet (endoCoefs, endoPoints, N)
  ## endoCoefs and endoPoints MUST be freed afterwards

  const M = when F is Fp:  2
            elif F is Fp2: 4
            else: {.error: "Unconfigured".}

  const L = bits.ceilDiv_vartime(M) + 1
  let splitCoefs   = allocHeapArray(array[M, BigInt[L]], N)
  let endoBasis    = allocHeapArray(array[M, ECP_ShortW_Aff[F, G]], N)

  tp.parallelFor i in 0 ..< N:
    captures: {coefs, points, splitCoefs, endoBasis}

    var negatePoints {.noinit.}: array[M, SecretBool]
    splitCoefs[i].decomposeEndo(negatePoints, coefs[i], F)
    if negatePoints[0].bool:
      endoBasis[i][0].neg(points[i])
    else:
      endoBasis[i][0] = points[i]

    when F is Fp:
      endoBasis[i][1].x.prod(points[i].x, F.C.getCubicRootOfUnity_mod_p())
      if negatePoints[1].bool:
        endoBasis[i][1].y.neg(points[i].y)
      else:
        endoBasis[i][1].y = points[i].y
    else:
      staticFor m, 1, M:
        endoBasis[i][m].frobenius_psi(points[i], m)
        if negatePoints[m].bool:
          endoBasis[i][m].neg()

  tp.syncAll()

  let endoCoefs = cast[ptr UncheckedArray[BigInt[L]]](splitCoefs)
  let endoPoints  = cast[ptr UncheckedArray[ECP_ShortW_Aff[F, G]]](endoBasis)

  return (endoCoefs, endoPoints, M*N)

template withEndo[bits: static int, F, G](
           msmProc: untyped,
           tp: Threadpool,
           r: var ECP_ShortW[F, G],
           coefs: ptr UncheckedArray[BigInt[bits]],
           points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
           N: int, c: static int) =
  when bits <= F.C.getCurveOrderBitwidth() and hasEndomorphismAcceleration(F.C):
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism_parallel(tp, coefs, points, N)
    msmProc(tp, r, endoCoefs, endoPoints, endoN, c)
    freeHeap(endoCoefs)
    freeHeap(endoPoints)
  else:
    msmProc(tp, r, coefs, points, N, c)

proc multiScalarMul_dispatch_vartime_parallel[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G], coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  case c
  of  2: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  2)
  of  3: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  3)
  of  4: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  4)
  of  5: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  5)
  of  6: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  6)
  of  7: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  7)
  of  8: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  8)
  of  9: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  9)
  of 10: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c = 10)
  of 11: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 11)
  of 12: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 12)
  of 13: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 13)
  of 14: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 14)
  of 15: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 15)
  of 16: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 16)
  of 17: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 17)
  of 18: msmAffine_vartime_parallel(tp, r, coefs, points, N, c = 18)
  else:
    unreachable()

proc multiScalarMul_vartime_parallel*[bits: static int, F, G](
       tp: Threadpool,
       r: var ECP_ShortW[F, G],
       coefs: openArray[BigInt[bits]],
       points: openArray[ECP_ShortW_Aff[F, G]]) {.meter, inline.} =

  debug: doAssert coefs.len == points.len
  let N = points.len

  tp.multiScalarMul_dispatch_vartime_parallel(r, coefs.asUnchecked(), points.asUnchecked(), N)