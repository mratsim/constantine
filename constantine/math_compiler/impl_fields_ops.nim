# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/[llvm, asm_nvidia],
  ./ir,
  ./impl_fields_globals,
  ./impl_fields_dispatch

## Section name used for `llvmInternalFnDef`
const SectionName = "ctt.impl_fields"

template declFieldOps*(asy: Assembler_LLVM, fd: FieldDescriptor): untyped {.dirty.} =
  ## This template can be used to make operations on `Field` elements
  ## more convenient.

  ## Note: This is handled via these templates, due to the Assembler_LLVM and
  ## (to a lesser extent) `FieldDescriptor` dependency.
  ## We could partially solve that by having `_impl` procs for every operation,
  ## which _only_ contains the inner code for the `llvmInternalFnDef` code.
  ## Thay way we could call _that_ function in these templates, which would
  ## be independent of the `asy`.
  ## For the `FieldDescriptor` we could anyhow (mostly?) reuse the `BuilderRef`
  ## that is part of the `Array` object (which `Field` is a `distinct` to).

  ## XXX: extend to include all ops
  # Boolean checks
  template isZero(res, x: Field): untyped  = asy.isZero(fd, res, x.buf)
  template isZero(x: Field): untyped =
    var res = asy.br.alloca(asy.ctx.int1_t())
    asy.isZero(fd, res, x.buf)
    res

  # Boolean logic
  template `not`(x: ValueRef): untyped     = asy.br.`not`(x)

  template checkIsBool(x: TypeRef): bool =
    x.getTypeKind == tkInteger and x.getIntTypeWidth == 1'u32
  template raiseIfNotBool(x: ValueRef, b: bool): untyped =
    if not b:
      raise newException(ValueError, "Code construction faulty. Expected a bool (i1) type, but " &
        "got: " & $x.getTypeOf)

  func derefBool(x: ValueRef): ValueRef =
    case x.getTypeOf.getTypeKind
    of tkPointer:
      result = asy.load2(asy.ctx.int1_t(), x)
      raiseIfNotBool(result, checkIsBool(result.getTypeOf))
    of tkInteger:
      raiseIfNotBool(x, checkIsBool(x.getTypeOf))
      result = x
    else:
      raiseIfNotBool(x, false)
      # will raise

  template `and`(x, y): untyped            = asy.br.`and`(derefBool x, derefBool y) # returns `i1`

  # Mutators
  template setZero(x: Field): untyped      = asy.setZero(fd, x.buf)
  template setOne(x: Field): untyped       = asy.setOne(fd, x.buf)
  template neg(res, y: Field): untyped     = asy.neg(fd, res.buf, y.buf)
  template neg(x: Field): untyped          =
    var res = asy.newField(fd)
    res.store(x)
    x.neg(res)

  # Conditional setters
  template csetZero(x: Field, c): untyped  = asy.csetZero(fd, x.buf, derefBool c)
  template csetOne(x: Field, c): untyped   = asy.csetOne(fd, x.buf, derefBool c)

  # Basic arithmetic
  template sum(res, x, y: Field): untyped  = asy.add(fd, res.buf, x.buf, y.buf)
  template add(res, x, y: Field): untyped  = res.sum(x, y)
  template diff(res, x, y: Field): untyped = asy.sub(fd, res.buf, x.buf, y.buf)
  template prod(res, x, y: Field, skipFinalSub: bool): untyped = asy.mul(fd, res.buf, x.buf, y.buf, skipFinalSub)
  template prod(res, x, y: Field): untyped = res.prod(x, y, skipFinalSub = false)

  # Conditional arithmetic
  template cadd(x, y: Field, c): untyped   = asy.cadd(fd, x.buf, y.buf, derefBool c)
  template csub(x, y: Field, c): untyped   = asy.csub(fd, x.buf, y.buf, derefBool c)
  template ccopy(x, y: Field, c): untyped  = asy.ccopy(fd, x.buf, y.buf, derefBool c)

  # Extended arithmetic
  template square(res, y: Field, skipFinalSub: bool): untyped = asy.nsqr(fd, res.buf, y.buf, count = 1, skipFinalSub)
  template square(res, y: Field): untyped  = res.square(y, skipFinalSub = false)
  template square(x: Field, skipFinalSub: bool): untyped = square(x, x, skipFinalSub)
  template square(x: Field): untyped       = square(x, x, skipFinalSub = false)
  template double(res, x: Field): untyped  = asy.double(fd, res.buf, x.buf)
  template double(x: Field): untyped       = x.double(x)
  template div2(x: Field): untyped         = asy.div2(fd, x.buf)

  # Mutating assignment ops
  template `*=`(x, y: Field): untyped      = x.prod(x, y)
  template `+=`(x, y: Field): untyped      = x.add(x, y)
  template `-=`(x, y: Field): untyped      = x.diff(x, y)
  template `*=`(x: Field, b: int): untyped = asy.scalarMul(fd, x.buf, b)

  # Other helpers that do not warrant a full LLVM internal/public proc
  template mulCheckSparse(x: Field, y: int) =
    ## Multiplication with optimization for sparse inputs
    ## intended to be used with curve `coaf_a` as argument `y`.
    if y == 1:
      discard
    elif y == 0:
      x.setZero()
    elif y == -1:
      x.neg()
    else:
      x *= b

