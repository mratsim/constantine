# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../arithmetic,
  ../ec_shortweierstrass,
  ./ec_shortweierstrass_jacobian_extended,
  ./ec_shortweierstrass_batch_ops

export abstractions, arithmetic,
       ec_shortweierstrass, ec_shortweierstrass_jacobian_extended

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ########################################################### #
#                                                             #
#          Multi Scalar Multiplication - Scheduling           #
#                                                             #
# ########################################################### #

# This file implements a bucketing acceleration structure.
#
# See the following for the baseline algorithm:
# - Faster batch forgery identification
#   Daniel J. Bernstein, Jeroen Doumen, Tanja Lange, and Jan-Jaap Oosterwijk, 2012
#   https://eprint.iacr.org/2012/549.pdf
# - Simple guide to fast linear combinations (aka multiexponentiations)
#   Vitalik Buterin, 2020
#   https://ethresear.ch/t/simple-guide-to-fast-linear-combinations-aka-multiexponentiations/7238
#   https://github.com/ethereum/research/blob/5c6fec6/fast_linear_combinations/multicombs.py
# - zkStudyClub: Multi-scalar multiplication: state of the art & new ideas
#   Gus Gutoski, 2020
#   https://www.youtube.com/watch?v=Bl5mQA7UL2I
#
# And for the scheduling technique and collision probability analysis
# - FPGA Acceleration of Multi-Scalar Multiplication: CycloneMSM
#   Kaveh Aasaraai, Don Beaver, Emanuele Cesena, Rahul Maganti, Nicolas Stalder and Javier Varela, 2022
#   https://eprint.iacr.org/2022/1396.pdf
#
# Challenges:
# - For the popular BLS12-377 and BLS12-381, an affine elliptic point takes 96 bytes
#   an extended jacobian point takes 192 bytes.
# - We want to deal with a large number of points, for example the Zprize competition used 2²⁶ ~= 67M points
#   in particular, memory usage is a concern as those input already require ~6.7GB for a BLS12 prime,
#   so we can't use much scratchspace, especially on GPUs.
# - Any bit-twiddling algorithm must scale at most linearly with the number of points
#   Algorithm that for example finds the most common pair of points for an optimized addition chain
#   are O(n²) and will need to select from a subsample.
# - The scalars are random, so the bucket accessed is random, which needs sorting or prefetching
#   to avoid bottlenecking on memory bandwidth. But sorting requires copies ...
# - While copies improve locality, our types are huge, 96~192 bytes
#   and we have millions of them.
# - We want our algorithm to be scalable to a large number of threads at minimum, or even better on GPUs.
#   Hence it should naturally offer data parallelism, which is tricky due to collisions when accumulating
#   1M points into 32~64K buckets.
# - The asymptotically fastest addition formulae are affine addition with individual cost 3M + 1I
#   and asymptotic cost for N points N*3M + N*3M+1I using batch inversion.
#   Vartime inversion cost 70-100M depending on the number of bits in the prime
#   (multiplication cost scale quadratically while inversion via Euclid linearly)
# - The second fastest general coordinate system is Extended Jacobian with cost 10M,
#   so the threshold for N is:
#     N*3M+N*3M+100M < N*10M <=> 100M < N * 4M <=> 25 < N
#   Hence we want to maximize the chance of doing 25 additions (so we need 50 points).
#   Given than there is low probability for consecutive random points to be assigned to the same bucket,
#   we can't keep a queue per bucket for batch accumulation.
#   However we can do a vector addition as there is a high probability that consecutive random points
#   are assigned to different buckets.
#
# Strategy:
# - Each bucket is associated with (EC Affine, EC ExtJac, set[Empty, AffineSet, ExtJacSet]), in SoA storage
# - Each thread is assigned a range of buckets and keeps a scheduler
#     start, stop: int32
#     curQueue, curRescheduled: int32
#     bucketMap:                BigInt[NumNZBuckets]
#     queue:                    array[MaxCapacity, (Target Bucket, PointID)]
#     rescheduled:              array[32, (Target Bucket, PointID)]
#   - when the queue reaches max capacity, we compute a vector affine addition with the target buckets
#     we interleave with prefetching to reduce cache misses.
#   - when the rescheduled array reaches max capacity, we check if there are at least 32 items in the queue
#     and if so schedule an vector addition otherwise we flush the queue into the EC ExtJac.
#     i.e. in the worst case, when all points are the same, we fallback to the JacExt MSM.
#   - As a stretch optimization, if many points in rescheduled queue target the same bucket
#     we can use sum_reduce_vartime, but are there workloads like that?
#
# Queue size is given by formula `4*c² - 16*c - 128` to handle various concerns: amortization of batch affine, memory usage, collision probability
# `c` is chosen to minimize the number of EC operations but does not take into account memory bandwidth and cache misses cost.
#
# Collision probability for `QueueSize` consecutive *uniformly random* points
# is derived from a Poisson distribution.
# NumCollisions = N*QueueSize/NumNZBuckets is the number of collisions
# NumCollisions / N is the probability of collision

