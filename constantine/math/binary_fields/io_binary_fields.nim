# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/serialization/[endians, codecs],
  constantine/math/io/io_extfields,
  ./gf2_64, ./gf2_64x2

export io_extfields

# ############################################################
#
#             Serialization of binary fields
#
# ############################################################
#
# Every bit pattern is a valid element, there is no range check.
#
# An 𝔽₂⁶⁴ element is serialized as its 64 raw bits.
# An 𝔽₂¹²⁸ element c0 + c1·y as the 128-bit integer c0 + c1·2⁶⁴:
# in little-endian, c0 then c1, each little-endian, which is leanVM's wire format.

{.push raises: [].}

# Bytes
# ------------------------------------------------------------

func marshal*(dst: var openArray[byte], src: GF2_64, dstEndianness: static Endianness): bool {.discardable.} =
  ## Serialize to 8 bytes.
  ## If the buffer is bigger, output is zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## Returns false if the buffer is smaller than 8 bytes.
  if dst.len < 8:
    return false
  when dstEndianness == littleEndian:
    dst.dumpRawInt(src.raw, 0, littleEndian)
    for i in 8 ..< dst.len:
      dst[i] = 0
  else:
    let pad = dst.len - 8
    for i in 0 ..< pad:
      dst[i] = 0
    dst.dumpRawInt(src.raw, pad, bigEndian)
  return true

func unmarshal*(dst: var GF2_64, src: openArray[byte], srcEndianness: static Endianness): bool {.discardable.} =
  ## Deserialize from exactly 8 bytes.
  ## Returns false if the buffer is not 8 bytes long.
  if src.len != 8:
    return false
  var bytes {.noInit.}: array[8, byte]
  for i in 0 ..< 8:
    bytes[i] = src[i]
  dst.raw = uint64.fromBytes(bytes, srcEndianness)
  return true

func marshal*(dst: var openArray[byte], src: GF2_64x2, dstEndianness: static Endianness): bool {.discardable.} =
  ## Serialize to 16 bytes, as the 128-bit integer c0 + c1·2⁶⁴.
  ## If the buffer is bigger, output is zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## Returns false if the buffer is smaller than 16 bytes.
  if dst.len < 16:
    return false
  when dstEndianness == littleEndian:
    dst.dumpRawInt(src.c0.raw, 0, littleEndian)
    dst.dumpRawInt(src.c1.raw, 8, littleEndian)
    for i in 16 ..< dst.len:
      dst[i] = 0
  else:
    let pad = dst.len - 16
    for i in 0 ..< pad:
      dst[i] = 0
    dst.dumpRawInt(src.c1.raw, pad, bigEndian)
    dst.dumpRawInt(src.c0.raw, pad+8, bigEndian)
  return true

func unmarshal*(dst: var GF2_64x2, src: openArray[byte], srcEndianness: static Endianness): bool {.discardable.} =
  ## Deserialize from exactly 16 bytes, the 128-bit integer c0 + c1·2⁶⁴.
  ## Returns false if the buffer is not 16 bytes long.
  if src.len != 16:
    return false
  when srcEndianness == littleEndian:
    discard dst.coords[0].unmarshal(src.toOpenArray(0, 7), littleEndian)
    discard dst.coords[1].unmarshal(src.toOpenArray(8, 15), littleEndian)
  else:
    discard dst.coords[1].unmarshal(src.toOpenArray(0, 7), bigEndian)
    discard dst.coords[0].unmarshal(src.toOpenArray(8, 15), bigEndian)
  return true

# Hex, for testing and debugging
# ------------------------------------------------------------

func appendHex*(dst: var string, a: GF2_64, indent = 0, order: static Endianness = bigEndian) =
  ## Append the 64 raw bits as 0x-prefixed hex, coefficient of x⁶³ first for big-endian.
  ## Leading zeros are kept. `indent` is unused, for the generic extension field printer.
  dst.add toHex(a.raw.toBytes(order))

func toHex*(a: GF2_64, order: static Endianness = bigEndian): string =
  ## The 64 raw bits as 0x-prefixed hex, coefficient of x⁶³ first for big-endian.
  ## Leading zeros are kept.
  result.appendHex(a, 0, order)

func fromHex*(dst: var GF2_64, hexString: string) =
  ## Read raw bits from big-endian hex, with or without 0x prefix,
  ## up to 16 hex digits.
  var bytes {.noInit.}: array[8, byte]
  bytes.paddedFromHex(hexString, bigEndian)
  dst.raw = uint64.fromBytes(bytes, bigEndian)

func fromHex*(T: type GF2_64, hexString: string): T {.noInit.} =
  result.fromHex(hexString)

func fromHex*(dst: var GF2_64x2, c0, c1: string) =
  ## Read c0 + c1·y from the big-endian hex of each coefficient
  dst.coords[0].fromHex(c0)
  dst.coords[1].fromHex(c1)

func fromHex*(T: type GF2_64x2, c0, c1: string): T {.noInit.} =
  result.fromHex(c0, c1)

{.pop.} # raises
