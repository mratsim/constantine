# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/curves,
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
  # Helpers
  ../helpers/static_for,
  ./bench_fields_template,
  # Standard library
  std/strutils

# ############################################################
#
#                  Benchmark of 𝔽p
#
# ############################################################


const Iters = 1_000_000
const ExponentIters = 1000
const AvailableCurves = [
  # P224,
  # BN254_Nogami,
  BN254_Snarks,
  # Curve25519,
  # P256,
  # Secp256k1,
  # BLS12_377,
  BLS12_381,
  # BN446,
  # FKM12_447,
  # BLS12_461,
  # BN462
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(Fp[curve], Iters)
    subBench(Fp[curve], Iters)
    negBench(Fp[curve], Iters)
    mulBench(Fp[curve], Iters)
    sqrBench(Fp[curve], Iters)
    invBench(Fp[curve], ExponentIters)
    powFermatInversionBench(Fp[curve], ExponentIters)
    sqrtBench(Fp[curve], ExponentIters)
    # Exponentiation by a "secret" of size ~the curve order
    powBench(Fp[curve], ExponentIters)
    powUnsafeBench(Fp[curve], ExponentIters)
    separator()

main()
notes()
