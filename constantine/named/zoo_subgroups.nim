# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ./algebras,
  ./constants/bandersnatch_subgroups,
  ./constants/bls12_377_subgroups,
  ./constants/bls12_381_subgroups,
  ./constants/bn254_nogami_subgroups,
  ./constants/bn254_snarks_subgroups,
  ./constants/bw6_761_subgroups,
  ./constants/pallas_subgroups,
  ./constants/vesta_subgroups,
  ./constants/secp256k1_subgroups

export
  bandersnatch_subgroups,
  bls12_377_subgroups,
  bls12_381_subgroups,
  bn254_nogami_subgroups,
  bn254_snarks_subgroups,
  bw6_761_subgroups,
  pallas_subgroups,
  vesta_subgroups,
  secp256k1_subgroups

func clearCofactor*[EC](P: var EC) {.inline.} =
  ## Clear the cofactor of a point on the curve
  ## From a point on the curve, returns a point on the subgroup of order r
  when EC.F.Name in {BN254_Nogami, BN254_Snarks, BLS12_377, BLS12_381}:
    P.clearCofactorFast()
  else:
    P.clearCofactorReference()
