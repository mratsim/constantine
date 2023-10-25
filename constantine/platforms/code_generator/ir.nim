# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../math/config/[curves, precompute],
  ../../math/io/io_bigints,
  ../primitives, ../bithacks,
  ../../serialization/[endians, codecs, io_limbs],
  ./llvm

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
    i1_t*, i32_t*, i64_t*, i128_t*, void_t*: TypeRef
    backend*: Backend

  Backend* = enum
    bkNvidiaPTX

  FnDef* = tuple[fnTy: TypeRef, fnImpl: ValueRef]
    # calling getTypeOf on a ValueRef function
    # loses type information like return value type or arity

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
  result.i64_t = result.ctx.int64_t()
  result.i128_t = result.ctx.int128_t()
  result.void_t = result.ctx.void_t()
  result.backend = backend

# ############################################################
#
#                Metadata precomputation
#
# ############################################################

# Constantine on CPU is configured at compile-time for several properties that need to be runtime configuration GPUs:
# - word size (32-bit or 64-bit)
# - curve properties access like modulus bitsize or -1/M[0] a.k.a. m0ninv
# - constants are stored in freestanding `const`
#
# This is because it's not possible to store a BigInt[254] and a BigInt[384]
# in a generic way in the same structure, especially without using heap allocation.
# And with Nim's dead code elimination, unused curves are not compiled in.
#
# As there would be no easy way to dynamically retrieve (via an array or a table)
#    const BLS12_381_modulus = ...
#    const BN254_Snarks_modulus = ...
#
# - We would need a macro to properly access each constant.
# - We would need to create a 32-bit and a 64-bit version.
# - Unused curves would be compiled in the program.
#
# Note: on GPU we don't manipulate secrets hence branches and dynamic memory allocations are allowed.
#
# As GPU is a niche usage, instead we recreate the relevant `precompute` and IO procedures
# with dynamic wordsize support.

type
  DynWord = uint32 or uint64
  BigNum[T: DynWord] = object
    bits: uint32
    limbs: seq[T]

# Serialization
# ------------------------------------------------

func byteLen(bits: SomeInteger): SomeInteger {.inline.} =
  ## Length in bytes to serialize BigNum
  (bits + 7) shr 3 # (bits + 8 - 1) div 8

func wordsRequired(bits, wordBitwidth: SomeInteger): SomeInteger {.inline.} =
  ## Compute the number of limbs required
  ## from the announced bit length

  debug: doAssert wordBitwidth == 32 or wordBitwidth == 64        # Power of 2
  (bits + wordBitwidth - 1) shr log2_vartime(uint32 wordBitwidth) # 5x to 55x faster than dividing by wordBitwidth

func fromHex[T](a: var BigNum[T], s: string) =
   var bytes = newSeq[byte](a.bits.byteLen())
   bytes.paddedFromHex(s, bigEndian)

   # 2. Convert canonical uint to BigNum
   const wordBitwidth = sizeof(T) * 8
   a.limbs.unmarshal(bytes, wordBitwidth, bigEndian)

func fromHex[T](BN: type BigNum[T], bits: uint32, s: string): BN =
  const wordBitwidth = sizeof(T) * 8
  let numWords = wordsRequired(bits, wordBitwidth)

  result.bits = bits
  result.limbs.setLen(numWords)
  result.fromHex(s)

func toHex[T](a: BigNum[T]): string =
  ## Conversion to big-endian hex
  ## This is variable-time
  # 1. Convert BigInt to canonical uint
  const wordBitwidth = sizeof(T) * 8
  var bytes = newSeq[byte](byteLen(a.bits))
  bytes.marshal(a.limbs, wordBitwidth, bigEndian)

  # 2 Convert canonical uint to hex
  return bytes.toHex()

# Checks
# ------------------------------------------------

func checkValidModulus(M: BigNum) =
  const wordBitwidth = uint32(BigNum.T.sizeof() * 8)
  let expectedMsb = M.bits-1 - wordBitwidth * (M.limbs.len.uint32 - 1)
  let msb = log2_vartime(M.limbs[M.limbs.len-1])

  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those:\n" &
    "    Modulus '" & M.toHex() & "' is declared with " & $M.bits &
    " bits but uses " & $(msb + wordBitwidth * uint32(M.limbs.len - 1)) & " bits."

