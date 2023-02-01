# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Platforms abstractions
#
# ############################################################

import ./primitives
import ../../metering/tracer

export primitives, tracer

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


  Limbs*[N: static int] = array[N, SecretWord]
    ## Limbs-type
    ## Should be distinct type to avoid builtins to use non-constant time
    ## implementation, for example for comparison.
    ##
    ## but for unknown reason, it prevents semchecking `bits`

const
  WordBitWidth* = sizeof(SecretWord) * 8
    ## Logical word size

  CtTrue* = ctrue(SecretWord)
  CtFalse* = cfalse(SecretWord)

  Zero* = SecretWord(0)
  One* = SecretWord(1)
  MaxWord* = SecretWord(high(BaseType))

const CttASM {.booldefine.} = true
const UseASM_X86_32* = CttASM and X86 and GCC_Compatible
const UseASM_X86_64* = WordBitWidth == 64 and UseASM_X86_32

# We use Nim effect system to track vartime subroutines
type VarTime*   = object