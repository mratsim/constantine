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
  ./endians2,
  ../primitives/constant_time,
  ../math/bigints_checked,
  ../config/common

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

# TODO: tag/remove exceptions raised.

func fromRawUintLE(
        dst: var BigInt,
        src: openarray[byte]) =
  ## Parse an unsigned integer from its canonical
  ## little-endian unsigned representation
  ## and store it into a BigInt
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time
  # TODO: error on destination to small

  var
    dst_idx = 0
    acc = Zero
    acc_len = 0

  for src_idx in 0 ..< src.len:
    let src_byte = Word(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= WordBitSize:
      dst.limbs[dst_idx] = acc and MaxWord
      inc dst_idx
      acc_len -= WordBitSize
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.limbs.len:
    dst.limbs[dst_idx] = acc

func fromRawUintBE(
        dst: var BigInt,
        src: openarray[byte]) =
  ## Parse an unsigned integer from its canonical
  ## big-endian unsigned representation (octet string)
  ## and store it into a BigInt.
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time

  var
    dst_idx = 0
    acc = Zero
    acc_len = 0

  for src_idx in countdown(src.len-1, 0):
    let src_byte = Word(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= WordBitSize:
      dst.limbs[dst_idx] = acc and MaxWord
      inc dst_idx
      acc_len -= WordBitSize
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.limbs.len:
    dst.limbs[dst_idx] = acc

func fromRawUint*(
        dst: var BigInt,
        src: openarray[byte],
        srcEndianness: static Endianness) =
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ## And store it into a BigInt of size `bits`
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time to embed curve moduli
  ## from a canonical integer representation

  when srcEndianness == littleEndian:
    dst.fromRawUintLE(src)
  else:
    dst.fromRawUintBE(src)
  dst.setInternalBitLength()

func fromRawUint*(
        T: type BigInt,
        src: openarray[byte],
        srcEndianness: static Endianness): T {.inline.}=
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ## And store it into a BigInt of size `bits`
  ##
  ## Constant-Time:
  ##   - no leaks
  ##
  ## Can work at compile-time to embed curve moduli
  ## from a canonical integer representation
  result.fromRawUint(src, srcEndianness)

func fromUint*(
        T: type BigInt,
        src: SomeUnsignedInt): T {.inline.}=
  ## Parse a regular unsigned integer
  ## and store it into a BigInt of size `bits`
  result.fromRawUint(cast[array[sizeof(src), byte]](src), cpuEndian)

func fromUint*(
        dst: var BigInt,
        src: SomeUnsignedInt) {.inline.}=
  ## Parse a regular unsigned integer
  ## and store it into a BigInt of size `bits`
  dst.fromRawUint(cast[array[sizeof(src), byte]](src), cpuEndian)

# ############################################################
#
# Serialising from internal representation to canonical format
#
# ############################################################

template blobFrom*(dst: var openArray[byte], src: SomeEndianInt, startIdx: int, endian: static Endianness) =
  ## Write an integer into a raw binary blob
  ## Swapping endianness if needed
  let s = when endian == cpuEndian: src
          else: swapBytes(src)

  for i in 0 ..< sizeof(src):
    dst[startIdx+i] = byte((s shr (i * 8)))

func exportRawUintLE(
        dst: var openarray[byte],
        src: BigInt) =
  ## Serialize a bigint into its canonical little-endian representation
  ## I.e least significant bit first

  var
    src_idx, dst_idx = 0
    acc: BaseType = 0
    acc_len = 0

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.limbs.len: BaseType(src.limbs[src_idx])
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
        dst.blobFrom(src = lo, dst_idx, littleEndian)
        dst_idx += sizeof(Word)
        tail -= sizeof(Word)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[dst_idx+i] = byte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[dst_idx+i] = byte(lo shr ((tail-i)*8))
        return

func exportRawUintBE(
        dst: var openarray[byte],
        src: BigInt) =
  ## Serialize a bigint into its canonical big-endian representation
  ## (octet string)
  ## I.e most significant bit first
  ##
  ## In cryptography specifications, this is often called
  ## "Octet string to Integer"

  var
    src_idx = 0
    dst_idx = dst.len - 1
    acc: BaseType = 0
    acc_len = 0

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.limbs.len: BaseType(src.limbs[src_idx])
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
        dst.blobFrom(src = lo, dst_idx, littleEndian)
        dst_idx -= sizeof(Word)
        tail -= sizeof(Word)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[dst_idx-i] = byte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[dst_idx-i] = byte(lo shr ((tail-i)*8))
        return

func exportRawUint*(
        dst: var openarray[byte],
        src: BigInt,
        dstEndianness: static Endianness) =
  ## Serialize a bigint into its canonical big-endian or little endian
  ## representation.
  ## A destination buffer of size "(BigInt.bits + 7) div 8" at minimum is needed,
  ## i.e. bits -> byte conversion rounded up
  ##
  ## If the buffer is bigger, output will be zero-padded left for big-endian
  ## or zero-padded right for little-endian.
  ## I.e least significant bit is aligned to buffer boundary

  assert dst.len >= (BigInt.bits + 7) div 8, "BigInt -> Raw int conversion: destination buffer is too small"

  when BigInt.bits == 0:
    zeroMem(dst, dst.len)

  when dstEndianness == littleEndian:
    exportRawUintLE(dst, src)
  else:
    exportRawUintBE(dst, src)

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

  doAssert size <= maxStrSize, "size: " & $size & " (without blanks or prefix), maxSize: " & $maxStrSize

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

func nativeEndianToHex(bytes: openarray[byte], order: static[Endianness]): string =
  ## Convert a byte-array to its hex representation
  ## Output is in lowercase and not prefixed.
  ## This assumes that input is in platform native endianness
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
  ##
  ## Can work at compile-time to declare curve moduli from their hex strings

  # 1. Convert to canonical uint
  const canonLen = (T.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  hexToPaddedByteArray(s, bytes, bigEndian)

  # 2. Convert canonical uint to Big Int
  result.fromRawUint(bytes, bigEndian)

func toHex*(big: BigInt, order: static Endianness = bigEndian): string =
  ## Stringify an int to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks

  # 1. Convert Big Int to canonical uint
  const canonLen = (big.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  exportRawUint(bytes, big, cpuEndian)

  # 2 Convert canonical uint to hex
  result = bytes.nativeEndianToHex(order)
