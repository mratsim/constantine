# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import constantine/named/algebras,
       constantine/math/arithmetic,
       constantine/math/endomorphisms/split_scalars,
       constantine/math/extension_fields,
       constantine/named/zoo_endomorphisms,
       constantine/platforms/abstractions,
       ./cyclotomic_subgroups, ./gt_prj

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

func bestBucketBitSize(inputSize: int, scalarBitwidth: static int, useSignedBuckets, useManualTuning: static bool): int {.inline.} =
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

func `~*=`[Gt: ExtensionField](a: var Gt, b: Gt) {.inline.} =
  # TODO: Analyze the inputs to see if there is avalue in more complex shortcuts (-1, or partial 0 coordinates)
  if a.isOne().bool():
    a = b
  elif b.isOne().bool():
    discard
  else:
    a *= b

func `~/=`[Gt: ExtensionField](a: var Gt, b: Gt) {.inline.} =
  ## Cyclotomic division
  var t {.noInit.}: Gt
  t.cyclotomic_inv(b)
  a ~*= t

func setNeutral[Gt: ExtensionField](a: var Gt) {.inline.} =
  a.setOne()

func `~*=`(a: var T2Prj, b: T2Aff) {.inline.} =
  a.mixedProd_vartime(a, b)

func `~*=`(a: var T2Prj, b: T2Prj) {.inline.} =
  a.prod(a, b)

func `~/=`(a: var T2Prj, b: T2Aff) {.inline.} =
  ## Cyclotomic division
  var t {.noInit.}: T2Aff
  t.inv(b)
  a ~*= t

# Reference multi-exponentiation
# -------------------------------------------------------------
# We distinguish GtAcc (GT Accumulators) from GtElt (Gt Element)
# They can map to the same type if using extension fields
# or to 2 different types if using tori (affine and projective torus coordinates)

func multiExpImpl_reference_vartime[bits: static int, GtAcc, GtElt](
       r: var GtAcc,
       elems: ptr UncheckedArray[GtElt],
       expos: ptr UncheckedArray[BigInt[bits]],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc].} =
  ## Inner implementation of MEXP, for static dispatch over c, the bucket bit length
  ## This is a straightforward simple translation of BDLO12, section 4

  # Prologue
  # --------
  const numBuckets = 1 shl c - 1 # bucket 0 is unused
  const numWindows = bits.ceilDiv_vartime(c)

  let miniEXPs = allocHeapArrayAligned(GtAcc, numWindows, alignment = 64)
  let buckets = allocHeapArrayAligned(GtAcc, numBuckets, alignment = 64)

  # Algorithm
  # ---------
  for w in 0 ..< numWindows:
    # Place our elements in a bucket corresponding to
    # how many times their bit pattern in the current window of size c
    for i in 0 ..< numBuckets:
      buckets[i].setNeutral()

    # 1. Bucket accumulation.                            Cost: n - (2ᶜ-1) => n elems in 2ᶜ-1 elems, first elem per bucket is just copied
    for j in 0 ..< N:
      let b = cast[int](expos[j].getWindowAt(w*c, c))
      if b == 0: # bucket 0 is unused, no need to add aⱼ⁰
        continue
      else:
        buckets[b-1] ~*= elems[j]

    # 2. Bucket reduction.                               Cost: 2x(2ᶜ-2) => 2 additions per 2ᶜ-1 bucket, last bucket is just copied
    # We have ordered subset sums in each bucket, we now need to compute the mini-exponentiation
    #   S₁¹ + S₂² + S₃³ + ... + (S₂c₋₁)^(2ᶜ-1)
    var accumBuckets{.noInit.}, miniEXP{.noInit.}: GtAcc
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
  buckets.freeHeapAligned()
  miniEXPs.freeHeapAligned()

