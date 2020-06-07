# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest,
        ../constantine/arithmetic,
        ../constantine/config/curves,
        ../constantine/io/io_fields

proc checkCubeRootOfUnity(curve: static Curve) =
  test $curve & " cube root of unity":
    var cru = curve.getCubicRootOfUnity()
    cru.square()
    cru *= curve.getCubicRootOfUnity()

    check: bool cru.isOne()

proc main() =
  suite "Sanity checks on precomputed values":
    checkCubeRootOfUnity(BN254_Snarks)
    checkCubeRootOfUnity(BLS12_381)

main()
