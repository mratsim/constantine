# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/named/algebras,
       ./ec_multi_scalar_mul_scheduler,
       ./ec_multi_scalar_mul,
       constantine/math/endomorphisms/split_scalars,
       constantine/math/extension_fields,
       constantine/named/zoo_endomorphisms,
       constantine/threadpool/[threadpool, partitioners]
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

# Parallel MSM non-affine
# ------------------------------

proc bucketAccumReduce_withInit[bits: static int, EC, ECaff](
       windowSum: ptr EC,
       buckets: ptr EC or ptr UncheckedArray[EC],
       bitIndex: int, miniMsmKind: static MiniMsmKind, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff], N: int) =
  const numBuckets = 1 shl (c-1)
  let buckets = cast[ptr UncheckedArray[EC]](buckets)
  for i in 0 ..< numBuckets:
    buckets[i].setNeutral()
  bucketAccumReduce(windowSum[], buckets, bitIndex, miniMsmKind, c, coefs, points, N)

proc msmImpl_vartime_parallel[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[EC_aff],
       N: int, c: static int) =

  # Prologue
  # --------
  const numBuckets = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  let miniMSMsResults = allocHeapArrayAligned(EC, numFullWindows, alignment = 64)
  let miniMSMsReady   = allocStackArray(FlowVar[bool], numFullWindows)

  let bucketsMatrix = allocHeapArrayAligned(EC, numBuckets*numWindows, alignment = 64)

  # Algorithm
  # ---------

  block: # 1. Bucket accumulation and reduction
    miniMSMsReady[0] = tp.spawnAwaitable bucketAccumReduce_withInit(
                                  miniMSMsResults[0].addr,
                                  bucketsMatrix[0].addr,
                                  bitIndex = 0, kBottomWindow, c,
                                  coefs, points, N)

  for w in 1 ..< numFullWindows:
    miniMSMsReady[w] = tp.spawnAwaitable bucketAccumReduce_withInit(
                                  miniMSMsResults[w].addr,
                                  bucketsMatrix[w*numBuckets].addr,
                                  bitIndex = w*c, kFullWindow, c,
                                  coefs, points, N)

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
    coefs, points, N)

  # 3. Final reduction
  for w in countdown(numFullWindows-1, 0):
    for _ in 0 ..< c:
      r[].double()
    discard sync miniMSMsReady[w]
    r[] ~+= miniMSMsResults[w]

  # Cleanup
  # -------
  miniMSMsResults.freeHeapAligned()
  bucketsMatrix.freeHeapAligned()

# Parallel MSM Affine - bucket accumulation
# -----------------------------------------
proc bucketAccumReduce_serial[bits: static int, EC, ECaff](
       r: ptr EC,
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       N: int) =

  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  let buckets = allocHeapAligned(Buckets[numBuckets, EC, ECaff], alignment = 64)
  let sched = allocHeapAligned(Scheduler[numBuckets, queueLen, EC, ECaff], alignment = 64)
  sched.init(points, buckets, 0, numBuckets.int32)

  # 1. Bucket Accumulation
  sched.schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  # 2. Bucket Reduction
  r.bucketReduce(sched.buckets)

  # Cleanup
  # ----------------
  sched.freeHeapAligned()
  buckets.freeHeapAligned()

