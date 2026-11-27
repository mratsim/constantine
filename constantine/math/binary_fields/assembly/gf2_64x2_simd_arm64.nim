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
  ./clmul_asm_arm64

# ############################################################
#
#     𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1) with PMULL and NEON
#
# ############################################################
#
# An element c0 + c1·y is kept in one 128-bit register [c0, c1].
# A product runs in three stages, all in vector registers:
#
#   products    4 carry-less 64x64 products  ->  coefficients of y⁰, y¹, y², 128 bits each
#   y-fold      y² = x·y + 1                 ->  coefficients of y⁰, y¹, 128 bits each
#   reduce      x⁶⁴ = x⁴ + x³ + x + 1        ->  coefficients of y⁰, y¹, 64 bits each
#
# The y-fold multiplies the y² coefficient by x, a 1-bit shift that stays within 128 bits
# as a 64x64 carry-less product has degree at most 126.
#
# Port of leanVM crates/stable_prover/primitives/src/field/lanes/neon.rs
#
# Callers must check `hasPmull()` at runtime.

static: doAssert UseASM_ARM64

{.push raises: [], checks: off, inline.}

template load(a: array[2, GF2_64]): uint64x2_t =
  vld1q_u64(a[0].addr)

template load(a: GF2_64Dbl): uint64x2_t =
  vld1q_u64(a.limbs2x[0].addr)

template store(r: var array[2, GF2_64], v: uint64x2_t) =
  vst1q_u64(r[0].addr, v)

template store(r: var GF2_64Dbl, v: uint64x2_t) =
  vst1q_u64(r.limbs2x[0].addr, v)

func timesX(p: uint64x2_t): uint64x2_t =
  ## x·p for a 128-bit polynomial p of degree at most 126:
  ## a 1-bit shift across the two lanes
  vorrq_u64(vshlq_n_u64(p, 1), vextq_u64(vdupq_n_u64(0), vshrq_n_u64(p, 63), 1))

func reduceLane(d, poly: uint64x2_t): uint64x2_t =
  ## Reduce the 128-bit polynomial d = lo + hi·x⁶⁴ into the low lane.
  ## poly holds 0x1B (x⁶⁴ mod the field polynomial) in its high lane.
  ##
  ## hi·0x1B = [t, s] with s of at most 4 bits, s·0x1B = [u, 0],
  ## and the reduced value is lo ⊕ t ⊕ u. The high lane is garbage.
  let t = pmull_hi(d, poly)
  veorq_u64(d, veorq_u64(t, pmull_hi(t, poly)))

func reducePair(d0, d1: uint64x2_t): uint64x2_t =
  ## [d0 mod P, d1 mod P]
  let poly = vdupq_n_u64(0x1B)
  vzip1q_u64(reduceLane(d0, poly), reduceLane(d1, poly))

func schoolbook(d0, d1: var uint64x2_t, a, b: uint64x2_t) =
  ## The y-folded product (a0 + a1·y)(b0 + b1·y), unreduced:
  ##   d0 = a0b0 + a1b1
  ##   d1 = a0b1 + a1b0 + x·a1b1
  let swapped = vextq_u64(a, a, 1)  # [a1, a0]
  let m00 = pmull_lo(a, b)
  let m11 = pmull_hi(a, b)
  let m10 = pmull_lo(swapped, b)    # a1·b0
  let m01 = pmull_hi(swapped, b)    # a0·b1
  d0 = veorq_u64(m00, m11)
  d1 = veorq_u64(veorq_u64(m01, m10), timesX(m11))

func squares(d0, d1: var uint64x2_t, a: uint64x2_t) =
  ## The y-folded square, unreduced. Cross terms cancel in characteristic 2:
  ##   (c0 + c1·y)² = c0² + c1²·y² = (c0² + c1²) + x·c1²·y
  let s0 = pmull_lo(a, a)
  let s1 = pmull_hi(a, a)
  d0 = veorq_u64(s0, s1)
  d1 = timesX(s1)

func prod_pmull*(r: var array[2, GF2_64], a, b: array[2, GF2_64]) =
  ## r <- a·b. r may alias a or b.
  var d0 {.noInit.}, d1 {.noInit.}: uint64x2_t
  schoolbook(d0, d1, load(a), load(b))
  r.store(reducePair(d0, d1))

func prod2x_pmull*(r: var array[2, GF2_64Dbl], a, b: array[2, GF2_64]) =
  ## r <- a·b, y-folded but not reduced modulo the base field polynomial
  var d0 {.noInit.}, d1 {.noInit.}: uint64x2_t
  schoolbook(d0, d1, load(a), load(b))
  r[0].store(d0)
  r[1].store(d1)

func square_pmull*(r: var array[2, GF2_64], a: array[2, GF2_64]) =
  ## r <- a². r may alias a.
  var d0 {.noInit.}, d1 {.noInit.}: uint64x2_t
  squares(d0, d1, load(a))
  r.store(reducePair(d0, d1))

