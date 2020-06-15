# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ../io/io_bigints

func curve_eq_rhs*[F](y2: var F, x: F) =
  ## Compute the curve equation right-hand-side from field element `x`
  ## i.e.  `y²` in `y² = x³ + a x + b`
  ## or on sextic twists for pairing curves `y² = x³ + b/µ` or `y² = x³ + µ b`
  ## with µ the chosen sextic non-residue

  var t{.noInit.}: F
  t.square(x)
  t *= x

  # This procedure is not use in perf critical situation like signing/verification
  # but for testing to quickly create points on a curve.
  # That said D-Twists require an inversion
  # and we could avoid doing `b/µ` or `µ*b` at runtime on 𝔽p²
  # which would accelerate random point generation
  #
  # This is preferred to generating random point
  # via random scalar multiplication of the curve generator
  # as the latter assumes:
  # - point addition, doubling work
  # - scalar multiplication works
  # - a generator point is defined
  # i.e. you can't test unless everything is already working
  #
  # TODO: precomputation needed when deserializing points
  #       to check if a point is on-curve and prevent denial-of-service
  #       using slow inversion.
  y2.fromBig F.C.matchingBigInt().fromUint F.C.getCoefB()
  when F is Fp2:
    when F.C.getSexticTwist() == D_Twist:
      y2 /= SexticNonResidue
    elif F.C.getSexticTwist() == M_Twist:
      y2 *= SexticNonResidue
    else:
      {.error: "Only twisted curves are supported on extension field 𝔽p²".}

  y2 += t

  when F.C.getCoefA() != 0:
    t = x
    t *= F.C.getCoefA()
    y2 += t

func isOnCurve*[F](x, y: F): SecretBool =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the elliptic curve

  var y2, rhs {.noInit.}: F
  y2.square(y)
  rhs.curve_eq_rhs(x)

  return y2 == rhs
