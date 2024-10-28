# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/bithacks,
  constantine/platforms/llvm/llvm,
  constantine/serialization/[io_limbs, codecs],
  constantine/named/deriv/precompute

import ./ir

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

func toHexLlvm*[T](a: BigNum[T]): string =
  ## Conversion to big-endian hex suitable for LLVM literals
  ## It MUST NOT have a prefix
  ## This is variable-time
  # 1. Convert BigInt to canonical uint
  const wordBitwidth = sizeof(T) * 8
  var bytes = newSeq[byte](byteLen(a.bits))
  bytes.marshal(a.limbs, wordBitwidth, bigEndian)

  # 2. Convert canonical uint to hex
  const hexChars = "0123456789abcdef"
  result = newString(2 * bytes.len)
  for i in 0 ..< bytes.len:
    let bi = bytes[i]
    result[2*i] = hexChars[bi shr 4 and 0xF]
    result[2*i+1] = hexChars[bi and 0xF]

# Checks
# ------------------------------------------------

func checkValidModulus(M: BigNum) =
  const wordBitwidth = uint32(BigNum.T.sizeof() * 8)
  let expectedMsb = M.bits-1 - wordBitwidth * (M.limbs.len.uint32 - 1)
  let msb = log2_vartime(M.limbs[M.limbs.len-1])

  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those:\n" &
    "    Modulus '0x" & M.toHexLlvm() & "' is declared with " & $M.bits &
    " bits but uses " & $(msb + wordBitwidth * uint32(M.limbs.len - 1)) & " bits."