# Fields metadata
# ------------------------------------------------

func negInvModWord[T](M: BigNum[T]): T =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   µ ≡ -1/M[0] (mod SecretWord)
  ##
  ## M[0] is the least significant limb of M
  ## M must be odd and greater than 2.
  ##
  ## Assuming 64-bit words:
  ##
  ## µ ≡ -1/M[0] (mod 2^64)
  checkValidModulus(M)
  return M.limbs[0].negInvModWord()

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

  FieldConst* = object
    wordTy: TypeRef
    fieldTy: TypeRef
    modulus*: seq[ConstValueRef]
    m0ninv*: ConstValueRef
    bits*: uint32
    spareBits*: uint8

  CurveMetadata* = object
    curve*: Curve
    prefix*: string
    wordSize*: WordSize
    fp*: FieldConst
    fr*: FieldConst

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

  let numWords = wordsRequired(modBits, wordBitwidth)

  fc.wordTy = wordTy
  fc.fieldTy = array_t(wordTy, numWords)

  case wordSize
  of size32:
    let m = BigNum[uint32].fromHex(modBits, modulus)
    fc.modulus.setlen(m.limbs.len)
    for i in 0 ..< m.limbs.len:
      fc.modulus[i] = ctx.int32_t().constInt(m.limbs[i])

    fc.m0ninv = ctx.int32_t().constInt(m.negInvModWord())

  of size64:
    let m = BigNum[uint64].fromHex(modBits, modulus)
    fc.modulus.setlen(m.limbs.len)
    for i in 0 ..< m.limbs.len:
      fc.modulus[i] = ctx.int64_t().constInt(m.limbs[i])

    fc.m0ninv = ctx.int64_t().constInt(m.negInvModWord())

  debug: doAssert numWords == fc.modulus.len.uint32
  fc.bits = modBits
  fc.spareBits = uint8(numWords*wordBitwidth - modBits)

proc init*(
       C: type CurveMetadata, ctx: ContextRef,
       prefix: string, wordSize: WordSize,
       fpBits: uint32, fpMod: string,
       frBits: uint32, frMod: string): CurveMetadata =

  result = C(prefix: prefix, wordSize: wordSize)
  result.fp.setFieldConst(ctx, wordSize, fpBits, fpMod)
  result.fr.setFieldConst(ctx, wordSize, frBits, frMod)

proc genSymbol*(cm: CurveMetadata, opcode: Opcode): string {.inline.} =
  cm.prefix &
    (if cm.wordSize == size32: "32b_" else: "64b_") &
    $opcode

func getFieldType*(cm: CurveMetadata, field: Field): TypeRef {.inline.} =
  if field == fp:
    return cm.fp.fieldTy
  else:
    return cm.fr.fieldTy

func getNumWords*(cm: CurveMetadata, field: Field): int {.inline.} =
  case field
  of fp:
    return cm.fp.modulus.len
  of fr:
    return cm.fr.modulus.len

func getModulus*(cm: CurveMetadata, field: Field): lent seq[ConstValueRef] {.inline.} =
  case field
  of fp:
    return cm.fp.modulus
  of fr:
    return cm.fr.modulus

func getSpareBits*(cm: CurveMetadata, field: Field): uint8 {.inline.} =
  if field == fp:
    return cm.fp.sparebits
  else:
    return cm.fr.sparebits

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

proc `[]`*(a: Array, index: SomeInteger): ValueRef {.inline.}=
  # First dereference the array pointer with 0, then access the `index`
  let pelem = a.builder.getElementPtr2_InBounds(a.arrayTy, a.p, [ValueRef constInt(a.int32_t, 0), ValueRef constInt(a.int32_t, uint64 index)])
  a.builder.load2(a.elemTy, pelem)

proc `[]=`*(a: Array, index: SomeInteger, val: ValueRef) {.inline.}=
  let pelem = a.builder.getElementPtr2_InBounds(a.arrayTy, a.p, [ValueRef constInt(a.int32_t, 0), ValueRef constInt(a.int32_t, uint64 index)])
  a.builder.store(val, pelem)

proc store*(builder: BuilderRef, dst: Array, src: Array) {.inline.}=
  let v = builder.load2(src.arrayTy, src.p)
  builder.store(v, dst.p)