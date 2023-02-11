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
  ../extension_fields,
  ../io/io_bigints,
  ../ec_shortweierstrass,
  ./ec_shortweierstrass_jacobian_extended

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
# For now implement the simple bucket method as described in
# - Faster batch forgery identification
#   Daniel J. Bernstein, Jeroen Doumen, Tanja Lange, and Jan-Jaap Oosterwijk, 2012
#   https://eprint.iacr.org/2012/549.pdf
#
# See also:
# - Simple guide to fast linear combinations (aka multiexponentiations)
#   Vitalik Buterin, 2020
#   https://ethresear.ch/t/simple-guide-to-fast-linear-combinations-aka-multiexponentiations/7238
#   https://github.com/ethereum/research/blob/5c6fec6/fast_linear_combinations/multicombs.py
# - zkStudyClub: Multi-scalar multiplication: state of the art & new ideas
#   Gus Gutoski, 2020
#   https://www.youtube.com/watch?v=Bl5mQA7UL2I
#
# We want to scale to millions of points and eventually add multithreading so any bit twiddling that hinder
# scalability is avoided.
# The current iteration is a baseline before evaluating and adding various optimizations
# (scalar recoding, change of coordinate systems, bucket sizing, sorting ...)

func multiScalarMulImpl_baseline_vartime[F, G; bits: static int](
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

  # We could free buckets before step 3, but we don't want to flush miniMSMs from cache
  # by going into deallocation code
  buckets.freeHeap()
  miniMSMs.freeHeap()

func bestBucketBitSize*(inputSize: int, orderBitwidth: static int): int {.inline.} =
  ## Evaluate the best bucket bit-size for the input size.
  ## That bucket size minimize group operations. It assumes that additions and doubling cost the same
  ## This ignore cache effect. Computation can become memory-bound, especially with large buckets
  ## that don't fit in L1 cache or worse (overflowing L2 cache or TLB).
  ## Especially, scalars are expected to be indistinguishable from random so buckets accessed during accumulation
  ## will be in a random pattern, triggering cache misses.

  # Raw operation cost is approximately
  # 1. Bucket accumulation
  #      n - (2ᶜ-1) additions for b/c windows
  # 2. Bucket reduction
  #      2x(2ᶜ-2) additions for b/c windows
  # 3. Final reduction
  #      (b/c - 1) x (c doublings + 1 addition)
  # Total
  #   b/c (n + 2ᶜ - 2) A + (b/c - 1) x (c*D + A)
  # https://www.youtube.com/watch?v=Bl5mQA7UL2I

  # A doubling costs 50% of an addition with jacobian coordinates
  # and between 60% (BLS12-381 G1) to 66% (BN254-Snarks G1)

  const A = 10'f32  # Addition cost
  const D =  6'f32  # Doubling cost

  let n = inputSize
  let b = float32(orderBitwidth)
  var minCost = float32(Inf)
  for c in 2 ..< 23:
    let b_over_c = b/c.float32

    let bucket_accumulate_reduce = b_over_c * float32(n + (1 shl c) - 2) * A
    let final_reduction = (b_over_c - 1'f32) * (c.float32*D + A)
    let cost = bucket_accumulate_reduce + final_reduction
    if cost < minCost:
      minCost = cost
      result = c

func multiScalarMul_baseline_vartime*[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff]) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  let N = points.len
  let coefs = coefs.asUnchecked()
  let points = points.asUnchecked()
  let c = bestBucketBitSize(N, BigInt.bits)

  case c
  of  2: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  2)
  of  3: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  3)
  of  4: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  4)
  of  5: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  5)
  of  6: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  6)
  of  7: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  7)
  of  8: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  8)
  of  9: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c =  9)
  of 10: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 10)
  of 11: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 11)
  of 12: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 12)
  of 13: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 13)
  of 14: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 14)
  of 15: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 15)
  of 16: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 16)
  of 17: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 17)
  of 18: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 18)
  of 19: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 19)
  of 20: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 20)
  of 21: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 21)
  of 22: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 22)
  of 23: multiScalarMulImpl_baseline_vartime(r, coefs, points, N, c = 23)
  else:
    unreachable()

# ------------------------------------------------------------------------------------------------------
#
# Multi-Scalar-Mul is the largest bottleneck in Zero-Knowledge-Proofs protocols
# There are ways to avoid FFTs, none to avoid Multi-Scalar-Multiplication
# Hence optimizing it is worth millions, see https://zprize.io

# Extended Jacobian generic bindings
# ----------------------------------
# All vartime procedures MUST be tagged vartime
# Hence we do not expose `sum` or `+=` for extended jacobian operation to prevent `vartime` mistakes
# we create a local `sum` or `+=` for this module only
func `+=`[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_JacExt[F, G]) {.inline.}=
  P.sum_vartime(P, Q)
func `+=`[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) {.inline.}=
  P.madd_vartime(P, Q)
func `-=`[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) {.inline.}=
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  P.madd_vartime(P, nQ)

