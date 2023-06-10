# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./intrinsics/bitops

# ############################################################
#
#                           Bit hacks
#
# ############################################################

# Bithacks
# ------------------------------------------------------------
# Nim std/bitops is unsatisfactory
# in particular the "noUndefined" flag
# for countLeadingZeroBits/countTrailingZeroBits
# is returning zero instead of the integer bitwidth
#
# Furthermore it is not guaranteed constant-time
# And lastly, even compiler builtin may be slightly inefficient
# for example when doing fastLog2
# which is "31 - builtin_clz" we get
# `bsr + xor (from clz) + sub`
# instead of plain `bsr`
#
# At the moment we don't need them to operate on secret data
#
# See: https://www.chessprogramming.org/BitScan
#      https://www.chessprogramming.org/General_Setwise_Operations
#      https://www.chessprogramming.org/De_Bruijn_Sequence_Generator
# and https://graphics.stanford.edu/%7Eseander/bithacks.html
# and Hacker's Delight 2nd Edition, Henry S Warren, Jr.
# and https://sites.google.com/site/sydfhd/articles-tutorials/de-bruijn-sequence-generator
# for compendiums of bit manipulation

func clearMask[T: SomeInteger](v: T, mask: T): T {.inline.} =
  ## Returns ``v``, with all the ``1`` bits from ``mask`` set to 0
  v and not mask

func clearBit*[T: SomeInteger](v: T, bit: T): T {.inline.} =
  ## Returns ``v``, with the bit at position ``bit`` set to 0
  v.clearMask(1.T shl bit)

