# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest,
        ../constantine/config/common,
        ../constantine/arithmetic,
        ../constantine/config/curves,
        ../constantine/io/[io_bigints, io_fields]

echo "\n------------------------------------------------------\n"

proc checkCubeRootOfUnity(curve: static Curve) =
  test $curve & " cube root of unity (mod p)":
    var cru = curve.getCubicRootOfUnity_mod_p()
    cru.square()
    cru *= curve.getCubicRootOfUnity_mod_p()

    check: bool cru.isOne()

  test $curve & " cube root of unity (mod r)":
    var cru: BigInt[3 * curve.getCurveOrderBitwidth()]
    cru.prod(curve.getCubicRootOfUnity_mod_r(), curve.getCubicRootOfUnity_mod_r())
    cru.prod(cru, curve.getCubicRootOfUnity_mod_r())

    var r: BigInt[curve.getCurveOrderBitwidth()]
    r.reduce(cru, curve.getCurveOrder)

    check: bool r.isOne()

proc main() =
  suite "Sanity checks on precomputed values" & " [" & $WordBitwidth & "-bit mode]":
    checkCubeRootOfUnity(BN254_Snarks)
    # checkCubeRootOfUnity(BLS12_381)

main()
