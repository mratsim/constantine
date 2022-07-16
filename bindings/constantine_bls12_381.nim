# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/math/config/curves,
  ../constantine/curves_primitives,
  genny

type
  bls12381_fr = Fr[BLS12_381]
  bls12381_fp = Fp[BLS12_381]

exportObject bls12381_fr:
  procs:
    neg(bls12381_fr, bls12381_fr)
    neg(bls12381_fr)

writeFiles("bindings/generated", "ctt_bls12_381")
include generated/internal