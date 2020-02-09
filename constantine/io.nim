# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO ⚠️:
#   - Constant-time validation for parsing secret keys
#   - Burning memory to ensure secrets are not left after dealloc.

import
  endians,
  ./word_types, ./bigints

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func fromRawUintLE(
        T: type BigInt,
        src: openarray[byte]): T =
  ## Parse an unsigned integer from its canonical
  ## little-endian unsigned representation
  ## And store it into a BigInt of size bits
  ##
  ## CT:
  ##   - no leaks

  var
    dst_idx = 0
    acc = Word(0)
    acc_len = 0

  for src_idx in 0 ..< src.len:
    let src_byte = Word(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= WordBitSize:
      result.limbs[dst_idx] = acc and MaxWord
      inc dst_idx
      acc_len -= WordBitSize
      acc = src_byte shr (8 - acc_len)

  if acc_len != 0:
    result.limbs[dst_idx] = acc

func fromRawUint*(
        T: type BigInt,
        src: openarray[byte],
        srcEndianness: static Endianness): T {.inline.}=
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ## And store it into a BigInt of size `bits`
  ##
  ## CT:
  ##   - no leaks

  when srcEndianness == littleEndian:
    fromRawUintLE(T, src)
  else:
    {.error: "Not implemented at the moment".}

func fromUint*(
        T: type BigInt,
        src: SomeUnsignedInt): T =
  ## Parse a regular unsigned integer
  ## and store it into a BigInt of size `bits`
  fromRawUint(T, cast[array[sizeof(src), byte]](src), cpuEndian)

# ############################################################
#
# Serialising from internal representation to canonical format
#
# ############################################################

template bigEndianXX[T: uint16 or uint32 or uint64](outp: pointer, inp: ptr T) =
  when T is uint64:
    bigEndian64(outp, inp)
  elif T is uint32:
    bigEndian32(outp, inp)
  elif T is uint16:
    bigEndian16(outp, inp)

template littleEndianXX[T: uint16 or uint32 or uint64](outp: pointer, inp: ptr T) =
  when T is uint64:
    littleEndian64(outp, inp)
  elif T is uint32:
    littleEndian32(outp, inp)
  elif T is uint16:
    littleEndian16(outp, inp)

func dumpRawUintLE(
        dst: var openarray[byte],
        src: BigInt) {.inline.}=
  ## Serialize a bigint into its canonical little-endian representation
  ## I.e least significant bit is aligned to buffer boundary

  var
    src_idx, dst_idx = 0
    acc: BaseType = 0
    acc_len = 0

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.limbs.len: src.limbs[src_idx].BaseType
            else: 0
    inc src_idx

    if acc_len == 0:
      # Edge case, we need to refill the buffer to output 64-bit
      # as we can only read 63-bit per word
      acc = w
      acc_len = WordBitSize
    else:
      let lo = (w shl acc_len) or acc
      dec acc_len
      acc = w shr (WordBitSize - acc_len)

      if tail >= sizeof(Word):
        # Unrolled copy
        # debugecho src.repr
        littleEndianXX(dst[dst_idx].addr, lo.unsafeAddr)
        dst_idx += sizeof(Word)
        tail -= sizeof(Word)
      else:
        # Process the tail
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          for i in dst_idx ..< tail:
            dst[dst_idx] = byte(lo shr (i-dst_idx))
        else:
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[dst_idx] = byte(lo shr (tail-i))

func dumpRawUint*(
        dst: var openarray[byte],
        src: BigInt,
        dstEndianness: static Endianness) =
  ## Serialize a bigint into its canonical big-endian or little endian
  ## representation.
  ## A destination buffer of size "BigInt.bits div 8" at minimum is needed.
  ##
  ## If the buffer is bigger, output will be zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## I.e least significant bit is aligned to buffer boundary

  if dst.len < static(BigInt.bits div 8):
    raise newException(ValueError, "BigInt -> Raw int conversion: destination buffer is too small")

  when BigInt.bits == 0:
    zeroMem(dst, dst.len)

  when dstEndianness == littleEndian:
    dumpRawUintLE(dst, src)
  else:
    {.error: "Not implemented at the moment".}

# ############################################################
#
#         Conversion helpers
#
# ############################################################

func readHexChar(c: char): uint8 {.inline.}=
  ## Converts an hex char to an int
  ## CT: leaks position of invalid input if any.
  case c
  of '0'..'9': result = uint8 ord(c) - ord('0')
  of 'a'..'f': result = uint8 ord(c) - ord('a') + 10
  of 'A'..'F': result = uint8 ord(c) - ord('A') + 10
  else:
    raise newException(ValueError, $c & "is not a hexadecimal character")

func skipPrefixes(current_idx: var int, str: string, radix: static range[2..16]) {.inline.} =
  ## Returns the index of the first meaningful char in `hexStr` by skipping
  ## "0x" prefix
  ## CT:
  ##   - leaks if input length < 2
  ##   - leaks if input start with 0x, 0o or 0b prefix

  if str.len < 2:
    return

  assert current_idx == 0, "skipPrefixes only works for prefixes (position 0 and 1 of the string)"
  if str[0] == '0':
    case str[1]
    of {'x', 'X'}:
      assert radix == 16, "Parsing mismatch, 0x prefix is only valid for a hexadecimal number (base 16)"
      current_idx = 2
    of {'o', 'O'}:
      assert radix == 8, "Parsing mismatch, 0o prefix is only valid for an octal number (base 8)"
      current_idx = 2
    of {'b', 'B'}:
      assert radix == 2, "Parsing mismatch, 0b prefix is only valid for a binary number (base 2)"
      current_idx = 2
    else: discard

func readDecChar(c: range['0'..'9']): int {.inline.}=
  ## Converts a decimal char to an int
  # specialization without branching for base <= 10.
  ord(c) - ord('0')

func countNonBlanks(hexStr: string, startPos: int): int =
  ## Count the number of non-blank characters
  ## ' ' (space) and '_' (underscore) are considered blank
  ##
  ## CT:
  ##   - Leaks white-spaces and non-white spaces position
  const blanks = {' ', '_'}

  for c in hexStr:
    if c in blanks:
      result += 1

func hexToPaddedByteArray(hexStr: string, output: var openArray[byte], order: static[Endianness]) =
  ## Read a hex string and store it in a byte array `output`.
  ## The string may be shorter than the byte array.
  ##
  ## The source string must be hex big-endian.
  ## The destination array can be big or little endian
  var
    skip = 0
    dstIdx: int
    shift = 4
  skipPrefixes(skip, hexStr, 16)

  const blanks = {' ', '_'}
  let nonBlanksCount = countNonBlanks(hexStr, skip)

  let maxStrSize = output.len * 2
  let size = hexStr.len - skip - nonBlanksCount

  doAssert size <= maxStrSize

  if size < maxStrSize:
    # include extra byte if odd length
    dstIdx = output.len - (size + 1) div 2
    # start with shl of 4 if length is even
    shift = 4 - size mod 2 * 4

  for srcIdx in skip ..< hexStr.len:
    if hexStr[srcIdx] in blanks:
      continue

    let nibble = hexStr[srcIdx].readHexChar shl shift
    when order == bigEndian:
      output[dstIdx] = output[dstIdx] or nibble
    else:
      output[output.high - dstIdx] = output[output.high - dstIdx] or nibble
    shift = (shift + 4) and 4
    dstIdx += shift shr 2

func toHex(bytes: openarray[byte], order: static[Endianness]): string =
  ## Convert a byte-array to its hex representation
  ## Output is in lowercase and not prefixed.
  const hexChars = "0123456789abcdef"
  result = newString(2 + 2 * bytes.len)
  result[0] = '0'
  result[1] = 'x'
  for i in 0 ..< bytes.len:
    when order == system.cpuEndian:
      result[2 + 2*i] = hexChars[int bytes[i] shr 4 and 0xF]
      result[2 + 2*i+1] = hexChars[int bytes[i] and 0xF]
    else:
      result[2 + 2*i] = hexChars[int bytes[bytes.high - i] shr 4 and 0xF]
      result[2 + 2*i+1] = hexChars[int bytes[bytes.high - i] and 0xF]

# ############################################################
#
#                      Hex conversion
#
# ############################################################

func fromHex*(T: type BigInt, s: string): T =
  ## Convert a hex string to BigInt that can hold
  ## the specified number of bits
  ##
  ## For example `fromHex(BigInt[256], "0x123456")`
  ##
  ## Hex string is assumed big-endian
  ##
  ## This API is intended for configuration and debugging purposes
  ## Do not pass secret or private data to it.

  # 1. Convert to canonical uint
  const canonLen = (T.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  hexToPaddedByteArray(s, bytes, littleEndian)

  # 2. Convert canonical uint to Big Int
  result = T.fromRawUint(bytes, littleEndian)

func dumpHex*(big: BigInt, order: static Endianness = bigEndian): string =
  ## Stringify an int to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## This is a raw memory dump. Output will be padded with 0
  ## if the big int does not use the full memory allocated for it.
  ##
  ## Regardless of the machine endianness the output will be big-endian hex.
  ##
  ## For example a BigInt representing 10 will be
  ##   - 0x0A                for BigInt[8]
  ##   - 0x000A              for BigInt[16]
  ##   - 0x00000000_0000000A for BigInt[64]
  ##
  ## CT:
  ##   - no leaks

  # 1. Convert Big Int to canonical uint
  const canonLen = (big.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  dumpRawUint(bytes, big, cpuEndian)

  # 2 Convert canonical uint to hex
  result = bytes.toHex(order)
