# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions

when UseASM_X86_64:
  import ./assembly/clmul_asm_x86
elif UseASM_ARM64:
  import ./assembly/clmul_asm_arm64

# ############################################################
#
#      Binary field 𝔽₂⁶⁴ = 𝔽₂[x]/(x⁶⁴ + x⁴ + x³ + x + 1)
#
# ############################################################
#
# The base field of leanVM (https://github.com/leanEthereum/leanVM), called K there.
#
# An element is a polynomial of degree < 64 over 𝔽₂, stored as 64 bits,
# bit i being the coefficient of xⁱ.
# - Addition is XOR: there are no carries and every element is its own negative.
# - Multiplication is a carry-less product followed by a reduction modulo
#   x⁶⁴ + x⁴ + x³ + x + 1, an irreducible polynomial.
#   x has multiplicative order 2⁶⁴ - 1, it generates 𝔽₂⁶⁴*.
#
# The carry-less product uses PCLMULQDQ on x86-64 and PMULL on ARM64
# when the CPU supports them, and a constant-time portable fallback otherwise.
#
# All operations are constant-time.
#
# The API follows Constantine's prime fields (`prod`, `square`, `inv`, `csetZero`, ...)
# so that generic code, for example `batchInv` or `MultilinearExtension`,
# can be instantiated with binary fields.

type
  GF2_64* = object
    ## An element of 𝔽₂⁶⁴ = 𝔽₂[x]/(x⁶⁴ + x⁴ + x³ + x + 1).
    ## Bit i of `raw` is the coefficient of xⁱ.
    raw*: uint64

  GF2_64Dbl* = object
    ## A carry-less product of two 𝔽₂⁶⁴ elements, not yet reduced:
    ## a polynomial of degree at most 126 stored as [low 64 bits, high 64 bits].
    ##
    ## The reduction is 𝔽₂-linear, so sums of products can be accumulated
    ## with XOR in this form and reduced once.
    limbs2x*: array[2, uint64]

const ReductionPoly = 0x1B'u64
  ## x⁶⁴ ≡ x⁴ + x³ + x + 1 (mod the field polynomial)

template doublePrec*(T: type GF2_64): type =
  ## The type of unreduced products
  GF2_64Dbl

# No exceptions allowed
{.push raises: [].}
{.push checks: off.}
{.push inline.}

# ############################################################
#
#               Constant-time word helpers
#
# ############################################################

template mask64(ctl: SecretBool): uint64 =
  ## All ones if ctl is true, all zeros otherwise
  0'u64 - uint64(BaseType(SecretWord(ctl)))

func isZeroWord(x: uint64): SecretBool =
  when sizeof(BaseType) == 8:
    SecretWord(x).isZero()
  else:
    SecretWord(BaseType(x) or BaseType(x shr 32)).isZero()

# ############################################################
#
#               Carry-less multiplication
#
# ############################################################

func clmulLow_portable(a, b: uint64): uint64 =
  ## The low 64 bits of the carry-less product a ⊗ b, by integer multiplication.
  ##
  ## Both operands are split into the four classes of their bit positions mod 4.
  ## A product of two classes only has bits in a single class,
  ## and a coefficient there sums at most 16 bit products (15 below bit 60).
  ## Carries out of a 4-bit group therefore never reach the next bit of the same class,
  ## except above bit 60 where they leave the 64-bit word,
  ## and masking each class keeps the parities.
  ##
  ## Credit: Thomas Pornin, BearSSL constant-time GHASH (ghash_ctmul64)
  ##         and the leanVM verifier (crates/verifier/src/field.rs)
  const
    M0 = 0x1111_1111_1111_1111'u64
    M1 = M0 shl 1
    M2 = M0 shl 2
    M3 = M0 shl 3
  let
    x0 = a and M0
    x1 = a and M1
    x2 = a and M2
    x3 = a and M3
    y0 = b and M0
    y1 = b and M1
    y2 = b and M2
    y3 = b and M3
    z0 = (x0 * y0) xor (x1 * y3) xor (x2 * y2) xor (x3 * y1)
    z1 = (x0 * y1) xor (x1 * y0) xor (x2 * y3) xor (x3 * y2)
    z2 = (x0 * y2) xor (x1 * y1) xor (x2 * y0) xor (x3 * y3)
    z3 = (x0 * y3) xor (x1 * y2) xor (x2 * y1) xor (x3 * y0)
  return (z0 and M0) or (z1 and M1) or (z2 and M2) or (z3 and M3)