proc setZero*(asy: Assembler_LLVM, fd: FieldDescriptor, r: ValueRef) {.used.} =
  ## Generate an internal field setZero
  ## with signature
  ##   void name(FieldType r)
  ## with r the element to be zeroed.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_setZero_impl"
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

proc setOne*(asy: Assembler_LLVM, fd: FieldDescriptor, r: ValueRef) {.used.} =
  ## Generate an internal field setOne
  ## with signature
  ##   void name(FieldType r)
  ## with `r` the element to be set to 1 in Montgomery form.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_setOne_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)
    let ri = llvmParams
    let rF = asy.asField(fd, ri)

    let mOne = asy.getMontyOnePtr(fd)
    let mF = asy.asField(fd, mOne)

    # Need to call `store` for `Field`, which actually copies
    # the full data!
    store(rF, mF)

    asy.br.retVoid()

  asy.callFn(name, [r])

proc add*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b: ValueRef) {.used.} =
  ## Generate an internal field addition proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_add_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, b]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, bi) = llvmParams
    asy.modadd(fd, ri, ai, bi, M)
    asy.br.retVoid()

  asy.callFn(name, [r, a, b])

proc mul*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b: ValueRef, skipFinalSub: bool = false) {.used.} =
  ## Generate an internal field multiplication proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ##
  ## If `skipFinalSub` is true, we do not subtract the modulus after the
  ## multiplication.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_mul_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, b]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, bi) = llvmParams
    asy.mtymul(fd, ri, ai, bi, M, finalReduce = not skipFinalSub) # TODO: for now we only suport Montgomery representation
    asy.br.retVoid()
  asy.callFn(name, [r, a, b])

proc ccopy*(asy: Assembler_LLVM, fd: FieldDescriptor, a, b, c: ValueRef) {.used.} =
  ## Generate an internal field conditional copy proc
  ## with signature
  ##   `void name(FieldType a, FieldType b, bool condition)`
  ## with `a` and `b` field field elements and `condition`.
  ## If `condition` is `true`:  `b` is copied into `a`
  ## if `condition` is `false`: `a` is left unmodified.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_ccopy_impl"
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
      let resultLimb = asy.br.select(condition, bA[i], aA[i])
      aA[i] = resultLimb

    asy.br.retVoid()
  asy.callFn(name, [a, b, c])

proc csetOne*(asy: Assembler_LLVM, fd: FieldDescriptor, r, c: ValueRef) {.used.} =
  ## Generate an internal field conditional setOne
  ## with signature
  ##   void name(FieldType r, bool condition)
  ## with `r` the element to be set to 1 in Montgomery form, if
  ## the `condition` is `true`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_csetOne_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, c]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)
    let mOne = asy.getMontyOnePtr(fd)

    let (ri, ci) = llvmParams
    asy.ccopy(fd, ri, mOne, ci)

    asy.br.retVoid()

  asy.callFn(name, [r, c])

