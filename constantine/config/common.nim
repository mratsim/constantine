# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Common configuration
#
# ############################################################

import ../primitives

when sizeof(int) == 8 and not defined(Constantine32):
  type
    BaseType* = uint64
      ## Physical BigInt for conversion in "normal integers"
else:
  type
    BaseType* = uint32
      ## Physical BigInt for conversion in "normal integers"

type
  SecretWord* = Ct[BaseType]
    ## Logical BigInt word
    ## A logical BigInt word is of size physical MachineWord-1

  SecretBool* = CTBool[SecretWord]

const
  WordBitWidth* = sizeof(SecretWord) * 8
    ## Logical word size

  CtTrue* = ctrue(SecretWord)
  CtFalse* = cfalse(SecretWord)

  Zero* = SecretWord(0)
  One* = SecretWord(1)
  MaxWord* = SecretWord(high(BaseType))

# TODO, we restrict assembly to 64-bit words
# We need to support register spills for large limbs
const ConstantineASM {.booldefine.} = true
const UseASM* = WordBitWidth == 64 and ConstantineASM and X86 and GCC_Compatible

# ############################################################
#
#                  Instrumentation
#
# ############################################################

template debug*(body: untyped): untyped =
  when defined(debugConstantine):
    body
