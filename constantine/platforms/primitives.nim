# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constant_time/[
    ct_types,
    ct_routines,
    multiplexers,
    ct_division
  ],
  compilers/[
    addcarry_subborrow,
    extended_precision
  ],
  ./bithacks,
  ../../helpers/static_for

export
  ct_types,
  ct_routines,
  multiplexers,
  addcarry_subborrow,
  extended_precision,
  ct_division,
  bithacks,
  staticFor

when X86 and GCC_Compatible:
  import isa/[cpuinfo_x86, macro_assembler_x86]
  export cpuinfo_x86, macro_assembler_x86
