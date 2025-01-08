# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/bithacks,
  constantine/platforms/llvm/[llvm, super_instructions],
  constantine/named/deriv/parser_fields, # types for curve definition
  std/[tables, typetraits]

# ############################################################
#
#                      Assembler
#
# ############################################################

type
  AttrKind* = enum
    # Other important properties like
    # - norecurse
    # - memory side-effects memory(argmem: readwrtite)
    #   can be deduced.
    kHot,
    kInline,
    kAlwaysInline,
    kNoInline

  Assembler_LLVMObj* = object
    ctx*: ContextRef
    module*: ModuleRef
    br*: BuilderRef
    datalayout: TargetDataRef
    psize*: int32
    publicCC: CallingConvention
    backend*: Backend
    byteOrder: ByteOrder

    # It doesn't seem possible to retrieve a function type
    # from its value, so we store them here.
    # If we store the type we might as well store the impl
    # and we store whether it's internal to apply the fastcc calling convention
    fns: Table[string, tuple[ty: TypeRef, impl: ValueRef, internal: bool]]
    attrs: array[AttrKind, AttributeRef]

    # Convenience
    void_t*: TypeRef

  Assembler_LLVM* = ref Assembler_LLVMObj

  Backend* = enum
    bkAmdGpu
    bkNvidiaPTX
    bkX86_64_Linux

proc finalizeAssemblerLLVM(asy: Assembler_LLVM) =
  if not asy.isNil:
    asy.br.dispose()
    asy.module.dispose()
    asy.ctx.dispose()
    # asy.datalayout.dispose() # unnecessary when module is cleared

proc configure(asy: var Assembler_LLVM, backend: Backend) =
  case backend
  of bkAmdGpu:
    asy.module.setTarget("amdgcn-amd-amdhsa")

    const datalayout1 {.used.} =
        "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-"               &
              "i64:64-"                                                                 &
              "v16:16-v24:32-"                                                          &
              "v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-" &
              "n32:64-S32-A5-G1-ni:7"

    const datalayout2 =
        "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-p7:160:256:256:32-p8:128:128-" &
              "i64:64-"                                                                                &
              "v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-"  &
              "n32:64-S32-A5-G1-ni:7:8"

    asy.module.setDataLayout(datalayout2)

  of bkNvidiaPTX:
    asy.module.setTarget("nvptx64-nvidia-cuda")
    # Datalayout for NVVM IR 1.8 (CUDA 11.6)
    asy.module.setDataLayout(
      "e-" & "p:64:64:64-" &
      "i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-i128:128:128-" &
      "f32:32:32-f64:64:64-" &
      "v16:16:16-v32:32:32-v64:64:64-v128:128:128-" &
      "n16:32:64")
  of bkX86_64_Linux:
    asy.module.setTarget("x86_64-pc-linux-gnu")

  asy.datalayout = asy.module.getDataLayout()
  asy.psize = int32 asy.datalayout.getPointerSize()
  asy.backend = backend
  asy.byteOrder = asy.dataLayout.getEndianness()

when defined(gcDestructors):
  proc `=destroy`(asy: Assembler_LLVMObj) =
    asy.br.dispose()
    asy.module.dispose()
    asy.ctx.dispose()

proc new*(T: type Assembler_LLVM, backend: Backend, moduleName: cstring): Assembler_LLVM =
  when not defined(gcDestructors):
    new result, finalizeAssemblerLLVM
  else:
    new result
  result.ctx = createContext()
  result.module = result.ctx.createModule(moduleName)
  result.br = result.ctx.createBuilder()
  result.datalayout = result.module.getDataLayout()

  result.void_t = result.ctx.void_t()

  result.configure(backend)

  result.attrs[kHot] = result.ctx.createAttr("hot")
  result.attrs[kInline] = result.ctx.createAttr("inlinehint")
  result.attrs[kAlwaysInline] = result.ctx.createAttr("alwaysinline")
  result.attrs[kNoInline] = result.ctx.createAttr("noinline")
  result.attrs[kNoInline] = result.ctx.createAttr("sret")

# ############################################################
#
#                     Syntax Sugar
#
# ############################################################

func i1*(asy: Assembler_LLVM, v: SomeInteger): ValueRef =
  constInt(asy.ctx.int1_t(), v)

func i32*(asy: Assembler_LLVM, v: SomeInteger): ValueRef =
  constInt(asy.ctx.int32_t(), v)

# ############################################################
#
#               Intermediate Representation
#
# ############################################################

func wordsRequired*(bits, wordBitwidth: SomeInteger): SomeInteger {.inline.} =
  ## Compute the number of limbs required
  ## from the announced bit length

  doAssert wordBitwidth == 32 or wordBitwidth == 64               # Power of 2
  (bits + wordBitwidth - 1) shr log2_vartime(uint32 wordBitwidth) # 5x to 55x faster than dividing by wordBitwidth

type
  FieldDescriptor* = object
    name*: string
    modulus*: string # Modulus as Big-Endian uppercase hex, NOT prefixed with 0x
    # primeKind*: PrimeKind

    # Word: i32, i64 but can also be v4i32, v16i32 ...
    wordTy*: TypeRef
    word2xTy*: TypeRef # Double the word size
    v*, w*: uint32
    numWords*: uint32
    zero*, zero_i1*: ValueRef
    intBufTy*: TypeRef # int type, multiple of the word size, that can store the field elements
                       # For example a 381 bit field is stored in 384-bit ints (whether on 32 or 64-bit platforms)

    # Field metadata
    fieldTy*: TypeRef
    bits*: uint32
    spareBits*: uint8

