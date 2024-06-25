# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest,
        constantine/platforms/abstractions,
        constantine/math/arithmetic,
        constantine/math/io/io_fields,
        constantine/named/algebras

echo "\n------------------------------------------------------\n"

proc main() =
  suite "Finite field conditional arithmetic":
    test "Conditional substraction borrow bug":
      let a = FP[BN254_Snarks].fromHex"0x14ae3e4392eb3238968c7624ee3d041590392e289e4f0bdfac4b6e56ac8cf768"
      let b = FP[BN254_Snarks].fromHex"0x24e810017b4c0630a0b35b5c63a377097533928b31fa95d58d0e08d1f98b16c6"

      let expected = FP[BN254_Snarks].fromHex"0x202a7cb4f8d0cc31ae29607f0c1ae569b287062ed4c640975b5df19b8b7edde9"

      var normalsub: Fp[BN254_Snarks]
      normalsub.diff(a, b)

      var condsub = a
      condsub.csub(b, CtTrue)

      check:
        bool(normalsub == expected)
        bool(condsub == expected)

main()
