# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../config

when UseAsmSyntaxIntel:
  # We need Intel syntax.
  # When using memory operand with displacement the default AT&T syntax is
  # 8(%[identifier])
  # GCC accepts 8+(%[identifier]) as well but not Clang
  # However when constant are propagated, 8(%[identifier]) can also expand to
  # 8BLS12_381_Modulus(%rip) i.e. the compiler tries to forward to the linker the relative address of a constant
  # and due to naive string mixin it fails.
  {.passC:"-masm=intel".}

  import ./macro_assembler_x86_intel
  export macro_assembler_x86_intel
else:
  import ./macro_assembler_x86_att
  export macro_assembler_x86_att