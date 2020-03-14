# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./constant_time_types

# ############################################################
#
#            Add-with-carry and Sub-with-borrow
#
# ############################################################
#
# This file implements add-with-carry and sub-with-borrow
#
# It is currently (Mar 2020) impossible to have the compiler
# generate optimal code in a generic way.
#
# On x86, addcarry_u64 intrinsic will generate optimal code
# except for GCC.
#
# On other CPU architectures inline assembly might be desirable.
# A compiler proof-of-concept is available in the "research" folder.
#
# See https://gcc.godbolt.org/z/2h768y
# ```C
# #include <stdint.h>
# #include <x86intrin.h>
#
# void add256(uint64_t a[4], uint64_t b[4]){
#   uint8_t carry = 0;
#   for (int i = 0; i < 4; ++i)
#     carry = _addcarry_u64(carry, a[i], b[i], &a[i]);
# }
# ```
#
# GCC
# ```asm
# add256:
#         movq    (%rsi), %rax
#         addq    (%rdi), %rax
#         setc    %dl
#         movq    %rax, (%rdi)
#         movq    8(%rdi), %rax
#         addb    $-1, %dl
#         adcq    8(%rsi), %rax
#         setc    %dl
#         movq    %rax, 8(%rdi)
#         movq    16(%rdi), %rax
#         addb    $-1, %dl
#         adcq    16(%rsi), %rax
#         setc    %dl
#         movq    %rax, 16(%rdi)
#         movq    24(%rsi), %rax
#         addb    $-1, %dl
#         adcq    %rax, 24(%rdi)
#         ret
# ```
#
# Clang
# ```asm
# add256:
#         movq    (%rsi), %rax
#         addq    %rax, (%rdi)
#         movq    8(%rsi), %rax
#         adcq    %rax, 8(%rdi)
#         movq    16(%rsi), %rax
#         adcq    %rax, 16(%rdi)
#         movq    24(%rsi), %rax
#         adcq    %rax, 24(%rdi)
#         retq
# ```

# ############################################################
#
#                     Intrinsics
#
# ############################################################

when X86:
  when defined(windows):
    {.pragma: intrinsics, header:"<intrin.h>", nodecl.}
  else:
    {.pragma: intrinsics, header:"<x86intrin.h>", nodecl.}

  func addcarry_u32(carryIn: Carry, a, b: Ct[uint32], sum: var Ct[uint32]): Carry {.importc: "_addcarry_u32", intrinsics.}
  func subborrow_u32(borrowIn: Borrow, a, b: Ct[uint32], diff: var Ct[uint32]): Borrow {.importc: "_subborrow_u32", intrinsics.}

  func addcarry_u64(carryIn: Carry, a, b: Ct[uint64], sum: var Ct[uint64]): Carry {.importc: "_addcarry_u64", intrinsics.}
  func subborrow_u64(borrowIn: Borrow, a, b: Ct[uint64], diff: var Ct[uint64]): Borrow {.importc: "_subborrow_u64", intrinsics.}

# ############################################################
#
#                     Public
#
# ############################################################

func addC*(cOut: var Carry, sum: var Ct[uint32], a, b: Ct[uint32], cIn: Carry) {.inline.} =
  ## Addition with carry
  ## (CarryOut, Sum) <- a + b + CarryIn
  when X86:
    cOut = addcarry_u32(cIn, a, b, sum)
  else:
    let dblPrec = uint64(cIn) + uint64(a) + uint64(b)
    sum = (Ct[uint32])(dblPrec)
    cOut = Carry(dblPrec shr 32)

func subB*(bOut: var Borrow, sum: var Ct[uint32], a, b: Ct[uint32], bIn: Borrow) {.inline.} =
  ## Substraction with borrow
  ## (BorrowOut, Diff) <- a - b - borrowIn
  when X86:
    bOut = subborrow_u32(bIn, a, b, sum)
  else:
    let dblPrec = uint64(a) - uint64(b) - bIn
    diff = (Ct[uint32])(dblPrec)
    bOut = Borrow(dblPrec shr 32)
