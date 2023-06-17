# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../platforms/abstractions

# perf critical we don't want bound checks here
# So no checks and we avoid signed int to ensur eno exceptions.
# TODO: Nim formal verification: https://nim-lang.org/docs/drnim.html
{.push checks:off, raises: [].}

template toByte*(x: SomeUnsignedInt): byte =
  ## At compile-time, conversion to bytes checks the range
  ## we want to ensure this is done at the register level
  ## at runtime in a single "mov byte" instruction
  when nimvm:
    byte(x and 0xFF)
  else:
    byte(x)

template blobFrom*(dst: var openArray[byte], src: SomeUnsignedInt, startIdx: int, endian: static Endianness) =
  ## Write an integer into a raw binary blob
  ## Swapping endianness if needed
  ## startidx is the first written array item if littleEndian is requested
  ## or the last if bigEndian is requested
  when endian == cpuEndian:
    for i in 0 ..< sizeof(src):
      dst[startIdx+i] = toByte(src shr (i * 8))
  else:
    for i in 0 ..< sizeof(src):
      dst[startIdx+sizeof(src)-1-i] = toByte(src shr (i * 8))

func parseFromBlob*(
           dst: var SomeUnsignedInt,
           src: openArray[byte],
           cursor: var uint, endian: static Endianness) {.inline.} =
  ## Read an unsigned integer from a raw binary blob.
  ## The `cursor` represents the current index in the array and is updated
  ## by N bytes where N is the size of `dst` type in bytes.
  ## The binary blob is interpreted as:
  ## - an array of words traversed from 0 ..< len (little-endian), via an incremented `cursor`
  ## - with each word being of `endian` ordering for deserialization purpose.
  debug:
    doAssert 0 <= cursor and cursor < src.len.uint
    doAssert cursor + sizeof(dst).uint <= src.len.uint,
      "cursor (" & $cursor & ") + sizeof(dst) (" & $sizeof(dst) &
      ") <= src.len (" & $src.len & ")"

  type U = typeof(dst)
  const L = sizeof(dst)

  var accum: U = 0
  when endian == littleEndian:
    for i in 0'u ..< L:
      accum = accum or (U(src[cursor+i]) shl (i * 8))
  else:
    for i in 0'u ..< L:
      accum = accum or (U(src[cursor+i]) shl ((L - 1 - i) * 8))
  dst = accum
  cursor.inc(L)

func dumpRawInt*(
           dst: var openArray[byte],
           src: SomeUnsignedInt,
           cursor: uint, endian: static Endianness) {.inline.} =
  ## Dump an integer into raw binary form
  ## The `cursor` represents the current index in the array and is updated
  ## by N bytes where N is the size of `src` type in bytes.
  ## The binary blob is interpreted as:
  ## - an array of words traversed from 0 ..< len (little-endian), via an incremented `cursor`
  ## - with each word being of `endian` ordering for deserialization purpose.
  debug:
    doAssert 0 <= cursor and cursor < dst.len.uint
    doAssert cursor + sizeof(src).uint <= dst.len.uint,
      "cursor (" & $cursor & ") + sizeof(src) (" & $sizeof(src) &
      ") <= dst.len (" & $dst.len & ")"

  const L = uint sizeof(src)

  when endian == littleEndian:
    for i in 0'u ..< L:
      dst[cursor+i] = toByte(src shr (i * 8))
  else:
    for i in 0'u ..< L:
      dst[cursor+i] = toByte(src shr ((L-i-1) * 8))

func toBytes*(num: SomeUnsignedInt, endianness: static Endianness): array[sizeof(num), byte] {.noInit, inline.}=
  ## Store an integer into an array of bytes
  ## in big endian representation
  const L = sizeof(num)
  when endianness == bigEndian:
    for i in 0 ..< L:
      result[i] = toByte(num shr ((L-1-i) * 8))
  else:
    for i in 0 ..< L:
      result[i] = toByte(num shr (i * 8))

func fromBytes*(T: type SomeUnsignedInt, bytes: openArray[byte], endianness: static Endianness): T {.inline.} =
  const L = sizeof(T)
  debug:
    doAssert bytes.len == L

  # Note: result is zero-init
  when endianness == cpuEndian:
    for i in 0 ..< L:
      result = result or (T(bytes[i]) shl (i*8))
  else:
    for i in 0 ..< L:
      result = result or (T(bytes[i]) shl ((L-1-i) * 8))