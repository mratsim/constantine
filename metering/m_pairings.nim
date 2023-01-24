# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/times,
  ./reports, ./tracer,
  ../constantine/math/config/[common, curves],
  ../constantine/math/[arithmetic, extension_fields],
  ../constantine/math/elliptic/ec_shortweierstrass_projective,
  ../constantine/math/constants/zoo_subgroups,
  ../constantine/math/pairings/pairings_bls12,
  # Helpers
  ../helpers/prng_unsafe

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactor()

proc pairingBLS12Meter*(C: static Curve) =
  let
    P = rng.random_point(ECP_ShortW_Prj[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])

  var f: Fp12[C]

  resetMetering()
  f.pairing_bls12(P, Q)

resetMetering()
pairingBLS12Meter(BLS12_381)
const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
reportCli(Metrics, flags)
