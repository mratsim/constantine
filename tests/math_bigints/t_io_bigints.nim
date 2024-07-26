# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/[unittest,times],
        constantine/math/io/io_bigints,
        constantine/platforms/abstractions,
        constantine/math/arithmetic,
        helpers/prng_unsafe

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_io_bigints xoshiro512** seed: ", seed

type T = BaseType

proc main() =
  suite "IO Hex - BigInt" & " [" & $WordBitWidth & "-bit words]":
    test "Parsing raw integers":
      block: # Sanity check
        let x = 0'u64
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].unmarshal(x_bytes, cpuEndian)

        check:
          T(big.limbs[0]) == 0

    test "Parsing and dumping round-trip on uint64":
      block:
        # "Little-endian" - 2^63
        let x = 1'u64 shl 63
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].unmarshal(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

        var r_bytes: array[8, byte]
        marshal(r_bytes, big, littleEndian)
        check: x_bytes == r_bytes

      block: # "Little-endian" - single random
        let x = rng.random_unsafe(uint64)
        let x_bytes = cast[array[8, byte]](x)
        let big = BigInt[64].unmarshal(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

        var r_bytes: array[8, byte]
        marshal(r_bytes, big, littleEndian)
        check: x_bytes == r_bytes

      block: # "Little-endian" - 10 random cases
        for _ in 0 ..< 10:
          let x = rng.random_unsafe(uint64)
          let x_bytes = cast[array[8, byte]](x)
          let big = BigInt[64].unmarshal(x_bytes, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

          var r_bytes: array[8, byte]
          marshal(r_bytes, big, littleEndian)
          check: x_bytes == r_bytes

    test "Round trip on elliptic curve constants":
      block: # Secp256r1 - NIST P-256
        const p = "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
        let x = BigInt[256].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

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

    test "Round trip on 3072-bit integer":
      const n = "0x75be9187192dccf08bedcb06c7fba60830840cb8a5c3a5895e63ffd78073f2f7e0ccc72ae2f91c2be9fe51e48373bf4426e6e1babb9bc5374747a0e24b982a27359cf403a6bb900800b6dd52b309788df7f599f3db6f5b5ba5fbe88b8d03ab32fbe8d75dbbad0178f70dc4dfbc39008e5c8a4975f08060f4af1718e1a8811b0b73daabf67bf971c1fa79d678e3e2bf878a844004d1ab5b11a2c3e4fa8abbbe15b75a4a15a4c0eecd128ad7b13571545a967cac88d1b1e88c3b09723849c54adede6b36dd21000f41bc404083bf01902d2d3591c2e51fe0cc26d691cbc9ba6ea3137bd977745cc8761c828f7d54899841701faeca7ff5fc975968693284c2dcaf68e9852a67b5782810834f2eed0ba8e69d18c2a9d8aa1d81528110f0156610febe5ee2db65add65006a9f91370828e356c7751fa50bb49f43b408cd2f4767a43bc57888afe01d2a85d457c68a3eb60de713b79c318b92cb1b2837cf78f9e6e5ec0091d2810a34a1c75400190f8582a8b42f436b799db088689f8187b6db8530d"

      block: # Big-Endian
        let x = BigInt[3072].fromHex(n)
        let h = x.toHex(bigEndian)

        check: n == h

      block: # Little-Endian
        let x = BigInt[3072].fromHex(n, littleEndian)
        let h = x.toHex(littleEndian)

        check: n == h

  suite "IO Decimal - BigInt" & " [" & $WordBitWidth & "-bit words]":
    test "Checks elliptic curve constants":
      block: # BLS12-381 - https://github.com/ethereum/py_ecc/blob/master/py_ecc/fields/field_properties.py
        const p = "4002409555221667393417789825735904156556882819939007885332058136124031650490837864442687629129015664037894272559787"
        const pHex = "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
        let x = BigInt[381].fromHex(pHex)
        let dec = x.toDecimal()

        check: p == dec

        let y = BigInt[381].fromDecimal(p)
        let hex = y.toHex()

        check: pHex == hex
main()