proc csetZero*(asy: Assembler_LLVM, fd: FieldDescriptor, r, c: ValueRef) {.used.} =
  ## Generate an internal field conditional setZero
  ## with signature
  ##   void name(FieldType r, bool condition)
  ## with `r` the element to be set to 1 in Montgomery form, if
  ## the `condition` is `true`.
  ##
  ## Generates a call, so that we zero can use this proc as part of another procedure.
  let name = fd.name & "_csetZero_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, c]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ci) = llvmParams

    # NOTE: We could follow the algorithm used for the BigInt
    # limbs, but we can also just combine `setZero`
    # with a ccopy.
    ## XXX: port the below
    var zero = asy.newField(fd)
    asy.setZero(fd, zero.buf)
    asy.ccopy(fd, ri, zero.buf, ci)

    when false:
      # func csetZero*(a: var Limbs, ctl: SecretBool) =
      #   ## Set ``a`` to 0 if ``ctl`` is true
      #   let mask = -(SecretWord(ctl) xor One)
      #   for i in 0 ..< a.len:
      #     a[i] = a[i] and mask

      # extend `int1_t` to `fd.wordTy`
      let cond = asy.br.zext(ci, fd.wordTy)
      # `xor` with `1`
      let One = constInt(fd.wordTy, 1)
      var mask = X
    asy.br.retVoid()

  asy.callFn(name, [r, c])

proc cadd*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, c: ValueRef) {.used.} =
  ## Generate an internal field conditional in-place addition proc
  ## with signature
  ##   void name(FieldType r, FieldType a, bool condition)
  ## `a` is added from `r` only if the `condition` is `true`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_cadd_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, c]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, ci) = llvmParams
    let t = asy.newField(fd)          # temp field for `add`
    let aA = asy.asField(fd, ai)
    asy.add(fd, t.buf, ri, ai)   # `t = r + b`
    asy.ccopy(fd, ai, t.buf, ci) # `a.ccopy(t, condition)`

    asy.br.retVoid()

  asy.callFn(name, [r, a, c])

proc sub*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b: ValueRef) {.used.} =
  ## Generate an internal field subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, FieldType b)
  ## with r the result and a, b the operands
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_sub_impl"
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

proc csub*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, c: ValueRef) {.used.} =
  ## Generate an internal field conditional in-place subtraction proc
  ## with signature
  ##   void name(FieldType r, FieldType a, bool condition)
  ## `a` is subtracted from `r` only if the `condition` is `true`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_csub_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, c]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai, ci) = llvmParams
    let t = asy.newField(fd)          # temp field for `sub`
    asy.sub(fd, t.buf, ri, ai)   # `t = r - b`
    asy.ccopy(fd, ri, t.buf, ci) # `r.ccopy(t, condition)`

    asy.br.retVoid()

  asy.callFn(name, [r, a, c])

proc double*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal out-of-place double procedure
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting field element, `a` the element to be doubled
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_double_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ri, ai) = llvmParams
    asy.add(fd, ri, ai, ai) # `r = a + a`

    asy.br.retVoid()
  asy.callFn(name, [r, a])

proc nsqr*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef, count: int,
                    skipFinalSub = false) {.used.} =
  ## Generate an internal CT nsqr procedure
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting field element, `a` the element to be (n-) squared.
  ##
  ## If `skipFinalSub` is true, we do not subtract the modulus even in the last iteration.
  ## This can be an optimization in some use cases.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_nsqr" & $count & "_impl"
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
      let fR = i == 1 and not skipFinalSub # only reduce on last iteration
      asy.mtymul(fd, ri, ri, ri, M, finalReduce = fR)

    asy.br.retVoid()
  asy.callFn(name, [r, a])