func multiExp_reference_dispatch_vartime[bits: static int, GtAcc, GtElt](
       r: var GtAcc,
       elems: ptr UncheckedArray[GtElt],
       expos: ptr UncheckedArray[BigInt[bits]],
       N: int) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let c = bestBucketBitSize(N, bits, useSignedBuckets = false, useManualTuning = false)

  case c
  of  2: multiExpImpl_reference_vartime(r, elems, expos, N, c =  2)
  of  3: multiExpImpl_reference_vartime(r, elems, expos, N, c =  3)
  of  4: multiExpImpl_reference_vartime(r, elems, expos, N, c =  4)
  of  5: multiExpImpl_reference_vartime(r, elems, expos, N, c =  5)
  of  6: multiExpImpl_reference_vartime(r, elems, expos, N, c =  6)
  of  7: multiExpImpl_reference_vartime(r, elems, expos, N, c =  7)
  of  8: multiExpImpl_reference_vartime(r, elems, expos, N, c =  8)
  of  9: multiExpImpl_reference_vartime(r, elems, expos, N, c =  9)
  of 10: multiExpImpl_reference_vartime(r, elems, expos, N, c = 10)
  of 11: multiExpImpl_reference_vartime(r, elems, expos, N, c = 11)
  of 12: multiExpImpl_reference_vartime(r, elems, expos, N, c = 12)
  of 13: multiExpImpl_reference_vartime(r, elems, expos, N, c = 13)
  of 14: multiExpImpl_reference_vartime(r, elems, expos, N, c = 14)
  of 15: multiExpImpl_reference_vartime(r, elems, expos, N, c = 15)

  of 16..20: multiExpImpl_reference_vartime(r, elems, expos, N, c = 16)
  else:
    unreachable()

func multiExp_reference_vartime*[bits: static int, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       expos: ptr UncheckedArray[BigInt[bits]],
       N: int, useTorus: static bool = false) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  when useTorus:
    static: doAssert Gt is QuadraticExt, "GT was: " & $Gt
    type F = typeof(elems[0].c0)
    var elemsTorus = allocHeapArrayAligned(T2Aff[F], N, alignment = 64)
    elemsTorus.toOpenArray(0, N-1).batchFromGT_vartime(
      elems.toOpenArray(0, N-1)
    )
    var r_torus {.noInit.}: T2Prj[F]
    multiExp_reference_dispatch_vartime(r_torus, elemsTorus, expos, N)
    r.fromTorus2_vartime(r_torus)
    elemsTorus.freeHeapAligned()
  else:
    multiExp_reference_dispatch_vartime(r, elems, expos, N)

func multiExp_reference_vartime*[Gt](
      r: var Gt,
      elems: openArray[Gt],
      expos: openArray[BigInt],
      useTorus: static bool = false) {.tags:[VarTime, HeapAlloc].} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert expos.len == elems.len
  let N = elems.len
  multiExp_reference_vartime(r, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)

func multiExp_reference_vartime*[F, Gt](
       r: var Gt,
       elems: ptr UncheckedArray[Gt],
       expos: ptr UncheckedArray[F],
       len: int,
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let n = cast[int](len)
  let expos_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)
  expos_big.batchFromField(expos, n)
  r.multiExp_reference_vartime(elems, expos_big, n, useTorus)

  expos_big.freeHeapAligned()

