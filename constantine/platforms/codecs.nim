# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./abstractions, ./signed_secret_words

# ############################################################
#
#                         Codecs
#
# ############################################################

template sw(a: auto): SecretWord = SecretWord(a)
template ssw(a: auto): SignedSecretWord = SignedSecretWord(a)

# ############################################################
#
#                      Hexadecimal
#
# ############################################################

func readHexChar(c: char): SecretWord {.inline.} =
  ## Converts an hex char to an int
  const OOR = ssw 256        # Push chars out-of-range
  var c = ssw(c) + OOR

  # '0' -> '9' maps to [0, 9]
  c.csub(OOR + ssw('0') - ssw  0, c.isInRangeMask(ssw('0') + OOR, ssw('9') + OOR))
  # 'A' -> 'Z' maps to [10, 16)
  c.csub(OOR + ssw('A') - ssw 10, c.isInRangeMask(ssw('A') + OOR, ssw('Z') + OOR))
  # 'a' -> 'z' maps to [10, 16)
  c.csub(OOR + ssw('a') - ssw 10, c.isInRangeMask(ssw('a') + OOR, ssw('z') + OOR))

  c = c and ssw(0xF) # Prevent overflow of invalid inputs
  return sw(c)

func paddedFromHex*(output: var openArray[byte], hexStr: string, order: static[Endianness]) =
  ## Read a hex string and store it in a byte array `output`.
  ## The string may be shorter than the byte array.
  ##
  ## The source string must be hex big-endian.
  ## The destination array can be big or little endian
  ##
  ## Only characters accepted are 0x or 0X prefix
  ## and 0-9,a-f,A-F in particular spaces and _ are not valid.
  ##
  ## Procedure is constant-time except for the presence (or absence) of the 0x prefix.
  ##
  ## This procedure is intended for configuration, prototyping, research and debugging purposes.
  ## You MUST NOT use it for production.

  var
    skip = Zero
    dstIdx: int
    shift = 4

  if hexStr.len >= 2:
    skip = sw(2)*(
      sw(hexStr[0] == '0') and
      (sw(hexStr[1] == 'x') or sw(hexStr[1] == 'X'))
    )

  let maxStrSize = output.len * 2
  let size = hexStr.len - skip.int

  doAssert size <= maxStrSize, "size: " & $size & ", maxSize: " & $maxStrSize

  if size < maxStrSize:
    # include extra byte if odd length
    dstIdx = output.len - (size + 1) shr 1
    # start with shl of 4 if length is even
    shift = 4 - (size and 1) * 4

  for srcIdx in skip.int ..< hexStr.len:
    let c = hexStr[srcIdx]
    let nibble = byte(c.readHexChar() shl shift)
    when order == bigEndian:
      output[dstIdx] = output[dstIdx] or nibble
    else:
      output[output.high - dstIdx] = output[output.high - dstIdx] or nibble
    shift = (shift + 4) and 4
    dstIdx += shift shr 2

func toHex*(bytes: openarray[byte]): string =
  ## Convert a byte-array to its hex representation
  ## Output is in lowercase and prefixed with 0x
  const hexChars = "0123456789abcdef"
  result = newString(2 + 2 * bytes.len)
  result[0] = '0'
  result[1] = 'x'
  for i in 0 ..< bytes.len:
    let bi = bytes[i]
    result[2 + 2*i] = hexChars.secretLookup(SecretWord bi shr 4 and 0xF)
    result[2 + 2*i+1] = hexChars.secretLookup(SecretWord bi and 0xF)

func fromHex*[N: static int](T: type array[N, byte], hex: string): T =
  result.paddedFromHex(hex, bigEndian)