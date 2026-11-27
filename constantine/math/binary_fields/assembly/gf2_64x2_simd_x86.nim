# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  ../gf2_64,
  ./clmul_asm_x86

# ############################################################
#
#     𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1) with PCLMULQDQ and SSE2
#
# ############################################################
#
# An element c0 + c1·y is kept in one 128-bit register [c0, c1].
# A product runs in three stages, all in vector registers:
#
#   products    3 carry-less 64x64 products (Karatsuba)  ->  coefficients of y⁰, y¹, y², 128 bits each
#   y-fold      y² = x·y + 1                              ->  coefficients of y⁰, y¹, 128 bits each
#   reduce      x⁶⁴ = x⁴ + x³ + x + 1                     ->  coefficients of y⁰, y¹, 64 bits each
#
# The reduction works on both coefficients at once with shifts,
# using only SSE2 so that no compiler flag is needed.
#
# Port of leanVM crates/stable_prover/primitives/src/field/lanes/x86.rs,
# with an SSE2 shift in place of the SSSE3 table lookup for the reduction spill.
#
# Callers must check `hasCLMUL()` at runtime.

static: doAssert UseASM_X86_64

{.push raises: [], checks: off, inline.}

template load(a: array[2, GF2_64]): m128i =
  loadu_u128(a[0].addr)

template load(a: GF2_64Dbl): m128i =
  loadu_u128(a.limbs2x[0].addr)

template store(r: var array[2, GF2_64], v: m128i) =
  storeu_u128(r[0].addr, v)

template store(r: var GF2_64Dbl, v: m128i) =
  storeu_u128(r.limbs2x[0].addr, v)

func timesX(p: m128i): m128i =
  ## x·p for a 128-bit polynomial p of degree at most 126:
  ## a 1-bit shift across the two qwords
  or_u128(shl_u64x2(p, 1), shlBytes_u128(shr_u64x2(p, 63), 8))

func reducePair(d0, d1: m128i): m128i =
  ## [d0 mod P, d1 mod P] for two 128-bit polynomials,
  ## see `reduce` in gf2_64.nim for the derivation.
  let lo = unpacklo_u64x2(d0, d1)
  let hi = unpackhi_u64x2(d0, d1)
  let spill = xor_u128(xor_u128(shr_u64x2(hi, 63), shr_u64x2(hi, 61)), shr_u64x2(hi, 60))
  let v = xor_u128(hi, spill)
  let z = xor_u128(v, shl_u64x2(v, 1))
  xor_u128(lo, xor_u128(z, shl_u64x2(z, 3)))

func karatsuba(d0, d1: var m128i, a, b: m128i) =
  ## The y-folded product (a0 + a1·y)(b0 + b1·y), unreduced:
  ##   d0 = a0b0 + a1b1
  ##   d1 = a0b1 + a1b0 + x·a1b1 = (a0+a1)(b0+b1) + a0b0 + a1b1 + x·a1b1
  let sa = xor_u128(a, shuf_u32x4(a, 0x4E))  # [a0+a1, a0+a1]
  let sb = xor_u128(b, shuf_u32x4(b, 0x4E))
  let p0 = pclmul(a, b, 0x00)
  let p1 = pclmul(a, b, 0x11)
  let pm = pclmul(sa, sb, 0x00)
  d0 = xor_u128(p0, p1)
  d1 = xor_u128(xor_u128(pm, d0), timesX(p1))

func squares(d0, d1: var m128i, a: m128i) =
  ## The y-folded square, unreduced. Cross terms cancel in characteristic 2:
  ##   (c0 + c1·y)² = c0² + c1²·y² = (c0² + c1²) + x·c1²·y
  let s0 = pclmul(a, a, 0x00)
  let s1 = pclmul(a, a, 0x11)
  d0 = xor_u128(s0, s1)
  d1 = timesX(s1)

func prod_pclmul*(r: var array[2, GF2_64], a, b: array[2, GF2_64]) =
  ## r <- a·b. r may alias a or b.
  var d0 {.noInit.}, d1 {.noInit.}: m128i
  karatsuba(d0, d1, load(a), load(b))
  r.store(reducePair(d0, d1))

func prod2x_pclmul*(r: var array[2, GF2_64Dbl], a, b: array[2, GF2_64]) =
  ## r <- a·b, y-folded but not reduced modulo the base field polynomial
  var d0 {.noInit.}, d1 {.noInit.}: m128i
  karatsuba(d0, d1, load(a), load(b))
  r[0].store(d0)
  r[1].store(d1)

func square_pclmul*(r: var array[2, GF2_64], a: array[2, GF2_64]) =
  ## r <- a². r may alias a.
  var d0 {.noInit.}, d1 {.noInit.}: m128i
  squares(d0, d1, load(a))
  r.store(reducePair(d0, d1))

