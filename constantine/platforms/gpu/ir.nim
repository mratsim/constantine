# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../math/config/curves,
  ../../math_gpu/metadata,
  ../primitives,
  ./llvm,
  std/hashes

# ############################################################
#
#                      Assembler
#
# ############################################################

type
  Assembler_LLVM* = ref object
    # LLVM
    ctx*: ContextRef
    module*: ModuleRef
    builder*: BuilderRef
    i1_t*, i32_t*, i64_t*, void_t*: TypeRef
    backend*: Backend

  Backend* = enum
    bkNvidiaPTX

proc finalizeAssemblerLLVM(asy: Assembler_LLVM) =
  if not asy.isNil:
    asy.builder.dispose()
    asy.module.dispose()
    asy.ctx.dispose()

proc new*(T: type Assembler_LLVM, backend: Backend, moduleName: cstring): Assembler_LLVM =
  new result, finalizeAssemblerLLVM
  result.ctx = createContext()
  result.module = result.ctx.createModule(moduleName)

  case backend
  of bkNvidiaPTX:
    result.module.setTarget("nvptx64-nvidia-cuda")
    # Datalayout for NVVM IR 1.8 (CUDA 11.6)
    result.module.setDataLayout("e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-i128:128:128-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64")

  result.builder = result.ctx.createBuilder()
  result.i1_t = result.ctx.int1_t()
  result.i32_t = result.ctx.int32_t()
  result.i64_t = result.ctx.int32_t()
  result.void_t = result.ctx.void_t()
  result.backend = backend


# ############################################################
#
#               Intermediate Representation
#
# ############################################################

type
  WordSize* = enum
    size32
    size64
  
  Field* = enum
    fp
    fr

  FieldTy* = tuple[wordTy, ty: TypeRef, len: uint32]
  
  FieldConst*[T: DynWord] = object
    fieldTy: FieldTy
    modulus*: BigNum[T]
    m0ninv*: T
    spareBits*: uint8

  CurveMetadata* = object
    curve*: Curve
    prefix*: string
    case wordSize*: WordSize
    of size32:
      fp32*: FieldConst[uint32]
      fr32*: FieldConst[uint32]
    of size64:
      fp64*: FieldConst[uint64]
      fr64*: FieldConst[uint64]    

  Opcode* = enum
    opFpAdd = "fp_add"
    opFrAdd = "fr_add"

proc setFieldConst(fc: var FieldConst, ctx: ContextRef, wordSize: WordSize, modBits: uint32, modulus: string) =
  let wordTy = case wordSize
    of size32: ctx.int32_t()
    of size64: ctx.int64_t()
  
  let wordBitwidth = case wordSize
    of size32: 32'u32
    of size64: 64'u32

  let numWords = wordsRequiredForBits(modBits, wordBitwidth)

  fc.fieldTy.wordTy = wordTy
  fc.fieldTy.ty = array_t(wordTy, numWords)
  fc.fieldTy.len = numWords
  fc.modulus.fromHex(modBits, modulus)
  
  fc.m0ninv = fc.modulus.negInvModWord()
  fc.spareBits = uint8(numWords*wordBitwidth - modBits)

proc init*(
       C: type CurveMetadata, ctx: ContextRef,
       prefix: string, wordSize: WordSize,
       fpBits: uint32, fpMod: string,
       frBits: uint32, frMod: string): CurveMetadata =
    
  result = C(prefix: prefix, wordSize: wordSize)

  case wordSize
  of size32:
    result.fp32.setFieldConst(ctx, wordSize, fpBits, fpMod)
    result.fr32.setFieldConst(ctx, wordSize, frBits, frMod)
  of size64:
    result.fp64.setFieldConst(ctx, wordSize, fpBits, fpMod)
    result.fr64.setFieldConst(ctx, wordSize, frBits, frMod)

proc hash*(curveOp: tuple[cm: CurveMetadata, op: Opcode]): Hash {.inline.} =
  result = hash(curveOp.cm.curve) !& int(hash(curveOp.op))
  result = !$result

proc genSymbol*(cm: CurveMetadata, opcode: Opcode): string {.inline.} =
  cm.prefix & 
    (if cm.wordSize == size32: "32b_" else: "64b_") &
    $opcode

func getFieldType*(cm: CurveMetadata, field: Field): FieldTy {.inline.} =
  if cm.wordSize == size32:
    if field == fp:
      return cm.fp32.fieldTy
    else:
      return cm.fr32.fieldTy
  else:
    if field == fp:
      return cm.fp64.fieldTy
    else:
      return cm.fr64.fieldTy

func getModulus*(cm: CurveMetadata, field: Field): auto {.inline.} =
  # TODO: replace static typing, the returned type is incorrect for 64-bit
  if cm.wordSize == size32:
    if field == fp:
      return cast[ptr UncheckedArray[uint32]](cm.fp32.modulus.limbs[0].unsafeAddr)
    else:
      return cast[ptr UncheckedArray[uint32]](cm.fr32.modulus.limbs[0].unsafeAddr)
  else:
    if field == fp:
      return cast[ptr UncheckedArray[uint32]](cm.fp64.modulus.limbs[0].unsafeAddr)
    else:
      return cast[ptr UncheckedArray[uint32]](cm.fr64.modulus.limbs[0].unsafeAddr)

func getSpareBits*(cm: CurveMetadata, field: Field): uint8 {.inline.} =
  if cm.wordSize == size32:
    if field == fp:
      return cm.fp32.sparebits
    else:
      return cm.fr32.sparebits
  else:
    if field == fp:
      return cm.fp64.sparebits
    else:
      return cm.fr64.sparebits

# ############################################################
#
#                    Syntax Sugar
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
    builder: BuilderRef
    p: ValueRef
    arrayTy: TypeRef
    elemTy: TypeRef
    int32_t: TypeRef

proc asArray*(builder: BuilderRef, arrayPtr: ValueRef, arrayTy: TypeRef): Array =
  Array(
    builder: builder,
    p: arrayPtr,
    arrayTy: arrayTy,
    elemTy: arrayTy.getElementType(),
    int32_t: arrayTy.getContext().int32_t()
  )

proc makeArray*(builder: BuilderRef, arrayTy: TypeRef): Array =
  Array(
    builder: builder,
    p: builder.alloca(arrayTy),
    arrayTy: arrayTy,
    elemTy: arrayTy.getElementType(),
    int32_t: arrayTy.getContext().int32_t()
  )

proc makeArray*(builder: BuilderRef, elemTy: TypeRef, len: uint32): Array =
  let arrayTy = array_t(elemTy, len)
  Array(
    builder: builder,
    p: builder.alloca(arrayTy),
    arrayTy: arrayTy,
    elemTy: elemTy,
    int32_t: arrayTy.getContext().int32_t()
  )

proc `[]`*(a: Array, index: uint32): ValueRef {.inline.}=
  # First dereference the array pointer with 0, then access the `index`
  let pelem = a.builder.getElementPtr2_InBounds(a.arrayTy, a.p, [constInt(a.int32_t, 0), constInt(a.int32_t, index)])
  a.builder.load2(a.elemTy, pelem)

proc `[]=`*(a: Array, index: uint32, val: ValueRef) {.inline.}=
  let pelem = a.builder.getElementPtr2_InBounds(a.arrayTy, a.p, [constInt(a.int32_t, 0), constInt(a.int32_t, index)])
  a.builder.store(val, pelem)

proc store*(builder: BuilderRef, dst: Array, src: Array) {.inline.}=
  let v = builder.load2(src.arrayTy, src.p)
  builder.store(v, dst.p)