# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/serialization/endians,
  constantine/math/extension_fields/[towers, exponentiations],
  ./gf2_64

when UseASM_X86_64:
  import ./assembly/gf2_64x2_simd_x86
elif UseASM_ARM64:
  import ./assembly/gf2_64x2_simd_arm64

export towers, exponentiations, gf2_64

# ############################################################
#
#     Binary field 𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1)
#
# ############################################################
#
# The extension field of leanVM (https://github.com/leanEthereum/leanVM), called E there.
# A leanVM machine word, challenges, sumcheck and transcript values live here.
#
# An element is c0 + c1·y with c0, c1 ∈ 𝔽₂⁶⁴.
# y² + xy + 1 is irreducible over 𝔽₂⁶⁴ as Tr(1/x²) = 1.
#
# This reuses Constantine's quadratic extension tower `QuadraticExt`.
# The tower's generic code (setZero, setOne, ==, isZero, ccopy, sum, diff, +=,
# csetZero, cadd, the lazy-reduced `QuadraticExt2x`, ...) applies unchanged.
#
# Only what depends on the modulus is specialized below.
# Constantine's towers assume a modulus y² = β with β a non-residue.
# That form does not exist in characteristic 2: every element is a square,
# so y² - β always has a root. Quadratic extensions take the
# Artin-Schreier form instead, here y² + xy + 1. This changes:
# - multiplication and squaring: y² folds back as x·y + 1
# - the conjugate (Frobenius), the norm and the inverse
#
# The generic tower dispatchers for those operations need a `NonResidue`,
# which 𝔽₂⁶⁴ does not define: if one of the specializations below
# were not selected, compilation would fail instead of computing a wrong value.

type
  GF2_64x2* = QuadraticExt[GF2_64]
    ## An element c0 + c1·y of 𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1)
    ##
    ## Its memory layout is [c0, c1], 16 bytes,
    ## the 128-bit little-endian integer c0 + c1·2⁶⁴ on little-endian machines.

  GF2_64x2Dbl* = QuadraticExt2x[GF2_64Dbl]
    ## A product of two 𝔽₂¹²⁸ elements, folded by y² = x·y + 1
    ## but not reduced modulo the base field polynomial.
    ## Sums of products accumulate here with XOR and are reduced once.

template doublePrec*(T: type GF2_64x2): type =
  ## The type of unreduced products
  GF2_64x2Dbl

# No exceptions allowed
{.push raises: [].}
{.push checks: off.}
{.push inline.}

template dispatch(x86, arm64, portable: untyped): untyped =
  ## Select the backend: CPU carry-less multiplication if available
  when UseASM_X86_64:
    if ({.noSideEffect.}: hasCLMUL()):
      x86
    else:
      portable
  elif UseASM_ARM64:
    if ({.noSideEffect.}: hasPmull()):
      arm64
    else:
      portable
  else:
    portable

# ############################################################
#
#                Construction and embedding
#
# ############################################################

func fromRaw*(T: type GF2_64x2, c0, c1: uint64): T {.noInit.} =
  ## The element c0 + c1·y, each coefficient given as raw bits
  result.coords[0].raw = c0
  result.coords[1].raw = c1

func fromBase*(r: var GF2_64x2, a: GF2_64) =
  ## Embed 𝔽₂⁶⁴ into 𝔽₂¹²⁸
  r.coords[0] = a
  r.coords[1].setZero()

func isBase*(a: GF2_64x2): SecretBool =
  ## Whether a belongs to the base field 𝔽₂⁶⁴, i.e. its y coefficient is 0
  a.c1.isZero()

func getZero*(T: type GF2_64x2): T {.noInit.} =
  result.setZero()

func getOne*(T: type GF2_64x2): T {.noInit.} =
  result.setOne()

# ############################################################
#
#              Conjugate (Frobenius) and norm
#
# ############################################################

func conj*(r: var GF2_64x2, a: GF2_64x2) =
  ## The Galois conjugate a^(2⁶⁴): it fixes 𝔽₂⁶⁴
  ## and maps y to the other root of y² + xy + 1, y + x:
  ##   c0 + c1·y ↦ (c0 + x·c1) + c1·y
  var t {.noInit.}: GF2_64
  t.mulByX(a.c1)
  r.c1 = a.c1
  r.c0.sum(a.c0, t)

func conj*(a: var GF2_64x2) =
  a.conj(a)

func conjneg*(r: var GF2_64x2, a: GF2_64x2) =
  ## -conj(a) = conj(a) in characteristic 2
  r.conj(a)

func conjneg*(a: var GF2_64x2) =
  a.conj(a)

func frobenius_map*(r: var GF2_64x2, a: GF2_64x2, k: static int = 1) =
  ## r <- a^(2^(64k)), the k-th power of the conjugation
  when (k and 1) == 1:
    r.conj(a)
  else:
    r = a

