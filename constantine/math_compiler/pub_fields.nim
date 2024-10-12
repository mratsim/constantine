# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# NOTE: We probably don't want the explicit `asm_nvidia` dependency here, I imagine? Currently it's
# for direct usage of `slct` in `neg`.
import
  constantine/platforms/llvm/[llvm, asm_nvidia],
  ./ir,
  ./impl_fields_globals,
  ./impl_fields_dispatch,
  ./impl_fields_ops

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_fields"

proc genFpSetZero*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field setZero procedure
  ## with signature
  ##   void name(FieldType r)
  ## with r the element to be zeroed.
  ## and return the corresponding name to call it

  let name = fd.name & "_setZero"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy]):
    let r = llvmParams
    asy.setZero(fd, r)
    asy.br.retVoid()

  return name

proc genFpSetOne*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field setOne procedure
  ## with signature
  ##   void name(FieldType r)
  ## with `r` the element to be set to 1 in Montgomery form.
  ## and return the corresponding name to call it

  let name = fd.name & "_setOne"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy]):
    let r = llvmParams
    asy.setOne(fd, r)
    asy.br.retVoid()

  return name

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
    asy.add(fd, r, a, b)
    asy.br.retVoid()

  return name

proc genFpMul*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field multiplication proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it
  let name = fd.name & "_mul"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let M = asy.getModulusPtr(fd)
    let (r, a, b) = llvmParams
    asy.mul(fd, r, a, b)
    asy.br.retVoid()
  return name

proc genFpCcopy*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field conditional copy proc
  ## with signature
  ##   `void name(FieldType a, FieldType b, bool condition)`
  ## with `a` and `b` field field elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_ccopy"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, asy.ctx.int1_t()]):
    let (a, b, condition) = llvmParams

    asy.ccopy(fd, a, b, condition)

    asy.br.retVoid()

  return name

proc genFpCsetOne*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field conditional setOne
  ## with signature
  ##   void name(FieldType r, bool condition)
  ## with `r` the element to be set to 1 in Montgomery form, if
  ## the `condition` is `true`.
  ##
  ## Returns the name of the kernel to call it.

  let name = fd.name & "_csetOne"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, asy.ctx.int1_t()]):
    let (r, c) = llvmParams
    asy.csetOne(fd, r, c)
    asy.br.retVoid()

  return name

proc genFpCsetZero*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field conditional setZero
  ## with signature
  ##   void name(FieldType r, bool condition)
  ## with `r` the element to be set to 1 in Montgomery form, if
  ## the `condition` is `true`.
  ##
  ## Returns the name of the kernel to call it.

  let name = fd.name & "_csetZero"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, asy.ctx.int1_t()]):
    let (r, c) = llvmParams
    asy.csetZero(fd, r, c)
    asy.br.retVoid()

  return name

proc genFpCadd*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field conditional in-place addition proc
  ## with signature
  ##   void name(FieldType r, FieldType a, bool condition)
  ## `a` is added from `r` only if the `condition` is `true`.
  ##
  ## and return the corresponding name to call it

  let name = fd.name & "_add"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, asy.ctx.int1_t()]):
    let (r, a, c) = llvmParams
    asy.cadd(fd, r, a, c)
    asy.br.retVoid()

  return name

proc genFpSub*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it

  let name = fd.name & "_sub"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let (r, a, b) = llvmParams
    asy.sub(fd, r, a, b)
    asy.br.retVoid()

  return name

proc genFpCsub*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field conditional in-place subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, bool condition)
  ## `a` is subtracted from `r` only if the `condition` is `true`.
  ##
  ## and return the corresponding name to call it

  let name = fd.name & "_sub"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, asy.ctx.int1_t()]):
    let (r, a, c) = llvmParams
    asy.csub(fd, r, a, c)
    asy.br.retVoid()

  return name

proc genFpDouble*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate an internal out-of-place double procedure
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting field element, `a` the element to be doubled
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_double"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy]):
    ## We can just reuse `mtymul`
    let (r, a) = llvmParams
    asy.double(fd, r, a)
    asy.br.retVoid()
  return name

proc genFpNsqr*(asy: Assembler_LLVM, fd: FieldDescriptor, count: int): string =
  ## Generate a public field n-square proc
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting field element, `a` the field element to square
  ## `count` times (i.e. for counts `[1, 2, 3, ...]` it yields `[a², a⁴, a⁸, ...]`).
  ## `count` is appended to the `name` of the function.
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_nsqr_" & $count
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy]):
    ## We can just reuse `mtymul`
    let (r, a) = llvmParams
    asy.nsqr(fd, r, a, count)
    asy.br.retVoid()
  return name

