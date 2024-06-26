# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/times,
  constantine/platforms/metering/[reports, tracer],
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  constantine/named/zoo_subgroups,
  constantine/math/elliptic/ec_multi_scalar_mul,
  constantine/platforms/abstractions,
  # Helpers
  helpers/prng_unsafe

var rng*: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "bench xoshiro512** seed: ", seed

proc msmMeter*(EC: typedesc, numPoints: int) =
  const bits = EC.getScalarField().bits()
  var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](numPoints)
  var scalars = newSeq[BigInt[bits]](numPoints)

  for i in 0 ..< numPoints:
    var tmp = rng.random_unsafe(EC)
    tmp.clearCofactor()
    points[i].affine(tmp)
    scalars[i] = rng.random_unsafe(BigInt[bits])

  var r{.noInit.}: EC
  r.setinf()
  resetMetering()
  r.multiScalarMul_vartime(scalars, points)

resetMetering()
msmMeter(EC_ShortW_Jac[Fp[BLS12_381], G1], 10000)
const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"
reportCli(Metrics, flags)
