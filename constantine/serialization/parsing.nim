# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/[primitives, fileio],
  ./endians

template `?`*(parseCall: bool): untyped =
  ## Return early if parsing failed
  ## Syntax `?parseCall()`
  if not parseCall:
    return false

proc parseInt*(f: File, v: var SomeInteger, endianness: static Endianness): bool =
  when endianness == cpuEndian:
    return f.readInto(v)
  else:
    var raw {.noInit.}: array[sizeof(v), byte]
    if not f.readInto(raw):
      return false

    # endianness / raw bytes are fundamentally unsigned
    type T = typeof(v)
    when sizeof(v) == 8:
      v = cast[T](uint64.fromBytes(raw, endianness))
    elif sizeof(v) == 4:
      v = cast[T](uint32.fromBytes(raw, endianness))
    elif sizeof(v) == 2:
      v = cast[T](uint16.fromBytes(raw, endianness))
    elif sizeof(v) == 1:
      v = cast[T](uint8.fromBytes(raw, endianness))
    else:
      unreachable()

    return true