func norm*(r: var GF2_64, a: GF2_64x2) =
  ## The norm N(a) = a·conj(a) ∈ 𝔽₂⁶⁴:
  ##   N(c0 + c1·y) = c0² + x·c0·c1 + c1²
  ## computed unreduced and reduced once.
  var acc {.noInit.}, t {.noInit.}: GF2_64Dbl
  acc.prod2x(a.c0, a.c1)
  acc.mulByX(acc)  # degree ≤ 127, fits
  t.square2x(a.c0)
  acc += t
  t.square2x(a.c1)
  acc += t
  r.redc2x(acc)

# ############################################################
#
#                  Portable backend
#
# ############################################################
#
# Without CPU extensions, for testing and benchmarking.
# Use `prod`, `square`, ... which dispatch to the fastest backend.

func prod2x_portable*(r: var GF2_64x2Dbl, a, b: GF2_64x2) =
  ## r <- a·b, y-folded but not reduced, by Karatsuba:
  ##   c0 = a0b0 + a1b1
  ##   c1 = (a0+a1)(b0+b1) + a0b0 + a1b1 + x·a1b1
  var p0 {.noInit.}, p1 {.noInit.}, pm {.noInit.}: GF2_64Dbl
  var sa {.noInit.}, sb {.noInit.}: GF2_64
  p0.prod2x_portable(a.c0, b.c0)
  p1.prod2x_portable(a.c1, b.c1)
  sa.sum(a.c0, a.c1)
  sb.sum(b.c0, b.c1)
  pm.prod2x_portable(sa, sb)

  r.c0.sum2xUnr(p0, p1)
  r.c1.sum2xUnr(pm, r.c0)
  p1.mulByX(p1)
  r.c1 += p1

func square2x_portable*(r: var GF2_64x2Dbl, a: GF2_64x2) =
  ## r <- a², y-folded but not reduced:
  ##   (c0 + c1·y)² = (c0² + c1²) + x·c1²·y
  var s0 {.noInit.}, s1 {.noInit.}: GF2_64Dbl
  s0.square2x_portable(a.c0)
  s1.square2x_portable(a.c1)
  r.c0.sum2xUnr(s0, s1)
  r.c1.mulByX(s1)

func prod_portable*(r: var GF2_64x2, a, b: GF2_64x2) =
  var d {.noInit.}: GF2_64x2Dbl
  d.prod2x_portable(a, b)
  r.c0.redc2x(d.c0)
  r.c1.redc2x(d.c1)

func square_portable*(r: var GF2_64x2, a: GF2_64x2) =
  var d {.noInit.}: GF2_64x2Dbl
  d.square2x_portable(a)
  r.c0.redc2x(d.c0)
  r.c1.redc2x(d.c1)

func prod_portable*(r: var GF2_64x2, a: GF2_64x2, b: GF2_64) =
  r.c0.prod_portable(a.c0, b)
  r.c1.prod_portable(a.c1, b)

func prod2x_portable*(r: var GF2_64x2Dbl, a: GF2_64x2, b: GF2_64) =
  r.c0.prod2x_portable(a.c0, b)
  r.c1.prod2x_portable(a.c1, b)

# ############################################################
#
#               Multiplication and squaring
#
# ############################################################

func prod*(r: var GF2_64x2, a, b: GF2_64x2) {.meter.} =
  ## r <- a·b. r may alias a or b.
  dispatch(
    r.coords.prod_pclmul(a.coords, b.coords),
    r.coords.prod_pmull(a.coords, b.coords),
    r.prod_portable(a, b))

func prod*(r: var GF2_64x2, a, b: GF2_64x2, lazyReduce: static bool) =
  ## Alias for generic code written for prime fields
  r.prod(a, b)

func `*=`*(a: var GF2_64x2, b: GF2_64x2) =
  a.prod(a, b)

func square*(r: var GF2_64x2, a: GF2_64x2) {.meter.} =
  ## r <- a². r may alias a.
  dispatch(
    r.coords.square_pclmul(a.coords),
    r.coords.square_pmull(a.coords),
    r.square_portable(a))

func square*(a: var GF2_64x2) =
  a.square(a)

func square*(r: var GF2_64x2, a: GF2_64x2, lazyReduce: static bool) =
  r.square(a)

func square*(a: var GF2_64x2, lazyReduce: static bool) =
  a.square(a)

func square_repeated*(a: var GF2_64x2, num: int) =
  ## a <- a^(2^num)
  for _ in 0 ..< num:
    a.square()

func square_repeated*(r: var GF2_64x2, a: GF2_64x2, num: int) =
  ## r <- a^(2^num)
  r = a
  r.square_repeated(num)

func prod*(r: var GF2_64x2, a: GF2_64x2, b: GF2_64) {.meter.} =
  ## r <- a·b for b in the base field. r may alias a.
  dispatch(
    r.coords.prodBase_pclmul(a.coords, b),
    r.coords.prodBase_pmull(a.coords, b),
    r.prod_portable(a, b))

func `*=`*(a: var GF2_64x2, b: GF2_64) =
  a.prod(a, b)

# ############################################################
#
#               Unreduced (double-width) products
#
# ############################################################

func `+=`*(a: var GF2_64x2Dbl, b: GF2_64x2Dbl) =
  a.c0 += b.c0
  a.c1 += b.c1

