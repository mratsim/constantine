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

when sizeof(int) == 8:
  type
    BaseType* = uint64
      ## Physical BigInt for conversion in "normal integers"
else:
  type
    BaseType* = uint32
      ## Physical BigInt for conversion in "normal integers"

type
  Word* = Ct[BaseType]
    ## Logical BigInt word
    ## A logical BigInt word is of size physical MachineWord-1

const
  WordBitWidth* = sizeof(Word) * 8
    ## Logical word size

  CtTrue* = ctrue(Word)
  CtFalse* = cfalse(Word)

  Zero* = Word(0)
  One* = Word(1)
  MaxWord* = Word(high(BaseType))

# ############################################################
#
#                  Instrumentation
#
# ############################################################

template debug*(body: untyped): untyped =
  when defined(debugConstantine):
    body