# -------inputs-------    c      ----buckets----   queue length  collision map bytes  num collisions   collision %
#  2^0               1    2      2^1           2           -144                    8             -72      -7200.0%
#  2^1               2    2      2^1           2           -144                    8            -144      -7200.0%
#  2^2               4    3      2^2           4           -140                    8            -140      -3500.0%
#  2^3               8    3      2^2           4           -140                    8            -280      -3500.0%
#  2^4              16    4      2^3           8           -128                    8            -256      -1600.0%
#  2^5              32    5      2^4          16           -108                    8            -216       -675.0%
#  2^6              64    5      2^4          16           -108                    8            -432       -675.0%
#  2^7             128    6      2^5          32            -80                    8            -320       -250.0%
#  2^8             256    7      2^6          64            -44                    8            -176        -68.8%
#  2^9             512    8      2^7         128              0                   16               0          0.0%
# 2^10            1024    9      2^8         256             52                   32             208         20.3% <- At half the queue length, we can still amortize batch inversion
# 2^11            2048    9      2^8         256             52                   32             416         20.3%
# 2^12            4096   10      2^9         512            112                   64             896         21.9%
# 2^13            8192   11     2^10        1024            180                  128            1440         17.6%
# 2^14           16384   12     2^11        2048            256                  256            2048         12.5%
# 2^15           32768   13     2^12        4096            340                  512            2720          8.3%
# 2^16           65536   14     2^13        8192            432                 1024            3456          5.3%
# 2^17          131072   15     2^14       16384            532                 2048            4256          3.2% <- 100/32 = 3.125, a collision queue of size 32 is highly unlikely to reach full capacity
# 2^18          262144   16     2^15       32768            640                 4096            5120          2.0% <- ~10MB of buckets
# 2^19          524288   17     2^16       65536            756                 8192            6048          1.2% <- for BLS12-381, the queue size reaches 64K aliasing conflict threshold
# 2^20         1048576   17     2^16       65536            756                 8192           12096          1.2%
# 2^21         2097152   18     2^17      131072            880                16384           14080          0.7%
# 2^22         4194304   19     2^18      262144           1012                32768           16192          0.4%
# 2^23         8388608   20     2^19      524288           1152                65536           18432          0.2%
# 2^24        16777216   21     2^20     1048576           1300               131072           20800          0.1%
# 2^25        33554432   22     2^21     2097152           1456               262144           23296          0.1%
# 2^26        67108864   23     2^22     4194304           1620               524288           25920          0.0%
# 2^27       134217728   24     2^23     8388608           1792              1048576           28672          0.0%
# 2^28       268435456   25     2^24    16777216           1972              2097152           31552          0.0%
# 2^29       536870912   26     2^25    33554432           2160              4194304           34560          0.0%
# 2^30      1073741824   27     2^26    67108864           2356              8388608           37696          0.0%
# 2^31      2147483648   28     2^27   134217728           2560             16777216           40960          0.0%
# 2^32      4294967296   29     2^28   268435456           2772             33554432           44352          0.0%
# 2^33      8589934592   30     2^29   536870912           2992             67108864           47872          0.0%
# 2^34     17179869184   31     2^30  1073741824           3220            134217728           51520          0.0%
# 2^35     34359738368   32     2^31  2147483648           3456            268435456           55296          0.0%
#
# The code to reproduce this table is at the bottom

