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
  ../constantine/tower_field_extensions/[abelian_groups, fp6_1_plus_i],
  # Helpers
  ../helpers/static_for,
  ./bench_fields_template,
  # Standard library
  std/strutils

# ############################################################
#
#               Benchmark of 𝔽p2 = 𝔽p[𝑖]
#
# ############################################################


const Iters = 1_000_000
const InvIters = 1000
const AvailableCurves = [
  BN254,
  BLS12_381
]

proc main() =
  echo "-".repeat(80)
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    # addBench(Fp6[curve], Iters)
    # subBench(Fp6[curve], Iters)
    # negBench(Fp6[curve], Iters)
    # mulBench(Fp6[curve], Iters)
    sqrBench(Fp6[curve], Iters)
    # invBench(Fp6[curve], InvIters)
    echo "-".repeat(80)

main()

echo "Notes:"
echo "  GCC is significantly slower than Clang on multiprecision arithmetic."