proc isZero*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal field isZero proc
  ## with signature
  ##   void name(*bool r, FieldType a)
  ## with r the result and a the operand
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_isZero_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")
    let M = asy.getModulusPtr(fd)

    let (ri, ai) = llvmParams
    let aA = asy.asArray(ai, fd.fieldTy)

    # Determine if `a == 0`
    ## XXX: Make this work, pass number to bool as return
    ## Then we can use this *maybe* in ~neg~ above!
    var isZero = aA[0]
    for i in 1 ..< fd.numWords:
      isZero = asy.br.`or`(isZero, aA[i])

    # create an int1 bool indicating if isZero is not zero: `notZero = isZero != 0`
    let cZeroW = constInt(fd.wordTy, 0)
    let isZeroI1 = asy.br.icmp(kEQ, isZero, cZeroW)

    asy.store(ri, isZeroI1)
    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc isOdd*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal field isOdd proc
  ## with signature
  ##   void name(*bool r, FieldType a)
  ## with r the result and a the operand
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_isOdd_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a]),
          {kHot}):
    tagParameter(1, "sret")

    let (ri, ai) = llvmParams
    let aA = asy.asArray(ai, fd.fieldTy)

    # Check if the least significant bit of the first word is 1
    let lsb = asy.br.and(aA[0], constInt(fd.wordTy, 1))
    let isOddI1 = asy.br.icmp(kNE, lsb, constInt(fd.wordTy, 0))

    asy.store(ri, isOddI1)
    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc neg*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a: ValueRef) {.used.} =
  ## Generate an internal field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a)`
  ## with `r` the resulting negated field element.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_neg_impl"
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

    # Determine if `a == 0` as a wordTy
    var isZeroW = aA[0]
    for i in 1 ..< fd.numWords:
      isZeroW = asy.br.`or`(isZeroW, aA[i])

    # Construct `isZero` as `i1`
    let cZeroW = constInt(fd.wordTy, 0)
    let isZero = asy.br.icmp(kEQ, isZeroW, cZeroW)

    # Zero result if `a == 0`
    for i in 0 ..< fd.numWords:
      # `select` uses `cZeroW` if `isZero == true`, else `rA`
      rA[i] = asy.br.select(isZero, cZeroW, rA[i])

    asy.br.retVoid()

  asy.callFn(name, [r, a])

proc cneg*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, c: ValueRef) {.used.} =
  ## Generate an internal conditional out of place field negation
  ## with signature
  ##   `void name(FieldType r, FieldType a, bool condition)`
  ## with `r` the resulting negated field element.
  ## The negation is only performed if `condition` is `true`.
  ##
  ## Generates a call, so that we one can use this proc as part of another procedure.
  let name = fd.name & "_cneg_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, c]),
          {kHot}):

    tagParameter(1, "sret")
    let (ri, ai, ci) = llvmParams
    let M = asy.getModulusPtr(fd)

    # first call the regular negation
    asy.neg(fd, ri, ai)
    # now ccopy
    asy.ccopy(fd, ri, ai, asy.br.`not`(ci))

    asy.br.retVoid()

  asy.callFn(name, [r, a, c])

proc shiftRight*(asy: Assembler_LLVM, fd: FieldDescriptor, a, k: ValueRef) {.used.} =
  ## Generate an internal field in-place shiftRight proc
  ## with signature
  ##   void name(FieldType a, i32 k)
  ## where a is the operand to be shifted and k is the shift amount
  let name = fd.name & "_shiftRight_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a, k]),
          {kHot}):
    tagParameter(1, "sret")
    let (ai, ki) = llvmParams
    let aA = asy.asArray(ai, fd.fieldTy)

    let wordBitWidth = constInt(fd.wordTy, fd.w)
    let shiftLeft = asy.br.sub(wordBitWidth, ki)

    # Process all but the last word
    for i in 0 ..< fd.numWords - 1:
      let current = aA[i]
      let next = aA[i + 1]

      let rightPart = asy.br.lshr(current, ki)
      let leftPart = asy.br.lshl(next, shiftLeft)
      let result = asy.br.`or`(rightPart, leftPart)

      aA[i] = result

    # Handle the last word
    let lastIndex = fd.numWords - 1
    aA[lastIndex] = asy.br.lshr(aA[lastIndex], ki)

    asy.br.retVoid()

  asy.callFn(name, [a, k])

