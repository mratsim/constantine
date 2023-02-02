# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./abstractions

# ############################################################
#
#                         Codecs
#
# ############################################################

# ############################################################
#
#                      Hexadecimal
#
# ############################################################

func readHexChar(c: char): SecretWord {.inline.}=
  ## Converts an hex char to an int
  template sw(a: char or int): SecretWord = SecretWord(a)
  const k = WordBitWidth - 1

  let c = sw(c)

  let lowercaseMask = not -(((c - sw'a') or (sw('f') - c)) shr k)
  let uppercaseMask = not -(((c - sw'A') or (sw('F') - c)) shr k)

  var val = c - sw'0'
  val = val xor ((val xor (c - sw('a') + sw(10))) and lowercaseMask)
  val = val xor ((val xor (c - sw('A') + sw(10))) and uppercaseMask)
  val = val and sw(0xF) # Prevent overflow of invalid inputs

  return val

func hexToPaddedByteArray*(hexStr: string, output: var openArray[byte], order: static[Endianness]) =
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

  template sw(a: bool or int): SecretWord = SecretWord(a)

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
  hexToPaddedByteArray(hex, result, bigEndian)