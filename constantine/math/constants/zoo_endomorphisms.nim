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
  ../extension_fields,
  ./bls12_377_endomorphisms,
  ./bls12_381_endomorphisms,
  ./bn254_nogami_endomorphisms,
  ./bn254_snarks_endomorphisms,
  ./bw6_761_endomorphisms,
  ./pallas_endomorphisms,
  ./vesta_endomorphisms

{.experimental: "dynamicBindSym".}

macro dispatch(C: static Curve, tag: static string, G: static string): untyped =
  result = bindSym($C & "_" & tag & "_" & G)

template babai*(F: typedesc[Fp or Fp2]): untyped =
  ## Return the GLV Babai roundings vector
  const G = if F is Fp: "G1"
            else: "G2"
  dispatch(F.C, "Babai", G)

template lattice*(F: typedesc[Fp or Fp2]): untyped =
  ## Returns the GLV Decomposition Lattice
  const G = if F is Fp: "G1"
            else: "G2"
  dispatch(F.C, "Lattice", G)

macro getCubicRootOfUnity_mod_p*(C: static Curve): untyped =
  ## Get a non-trivial cubic root of unity (mod p) with p the prime field
  result = bindSym($C & "_cubicRootOfUnity_mod_p")

func hasEndomorphismAcceleration*(C: static Curve): bool =
  C in {
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381,
    BW6_761,
    Pallas,
    Vesta
  }

const EndomorphismThreshold* = 196
  ## We use substraction by maximum infinity norm coefficient
  ## to split scalars for endomorphisms
  ## For small scalars the substraction will overflow
  ##
  ## TODO: implement an alternative way to split scalars.