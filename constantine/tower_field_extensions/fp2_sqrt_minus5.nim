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
#   x² - µ with µ = -5
# i.e. 𝔽p2 = 𝔽p[√-5]
#
# Consequently, for this file Fp2 to be valid
# -5 MUST not be a square in 𝔽p
#
# References
# [1] High-Speed Software Implementation of the Optimal Ate Pairing over Barreto-Naehrig Curves\
#     Jean-Luc Beuchat and Jorge Enrique González Díaz and Shigeo Mitsunari and Eiji Okamoto and Francisco Rodríguez-Henríquez and Tadanori Teruya, 2010\
#     https://eprint.iacr.org/2010/354

import
  ../arithmetic/finite_fields,
  ../config/curves,
  ./abelian_groups

type
  Fp2*[C: static Curve] = object
    ## Element of the extension field
    ## 𝔽p2 = 𝔽p[√-5] of a prime p
    ##
    ## with coordinates (c0, c1) such as
    ## c0 + c1 √-5
    ##
    ## This requires -5 to not be a square (mod p)
    c0*, c1*: Fp[C]

# TODO: need fast multiplication by small constant
#       which probably requires lazy carries
#       https://github.com/mratsim/constantine/issues/15
