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

  # No need to precompute `b` in 𝔽p or 𝔽p² or `b/µ` `µ b`
  # This procedure is not use in perf critcal situation like signing/verification
  # but for testing to quickly create points on a curve.
  y2 = F.fromBig F.C.matchingBigInt().fromUint F.C.getCoefB()
  when F is Fp2:
    when F.C.getSexticTwist() == D_Twist:
      y2 /= F.C.get_SNR_Fp2()
    elif F.C.getSexticTwist() == M_Twist:
      y2 *= F.C.get_SNR_Fp2()
    else:
      {.error: "Only twisted curves are supported on extension field 𝔽p²".}

  y2 += t

  when F.C.getCoefA() != 0:
    t = x
    t *= F.C.getCoefA()
    y2 += t

func isOnCurve*[F](x, y: F): CTBool[Word] =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the elliptic curve

  var y2, rhs {.noInit.}: F
  y2.square(y)
  rhs.curve_eq_rhs(x)

  return y2 == rhs
