# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/llvm,
  ./ir,
  ./impl_fields_sat {.all.},
  ./impl_fields_nvidia {.all.}

proc modadd*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) =
  case asy.backend
  of {bkX86_64_Linux, bkAmdGpu}:
    asy.modadd_sat(fd, r, a, b, M)
  of bkNvidiaPTX:
    asy.modadd_nvidia(fd, r, a, b, M)

proc modsub*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) =
  case asy.backend
  of bkNvidiaPTX:
    asy.modsub_nvidia(fd, r, a, b, M)
  else:
    doAssert false, "Unimplemented"

proc mtymul*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce = true) =
  case asy.backend
  of bkNvidiaPTX:
    asy.mtymul_nvidia(fd, r, a, b, M, finalReduce)
  else:
    doAssert false, "Unimplemented"
