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
  ./impl_fields_globals,
  ./impl_fields_dispatch

proc genFpAdd*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field addition proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it

  let name = fd.name & "_add"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let M = asy.getModulusPtr(fd)

    let (r, a, b) = llvmParams
    asy.modadd(fd, r, a, b, M)
    asy.br.retVoid()

  return name

proc genFpSub*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field substraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it

  let name = fd.name & "_sub"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let M = asy.getModulusPtr(fd)

    let (r, a, b) = llvmParams
    asy.modsub(fd, r, a, b, M)
    asy.br.retVoid()

  return name

proc genFpMul*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field substraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it

  let name = fd.name & "_mul"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let M = asy.getModulusPtr(fd)

    let (r, a, b) = llvmParams
    asy.mtymul(fd, r, a, b, M) # TODO: for now we only suport Montgomery representation
    asy.br.retVoid()

  return name