func prod2x*(r: var GF2_64x2Dbl, a, b: GF2_64x2) =
  ## r <- a·b, y-folded but not reduced
  dispatch(
    r.coords.prod2x_pclmul(a.coords, b.coords),
    r.coords.prod2x_pmull(a.coords, b.coords),
    r.prod2x_portable(a, b))

func square2x*(r: var GF2_64x2Dbl, a: GF2_64x2) =
  ## r <- a², y-folded but not reduced
  dispatch(
    r.coords.square2x_pclmul(a.coords),
    r.coords.square2x_pmull(a.coords),
    r.square2x_portable(a))

func prod2x*(r: var GF2_64x2Dbl, a: GF2_64x2, b: GF2_64) =
  ## r <- a·b for b in the base field, not reduced
  dispatch(
    r.coords.prod2xBase_pclmul(a.coords, b),
    r.coords.prod2xBase_pmull(a.coords, b),
    r.prod2x_portable(a, b))

func redc2x*(r: var GF2_64x2, a: GF2_64x2Dbl) =
  ## Reduce both coefficients modulo the base field polynomial
  dispatch(
    r.coords.redc2x_pclmul(a.coords),
    r.coords.redc2x_pmull(a.coords),
    (r.c0.redc2x(a.c0); r.c1.redc2x(a.c1)))

func sumprod_portable*(r: var GF2_64x2, a, b: openArray[GF2_64x2]) =
  ## r <- ∑ aᵢ·bᵢ with a single reduction, without CPU extensions
  var acc {.noInit.}, t {.noInit.}: GF2_64x2Dbl
  acc.setZero()
  for i in 0 ..< min(a.len, b.len):
    t.prod2x_portable(a[i], b[i])
    acc += t
  r.c0.redc2x(acc.c0)
  r.c1.redc2x(acc.c1)

func sumprod_portable*(r: var GF2_64x2, a: openArray[GF2_64x2], b: openArray[GF2_64]) =
  ## r <- ∑ aᵢ·bᵢ with bᵢ in the base field and a single reduction, without CPU extensions
  var acc {.noInit.}, t {.noInit.}: GF2_64x2Dbl
  acc.setZero()
  for i in 0 ..< min(a.len, b.len):
    t.prod2x_portable(a[i], b[i])
    acc += t
  r.c0.redc2x(acc.c0)
  r.c1.redc2x(acc.c1)

func sumprod*(r: var GF2_64x2, a, b: openArray[GF2_64x2]) {.meter.} =
  ## r <- ∑ aᵢ·bᵢ with a single reduction: a dot product.
  ## a and b must have the same length, the empty sum is 0.
  debug: doAssert a.len == b.len
  dispatch(
    r.sumprod_pclmul(a, b),
    r.sumprod_pmull(a, b),
    r.sumprod_portable(a, b))

func sumprod*(r: var GF2_64x2, a: openArray[GF2_64x2], b: openArray[GF2_64]) {.meter.} =
  ## r <- ∑ aᵢ·bᵢ with bᵢ in the base field and a single reduction.
  ## a and b must have the same length, the empty sum is 0.
  debug: doAssert a.len == b.len
  dispatch(
    r.sumprodBase_pclmul(a, b),
    r.sumprodBase_pmull(a, b),
    r.sumprod_portable(a, b))

func sumprod*[N: static int](r: var GF2_64x2, a, b: array[N, GF2_64x2]) =
  ## r <- ∑ aᵢ·bᵢ with a single reduction
  r.sumprod(a.toOpenArray(0, N-1), b.toOpenArray(0, N-1))

# ############################################################
#
#                      Inversion
#
# ############################################################

func inv*(r: var GF2_64x2, a: GF2_64x2) {.meter.} =
  ## r <- a⁻¹ = conj(a)·N(a)⁻¹, as a·conj(a) = N(a) ∈ 𝔽₂⁶⁴.
  ## The inverse of 0 is 0.
  var n {.noInit.}: GF2_64
  n.norm(a)
  n.inv()
  var c {.noInit.}: GF2_64x2
  c.conj(a)
  r.prod(c, n)

func inv*(a: var GF2_64x2) =
  a.inv(a)

func inv_vartime*(r: var GF2_64x2, a: GF2_64x2) {.tags: [VarTime].} =
  ## The constant-time inversion is as fast, this is an alias for generic code
  r.inv(a)

func inv_vartime*(a: var GF2_64x2) {.tags: [VarTime].} =
  a.inv(a)

{.pop.} # inline

# ############################################################
#
#                    Exponentiation
#
# ############################################################

func pow_vartime*(a: var (GF2_64 or GF2_64x2), exponent: uint64) {.tags: [VarTime].} =
  ## a <- a^exponent for a public exponent,
  ## with Constantine's generic windowed exponentiation.
  ##
  ## For example xⁱ, the powers of the generator that leanVM uses
  ## to encode indices and domain separators.
  let e = exponent.toBytes(bigEndian)
  a.pow_vartime(e, window = 3)

# ############################################################
#
#                 Out-of-place functions
#
# ############################################################
#
# `+`, `-` and `*` for prototyping, testing and debugging
# are provided by the generic tower code.

{.pop.} # checks
{.pop.} # raises