proc div2*(asy: Assembler_LLVM, fd: FieldDescriptor, a: ValueRef) {.used.} =
  ## Generate an internal field in-place div2 proc
  ## with signature
  ##   void name(FieldType a, i32 k)
  ## where a is the operand to be divided by 2.
  let name = fd.name & "_div2_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a]),
          {kHot}):
    tagParameter(1, "sret")
    let ai = llvmParams
    #let aA = asy.asField(fd, ai)

    var wasOdd = asy.br.alloca(asy.ctx.int1_t())
    asy.isOdd(fd, wasOdd, ai)
    asy.shiftRight(fd, ai, constInt(fd.wordTy, 1))

    let pp1d2 = asy.getPrimePlus1div2Ptr(fd)
    asy.cadd(fd, ai, pp1d2, asy.load2(asy.ctx.int1_t(), wasOdd))

    asy.br.retVoid()

  asy.callFn(name, [a])

proc scalarMul*(asy: Assembler_LLVM, fd: FieldDescriptor, a: ValueRef, b: int) =
  ## Multiplication by a small integer known at compile-time
  ## with signature
  ##   void name(FieldType a)
  ## where `a` is the operand to be multiplied by the statically known `b`.
  ## `a` is modified in place, i.e. akin to `*=`.
  ##
  ## Direct port of the code in `finite_fields.nim`.

  # NOTE: This implementation could take a Nim RT `b` of course
  let name = fd.name & "_scalarMul_" & $b & "_impl"
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([a]),
          {kHot}):
    tagParameter(1, "sret")
    let ai = llvmParams

    # Make field ops convenient:
    declFieldOps(asy, fd)

    let a = asy.asField(fd, ai) # shadow `a` argument of proc

    let negate = b < 0
    let b = if negate: -b
            else: b
    if negate:
      a.neg(a)
    if b == 0:
      a.setZero()
    elif b == 1:
      discard # nothing to do!
    elif b == 2:
      a.double()
    elif b == 3:
      var t = asy.newField(fd)
      t.double(a)
      a += t
    elif b == 4:
      a.double()
      a.double()
    elif b == 5:
      var t = asy.newField(fd)
      t.double(a)
      t.double()
      a += t
    elif b == 6:
      var t = asy.newField(fd)
      t.double(a)
      t += a # 3
      a.double(t)
    elif b == 7:
      var t = asy.newField(fd)
      t.double(a)
      t.double()
      t.double()
      a.diff(t, a)
    elif b == 8:
      a.double()
      a.double()
      a.double()
    elif b == 9:
      var t = asy.newField(fd)
      t.double(a)
      t.double()
      t.double()
      a.sum(t, a)
    elif b == 10:
      var t = asy.newField(fd)
      t.double(a)
      t.double()
      a += t     # 5
      a.double()
    elif b == 11:
      var t = asy.newField(fd)
      t.double(a)
      t += a       # 3
      t.double()   # 6
      t.double()   # 12
      a.diff(t, a) # 11
    elif b == 12:
      var t = asy.newField(fd)
      t.double(a)
      t += a       # 3
      t.double()   # 6
      a.double(t)   # 12
    elif b == 15:
      var t = asy.newField(fd)
      t.double(a)
      t += a       # 3
      a.double(t)  # 6
      a.double()   # 12
      a += t       # 15
    elif b == 21:
      var t = asy.newField(fd)
      t.double(a)
      t.double()   # 4
      t += a       # 5
      t.double()   # 10
      t.double()   # 20
      a += t       # 21
    else:
      raise newException(ValueError, "Multiplication by small int: " & $b & " not implemented")

    asy.br.retVoid()

  asy.callFn(name, [a])
