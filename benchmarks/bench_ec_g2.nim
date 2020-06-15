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
  ../constantine/towers,
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


const Iters = 500_000
const MulIters = 500
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
    addBench(ECP_SWei_Proj[Fp2[curve]], Iters)
    separator()
    doublingBench(ECP_SWei_Proj[Fp2[curve]], Iters)
    separator()
    scalarMulUnsafeDoubleAddBench(ECP_SWei_Proj[Fp2[curve]], MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp2[curve]], scratchSpaceSize = 1 shl 2, MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp2[curve]], scratchSpaceSize = 1 shl 3, MulIters)
    separator()
    scalarMulGenericBench(ECP_SWei_Proj[Fp2[curve]], scratchSpaceSize = 1 shl 4, MulIters)
    separator()
    # scalarMulEndo(ECP_SWei_Proj[Fp2[curve]], MulIters)
    # separator()
  separator()

main()

echo "\nNotes:"
echo "  - GCC is significantly slower than Clang on multiprecision arithmetic."
echo "  - The simplest operations might be optimized away by the compiler."
echo "  - Fast Squaring and Fast Multiplication are possible if there are spare bits in the prime representation (i.e. the prime uses 254 bits out of 256 bits)"
