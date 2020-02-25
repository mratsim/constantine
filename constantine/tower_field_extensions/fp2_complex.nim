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

import
  ../arithmetic/finite_fields,
  ../config/curves

type
  Fp2[C: static Curve] = object
    ## Element of the extension field
    ## 𝔽p2 = 𝔽p[𝑖] of a prime p
    ##
    ## with coordinates (c0, c1) such as
    ## c0 + c1 𝑖
    ##
    ## This requires 𝑖² = -1 to not
    ## be a square (mod p)
    c0, c1: Fp[Curve]

func setZero*(a: var Fp2) =
  ## Set ``a`` to zero in 𝔽p2
  ## Coordinates 0 + 0𝑖
  a.c0.setZero()
  a.c1.setZero()

func setOne*(a: var Fp2) =
  ## Set ``a`` to one in 𝔽p2
  ## Coordinates 1 + 0𝑖
  a.c0.setOne()
  a.c1.setZero()

func `+=`*(a: var Fp2, b: Fp2) =
  ## Addition over 𝔽p2
  a.c0 += b.c0
  a.c1 += b.c1

func `-=`*(a: var Fp2, b: Fp2) =
  ## Substraction over 𝔽p2
  a.c0 -= b.c0
  a.c1 -= b.c1

func square*(a: Fp2): Fp2 {.noInit.} =
  ## Return a^2 in 𝔽p2
  # (c0, c1)² => (c0 + c1𝑖)²
  #           => c0² + 2 c0 c1𝑖 + (c1𝑖)²
  #           => c0²-c1² + 2 c0 c1𝑖
  #           => (c0²-c1², 2 c0 c1)
  #           or
  #           => ((c0-c1)(c0+c1), 2 c0 c1)
  #           => ((c0-c1)(c0-c1 + 2 c1), 2 c0 c1)
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
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 1 named temporaries + 1 multiplication temporary)
  # as multiplications require a (shared) internal temporary

  var c0mc1 {.noInit.}: Fp
  c0mc1.diff(a.c0, a.c1)           # c0mc1 = c0 - c1                               [1 Sub]
  result.c1.double(a.c1)           # result.c1 = 2 c1                              [1 Dbl, 1 Sub]
  result.c0.sum(c0mc1, result.c1)  # result.c0 = c0 - c1 + 2 c1                    [1 Add, 1 Dbl, 1 Sub]
  result.c0 *= c0mc1               # result.c0 = (c0 + c1)(c0 - c1) = c0² - c1²    [1 Mul, 1 Add, 1 Dbl, 1 Sub]
  result.c1 *= a.c0                # result.c1 = 2 c1 c0                           [2 Mul, 1 Add, 1 Dbl, 1 Sub]
