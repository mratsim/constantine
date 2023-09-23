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
  ./bls12_377_sqrt,
  ./bls12_381_sqrt,
  ./bn254_nogami_sqrt,
  ./bn254_snarks_sqrt,
  ./bw6_761_sqrt,
  ./curve25519_sqrt,
  ./jubjub_sqrt,
  ./bandersnatch_sqrt,
  ./banderwagon_sqrt,
  ./pallas_sqrt,
  ./vesta_sqrt

export
  bls12_377_sqrt,
  bls12_381_sqrt,
  bn254_nogami_sqrt,
  bn254_snarks_sqrt,
  bw6_761_sqrt,
  curve25519_sqrt,
  jubjub_sqrt,
  bandersnatch_sqrt,
  banderwagon_sqrt,
  pallas_sqrt,
  vesta_sqrt

func hasSqrtAddchain*(C: static Curve): static bool =
  when C in {BLS12_381, BN254_Nogami, BN254_Snarks, BW6_761, Edwards25519}:
    true
  else:
    false

{.experimental: "dynamicBindSym".}

macro tonelliShanks*(C: static Curve, value: untyped): untyped =
  ## Get Square Root via Tonelli-Shanks related constants
  return bindSym($C & "_TonelliShanks_" & $value)

func hasTonelliShanksAddchain*(C: static Curve): static bool =
  when C in {BLS12_377}:
    true
  else:
    false