func log2_impl_vartime(n: uint32): uint32 =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time.
  ## ⚠️ not constant-time, table accesses are not uniform.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  const lookup: array[32, uint8] = [
    uint8  0,  9,  1, 10, 13, 21,  2, 29,
          11, 14, 16, 18, 22, 25,  3, 30,
           8, 12, 20, 28, 15, 17, 24,  7,
          19, 27, 23,  6, 26,  5,  4, 31]

  # Isolate MSB
  var n = n
  n = n or n shr 1 # first round down to one less than a power of 2
  n = n or n shr 2
  n = n or n shr 4
  n = n or n shr 8
  n = n or n shr 16
  uint32 lookup[(n * 0x07C4ACDD'u32) shr 27]

func log2_impl_vartime(n: uint64): uint64 {.inline.} =
  ## Find the log base 2 of a 32-bit or less integer.
  ## using De Bruijn multiplication
  ## Works at compile-time.
  ## ⚠️ not constant-time, table accesses are not uniform.
  # https://graphics.stanford.edu/%7Eseander/bithacks.html#IntegerLogDeBruijn
  # https://stackoverflow.com/questions/11376288/fast-computing-of-log2-for-64-bit-integers
  const lookup: array[64, uint8] = [
    uint8  0, 58,  1, 59, 47, 53,  2, 60,
          39, 48, 27, 54, 33, 42,  3, 61,
          51, 37, 40, 49, 18, 28, 20, 55,
          30, 34, 11, 43, 14, 22,  4, 62,
          57, 46, 52, 38, 26, 32, 41, 50,
          36, 17, 19, 29, 10, 13, 21, 56,
          45, 25, 31, 35, 16,  9, 12, 44,
          24, 15,  8, 23,  7,  6,  5, 63]

  # Isolate MSB
  var n = n
  n = n or n shr 1 # first round down to one less than a power of 2
  n = n or n shr 2
  n = n or n shr 4
  n = n or n shr 8
  n = n or n shr 16
  n = n or n shr 32
  uint64 lookup[(n * 0x03F6EAF2CD271461'u64) shr 58]

func log2_vartime*[T: SomeUnsignedInt](n: T): T {.inline.} =
  ## Find the log base 2 of an integer
  when nimvm:
    when sizeof(T) == 8:
      T(log2_impl_vartime(uint64(n)))
    else:
      T(log2_impl_vartime(uint32(n)))
  else:
    log2_c_compiler_vartime(n)

func ctz_impl_vartime(n: uint32): uint32 =
  ## Find the number of trailing zero bits
  ## Requires n != 0
  # https://sites.google.com/site/sydfhd/articles-tutorials/de-bruijn-sequence-generator
  const lookup: array[32, uint8] = [
    uint8  0,  1, 16,  2, 29, 17,  3, 22,
          30, 20, 18, 11, 13,  4,  7, 23,
          31, 15, 28, 21, 19, 10, 12,  6,
          14, 27,  9,  5, 26,  8, 25, 24]

  let isolateLSB = n xor (n-1)
  uint32 lookup[(isolateLSB * 0x6EB14F9'u32) shr 27]

func ctz_impl_vartime(n: uint64): uint64 =
  ## Find the number of trailing zero bits
  ## Requires n != 0
  # https://www.chessprogramming.org/BitScan#Bitscan_forward
  const lookup: array[64, uint8] = [
    uint8  0, 47,  1, 56, 48, 27,  2, 60,
          57, 49, 41, 37, 28, 16,  3, 61,
          54, 58, 35, 52, 50, 42, 21, 44,
          38, 32, 29, 23, 17, 11,  4, 62,
          46, 55, 26, 59, 40, 36, 15, 53,
          34, 51, 20, 43, 31, 22, 10, 45,
          25, 39, 14, 33, 19, 30,  9, 24,
          13, 18,  8, 12,  7,  6,  5, 63]

  let isolateLSB = n xor (n-1)
  uint64 lookup[(isolateLSB * 0x03f79d71b4cb0a89'u64) shr 58]

func countTrailingZeroBits_vartime*[T: SomeUnsignedInt](n: T): T {.inline.} =
  ## Count the number of trailing zero bits of an integer
  when nimvm:
    if n == 0:
      T(sizeof(n) * 8)
    else:
      when sizeof(T) == 8:
        T(ctz_impl_vartime(uint64(n)))
      else:
        T(ctz_impl_vartime(uint32(n)))
  else:
    ctz_c_compiler_vartime(n)

func isPowerOf2_vartime*(n: SomeUnsignedInt): bool {.inline.} =
  ## Returns true if n is a power of 2
  ## ⚠️ Result is bool instead of Secretbool,
  ## for compile-time or explicit vartime proc only.
  (n and (n - 1)) == 0 and n > 0

func nextPowerOfTwo_vartime*(n: SomeUnsignedInt): SomeUnsignedInt {.inline.} =
  ## Returns x if x is a power of 2
  ## or the next biggest power of 2
  1.SomeUnsignedInt shl (log2_vartime(n-1) + 1)

func swapBytes_impl(n: uint32): uint32 {.inline.} =
  result = n
  result = ((result shl 8) and 0xff00ff00'u32) or ((result shr 8) and 0x00ff00ff'u32)
  result = (result shl 16) or (result shr 16)

func swapBytes_impl(n: uint64): uint64 {.inline.} =
  result = n
  result = ((result shl 8) and 0xff00ff00ff00ff00'u64) or ((result shr 8) and 0x00ff00ff00ff00ff'u64)
  result = ((result shl 16) and 0xffff0000ffff0000'u64) or ((result shr 16) and 0x0000ffff0000ffff'u64)
  result = (result shl 32) or (result shr 32)

func swapBytes*(n: SomeUnsignedInt): SomeUnsignedInt {.inline.} =
  # Note:
  #   using the raw Nim implementation:
  #     - leads to vectorized code if swapping an array
  #     - leads to builtin swap on modern compilers
  when nimvm:
    swapBytes_impl(n)
  else:
    swapBytes_c_compiler(n)

func reverseBits*(n, k : uint32): uint32 {.inline.} =
  ## Bit reversal permutation with n ∈ [0, 2ᵏ)
  # Swap bytes - allow vectorization by using raw Nim impl instead of compiler builtin
  var n = swapBytes_impl(n)
  n = ((n and 0x55555555'u32) shl 1) or ((n and 0xaaaaaaaa'u32) shr 1)
  n = ((n and 0x33333333'u32) shl 2) or ((n and 0xcccccccc'u32) shr 2)
  n = ((n and 0x0f0f0f0f'u32) shl 4) or ((n and 0xf0f0f0f0'u32) shr 4)
  return n shr (32 - k)

func reverseBits*(n, k: uint64): uint64 {.inline.} =
  ## Bit reversal permutation with n ∈ [0, 2ᵏ)
  # Swap bytes - allow vectorization by using raw Nim impl instead of compiler builtin
  var n = swapBytes_impl(n)
  n = ((n and 0x5555555555555555'u64) shl 1) or ((n and 0xaaaaaaaaaaaaaaaa'u64) shr 1)
  n = ((n and 0x3333333333333333'u64) shl 2) or ((n and 0xcccccccccccccccc'u64) shr 2)
  n = ((n and 0x0f0f0f0f0f0f0f0f'u64) shl 4) or ((n and 0xf0f0f0f0f0f0f0f0'u64) shr 4)
  return n shr (64 - k)