func multiExp_reference_vartime*[Gt](
       r: var Gt,
       elems: openArray[Gt],
       expos: openArray[Fr],
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert expos.len == elems.len
  let N = elems.len
  multiExp_reference_vartime(r, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)

# ########################################################### #
#                                                             #
#                 Multi-exponentiations in 𝔾ₜ                 #
#                     Optimized version                       #
#                                                             #
# ########################################################### #

func accumulate[GtAcc, GtElt](buckets: ptr UncheckedArray[GtAcc], val: SecretWord, negate: SecretBool, elem: GtElt) {.inline, meter.} =
  let val = BaseType(val)
  if val == 0: # Skip g⁰
    return
  elif negate.bool:
    buckets[val-1] ~/= elem
  else:
    buckets[val-1] ~*= elem

func bucketReduce[GtAcc](r: var GtAcc, buckets: ptr UncheckedArray[GtAcc], numBuckets: static int) {.meter.} =
  # We interleave reduction with one-ing the bucket to use instruction-level parallelism

  var accumBuckets{.noInit.}: typeof(r)
  accumBuckets = buckets[numBuckets-1]
  r = buckets[numBuckets-1]
  buckets[numBuckets-1].setNeutral()

  for k in countdown(numBuckets-2, 0):
    accumBuckets ~*= buckets[k]
    r ~*= accumBuckets
    buckets[k].setNeutral()

type MiniMultiExpKind* = enum
  kTopWindow
  kFullWindow
  kBottomWindow

func bucketAccumReduce[bits: static int, GtAcc, GtElt](
       r: var GtAcc,
       buckets: ptr UncheckedArray[GtAcc],
       bitIndex: int, miniMultiExpKind: static MiniMultiExpKind, c: static int,
       elems: ptr UncheckedArray[GtElt], expos: ptr UncheckedArray[BigInt[bits]], N: int) =

  const excess = bits mod c
  const top = bits - excess

  # 1. Bucket Accumulation
  var curVal, nextVal: SecretWord
  var curNeg, nextNeg: SecretBool

  template getSignedWindow(j : int): tuple[val: SecretWord, neg: SecretBool] =
    when miniMultiExpKind == kBottomWindow: expos[j].getSignedBottomWindow(c)
    elif miniMultiExpKind == kTopWindow:    expos[j].getSignedTopWindow(top, excess)
    else:                                   expos[j].getSignedFullWindowAt(bitIndex, c)

  (curVal, curNeg) = getSignedWindow(0)
  for j in 0 ..< N-1:
    (nextVal, nextNeg) = getSignedWindow(j+1)
    if nextVal.BaseType != 0:
      # In cryptography, points are indistinguishable from random
      # hence, without prefetching, accessing the next bucket is a guaranteed cache miss
      prefetchLarge(buckets[nextVal.BaseType-1].addr, Write, HighTemporalLocality, maxCacheLines = 2)
    buckets.accumulate(curVal, curNeg, elems[j])
    curVal = nextVal
    curNeg = nextNeg
  buckets.accumulate(curVal, curNeg, elems[N-1])

  # 2. Bucket Reduction
  r.bucketReduce(buckets, numBuckets = 1 shl (c-1))

func miniMultiExp[bits: static int, GtAcc, GtElt](
       r: var GtAcc,
       buckets: ptr UncheckedArray[GtAcc],
       bitIndex: int, miniMultiExpKind: static MiniMultiExpKind, c: static int,
       elems: ptr UncheckedArray[GtElt], expos: ptr UncheckedArray[BigInt[bits]], N: int) {.meter.} =
  ## Apply a mini-Multi-Exponentiation on [bitIndex, bitIndex+window)
  ## slice of all (coef, point) pairs

  var windowProd{.noInit.}: typeof(r)
  windowProd.bucketAccumReduce(
    buckets, bitIndex, miniMultiExpKind, c,
    elems, expos, N)

  # 3. Mini-MultiExp on the slice [bitIndex, bitIndex+window)
  r ~*= windowProd
  when miniMultiExpKind != kBottomWindow:
    for _ in 0 ..< c:
      r.cyclotomic_square()

func multiExpImpl_vartime[bits: static int, GtAcc, GtElt](
       r: var GtAcc,
       elems: ptr UncheckedArray[GtElt], expos: ptr UncheckedArray[BigInt[bits]],
       N: int, c: static int) {.tags:[VarTime, HeapAlloc], meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ

  # Setup
  # -----
  const numBuckets = 1 shl (c-1)

  let buckets = allocHeapArrayAligned(GtAcc, numBuckets, alignment = 64)
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
      r.miniMultiExp(buckets, w, kTopWindow, c, elems, expos, N)
      w -= c
    else:
      # If c divides bits exactly, the signed windowed recoding still needs to see an extra 0
      # Since we did r.setNeutral() earlier, this is a no-op
      discard

  while w != 0:       # Steady state
    r.miniMultiExp(buckets, w, kFullWindow, c, elems, expos, N)
    w -= c

  block:              # Epilogue
    r.miniMultiExp(buckets, w, kBottomWindow, c, elems, expos, N)

  # Cleanup
  # -------
  buckets.freeHeapAligned()

# Endomorphism acceleration
# -----------------------------------------------------------------------------------------------------------------------

proc applyEndomorphism[bits: static int, GT](
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

  for i in 0 ..< N:
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
           r: var GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           N: int, c: static int) =
  when Gt.Name.hasEndomorphismAcceleration() and
        EndomorphismThreshold <= exponentsBits and
        exponentsBits <= Fr[Gt.Name].bits():
    let (endoElems, endoExpos, endoN) = applyEndomorphism(elems, expos, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # TODO: bench
    multiExpProc(r, endoElems, endoExpos, endoN, c)
    endoElems.freeHeapAligned()
    endoExpos.freeHeapAligned()
  else:
    multiExpProc(r, elems, expos, N, c)

# Torus acceleration
# -----------------------------------------------------------------------------------------------------------------------

template withTorus[exponentsBits: static int, GT](
           multiExpProc: untyped,
           r: var GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           len: int, c: static int) =
  static: doAssert Gt is QuadraticExt, "GT was: " & $Gt
  type F = typeof(elems[0].c0)
  var elemsTorus = allocHeapArrayAligned(T2Aff[F], len, alignment = 64)
  batchFromGT_vartime(
    elemsTorus.toOpenArray(0, len-1),
    elems.toOpenArray(0, len-1))
  var r_torus {.noInit.}: T2Prj[F]
  multiExpProc(r_torus, elemsTorus, expos, len, c)
  r.fromTorus2_vartime(r_torus)
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

template withEndoTorus[exponentsBits: static int, GT](
           multiExpProc: untyped,
           r: var GT,
           elems: ptr UncheckedArray[GT],
           expos: ptr UncheckedArray[BigInt[exponentsBits]],
           N: int, c: static int) =
  when Gt.Name.hasEndomorphismAcceleration() and
        EndomorphismThreshold <= exponentsBits and
        exponentsBits <= Fr[Gt.Name].bits():
    let (endoElems, endoExpos, endoN) = applyEndomorphism(elems, expos, N)
    # Given that bits and N changed, we are able to use a bigger `c`
    # TODO: bench
    withTorus(multiExpProc, r, endoElems, endoExpos, endoN, c)
    endoElems.freeHeapAligned()
    endoExpos.freeHeapAligned()
  else:
    withTorus(multiExpProc, r, elems, expos, N, c)

# ########################################################### #
#                                                             #
#                 Multi-exponentiations in 𝔾ₜ                 #
#                   Algorithm selection                       #
#                                                             #
# ########################################################### #

func multiexp_dispatch_vartime[bits: static int, GT](
       r: var GT,
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
    of  2: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  2)
    of  3: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  3)
    of  4: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  4)
    of  5: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  5)
    of  6: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  6)
    of  7: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  7)
    of  8: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  8)
    of  9: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c =  9)
    of 10: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c = 10)
    of 11: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c = 11)
    of 12: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c = 12)
    of 13: withEndoTorus(multiExpImpl_vartime, r, elems, expos, N, c = 13)
    of 14: withTorus(multiExpImpl_vartime, r, elems, expos, N, c = 14)
    of 15: withTorus(multiExpImpl_vartime, r, elems, expos, N, c = 15)

    of 16..17: withTorus(multiExpImpl_vartime, r, elems, expos, N, c = 16)
    else:
      unreachable()
  else:
    case c
    of  2: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  2)
    of  3: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  3)
    of  4: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  4)
    of  5: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  5)
    of  6: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  6)
    of  7: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  7)
    of  8: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  8)
    of  9: withEndo(multiExpImpl_vartime, r, elems, expos, N, c =  9)
    of 10: withEndo(multiExpImpl_vartime, r, elems, expos, N, c = 10)
    of 11: withEndo(multiExpImpl_vartime, r, elems, expos, N, c = 11)
    of 12: withEndo(multiExpImpl_vartime, r, elems, expos, N, c = 12)
    of 13: withEndo(multiExpImpl_vartime, r, elems, expos, N, c = 13)
    of 14: multiExpImpl_vartime(r, elems, expos, N, c = 14)
    of 15: multiExpImpl_vartime(r, elems, expos, N, c = 15)

    of 16..17: multiExpImpl_vartime(r, elems, expos, N, c = 16)
    else:
      unreachable()