func clmul_portable*(hi, lo: var uint64, a, b: uint64) =
  ## (hi, lo) <- a ⊗ b, the 128-bit carry-less product, without CPU extensions
  ##
  ## The high half is the low half of the bit-reversed operands' product, reversed back.
  lo = clmulLow_portable(a, b)
  hi = reverseBits(clmulLow_portable(reverseBits(a, 64), reverseBits(b, 64)), 64) shr 1

func spread32(x: uint64): uint64 =
  ## Interleave the low 32 bits of x with zeros: bit i moves to bit 2i
  var x = x and 0xFFFF_FFFF'u64
  x = (x or (x shl 16)) and 0x0000_FFFF_0000_FFFF'u64
  x = (x or (x shl 8))  and 0x00FF_00FF_00FF_00FF'u64
  x = (x or (x shl 4))  and 0x0F0F_0F0F_0F0F_0F0F'u64
  x = (x or (x shl 2))  and 0x3333_3333_3333_3333'u64
  x = (x or (x shl 1))  and 0x5555_5555_5555_5555'u64
  return x

func clsquare_portable*(hi, lo: var uint64, a: uint64) =
  ## (hi, lo) <- a ⊗ a. The cross terms cancel in characteristic 2,
  ## so the square spreads the bits of `a` to the even positions.
  lo = spread32(a)
  hi = spread32(a shr 32)

func hasClmulHardware*(): bool =
  ## Whether `clmul` uses a CPU instruction (PCLMULQDQ or PMULL)
  ## rather than the portable fallback
  when UseASM_X86_64:
    return ({.noSideEffect.}: hasCLMUL())
  elif UseASM_ARM64:
    return ({.noSideEffect.}: hasPmull())
  else:
    return false

func clmul*(hi, lo: var uint64, a, b: uint64) =
  ## (hi, lo) <- a ⊗ b, the 128-bit carry-less product of 64-bit polynomials over 𝔽₂
  when UseASM_X86_64:
    if ({.noSideEffect.}: hasCLMUL()):
      clmul_x86(hi, lo, a, b)
    else:
      clmul_portable(hi, lo, a, b)
  elif UseASM_ARM64:
    if ({.noSideEffect.}: hasPmull()):
      clmul_arm64(hi, lo, a, b)
    else:
      clmul_portable(hi, lo, a, b)
  else:
    clmul_portable(hi, lo, a, b)

func clsquare*(hi, lo: var uint64, a: uint64) =
  ## (hi, lo) <- a ⊗ a
  when UseASM_X86_64:
    if ({.noSideEffect.}: hasCLMUL()):
      clmul_x86(hi, lo, a, a)
    else:
      clsquare_portable(hi, lo, a)
  elif UseASM_ARM64:
    if ({.noSideEffect.}: hasPmull()):
      clsquare_arm64(hi, lo, a)
    else:
      clsquare_portable(hi, lo, a)
  else:
    clsquare_portable(hi, lo, a)

func reduce*(hi, lo: uint64): uint64 =
  ## Reduce the 128-bit polynomial lo + hi·x⁶⁴ modulo x⁶⁴ + x⁴ + x³ + x + 1.
  ##
  ## Substituting x⁶⁴ = x⁴ + x³ + x + 1 gives hi·x⁶⁴ ≡ f(hi) = hi ⊕ hi≪1 ⊕ hi≪3 ⊕ hi≪4,
  ## a 68-bit value whose 4 bits past x⁶³ are spill = hi≫63 ⊕ hi≫61 ⊕ hi≫60.
  ## Folding the spill once more fits in 8 bits and is final.
  ## As f truncated to 64 bits is 𝔽₂-linear, both folds merge:
  ##   result = lo ⊕ f(hi ⊕ spill) (mod 2⁶⁴)
  let spill = (hi shr 63) xor (hi shr 61) xor (hi shr 60)
  let v = hi xor spill
  let z = v xor (v shl 1)
  return lo xor z xor (z shl 3)

