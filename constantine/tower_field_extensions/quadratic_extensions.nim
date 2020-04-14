# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../arithmetic,
  ../config/common,
  ../primitives,
  ./tower_common

# Commutative ring implementation for complex extension fields
# -------------------------------------------------------------------

func square_complex(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (c0, c1)² => (c0 + c1𝑖)²
  #           => c0² + 2 c0 c1𝑖 + (c1𝑖)²
  #           => c0²-c1² + 2 c0 c1𝑖
  #           => (c0²-c1², 2 c0 c1)
  #           or
  #           => ((c0-c1)(c0+c1), 2 c0 c1)
  #           => ((c0-c1)(c0-c1 + 2 c1), c0 * 2 c1)
  #
  # Costs (naive implementation)
  # - 1 Multiplication 𝔽p
  # - 2 Squarings 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 4 * ModulusBitSize (4x 𝔽p element)
  #
  # Or (with 1 less Mul/Squaring at the cost of 1 addition and extra 2 𝔽p stack space)
  #
  # - 2 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 1 named temporaries + 1 in-place multiplication temporary)
  # as in-place multiplications require a (shared) internal temporary
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  var c0mc1 {.noInit.}: typeof(r.c0)
  c0mc1.diff(a.c0, a.c1) # c0mc1 = c0 - c1                            [1 Sub]
  r.c1.double(a.c1)      # result.c1 = 2 c1                           [1 Dbl, 1 Sub]
  r.c0.sum(c0mc1, r.c1)  # result.c0 = c0 - c1 + 2 c1                 [1 Add, 1 Dbl, 1 Sub]
  r.c0 *= c0mc1          # result.c0 = (c0 + c1)(c0 - c1) = c0² - c1² [1 Mul, 1 Add, 1 Dbl, 1 Sub] - 𝔽p temporary
  r.c1 *= a.c0           # result.c1 = 2 c1 c0                        [2 Mul, 1 Add, 1 Dbl, 1 Sub] - 𝔽p temporary

func prod_complex(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Return a * b in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
  ##
  ## Requires a complex extension field
  # (a0, a1) (b0, b1) => (a0 + a1𝑖) (b0 + b1𝑖)
  #                   => (a0 b0 - a1 b1) + (a0 b1 + a1 b0) 𝑖
  #
  # In Fp, multiplication has cost O(n²) with n the number of limbs
  # while addition has cost O(3n) (n for addition, n for overflow, n for conditional substraction)
  # and substraction has cost O(2n) (n for substraction + underflow, n for conditional addition)
  #
  # Even for 256-bit primes, we are looking at always a minimum of n=5 limbs (with 2^63 words)
  # where addition/substraction are significantly cheaper than multiplication
  #
  # So we always reframe the imaginary part using Karatsuba approach to save a multiplication
  # (a0, a1) (b0, b1) => (a0 b0 - a1 b1) + 𝑖( (a0 + a1)(b0 + b1) - a0 b0 - a1 b1 )
  #
  # Costs (naive implementation)
  # - 4 Multiplications 𝔽p
  # - 1 Addition 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries)
  #
  # Costs (Karatsuba)
  # - 3 Multiplications 𝔽p
  # - 3 Substraction 𝔽p (2 are fused)
  # - 2 Addition 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2x named temporaries + 1 in-place multiplication temporary)
  mixin fromComplexExtension
  static: doAssert r.fromComplexExtension()

  var a0b0 {.noInit.}, a1b1 {.noInit.}: typeof(r.c0)
  a0b0.prod(a.c0, b.c0)                                         # [1 Mul]
  a1b1.prod(a.c1, b.c1)                                         # [2 Mul]

  r.c0.sum(a.c0, a.c1)  # r0 = (a0 + a1)                        # [2 Mul, 1 Add]
  r.c1.sum(b.c0, b.c1)  # r1 = (b0 + b1)                        # [2 Mul, 2 Add]
  r.c1 *= r.c0          # r1 = (b0 + b1)(a0 + a1)               # [3 Mul, 2 Add] - 𝔽p temporary

  r.c0.diff(a0b0, a1b1) # r0 = a0 b0 - a1 b1                    # [3 Mul, 2 Add, 1 Sub]
  r.c1 -= a0b0          # r1 = (b0 + b1)(a0 + a1) - a0b0        # [3 Mul, 2 Add, 2 Sub]
  r.c1 -= a1b1          # r1 = (b0 + b1)(a0 + a1) - a0b0 - a1b1 # [3 Mul, 2 Add, 3 Sub]

# Commutative ring implementation for generic quadratic extension fields
# -------------------------------------------------------------------

func square_generic(r: var QuadraticExt, a: QuadraticExt) =
  ## Return a² in ``r``
  ## ``r`` is initialized/overwritten
  # Algorithm (with β the non-residue in the base field)
  #
  # (c0, c1)² => (c0 + c1 w)²
  #           => c0² + 2 c0 c1 w + c1²w²
  #           => c0² + β c1² + 2 c0 c1 w
  #           => (c0² + β c1², 2 c0 c1)
  # We have 2 squarings and 1 multiplication in the base field
  # which are significantly more costly than additions.
  # For example when construction 𝔽p12 from 𝔽p6:
  # - 4 limbs like BN254:     multiplication is 20x slower than addition/substraction
  # - 6 limbs like BLS12-381: multiplication is 28x slower than addition/substraction
  #
  # We can save operations with one of the following expressions
  # of c0² + β c1² and noticing that c0c1 is already computed for the "y" coordinate
  #
  # Alternative 1:
  #   c0² + β c1² <=> (c0 - c1)(c0 - β c1) + β c0c1 + c0c1
  #
  # Alternative 2:
  #   c0² + β c1² <=> (c0 + c1)(c0 + β c1) - β c0c1 - c0c1
  mixin prod

  # r0 <- (c0 + c1)(c0 + β c1)
  r.c0.sum(a.c0, a.c1)
  r.c1.sum(a.c0, β * a.c1)
  r.c0 *= r.c1

  # r1 <- c0 c1
  r.c1.prod(a.c0, a.c1)

  # r0 = (c0 + c1)(c0 + β c1) - β c0c1 - c0c1
  r.c0 -= β * r.c1
  r.c0 -= r.c1

  # r1 = 2 c0c1
  r.c1.double()

func prod_generic(r: var QuadraticExt, a, b: QuadraticExt) =
  ## Returns r = a * b
  # Algorithm (with β the non-residue in the base field)
  #
  # r0 = a0 b0 + β a1 b1
  # r1 = (a0 + a1) (b0 + b1) - a0 b0 - a1 b1 (Karatsuba)
  mixin prod
  var t {.noInit.}: typeof(r.c0)

  # r1 <- (a0 + a1)(b0 + b1)
  r.c0.sum(a.c0, a.c1)
  t.sum(b.c0, b.c1)
  r.c1.prod(r.c0, t)

  # r0 <- a0 b0
  # r1 <- (a0 + a1)(b0 + b1) - a0 b0 - a1 b1
  r.c0.prod(a.c0, b.c0)
  t.prod(a.c1, b.c1)
  r.c1 -= r.c0
  r.c1 -= t

  # r0 <- a0 b0 + β a1 b1
  r.c0 += β * t

# Exported symbols
# -------------------------------------------------------------------

func square*(r: var QuadraticExt, a: QuadraticExt) {.inline.} =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    r.square_complex(a)
  else:
    r.square_generic(a)

func prod*(r: var QuadraticExt, a, b: QuadraticExt) {.inline.} =
  mixin fromComplexExtension
  when r.fromComplexExtension():
    r.prod_complex(a, b)
  else:
    r.prod_generic(a, b)

func inv*(r: var QuadraticExt, a: QuadraticExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  #
  # Algorithm:
  #
  # 1 / (a0 + a1 w) <=> (a0 - a1 w) / (a0 + a1 w)(a0 - a1 w)
  #                 <=> (a0 - a1 w) / (a0² - a1² w²)
  # with w being our coordinate system and β the quadratic non-residue
  # we have w² = β
  # So the inverse is (a0 - a1 w) / (a0² - β a1²)
  mixin fromComplexExtension

  # [2 Sqr, 1 Add]
  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.square(a.c0)
  v1.square(a.c1)
  when r.fromComplexExtension():
    v0 += v1
  else:
    v0 -= β * v1     # v0 = a0² - β a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  v1.inv(v0)           # v1 = 1 / (a0² - β a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, v1)  # r0 = a0 / (a0² - β a1²)
  v0.neg(v1)           # v0 = -1 / (a0² - β a1²)
  r.c1.prod(a.c1, v0)  # r1 = -a1 / (a0² - β a1²)

func `*=`*(a: var QuadraticExt, b: QuadraticExt) {.inline.} =
  ## In-place multiplication
  # On higher extension field like 𝔽p12,
  # if `prod` is called on shared in and out buffer, the result is wrong
  let t = a
  a.prod(t, b)

func square*(a: var QuadraticExt){.inline.} =
  let t = a
  a.square(t)