proc bucketAccumReduce_parallel[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       bitIndex: int,
       miniMsmKind: static MiniMsmKind,  c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       N: int) =

  const (numBuckets, queueLen) = c.deriveSchedulerConstants()
  const windowParallelism = bits div c # It's actually ceilDiv instead of floorDiv, but the last iteration might be too small

  var bucketParallelism = 1'i32
  while windowParallelism*bucketParallelism < tp.numThreads:
    bucketParallelism = bucketParallelism shl 1

  let numChunks = bucketParallelism
  let chunkSize = int32(numBuckets) shr log2_vartime(cast[uint32](numChunks)) # Both are power of 2 so exact division
  let chunksReadiness = allocStackArray(FlowVar[bool], numChunks-1)           # Last chunk is done on this thread

  let buckets = allocHeapAligned(Buckets[numBuckets, EC, ECaff], alignment = 64)
  let scheds = allocHeapArrayAligned(Scheduler[numBuckets, queueLen, EC, ECaff], numChunks, alignment = 64)

  block: # 1. Bucket Accumulation
    for chunkID in 0'i32 ..< numChunks-1:
      let idx = chunkID*chunkSize
      scheds[chunkID].addr.init(points, buckets, idx, idx+chunkSize)
      chunksReadiness[chunkID] = tp.spawnAwaitable schedAccumulate(scheds[chunkID].addr, bitIndex, miniMsmKind, c, coefs, N)
    # Last bucket is done sync on this thread
    scheds[numChunks-1].addr.init(points, buckets, (numChunks-1)*chunkSize, int32 numBuckets)
    scheds[numChunks-1].addr.schedAccumulate(bitIndex, miniMsmKind, c, coefs, N)

  block: # 2. Bucket reduction with latency hiding
    var windowSum{.noInit.}: EC
    var accumBuckets{.noinit.}: EC

    if kAffine in buckets.status[numBuckets-1]:
      if kNonAffine in buckets.status[numBuckets-1]:
        accumBuckets.mixedSum_vartime(buckets.pt[numBuckets-1], buckets.ptAff[numBuckets-1])
      else:
        accumBuckets.fromAffine(buckets.ptAff[numBuckets-1])
    elif kNonAffine in buckets.status[numBuckets-1]:
      accumBuckets = buckets.pt[numBuckets-1]
    else:
      accumBuckets.setNeutral()
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
        if kNonAffine in buckets.status[k]:
          var t{.noInit.}: EC
          t.mixedSum_vartime(buckets.pt[k], buckets.ptAff[k])
          accumBuckets ~+= t
        else:
          accumBuckets ~+= buckets.ptAff[k]
      elif kNonAffine in buckets.status[k]:
        accumBuckets ~+= buckets.pt[k]

      buckets.reset(k)
      windowSum ~+= accumBuckets

    r[] = windowSum

  # Cleanup
  # ----------------
  scheds.freeHeapAligned()
  buckets.freeHeapAligned()

# Parallel MSM Affine - window-level only
# ---------------------------------------

proc msmAffine_vartime_parallel[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff],
       N: int, c: static int, useParallelBuckets: static bool) =

  # Prologue
  # --------
  const numBuckets {.used.} = 1 shl (c-1)
  const numFullWindows = bits div c
  const numWindows = numFullWindows + 1 # Even if `bits div c` is exact, the signed recoding needs to see an extra 0 after the MSB

  # Instead of storing the result in futures, risking them being scattered in memory
  # we store them in a contiguous array, and the synchronizing future just returns a bool.
  # top window is done on this thread
  let miniMSMsResults = allocHeapArrayAligned(EC, numFullWindows, alignment = 64)
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
  const msmKind = if top == 0: kBottomWindow
                  elif excess == 0: kFullWindow
                  else: kTopWindow

  let buckets = allocHeapArrayAligned(EC, numBuckets, alignment = 64)
  bucketAccumReduce_withInit(
    r,
    buckets,
    bitIndex = top, msmKind, c,
    coefs, points, N)
  buckets.freeHeapAligned()

  # 3. Final reduction
  for w in countdown(numFullWindows-1, 0):
    for _ in 0 ..< c:
      r[].double()
    discard sync miniMSMsReady[w]
    r[] ~+= miniMSMsResults[w]

  # Cleanup
  # -------
  miniMSMsResults.freeHeapAligned()

proc msmAffine_vartime_parallel_split[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECaff],
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
  let splitMSMsResults = allocHeapArrayAligned(typeof(r[]), msmParallelism-1, alignment = 64)
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
    r[] ~+= splitMSMsResults[i]

  splitMSMsResults.freeHeapAligned()