func checkOdd[T](a: T) =
  doAssert bool(a and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

func checkOdd(M: BigNum) =
  checkOdd(M.limbs[0])

# BigNum operations
# ------------------------------------------------

template Widths(): untyped {.dirty.} =
  when T is uint32:
    const
      HalfWidth = 16
      HalfBase = (1'u32 shl HalfWidth)
      HalfMask = HalfBase - 1
  elif T is uint64:
    const
      HalfWidth = 32
      HalfBase = (1'u64 shl HalfWidth)
      HalfMask = HalfBase - 1
  else:
    {.error: "Invalid type for BigNum.".}

func hi[T: DynWord](n: T): T =
  Widths()
  result = n shr HalfWidth

func lo[T: DynWord](n: T): T =
  Widths()
  result = n and HalfMask

func split[T: DynWord](n: T): tuple[hi, lo: T] =
  result.hi = n.hi
  result.lo = n.lo

func merge[T: DynWord](hi, lo: T): T =
  when T is uint32:
    const HalfWidth = 16
  else: # uint64
    const HalfWidth = 32
  (hi shl HalfWidth) or lo

func addC[T: DynWord](cOut, sum: var T, a, b, cIn: T) =
  # Add with carry, fallback for the Compile-Time VM
  # (CarryOut, Sum) <- a + b + CarryIn
  let (aHi, aLo) = split(a)
  let (bHi, bLo) = split(b)
  let tLo = aLo + bLo + cIn
  let (cLo, rLo) = split(tLo)
  let tHi = aHi + bHi + cLo
  let (cHi, rHi) = split(tHi)
  cOut = cHi
  sum = merge(rHi, rLo)

func subB[T: DynWord](bOut, diff: var T, a, b, bIn: T) =
  # Substract with borrow, fallback for the Compile-Time VM
  # (BorrowOut, Sum) <- a - b - BorrowIn
  Widths()
  let (aHi, aLo) = split(a)
  let (bHi, bLo) = split(b)
  let tLo = HalfBase + aLo - bLo - bIn
  let (noBorrowLo, rLo) = split(tLo)
  let tHi = HalfBase + aHi - bHi - T(noBorrowLo == 0)
  let (noBorrowHi, rHi) = split(tHi)
  bOut = T(noBorrowHi == 0)
  diff = merge(rHi, rLo)

func add[T: DynWord](a: var BigNum[T], w: T): bool =
  ## Limbs addition, add a number that fits in a word
  ## Returns the carry
  var carry, sum: T
  addC(carry, sum, T(a.limbs[0]), w, carry)
  a.limbs[0] = sum
  for i in 1 ..< a.limbs.len:
    let ai = T(a.limbs[i])
    addC(carry, sum, ai, 0, carry)
    a.limbs[i] = sum

  result = bool(carry)

func shiftRight*[T: DynWord](a: var BigNum[T], k: int) =
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^32 or 2^64)
  const wordBitwidth = sizeof(T) * 8
  for i in 0 ..< a.limbs.len-1:
    a.limbs[i] = (a.limbs[i] shr k) or (a.limbs[i+1] shl (wordBitWidth - k))
  a.limbs[a.limbs.len-1] = a.limbs[a.limbs.len-1] shr k

func dbl[T: DynWord](a: var BigNum[T]): bool =
  ## In-place multiprecision double
  ##   a -> 2a
  var carry, sum: T
  for i in 0 ..< a.limbs.len:
    let ai = T(a.limbs[i])
    addC(carry, sum, ai, ai, carry)
    a.limbs[i] = sum

  result = bool carry

func csub[T: DynWord](a: var BigNum[T], b: BigNum[T], ctl: bool): bool =
  ## In-place optional substraction
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var borrow, diff: T
  for i in 0 ..< a.limbs.len:
    let ai = T(a.limbs[i])
    let bi = T(b.limbs[i])
    subB(borrow, diff, ai, bi, borrow)
    if ctl:
      a.limbs[i] = diff

  result = bool borrow

func doubleMod[T: DynWord](a: var BigNum[T], M: BigNum[T]) =
  ## In-place modular double
  ##   a -> 2a (mod M)
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var ctl = dbl(a)
  ctl = ctl or not a.csub(M, false)
  discard csub(a, M, ctl)

func r_powmod[T: DynWord](n: static int, M: BigNum[T]): BigNum[T] =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R ≡ R (mod M) with R = (2^WordBitWidth)^numWords
  ##   or
  ##   R² ≡ R² (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## Assuming a field modulus of size 256-bit with 63-bit words, we require 5 words
  ##   R² ≡ ((2^63)^5)^2 (mod M) = 2^630 (mod M)

  # Algorithm
  # Bos and Montgomery, Montgomery Arithmetic from a Software Perspective
  # https://eprint.iacr.org/2017/1057.pdf
  #
  # For R = r^n = 2^wn and 2^(wn − 1) ≤ N < 2^wn
  # r^n = 2^63 in on 64-bit and w the number of words
  #
  # 1. C0 = 2^(wn - 1), the power of two immediately less than N
  # 2. for i in 1 ... wn+1
  #      Ci = C(i-1) + C(i-1) (mod M)
  #
  # Thus: C(wn+1) ≡ 2^(wn+1) C0 ≡ 2^(wn + 1) 2^(wn - 1) ≡ 2^(2wn) ≡ (2^wn)^2 ≡ R² (mod M)

  checkOdd(M)
  checkValidModulus(M)

  let
    wordBitwidth = sizeof(T) * 8
    w = M.limbs.len
    msb = M.bits-1 - uint32(wordBitWidth * (w - 1))
    start = uint32((w - 1) * wordBitWidth) + msb
    stop = uint32 n*wordBitWidth*w

  result.limbs = newSeq[T](M.limbs.len)
  result.limbs[M.limbs.len-1] = T(1) shl msb # C0 = 2^(wn-1), the power of 2 immediatly less than the modulus
  for _ in start ..< stop:
    result.doubleMod(M)

# Fields metadata
# ------------------------------------------------

func negInvModWord[T: DynWord](M: BigNum[T]): T =
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

func primePlus1div2*[T: DynWord](P: BigNum[T]): BigNum[T] =
  ## Compute (P+1)/2, assumes P is odd
  ## For use in constant-time modular inversion
  ##
  ## Warning ⚠️: Result is in the canonical domain (not Montgomery)
  checkOdd(P)

  # (P+1)/2 = P/2 + 1 if P is odd,
  # this avoids overflowing if the prime uses all bits
  # i.e. in the form (2^64)ʷ - 1 or (2^32)ʷ - 1

  result = P
  result.shiftRight(1)
  let carry = result.add(1)
  doAssert not carry

func montyOne*[T: DynWord](M: BigNum[T]): BigNum[T] =
  ## Returns "1 (mod M)" in the Montgomery domain.
  ## This is equivalent to R (mod M) in the natural domain
  r_powmod(1, M)

# ############################################################
#
#                Globals in IR
#
# ############################################################

proc getModulusPtr*(asy: Assembler_LLVM, fd: FieldDescriptor): ValueRef =
  let modname = fd.name & "_mod"
  var M = asy.module.getGlobal(cstring modname)
  if M.isNil():
    M = asy.defineGlobalConstant(
      name = modname,
      section = fd.name,
      constIntOfStringAndSize(fd.intBufTy, fd.modulus, 16),
      fd.intBufTy,
      alignment = 64
    )
  return M

proc getPrimePlus1div2Ptr*(asy: Assembler_LLVM, fd: FieldDescriptor): ValueRef =
  let pp1d2name = fd.name & "_pp1d2"
  result = asy.module.getGlobal(cstring pp1d2name)
  if result.isNil():
    ## NOTE: Construction of bigint in LLVM happens based on uint64 regardless of
    ## word size on device.
    let M = BigNum[uint64].fromHex(fd.bits, fd.modulus)
    let Mpp1d2 = M.primePlus1div2()
    result = asy.defineGlobalConstant(
      name = pp1d2name,
      section = fd.name,
      constIntOfArbitraryPrecision(fd.intBufTy, cuint Mpp1d2.limbs.len, Mpp1d2.limbs[0].addr),
      fd.intBufTy,
      alignment = 64
    )

proc getMontyOnePtr*(asy: Assembler_LLVM, fd: FieldDescriptor): ValueRef =
  let mOneName = fd.name & "_montyOne"
  result = asy.module.getGlobal(cstring mOneName)
  if result.isNil():
    ## NOTE: Construction of bigint in LLVM happens based on uint64 regardless of
    ## word size on device.
    let M = BigNum[uint64].fromHex(fd.bits, fd.modulus)
    let MmOne = M.montyOne()
    result = asy.defineGlobalConstant(
      name = mOneName,
      section = fd.name,
      constIntOfArbitraryPrecision(fd.intBufTy, cuint MmOne.limbs.len, MmOne.limbs[0].addr),
      fd.intBufTy,
      alignment = 64
    )

proc getM0ninv*(asy: Assembler_LLVM, fd: FieldDescriptor): ValueRef =
  let m0ninvname = fd.name & "_m0ninv"
  var m0ninv = asy.module.getGlobal(cstring m0ninvname)
  if m0ninv.isNil():
    if fd.w == 32:
      let M = BigNum[uint32].fromHex(fd.bits, fd.modulus)
      m0ninv = asy.defineGlobalConstant(
        name = m0ninvname,
        section = fd.name,
        constInt(fd.wordTy, M.negInvModWord()),
        fd.wordTy
      )
    else:
      let M = BigNum[uint64].fromHex(fd.bits, fd.modulus)
      m0ninv = asy.defineGlobalConstant(
        name = m0ninvname,
        section = fd.name,
        constInt(fd.wordTy, M.negInvModWord()),
        fd.wordTy
      )

  return asy.load2(fd.wordTy, m0ninv, "m0ninv")

when isMainModule:
  let asy = Assembler_LLVM.new("test_module", bkX86_64_Linux)
  let fd = asy.ctx.configureField(
    "bls12_381_fp",
    381,
    "1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab",
    v = 1, w = 64)

  discard asy.getModulusPtr(fd)
  discard asy.getM0ninv(fd)

  echo "========================================="
  echo "LLVM IR\n"

  echo asy.module
  echo "========================================="

  asy.module.verify(AbortProcessAction)

  # --------------------------------------------
  # See the assembly - note it might be different from what the JIT compiler did
  initializeFullNativeTarget()

  const triple = "x86_64-pc-linux-gnu"

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = "",
    features = "adx,bmi2", # TODO check the proper way to pass options
    level = CodeGenLevelAggressive,
    reloc = RelocDefault,
    codeModel = CodeModelDefault
  )

  let pbo = createPassBuilderOptions()
  let err = asy.module.runPasses(
    "default<O3>,function-attrs,memcpyopt,sroa,mem2reg,gvn,dse,instcombine,inline,adce",
    machine,
    pbo
  )
  if not err.pointer().isNil():
    writeStackTrace()
    let errMsg = err.getErrorMessage()
    stderr.write("\"codegenX86_64\" for module '" & astToStr(module) & "' " & $instantiationInfo() &
                 " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

  echo "========================================="
  echo "Assembly\n"

  echo machine.emitTo[:string](asy.module, AssemblyFile)
  echo "========================================="
