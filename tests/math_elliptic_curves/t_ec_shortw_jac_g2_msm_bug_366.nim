# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/algebras,
  constantine/math/ec_shortweierstrass,
  constantine/math/extension_fields,
  # Test utilities
  helpers/prng_unsafe

var rng: RngState
let seed = 1234
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "BN254 G2 MSM edge case #366 xoshiro512** seed: ", seed

# https://github.com/mratsim/constantine/issues/366
# 22529 points leads to c = 13.
# BN254 on G2 transform 1 254-bit scalar into 4 65-bit scalars.
# 13 divides 65 and triggered an off-by-one edge case
var gs = newSeq[EC_ShortW_Aff[Fp2[BN254_Snarks], G2]](22529)
for g in gs.mitems():
  g.setGenerator()

var cs = newSeq[Fr[BN254_Snarks]](22529)
for c in cs.mitems():
  c = rng.random_long01Seq(Fr[BN254_Snarks])

var r_ref, r_opt: EC_ShortW_Jac[Fp2[BN254_Snarks], G2]
r_ref.multi_scalar_mul_reference_vartime(cs, gs)
r_opt.multi_scalar_mul_vartime(cs, gs)

doAssert bool(r_ref == r_opt)
echo "BN254 G2 MSM edge case #366 - SUCCESS"
