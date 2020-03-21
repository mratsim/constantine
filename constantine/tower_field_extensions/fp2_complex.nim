# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        Quadratic Extension field over base field 𝔽p
#                        𝔽p2 = 𝔽p[𝑖]
#
# ############################################################

# This implements a quadratic extension field over
# the base field 𝔽p:
#   𝔽p2 = 𝔽p[x]
# with element A of coordinates (a0, a1) represented
# by a0 + a1 x
#
# The irreducible polynomial chosen is
#   x² - µ with µ = -1
# i.e. 𝔽p2 = 𝔽p[𝑖], 𝑖 being the imaginary unit
#
# Consequently, for this file Fp2 to be valid
# -1 MUST not be a square in 𝔽p
#
# µ is also chosen to simplify multiplication and squaring
# => A(a0, a1) * B(b0, b1)
# => (a0 + a1 x) * (b0 + b1 x)
# => a0 b0 + (a0 b1 + a1 b0) x + a1 b1 x²
# We need x² to be as cheap as possible
#
# References
# [1] Constructing Tower Extensions for the implementation of Pairing-Based Cryptography\
#     Naomi Benger and Michael Scott, 2009\
#     https://eprint.iacr.org/2009/556
#
# [2] Choosing and generating parameters for low level pairing implementation on BN curves\
#     Sylvain Duquesne and Nadia El Mrabet and Safia Haloui and Franck Rondepierre, 2015\
#     https://eprint.iacr.org/2015/1212

# TODO: Clarify some assumptions about the prime p ≡ 3 (mod 4)

import
  ../arithmetic,
  ../config/curves,
  ./abelian_groups

type
  Fp2*[C: static Curve] = object
    ## Element of the extension field
    ## 𝔽p2 = 𝔽p[𝑖] of a prime p
    ##
    ## with coordinates (c0, c1) such as
    ## c0 + c1 𝑖
    ##
    ## This requires 𝑖² = -1 to not
    ## be a square (mod p)
    c0*, c1*: Fp[C]

func square*(r: var Fp2, a: Fp2) =
  ## Return a² in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
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

  var c0mc1 {.noInit.}: Fp[Fp2.C]
  c0mc1.diff(a.c0, a.c1) # c0mc1 = c0 - c1                            [1 Sub]
  r.c1.double(a.c1)      # result.c1 = 2 c1                           [1 Dbl, 1 Sub]
  r.c0.sum(c0mc1, r.c1)  # result.c0 = c0 - c1 + 2 c1                 [1 Add, 1 Dbl, 1 Sub]
  r.c0 *= c0mc1          # result.c0 = (c0 + c1)(c0 - c1) = c0² - c1² [1 Mul, 1 Add, 1 Dbl, 1 Sub] - 𝔽p temporary
  r.c1 *= a.c0           # result.c1 = 2 c1 c0                        [2 Mul, 1 Add, 1 Dbl, 1 Sub] - 𝔽p temporary

func prod*(r: var Fp2, a, b: Fp2) =
  ## Return a * b in 𝔽p2 = 𝔽p[𝑖] in ``r``
  ## ``r`` is initialized/overwritten
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
  var a0b0 {.noInit.}, a1b1 {.noInit.}: Fp[Fp2.C]
  a0b0.prod(a.c0, b.c0)                                         # [1 Mul]
  a1b1.prod(a.c1, b.c1)                                         # [2 Mul]

  r.c0.sum(a.c0, a.c1)  # r0 = (a0 + a1)                        # [2 Mul, 1 Add]
  r.c1.sum(b.c0, b.c1)  # r1 = (b0 + b1)                        # [2 Mul, 2 Add]
  r.c1 *= r.c0          # r1 = (b0 + b1)(a0 + a1)               # [3 Mul, 2 Add] - 𝔽p temporary

  r.c0.diff(a0b0, a1b1) # r0 = a0 b0 - a1 b1                    # [3 Mul, 2 Add, 1 Sub]
  r.c1 -= a0b0          # r1 = (b0 + b1)(a0 + a1) - a0b0        # [3 Mul, 2 Add, 2 Sub]
  r.c1 -= a1b1          # r1 = (b0 + b1)(a0 + a1) - a0b0 - a1b1 # [3 Mul, 2 Add, 3 Sub]

func inv*(r: var Fp2, a: Fp2) =
  ## Compute the modular multiplicative inverse of ``a``
  ## in 𝔽p2 = 𝔽p[𝑖]
  #
  # Algorithm: (the inverse exist if a != 0 which might cause constant-time issue)
  #
  # 1 / (a0 + a1 x) <=> (a0 - a1 x) / (a0 + a1 x)(a0 - a1 x)
  #                 <=> (a0 - a1 x) / (a0² - a1² x²)
  # In our case 𝔽p2 = 𝔽p[𝑖], we have x = 𝑖
  # So the inverse is (a0 - a1 𝑖) / (a0² + a1²)

  # [2 Sqr, 1 Add]
  var t0 {.noInit.}, t1 {.noInit.}: Fp[Fp2.C]
  t0.square(a.c0)
  t1.square(a.c1)
  t0 += t1             # t0 = a0² + a1² (the norm / squared magnitude of a)

  # [1 Inv, 2 Sqr, 1 Add]
  t0.inv(t0)           # t0 = 1 / (a0² + a1²)

  # [1 Inv, 2 Mul, 2 Sqr, 1 Add, 1 Neg]
  r.c0.prod(a.c0, t0)  # r0 = a0 / (a0² + a1²)
  t1.neg(t0)           # t0 = -1 / (a0² + a1²)
  r.c1.prod(a.c1, t1)  # r1 = -a1 / (a0² + a1²)