proc applyEndomorphism_parallel[bits: static int, ECaff](
       tp: Threadpool,
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

  syncScope:
    tp.parallelFor i in 0 ..< N:
      captures: {coefs, points, splitCoefs, endoBasis}

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
           tp: Threadpool,
           r: ptr EC,
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
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism_parallel(tp, coefs, points, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # but it has no significant impact on performance
    msmProc(tp, r, endoCoefs, endoPoints, endoN, c)
    endoCoefs.freeHeapAligned()
    endoPoints.freeHeapAligned()
  else:
    msmProc(tp, r, coefs, points, N, c)

template withEndo[coefsBits: static int, EC, ECaff](
           msmProc: untyped,
           tp: Threadpool,
           r: ptr EC,
           coefs: ptr UncheckedArray[BigInt[coefsBits]],
           points: ptr UncheckedArray[ECaff],
           N: int, c: static int, useParallelBuckets: static bool) =
  when hasEndomorphismAcceleration(EC.getName()) and
        EndomorphismThreshold <= coefsBits and
        coefsBits <= EC.getScalarField().bits() and
        # computeEndomorphism assumes they can be applied to affine repr
        # but this is not the case for Bandersnatch/wagon
        # instead Twisted Edwards MSM should be overloaded for Projective/ProjectiveExtended
        EC.getName() notin {Bandersnatch, Banderwagon}:
    let (endoCoefs, endoPoints, endoN) = applyEndomorphism_parallel(tp, coefs, points, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # but it has no significant impact on performance
    msmProc(tp, r, endoCoefs, endoPoints, endoN, c, useParallelBuckets)
    endoCoefs.freeHeapAligned()
    endoPoints.freeHeapAligned()
  else:
    msmProc(tp, r, coefs, points, N, c, useParallelBuckets)

proc multiScalarMul_dispatch_vartime_parallel[bits: static int, F, G](
       tp: Threadpool,
       r: ptr (EC_ShortW_Jac[F, G] or EC_ShortW_Prj[F, G]),
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[EC_ShortW_Aff[F, G]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # but it has no significant impact on performance

  case c
  of  2: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  2)
  of  3: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  3)
  of  4: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  4)
  of  5: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  5)
  of  6: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  6)

  of  7: msmImpl_vartime_parallel(tp, r, coefs, points, N, c =  7)
  of  8: msmImpl_vartime_parallel(tp, r, coefs, points, N, c =  8)

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

proc multiScalarMul_dispatch_vartime_parallel[bits: static int, F](
       tp: Threadpool,
       r: ptr EC_TwEdw_Prj[F], coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[EC_TwEdw_Aff[F]], N: int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = true, useManualTuning = true)

  # Given that bits and N change after applying an endomorphism,
  # we are able to use a bigger `c`
  # but it has no significant impact on performance

  case c
  of  2: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  2)
  of  3: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  3)
  of  4: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  4)
  of  5: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  5)
  of  6: withEndo(msmImpl_vartime_parallel, tp, r, coefs, points, N, c =  6)

  of   7: msmImpl_vartime_parallel(tp, r, coefs, points, N, c =  7)
  of   8: msmImpl_vartime_parallel(tp, r, coefs, points, N, c =  8)
  of   9: msmImpl_vartime_parallel(tp, r, coefs, points, N, c =  9)
  of  10: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 10)
  of  11: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 11)
  of  12: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 12)
  of  13: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 13)
  of  14: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 14)
  of  15: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 16)

  of  16..17: msmImpl_vartime_parallel(tp, r, coefs, points, N, c = 16)
  else:
    unreachable()

proc multiScalarMul_vartime_parallel*[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[BigInt[bits]],
       points: ptr UncheckedArray[ECaff],
       len: int) {.meter, inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  ## This function can be nested in another parallel function
  tp.multiScalarMul_dispatch_vartime_parallel(r, coefs, points, len)

proc multiScalarMul_vartime_parallel*[bits: static int, EC, ECaff](
       tp: Threadpool,
       r: var EC,
       coefs: openArray[BigInt[bits]],
       points: openArray[ECaff]) {.meter, inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  ## This function can be nested in another parallel function
  debug: doAssert coefs.len == points.len
  let N = points.len
  tp.multiScalarMul_dispatch_vartime_parallel(r.addr, coefs.asUnchecked(), points.asUnchecked(), N)

proc multiScalarMul_vartime_parallel*[F, EC, ECaff](
       tp: Threadpool,
       r: ptr EC,
       coefs: ptr UncheckedArray[F],
       points: ptr UncheckedArray[ECaff],
       len: int) {.meter.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  let n = cast[int](len)
  let coefs_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)

  syncScope:
    tp.parallelFor i in 0 ..< n:
      captures: {coefs, coefs_big}
      coefs_big[i].fromField(coefs[i])
  tp.multiScalarMul_vartime_parallel(r, coefs_big, points, n)

  freeHeapAligned(coefs_big)

proc multiScalarMul_vartime_parallel*[EC, ECaff](
       tp: Threadpool,
       r: var EC,
       coefs: openArray[Fr],
       points: openArray[ECaff]) {.inline.} =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ₋₁]Pₙ₋₁
  debug: doAssert coefs.len == points.len
  let N = points.len
  tp.multiScalarMul_vartime_parallel(r.addr, coefs.asUnchecked(), points.asUnchecked(), N)
