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
    modulusBitWidth*: uint32
    order*: string
    orderBitWidth*: uint32

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
      coefA, coefB: int): CurveDescriptor =
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

  # Curve parameters
  result.coef_a = coef_a
  result.coef_b = coef_b # unused

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

proc `[]`*(a: Array, index: SomeInteger): ValueRef {.inline.}
proc `[]=`*(a: Array, index: SomeInteger, val: ValueRef) {.inline.}

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

proc `[]`*(a: Array, index: SomeInteger): ValueRef {.inline.}=
  # First dereference the array pointer with 0, then access the `index`
  let pelem = a.getElementPtr(0, index.int)
  a.builder.load2(a.elemTy, pelem)

proc `[]=`*(a: Array, index: SomeInteger, val: ValueRef) {.inline.}=
  let pelem = a.getElementPtr(0, index.int)
  a.builder.store(val, pelem)

proc store*(asy: Assembler_LLVM, dst: Array, src: Array) {.inline.}=
  let v = asy.br.load2(src.arrayTy, src.buf)
  asy.br.store(v, dst.buf)

proc store*(asy: Assembler_LLVM, dst: Array, src: ValueRef) {.inline.}=
  ## Heterogeneous store of i256 into 4xuint64
  doAssert asy.byteOrder == kLittleEndian
  asy.br.store(src, dst.buf)

# Representation of a finite field point with some utilities
type Field* {.borrow: `.`.} = distinct Array

proc `[]`*(a: Field, index: SomeInteger): ValueRef = distinctBase(a)[index]
proc `[]=`*(a: Field, index: SomeInteger, val: ValueRef) = distinctBase(a)[index] = val

proc asField*(br: BuilderRef, a: ValueRef, fieldTy: TypeRef): Field =
  result = Field(br.asArray(a, fieldTy))
proc asField*(asy: Assembler_LLVM, a: ValueRef, fieldTy: TypeRef): Field =
  asy.br.asField(a, fieldTy)
proc asField*(asy: Assembler_LLVM, fd: FieldDescriptor, a: ValueRef): Field =
  asy.br.asField(a, fd.fieldTy)

proc newField*(asy: Assembler_LLVM, fd: FieldDescriptor): Field =
  ## Use field descriptor for size etc?
  result = Field(asy.makeArray(fd.fieldTy))

proc store*(dst: Field, src: Field) =
  ## Stores the `dst` in `src`. Both must correspond to the same field of course.
  assert dst.arrayTy.getArrayLength() == src.arrayTy.getArrayLength()
  for i in 0 ..< dst.arrayTy.getArrayLength:
    dst[i] = src[i]

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
  asy.br.store(src, dst)
