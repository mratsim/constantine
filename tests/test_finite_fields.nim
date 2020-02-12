# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/math/finite_fields,
        ../constantine/io/io_fields,
        ../constantine/config/curves

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc main() =
  suite "Basic arithmetic over finite fields":
    test "Addition mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(10'u32)
        z.fromUint(90'u32)

        x += y
        check: bool(z == x)

main()
