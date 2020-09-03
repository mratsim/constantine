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
  ../constantine/elliptic/ec_weierstrass_projective,
  # Helpers
  ../helpers/static_for,
  ./bench_elliptic_template,
  # Standard library
  std/strutils

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 1_000_000
const MulIters = 1000
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
    addBench(ECP_SWei_Proj[Fp[curve]], Iters)
    separator()
    doublingBench(ECP_SWei_Proj[Fp[curve]], Iters)
    separator()
    scalarMulUnsafeDoubleAddBench(ECP_SWei_Proj[Fp[curve]], MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp[curve]], window = 2, MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp[curve]], window = 3, MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp[curve]], window = 4, MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp[curve]], window = 5, MulIters)
    separator()
    scalarMulEndo(ECP_SWei_Proj[Fp[curve]], MulIters)
    separator()
    scalarMulEndoWindow(ECP_SWei_Proj[Fp[curve]], MulIters)
    separator()
    separator()

main()
notes()