func square2x_pclmul*(r: var array[2, GF2_64Dbl], a: array[2, GF2_64]) =
  ## r <- a², y-folded but not reduced
  var d0 {.noInit.}, d1 {.noInit.}: m128i
  squares(d0, d1, load(a))
  r[0].store(d0)
  r[1].store(d1)

func prodBase_pclmul*(r: var array[2, GF2_64], a: array[2, GF2_64], b: GF2_64) =
  ## r <- a·b for b in the base field: both coefficients scale independently.
  ## r may alias a.
  let va = load(a)
  let vb = movq_to_u128(b.raw)
  r.store(reducePair(pclmul(va, vb, 0x00), pclmul(va, vb, 0x01)))

func prod2xBase_pclmul*(r: var array[2, GF2_64Dbl], a: array[2, GF2_64], b: GF2_64) =
  ## r <- a·b for b in the base field, not reduced
  let va = load(a)
  let vb = movq_to_u128(b.raw)
  r[0].store(pclmul(va, vb, 0x00))
  r[1].store(pclmul(va, vb, 0x01))

func redc2x_pclmul*(r: var array[2, GF2_64], a: array[2, GF2_64Dbl]) =
  ## Reduce both coefficients modulo the base field polynomial
  r.store(reducePair(load(a[0]), load(a[1])))

# Sums of products
# ------------------------------------------------------------
#
# Generic over the element type, which must have `coords: array[2, GF2_64]`,
# so that this module does not depend on the extension field module.
#
# The accumulators stay in vector registers and the Karatsuba recombination
# and y-fold are linear, so they are applied once to the sums:
#   Σ aᵢbᵢ = (P₀ + P₁) + (Pₘ + P₀ + P₁ + x·P₁)·y
# with P₀ = Σ a0b0, P₁ = Σ a1b1, Pₘ = Σ (a0+a1)(b0+b1), then one reduction.

template accumulate(p0, p1, pm: var m128i, va, vb: m128i) =
  let sa = xor_u128(va, shuf_u32x4(va, 0x4E))
  let sb = xor_u128(vb, shuf_u32x4(vb, 0x4E))
  p0 = xor_u128(p0, pclmul(va, vb, 0x00))
  p1 = xor_u128(p1, pclmul(va, vb, 0x11))
  pm = xor_u128(pm, pclmul(sa, sb, 0x00))

func sumprod_pclmul*[E](r: var E, a, b: openArray[E]) =
  ## r <- ∑ aᵢ·bᵢ for i < min(a.len, b.len)
  ##
  ## Two independent sets of accumulators, for even and odd terms,
  ## so that the loop is not bound by the latency of the accumulation.
  let zero = zero_u128()
  var (e0, e1, em) = (zero, zero, zero)
  var (o0, o1, om) = (zero, zero, zero)
  let n = min(a.len, b.len)
  var i = 0
  while i + 1 < n:
    accumulate(e0, e1, em, load(a[i].coords), load(b[i].coords))
    accumulate(o0, o1, om, load(a[i+1].coords), load(b[i+1].coords))
    i += 2
  if i < n:
    accumulate(e0, e1, em, load(a[i].coords), load(b[i].coords))
  let p0 = xor_u128(e0, o0)
  let p1 = xor_u128(e1, o1)
  let pm = xor_u128(em, om)
  let d0 = xor_u128(p0, p1)
  let d1 = xor_u128(xor_u128(pm, d0), timesX(p1))
  r.coords.store(reducePair(d0, d1))

func sumprodBase_pclmul*[E](r: var E, a: openArray[E], b: openArray[GF2_64]) =
  ## r <- ∑ aᵢ·bᵢ for i < min(a.len, b.len), with bᵢ in the base field
  ##
  ## Two independent sets of accumulators, for even and odd terms.
  let zero = zero_u128()
  var (e0, e1, o0, o1) = (zero, zero, zero, zero)
  let n = min(a.len, b.len)
  var i = 0
  while i + 1 < n:
    let va = load(a[i].coords)
    let vb = movq_to_u128(b[i].raw)
    let wa = load(a[i+1].coords)
    let wb = movq_to_u128(b[i+1].raw)
    e0 = xor_u128(e0, pclmul(va, vb, 0x00))
    e1 = xor_u128(e1, pclmul(va, vb, 0x01))
    o0 = xor_u128(o0, pclmul(wa, wb, 0x00))
    o1 = xor_u128(o1, pclmul(wa, wb, 0x01))
    i += 2
  if i < n:
    let va = load(a[i].coords)
    let vb = movq_to_u128(b[i].raw)
    e0 = xor_u128(e0, pclmul(va, vb, 0x00))
    e1 = xor_u128(e1, pclmul(va, vb, 0x01))
  r.coords.store(reducePair(xor_u128(e0, o0), xor_u128(e1, o1)))

{.pop.}