func accumulate[ECbucket, ECpoint](buckets: ptr UncheckedArray[ECbucket], val: SecretWord, negate: SecretBool, point: ECpoint) {.inline.} =
  let val = BaseType(val)
  if val == 0:
    return
  elif negate.bool:
    buckets[val-1] -= point
  else:
    buckets[val-1] += point

func bucketReduce[EC](r: var EC, buckets: ptr UncheckedArray[EC], numBuckets: static int) =
  # We interleave reduction with zero-ing the bucket to use instruction-level parallelism

  var accumBuckets{.noInit.}, sliceSum{.noInit.}: EC
  accumBuckets = buckets[numBuckets-1]
  r = buckets[numBuckets-1]
  zeroMem(buckets[numBuckets-1].addr, sizeof(EC))

  for k in countdown(numBuckets-2, 0):
    accumBuckets += buckets[k]
    r += accumBuckets
    zeroMem(buckets[k].addr, sizeof(EC))

func miniMSM[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       buckets: ptr UncheckedArray[ECP_ShortW_JacExt[F, G]],
       bitIndex: int, window, c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) =
  ## Apply a mini-Multi-Scalar-Multiplication on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs
  ##
  ## For bitIndex != 0

  # 1. Bucket Accumulation
  for j in 0 ..< N:
    let digit = coefs[j].getWindowAt(bitIndex-1, window+1) # get the bit on the left of LSB for Booth recoding
    const hasExcess = window != c                          # Usually window == c, except for the excess top (bits mod c)
    let (value, isNeg) = digit.getBoothEncoding(window + int(hasExcess)) # Add a top 0 for excess bits
    buckets.accumulate(value, isNeg, points[j])

  # 2. Bucket Reduction
  var sliceSum{.noinit.}: ECP_ShortW_JacExt[F, G]
  sliceSum.bucketReduce(buckets, numBuckets = 1 shl (c-1))

  # 3. Mini-MSM on the slice [bitIndex, bitIndex+window)
  var windowSum{.noInit.}: typeof(r)
  windowSum.fromJacobianExtended(sliceSum)
  r += windowSum
  for _ in 0 ..< c:
    r.double()

func miniMSM0[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       buckets: ptr UncheckedArray[ECP_ShortW_JacExt[F, G]],
       c: static int,
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]], N: int) =
  ## Apply a mini-Multi-Scalar-Multiplication on [0, c)
  ## slice of all (coef, point) pairs

  # 1. Bucket Accumulation
  for j in 0 ..< N:
    let digit = coefs[j].getWindowAt(0, c) shl 1 # implicit 0 on the right of the LSB
    let (value, isNeg) = digit.getBoothEncoding(c) # Add a top 0 for excess bits
    buckets.accumulate(value, isNeg, points[j])

  # 2. Bucket Reduction
  var sliceSum{.noinit.}: ECP_ShortW_JacExt[F, G]
  sliceSum.bucketReduce(buckets, numBuckets = 1 shl (c-1))

  # 3. Mini-MSM on the least significant slice
  var windowSum{.noInit.}: typeof(r)
  windowSum.fromJacobianExtended(sliceSum)
  r += windowSum

func multiScalarMulImpl_opt_vartime[F, G; bits: static int](
       r: var ECP_ShortW[F, G],
       coefs: ptr UncheckedArray[BigInt[bits]], points: ptr UncheckedArray[ECP_ShortW_Aff[F, G]],
       N: int, c: static int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  # Setup
  # -----
  const numBuckets = 1 shl (c-1)
  type EC = typeof(r)

  let buckets = allocHeapArray(jacobianExtended(EC), numBuckets)
  zeroMem(buckets[0].addr, sizeof(jacobianExtended(EC)) * numBuckets)

  # Algorithm
  # ---------
  const excess = bits mod c
  const top = bits - excess
  var w = top

  if excess != 0 and w != 0: # Prologue
    r.miniMSM(buckets, top, window = excess, c, coefs, points, N)
    w -= c

  while w != 0:              # Steady state
    r.miniMSM(buckets, w, window = c, c, coefs, points, N)
    w -= c

  block:
    r.miniMSM0(buckets, c, coefs, points, N)

  # Cleanup
  # -------
  buckets.freeHeap()

func multiScalarMul_opt_vartime*[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff]) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  debug: doAssert coefs.len == points.len

  let N = points.len
  let coefs = coefs.asUnchecked()
  let points = points.asunchecked()
  let c = bestBucketBitSize(N, BigInt.bits)

  case c
  of  2: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  2)
  of  3: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  3)
  of  4: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  4)
  of  5: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  5)
  of  6: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  6)
  of  7: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  7)
  of  8: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  8)
  of  9: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c =  9)
  of 10: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 10)
  of 11: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 11)
  of 12: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 12)
  of 13: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 13)
  of 14: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 14)
  of 15: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 15)
  of 16: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 16)
  of 17: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 17)
  of 18: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 18)
  of 19: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 19)
  of 20: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 20)
  of 21: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 21)
  of 22: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 22)
  of 23: multiScalarMulImpl_opt_vartime(r, coefs, points, N, c = 23)
  else:
    unreachable()