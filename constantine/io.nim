# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
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
        src: openarray[byte],
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
    let src_byte = Word(src[src_idx])

    acc = acc and (src_byte shl acc_len)
    acc_len += 8 # We count bit by bit

    if acc_len >= WordBitSize:
      result[dst_idx] = acc and MaxWord
      inc dst_idx
      acc_len -= WordBitSize
      acc = src_byte shr (8 - acc_len)

  when endian == bigEndian:
    for src_idx in countdown(src.high, 0):
      body()
  else:
    for src_idx in 0 ..< src.len:
      body()

  if acc_len != 0:
    result[dst_idx] = acc

# ############################################################
#
# Serialising from internal representation to canonical format
#
# ############################################################

template bigEndian[T: uint16 or uint32 or uint64](outp: pointer, inp: ptr T) =
  when T is uint64:
    bigEndian64(outp, inp)
  elif T is uint32:
    bigEndian32(outp, inp)
  elif T is uint16:
    bigEndian16(outp, inp)

template littleEndian[T: uint16 or uint32 or uint64](outp: pointer, inp: ptr T) =
  when T is uint64:
    littleEndian64(outp, inp)
  elif T is uint32:
    littleEndian32(outp, inp)
  elif T is uint16:
    littleEndian16(outp, inp)

func round_step_up(x: Natural, step: static Natural): int {.inline.} =
  ## Round the input to the next multiple of "step"
  assert (step and (step - 1)) == 0, "Step must be a power of 2"
  result = (x + step - 1) and not(step - 1)

func dumpRawUint*(
        dst: var openarray[byte],
        src: BigInt,
        endian: static Endianness) =
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
  else:
    var
      src_idx = 0
      acc = Word(0)
      acc_len = 0

    template body(){.dirty.} =
      let w = if src_idx < src.limbs.len: src[src_idx]
              else: Word(0)
      inc src_idx

      if acc_len == 0:
        # Edge case to avoid shifting by 0
        acc = w
        acc_len = WordBitSize
      else:
        let lo = (w shr acc_len) or acc
        dec acc_len
        acc = w shr (WordBitSize - acc_len)
        when endian == bigEndian:
          # We're counting down
          bigEndian(dst[dst_idx - Word.sizeof], w.unsafeAddr)
        else:
          littleEndian(dst[dst_idx], w.unsafeAddr)

    when endian == bigEndian:
      discard # TODO
    else:
      let unroll_stop = round_step_up(dst.len, Word.sizeof)
      for dst_idx in countup(0, unroll_stop - 1, Word.sizeof):
        body()

      # Process the tail - TODO
