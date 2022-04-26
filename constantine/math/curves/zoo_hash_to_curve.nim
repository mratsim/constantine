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
  ../elliptic/ec_shortweierstrass_affine,
  ./bls12_381_hash_to_curve_g1,
  ./bls12_381_hash_to_curve_g2,
  ./bn254_snarks_hash_to_curve_g1,
  ./bn254_snarks_hash_to_curve_g2

{.experimental: "dynamicBindSym".}

macro h2cConst*(C: static Curve, mapping: untyped, group: static Subgroup, value: untyped): untyped =
  ## Get a Hash-to-Curve constant
  ## for mapping to a elliptic curve group (G1 or G2)
  return bindSym($C & "_h2c_" & $mapping & "_" & $group & "_" & $value)

macro h2cIsomapPoly*(C: static Curve,
        mapping: untyped,
        group: static Subgroup,
        value: untyped): untyped =
  ## Get an isogeny map polynomial
  ## for mapping to a elliptic curve group (G1 or G2)
  return bindSym($C & "_h2c_" &
    $mapping & "_" &
    $group & "_isogeny_map_" & $value)