func square2x_pmull*(r: var array[2, GF2_64Dbl], a: array[2, GF2_64]) =
  ## r <- a², y-folded but not reduced
  var d0 {.noInit.}, d1 {.noInit.}: uint64x2_t
  squares(d0, d1, load(a))
  r[0].store(d0)
  r[1].store(d1)

func prodBase_pmull*(r: var array[2, GF2_64], a: array[2, GF2_64], b: GF2_64) =
  ## r <- a·b for b in the base field: both coefficients scale independently.
  ## r may alias a.
  let va = load(a)
  let vb = vdupq_n_u64(b.raw)
  r.store(reducePair(pmull_lo(va, vb), pmull_hi(va, vb)))

func prod2xBase_pmull*(r: var array[2, GF2_64Dbl], a: array[2, GF2_64], b: GF2_64) =
  ## r <- a·b for b in the base field, not reduced
  let va = load(a)
  let vb = vdupq_n_u64(b.raw)
  r[0].store(pmull_lo(va, vb))
  r[1].store(pmull_hi(va, vb))

func redc2x_pmull*(r: var array[2, GF2_64], a: array[2, GF2_64Dbl]) =
  ## Reduce both coefficients modulo the base field polynomial
  r.store(reducePair(load(a[0]), load(a[1])))

# Sums of products
# ------------------------------------------------------------
#
# Generic over the element type, which must have `coords: array[2, GF2_64]`,
# so that this module does not depend on the extension field module.
#
# The accumulators stay in vector registers and both folds are linear,
# so they are applied once to the sums instead of once per term:
#   Σ aᵢbᵢ = (A₀₀ + A₁₁) + (A₀₁ + x·A₁₁)·y
# with A₀₀ = Σ a0b0, A₁₁ = Σ a1b1, A₀₁ = Σ (a0b1 + a1b0), then one reduction.

template accumulate(a00, a11, a01: var uint64x2_t, va, vb: uint64x2_t) =
  let swapped = vextq_u64(va, va, 1)  # [a1, a0]
  a00 = veorq_u64(a00, pmull_lo(va, vb))
  a11 = veorq_u64(a11, pmull_hi(va, vb))
  a01 = veorq_u64(a01, veorq_u64(pmull_lo(swapped, vb), pmull_hi(swapped, vb)))

func sumprod_pmull*[E](r: var E, a, b: openArray[E]) =
  ## r <- ∑ aᵢ·bᵢ for i < min(a.len, b.len)
  ##
  ## Two independent sets of accumulators, for even and odd terms,
  ## so that the loop is not bound by the latency of the accumulation.
  let zero = vdupq_n_u64(0)
  var (e00, e11, e01) = (zero, zero, zero)
  var (o00, o11, o01) = (zero, zero, zero)
  let n = min(a.len, b.len)
  var i = 0
  while i + 1 < n:
    accumulate(e00, e11, e01, load(a[i].coords), load(b[i].coords))
    accumulate(o00, o11, o01, load(a[i+1].coords), load(b[i+1].coords))
    i += 2
  if i < n:
    accumulate(e00, e11, e01, load(a[i].coords), load(b[i].coords))
  let a00 = veorq_u64(e00, o00)
  let a11 = veorq_u64(e11, o11)
  let a01 = veorq_u64(e01, o01)
  let d0 = veorq_u64(a00, a11)
  let d1 = veorq_u64(a01, timesX(a11))
  r.coords.store(reducePair(d0, d1))

func sumprodBase_pmull*[E](r: var E, a: openArray[E], b: openArray[GF2_64]) =
  ## r <- ∑ aᵢ·bᵢ for i < min(a.len, b.len), with bᵢ in the base field
  ##
  ## Two independent sets of accumulators, for even and odd terms.
  let zero = vdupq_n_u64(0)
  var (e0, e1, o0, o1) = (zero, zero, zero, zero)
  let n = min(a.len, b.len)
  var i = 0
  while i + 1 < n:
    let va = load(a[i].coords)
    let vb = vdupq_n_u64(b[i].raw)
    let wa = load(a[i+1].coords)
    let wb = vdupq_n_u64(b[i+1].raw)
    e0 = veorq_u64(e0, pmull_lo(va, vb))
    e1 = veorq_u64(e1, pmull_hi(va, vb))
    o0 = veorq_u64(o0, pmull_lo(wa, wb))
    o1 = veorq_u64(o1, pmull_hi(wa, wb))
    i += 2
  if i < n:
    let va = load(a[i].coords)
    let vb = vdupq_n_u64(b[i].raw)
    e0 = veorq_u64(e0, pmull_lo(va, vb))
    e1 = veorq_u64(e1, pmull_hi(va, vb))
  r.coords.store(reducePair(veorq_u64(e0, o0), veorq_u64(e1, o1)))

{.pop.}
