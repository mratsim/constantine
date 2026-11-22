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
  constantine/math/elliptic/[
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended],
  # Helpers
  ./bench_elliptic_template

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 10_000_000
const MulIters = 100
const AvailableCurves = [
  # P224,
  # BN254_Nogami,
  # BN254_Snarks,
  # Edwards25519,
  # P256,
  Secp256k1,
  # Pallas,
  # Vesta,
  # BLS12_377,
  # BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    # addBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    # addBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    # mixedAddBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    # mixedAddBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    # mixedAddBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    # doublingBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    # doublingBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    # doublingBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    # separator()
    # affFromProjBench(EC_ShortW_Prj[Fp[curve], G1], MulIters)
    # affFromJacBench(EC_ShortW_Jac[Fp[curve], G1], MulIters)
    # separator()
    # for numPoints in [10, 100, 1000, 10000]:
    #   let batchIters = max(1, Iters div numPoints)
    #   affFromProjBatchBench(EC_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    # separator()
    # for numPoints in [10, 100, 1000, 10000]:
    #   let batchIters = max(1, Iters div numPoints)
    #   affFromProjBatchBench(EC_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    # separator()
    # for numPoints in [10, 100, 1000, 10000]:
    #   let batchIters = max(1, Iters div numPoints)
    #   affFromJacBatchBench(EC_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    # separator()
    # for numPoints in [10, 100, 1000, 10000]:
    #   let batchIters = max(1, Iters div numPoints)
    #   affFromJacBatchBench(EC_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    # separator()
    separator()

main()
notes()
