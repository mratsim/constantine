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
       ../../threadpool/[threadpool, partitioners]
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
# There are 3 parallelism opportunities:
# - 0.a MiniMSMs accumulation a.k.a "window-level paralllism"
#       is straightforward as there are no data dependencies at all.
# - 1.a Buckets accumulation a.k.a "bucket-level parallelism".
#       Buckets needs to be parallelized over buckets and not points to avoid synchronization between threads.
#       The disadvantage is that all threads scan all the points.
# - and doing separate MSMs over part of the points, a.k.a "msm-level parallelism".
#   As the number of points grows, the cost of scalar-mul per point diminishes at the rate O(n/log n) as we can increase the window size `c`
#   to reduce the number of operations. However when `c` reaches 16, memory bandwidth becomes another bottleneck
#   hence parallelizing at this level becomes interesting.
#
# We can also parallelize the reductions but they would require extra doublings to "place the reduction" at the right bits.
# Example:
#   let's say we compute the binary number 0b11010110
#   Each 1 is add+double, each 0 is just double.
#   We can split the computation in parallel 0b1101 << 4 and 0b0110
#   but now we need 4 extra doublings to shift the high part in the correct place.
# Alternatively we can do "latency hiding", we start the computation before all results are available, and wait for the next part to finish.
#
# Now, with a small c, say 1024 inputs, c=9, the window-level parallelism is large: 14 to 28 for 128-bit to 256-bit coefs.
# For large c, say 262k inputs, c=16, the window-level parallelism is small:         8 to 16 for 128-bit to 256-bit coefs.
#
# Zero Knowledge protocols need to operate on millions of points, so we want to fully occupy high-end CPUs
# - AMD EPYC 9654 96C/192T on 2 sockets hence 384 threads
# - Intel Xeon Platinum 8490H 60C/120T on 8 sockets hence 960 threads
#
# Bucket-level parallism has a multiplicative factor on parallelism exposed
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
# Lastly we can go further on latency hiding for the bucket-level parallelism,
# having decreasing range sizes so that the top ranges are ready earlier for interleaving reduction.

# Parallel MSM Jacobian Extended
# ------------------------------

proc bucketAccumReduce_jacext_zeroMem[EC, F, G; bits: static int](
       windowSum: ptr EC,
       buckets: ptr ECP_ShortW_JacExt[F, G] or ptr UncheckedArray[ECP_ShortW_JacExt[F, G]],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) =
  const numBuckets = 1 shl (c-1)
  let buckets = cast[ptr UncheckedArray[ECP_ShortW_JacExt[F, G]]](buckets)
  zeroMem(buckets, sizeof(ECP_ShortW_JacExt[F, G]) * numBuckets)
  bucketAccumReduce_jacext(windowSum[], buckets, bitIndex, miniMsmKind, c, coefs, points, N)

