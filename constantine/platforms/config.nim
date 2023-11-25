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

const UseAsmSyntaxIntel* {.booldefine.} = not(defined(macos) or defined(macosx) or defined(ios))
  ## When using LTO with AT&T syntax
  ## - GCC will give spurious "Warning: missing operand; zero assumed" with AT&T syntax
  ## - Clang will wrongly combine memory offset and constant propagated address of constants
  ##
  ## Intel syntax does not have such limitation.
  ## However
  ## - Global "-masm=intel" composition with other libraries that use AT&T inline assembly
  ## - It is not supported on Apple Clang due to missing
  ##   commit: https://github.com/llvm/llvm-project/commit/ae98182cf7341181e4aa815c372a072dec82779f
  ##   Revision: https://reviews.llvm.org/D113707
  ##
  ## As a workaround:
  ## - Intel assembly is used on a per-file basis
  ##   and does not affect other libraries that might be compiled together with Constantine.
  ## - It is deactivated on MacOs / iOS.
  ##   That means LTO will not work on MacOS unless upstream Clang is used instead of Apple fork.