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
  ./impl_fields_dispatch

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.pub_fields"

proc setZero_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r: ValueRef) {.used.} =
  ## Generate an internal field setZero
  ## with signature
  ##   void name(FieldType r, FieldType a)
  ## with r the element to be zeroed.
  ## and return the corresponding name to call it
  let name = fd.name & "_setZero_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let ri = llvmParams
    let rA = asy.asField(fd, ri)
    for i in 0 ..< fd.numWords:
      rA[i] = constInt(fd.wordTy, 0)

    asy.br.retVoid()

  asy.callFn(name, [r])

proc genFpSetZero*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the element to be zeroed.
  ## and return the corresponding name to call it

  let name = fd.name & "_setZero"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy]):
    let r = llvmParams
    asy.setZero_internal(fd, r)
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
    asy.modadd(fd, r, a, b, M)
    asy.br.retVoid()

  return name

proc sub_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b: ValueRef) {.used.} =
  ## Generate an internal field subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it
  let name = fd.name & "_sub_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, b]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, bi) = llvmParams
    asy.modsub(fd, ri, ai, bi, M)
    asy.br.retVoid()

  asy.callFn(name, [r, a, b])

proc genFpSub*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  ## Generate a public field subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it

  let name = fd.name & "_sub"
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [fd.fieldTy, fd.fieldTy, fd.fieldTy]):
    let (r, a, b) = llvmParams
    asy.sub_internal(fd, r, a, b)
    asy.br.retVoid()

  return name

proc mul_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b: ValueRef) {.used.} =
  ## Generate an internal field multiplication proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ## and return the corresponding name to call it
  let name = fd.name & "_mul_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, b]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, bi) = llvmParams
    asy.mtymul(fd, ri, ai, bi, M) # TODO: for now we only suport Montgomery representation
    asy.br.retVoid()
  asy.callFn(name, [r, a, b])

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
    asy.mul_internal(fd, r, a, b)
    asy.br.retVoid()
  return name

proc ccopy_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, a, b, c: ValueRef) {.used.} =
  ## Generate an internal field conditional copy proc
  ## with signature
  ##   `void name(FieldType a, FieldType b, bool condition)`
  ## with `a` and `b` field field elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ##
  ## Generates a call, so that we one can use this proc as part of another (public)
  ## procedure.
  let name = fd.name & "_ccopy_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, b, c]),
          {kHot}):

    tagParameter(1, "sret")
    let (ai, bi, condition) = llvmParams
    # Assuming fd.numWords is the number of limbs in the field element
    let aA = asy.asArray(ai, fd.fieldTy)
    let bA = asy.asArray(bi, fd.fieldTy)

    for i in 0 ..< fd.numWords:
      # `select` uses `bA` if `condition == true`, else `aA`
      ## XXX: Could also use nvidia PTX `slct` instead?
      let resultLimb = asy.br.select(condition, bA[i], aA[i])
      aA[i] = resultLimb

    asy.br.retVoid()
  asy.callFn(name, [a, b, c])

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

    asy.ccopy_internal(fd, a, b, condition)

    asy.br.retVoid()

  return name

proc nsqr_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef, count: int) {.used.} =
  ## Generate an internal CT nsqr procedure
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting field element, `a` the element to be (n-) squared.
  ##
  ## Generates a call, so that we one can use this proc as part of another (public)
  ## procedure.
  let name = fd.name & "_nsqr" & $count & "_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ri, ai) = llvmParams
    let M = asy.getModulusPtr(fd)

    let rA = asy.asArray(ri, fd.fieldTy)
    let aA = asy.asArray(ai, fd.fieldTy)
    for i in 0 ..< fd.numWords:
      rA[i] = aA[i]

    # `r` now stores `a`
    for i in countdown(count, 1):
      # `mtymul` does not touch `r` until the end to store the result. It uses a temporary
      # buffer internally. So we can just pass `r` 3 times!
      asy.mtymul(fd, ri, ri, ri, M)

    asy.br.retVoid()
  asy.callFn(name, [r, a])

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
    asy.nsqr_internal(fd, r, a, count)
    asy.br.retVoid()
  return name
    let M = asy.getModulusPtr(fd)

    let rA = asy.asArray(r, fd.fieldTy)
    let aA = asy.asArray(a, fd.fieldTy)
    for i in 0 ..< fd.numWords:
      rA[i] = aA[i]

    # `r` now stores `a`
    for i in countdown(count, 1):
      # `mtymul` does not touch `r` until the end to store the result. It uses a temporary
      # buffer internally. So we can just pass `r` 3 times!
      asy.mtymul(fd, r, r, r, M)

    asy.br.retVoid()

  return name