proc configureField*(ctx: ContextRef,
      name: string,
      modBits: int, modulus: string,
      v, w: int): FieldDescriptor =
  ## Configure a field descriptor with:
  ## - v: vector length
  ## - w: base word size in bits
  ## - a `modulus` of bitsize `modBits`
  ##
  ## - Name is a prefix for example
  ##   `mycurve_fp_`

  let v = uint32 v
  let w = uint32 w
  let modBits = uint32 modBits

  result.name = name
  result.modulus = modulus

  doAssert v == 1, "At the moment SIMD vectorization is not supported."
  result.v = v
  result.w = w

  result.numWords = wordsRequired(modBits, w)
  result.wordTy = ctx.int_t(w)
  result.word2xTy = ctx.int_t(w+w)
  result.zero = constInt(result.wordTy, 0)
  result.zero_i1 = constInt(ctx.int1_t(), 0)

  let next_multiple_wordsize = result.numWords * w
  result.intBufTy = ctx.int_t(next_multiple_wordsize)

  result.fieldTy = array_t(result.wordTy, result.numWords)
  result.bits = modBits
  result.spareBits = uint8(next_multiple_wordsize - modBits)

proc definePrimitives*(asy: Assembler_LLVM, fd: FieldDescriptor) =
  asy.ctx.def_llvm_add_overflow(asy.module, fd.wordTy)
  asy.ctx.def_llvm_add_overflow(asy.module, fd.intBufTy)
  asy.ctx.def_llvm_sub_overflow(asy.module, fd.wordTy)
  asy.ctx.def_llvm_sub_overflow(asy.module, fd.intBufTy)

  asy.ctx.def_addcarry(asy.module, asy.ctx.int1_t(), fd.wordTy)
  asy.ctx.def_subborrow(asy.module, asy.ctx.int1_t(), fd.wordTy)

proc wordTy*(fd: FieldDescriptor, value: SomeInteger) =
  constInt(fd.wordTy, value)

type
  ## XXX: For now we barely use any of these fields!
  CurveDescriptor* = object
    name*: string # of the curve
    fd*: FieldDescriptor # of the underlying field
    family*: CurveFamily
    modulus*: string # Modulus as Big-Endian uppercase hex, NOT prefixed with 0x
    modulusBitWidth*: uint32 # bits required for elements of `Fp`
    order*: string
    orderBitWidth*: uint32 # bits required for scalar elements `Fr`

    # type of the field Fr
    fieldScalarTy*: TypeRef
    numWordsScalar*: uint32 # num words required for it

    cofactor*: string
    eqForm*: CurveEquationForm

    coef_a*: int
    coef_b*: int

    nonResidueFp*: uint32
    nonResidueFp2*: uint32

    embeddingDegree*: uint32
    sexticTwist*: SexticTwist

    curveTyAff*: TypeRef # type of EC point in Affine coordinates
    curveTy*: TypeRef # type of EC point in Jacobian and Projective coordinates
                      # Their individual values differ, but both have (X,Y,Z) FF coords

proc configureCurve*(ctx: ContextRef,
      name: string,
      modBits: int, modulus: string,
      v, w: int,
      coefA, coefB: int,
      curveOrderBitWidth: int): CurveDescriptor =
  ## Configure a curve descriptor with:
  ## - v: vector length
  ## - w: base word size in bits
  ## - a `modulus` of bitsize `modBits`
  ##
  ## - Name is a prefix for example
  ##   `mycurve_fp_`
  result.name = "curve_" & name
  result.fd = configureField(ctx, name, modBits, modulus, v, w)
  # Array of 3 arrays, one for each field type
  result.curveTy = array_t(result.fd.fieldTy, 3)
  # Array of 2 arrays for affine coords
  result.curveTyAff = array_t(result.fd.fieldTy, 2)

  # and the type for elements of Fr
  result.numWordsScalar = uint32 wordsRequired(curveOrderBitWidth, w)
  result.fieldScalarTy = array_t(result.fd.wordTy, result.numWordsScalar)

  # Curve parameters
  result.coef_a = coef_a
  result.coef_b = coef_b # unused
  result.orderBitWidth = curveOrderBitWidth.uint32

proc definePrimitives*(asy: Assembler_LLVM, cd: CurveDescriptor) =
  asy.definePrimitives(cd.fd)

# ############################################################
#
#                    Aggregate Types
#
# ############################################################

# For array access we need to use:
#
#   builder.extractValue(array, index, name)
#   builder.insertValue(array, index, value, name)
#
# which is very verbose compared to array[index].
# So we wrap in syntactic sugar to improve readability, maintainability and auditability

type
  Array* = object
    builder*: BuilderRef
    buf*: ValueRef
    arrayTy*: TypeRef
    elemTy*: TypeRef
    int32_t: TypeRef

