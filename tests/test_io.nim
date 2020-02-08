# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/[io, bigints]

randomize(0xDEADBEEF) # Random seed for reproducibility
type T = BaseType

suite "IO":
  test "Parsing raw integers":
    block: # Sanity check
      let x = 0'u64
      let x_bytes = cast[array[8, byte]](x)
      let big = parseRawUint(x_bytes, 64, cpuEndian)

      check:
        T(big[0]) == 0
        T(big[1]) == 0

    block: # 2^63 is properly represented on 2 limbs
      let x = 1'u64 shl 63
      let x_bytes = cast[array[8, byte]](x)
      let big = parseRawUint(x_bytes, 64, cpuEndian)

      check:
        T(big[0]) == 0
        T(big[1]) == 1

  test "Parsing and dumping round-trip on uint64":
    block:
      # "Little-endian" - 2^63
      let x = 1'u64 shl 63
      let x_bytes = cast[array[8, byte]](x)
      let big = parseRawUint(x_bytes, 64, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

      var r_bytes: array[8, byte]
      dumpRawUint(r_bytes, big, littleEndian)
      check: x_bytes == r_bytes

    block: # "Little-endian" - single random
      let x = uint64 rand(0..high(int))
      let x_bytes = cast[array[8, byte]](x)
      let big = parseRawUint(x_bytes, 64, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

      var r_bytes: array[8, byte]
      dumpRawUint(r_bytes, big, littleEndian)
      check: x_bytes == r_bytes

    block: # "Little-endian" - 10 random cases
      for _ in 0 ..< 10:
        let x = uint64 rand(0..high(int))
        let x_bytes = cast[array[8, byte]](x)
        let big = parseRawUint(x_bytes, 64, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

        var r_bytes: array[8, byte]
        dumpRawUint(r_bytes, big, littleEndian)
        check: x_bytes == r_bytes

  test "Round trip on elliptic curve constants":
    block: # Secp256k1 - https://en.bitcoin.it/wiki/Secp256k1
      const p = "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
      let x = fromHex(BigInt[256], p)
      let hex = x.dumpHex(bigEndian)

      check: p == hex

    block: # alt-BN128 - https://github.com/ethereum/py_ecc/blob/master/py_ecc/fields/field_properties.py
      const p = "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
      let x = fromHex(BigInt[254], p)
      let hex = x.dumpHex(bigEndian)

      check: p == hex

    block: # BLS12-381 - https://github.com/ethereum/py_ecc/blob/master/py_ecc/fields/field_properties.py
      const p = "1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
      let x = fromHex(BigInt[381], p)
      let hex = x.dumpHex(bigEndian)

      check: p == hex
