# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/[curves, common],
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
  ../constantine/curves/[zoo_inversions, zoo_square_roots],
  # Helpers
  ../helpers/static_for,
  ./bench_fields_template

# ############################################################
#
#                  Benchmark of 𝔽p
#
# ############################################################


const Iters = 100_000
const ExponentIters = 100
const AvailableCurves = [
  # P224,
  BN254_Nogami,
  BN254_Snarks,
  Curve25519,
  Bandersnatch,
  P256,
  Secp256k1,
  BLS12_377,
  BLS12_381,
  BW6_761
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(Fp[curve], Iters)
    subBench(Fp[curve], Iters)
    negBench(Fp[curve], Iters)
    ccopyBench(Fp[curve], Iters)
    div2Bench(Fp[curve], Iters)
    mulBench(Fp[curve], Iters)
    sqrBench(Fp[curve], Iters)
    smallSeparator()
    invEuclidBench(Fp[curve], ExponentIters)
    invPowFermatBench(Fp[curve], ExponentIters)
    sqrtBench(Fp[curve], ExponentIters)
    sqrtRatioBench(Fp[curve], ExponentIters)
    # Exponentiation by a "secret" of size ~the curve order
    powBench(Fp[curve], ExponentIters)
    powUnsafeBench(Fp[curve], ExponentIters)
    separator()

main()
notes()
