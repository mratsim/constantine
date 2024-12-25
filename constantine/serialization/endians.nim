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

func blobFrom*(dst: var openArray[byte], src: SomeUnsignedInt, startIdx: int, endian: static Endianness) {.inline.} =
  ## Write an integer into a raw binary blob
  ## The whole binary blob is interpreted as big-endian/little-endian
  ## Swapping endianness if needed
  ## startidx is the first written array item if littleEndian is requested
  ## or the last if bigEndian is requested
  when endian == cpuEndian:
    for i in 0 ..< sizeof(src):
      dst[startIdx+i] = toByte(src shr (i * 8))
  else:
    for i in 0 ..< sizeof(src):
      dst[startIdx+sizeof(src)-1-i] = toByte(src shr (i * 8))

func dumpRawInt*(
           dst: var openArray[byte],
           src: SomeUnsignedInt,
           cursor: int, endian: static Endianness) {.inline.} =
  ## Dump an integer into raw binary form
  ## The `cursor` represents the current index in the array
  ## The binary blob is interpreted as:
  ## - an array of words traversed from 0 ..< len (little-endian), via an incremented `cursor`
  ## - with each word being of `endian` ordering for deserialization purpose.
  debug:
    doAssert 0 <= cursor and cursor < dst.len.uint
    doAssert cursor + sizeof(src).uint <= dst.len.uint,
      "cursor (" & $cursor & ") + sizeof(src) (" & $sizeof(src) &
      ") <= dst.len (" & $dst.len & ")"

  const L = sizeof(src)

  when endian == littleEndian:
    for i in 0 ..< L:
      dst[cursor+i] = toByte(src shr (i * 8))
  else:
    for i in 0 ..< L:
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

func fromBytes*(T: type SomeUnsignedInt, bytes: array[sizeof(T), byte], endianness: static Endianness): T {.inline.} =
  const L = sizeof(T)
  # Note: result is zero-init
  when endianness == cpuEndian:
    for i in 0 ..< L:
      result = result or (T(bytes[i]) shl (i*8))
  else:
    for i in 0 ..< L:
      result = result or (T(bytes[i]) shl ((L-1-i) * 8))

template fromBytesImpl(
      r: var SomeUnsignedInt,
      bytes: openArray[byte] or ptr UncheckedArray[byte],
      offset: int,
      endianness: static Endianness) =
  # With a function array[N, byte] doesn't match "openArray[byte] or something"
  # https://github.com/nim-lang/Nim/issues/7432
  type T = typeof(r)
  const L = sizeof(r)
  r.reset()
  when endianness == cpuEndian:
    for i in 0 ..< L:
      r = r or (T(bytes[i+offset]) shl (i*8))
  else:
    for i in 0 ..< L:
      r = r or (T(bytes[i+offset]) shl ((L-1-i) * 8))

func fromBytes*(
      T: type SomeUnsignedInt,
      bytes: openArray[byte],
      offset: int,
      endianness: static Endianness): T {.inline.} =
  ## Read an unsigned integer from a raw binary blob.
  ## The `offset` represents the current index in the array
  ## The binary blob is interpreted as:
  ## - an array of words traversed from 0 ..< len (little-endian)
  ## - with each word being of `endian` ordering for deserialization purpose.
  debug:
    doAssert 0 <= offset and offset < bytes.len
    doAssert offset + sizeof(T) <= bytes.len,
      "offset (" & $offset & ") + sizeof(T) (" & $sizeof(T) &
      ") <= bytes.len (" & $bytes.len & ")"

  result.fromBytesImpl(bytes, offset, endianness)

func fromBytes*(
      T: type SomeUnsignedInt,
      bytes: ptr UncheckedArray[byte],
      offset: int,
      endianness: static Endianness): T {.inline.} =
  ## Read an unsigned integer from a raw binary blob.
  ## The `offset` represents the current index in the array
  ## The binary blob is interpreted as:
  ## - an array of words traversed from 0 ..< len (little-endian)
  ## - with each word being of `endian` ordering for deserialization purpose.
  result.fromBytesImpl(bytes, offset, endianness)
