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
  ./impl_fields_isa_nvidia {.all.}

proc modadd*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) =
  case asy.backend
  of {bkX86_64_Linux, bkArm64_MacOS, bkAmdGpu}:
    asy.modadd_sat(fd, r, a, b, M)
  of bkNvidiaPTX:
    # addcarries are not properly produced and chained with Nvidia backend
    asy.modadd_nvidia(fd, r, a, b, M)

proc modsub*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) =
  case asy.backend
  of {bkX86_64_Linux, bkArm64_MacOS, bkAmdGpu}:
    asy.modsub_sat(fd, r, a, b, M)
  of bkNvidiaPTX:
    # subborrows are not properly produced and chained with Nvidia backend
    asy.modsub_nvidia(fd, r, a, b, M)

proc mtymul*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce = true) =
  case asy.backend
  of bkX86_64_Linux:
    # TODO: Fallback code that doesn't use extended precision mul and dual carry chains
    asy.mtymul_sat_mulhi(fd, r, a, b, M, finalReduce)
  of {bkArm64_MacOS, bkAmdGpu}:
    asy.mtymul_sat_mulhi(fd, r, a, b, M, finalReduce)
  of bkNvidiaPTX:
    # mtymul_sat_mulhi does not produce fused instructions
    #   mad.lo mad.lo.cc, madc.lo, madc.lo.cc
    #   mad.hi mad.hi.cc, madc.hi, madc.hi.cc
    asy.mtymul_nvidia(fd, r, a, b, M, finalReduce)