proc `=copy`*(m: var Array, x: Array) {.error: "Copying an Array is not allowed. " &
  "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}

proc `[]`*(a: Array, index: SomeInteger | ValueRef): ValueRef {.inline.}
proc `[]=`*(a: Array, index: SomeInteger | ValueRef, val: ValueRef) {.inline.}

proc asArray*(br: BuilderRef, arrayPtr: ValueRef, arrayTy: TypeRef): Array =
  Array(
    builder: br,
    buf: arrayPtr,
    arrayTy: arrayTy,
    elemTy: arrayTy.getElementType(),
    int32_t: arrayTy.getContext().int32_t()
  )

proc asArray*(asy: Assembler_LLVM, arrayPtr: ValueRef, arrayTy: TypeRef): Array =
  asy.br.asArray(arrayPtr, arrayTy)

proc makeArray*(asy: Assembler_LLVM, arrayTy: TypeRef): Array =
  Array(
    builder: asy.br,
    buf: asy.br.alloca(arrayTy),
    arrayTy: arrayTy,
    elemTy: arrayTy.getElementType(),
    int32_t: arrayTy.getContext().int32_t()
  )

proc makeArray*(asy: Assembler_LLVM, elemTy: TypeRef, len: uint32): Array =
  let arrayTy = array_t(elemTy, len)
  Array(
    builder: asy.br,
    buf: asy.br.alloca(arrayTy),
    arrayTy: arrayTy,
    elemTy: elemTy,
    int32_t: arrayTy.getContext().int32_t()
  )

proc getElementPtr*(a: Array, indices: varargs[int]): ValueRef =
  ## Helper to get an element pointer from a (nested) array.
  var idxs = newSeq[ValueRef](indices.len)
  for i, idx in indices:
    idxs[i] = constInt(a.int32_t, idx)
  result = a.builder.getElementPtr2_InBounds(a.arrayTy, a.buf, idxs)

proc getElementPtr*(a: Array, indices: varargs[ValueRef]): ValueRef =
  ## Helper to get an element pointer from a (nested) array using
  ## indices that are already `ValueRef`
  let idxs = @indices
  result = a.builder.getElementPtr2_InBounds(a.arrayTy, a.buf, idxs)

template asInt(x: SomeInteger | ValueRef): untyped =
  when typeof(x) is ValueRef: x
  else: x.int

proc getPtr*(a: Array, index: SomeInteger | ValueRef): ValueRef {.inline.}=
  ## First dereference the array pointer with 0, then access the `index`
  ## but do not load the element!
  when typeof(index) is SomeInteger:
    result = a.getElementPtr(0, index.int)
  else:
    result = a.getElementPtr(constInt(a.int32_t, 0), index)

proc `[]`*(a: Array, index: SomeInteger | ValueRef): ValueRef {.inline.}=
  # First dereference the array pointer with 0, then access the `index`
  let pelem = getPtr(a, index)
  a.builder.load2(a.elemTy, pelem)

proc `[]=`*(a: Array, index: SomeInteger | ValueRef, val: ValueRef) {.inline.}=
  when typeof(index) is SomeInteger:
    let pelem = a.getElementPtr(0, index.int)
  else:
    let pelem = a.getElementPtr(constInt(a.int32_t, 0), index)
  a.builder.store(val, pelem)

proc store*(asy: Assembler_LLVM, dst: Array, src: Array) {.inline.}=
  let v = asy.br.load2(src.arrayTy, src.buf)
  asy.br.store(v, dst.buf)

proc store*(asy: Assembler_LLVM, dst: Array, src: ValueRef) {.inline.}=
  ## Heterogeneous store of i256 into 4xuint64
  doAssert asy.byteOrder == kLittleEndian
  asy.br.store(src, dst.buf)

# Representation of a finite field point with some utilities

template genField(name, desc, field: untyped): untyped =
  type name* {.borrow: `.`.} = distinct Array

  proc `=copy`(m: var name, x: name) {.error: "Copying a " & $name & " is not allowed. " &
    "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}

  proc `[]`*(a: name, index: SomeInteger | ValueRef): ValueRef = distinctBase(a)[index]
  proc `[]=`*(a: name, index: SomeInteger | ValueRef, val: ValueRef) = distinctBase(a)[index] = val

  proc `as name`*(br: BuilderRef, a: ValueRef, fieldTy: TypeRef): name =
    result = name(br.asArray(a, fieldTy))
  proc `as name`*(asy: Assembler_LLVM, a: ValueRef, fieldTy: TypeRef): name =
    asy.br.`as name`(a, fieldTy)
  proc `as name`*(asy: Assembler_LLVM, d: desc, a: ValueRef): name =
    asy.br.`as name`(a, d.field)

  proc `new name`*(asy: Assembler_LLVM, d: desc): name =
    ## Use field descriptor for size etc?
    result = name(asy.makeArray(d.field))

  proc store*(dst: name, src: name) =
    ## Stores the `dst` in `src`. Both must correspond to the same field of course.
    assert dst.arrayTy.getArrayLength() == src.arrayTy.getArrayLength()
    for i in 0 ..< dst.arrayTy.getArrayLength:
      dst[i] = src[i]


genField(Field, FieldDescriptor, fieldTy)             # intended for elements of `Fp[Curve]`
genField(FieldScalar, CurveDescriptor, fieldScalarTy) # intended for elements of `Fr[Curve]`

# Representation of a finite field point with some utilities
type FieldArray* {.borrow: `.`.} = distinct Array

proc `=copy`(m: var FieldArray, x: FieldArray) {.error: "Copying an FieldArray is not allowed. " &
  "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}

proc `[]`*(a: FieldArray, index: SomeInteger | ValueRef): Field = asField(a.builder, distinctBase(a).getPtr(index), a.elemTy)
proc `[]=`*(a: FieldArray, index: SomeInteger | ValueRef, val: ValueRef) = distinctBase(a)[index] = val

proc asFieldArray*(asy: Assembler_LLVM, fd: FieldDescriptor, a: ValueRef, num: int): FieldArray =
  ## Interpret the given value `a` as an array of Field elements.
  let ty = array_t(fd.fieldTy, num)
  result = FieldArray(asy.br.asArray(a, ty))

type FieldScalarArray* {.borrow: `.`.} = distinct Array

proc `=copy`(m: var FieldScalarArray, x: FieldScalarArray) {.error: "Copying an FieldScalarArray is not allowed. " &
  "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}

proc `[]`*(a: FieldScalarArray, index: SomeInteger | ValueRef): FieldScalar = asFieldScalar(a.builder, distinctBase(a).getPtr(index), a.elemTy)
proc `[]=`*(a: FieldScalarArray, index: SomeInteger | ValueRef, val: ValueRef) = distinctBase(a)[index] = val

proc asFieldScalarArray*(asy: Assembler_LLVM, cd: CurveDescriptor, a: ValueRef, num: int): FieldScalarArray =
  ## Interpret the given value `a` as an array of Field elements.
  let ty = array_t(cd.fieldScalarTy, num)
  result = FieldScalarArray(asy.br.asArray(a, ty))


# Conversion to native LLVM int
# -------------------------------

proc asLlvmIntPtr*(asy: Assembler_LLVM, a: Array): ValueRef =
  doAssert asy.byteOrder == kLittleEndian, "Only little-endian machines are supported at the moment."
  let bits = asy.datalayout.getSizeInBits(a.arrayTy)
  let pInt = pointer_t(asy.ctx.int_t(uint32 bits))
  asy.br.bitcast(a.buf, pInt)

proc asLlvmIntPtr*(asy: Assembler_LLVM, v: ValueRef, ty: TypeRef): ValueRef =
  doAssert asy.byteOrder == kLittleEndian, "Only little-endian machines are supported at the moment."
  let pInt = pointer_t(ty)
  asy.br.bitcast(v, pInt)

# ############################################################
#
#                       Globals
#
# ############################################################

proc loadGlobal*(asy: Assembler_LLVM, name: string): ValueRef =
  let g = asy.module.getGlobal(cstring name)
  doAssert not result.isNil(), "The global '" & name & "' has not been declared in the module"
  let ty = result.getTypeOf()
  return asy.br.load2(ty, g, name = "g")

proc defineGlobalConstant*(
      asy: Assembler_LLVM,
      name, section: string,
      value: ValueRef,
      ty: TypeRef, alignment = -1): ValueRef =
  ## Declare a global constant
  ## name: The name of the constant
  ## section: globals are kept near each other in memory to improve locality
  ##          and avoid page-faults
  ## an alignment of -1 leaves it at default for the ISA.
  ## Otherwise configure the alignment in bytes.
  ##
  ## Return a pointer to the global
  let g = asy.module.addGlobal(ty, cstring name)
  g.setGlobal(value)
  if alignment > 0:
    g.setAlignment(cuint alignment)
  # We intentionally keep globals internal:
  # - for performance, this may avoids a translation table,
  #   they also can be inlined.
  # - for forward-compatibility, for example to expose the modulus
  #   a function can handle non-matching in internal representation
  #   for example if we want to have different endianness of words on bigEndian machine.
  # g.setLinkage(linkInternal)
  g.setImmutable()

  # Group related globals in the same section
  # This doesn't prevent globals from being optimized away
  # if they are fully inlined or unused.
  # This has the following benefits:
  # - They might all be loaded in memory if they share a cacheline
  # - If a section is unused, it can be garbage collected by the linker
  g.setSection(cstring("ctt." & section & ".constants"))
  return g

# ############################################################
#
#                  ISA configuration
#
# ############################################################

proc tagCudaKernel(asy: Assembler_LLVM, fn: ValueRef) =
  ## Tag a function as a Cuda Kernel, i.e. callable from host

  # We cannot get the full function type from its impl so we cannot do this check.
  # let returnTy = fn.getTypeOf().getReturnType()
  # doAssert returnTy.isVoid(), block:
  #   "Kernels must not return values but function returns " & $returnTy.getTypeKind()

  asy.module.addNamedMetadataOperand(
    "nvvm.annotations",
    asy.ctx.asValueRef(asy.ctx.metadataNode([
      fn.asMetadataRef(),
      asy.ctx.metadataNode("kernel"),
      asy.i32(1).asMetadataRef()
    ]))
  )

proc setPublic(asy: Assembler_LLVM, fn: ValueRef) =
  case asy.backend
  of bkAmdGpu:
    fn.setFnCallConv(AMDGPU_KERNEL)
  of bkNvidiaPtx:
    # asy.tagCudaKernel(fn)
    fn.setFnCallConv(PTX_Kernel)
  else: discard

# ############################################################
#
#        Function Definition and calling convention
#
# ############################################################

# Most architectures can pass up to 4 or 6 arguments directly into registers
# And we allow LLVM to use the best calling convention possible with "Fast".
#
# Recommendation:
#   https://llvm.org/docs/Frontend/PerformanceTips.html
#
#   Avoid creating values of aggregate types (i.e. structs and arrays).
#   In particular, avoid loading and storing them,
#   or manipulating them with insertvalue and extractvalue instructions.
#   Instead, only load and store individual fields of the aggregate.
#
#   There are some exceptions to this rule:
#   - It is fine to use values of aggregate type in global variable initializers.
#   - It is fine to return structs, if this is done to represent the return of multiple values in registers.
#   - It is fine to work with structs returned by LLVM intrinsics, such as the with.overflow family of intrinsics.
#   - It is fine to use aggregate types without creating values. For example, they are commonly used in getelementptr instructions or attributes like sret.
#
# Furthermore for aggregate types like struct we need to check the number of elements
# - https://groups.google.com/g/llvm-dev/c/CafdpEzOEp0
# - https://stackoverflow.com/questions/27386912/prevent-clang-from-expanding-arguments-that-are-aggregate-types
# - https://people.freebsd.org/~obrien/amd64-elf-abi.pdf
# Though that might be overkill for functions tagged 'internal' linkage and 'Fast' CC
#
# Hopefully the compiler will remove the unnecessary lod/store/register movement, especially when inlining.

proc wrapTypesForFnCall[N: static int](
        asy: AssemblerLLVM,
        paramTypes: array[N, TypeRef]
      ): tuple[wrapped, src: array[N, TypeRef]] =
  ## Wrap parameters that would need more than 3x registers
  ## into a pointer.
  ## There are 2 such cases:
  ## - An array/struct of more than 3 elements, for example 4x uint32
  ## - A type larger than 3x the pointer size, for example 4x uint64
  ## Vectors are passed by special SIMD registers
  ##
  ## Due to LLVM opaque pointers, we return the wrapped and src types

  for i in 0 ..< paramTypes.len:
    let ty = paramTypes[i]
    let tk = ty.getTypeKind()
    if tk in {tkVector, tkScalableVector}:
      ## There are special SIMD registers for vectors
      result.wrapped[i] = paramTypes[i]
      result.src[i]     = paramTypes[i]
    elif asy.datalayout.getAbiSize(ty).int32 > 3*asy.psize:
      result.wrapped[i] = pointer_t(paramTypes[i])
      result.src[i]     = paramTypes[i]
    else:
      case tk
      of tkArray:
        if ty.getArrayLength() >= 3:
          result.wrapped[i] = pointer_t(paramTypes[i])
          result.src[i]     = paramTypes[i]
        else:
          result.wrapped[i] = paramTypes[i]
          result.src[i]     = paramTypes[i]
      of tkStruct:
        if ty.getNumElements() >= 3:
          result.wrapped[i] = pointer_t(paramTypes[i])
          result.src[i]     = paramTypes[i]
        else:
          result.wrapped[i] = paramTypes[i]
          result.src[i]     = paramTypes[i]
      else:
        result.wrapped[i] = paramTypes[i]
        result.src[i]     = paramTypes[i]

proc addAttributes(asy: Assembler_LLVM, fn: ValueRef, attrs: set[AttrKind]) =
  for attr in attrs:
    fn.addAttribute(kAttrFnIndex, asy.attrs[attr])

  fn.addAttribute(kAttrFnIndex, asy.attrs[kHot])

template llvmFnDef[N: static int](
          asy: Assembler_LLVM,
          name, sectionName: string,
          returnType: TypeRef,
          paramTypes: array[N, TypeRef],
          internal: bool,
          attrs: set[AttrKind],
          body: untyped) =
  ## This setups common prologue to implement a function in LLVM
  ## Function parameters are available with the `llvmParams` magic variable
  let paramsTys = asy.wrapTypesForFnCall(paramTypes)

  var fn {.inject.} = asy.module.getFunction(cstring name)
  if fn.pointer.isNil():
    var savedLoc = asy.br.getInsertBlock()

    let fnTy = function_t(returnType, paramsTys.wrapped)
    fn = asy.module.addFunction(cstring name, fnTy)

    asy.fns[name] = (fnTy, fn, internal)

    let blck = asy.ctx.appendBasicBlock(fn)
    asy.br.positionAtEnd(blck)

    if savedLoc.pointer.isNil():
      # We're installing the first function
      # of the call tree, return to its basic block
      savedLoc = blck

    let llvmParams {.inject.} = unpackParams(asy.br, paramsTys)
    template tagParameter(idx: int, attr: string) {.inject, used.} =
      let a = asy.ctx.createAttr(attr)
      fn.addAttribute(cint idx, a)
    body

    if internal:
      fn.setFnCallConv(Fast)
      fn.setLinkage(linkInternal)
    else:
      asy.setPublic(fn)
    fn.setSection(cstring sectionName)
    asy.addAttributes(fn, attrs)

    asy.br.positionAtEnd(savedLoc)

template llvmInternalFnDef*[N: static int](
          asy: Assembler_LLVM,
          name, sectionName: string,
          returnType: TypeRef,
          paramTypes: array[N, TypeRef],
          attrs: set[AttrKind] = {},
          body: untyped) =
  llvmFnDef(asy, name, sectionName, returnType, paramTypes, internal = true, attrs, body)

template llvmPublicFnDef*[N: static int](
          asy: Assembler_LLVM,
          name, sectionName: string,
          returnType: TypeRef,
          paramTypes: array[N, TypeRef],
          body: untyped) =
  llvmFnDef(asy, name, sectionName, returnType, paramTypes, internal = false, {}, body)

proc callFn*(
      asy: Assembler_LLVM,
      name: string,
      params: openArray[ValueRef]): ValueRef {.discardable.} =

  if asy.fns[name].ty.getReturnType().getTypeKind() == tkVoid:
    result = asy.br.call2(asy.fns[name].ty, asy.fns[name].impl, params)
  else:
    result = asy.br.call2(asy.fns[name].ty, asy.fns[name].impl, params, cstring(name))

  if asy.fns[name].internal:
    result.setInstrCallConv(Fast)

# ############################################################
#
#                      Forward to Builder
#
# ############################################################

# {.experimental: "dotOperators".} dos not seem to work within templates?macros

template load2*(asy: Assembler_LLVM, ty: TypeRef, `ptr`: ValueRef, name: cstring = ""): ValueRef =
  asy.br.load2(ty, `ptr`, name)

template store*(asy: Assembler_LLVM, dst, src: ValueRef, name: cstring = "") =
  if not dst.getTypeOf.isPointerType():
    raise newException(ValueError, "The destination argument to `store` is not a pointer type.")
  if src.getTypeOf.isPointerType():
    raise newException(ValueError, "The source argument to `store` is a pointer type. " &
      "You must `load2()` it before the store. Or use the `MutableValue` type, in which case " &
      "we can load it automatically for you. If you really wish to store the pointer " &
      "to the destination, use `storePtr` instead.")
  asy.br.store(src, dst)

template storePtr*(asy: Assembler_LLVM, dst, src: ValueRef, name: cstring = "") =
  if not dst.getTypeOf.isPointerType():
    raise newException(ValueError, "The destination argument to `storePtr` is not a pointer type.")
  if not src.getTypeOf.isPointerType():
    raise newException(ValueError, "The source argument to `storePtr` is not a pointer type. " &
      "You likely want to call `store` instead.")
  asy.br.store(src, dst)

## No-op to support calling it on `MutableValue | ConstantValue | ValueRef`
proc getValueRef*(x: ValueRef): ValueRef = x

proc nimToLlvmType[T](asy: Assembler_LLVM, _: typedesc[T]): TypeRef =
  when T is SomeInteger:
    result = asy.ctx.int_t(sizeof(T) * 8)
  else:
    {.error: "Unsupported so far: " & $T.}

type
  ## A value constructed using `constX`
  ConstantValue* = object
    br: BuilderRef
    val: ValueRef
    typ: TypeRef

proc `=copy`(m: var ConstantValue, x: ConstantValue) {.error: "Copying a constant value is not allowed. " &
  "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}


proc initConstVal*(br: BuilderRef, val: ValueRef): ConstantValue =
  ## Construct a constant value from a given LLVM value.
  result = ConstantValue(br: br, val: val, typ: getTypeOf(val))

proc initConstVal*(asy: Assembler_LLVM, val: ValueRef): ConstantValue =
  asy.br.initConstVal(val)

proc initConstVal*[T: SomeInteger](asy: Assembler_LLVM, x: T): ConstantValue =
  let t = asy.nimToLlvmType(T)
  result = initConstVal(asy.br, constInt(t, x))

proc initConstVal*(br: BuilderRef, val: int{lit}, typ: TypeRef): ConstantValue =
  ## Construct an LLVM value from an integer literal of the targe type `typ`.
  result = br.initConstVal(constInt(typ, val))

proc initConstVal*(asy: Assembler_LLVM, val: int{lit}, typ: TypeRef): ConstantValue =
  ## Construct an LLVM value from an integer literal of the targe type `typ`.
  result = asy.br.initConstVal(constInt(typ, val))

template store*(asy: Assembler_LLVM, dst: ValueRef, src: ConstantValue, name: cstring = "") =
  if not dst.getTypeOf.isPointerType():
    raise newException(ValueError, "The destination argument to `store` is not a pointer type.")
  asy.br.store(src.val, dst)

proc getValueRef*(v: ConstantValue): ValueRef = v.val

proc asLlvmConstInt[T: SomeInteger | ValueRef](x: T, dtype: TypeRef): ValueRef =
  ## Given either a value that is already an LLVM value ref or
  ## a Nim value, return a `constInt`
  when T is ValueRef:
    ## XXX: check type is int
    result = x
  else:
    result = constInt(dtype, x)

type
  ## A value constructed using `constX`
  MutableValue* = object
    br: BuilderRef
    buf: ValueRef
    typ: TypeRef ## type of the *underlying* type, not the pointer

proc `=copy`(m: var MutableValue, x: MutableValue) {.error: "Copying a mutable value is not allowed. " &
  "You likely want to copy the LLVM value. Use `dst.store(src)` instead.".}

proc initMutVal*(br: BuilderRef, x: ValueRef): MutableValue =
  ## Initializes a mutable value from a given LLVM value. Raises if the given
  ## value is of pointer type.
  if x.getTypeOf().isPointerType():
    raise newException(ValueError, "Initializing a mutable value from a pointer type is not supported.")
  let typ = x.getTypeOf()
  result = MutableValue(
    br: br,
    buf: br.alloca(typ),
    typ: typ
  )
  br.store(x, result.buf) # LLVM store is (source, dest)

proc initMutVal*(br: BuilderRef, x: ConstantValue): MutableValue =
  br.initMutVal(x.val)

proc initMutVal*(asy: Assembler_LLVM, x: ConstantValue): MutableValue =
  asy.br.initMutVal(x)

proc initMutVal*(br: BuilderRef, typ: TypeRef): MutableValue =
  if typ.getTypeKind != tkInteger:
    raise newException(ValueError, "Initializing a mutable value from a non integer type without value is not supported. " &
      "Type is: " & $typ)
  br.initMutVal(constInt(typ, 0))

proc initMutVal*(asy: Assembler_LLVM, typ: TypeRef): MutableValue =
  asy.br.initMutVal(typ)

proc initMutVal*[T](br: BuilderRef): MutableValue =
  br.initMutVal(default(T)) # initialize with default value for correct type info

proc initMutVal*[T](asy: Assembler_LLVM): MutableValue =
  asy.br.initMutVal[:T]()

proc load*(m: MutableValue): ConstantValue =
  result = m.br.initConstVal(m.br.load2(m.typ, m.buf))

proc store*(m: MutableValue, val: ValueRef) =
  if val.getTypeOf.isPointerType():
    raise newException(ValueError, "The source argument to `store` is a pointer type. " &
      "You must `load2()` it before the store. Or use the `MutableValue` type, in which case " &
      "we can load it automatically for you. If you really wish to store the pointer " &
      "to the destination, use `storePtr` instead.")
  m.br.store(val, m.buf) # LLVM store uses (target, source)

proc store*(asy: Assembler_LLVM, dst: ValueRef, m: MutableValue) =
  asy.store(dst, m.load().val) # delegate to regular template defined further above

proc store*(asy: Assembler_LLVM, dst: MutableValue, x: ValueRef) =
  asy.store(dst.buf, x) # delegate to regular template defined further above

proc storePtr*(m: MutableValue, val: ValueRef) =
  if not val.getTypeOf.isPointerType():
    raise newException(ValueError, "The source argument to `store` is not a pointer type. " &
      "You likely want to call `store` instead.")
  m.br.store(val, m.buf) # LLVM store uses (target, source)

proc store*(m: MutableValue, val: ConstantValue) =
  m.store(val.val)

proc getValueRef*(m: MutableValue): ValueRef = m.load().val

## Convenience templates that make writing code more succinct

import std / macros
template llvmForImpl(asy, iter, suffix: untyped, start, stop, isCountup: typed, body: untyped): untyped =
  ## `asy: Assembler_LLVM`, `fn` need to be in scope!
  ## Start and stop need to be Nim values (CT or RT)
  block:
    let loopEntry = asy.ctx.appendBasicBlock(fn, "loop.entry" & suffix)
    let loopBody  = asy.ctx.appendBasicBlock(fn, "loop.body" & suffix)
    let loopExit  = asy.ctx.appendBasicBlock(fn, "loop.exit" & suffix)

    # Branch to loop entry
    asy.br.br(loopEntry)

    # Position at loop entry
    asy.br.positionAtEnd(loopEntry)

    # stopping value & increment / decrement per iteration
    let cStart = asLlvmConstInt(start, asy.ctx.int32_t())
    let cStop = asLlvmConstInt(stop, asy.ctx.int32_t())
    let change = if isCountup: 1 else: -1
    let cChange = constInt(asy.ctx.int32_t(), change)

    # Loop entry condition
    let cmp = if isCountup: kSLE else: kSGE
    let condition = asy.br.icmp(cmp, cStart, cStop)
    asy.br.condBr(condition, loopBody, loopExit)

    # Loop body
    asy.br.positionAtEnd(loopBody)
    let phi = asy.br.phi(getTypeOf cStart)
    phi.addIncoming(cStart, loopEntry)

    # Inject the phi node as the iterator
    let iter {.inject.} = phi
    # The loop body
    body

    # Increment / decrement for next iteration
    let nextIter = asy.br.add(phi, cChange) # will subtract for countdown

    ## After the loop body the builder may not be in the `loopBody` anymore.
    ## Consider:
    ##
    ## llvmFor i, 0, 10, true:    # Outer loop
    ##   # Block: outer.body
    ##   llvmFor j, 0, 5, true:    # Inner loop
    ##     # Block: inner.body
    ##     # ... instructions ...
    ##   # After inner loop - which block are we in?
    ##
    ##   # Need to add PHI incoming edge for outer loop
    ##   phi.addIncoming(nextIter, ????)  # <-- `getInsertBlock` yields the after block of the inner loop
    ##   # `loopBody` would be incorrect as a result of the inner loop.
    phi.addIncoming(nextIter, asy.br.getInsertBlock())

    # Check if we should continue looping
    let continueLoop = asy.br.icmp(cmp, nextIter, cStop)
    asy.br.condBr(continueLoop, loopBody, loopExit)

    # Loop exit
    asy.br.positionAtEnd(loopExit)

macro llvmFor*(asy: untyped, iter: untyped, start, stop, isCountup: typed, body: untyped): untyped =
  let label = $genSym(nskLabel, "loop")
  result = quote do:
    llvmForImpl(`asy`, `iter`, `label`, `start`, `stop`, `isCountup`, `body`)

template llvmFor*(asy: untyped, iter: untyped, start, stop: typed, body: untyped): untyped {.dirty.} =
  ## Start and stop must be Nim values
  block:
    let isCountup = start < stop
    asy.llvmFor iter, start, stop, isCountup:
      body

template llvmForCountup*(asy: untyped, iter: untyped, start, stop: typed, body: untyped): untyped  {.dirty.} =
  ## Start and stop can either be Nim or LLVM values
  block:
    asy.llvmFor iter, start, stop, true:
      body

template llvmForCountdown*(asy: untyped, iter: untyped, start, stop: typed, body: untyped): untyped  {.dirty.} =
  ## Start and stop can either be Nim or LLVM values
  block:
    asy.llvmFor iter, start, stop, false:
      body

## Convenience utilities for `ValueRef` (representing numbers) for LLVM
template declNumberOps*(asy: Assembler_LLVM, fd: FieldDescriptor): untyped =
  ## Declares templates similar to the field and EC ops templates
  ## for `ValueRef`, `MutableValue` and `ConstantValue` so that one
  ## can effectively write regular arithmetic / boolean logic code
  ## with LLVM values to produce the correct code.
  template genLhsRhsVariants(name, fn: untyped): untyped =
    ## Generates variants for mix of Nim integer + ValueRef and
    ## pure ValueRef
    type T = int | uint32 | uint64
    type U = ValueRef | MutableValue | ConstantValue
    type X = MutableValue | ConstantValue

    let I = fd.wordTy

    template name(lhs, rhs: ValueRef): untyped =
      if $getTypeOf(lhs) != $getTypeOf(rhs):
        raise newException(ValueError, "Inputs do not have matching types. LHS = " & $getTypeOf(lhs) & ", RHS = " & $getTypeOf(rhs))
      elif getTypeOf(lhs).isPointerType():
        raise newException(ValueError, "Inputs must not be pointer types.")
      asy.br.fn(lhs, rhs)
    template name(lhs: SomeInteger, rhs: U): untyped =
      block:
        let lhsV = constInt(I, lhs)
        asy.br.fn(lhsV, getValueRef rhs)
    template name(lhs: U, rhs: SomeInteger): untyped =
      block:
        let rhsV = constInt(I, rhs)
        asy.br.fn(getValueRef lhs, rhsV)
    template name[T: X; U: X](lhs: T; rhs: U): untyped =
      asy.br.fn(getValueRef lhs, getValueRef rhs)

  template genLhsRhsBooleanVariants(name, pred: untyped): untyped =
    ## Generates variants for mix of Nim integer + ValueRef and
    ## pure ValueRef for boolean operations
    type T = int | uint32 | uint64
    type U = ValueRef | MutableValue | ConstantValue
    type X = MutableValue | ConstantValue

    let I = fd.wordTy

    template name(lhs, rhs: ValueRef): untyped =
      if $getTypeOf(lhs) != $getTypeOf(rhs):
        raise newException(ValueError, "Inputs do not have matching types. LHS = " & $getTypeOf(lhs) & ", RHS = " & $getTypeOf(rhs))
      elif getTypeOf(lhs).isPointerType():
        raise newException(ValueError, "Inputs must not be pointer types.")
      asy.br.icmp(pred, lhs, rhs)
    template name(lhs: T; rhs: U): untyped =
      block:
        let lhsV = constInt(I, lhs)
        name(lhsV, getValueRef rhs)
    template name(lhs: U; rhs: T): untyped =
      block:
        let rhsV = constInt(I, rhs)
        name(getValueRef lhs, rhsV)
    template name[T: X; U: X](lhs: T; rhs: U): untyped =
      name(getValueRef lhs, getValueRef rhs)

  # standard binary operations
  genLhsRhsVariants(`shl`, lshl)
  genLhsRhsVariants(`shr`, lshr)
  genLhsRhsVariants(`and`, `and`)
  genLhsRhsVariants(`or`, `or`)
  genLhsRhsVariants(`+`, add)
  genLhsRhsVariants(`-`, sub)
  genLhsRhsVariants(`*`, mul)

  # boolean based on `icmp`
  genLhsRhsBooleanVariants(`<`, kSLT)
  genLhsRhsBooleanVariants(`<=`, kSLE)
  genLhsRhsBooleanVariants(`==`, kEQ)
  ## XXX: The following cause overload resolution errors for
  ## bog standard types, i.e. `>` of `uint32` or `!=` for `string`.
  ## I think this is because `!=`, `>` and `>=` are implemented as
  ## untyped templates in system.nim.
  ## Slightly problematic, we need to add `not` for LLVM to achieve
  ## the correct behavior.
  #genLhsRhsBooleanVariants(`>`, kSGT)
  #genLhsRhsBooleanVariants(`>=`, kSGE)
  #genLhsRhsBooleanVariants(`!=`, kNE)

proc collectElifBranches(n: NimNode): tuple[elifs: seq[NimNode], els: NimNode] =
  ## The `else` branch is an optional second argument, `els`
  doAssert n.kind == nnkIfStmt
  result.els = newEmptyNode() # set to empty as default
  for el in n:
    case el.kind
    of nnkElifBranch: result.elifs.add el
    of nnkElse: result.els = el
    else: raiseAssert "Invalid branch: " & $el.kind

macro llvmIf*(asy, body: untyped): untyped =
  ## Rewrites the given body, which *must* contain an if statement
  ## with (possibly) multiple branches) into conditional branches
  ## on LLVM. We jump from the current block of `asy` into the
  ## conditional branches and provide a block at the end, which we
  ## will reach from every if branch.
  ##
  ## NOTE: This can only be used inside of an `llvmInternalFnDef` template,
  ## because it needs access to the current function, `fn` identifier.
  ##
  ## BE CAREFUL: For the moment this macro does not handle using values
  ## assigned in its body after the if statements. This would require
  ## creating a φ-node for the value, which we currently do not do.
  ## Mainly, because this requires a more complicated traversal of the
  ## macro body to detect such a requirement. Instead we might add
  ## an alternative `llvmIfUse` or similar in the future, where exactly
  ## one assignment is allowed.
  ##
  ##   IfStmt
  ##     ElifBranch
  ##       Ident "true"
  ##       StmtList
  ##         Command
  ##           Ident "echo"
  ##           StrLit "x"
  ##     Else
  ##       StmtList
  ##         Command
  ##           Ident "echo"
  ##           StrLit "y"
  ##
  doAssert body.kind in {nnkIfStmt, nnkStmtList}, "Input *must* be an if statement, but is: " & $body.kind
  var body = body
  if body.kind == nnkStmtList:
    doAssert body.len == 1 and body[0].kind == nnkIfStmt, "If a nnkStmtList, must only contain an nnkIfStmt, but: " & $body.treerepr
    body = body[0]

  # 1. collect all elif branches (and possible else)
  let (elifs, els) = collectElifBranches(body)
  let hasElse = els.kind != nnkEmpty

  # For each `elif` (including the first `if`) we need 2 blocks:
  # - elif condition
  # - if true body
  # If `els` is set, need an additional:
  # - else body
  # Finally, need an
  # - after if/else body
  result = newStmtList()

  # 2. generate all required blocks
  var elifBranches = newSeq[tuple[cond, body: NimNode]]() # contains the *identifiers* for the blocks
  for i, el in elifs:
    # 2.1 create the identifiers
    let condId = genSym(nskLet, "elifCond")
    let bodyId = genSym(nskLet, "elifBody")
    # 2.2 generate let stmts to append the blocks to LLVM context
    let idx = $i
    result.add quote do:
      let `condId` = `asy`.ctx.appendBasicBlock(fn, "elif.condition." & `idx`)
      let `bodyId` = `asy`.ctx.appendBasicBlock(fn, "elif.body." & `idx`)
    # 2.3 store
    elifBranches.add (cond: condId, body: bodyId)
  # 2.4 create `else` block if needed
  var elseId: NimNode
  if hasElse:
    elseId = genSym(nskLet, "elseBody")
    result.add quote do:
      let `elseId` = `asy`.ctx.appendBasicBlock(fn, "else.body")
  # 2.5 create 'after if/else' block
  let afterId = genSym(nskLet, "afterBody")
  result.add quote do:
    let `afterId` = `asy`.ctx.appendBasicBlock(fn, "after.body")

  # 3. jump to the first if condition
  let firstCond = elifBranches[0].cond
  result.add quote do:
    `asy`.br.br(`firstCond`)

  # 4. fill all the blocks
  for i, el in elifs:
    # 4.1 take condition of `elif`
    # ElifBranch
    #   Ident "true"       <- `el[0]`
    #   StmtList           <- `el[1]`
    #     Command
    #       Ident "echo"
    #       StrLit "x"
    let cond = el[0]
    # 4.2 set our builder to this block
    let condId = elifBranches[i].cond
    let condVal = genSym(nskLet, "condVal")
    result.add quote do:
      `asy`.br.positionAtEnd(`condId`)
    # 4.3 fill the block with the condition
    result.add quote do:
      let `condVal` = `cond`

    #result.add nnkBlockStmt.newTree(ident("Block_" & $condId), cond)
    # 4.4 determine the `else` block to jump to (else, after or next elif)
    let ifFalseNext =
      if i < elifBranches.high: # has another elif
        elifBranches[i+1].cond
      elif hasElse:             # last, jump to existing else
        elseId
      else:                     # neither, jump after if/else
        afterId

    # 4.5 conditionally branch based on condition the block with a conditional branch
    let bodyId = elifBranches[i].body
    result.add quote do:
      `asy`.br.condBr(`condVal`, `bodyId`, `ifFalseNext`)

    # 4.6 set builder to if body
    let blkBody = el[1]
    result.add quote do:
      `asy`.br.positionAtEnd(`bodyId`)
    # 4.7 fill the block with the body
    result.add nnkBlockStmt.newTree(ident("Block_" & $bodyId), blkBody)
    # 4.8 branch to after if
    result.add quote do:
      `asy`.br.br(`afterId`)

  # 5. handle the `else` branch if any
  if hasElse:
    # 5.1 position at else block
    result.add quote do:
      `asy`.br.positionAtEnd(`elseId`)
    # 5.2 add the else body to this block
    result.add els[0]
    # 5.3 jump to after block
    result.add quote do:
      `asy`.br.br(`afterId`)

  # 6. position builder at after block
  result.add quote do:
    `asy`.br.positionAtEnd(`afterId`)

proc to*(asy: Assembler_LLVM, x: ValueRef, dtype: TypeRef, signed = false): ValueRef =
  ## Converts the given integer type of `x` to the target type `T`.
  ## The numbers are treated as signed integers if `signed` is true, else
  ## as unsigned.
  let outsize = getIntTypeWidth(dtype)
  let tk = x.getTypeOf().getTypeKind()
  if tk != tkInteger:
    raise newException(ValueError, "The argument is not an integer type, but: " & $getTypeOf(x))
  let inSize = getTypeOf(x).getIntTypeWidth()
  if inSize == outsize:
    result = x
  elif inSize < outsize:
    # extend,
    if signed:
      result = asy.br.sext(x, dtype, "to.i" & $outSize)
    else:
      result = asy.br.zext(x, dtype, "to.u" & $outSize)
  else: # trunacte
    result = asy.br.trunc(x, dtype, "trunc.to.i" & $outSize)

proc to*[T](asy: Assembler_LLVM, x: ValueRef, dtype: typedesc[T], signed = false): ValueRef =
  let outTyp = asy.nimToLlvmType(T)
  result = asy.to(x, outTyp, signed)
