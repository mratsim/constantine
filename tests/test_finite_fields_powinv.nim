# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest,
        ../constantine/arithmetic/[bigints, finite_fields],
        ../constantine/io/[io_bigints, io_fields],
        ../constantine/config/curves

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc main() =
  suite "Modular exponentiation over finite fields":
    test "n² mod 101":
      let exponent = BigInt[64].fromUint(2'u64)

      block: # 1*1 mod 101
        var n, expected: Fp[Fake101]

        n.fromUint(1'u32)
        expected = n

        var r: Fp[Fake101]
        r.prod(n, n)

        var r_bytes: array[8, byte]
        r_bytes.exportRawUint(r, cpuEndian)
        let rU64 = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(r == expected)
          # Check equality when converting back to natural domain
          1'u64 == rU64

      block: # 1^2 mod 101
        var n, expected: Fp[Fake101]

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
        var n, expected: Fp[Fake101]

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
        var n, expected: Fp[Fake101]

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
        var n, expected: Fp[Fake101]

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

    test "x^(p-2) mod p (modular inversion if p prime)":
      block:
        var x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
        # BLS12-381 prime - 2
        let exponent = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"

        x.pow(exponent)
        let computed = x.toHex()

        check:
          computed == expected

      block:
        var x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
        # BLS12-381 prime - 2
        let exponent = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaa9")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"

        x.powUnsafeExponent(exponent)
        let computed = x.toHex()

        check:
          computed == expected

  suite "Modular inversion over prime fields":
    test "x^(-1) mod p":
        var x: Fp[BLS12_381]

        # BN254 field modulus
        x.fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")

        let expected = "0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8"
        x.inv()
        let computed = x.toHex()

        check:
          computed == expected

main()