proc genFpIsZero*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field isZero proc
  ## with signature
  ##   void name(*bool r, FieldType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = fd.name & "_isZero"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrBool, fd.fieldTy]):
    let (r, a) = llvmParams
    asy.isZero(fd, r, a)
    asy.br.retVoid()

  return name

proc genFpIsOdd*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field isOdd proc
  ## with signature
  ##   void name(*bool r, FieldType a)
  ## with r the result and a the operand
  ## and return the corresponding name to call it

  let name = fd.name & "_isOdd"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrBool, fd.fieldTy]):
    let (r, a) = llvmParams
    asy.isOdd(fd, r, a)
    asy.br.retVoid()

  return name

proc genFpNeg*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting negated field element.
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_neg"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy]):
    let (r, a) = llvmParams

    asy.neg(fd, r, a)

    asy.br.retVoid()

  return name

proc genFpCNeg*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate an internal conditional out of place field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a, bool condition)`
  ## with `r` the resulting negated field element.
  ## The negation is only performed if `condition` is `true`.
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_cneg"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, asy.ctx.int1_t()]):
    let (r, a, c) = llvmParams
    asy.cneg(fd, r, a, c)
    asy.br.retVoid()
  return name

template genCountdownLoop(asy: Assembler_LLVM, fn, initialValue: ValueRef, body: untyped): untyped =
  ## A helper template that constructs a `countdown(initialValue, 1)` loop.
  let loopEntry = asy.ctx.appendBasicBlock(fn, "loop.entry")
  let loopBody  = asy.ctx.appendBasicBlock(fn, "loop.body")
  let loopExit  = asy.ctx.appendBasicBlock(fn, "loop.exit")

  # Branch to loop entry
  asy.br.br(loopEntry)

  let c0 = constInt(asy.ctx.int32_t(), 0)
  let c1 = constInt(asy.ctx.int32_t(), 1)

  # Loop entry
  asy.br.positionAtEnd(loopEntry)
  let condition = asy.br.icmp(kSGT, initialValue, c0)
  asy.br.condBr(condition, loopBody, loopExit)

  # Loop body
  asy.br.positionAtEnd(loopBody)
  let phi = asy.br.phi(getTypeOf initialValue)
  phi.addIncoming(initialValue, loopEntry)

  # Decrement
  let decremented = asy.br.sub(phi, c1)
  phi.addIncoming(decremented, loopBody)

  # The loop body
  body

  # Check if we should continue looping
  let continueLoop = asy.br.icmp(kSGT, decremented, c0)
  asy.br.condBr(continueLoop, loopBody, loopExit)

  # Loop exit
  asy.br.positionAtEnd(loopExit)

proc genFpNsqrRT*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field n-square proc
  ## with signature
  ##   `void name(FieldType r, FieldType a, count int)`
  ## with `r` the resulting field element, `a` the field element to square
  ## `count` times (i.e. for counts `[1, 2, 3, ...]` it yields `[a², a⁴, a⁸, ...]`).
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_nsqr"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, asy.ctx.int32_t()]):
    ## We can just reuse `mtymul`
    let (r, a, count) = llvmParams
    let M = asy.getModulusPtr(fd)

    let rA = asy.asArray(r, fd.fieldTy)
    let aA = asy.asArray(a, fd.fieldTy)
    for i in 0 ..< fd.numWords:
      rA[i] = aA[i]

    asy.genCountdownLoop(fn, count):
      # use `mtymul` to multiply `r·r` and store it again in `r`
      asy.mtymul(fd, r, r, r, M)

    asy.br.retVoid()
  return name

proc genFpShiftRight*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field in-place shiftRight proc
  ## with signature
  ##   void name(FieldType a, i32 k)
  ## where a is the operand to be shifted and k is the shift amount
  ## and return the corresponding name to call it

  let name = fd.name & "_shiftRight"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, asy.ctx.int32_t()]):
    let (a, k) = llvmParams
    asy.shiftRight(fd, a, k)
    asy.br.retVoid()

  return name

proc genFpDiv2*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field in-place div2 proc
  ## with signature
  ##   void name(FieldType a, i32 k)
  ## where a is the operand to be shifted and k is the shift amount
  ## and return the corresponding name to call it

  let name = fd.name & "_div2"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy]):
    let a = llvmParams
    asy.div2(fd, a)
    asy.br.retVoid()

  return name

proc genFpScalarMul*(asy: Assembler_LLVM, fd: FieldDescriptor, b: static int): string =
  ## Multiplication by a small integer known at compile-time
  ## with signature
  ##   void name(FieldType a)
  ## where `a` is the operand to be multiplied by the statically known `b`.
  ## `a` is modified in place, i.e. akin to `*=`.
  ##
  ## Returns the corresponding name to call it.

  let name = fd.name & "_scalarMul_" & $b
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy]):
    let a = llvmParams
    asy.scalarMul(fd, a, b)
    asy.br.retVoid()

  return name