proc msmJacExt_vartime_parallel*[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC,
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
  let miniMSMsResults = allocHeapArray(EC, numFullWindows)
  let miniMSMsReady   = allocStackArray(FlowVar[bool], numFullWindows)

  let bucketsMatrix = allocHeapArray(ECP_ShortW_JacExt[F, G], numBuckets*numWindows)

  # Algorithm
  # ---------

  block: # 1. Bucket accumulation and reduction
    miniMSMsReady[0] = tp.spawnAwaitable bucketAccumReduce_jacext_zeroMem(
                                  miniMSMsResults[0].addr,
                                  bucketsMatrix[0].addr,
                                  bitIndex = 0, kBottomWindow, c,
                                  coefs, points, N)

  for w in 1 ..< numFullWindows:
    miniMSMsReady[w] = tp.spawnAwaitable bucketAccumReduce_jacext_zeroMem(
                                  miniMSMsResults[w].addr,
                                  bucketsMatrix[w*numBuckets].addr,
                                  bitIndex = w*c, kFullWindow, c,
                                  coefs, points, N)

  # Last window is done sync on this thread, directly initializing r
  const excess = bits mod c
  const top = bits-excess

  when top != 0:
    when excess != 0:
      bucketAccumReduce_jacext_zeroMem(
        r,
        bucketsMatrix[numFullWindows*numBuckets].addr,
        bitIndex = top, kTopWindow, c,
        coefs, points, N)
    else:
      r[].setInf()

  # 3. Final reduction, r initialized to what would be miniMSMsReady[numWindows-1]
  when excess != 0:
    for w in countdown(numWindows-2, 0):
      for _ in 0 ..< c:
        r[].double()
      discard sync miniMSMsReady[w]
      r[].sum_vartime(r[], miniMSMsResults[w])
  elif numWindows >= 2:
    discard sync miniMSMsReady[numWindows-2]
    r[] = miniMSMsResults[numWindows-2]
    for w in countdown(numWindows-3, 0):
      for _ in 0 ..< c:
        r[].double()
      discard sync miniMSMsReady[w]
      r[].sum_vartime(r[], miniMSMsResults[w])

  # Cleanup
  # -------
  miniMSMsResults.freeHeap()
  bucketsMatrix.freeHeap()

# Parallel MSM Affine - bucket accumulation
# -----------------------------------------
proc bucketAccumReduce_serial[bits: static int, EC, F, G](
       r: ptr EC,
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int) =

  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  let buckets = allocHeap(Buckets[numBuckets, F, G])
  let sched = allocHeap(Scheduler[numBuckets, queueLen, F, G])
  sched.init(points, buckets, 0, numBuckets.int32)

  # 1. Bucket Accumulation
  sched.schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  # 2. Bucket Reduction
  var windowSum{.noInit.}: ECP_ShortW_JacExt[F, G]
  windowSum.bucketReduce(sched.buckets)
  r[].fromJacobianExtended_vartime(windowSum)

  # Cleanup
  # ----------------
  sched.freeHeap()
  buckets.freeHeap()

proc bucketAccumReduce_parallel[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC,
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int) =

  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  const windowParallelism = bits div c # It's actually ceilDiv instead of floorDiv, but the last iteration might be too small

  var bucketParallelism = 1'i32
  while windowParallelism*bucketParallelism < tp.numThreads:
    bucketParallelism = bucketParallelism shl 1

  let numChunks = bucketParallelism
  let chunkSize = int32(numBuckets) shr log2_vartime(cast[uint32](numChunks)) # Both are power of 2 so exact division
  let chunksReadiness = allocStackArray(FlowVar[bool], numChunks-1)           # Last chunk is done on this thread

  let buckets = allocHeap(Buckets[numBuckets, F, G])
  let scheds = allocHeapArray(Scheduler[numBuckets, queueLen, F, G], numChunks)

  block: # 1. Bucket Accumulation
    for chunkID in 0'i32 ..< numChunks-1:
      let idx = chunkID*chunkSize
      scheds[chunkID].addr.init(points, buckets, idx, idx+chunkSize)
      chunksReadiness[chunkID] = tp.spawnAwaitable schedAccumulate(scheds[chunkID].addr, bitIndex, miniMsmKind, c, coefs, N)
    # Last bucket is done sync on this thread
    scheds[numChunks-1].addr.init(points, buckets, (numChunks-1)*chunkSize, int32 numBuckets)
    scheds[numChunks-1].addr.schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  block: # 2. Bucket reduction with latency hiding
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
    buckets.reset(numBuckets-1)

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

      buckets.reset(k)
      windowSum += accumBuckets

    r[].fromJacobianExtended_vartime(windowSum)

  # Cleanup
  # ----------------
  scheds.freeHeap()
  buckets.freeHeap()

# Parallel MSM Affine - window-level only
# ---------------------------------------

proc msmAffine_vartime_parallel*[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int, useParallelBuckets: static bool) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  type EC = typeof(r[])
  let miniMSMsResults = allocHeapArray(EC, numFullWindows)
  let miniMSMsReady   = allocStackArray(Flowvar[bool], numFullWindows)

  # Algorithm
  # ---------

  # 1. mini-MSMs: Bucket accumulation and reduction
  when useParallelBuckets:
    miniMSMsReady[0] = tp.spawnAwaitable bucketAccumReduce_parallel(
                                    tp, miniMSMsResults[0].addr,
                                    bitIndex = 0, kBottomWindow, c,
                                    coefs, points, N)

    for w in 1 ..< numFullWindows:
      miniMSMsReady[w] = tp.spawnAwaitable bucketAccumReduce_parallel(
                                    tp, miniMSMsResults[w].addr,
                                    bitIndex = w*c, kFullWindow, c,
                                    coefs, points, N)
  else:
    miniMSMsReady[0] = tp.spawnAwaitable bucketAccumReduce_serial(
                                    miniMSMsResults[0].addr,
                                    bitIndex = 0, kBottomWindow, c,
                                    coefs, points, N)

    for w in 1 ..< numFullWindows:
      miniMSMsReady[w] = tp.spawnAwaitable bucketAccumReduce_serial(
                                    miniMSMsResults[w].addr,
                                    bitIndex = w*c, kFullWindow, c,
                                    coefs, points, N)

  # Last window is done sync on this thread, directly initializing r
  const excess = bits mod c
  const top = bits-excess

  when top != 0:
    when excess != 0:
      let buckets = allocHeapArray(ECP_ShortW_JacExt[F, G], numBuckets)
      zeroMem(buckets[0].addr, sizeof(ECP_ShortW_JacExt[F, G]) * numBuckets)
      r[].bucketAccumReduce_jacext(buckets, bitIndex = top, kTopWindow, c,
                                coefs, points, N)
      buckets.freeHeap()
    else:
      r[].setInf()

  # 2. Final reduction with latency hiding, r initialized to what would be miniMSMsReady[numWindows-1]
  when excess != 0:
    for w in countdown(numWindows-2, 0):
      for _ in 0 ..< c:
        r[].double()
      discard sync miniMSMsReady[w]
      r[].sum_vartime(r[], miniMSMsResults[w])
  elif numWindows >= 2:
    discard sync miniMSMsReady[numWindows-2]
    r[] = miniMSMsResults[numWindows-2]
    for w in countdown(numWindows-3, 0):
      for _ in 0 ..< c:
        r[].double()
      discard sync miniMSMsReady[w]
      r[].sum_vartime(r[], miniMSMsResults[w])

  # Cleanup
  # -------
  miniMSMsResults.freeHeap()

proc msmAffine_vartime_parallel_split[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int, useParallelBuckets: static bool) =

  # Parallelism levels:
  # - MSM parallelism:   compute independent MSMs, this increases the number of total ops
  # - window parallelism: compute a MSM outer loop on different threads, this has no tradeoffs
  # - bucket parallelism: handle range of buckets on different threads, threads do superfluous overlapping memory reads
  #
  # It seems to be beneficial to have both MSM and bucket level parallelism.
  # Probably by guaranteeing 2x more tasks than threads, we avoid starvation.

  var windowParallelism = bits div c # It's actually ceilDiv instead of floorDiv, but the last iteration might be too small
  var msmParallelism = 1'i32

  while windowParallelism*msmParallelism < tp.numThreads:
    windowParallelism = bits div c     # This is an approximation
    msmParallelism = msmParallelism shl 1

  if msmParallelism == 1:
    msmAffine_vartime_parallel(tp, r, coefs, points, N, c, useParallelBuckets)
    return

  let chunkingDescriptor = balancedChunksPrioNumber(0, N, msmParallelism)
  let splitMSMsResults = allocHeapArray(typeof(r[]), msmParallelism-1)
  let splitMSMsReady   = allocStackArray(Flowvar[bool], msmParallelism-1)

  for (i, start, len) in items(chunkingDescriptor):
    if i != msmParallelism-1:
      splitMSMsReady[i] = tp.spawnAwaitable msmAffine_vartime_parallel(
                               tp, splitMSMsResults[i].addr,
                               coefs +% start, points +% start, len,
                               c, useParallelBuckets)
    else: # Run last on this thread
      msmAffine_vartime_parallel(
        tp, r,
        coefs +% start, points +% start, len,
        c, useParallelBuckets)

  for i in countdown(msmParallelism-2, 0):
    discard sync splitMSMsReady[i]
    r[].sum_vartime(r[], splitMSMsResults[i])

  freeHeap(splitMSMsResults)

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

  syncScope:
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

  let endoCoefs = cast[ptr UncheckedArray[BigInt[L]]](splitCoefs)
  let endoPoints  = cast[ptr UncheckedArray[ECP_ShortW_Aff[F, G]]](endoBasis)

  return (endoCoefs, endoPoints, M*N)

template withEndo[bits: static int, EC, F, G](
           msmProc: untyped,
           tp: Threadpool,
           r: ptr EC,
           coefs: ptr UncheckedArray[BigInt[bits]],
           points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
           N: int, c: static int) =
  when bits <= F.C.getCurveOrderBitwidth() and hasEndomorphismAcceleration(F.C):
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism_parallel(tp, coefs, points, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # but it has no significant impact on performance
    msmProc(tp, r, endoCoefs, endoPoints, endoN, c)
    freeHeap(endoCoefs)
    freeHeap(endoPoints)
  else:
    msmProc(tp, r, coefs, points, N, c)

template withEndo[bits: static int, EC, F, G](
           msmProc: untyped,
           tp: Threadpool,
           r: ptr EC,
           coefs: ptr UncheckedArray[BigInt[bits]],
           points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
           N: int, c: static int, useParallelBuckets: static bool) =
  when bits <= F.C.getCurveOrderBitwidth() and hasEndomorphismAcceleration(F.C):
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism_parallel(tp, coefs, points, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # but it has no significant impact on performance
    msmProc(tp, r, endoCoefs, endoPoints, endoN, c, useParallelBuckets)
    freeHeap(endoCoefs)
    freeHeap(endoPoints)
  else:
    msmProc(tp, r, coefs, points, N, c, useParallelBuckets)

proc multiScalarMul_dispatch_vartime_parallel[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC, coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # but it has no significant impact on performance

  case c
  of  2: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  2)
  of  3: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  3)
  of  4: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  4)
  of  5: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  5)
  of  6: withEndo(msmJacExt_vartime_parallel, tp, r, coefs, points, N, c =  6)

  of  7: msmJacExt_vartime_parallel(tp, r, coefs, points, N, c =  7)
  of  8: msmJacExt_vartime_parallel(tp, r, coefs, points, N, c =  8)

  of  9: withEndo(msmAffine_vartime_parallel_split, tp, r, coefs, points, N, c =  9, useParallelBuckets = true)
  of 10: withEndo(msmAffine_vartime_parallel_split, tp, r, coefs, points, N, c = 10, useParallelBuckets = true)

  of 11: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 10, useParallelBuckets = true)
  of 12: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 11, useParallelBuckets = true)
  of 13: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 12, useParallelBuckets = true)
  of 14: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 13, useParallelBuckets = true)
  of 15: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 14, useParallelBuckets = true)
  of 16: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 15, useParallelBuckets = true)
  of 17: msmAffine_vartime_parallel_split(tp, r, coefs, points, N, c = 16, useParallelBuckets = true)
  else:
    unreachable()

proc multiScalarMul_vartime_parallel*[bits: static int, EC, F, G](
       tp: Threadpool,
       r: var EC,
       coefs: openArray[BigInt[bits]],
       points: openArray[ECP_ShortW_Aff[F, G]]) {.meter, inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  ## This function can be nested in another parallel function
  debug: doAssert coefs.len == points.len
  let N = points.len

  tp.multiScalarMul_dispatch_vartime_parallel(r.addr, coefs.asUnchecked(), points.asUnchecked(), N)

proc multiScalarMul_vartime_parallel*[bits: static int, EC, F, G](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       len: int) {.meter, inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  ## This function can be nested in another parallel function
  tp.multiScalarMul_dispatch_vartime_parallel(r, coefs, points, len)