# ############################################################
#
#                    Initialization
#
# ############################################################

func setZero*(a: var GF2_64) =
  a.raw = 0

func setOne*(a: var GF2_64) =
  a.raw = 1

func setMinusOne*(a: var GF2_64) =
  ## -1 = 1 in characteristic 2
  a.raw = 1

func getZero*(T: type GF2_64): T {.noInit.} =
  result.setZero()

func getOne*(T: type GF2_64): T {.noInit.} =
  result.setOne()

func fromRaw*(T: type GF2_64, raw: uint64): T {.noInit.} =
  ## The element whose coefficient of xⁱ is bit i of `raw`
  result.raw = raw

func generator*(T: type GF2_64): T {.noInit.} =
  ## x, a generator of 𝔽₂⁶⁴*, of order 2⁶⁴ - 1.
  ## For k < 64, xᵏ has a single bit set: bit k.
  result.raw = 2

# ############################################################
#
#                  Comparisons and copies
#
# ############################################################

func `==`*(a, b: GF2_64): SecretBool =
  ## Constant-time equality check
  isZeroWord(a.raw xor b.raw)

func isZero*(a: GF2_64): SecretBool =
  isZeroWord(a.raw)

func isOne*(a: GF2_64): SecretBool =
  isZeroWord(a.raw xor 1)

func isMinusOne*(a: GF2_64): SecretBool =
  ## -1 = 1 in characteristic 2
  a.isOne()

func ccopy*(a: var GF2_64, b: GF2_64, ctl: SecretBool) =
  ## Constant-time conditional copy:
  ## if ctl is true, b is copied into a, otherwise a is unchanged
  a.raw = a.raw xor ((a.raw xor b.raw) and ctl.mask64())

func csetZero*(a: var GF2_64, ctl: SecretBool) =
  ## Set a to 0 if ctl is true
  a.raw = a.raw and not ctl.mask64()

