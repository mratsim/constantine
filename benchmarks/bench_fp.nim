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
  constantine/math/arithmetic,
  constantine/math/io/io_bigints,
  constantine/named/zoo_square_roots,
  # Helpers
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
  Edwards25519,
  Bandersnatch,
  Pallas,
  Vesta,
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
    mul2xUnrBench(Fp[curve], Iters)
    sqr2xUnrBench(Fp[curve], Iters)
    rdc2xBench(Fp[curve], Iters)
    smallSeparator()
    when not Fp[curve].isCrandallPrimeField():
      sumprodBench(Fp[curve], Iters)
      smallSeparator()
    toBigBench(Fp[curve], Iters)
    toFieldBench(Fp[curve], Iters)
    smallSeparator()
    invBench(Fp[curve], ExponentIters)
    invVartimeBench(Fp[curve], ExponentIters)
    isSquareBench(Fp[curve], ExponentIters)
    when not Fp[curve].isCrandallPrimeField(): # TODO implement
      sqrtBench(Fp[curve], ExponentIters)
      sqrtRatioBench(Fp[curve], ExponentIters)
      when curve == Bandersnatch:
        sqrtVartimeBench(Fp[curve], ExponentIters)
        sqrtRatioVartimeBench(Fp[curve], ExponentIters)
      # Exponentiation by a "secret" of size ~the curve order
      powBench(Fp[curve], ExponentIters)
      powVartimeBench(Fp[curve], ExponentIters)
    separator()

main()
notes()
