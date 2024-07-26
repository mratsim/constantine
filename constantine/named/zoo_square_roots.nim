# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./algebras,
  ./constants/bls12_377_sqrt,
  ./constants/bls12_381_sqrt,
  ./constants/bn254_nogami_sqrt,
  ./constants/bn254_snarks_sqrt,
  ./constants/bw6_761_sqrt,
  ./constants/curve25519_sqrt,
  ./constants/jubjub_sqrt,
  ./constants/bandersnatch_sqrt,
  ./constants/banderwagon_sqrt,
  ./constants/pallas_sqrt,
  ./constants/vesta_sqrt

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

func hasSqrtAddchain*(Name: static Algebra): static bool =
  when Name in {BLS12_381, BN254_Nogami, BN254_Snarks, BW6_761, Edwards25519}:
    true
  else:
    false

{.experimental: "dynamicBindSym".}

macro tonelliShanks*(Name: static Algebra, value: untyped): untyped =
  ## Get Square Root via Tonelli-Shanks related constants
  return bindSym($Name & "_TonelliShanks_" & $value)

macro sqrtDlog*(Name: static Algebra, value: untyped): untyped =
  ## Get Square Root via Square Root Dlog related constants
  return bindSym($Name & "_SqrtDlog_" & $value)

func hasTonelliShanksAddchain*(Name: static Algebra): static bool =
  when Name in {Bandersnatch, Banderwagon, BLS12_377}:
    true
  else:
    false
