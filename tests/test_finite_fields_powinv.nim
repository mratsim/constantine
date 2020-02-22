# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/math/[bigints_checked, finite_fields],
        ../constantine/io/io_fields,
        ../constantine/config/curves

import ../constantine/io/io_bigints

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc main() =
  suite "Modular exponentiation over finite fields":
    test "n² mod 101":
      let exponent = BigInt[64].fromUint(2'u64)

      block: # 1^2 mod 101
        var n, expected: Fq[Fake101]

        n.fromUint(1'u32)
        expected = n

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.exportRawUint(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          1'u64 == r

      block: # 2^2 mod 101
        var n, expected: Fq[Fake101]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.exportRawUint(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          4'u64 == r

      block: # 10^2 mod 101
        var n, expected: Fq[Fake101]

        n.fromUint(10'u32)
        expected.fromUint(100'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.exportRawUint(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          100'u64 == r

      block: # 11^2 mod 101
        var n, expected: Fq[Fake101]

        n.fromUint(11'u32)
        expected.fromUint(20'u32)

        n.pow(exponent)

        var n_bytes: array[8, byte]
        n_bytes.exportRawUint(n, cpuEndian)
        let r = cast[uint64](n_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(n == expected)
          # Check equality when converting back to natural domain
          20'u64 == r

main()
