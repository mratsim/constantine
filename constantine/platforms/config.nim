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

const UseAsmSyntaxIntel* {.booldefine.} = true
