# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/io/io_bigints,
        ../constantine/config/common,
        ../constantine/math/bigints_checked

randomize(0xDEADBEEF) # Random seed for reproducibility
type T = BaseType

proc main() =
  suite "IO":
    test "Parsing raw integers":
      block: # Sanity check
        let x = 0'u64
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].fromRawUint(x_bytes, cpuEndian)

        check:
          T(big.limbs[0]) == 0
          T(big.limbs[1]) == 0

    test "Parsing and dumping round-trip on uint64":
      block:
        # "Little-endian" - 2^63
        let x = 1'u64 shl 63
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].fromRawUint(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

        var r_bytes: array[8, byte]
        serializeRawUint(r_bytes, big, littleEndian)
        check: x_bytes == r_bytes

      block: # "Little-endian" - single random
        let x = uint64 rand(0..high(int))
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].fromRawUint(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

        var r_bytes: array[8, byte]
        serializeRawUint(r_bytes, big, littleEndian)
        check: x_bytes == r_bytes

      block: # "Little-endian" - 10 random cases
        for _ in 0 ..< 10:
          let x = uint64 rand(0..high(int))
          let x_bytes = cast[array[8, byte]](x)
          let big = BigInt[64].fromRawUint(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

          var r_bytes: array[8, byte]
          serializeRawUint(r_bytes, big, littleEndian)
          check: x_bytes == r_bytes

    test "Round trip on elliptic curve constants":
      block: # Secp256k1 - https://en.bitcoin.it/wiki/Secp256k1
        const p = "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
        let x = BigInt[256].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

      block: # BN254 - https://github.com/ethereum/py_ecc/blob/master/py_ecc/fields/field_properties.py
        const p = "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
        let x = BigInt[254].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

      block: # BLS12-381 - https://github.com/ethereum/py_ecc/blob/master/py_ecc/fields/field_properties.py
        const p = "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
        let x = BigInt[381].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

main()
