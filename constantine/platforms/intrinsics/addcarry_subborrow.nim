# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config,
  ../constant_time/ct_types

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
# See https://gcc.godbolt.org/z/2h768y (Mar 2020 compilers)
#     https://gcc.godbolt.org/z/WP38PzsMs
#    (Dec 2023 compilers improved but __builtin_addcll leads to very poor GCC codegen)
#    Tracking compiler inefficients - https://github.com/mratsim/constantine/issues/357
#
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

# Note: GCC before 2017 had incorrect codegen in some cases:
# - https://gcc.gnu.org/bugzilla/show_bug.cgi?id=81300

when X86:
  when defined(windows):
    {.pragma: intrinsics, header:"<intrin.h>", nodecl.}
  else:
    {.pragma: intrinsics, header:"<x86intrin.h>", nodecl.}

  func addcarry_u32(carryIn: Carry, a, b: cuint, sum: var cuint): Carry {.importc: "_addcarry_u32", intrinsics.}
  func subborrow_u32(borrowIn: Borrow, a, b: cuint, diff: var cuint): Borrow {.importc: "_subborrow_u32", intrinsics.}

  # Note, Nim uint64 maps to uint64_t which maps to long unsigned int on 64-bit instead of long long unsigned int
  func addcarry_u64(carryIn: Carry, a, b: culonglong, sum: var culonglong): Carry {.importc: "_addcarry_u64", intrinsics.}
  func subborrow_u64(borrowIn: Borrow, a, b: culonglong, diff: var culonglong): Borrow {.importc: "_subborrow_u64", intrinsics.}

  template addcarry_u32(carryIn: Carry, a, b: Ct[uint32], sum: var Ct[uint32]): Carry =
    addcarry_u32(carryIn, cast[cuint](a), cast[cuint](b), cast[ptr cuint](sum.addr)[])

  template subborrow_u32(borrowIn: Borrow, a, b: Ct[uint32], sum: var Ct[uint32]): Borrow =
    subborrow_u32(borrowIn, cast[cuint](a), cast[cuint](b), cast[ptr cuint](sum.addr)[])

  template addcarry_u64(carryIn: Carry, a, b: Ct[uint64], sum: var Ct[uint64]): Carry =
    addcarry_u64(carryIn, cast[culonglong](a), cast[culonglong](b), cast[ptr culonglong](sum.addr)[])

  template subborrow_u64(borrowIn: Borrow, a, b: Ct[uint64], sum: var Ct[uint64]): Borrow =
    subborrow_u64(borrowIn, cast[culonglong](a), cast[culonglong](b), cast[ptr culonglong](sum.addr)[])

elif defined(clang):
  func builtin_addcl(x, y: Ct[uint32], carryIn: Ct[uint32], carryOut: var Ct[uint32]): Ct[uint32] {.importc: "__builtin_addcl", nodecl.}
  func builtin_subcl(x, y: Ct[uint32], carryIn: Ct[uint32], carryOut: var Ct[uint32]): Ct[uint32] {.importc: "__builtin_subcl", nodecl.}

  func builtin_addcll(x, y: Ct[uint64], carryIn: Ct[uint64], carryOut: var Ct[uint64]): Ct[uint64] {.importc: "__builtin_addcll", nodecl.}
  func builtin_subcll(x, y: Ct[uint64], carryIn: Ct[uint64], carryOut: var Ct[uint64]): Ct[uint64] {.importc: "__builtin_subcll", nodecl.}

# ############################################################
#
#                     Public
#
# ############################################################

const
  nim_v2 = (NimMajor, NimMinor) > (1, 6)
  noExplicitVarDeref {.used.} = defined(cpp) or nim_v2
    ## In C++ mode or with Nim v2, emit of `var` params is auto-deref by Nim.

func addC*(cOut: var Carry, sum: var Ct[uint32], a, b: Ct[uint32], cIn: Carry) {.inline.} =
  ## Addition with carry
  ## (CarryOut, Sum) <- a + b + CarryIn
  when X86:
    cOut = addcarry_u32(cIn, a, b, sum)
  elif defined(clang):
    var carryOut: Ct[uint32]
    sum = builtin_addcl(a, b, cast[Ct[uint32]](cIn), carryOut)
    cOut = cast[Carry](carryOut)
  else:
    let dblPrec = uint64(cIn) + uint64(a) + uint64(b)
    sum = (Ct[uint32])(dblPrec)
    cOut = Carry(dblPrec shr 32)

func subB*(bOut: var Borrow, diff: var Ct[uint32], a, b: Ct[uint32], bIn: Borrow) {.inline.} =
  ## Substraction with borrow
  ## (BorrowOut, Diff) <- a - b - borrowIn
  when X86:
    bOut = subborrow_u32(bIn, a, b, diff)
  elif defined(clang):
    var borrowOut: Ct[uint32]
    diff = builtin_subcl(a, b, cast[Ct[uint32]](bIn), borrowOut)
    bOut = cast[Borrow](borrowOut)
  else:
    let dblPrec = uint64(a) - uint64(b) - uint64(bIn)
    diff = (Ct[uint32])(dblPrec)
    # On borrow the high word will be 0b1111...1111 and needs to be masked
    bOut = Borrow((dblPrec shr 32) and 1)

func addC*(cOut: var Carry, sum: var Ct[uint64], a, b: Ct[uint64], cIn: Carry) {.inline.} =
  ## Addition with carry
  ## (CarryOut, Sum) <- a + b + CarryIn
  when X86:
    cOut = addcarry_u64(cIn, a, b, sum)
  elif defined(clang):
    var carryOut: Ct[uint64]
    sum = builtin_addcll(a, b, cast[Ct[uint64]](cIn), carryOut)
    cOut = cast[Carry](carryOut)
  else:
    block:
      static:
        doAssert GCC_Compatible
        doAssert sizeof(int) == 8

      var dblPrec {.noInit.}: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a," + (unsigned __int128)", b, " + (unsigned __int128)",cIn,";"].}

      when noExplicitVarDeref:
        {.emit:[cOut, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
        {.emit:[sum, " = (NU64)", dblPrec,";"].}
      else:
        {.emit:["*",cOut, " = (NU64)(", dblPrec," >> ", 64'u64, ");"].}
        {.emit:["*",sum, " = (NU64)", dblPrec,";"].}

func subB*(bOut: var Borrow, diff: var Ct[uint64], a, b: Ct[uint64], bIn: Borrow) {.inline.} =
  ## Substraction with borrow
  ## (BorrowOut, Diff) <- a - b - borrowIn
  when X86:
    bOut = subborrow_u64(bIn, a, b, diff)
  elif defined(clang):
    var borrowOut: Ct[uint64]
    diff = builtin_subcll(a, b, cast[Ct[uint64]](bIn), borrowOut)
    bOut = cast[Borrow](borrowOut)
  else:
    block:
      static:
        doAssert GCC_Compatible
        doAssert sizeof(int) == 8

      var dblPrec {.noInit.}: uint128
      {.emit:[dblPrec, " = (unsigned __int128)", a," - (unsigned __int128)", b, " - (unsigned __int128)",bIn,";"].}

      when noExplicitVarDeref:
        {.emit:[bOut, " = (NU64)(", dblPrec," >> ", 64'u64, ") & 1;"].}
        {.emit:[diff, " = (NU64)", dblPrec,";"].}
      else:
        {.emit:["*",bOut, " = (NU64)(", dblPrec," >> ", 64'u64, ") & 1;"].}
        {.emit:["*",diff, " = (NU64)", dblPrec,";"].}