func multiExp_vartime*[bits: static int, GT](
       r: var GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[BigInt[bits]],
       len: int,
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  multiExp_dispatch_vartime(r, elems, expos, len, useTorus)

func multiExp_vartime*[bits: static int, GT](
       r: var GT,
       elems: openArray[GT],
       expos: openArray[BigInt[bits]],
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], meter, inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  multiExp_vartime(r, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)

func multiExp_vartime*[F, GT](
       r: var GT,
       elems: ptr UncheckedArray[GT],
       expos: ptr UncheckedArray[F],
       len: int,
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], meter.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  let n = cast[int](len)
  let expos_big = allocHeapArrayAligned(F.getBigInt(), n, alignment = 64)
  expos_big.batchFromField(expos, n)
  r.multiExp_vartime(elems, expos_big, n, useTorus)

  expos_big.freeHeapAligned()

func multiExp_vartime*[GT](
       r: var GT,
       elems: openArray[GT],
       expos: openArray[Fr],
       useTorus: static bool = false) {.tags:[VarTime, Alloca, HeapAlloc], inline.} =
  ## Multiexponentiation:
  ##   r <- g₀^a₀ + g₁^a₁ + ... + gₙ^aₙ
  debug: doAssert elems.len == expos.len
  let N = elems.len
  multiExp_vartime(r, elems.asUnchecked(), expos.asUnchecked(), N, useTorus)
