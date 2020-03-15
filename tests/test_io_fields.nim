# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/io/[io_bigints, io_fields],
        ../constantine/config/curves,
        ../constantine/config/common,
        ../constantine/arithmetic/[bigints, finite_fields]

randomize(0xDEADBEEF) # Random seed for reproducibility
type T = BaseType

proc main() =
  suite "IO - Finite fields":
    test "Parsing and serializing round-trip on uint64":
      block:
        # "Little-endian" - 0
        let x = 0'u64
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 1
        let x = 1'u64
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 2^31
        let x = 1'u64 shl 31
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      block:
        # "Little-endian" - 2^32
        let x = 1'u64 shl 32
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne61]
        f.fromUint(x)

        var r_bytes: array[8, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes

      # Mersenne 127 ---------------------------------
      block:
        # "Little-endian" - 2^63
        let x = 1'u64 shl 63
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne127]
        f.fromUint(x)

        var r_bytes: array[16, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes[0 ..< 8]

      block: # "Little-endian" - single random
        let x = uint64 rand(0..high(int))
        let x_bytes = cast[array[8, byte]](x)
        var f: Fp[Mersenne127]
        f.fromUint(x)

        var r_bytes: array[16, byte]
        exportRawUint(r_bytes, f, littleEndian)
        check: x_bytes == r_bytes[0 ..< 8]

      block: # "Little-endian" - 10 random cases
        for _ in 0 ..< 10:
          let x = uint64 rand(0..high(int))
          let x_bytes = cast[array[8, byte]](x)
          var f: Fp[Mersenne127]
          f.fromUint(x)

          var r_bytes: array[16, byte]
          exportRawUint(r_bytes, f, littleEndian)
          check: x_bytes == r_bytes[0 ..< 8]

    test "Round trip on large constant":
      block: # 2^126
        const p = "0x40000000000000000000000000000000"
        let x = Fp[Mersenne127].fromBig BigInt[127].fromHex(p)
        let hex = x.toHex(bigEndian)

        check: p == hex

main()
