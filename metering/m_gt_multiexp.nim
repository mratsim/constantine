# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/times,
  constantine/platforms/abstractions,
  constantine/platforms/metering/[reports, tracer],
  constantine/named/algebras,
  constantine/named/zoo_subgroups,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/pairings/[gt_multiexp, pairings_generic],
  # Helpers
  helpers/prng_unsafe

var rng*: RngState
let seed = 777
rng.seed(seed)
echo "metering xoshiro512** seed: ", seed

func random_gt(rng: var RngState, F: typedesc): F {.noInit.} =
  result = rng.random_unsafe(F)
  result.finalExp()
  debug: doAssert bool result.isInPairingSubgroup()

proc genBatch(rng: var RngState, GT: typedesc, numPoints: int): (seq[GT], seq[Fr[GT.Name].getBigInt()]) =
  var elems = newSeq[GT](numPoints)
  var exponents = newSeq[Fr[GT.Name]](numPoints)

  for i in 0 ..< numPoints:
    elems[i] = rng.random_gt(GT)
    exponents[i] = rng.random_unsafe(Fr[GT.Name])
    
  var exponents_big = newSeq[Fr[GT.Name].getBigInt()](numPoints)
  exponents_big.asUnchecked().batchFromField(exponents.asUnchecked(), numPoints)
  
  return (elems, exponents_big)
  
proc mexpMeter[bits: static int](elems: openArray[AnyFp12], exponents: openArray[BigInt[bits]], useTorus: static bool) =
  var r{.noInit.}: AnyFp12
  r.setZero()
  resetMetering()
  r.multiExp_vartime(elems, exponents, useTorus)

type GT_12o6 = QuadraticExt[Fp6[BLS12_381]]
type GT_12o4 = CubicExt[Fp4[BLS12_381]]

type GT = GT_12o6
const N = 256
const useTorus = true

echo "Config: GT = ", $GT, ", N = ", N, ", use-torus = ", useTorus

resetMetering()
let (elems, exponents) = rng.genBatch(GT, N)
resetMetering()

mexpMeter(elems, exponents, useTorus)
const flags = if UseASM_X86_64 or UseASM_X86_32: "UseAssembly" else: "NoAssembly"

reportCli(Metrics, flags)
