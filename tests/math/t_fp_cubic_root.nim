# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest,
        ../../constantine/platforms/abstractions,
        ../../constantine/math/arithmetic,
        ../../constantine/math/config/curves,
        ../../constantine/math/curves/zoo_endomorphisms

echo "\n------------------------------------------------------\n"

proc checkCubeRootOfUnity(curve: static Curve) =
  test $curve & " cube root of unity (mod p)":
    var cru = curve.getCubicRootOfUnity_mod_p()
    cru.square()
    cru *= curve.getCubicRootOfUnity_mod_p()

    check: bool cru.isOne()

proc main() =
  suite "Sanity checks on precomputed values" & " [" & $WordBitwidth & "-bit mode]":
    checkCubeRootOfUnity(BN254_Snarks)
    checkCubeRootOfUnity(BLS12_377)
    checkCubeRootOfUnity(BLS12_381)

main()
