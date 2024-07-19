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
  constantine/math/extension_fields,
  # Helpers
  ./bench_gt_template

# ############################################################
#
#               Benchmark of the 𝔾ₜ group of
#                  Pairing Friendly curves
#
# ############################################################

const Iters = 10000
const ExpIters = 1000
const AvailableCurves = [
  # BN254_Nogami,
  BN254_Snarks,
  # BLS12_377,
  BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    separator()
    mulBench(Fp12[curve], Iters)
    sqrBench(Fp12[curve], Iters)
    invBench(Fp12[curve], Iters)
    separator()
    cyclotomicSquare_Bench(Fp12[curve], Iters)
    cyclotomicInv_Bench(Fp12[curve], Iters)
    cyclotomicSquareCompressed_Bench(Fp12[curve], Iters)
    cyclotomicDecompression_Bench(Fp12[curve], Iters)
    separator()
    powVartimeBench(Fp12[curve], window = 2, ExpIters)
    powVartimeBench(Fp12[curve], window = 3, ExpIters)
    powVartimeBench(Fp12[curve], window = 4, ExpIters)
    separator()
    gtExp_sqrmul_vartimeBench(Fp12[curve], ExpIters)
    gtExp_jy00_vartimeBench(Fp12[curve], ExpIters)
    separator()
    gtExp_wNAF_vartimeBench(Fp12[curve], window = 2, ExpIters)
    gtExp_wNAF_vartimeBench(Fp12[curve], window = 3, ExpIters)
    gtExp_wNAF_vartimeBench(Fp12[curve], window = 4, ExpIters)
    separator()
    gtExp_endo_wNAF_vartimeBench(Fp12[curve], window = 2, ExpIters)
    gtExp_endo_wNAF_vartimeBench(Fp12[curve], window = 3, ExpIters)
    gtExp_endo_wNAF_vartimeBench(Fp12[curve], window = 4, ExpIters)
    separator()
    gtExpEndo_constanttimeBench(Fp12[curve], ExpIters)
    separator()


main()
notes()
