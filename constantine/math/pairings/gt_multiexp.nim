# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

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
       constantine/math/arithmetic/bigints,
       constantine/named/zoo_endomorphisms,
       constantine/platforms/abstractions,
       ./cyclotomic_subgroups

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# ########################################################### #
#                                                             #
#             Multi-Exponentiation in 𝔾ₜ                      #
#                                                             #
# ########################################################### #

# General utilities
# -------------------------------------------------------------

func bestBucketBitSize*(inputSize: int, scalarBitwidth: static int, useSignedBuckets, useManualTuning: static bool): int {.inline.} =
  ## Evaluate the best bucket bit-size for the input size.
  ## That bucket size minimize group operations.
  ## This ignore cache effect. Computation can become memory-bound, especially with large buckets
  ## that don't fit in L1 cache, trigger the 64K aliasing conflict or worse (overflowing L2 cache or TLB).
  ## Especially, scalars are expected to be indistinguishable from random so buckets accessed during accumulation
  ## will be in a random pattern, triggering cache misses.

  # Raw operation cost is approximately
  # 1. Bucket accumulation
  #      n - (2ᶜ-1) mul for b/c windows    or n - (2ᶜ⁻¹-1) if using signed buckets
  # 2. Bucket reduction
  #      2x(2ᶜ-2) mul for b/c windows      or 2*(2ᶜ⁻¹-2)
  # 3. Final reduction
  #      (b/c - 1) x (c cyclotomic squarings + 1 multiplication)
  # Total
  #   b/c (n + 2ᶜ - 2) A + (b/c - 1) * (c*D + A)
  # https://www.youtube.com/watch?v=Bl5mQA7UL2I

  # A cyclotomic square costs ~50% of a 𝔾ₜ multiplication with Granger-Scott formula

  const M = 5300'f32  # Mul cost (in cycles)
  const S = 2100'f32  # Cyclotomic square cost (in cycles)

  const s = int useSignedBuckets
  let n = inputSize
  let b = float32(scalarBitwidth)
  var minCost = float32(Inf)
  for c in 2 .. 20: # cap return value at 17 after manual tuning
    let b_over_c = b/c.float32

    let bucket_accumulate_reduce = b_over_c * float32(n + (1 shl (c-s)) - 2) * M
    let final_reduction = (b_over_c - 1'f32) * (c.float32*S + M)
    let cost = bucket_accumulate_reduce + final_reduction
    if cost < minCost:
      minCost = cost
      result = c

  # Manual tuning, memory bandwidth / cache boundaries of
  # L1, L2 caches, TLB and 64 aliasing conflict
  # are not taken into account in previous formula.
  # Each increase in c doubles memory used.
  # Compared to 𝔾₁, 𝔾ₜ elements are 6x bigger so we shift by 3
  when useManualTuning:
    if 11 <= result:
      result -= 1
    if 12 <= result:
      result -= 1
    if 13 <= result:
      result -= 1

func `~*=`*[Gt: ExtensionField](a: var Gt, b: Gt) =

  # TODO: Analyze the inputs to see if there is avalue in more complex shortcuts (-1, or partial 0 coordinates)
  if a.isOne().bool():
    a = b
  elif b.isOne().bool():
    discard
  else:
    a *= b

func `~/=`*[Gt: ExtensionField](a: var Gt, b: Gt) =
  ## Cyclotomic division
  var t {.noInit.}: Gt
  t.cyclotomic_inv(b)
  a ~*= b

# Reference multi-exponentiation
# -------------------------------------------------------------

func multiExpImpl_reference_vartime[bits: static int, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       exponents: ptr UncheckedArray[BigInt[bits]],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc].} =
  ## Inner implementation of MEXP, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4

  # Prologue
  # --------
  const numBuckets = 1 shl c - 1 # bucket 0 is unused
  const numWindows = bits.ceilDiv_vartime(c)

  let miniEXPs = allocHeapArray(Gt, numWindows)
  let buckets = allocHeapArray(Gt, numBuckets)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our elements in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setOne()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n elems in 2ᶜ-1 elems, first elem per bucket is just copied
    for j in 0 ..< N:
      let b = cast[int](exponents[j].getWindowAt(w*c, c))
      if b == 0: # bucket 0 is unused, no need to add aⱼ⁰
        continue
      else:
        buckets[b-1] ~*= elems[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-exponentiation
    #   S₁¹ + S₂² + S₃³ + ... + (S₂c₋₁)^(2ᶜ-1)
    var accumBuckets{.noInit.}, miniEXP{.noInit.}: Gt
    accumBuckets = buckets[numBuckets-1]
    miniEXP = buckets[numBuckets-1]

    # Example with c = 3, 2³ = 8
    for k in countdown(numBuckets-2, 0):
      accumBuckets ~*= buckets[k] # Stores S₈ then S₈ +S₇ then S₈ +S₇ +S₆ then ...
      miniEXP ~*= accumBuckets    # Stores S₈ then S₈²+S₇ then S₈³+S₇²+S₆ then ...

    miniEXPs[w] = miniEXP

  # 3. Final reduction.                                  Cost: (b/c - 1)x(c+1) => b/c windows, first is copied, c squarings + 1 mul per window
  r = miniEXPs[numWindows-1]
  for w in countdown(numWindows-2, 0):
    for _ in 0 ..< c:
      r.cyclotomic_square()
    r ~*= miniEXPs[w]

  # Cleanup
  # -------
  buckets.freeHeap()
  miniEXPs.freeHeap()

func multiExp_reference_dispatch_vartime[bits: static int, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       exponents: ptr UncheckedArray[BigInt[bits]],
       N: int) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = false, useManualTuning = false)

  case c
  of  2: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  2)
  of  3: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  3)
  of  4: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  4)
  of  5: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  5)
  of  6: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  6)
  of  7: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  7)
  of  8: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  8)
  of  9: multiExpImpl_reference_vartime(r, elems, exponents, N, c =  9)
  of 10: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 10)
  of 11: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 11)
  of 12: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 12)
  of 13: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 13)
  of 14: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 14)
  of 15: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 15)

  of 16..20: multiExpImpl_reference_vartime(r, elems, exponents, N, c = 16)
  else:
    unreachable()

func multiExp_reference_vartime*[bits: static int, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       exponents: ptr UncheckedArray[BigInt[bits]],
       N: int) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  multiExp_reference_dispatch_vartime(r, elems, exponents, N)

func multiExp_reference_vartime*[Gt](r: var Gt, elems: openArray[Gt], exponents: openArray[BigInt]) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert exponents.len == elems.len
  let N = elems.len
  multiExp_reference_dispatch_vartime(r, elems.asUnchecked(), exponents.asUnchecked(), N)

func multiExp_reference_vartime*[F, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       exponents: ptr UncheckedArray[F],
       len: int) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let n = cast[int](len)
  let exponents_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)
  exponents_big.batchFromField(exponents, n)
  r.multiExp_reference_vartime(elems, exponents_big, n)

  freeHeapAligned(exponents_big)

func multiExp_reference_vartime*[Gt](
       r: var Gt,
       elems: openArray[Gt],
       exponents: openArray[Fr]) {.tags:[VarTime, Alloca, HeapAlloc], inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert exponents.len == elems.len
  let N = elems.len
  multiExp_reference_vartime(r, elems.asUnchecked(), exponents.asUnchecked(), N)
