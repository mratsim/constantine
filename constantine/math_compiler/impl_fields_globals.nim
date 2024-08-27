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
