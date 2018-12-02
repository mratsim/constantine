# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO ⚠️:
#   - Constant-time validation for parsing secret keys
#   - Burning memory to ensure secrets are not left after dealloc.

import ./word_types, ./bigints

# ############################################################
#
#         Constant-time hex to byte conversion
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

func nextNonBlank(current_idx: var int, s: string) {.inline.} =
  ## Move the current index, skipping white spaces and "_" characters.
  ## CT:
  ##   - Leaks white-spaces and non-white spaces position

  const blanks = {' ', '_'}

  inc current_idx
  while current_idx < s.len and s[current_idx] in blanks:
    inc current_idx

func readDecChar(c: range['0'..'9']): int {.inline.}=
  ## Converts a decimal char to an int
  # specialization without branching for base <= 10.
  ord(c) - ord('0')

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func parseRawUint*(
        input: openarray[byte],
        bits: static int,
        endian: static Endianness): BigInt[bits] =
  ## Parse an unsigned integer from its canonical
  ## big-endian or little-endian unsigned representation
  ## And store it into a BigInt of size bits
  ##
  ## CT:
  ##   - no leaks

  var
    dst_idx = 0
    acc = Word(0)
    acc_len = 0

  template body(){.dirty.} =
    let src_byte = Word(input[src_idx])

    acc = acc and (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    if acc_len >= WordBitSize:
      result[dst_idx] = acc and MaxWord
      inc dst_idx
      acc_len -= WordBitSize
      acc = src_byte shr (8 - acc_len)

  when endian == bigEndian:
    for src_idx in countdown(input.high, 0):
      body()
  else:
    for src_idx in 0 ..< input.len:
      body()

  if acc_len != 0:
    result[dst_idx] = acc

# ############################################################
#
# Serialising from internal representation to canonical format
#
# ############################################################