func csetOne*(a: var GF2_64, ctl: SecretBool) =
  ## Set a to 1 if ctl is true
  let m = ctl.mask64()
  a.raw = (a.raw and not m) or (1'u64 and m)

# ############################################################
#
#                    Abelian group
#
# ############################################################
#
# Addition and subtraction are both XOR.
# Doubling gives 0 and negation is the identity.

func `+=`*(a: var GF2_64, b: GF2_64) =
  a.raw = a.raw xor b.raw

func `-=`*(a: var GF2_64, b: GF2_64) =
  a.raw = a.raw xor b.raw

func sum*(r: var GF2_64, a, b: GF2_64) =
  r.raw = a.raw xor b.raw

func diff*(r: var GF2_64, a, b: GF2_64) =
  r.raw = a.raw xor b.raw

func sumUnr*(r: var GF2_64, a, b: GF2_64) =
  ## There is no reduction to skip in a binary field
  r.raw = a.raw xor b.raw

func neg*(r: var GF2_64, a: GF2_64) =
  r = a

func neg*(a: var GF2_64) =
  discard

func double*(r: var GF2_64, a: GF2_64) =
  ## 2a = 0 in characteristic 2
  r.raw = 0

func double*(a: var GF2_64) =
  ## 2a = 0 in characteristic 2
  a.raw = 0

func div2*(a: var GF2_64) {.error: "Division by 2 is undefined in characteristic 2".} =
  discard

func cneg*(a: var GF2_64, ctl: SecretBool) =
  ## Negation is the identity
  discard

func cadd*(a: var GF2_64, b: GF2_64, ctl: SecretBool) =
  ## Constant-time conditional addition
  a.raw = a.raw xor (b.raw and ctl.mask64())

func csub*(a: var GF2_64, b: GF2_64, ctl: SecretBool) =
  ## Constant-time conditional subtraction
  a.raw = a.raw xor (b.raw and ctl.mask64())

# ############################################################
#
#              Multiplication by x and by integers
#
# ############################################################

func mulByX*(r: var GF2_64, a: GF2_64) =
  ## r <- x·a: a shift, and a fold of bit 64 by x⁶⁴ = x⁴ + x³ + x + 1
  r.raw = (a.raw shl 1) xor (ReductionPoly and (0'u64 - (a.raw shr 63)))

func mulByX*(a: var GF2_64) =
  a.mulByX(a)

func divByX*(r: var GF2_64, a: GF2_64) =
  ## r <- a/x, the inverse of `mulByX`.
  ## Bit 0 of a tells whether x·r folded: if so, unfold and set bit 63.
  let m = 0'u64 - (a.raw and 1)
  r.raw = ((a.raw xor (ReductionPoly and m)) shr 1) or (m shl 63)

func divByX*(a: var GF2_64) =
  a.divByX(a)

func `*=`*(a: var GF2_64, b: static int) =
  ## Multiplication by an integer known at compile-time:
  ## the integer n acts as n mod 2
  when (b and 1) == 0:
    a.raw = 0

func prod*(r: var GF2_64, a: GF2_64, b: static int) =
  ## Multiplication by an integer known at compile-time:
  ## the integer n acts as n mod 2
  when (b and 1) == 0:
    r.raw = 0
  else:
    r = a

# ############################################################
#
#               Multiplication and squaring
#
# ############################################################

func prod*(r: var GF2_64, a, b: GF2_64) {.meter.} =
  ## r <- a·b
  var hi {.noInit.}, lo {.noInit.}: uint64
  clmul(hi, lo, a.raw, b.raw)
  r.raw = reduce(hi, lo)

func prod*(r: var GF2_64, a, b: GF2_64, lazyReduce: static bool) =
  ## Alias for generic code written for prime fields,
  ## there is no reduction to skip.
  r.prod(a, b)

func `*=`*(a: var GF2_64, b: GF2_64) =
  a.prod(a, b)

func square*(r: var GF2_64, a: GF2_64) {.meter.} =
  ## r <- a²
  var hi {.noInit.}, lo {.noInit.}: uint64
  clsquare(hi, lo, a.raw)
  r.raw = reduce(hi, lo)

func square*(a: var GF2_64) =
  a.square(a)

func square*(r: var GF2_64, a: GF2_64, lazyReduce: static bool) =
  r.square(a)

func square*(a: var GF2_64, lazyReduce: static bool) =
  a.square(a)

func square_repeated*(a: var GF2_64, num: int) =
  ## a <- a^(2^num)
  for _ in 0 ..< num:
    a.square()

func square_repeated*(r: var GF2_64, a: GF2_64, num: int) =
  ## r <- a^(2^num)
  r = a
  r.square_repeated(num)

func prod_portable*(r: var GF2_64, a, b: GF2_64) =
  ## r <- a·b without CPU extensions, for testing and benchmarking
  var hi {.noInit.}, lo {.noInit.}: uint64
  clmul_portable(hi, lo, a.raw, b.raw)
  r.raw = reduce(hi, lo)

func square_portable*(r: var GF2_64, a: GF2_64) =
  ## r <- a² without CPU extensions, for testing and benchmarking
  var hi {.noInit.}, lo {.noInit.}: uint64
  clsquare_portable(hi, lo, a.raw)
  r.raw = reduce(hi, lo)

# ############################################################
#
#               Unreduced (double-width) products
#
# ############################################################

func setZero*(a: var GF2_64Dbl) =
  a.limbs2x = [0'u64, 0]

func `+=`*(a: var GF2_64Dbl, b: GF2_64Dbl) =
  a.limbs2x[0] = a.limbs2x[0] xor b.limbs2x[0]
  a.limbs2x[1] = a.limbs2x[1] xor b.limbs2x[1]

func sum2xUnr*(r: var GF2_64Dbl, a, b: GF2_64Dbl) =
  r.limbs2x[0] = a.limbs2x[0] xor b.limbs2x[0]
  r.limbs2x[1] = a.limbs2x[1] xor b.limbs2x[1]

func diff2xUnr*(r: var GF2_64Dbl, a, b: GF2_64Dbl) =
  r.sum2xUnr(a, b)

func sum2xMod*(r: var GF2_64Dbl, a, b: GF2_64Dbl) =
  r.sum2xUnr(a, b)

func diff2xMod*(r: var GF2_64Dbl, a, b: GF2_64Dbl) =
  r.sum2xUnr(a, b)

func neg2xMod*(r: var GF2_64Dbl, a: GF2_64Dbl) =
  r = a

func prod2x*(r: var GF2_64Dbl, a: GF2_64Dbl, b: static int) =
  ## Multiplication by an integer known at compile-time: n acts as n mod 2
  when (b and 1) == 0:
    r.setZero()
  else:
    r = a

func mulByX*(r: var GF2_64Dbl, a: GF2_64Dbl) =
  ## r <- x·a, assuming a has degree at most 126 so nothing is lost
  r.limbs2x[1] = (a.limbs2x[1] shl 1) or (a.limbs2x[0] shr 63)
  r.limbs2x[0] = a.limbs2x[0] shl 1

func prod2x*(r: var GF2_64Dbl, a, b: GF2_64) =
  ## r <- a ⊗ b, unreduced
  clmul(r.limbs2x[1], r.limbs2x[0], a.raw, b.raw)

func square2x*(r: var GF2_64Dbl, a: GF2_64) =
  ## r <- a ⊗ a, unreduced
  clsquare(r.limbs2x[1], r.limbs2x[0], a.raw)

func prod2x_portable*(r: var GF2_64Dbl, a, b: GF2_64) =
  ## r <- a ⊗ b, unreduced, without CPU extensions
  clmul_portable(r.limbs2x[1], r.limbs2x[0], a.raw, b.raw)

func square2x_portable*(r: var GF2_64Dbl, a: GF2_64) =
  ## r <- a ⊗ a, unreduced, without CPU extensions
  clsquare_portable(r.limbs2x[1], r.limbs2x[0], a.raw)

func redc2x*(r: var GF2_64, a: GF2_64Dbl) =
  ## r <- a mod (x⁶⁴ + x⁴ + x³ + x + 1)
  r.raw = reduce(a.limbs2x[1], a.limbs2x[0])

# ############################################################
#
#                      Inversion
#
# ############################################################

func inv*(r: var GF2_64, a: GF2_64) {.meter.} =
  ## r <- a⁻¹ = a^(2⁶⁴ - 2), by Itoh-Tsujii.
  ## The inverse of 0 is 0.
  ##
  ## Each tₖ = a^(2ᵏ - 1) is built from shorter ones, tₘ₊ₙ = tₘ^(2ⁿ)·tₙ,
  ## so the exponent costs 63 squarings and 8 multiplications.
  var t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t6 {.noInit.}, t12 {.noInit.}: GF2_64
  var t {.noInit.}: GF2_64

  t1 = a
  t2.square(t1)
  t2 *= t1                      # a^(2²-1)
  t3.square(t2)
  t3 *= t1                      # a^(2³-1)
  t6.square_repeated(t3, 3)
  t6 *= t3                      # a^(2⁶-1)
  t12.square_repeated(t6, 6)
  t12 *= t6                     # a^(2¹²-1)
  t.square_repeated(t12, 12)
  t *= t12                      # a^(2²⁴-1)
  var t48 {.noInit.}: GF2_64
  t48.square_repeated(t, 24)
  t48 *= t                      # a^(2⁴⁸-1)
  t.square_repeated(t48, 12)
  t *= t12                      # a^(2⁶⁰-1)
  t.square_repeated(3)
  t *= t3                       # a^(2⁶³-1)
  r.square(t)                   # a^(2⁶⁴-2)

func inv*(a: var GF2_64) =
  a.inv(a)

func inv_vartime*(r: var GF2_64, a: GF2_64) {.tags: [VarTime].} =
  ## The constant-time inversion is as fast, this is an alias for generic code
  r.inv(a)

func inv_vartime*(a: var GF2_64) {.tags: [VarTime].} =
  a.inv(a)

{.pop.} # inline

# ############################################################
#
#                 Out-of-place functions
#
# ############################################################
#
# For prototyping, testing and debugging.
# They SHOULD NOT be used in performance-critical subroutines,
# see https://github.com/mratsim/constantine/issues/145

func `+`*(a, b: GF2_64): GF2_64 {.noInit, inline.} =
  result.sum(a, b)

func `-`*(a, b: GF2_64): GF2_64 {.noInit, inline.} =
  result.diff(a, b)

func `*`*(a, b: GF2_64): GF2_64 {.noInit, inline.} =
  result.prod(a, b)

{.pop.} # checks
{.pop.} # raises
