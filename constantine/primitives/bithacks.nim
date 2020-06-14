# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                           Bit hacks
#
# ############################################################

# Bithacks
# ------------------------------------------------------------
# TODO: Nim std/bitops is unsatisfactory
#       in particular the "noUndefined" flag
#       for countLeadingZeroBits/countTrailingZeroBits
#       is returning zero instead of the integer bitwidth
#
#       Furthermore it is not guaranteed constant-time
#       And lastly, even compiler builtin may be slightly inefficient
#       for example when doing fastLog2
#       which is "31 - builtin_clz" we get
#       `bsr + xor (from clz) + sub`
#       instead of plain `bsr`
#
#       At the moment we don't need them to operate on secret data
#
# See: https://www.chessprogramming.org/BitScan
#      https://www.chessprogramming.org/General_Setwise_Operations
# and https://graphics.stanford.edu/%7Eseander/bithacks.html
# for compendiums of bit manipulation

proc clearMask[T: SomeInteger](v: T, mask: T): T {.inline.} =
  ## Returns ``v``, with all the ``1`` bits from ``mask`` set to 0
  v and not mask

proc clearBit*[T: SomeInteger](v: T, bit: T): T {.inline.} =
  ## Returns ``v``, with the bit at position ``bit`` set to 0
  v.clearMask(1.T shl bit)

func log2*(x: uint32): uint32 =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time, guaranteed constant-time.
  ## TODO: at runtime BitScanReverse or CountLeadingZero are more efficient
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  const lookup: array[32, uint8] = [0'u8, 9, 1, 10, 13, 21, 2, 29, 11, 14, 16, 18,
    22, 25, 3, 30, 8, 12, 20, 28, 15, 17, 24, 7, 19, 27, 23, 6, 26, 5, 4, 31]
  var v = x
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  lookup[(v * 0x07C4ACDD'u32) shr 27]

func log2*(x: uint64): uint64 {.inline, noSideEffect.} =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time, guaranteed constant-time.
  ## TODO: at runtime BitScanReverse or CountLeadingZero are more efficient
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  const lookup: array[64, uint8] = [0'u8, 58, 1, 59, 47, 53, 2, 60, 39, 48, 27, 54,
    33, 42, 3, 61, 51, 37, 40, 49, 18, 28, 20, 55, 30, 34, 11, 43, 14, 22, 4, 62,
    57, 46, 52, 38, 26, 32, 41, 50, 36, 17, 19, 29, 10, 13, 21, 56, 45, 25, 31,
    35, 16, 9, 12, 44, 24, 15, 8, 23, 7, 6, 5, 63]
  var v = x
  v = v or v shr 1 # first round down to one less than a power of 2
  v = v or v shr 2
  v = v or v shr 4
  v = v or v shr 8
  v = v or v shr 16
  v = v or v shr 32
  lookup[(v * 0x03F6EAF2CD271461'u64) shr 58]
