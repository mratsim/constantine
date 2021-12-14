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
  ../primitives,
  ../arithmetic/bigints,
  ../config/[common, type_bigint],
  ./endians

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

# No exceptions for the byte API
{.push raises: [].}

# Note: the parsing/serialization routines were initially developed
#       with an internal representation that used 31 bits out of a uint32
#       or 63-bits out of an uint64

# TODO: the in-place API should return a bool
#       to indicate success.
#       the out-of place API are for configuration,
#       prototyping, research and debugging purposes,
#       and can use exceptions.

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
    let src_byte = SecretWord(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= WordBitWidth:
      dst.limbs[dst_idx] = acc
      inc dst_idx
      acc_len -= WordBitWidth
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.limbs.len:
    dst.limbs[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.limbs.len:
    dst.limbs[i] = Zero

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
    let src_byte = SecretWord(src[src_idx])

    # buffer reads
    acc = acc or (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    # if full, dump
    if acc_len >= WordBitWidth:
      dst.limbs[dst_idx] = acc
      inc dst_idx
      acc_len -= WordBitWidth
      acc = src_byte shr (8 - acc_len)

  if dst_idx < dst.limbs.len:
    dst.limbs[dst_idx] = acc

  for i in dst_idx + 1 ..< dst.limbs.len:
    dst.limbs[i] = Zero

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

template blobFrom(dst: var openArray[byte], src: SomeUnsignedInt, startIdx: int, endian: static Endianness) =
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
      # We need to refill the buffer to output 64-bit
      acc = w
      acc_len = WordBitWidth
    else:
      when WordBitWidth == sizeof(SecretWord) * 8:
        let lo = acc
        acc = w
      else: # If using 63-bit (or less) out of uint64
        let lo = (w shl acc_len) or acc
        dec acc_len
        acc = w shr (WordBitWidth - acc_len)

      if tail >= sizeof(SecretWord):
        # Unrolled copy
        dst.blobFrom(src = lo, dst_idx, littleEndian)
        dst_idx += sizeof(SecretWord)
        tail -= sizeof(SecretWord)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[dst_idx+i] = toByte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[dst_idx+i] = toByte(lo shr ((tail-i)*8))
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
    acc: BaseType = 0
    acc_len = 0

  var tail = dst.len
  while tail > 0:
    let w = if src_idx < src.limbs.len: BaseType(src.limbs[src_idx])
            else: 0
    inc src_idx

    if acc_len == 0:
      # We need to refill the buffer to output 64-bit
      acc = w
      acc_len = WordBitWidth
    else:
      when WordBitWidth == sizeof(SecretWord) * 8:
        let lo = acc
        acc = w
      else: # If using 63-bit (or less) out of uint64
        let lo = (w shl acc_len) or acc
        dec acc_len
        acc = w shr (WordBitWidth - acc_len)

      if tail >= sizeof(SecretWord):
        # Unrolled copy
        tail -= sizeof(SecretWord)
        dst.blobFrom(src = lo, tail, bigEndian)
      else:
        # Process the tail and exit
        when cpuEndian == littleEndian:
          # When requesting little-endian on little-endian platform
          # we can just copy each byte
          # tail is inclusive
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr (i*8))
        else: # TODO check this
          # We need to copy from the end
          for i in 0 ..< tail:
            dst[tail-1-i] = toByte(lo shr ((tail-i)*8))
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

{.pop.} # {.push raises: [].}

# ############################################################
#
#         Conversion helpers
#
# ############################################################
# TODO: constant-time

func readHexChar(c: char): uint8 {.inline.}=
  ## Converts an hex char to an int
  ## CT: leaks position of invalid input if any.
  ##     and leaks if 0..9 or a..f or A..F
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

func hexToPaddedByteArray*(hexStr: string, output: var openArray[byte], order: static[Endianness]) =
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

func fromHex*(a: var BigInt, s: string) =
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
  const canonLen = (BigInt.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  hexToPaddedByteArray(s, bytes, bigEndian)

  # 2. Convert canonical uint to Big Int
  a.fromRawUint(bytes, bigEndian)

func fromHex*(T: type BigInt, s: string): T {.noInit.} =
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
  result.fromHex(s)

func appendHex*(dst: var string, big: BigInt, order: static Endianness = bigEndian) =
  ## Append the BigInt hex into an accumulator
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  ##
  ## This is useful to reduce the number of allocations when serializing
  ## Fp towers

  # 1. Convert Big Int to canonical uint
  const canonLen = (big.bits + 8 - 1) div 8
  var bytes: array[canonLen, byte]
  exportRawUint(bytes, big, cpuEndian)

  # 2 Convert canonical uint to hex
  dst.add bytes.nativeEndianToHex(order)

func toHex*(big: BigInt, order: static Endianness = bigEndian): string =
  ## Stringify an int to hex.
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  result.appendHex(big, order)

# ############################################################
#
#                    Decimal conversion
#
# ############################################################
#
# We need to convert between the size in binary
# and the size in decimal. Unlike for the hexadecimal case
# this is not trivial. We find the following relation.
#
# binary_length = log₂(value)
# decimal_length = log₁₀(value)
#
# Hence we have:
# binary_length = (log₂(value) / log₁₀(value)) * decimal_length
#
# the log change of base formula allow us to express
# log₁₀(value) = log₂(value) / log₂(10)
#
# Hence
# binary_length = log₂(10) * decimal_length
#
# Now we need to approximate log₂(10), we can have a best approximation
# using continued factions:
# In Sagemath: "continued_fraction(log(10,2)).convergents()[0:10].list()"
# [3,
#  10/3,
#  93/28,
#  196/59,
#  485/146,
#  2136/643,
#  13301/4004,
#  28738/8651,
#  42039/12655,
#  70777/21306]
#
# According to http://www.maths.surrey.ac.uk/hosted-sites/R.Knott/Fibonacci/cfCALC.html
# we have
# 42039/12655	= [3;3,9,2,2,4,6,2,1]	  = 3.321928091663374	 error -3.223988631617658×10-9 (9.705×10-8%)
# 70777/21306	= [3;3,9,2,2,4,6,2,1,1]	= 3.3219280953721957 error +4.848330625861763×10-10 (1.459×10-8%
# as lower and upper bound.

const log2_10_Num = 42039
const log2_10_Denom = 12655

# No exceptions for the in-place API
{.push raises: [].}

func hasEnoughBitsForDecimal(bits: uint, decimalLength: uint): bool =
  ## Check if the decimalLength would fit in a big int of size bits.
  ## This assumes that bits and decimal length are **public.**
  ##
  ## The check uses continued fraction approximation
  ## In Sagemath: "continued_fraction(log(10,2)).convergents()[0:10].list()"
  ## which gives 70777/21306
  ##
  ## The check might be too lenient by 1 bit.
  if bits >= high(uint) div log2_10_Num:
    # The next multiplication would overflow
    return false
  # Compute the expected length
  let maxExpectedBitlength = ((decimalLength * log2_10_Num) div log2_10_Denom)

  # A big int "400....." might take 381 bits and "500....." might take 382
  let lenientBitlength = maxExpectedBitlength - 1

  result = bits >= lenientBitlength

func fromDecimal*[aBits: static int](a: var BigInt[aBits], s: string): SecretBool =
  ## Convert a decimal string. The input must be packed
  ## with no spaces or underscores.
  ## This assumes that bits and decimal length are **public.**
  ##
  ## This function does approximate validation that the BigInt
  ## can hold the input string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## Return true if conversion is successful
  ##
  ## Return false if an error occured:
  ## - There is not enough space in the BigInt
  ## - An invalid character was found

  if not aBits.hasEnoughBitsForDecimal(s.len.uint):
    return CtFalse

  a.setZero()
  result = CtTrue

  for i in 0 ..< s.len:
    let c = SecretWord(ord(s[i]))
    result = result and (SecretWord(ord('0')) <= c and c <= SecretWord(ord('9')))

    a += c - SecretWord(ord('0'))
    if i != s.len - 1:
      a *= 10

func fromDecimal*(T: type BigInt, s: string): T {.raises: [ValueError].}=
  ## Convert a decimal string. The input must be packed
  ## with no spaces or underscores.
  ## This assumes that bits and decimal length are **public.**
  ##
  ## This function does approximate validation that the BigInt
  ## can hold the input string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## This function may raise an exception if input is incorrect
  ## - There is not enough space in the BigInt
  ## - An invalid character was found
  let status = result.fromDecimal(s)
  if not status.bool:
    raise newException(ValueError,
      "BigInt could not be parsed from decimal string." &
      " <Potentially secret input withheld>")

# Conversion to decimal
# ----------------------------------------------------------------
#
# The first problem to solve is precomputing the final size
# We also use continued fractions to approximate log₁₀(2)
#
# decimal_length = log₁₀(2) * binary_length
#
# sage: [(frac, numerical_approx(frac - log(2,10))) for frac in continued_fraction(log(2,10)).convergents()[0:10]]
# [(0, -0.301029995663981),
#  (1/3, 0.0323033376693522),
#  (3/10, -0.00102999566398115),
#  (28/93, 0.0000452731532231687),
#  (59/196, -9.58750071583525e-6),
#  (146/485, 9.32171070389121e-7),
#  (643/2136, -3.31171646772432e-8),
#  (4004/13301, 2.08054934391910e-9),
#  (8651/28738, -5.35579747218407e-10),
#  (12655/42039, 2.92154800352051e-10)]

const log10_2_Num = 12655
const log10_2_Denom = 42039

# Then the naive way to serialize is to repeatedly do
# const intToCharMap = "0123456789"
# rest = number
# while rest != 0:
#   digitToPrint = rest mod 10
#   result.add intToCharMap[digitToPrint]
#   rest /= 10
#
# For constant-time we:
# 1. can't compare with 0 as a stopping condition
# 2. repeatedly add to a buffer
# 3. can't use naive indexing (cache timing attacks though very unlikely given the small size)
# 4. need (fast) constant-time division
#
# 1 and 2 is solved by precomputing the length and make the number of add be fixed.
# 3 is easily solved by doing "digitToPrint + ord('0')" instead
#
# For 4 for now we use non-constant-time division (TODO)

func decimalLength(bits: static int): int =
  doAssert bits < (high(uint) div log10_2_Num),
    "Constantine does not support that many bits to convert to a decimal string: " & $bits
    # The next multiplication would overflow

  result = 1 + ((bits * log10_2_Num) div log10_2_Denom)

func toDecimal*(a: BigInt): string =
  ## Convert to a decimal string.
  ##
  ## It is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.
  ##
  ## This function is NOT constant-time at the moment.
  const len = decimalLength(BigInt.bits)
  result = newString(len)

  var a = a
  for i in countdown(len-1, 0):
    let c = ord('0') + a.div10().int
    result[i] = char(c)
