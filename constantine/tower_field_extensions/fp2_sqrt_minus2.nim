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
#                        𝔽p2 = 𝔽p[√-5]
#
# ############################################################

# This implements a quadratic extension field over
# the base field 𝔽p:
#   𝔽p2 = 𝔽p[x]
# with element A of coordinates (a0, a1) represented
# by a0 + a1 x
#
# The irreducible polynomial chosen is
#   x² - µ with µ = -2
# i.e. 𝔽p2 = 𝔽p[√-2]
#
# Consequently, for this file Fp2 to be valid
# -2 MUST not be a square in 𝔽p
#
# References
# [1] Software Implementation of Pairings\
#     D. Hankerson, A. Menezes, and M. Scott, 2009\
#     http://cacr.uwaterloo.ca/~ajmeneze/publications/pairings_software.pdf


import
  ../arithmetic/finite_fields,
  ../config/curves,
  ./abelian_groups

type
  Fp2*[C: static Curve] = object
    ## Element of the extension field
    ## 𝔽p2 = 𝔽p[√-2] of a prime p
    ##
    ## with coordinates (c0, c1) such as
    ## c0 + c1 √-2
    ##
    ## This requires -2 to not be a square (mod p)
    c0*, c1*: Fp[C]

func square*(r: var Fp2, a: Fp2) =
  ## Return a^2 in 𝔽p2 in ``r``
  ## ``r`` is initialized/overwritten
  # (c0, c1)² => (c0 + c1√-2)²
  #           => c0² + 2 c0 c1√-2 + (c1√-2)²
  #           => c0² - 2c1² + 2 c0 c1 √-2
  #           => (c0²-2c1², 2 c0 c1)
  #
  # Costs (naive implementation)
  # - 2 Multiplications 𝔽p
  # - 1 Squaring 𝔽p
  # - 1 Doubling 𝔽p
  # - 1 Substraction 𝔽p
  # Stack: 6 * ModulusBitSize (4x 𝔽p element + 2 named temporaries + 1 "in-place" mul temporary)

  var c1d, c0s {.noInit.}: typeof(a.c1)
  c1d.double(a.c1)       # c1d = 2 c1      [1 Dbl]
  c0s.square(a.c0)       # c0s = c0²       [1 Sqr, 1 Dbl]

  r.c1.prod(c1d, a.c0)   # r.c1 = 2 c1 c0  [1 Mul, 1 Sqr, 1 Dbl]
  c1d *= a.c1            # c1d = 2 c1²     [2 Mul, 1 Sqr, 1 Dbl] - 1 "in-place" temporary
  r.c0.diff(c0s, c1d)    # r.c0 = c0²-2c1² [2 Mul, 1 Sqr, 1 Dbl, 1 Sub]
