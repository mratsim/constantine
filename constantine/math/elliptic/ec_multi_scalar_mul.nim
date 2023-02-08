# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/[abstractions, allocs, views],
  ../arithmetic,
  ../extension_fields,
  ../io/io_bigints,
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_jacobian

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
# {.push checks: off.}

{.localpassC:"-fsanitize=address".}
{.passL:"-fsanitize=address".}

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

func digit_vartime(a: BigInt, index: int, bitsize: static int): uint {.inline, tags:[VarTime].} =
  ## Access a digit of `a` of size bitsize
  ## Variable-time!
  static: doAssert bitsize <= WordBitWidth

  const SlotShift = log2_vartime(WordBitWidth.uint32)
  const WordMask = WordBitWidth - 1
  const DigitMask = (1 shl bitsize) - 1

  let bitIndex = index * bitsize
  let slot     = bitIndex shr SlotShift
  let word     = a.limbs[slot]                    # word in limbs
  let pos      = bitIndex and WordMask            # position in the word

  when bitsize.isPowerOf2_vartime():
    # Bit extraction is aligned with 32-bit or 64-bit words
    return uint(word shr pos) and DigitMask
  else:
    # unaligned extraction, we might need to read the next word as well.
    if pos + bitsize > WordBitWidth and slot+1 < a.limbs.len:
      # Read next word as well
      return uint((word shr pos) or (a.limbs[slot+1] shl (WordBitWidth-pos))) and DigitMask
    else:
      return uint(word shr pos) and DigitMask

func multiScalarMulImpl_baseline_vartime[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff], c: static int) =
  ## Inner implementation of MSM, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4
  debug: assert coefs.len == points.len

  const numWindows = (BigInt.bits + c - 1) div c
  const numBuckets = 1 shl c # Technically 2ᶜ-1 since bucket 0 is unused

  let buckets = allocHeapArray(EC, numBuckets)
  let miniMSMs = allocHeapArray(EC, numWindows)

  for w in 0 ..< numWindows:
    # Place our points in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setInf()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n points in 2ᶜ-1 buckets, first point per bucket is just copied
    for j in 0 ..< points.len:
      let b = coefs[j].digit_vartime(w, c)
      if b == 0: # bucket 0 is unused, no need to add [0]Pⱼ
        continue
      else:
        buckets[b] += points[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-MSM
    #   [1]S₁ + [2]S₂ + [3]S₃ + ... + [2ᶜ-1]S₂c₋₁
    var accumBuckets{.noInit.}, miniMSM{.noInit.}: EC
    accumBuckets = buckets[numBuckets-1]
    miniMSM = buckets[numBuckets-1]

    # Example with c = 3, 2³ = 8
    for k in countdown(numBuckets-2, 1):
      accumBuckets += buckets[k] # Stores S₈ then    S₈+S₇ then       S₈+S₇+S₆ then ...
      miniMSM += accumBuckets    # Stores S₈ then [2]S₈+S₇ then [3]S₈+[2]S₇+S₆ then ...

    miniMSMs[w] = miniMSM

  buckets.freeHeap()

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c doublings + 1 addition per window
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r += miniMSMs[w]

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
  let c = bestBucketBitSize(points.len, BigInt.bits)

  case c
  of  2: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  2)
  of  3: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  3)
  of  4: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  4)
  of  5: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  5)
  of  6: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  6)
  of  7: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  7)
  of  8: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  8)
  of  9: multiScalarMulImpl_baseline_vartime(r, coefs, points, c =  9)
  of 10: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 10)
  of 11: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 11)
  of 12: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 12)
  of 13: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 13)
  of 14: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 14)
  of 15: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 15)
  of 16: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 16)
  of 17: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 17)
  of 18: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 18)
  of 19: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 19)
  of 20: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 20)
  of 21: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 21)
  of 22: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 22)
  of 23: multiScalarMulImpl_baseline_vartime(r, coefs, points, c = 23)
  else:
    unreachable()

# ------------------------------------------------------------------------------------------------------
#
# Multi-Scalar-Mul is the largest bottleneck in Zero-Knowledge-Proofs protocols
# There are ways to avoid FFTs, none to avoid Multi-Scalar-Multiplication
# Hence optimizing it is worth millions, see https://zprize.io

func multiScalarMulImpl_opt_vartime[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff], c: static int) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ

  debug: assert coefs.len == points.len

  # When c = 2, the digits can be 0, 1, 2, 3
  # if the MSB is set, we substract 4, hence the signed digit can be 0, 1, -2, -1
  # We add 1 unsed bucket at position 0 for now to allow indexing directly with the value
  const numBuckets = 1 shl (c-1) + 1
  const numWindows = (BigInt.bits + c - 1) div c + 1 # signed overflow

  let bucketsBuf = allocHeapArray(EC, numWindows*numBuckets)
  let miniMSMs = allocHeapArray(EC, numWindows)

  for i in 0 ..< numWindows*numBuckets:
    bucketsBuf[i].setInf()

  let buckets = bucketsBuf.toMatrixView(numWindows, numBuckets)

  # 1. Bucket accumulation
  for j in 0 ..< points.len:
    var carry = 0
    for w in 0 ..< numWindows:
      var digit = carry
      if (w * c) < BigInt.bits:
        digit += coefs[j].digit_vartime(w, c).int

      if digit == 0: # bucket 0 is unused, no need to add [0]Pⱼ
        continue
      elif digit >= 1 shl (c-1):
        debug: doAssert w != numWindows-1, "numWindows: " & $numWindows & " for " & $BigInt.bits & "-bit scalars with window " & $c
        digit -= 1 shl c
        carry = 1
        buckets[w, -digit] -= points[j]
      else:
        carry = 0
        buckets[w, digit] += points[j]

  # 2. Bucket reduction
  block:
    let accumBuckets = allocHeapArray(EC, numWindows)
    for k in countdown(numBuckets-1, 1):
      for w in 0 ..< numWindows:
        if k == numBuckets-1:
          accumBuckets[w] = buckets[w, numBuckets-1]
          miniMSMs[w]     = buckets[w, numBuckets-1]
        else:
          accumBuckets[w] += buckets[w, k]
          miniMSMs[w]     += accumBuckets[w]
    accumBuckets.freeHeap()
  bucketsBuf.freeHeap()

  # 3. Final reduction.
  r = miniMSMs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.double()
    r += miniMSMs[w]

  miniMSMs.freeHeap()

func multiScalarMul_opt_vartime*[EC](r: var EC, coefs: openArray[BigInt], points: openArray[ECP_ShortW_Aff]) =
  ## Multiscalar multiplication:
  ##   r <- [a₀]P₀ + [a₁]P₁ + ... + [aₙ]Pₙ
  let c = bestBucketBitSize(points.len, BigInt.bits)

  case c
  of  2: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  2)
  of  3: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  3)
  of  4: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  4)
  of  5: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  5)
  of  6: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  6)
  of  7: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  7)
  of  8: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  8)
  of  9: multiScalarMulImpl_opt_vartime(r, coefs, points, c =  9)
  of 10: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 10)
  of 11: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 11)
  of 12: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 12)
  of 13: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 13)
  of 14: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 14)
  of 15: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 15)
  of 16: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 16)
  of 17: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 17)
  of 18: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 18)
  of 19: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 19)
  of 20: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 20)
  of 21: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 21)
  of 22: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 22)
  of 23: multiScalarMulImpl_opt_vartime(r, coefs, points, c = 23)
  else:
    unreachable()