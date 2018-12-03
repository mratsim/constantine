# constantine
# Copyright (c) 2018 Status Research & Development GmbH
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

  test "Parsing and dumping round-trip":
    block: # "Little-endian"
      let x = 1'u64 shl 63
      let x_bytes = cast[array[8, byte]](x)
      let big = parseRawUint(x_bytes, 64, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

      var r_bytes: array[8, byte]
      dumpRawUint(r_bytes, big, littleEndian)
      check: x_bytes == r_bytes

    # block: # "Little-endian"
    #   let x = uint64 rand(0..high(int))
    #   let x_bytes = cast[array[8, byte]](x)
    #   let big = parseRawUint(x_bytes, 64, littleEndian) # It's fine even on big-endian platform. We only want the byte-pattern

    #   var r_bytes: array[8, byte]
    #   dumpRawUint(r_bytes, big, littleEndian)
    #   check: x_bytes == r_bytes
