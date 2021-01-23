# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_ff],
  ./bls12_377_inversion,
  ./bls12_381_inversion,
  ./bn254_nogami_inversion,
  ./bn254_snarks_inversion,
  ./bw6_761_inversion,
  ./secp256k1_inversion

export
  bls12_377_inversion,
  bls12_381_inversion,
  bn254_nogami_inversion,
  bn254_snarks_inversion,
  bw6_761_inversion,
  secp256k1_inversion

func hasInversionAddchain*(C: static Curve): static bool =
  # TODO: For now we don't activate the addition chains
  #      for Secp256k1
  # Performance is slower than GCD
  when C in {BN254_Nogami, BN254_Snarks, BLS12_377, BLS12_381, BW6_761}:
    true
  else:
    false