# Sizes for BLS12-381 with c = 16
#
# Buckets: 32768
# - Status:             1        32768
# - Affine:            96      3145728
# - ExtJac:           192      6291456
#   ----------------------------------
#   Total             289    9 469 952  ~= 10MB
#
# Scheduler: 1 per thread
# - start, stop:        8
# - queue cursors:      8
# - bucketMap:       4096
# - rescheduled:      256
#   -----------------------------------
#   Total            4368 ~= 4KB per thread

# ########################################################### #
#                                                             #
#                    General utilities                        #
#                                                             #
# ########################################################### #

func bestBucketBitSize*(inputSize: int, scalarBitwidth: static int, useSignedBuckets, useManualTuning: static bool): int {.inline.} =
  ## Evaluate the best bucket bit-size for the input size.
  ## That bucket size minimize group operations.
  ## This ignore cache effect. Computation can become memory-bound, especially with large buckets
  ## that don't fit in L1 cache, trigger the 64K aliasing conflict or worse (overflowing L2 cache or TLB).
  ## Especially, scalars are expected to be indistinguishable from random so buckets accessed during accumulation
  ## will be in a random pattern, triggering cache misses.

  # Raw operation cost is approximately
  # 1. Bucket accumulation
  #      n - (2ᶜ-1) additions for b/c windows    or n - (2ᶜ⁻¹-1) if using signed buckets
  # 2. Bucket reduction
  #      2x(2ᶜ-2) additions for b/c windows      or 2*(2ᶜ⁻¹-2)
  # 3. Final reduction
  #      (b/c - 1) x (c doublings + 1 addition)
  # Total
  #   b/c (n + 2ᶜ - 2) A + (b/c - 1) * (c*D + A)
  # https://www.youtube.com/watch?v=Bl5mQA7UL2I

  # A doubling costs 50% of an addition with jacobian coordinates
  # and between 60% (BLS12-381 G1) to 66% (BN254-Snarks G1)

  const A = 10'f32  # Addition cost
  const D =  6'f32  # Doubling cost

  const s = int useSignedBuckets
  let n = inputSize
  let b = float32(scalarBitwidth)
  var minCost = float32(Inf)
  for c in 2 .. 20: # cap return value at 17 after manual tuning
    let b_over_c = b/c.float32

    let bucket_accumulate_reduce = b_over_c * float32(n + (1 shl (c-s)) - 2) * A
    let final_reduction = (b_over_c - 1'f32) * (c.float32*D + A)
    let cost = bucket_accumulate_reduce + final_reduction
    if cost < minCost:
      minCost = cost
      result = c

  # Manual tuning, memory bandwidth / cache boundaries of
  # L1, L2 caches, TLB and 64 aliasing conflict
  # are not taken into account in previous formula.
  # Each increase in c doubles memory used.
  when useManualTuning:
    if 14 <= result:
      result -= 1
    if 15 <= result:
      result -= 1
    if 16 <= result:
      result -= 1

# Extended Jacobian generic bindings
# ----------------------------------
# All vartime procedures MUST be tagged vartime
# Hence we do not expose `sum` or `+=` for extended jacobian operation to prevent `vartime` mistakes
# we create a local `sum` or `+=` for this module only
func `+=`*[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_JacExt[F, G]) {.inline.}=
  P.sum_vartime(P, Q)
func `+=`*[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) {.inline.}=
  P.madd_vartime(P, Q)
func `-=`*[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) {.inline.}=
  P.msub_vartime(P, Q)

# ########################################################### #
#                                                             #
#                       Scheduler                             #
#                                                             #
# ########################################################### #
#
# "磨刀不误砍柴功"
# "Sharpening the axe will not delay cutting the wood" - Chinese proverb

type
  BucketStatus* = enum
    kAffine, kJacExt

  Buckets*[N: static int, F; G: static Subgroup] = object
    status*:   array[N, set[BucketStatus]]
    ptAff*:    array[N, ECP_ShortW_Aff[F, G]]
    ptJacExt*: array[N, ECP_ShortW_JacExt[F, G]] # Public for the top window

  ScheduledPoint* = object
    # Note: we cannot compute the size at compile-time due to https://github.com/nim-lang/Nim/issues/19040
    bucket  {.bitsize:26.}: int64 # Supports up to 2²⁵ =      33 554 432 buckets and -1 for the skipped bucket 0
    sign    {.bitsize: 1.}: int64
    pointID {.bitsize:37.}: int64 # Supports up to 2³⁷ = 137 438 953 472 points

  Scheduler*[NumNZBuckets, QueueLen: static int, F; G: static Subgroup] = object
    points:                        ptr UncheckedArray[ECP_ShortW_Aff[F, G]]
    buckets*:                      ptr Buckets[NumNZBuckets, F, G]
    start, stopEx:                 int32                # Bucket range
    numScheduled, numCollisions:   int32
    collisionsMap:                 BigInt[NumNZBuckets] # We use a BigInt as a bitmap, when all you have is an axe ...
    queue:                         array[QueueLen, ScheduledPoint]
    collisions:                    array[QueueLen, ScheduledPoint]

const MinVectorAddThreshold = 32

func init*(buckets: ptr Buckets) {.inline.} =
  zeroMem(buckets.status.addr, buckets.status.sizeof())

func reset*(buckets: ptr Buckets, index: int) {.inline.} =
  buckets.status[index] = {}

func deriveSchedulerConstants*(c: int): tuple[numNZBuckets, queueLen: int] {.compileTime.} =
  # Returns the number of non-zero buckets and the scheduler queue length
  result.numNZBuckets = 1 shl (c-1)
  result.queueLen = max(MinVectorAddThreshold, 4*c*c - 16*c - 128)

func init*[NumNZBuckets, QueueLen: static int, F; G: static Subgroup](
      sched: ptr Scheduler[NumNZBuckets, QueueLen, F, G], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
      buckets: ptr Buckets[NumNZBuckets, F, G], start, stopEx: int32) {.inline.} =
  ## init a scheduler overseeing buckets [start, stopEx)
  ## within the indices [0, NumNZBuckets). Bucket for value 0 is considered at index -1.
  sched.points        =  points
  sched.buckets       = buckets
  sched.start         =   start
  sched.stopEx        =  stopEx
  sched.numScheduled  =       0
  sched.numCollisions =       0

func bucketInit*(sched: ptr Scheduler) {.inline.} =
  zeroMem(sched.buckets.status.addr +% sched.start, (sched.stopEx-sched.start)*sizeof(set[BucketStatus]))

func scheduledPointDescriptor*(pointIndex: int, pointDesc: tuple[val: SecretWord, neg: SecretBool]): ScheduledPoint {.inline.} =
  ScheduledPoint(
    bucket:  cast[int64](pointDesc.val)-1, # shift bucket by 1 as bucket 0 is skipped
    sign:    cast[int64](pointDesc.neg),
    pointID: cast[int64](pointIndex))

func enqueuePoint(sched: ptr Scheduler, sp: ScheduledPoint) {.inline.} =
  sched.queue[sched.numScheduled] = sp
  sched.collisionsMap.setBit(sp.bucket.int)
  sched.numScheduled += 1

func handleCollision(sched: ptr Scheduler, sp: ScheduledPoint)
func rescheduleCollisions(sched: ptr Scheduler)
func sparseVectorAddition[F, G](
       buckets:         ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       bucketStatuses:  ptr UncheckedArray[set[BucketStatus]],
       points:          ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       scheduledPoints: ptr UncheckedArray[ScheduledPoint],
       numScheduled:    int32) {.noInline, tags:[VarTime, Alloca].}

func prefetch*(sched: ptr Scheduler, sp: ScheduledPoint) =
  let bucket = sp.bucket
  if bucket == -1:
    return

  prefetch(sched.buckets.status[bucket].addr, Write, HighTemporalLocality)
  prefetchLarge(sched.buckets.ptAff[bucket].addr, Write, HighTemporalLocality, maxCacheLines = 1)
  prefetchLarge(sched.buckets.ptJacExt[bucket].addr, Write, HighTemporalLocality, maxCacheLines = 1)

func schedule*(sched: ptr Scheduler, sp: ScheduledPoint) =
  ## Schedule a point for accumulating in buckets

  let bucket = int sp.bucket
  if not(sched.start <= bucket and bucket < sched.stopEx):
    return

  if kAffine notin sched.buckets.status[bucket]: # Random access, prefetch to avoid cache-misses
    if sp.sign == 0:
      sched.buckets.ptAff[bucket] = sched.points[sp.pointID]
    else:
      sched.buckets.ptAff[bucket].neg(sched.points[sp.pointID])
    sched.buckets.status[bucket].incl(kAffine)
    return

  if sched.collisionsMap.bit(bucket).bool:
    sched.handleCollision(sp)
    return

  sched.enqueuePoint(sp)

  if sched.numScheduled == sched.queue.len:
    sparseVectorAddition(
      sched.buckets.ptAff.asUnchecked(), sched.buckets.status.asUnchecked(),
      sched.points, sched.queue.asUnchecked(), sched.numScheduled)
    sched.numScheduled = 0
    sched.collisionsMap.setZero()
    sched.rescheduleCollisions()

func handleCollision(sched: ptr Scheduler, sp: ScheduledPoint) =
  if sched.numCollisions < sched.collisions.len:
    sched.collisions[sched.numCollisions] = sp
    sched.numCollisions += 1
    return

  # If we want to optimize for a workload were many multipliers are the same, it's here
  if kJacExt notin sched.buckets.status[sp.bucket]:
    sched.buckets.ptJacExt[sp.bucket].fromAffine(sched.points[sp.pointID])
    if sp.sign != 0:
      sched.buckets.ptJacExt[sp.bucket].neg()
    sched.buckets.status[sp.bucket].incl(kJacExt)
    return

  if sp.sign == 0:
    sched.buckets.ptJacExt[sp.bucket] += sched.points[sp.pointID]
  else:
    sched.buckets.ptJacExt[sp.bucket] -= sched.points[sp.pointID]

func rescheduleCollisions(sched: ptr Scheduler) =
  template last: untyped = sched.numCollisions-1
  var i = last()
  while i >= 0:
    let sp = sched.collisions[i]
    if not sched.collisionsMap.bit(sp.bucket.int).bool:
      sched.enqueuePoint(sp)
      if i != last():
        sched.collisions[i] = sched.collisions[last()]
      sched.numCollisions -= 1
    i -= 1

func flushBuffer(sched: ptr Scheduler, buf: ptr UncheckedArray[ScheduledPoint], count: var int32) =
  for i in 0 ..< count:
    let sp = buf[i]
    if kJacExt in sched.buckets.status[sp.bucket]:
      if sp.sign == 0:
        sched.buckets.ptJacExt[sp.bucket] += sched.points[sp.pointID]
      else:
        sched.buckets.ptJacExt[sp.bucket] -= sched.points[sp.pointID]
    else:
      sched.buckets.ptJacExt[sp.bucket].fromAffine(sched.points[sp.pointID])
      if sp.sign != 0:
        sched.buckets.ptJacExt[sp.bucket].neg()
      sched.buckets.status[sp.bucket].incl(kJacExt)
  count = 0

func flushPendingAndReset*(sched: ptr Scheduler) =
  if sched.numScheduled >= MinVectorAddThreshold:
    sparseVectorAddition(
      sched.buckets.ptAff.asUnchecked(), sched.buckets.status.asUnchecked(),
      sched.points, sched.queue.asUnchecked(), sched.numScheduled)
    sched.numScheduled = 0

  if sched.numScheduled > 0:
    sched.flushBuffer(sched.queue.asUnchecked(), sched.numScheduled)

  if sched.numCollisions > 0:
    sched.flushBuffer(sched.collisions.asUnchecked(), sched.numCollisions)

  sched.collisionsMap.setZero()

# ########################################################### #
#                                                             #
#                    Computation                             #
#                                                             #
# ########################################################### #

func sparseVectorAddition[F, G](
       buckets: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       bucketStatuses: ptr UncheckedArray[set[BucketStatus]],
       points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       scheduledPoints: ptr UncheckedArray[ScheduledPoint],
       numScheduled: int32
      ) {.noInline, tags:[VarTime, Alloca].} =
  ## Does a sparse vector addition: buckets += scheduledPoints
  ## This implementation is optimized using batch affine inversion
  ## with an asymptotic cost for N points of N*6M + I
  ## where M is field multiplication and I the field inversion.
  ##
  ## Inversion usually costs between 66M to 120M depending on implementation:
  ## - scaling linearly with bits (Euclid, Lehmer, Stein, Bernstein-Yang, Pornin algorithm)
  ## - scaling quadratically with bits if using Fermat's Little Theorem a⁻¹ ≡ ᵖ⁻² (mod p) with addition chains
  ## - constant-time or variable time
  ##
  ## `scheduledPoints` must all target a different bucket.
  template sps: untyped = scheduledPoints

  type SpecialCase = enum
    kRegular, kInfLhs, kInfRhs, kOpposite

  let lambdas = allocStackArray(tuple[num, den: F], numScheduled)
  let accumDen = allocStackArray(F, numScheduled)
  let specialCases = allocStackArray(SpecialCase, numScheduled)

  # Step 1: Compute numerators and denominators of λᵢ = λᵢ_num / λᵢ_den
  for i in 0 ..< numScheduled:

    template skipSpecialCase {.dirty.} =
      if i == 0: accumDen[i].setOne()
      else: accumDen[i] = accumDen[i-1]
      continue

    if i != numScheduled - 1:
      prefetchLarge(points[sps[i+1].pointID].addr, Read, HighTemporalLocality, maxCacheLines = 4)
      prefetch(bucketStatuses[sps[i+1].bucket].addr, Read, HighTemporalLocality)
      prefetchLarge(buckets[sps[i+1].bucket].addr, Read, HighTemporalLocality, maxCacheLines = 4)

    # Special cases 1: infinity points have affine coordinates (0, 0) by convention
    #                  it doesn't match the y²=x³+ax+b equation so slope formula need special handling
    if (kAffine notin bucketStatuses[sps[i].bucket]) or buckets[sps[i].bucket].isInf().bool:
      specialCases[i] = kInfLhs
      skipSpecialCase()
    elif points[sps[i].pointID].isInf().bool:
      specialCases[i] = kInfRhs
      skipSpecialCase()

    # Special case 2: λ = (Qy-Py)/(Qx-Px) which is undefined when Px == Qx
    #                 This happens when P == Q or P == -Q
    if bool(buckets[sps[i].bucket].x == points[sps[i].pointID].x):
      if sps[i].sign == 0:
        if bool(buckets[sps[i].bucket].y == points[sps[i].pointID].y):
          lambdaDouble(lambdas[i].num, lambdas[i].den, buckets[sps[i].bucket])
        else:
          specialCases[i] = kOpposite
          skipSpecialCase()
      else:
        if bool(buckets[sps[i].bucket].y == points[sps[i].pointID].y):
          specialCases[i] = kOpposite
          skipSpecialCase()
        else:
          lambdaDouble(lambdas[i].num, lambdas[i].den, buckets[sps[i].bucket])
    else:
      if sps[i].sign == 0:
        lambdaAdd(lambdas[i].num, lambdas[i].den, buckets[sps[i].bucket], points[sps[i].pointID])
      else:
        lambdaSub(lambdas[i].num, lambdas[i].den, buckets[sps[i].bucket], points[sps[i].pointID])

    # Step 2: Accumulate denominators.
    specialCases[i] = kRegular
    if i == 0:
      accumDen[i] = lambdas[i].den
    elif i == numScheduled-1:
      accumDen[i].prod(accumDen[i-1], lambdas[i].den)
    else:
      accumDen[i].prod(accumDen[i-1], lambdas[i].den, skipFinalSub = true)

  # Step 3: Batch invert
  var accInv {.noInit.}: F
  accInv.inv_vartime(accumDen[numScheduled-1])

  # Step 4: Output the sums
  for i in countdown(numScheduled-1, 1):
    prefetchLarge(points[sps[i-1].pointID].addr, Read, HighTemporalLocality, maxCacheLines = 4)
    prefetchLarge(buckets[sps[i-1].bucket].addr, Write, HighTemporalLocality, maxCacheLines = 4)

    if specialCases[i] == kInfLhs:
      if sps[i]. sign == 0:
        buckets[sps[i].bucket] = points[sps[i].pointID]
      else:
        buckets[sps[i].bucket].neg(points[sps[i].pointID])
      bucketStatuses[sps[i].bucket].incl(kAffine)
      continue
    elif specialCases[i] == kInfRhs:
      continue
    elif specialCases[i] == kOpposite:
      buckets[sps[i].bucket].setInf()
      bucketStatuses[sps[i].bucket].excl(kAffine)
      continue

    # Compute lambda - destroys accumDen[i]
    accumDen[i].prod(accInv, accumDen[i-1], skipFinalSub = true)
    accumDen[i].prod(accumDen[i], lambdas[i].num, skipFinalSub = true)

    # Compute EC addition
    var r{.noInit.}: ECP_ShortW_Aff[F, G]
    r.affineAdd(lambda = accumDen[i], buckets[sps[i].bucket], points[sps[i].pointID]) # points[sps[i].pointID].y unused even if sign is negative

    # Store result
    buckets[sps[i].bucket] = r

    # Next iteration
    accInv.prod(accInv, lambdas[i].den, skipFinalSub = true)

  block: # tail
    if specialCases[0] == kInfLhs:
      if sps[0].sign == 0:
        buckets[sps[0].bucket] = points[sps[0].pointID]
      else:
        buckets[sps[0].bucket].neg(points[sps[0].pointID])
      bucketStatuses[sps[0].bucket].incl(kAffine)
    elif specialCases[0] == kInfRhs:
      discard
    elif specialCases[0] == kOpposite:
      buckets[sps[0].bucket].setInf()
      bucketStatuses[sps[0].bucket].excl(kAffine)
    else:
      # Compute lambda
      accumDen[0].prod(lambdas[0].num, accInv, skipFinalSub = true)

      # Compute EC addition
      var r{.noInit.}: ECP_ShortW_Aff[F, G]
      r.affineAdd(lambda = accumDen[0], buckets[sps[0].bucket], points[sps[0].pointID])

      # Store result
      buckets[sps[0].bucket] = r

func bucketReduce*[N, F, G](
       r: var ECP_ShortW_JacExt[F, G],
       buckets: ptr Buckets[N, F, G]) =

  var accumBuckets{.noinit.}: ECP_ShortW_JacExt[F, G]

  if kAffine in buckets.status[N-1]:
    if kJacExt in buckets.status[N-1]:
      accumBuckets.madd_vartime(buckets.ptJacExt[N-1], buckets.ptAff[N-1])
    else:
      accumBuckets.fromAffine(buckets.ptAff[N-1])
  elif kJacExt in buckets.status[N-1]:
    accumBuckets = buckets.ptJacExt[N-1]
  else:
    accumBuckets.setInf()
  r = accumBuckets
  buckets.reset(N-1)

  for k in countdown(N-2, 0):
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
    r += accumBuckets

# ########################################################### #
#                                                             #
#                   Statistics generation                     #
#                                                             #
# ########################################################### #

when isMainModule:
  import strformat

  proc echoSchedulingParameter(logInputSize: int, echoHeader = false) {.raises:[ValueError].} =

    const titles = ["-------inputs-------", "c", "----buckets----", "queue length", "collision map bytes", "num collisions", "collision %"]
    const header = &"{titles[0]:>16}  {titles[1]:>3}  {titles[2]:>19}  {titles[3]:>13}  {titles[4]:>16}  {titles[5]:>14}  {titles[6]:>12}"

    if echoHeader:
      echo header
      return

    let inputSize = 1 shl logInputSize
    let c = inputSize.bestBucketBitSize(255, useSignedBuckets = true, useManualTuning = false)
    let twoPow = "2^"
    let numNZBuckets = 1 shl (c-1)
    let collisionMapSize = ceilDiv_vartime(1 shl (c-1), 64) * 8 # Stored in BigInt[1 shl (c-1)]
    let queueSize = 4*c*c - 16*c - 128
    let numCollisions = float(inputSize*queueSize) / float(numNZBuckets)
    let collisionPercentage = numCollisions / float(inputSize) * 100

    echo &"{twoPow & $logInputSize:>4}  {inputSize:>14}  {c:>3}     {twoPow & $(c-1):>4} {numNZBuckets:>11}  {queueSize:>13}  {collisionMapSize:>19}  {numCollisions:>14}  {collisionPercentage:>11.1f}%"

  echoSchedulingParameter(0, echoHeader = true)
  for n in 0 ..< 36:
    echoSchedulingParameter(n)
