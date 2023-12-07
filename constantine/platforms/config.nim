# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Compiler and CPU architecture configuration
# ------------------------------------------------------------

const GCC_Compatible* = defined(gcc) or defined(clang) or defined(llvm_gcc) or defined(icc)
const X86* = defined(amd64) or defined(i386)

when sizeof(int) == 8 and GCC_Compatible:
  type
    uint128*{.importc: "unsigned __int128".} = object
    int128*{.importc: "__int128".} = object

# Env variable configuration
# ------------------------------------------------------------

const CTT_ASM {.booldefine.} = true
const CTT_32* {.booldefine.} = bool(sizeof(pointer)*8 == 32)
const UseASM_X86_32* = CTT_ASM and X86 and GCC_Compatible
const UseASM_X86_64* = not(CTT_32) and UseASM_X86_32

when UseASM_X86_64:
  static: doAssert bool(sizeof(pointer)*8 == 64), "Only 32-bit and 64-bit platforms are supported"

const UseAsmSyntaxIntel* {.booldefine.} = defined(lto) or defined(lto_incremental)
  ## When using LTO with AT&T syntax
  ## - GCC will give spurious "Warning: missing operand; zero assumed" with AT&T syntax
  ## - Clang will wrongly combine memory offset and constant propagated address of constants
  ##
  ## Intel syntax does not have such limitation.
  ## However
  ## - It is not supported on Apple Clang due to missing
  ##   commit: https://github.com/llvm/llvm-project/commit/ae98182cf7341181e4aa815c372a072dec82779f
  ##   Revision: https://reviews.llvm.org/D113707
  ##   Apple bug: FB12137688
  ## - Global "-masm=intel" composition with other libraries that use AT&T inline assembly
  ##
  ## As a workaround:
  ## - On MacOS/iOS upstream Clang can be used instead of Apple fork.
  ## - Do not use LTO or build Constantine as a separate library
  ##
  ## Regarding -masm=intel:
  ##   - It might be possible to use Intel assembly is used on a per-file basis
  ##     so that we do not affect other libraries that might be compiled together with Constantine.
  ##     Generating an object file works but the final linking step assumes AT&T syntax and fails.
  ##   - Surrounding code with ".intel_syntax noprefix" and "att_syntax prefix"
  ##     doesn't work with memory operands.

when UseAsmSyntaxIntel:
  {.passC: "-masm=intel".}