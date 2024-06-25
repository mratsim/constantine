# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/[unittest, times],
        constantine/math/io/[io_bigints, io_fields],
        constantine/named/algebras,
        constantine/platforms/abstractions,
        constantine/math/arithmetic,
        helpers/prng_unsafe

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_io_fields xoshiro512** seed: ", seed

proc main() =
  suite "IO - Finite fields" & " [" & $WordBitWidth & "-bit words]":
    test "Parsing and serializing round-trip on uint64":
      # 101 ---------------------------------
      block:
        # "Little-endian" - 0
        let x = BaseType(0)
        let x_bytes = cast[array[sizeof(BaseType), byte]](x)
        var f: Fp[Fake101]
        f.fromUint(x)

        var r_bytes: array[sizeof(BaseType), byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 1
        let x = BaseType(1)
        let x_bytes = cast[array[sizeof(BaseType), byte]](x)
        var f: Fp[Fake101]
        f.fromUint(x)

        var r_bytes: array[sizeof(BaseType), byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      # Mersenne 61 ---------------------------------
      block:
        # "Little-endian" - 0
        let x = 0'u64
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 1
        let x = 1'u64
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 2^31
        let x = 1'u64 shl 31
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 2^32
        let x = 1'u64 shl 32
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      # Mersenne 127 ---------------------------------
      block:
        # "Little-endian" - 2^63
        let x = 1'u64 shl 63
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne127]
        f.fromUint(x)

        var r_bytes: array[16, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes[0 ..< 8]

      block: # "Little-endian" - single random
        let x = rng.random_unsafe(uint64)
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne127]
        f.fromUint(x)

        var r_bytes: array[16, byte]
        marshal(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes[0 ..< 8]

      block: # "Little-endian" - 10 random cases
        for _ in 0 ..< 10:
          let x = rng.random_unsafe(uint64)
          let x_bytes = cast[array[8, byte]](x)
          var f: Fp[Mersenne127]
          f.fromUint(x)

          var r_bytes: array[16, byte]
          marshal(r_bytes, f, littleEndian)
          check: x_bytes == r_bytes[0 ..< 8]

    test "Round trip on large constant":
      block: # 2^126
        const p = "0x40000000000000000000000000000000"
        let x = Fp[Mersenne127].fromBig BigInt[127].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

    test "Round trip on prime field of NIST P256 (secp256r1) curve":
      block: # 2^126
        const p = "0x0000000000000000000000000000000040000000000000000000000000000000"
        let x = Fp[P256].fromBig BigInt[256].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

    test "Round trip on prime field of BN254 Snarks curve":
      block: # 2^126
        const p = "0x0000000000000000000000000000000040000000000000000000000000000000"
        let x = Fp[BN254_Snarks].fromBig BigInt[254].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

    test "Round trip on prime field of BLS12_381 curve":
      block: # 2^126
        const p = "0x000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000"
        let x = Fp[BLS12_381].fromBig BigInt[381].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

    test "Fuzz #1 - incorrect reduction of BigInt":
      block:
        var a{.noInit.}: Fp[BN254_Snarks]
        a.fromBig(BigInt[254].fromHex("0xdd1119d0c5b065898a0848e21c209153f4622f06cb763e7ef00eef28b94780f8"))

        var b{.noInit.}: Fp[BN254_Snarks]
        b.fromBig(BigInt[254].fromHex("0x1b7fe00540e9e4e2a8c73208161b2fdd965c84c129af1449ff8cbecd57538bdc"))

        doAssert bool(a == b)

main()
