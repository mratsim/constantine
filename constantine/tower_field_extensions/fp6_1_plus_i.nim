# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#        Cubic Extension field over base field 𝔽p2
#             𝔽p6 = 𝔽p2[∛(1 + 𝑖)]
#
# ############################################################

# This implements a quadratic extension field over 𝔽p2 = 𝔽p[𝑖]
# the base field 𝔽p:
#   𝔽p6 = 𝔽p2[∛(1 + 𝑖)]
# with element A of coordinates (a0, a1) represented
# by a0 + a1 ξ + a2 ξ²
#
# The irreducible polynomial chosen is
#   x³ - ξ with ξ = 𝑖+1
#
#
# Consequently, for this file Fp2 to be valid
# 𝑖+1 MUST not be a square in 𝔽p2

import
  ../arithmetic,
  ../config/curves,
  ./abelian_groups,
  ./fp2_complex

type
  Fp6*[C: static Curve] = object
    ## Element of the extension field
    ## 𝔽p6 = 𝔽p2[∛(1 + 𝑖)]
    ##
    ## with coordinates (c0, c1, c2) such as
    ## c0 + c1 ξ + c2 ξ²
    ##
    ## This requires 1 + 𝑖 to not be a cube in 𝔽p2
    c0*, c1*, c2*: Fp2[C]

  Xi = object
    ## ξ (Xi) the cubic non-residue

func `*`(_: typedesc[Xi], a: Fp2): Fp2 =
  ## Multiply an element of 𝔽p2 by 𝔽p6 cubic non-residue 1 + 𝑖
  ## (c0 + c1 𝑖) (1 + 𝑖) => c0 + (c0 + c1)𝑖 + c1 𝑖²
  ##                     => c0 - c1 + (c0 + c1) 𝑖
  result.c0.diff(a.c0, a.c1)
  result.c1.sum(a.c0, a.c1)

template `*`(a: Fp2, _: typedesc[Xi]): Fp2 =
  Xi * a

func `*=`(a: var Fp2, _: typedesc[Xi]) =
  ## Inplace multiply an element of 𝔽p2 by 𝔽p6 cubic non-residue 1 + 𝑖
  let t = a.c0
  a.c0 -= a.c1
  a.c1 += t

func square*[C](r: var Fp6[C], a: Fp6[C]) =
  ## Returns r = a²
  # Algorithm is Chung-Hasan Squaring SQR2
  # http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf
  #
  # TODO: change to SQR1 or SQR3 (requires div2)
  #       which are faster for the sizes we are interested in.
  var v2{.noInit.}, v3{.noInit.}, v4{.noInit.}, v5{.noInit.}: Fp2[C]

  v4.prod(a.c0, a.c1)
  v4.double()
  v5.square(a.c2)
  r.c1 = Xi * v5
  r.c1 += v4
  v2.diff(v4, v5)
  v3.square(a.c0)
  v4.diff(a.c0, a.c1)
  v4 += a.c2
  v5.prod(a.c1, a.c2)
  v5.double()
  v4.square(v4)
  r.c0 = Xi * v5
  r.c0 += v3
  r.c2.sum(v2, v4)
  r.c2 += v5
  r.c2 -= v3

func prod*[C](r: var Fp6[C], a, b: Fp6[C]) =
  ## Returns r = a * b
  # Algorithm is Karatsuba
  var v0{.noInit.}, v1{.noInit.}, v2{.noInit.}, t{.noInit.}: Fp2[C]

  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)
  v2.prod(a.c2, b.c2)

  # r.c0 = ((a.c1 + a.c2) * (b.c1 + b.c2) - v1 - v2) * Xi + v0
  r.c0.sum(a.c1, a.c2)
  t.sum(b.c1, b.c2)
  r.c0 *= t
  r.c0 -= v1
  r.c0 -= v2
  r.c0 *= Xi
  r.c0 += v0

  # r.c1 = (a.c0 + a.c1) * (b.c0 + b.c1) - v0 - v1 + Xi * v2
  r.c1.sum(a.c0, a.c1)
  t.sum(b.c0, b.c1)
  r.c1 *= t
  r.c1 -= v0
  r.c1 -= v1
  r.c1 += Xi * v2

  # r.c2 = (a.c0 + a.c2) * (b.c0 + b.c2) - v0 - v2 + v1
  r.c2.sum(a.c0, a.c2)
  t.sum(b.c0, b.c2)
  r.c2 *= t
  r.c2 -= v0
  r.c2 -= v2
  r.c2 += v1