proc neg_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting negated field element.
  ##
  ## Generates a call, so that we one can use this proc as part of another (public)
  ## procedure.
  let name = fd.name & "_neg_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):

    tagParameter(1, "sret")
    let (ri, ai) = llvmParams
    let M = asy.getModulusPtr(fd)
    let aA = asy.asArray(ai, fd.fieldTy)
    let rA = asy.asArray(ri, fd.fieldTy)

    # Subtraction M - a
    asy.modsub(fd, ri, M, ai, M)

    # Determine if `a == 0`
    var isZero = aA[0]
    for i in 1 ..< fd.numWords:
      isZero = asy.br.`or`(isZero, aA[i])

    # `slct` takes a condition and returns argument 1 if `cond >= 0` and argument 2 if `cond < 0`.
    # Given that our `isZero` value is either positive or 0, we need to split the `== 0` and `> 0`
    # for the condition. We do this by turning positive values into negative ones and keeping
    # zeroes as is.
    # Further, `slct` needs a 32 bit value as the condition. We want to avoid truncating `isZero`,
    # from potentially larger values.
    # So we create a boolean of whether it is 0, extend it to 32 bit and
    # compute `0 - X` with `X ∈ {0, 1}`.

    # create an int1 bool indicating if isZero is not zero: `notZero = isZero != 0`
    let cZeroW = constInt(fd.wordTy, 0)
    let notZero = asy.br.icmp(kNE, isZero, cZeroW)

    # extend `int1_t` to `int32_t`
    let notZeroExt = asy.br.zext(notZero, asy.ctx.int32_t())

    # Create a value that's 0 if input was zero, -1 if input was non-zero
    # i.e. `negNotZero = 0 - notZeroExt`.
    let cZero32 = constInt(asy.ctx.int32_t(), 0)
    let negNotZero = asy.br.sub(cZero32, notZeroExt)

    # Zero result if `a == 0`
    for i in 0 ..< fd.numWords:
      # `slct`: r <- (c >= 0) ? a : b;
      rA[i] = asy.br.slct(cZeroW, rA[i], negNotZero)
      # -> copy `0` to `r` via `cZeroW` IFF `negNotZero == 0` (`c >= 0`)
      # -> copy `a` to `r` otherwise (`negNotZero < 0`)

    asy.br.retVoid()

  asy.callFn(name, [r, a])

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

    asy.neg_internal(fd, r, a)

    asy.br.retVoid()

  return name

proc cneg_internal*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, c: ValueRef) {.used.} =
  ## Generate an internal conditional out of place field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a, bool condition)`
  ## with `r` the resulting negated field element.
  ## The negation is only performed if `condition` is `true`.
  ##
  ## Returns the corresponding name to call it
  let name = fd.name & "_cneg_internal"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, c]),
          {kHot}):

    tagParameter(1, "sret")
    let (ri, ai, ci) = llvmParams
    let M = asy.getModulusPtr(fd)

    # first call the regular negation
    asy.neg_internal(fd, ri, ai)
    # now ccopy
    asy.ccopy_internal(fd, ri, ai, asy.br.`not`(ci))

    asy.br.retVoid()

  asy.callFn(name, [r, a, c])


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
    asy.cneg_internal(fd, r, a, c)
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
  let ptrBool = pointer_t(asy.ctx.int1_t())
  ## XXX: int32? int64?
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
