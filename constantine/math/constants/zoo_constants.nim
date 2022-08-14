# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/curves,
  ./bls12_377_constants,
  ./bls12_381_constants,
  ./bn254_nogami_constants,
  ./bn254_snarks_constants,
  ./bw6_761_constants

{.experimental: "dynamicBindSym".}

macro getCoefB_G2*(C: static Curve): untyped =
  ## A pairing curve has the following equation on G1
  ##   y² = x³ + b
  ## and on G2
  ##   y² = x³ + b/µ (D-Twist)
  ##   y² = x³ + b*µ (M-Twist)
  ## with µ the non-residue (sextic non-residue with a sextic twist)
  return bindSym($C & "_coefB_G2")

macro getCoefB_G2_times_3*(C: static Curve): untyped =
  ## A pairing curve has the following equation on G1
  ##   y² = x³ + b
  ## and on G2
  ##   y² = x³ + b/µ (D-Twist)
  ##   y² = x³ + b*µ (M-Twist)
  ## with µ the non-residue (sextic non-residue with a sextic twist)
  return bindSym($C & "_coefB_G2_times_3")