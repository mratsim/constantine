import std / strformat

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/math/arithmetic/bigints,
  constantine/platforms/abstractions {.all.},
  constantine/platforms/abis/nvidia_abi,
  constantine/math_compiler/experimental/runtime_compile,
  constantine/serialization/io_limbs

import constantine/math_compiler/experimental/nvrtc_field_ops

proc toFp[Name: static Algebra](FF: type Fp[Name], ar: array[8, uint32]): Fp[Name] =
  var resBI: matchingBigInt(BN254_Snarks)
  var arBytes: array[32, byte]
  arBytes.marshal(ar, 32, littleEndian) # convert to 32 bytes
  resBI.unmarshal(arBytes, littleEndian)  # convert bytes to BigInt[254]
  # undo Montgomery representation
  resBI.fromMont(resBI, FF.getModulus(), FF.getNegInvModWord(), FF.getSpareBits())
  result.fromBig(resBI)                        # convert `BigInt[254]` to finite field element

const N = 8
type T = Fp[BN254_Snarks]
const WordSize = 32
const BigIntExample* = cuda:

  defBigInt(N)
  defPtxHelpers()
  defCoreFieldOps(T)

  proc testPassBigInt(output: ptr BigInt) {.global.} =
    # Call `modadd` and assign to result
    for i in 0 ..< 8:
      output[i] = i.uint32

  proc testSetZero(output: ptr BigInt) {.global.} =
    output[].setZero()

  proc testSetOne(output: ptr BigInt) {.global.} =
    output[].setOne()

  proc testAdd(output: ptr BigInt, a, b: BigInt) {.global.} =
    output[].add(a, b)

  proc testSub(output: ptr BigInt, a, b: BigInt) {.global.} =
    output[].sub(a, b)

  proc testMul(output: ptr BigInt, a, b: BigInt) {.global.} =
    output[].mul(a, b)

  proc testCcopy(output: ptr BigInt, a, b: BigInt, c: bool) {.global.} =
    output[] = a
    output[].ccopy(b, c)

  proc testCsetOne(output: ptr BigInt, a: BigInt, c: bool) {.global.} =
    output[] = a
    output[].cSetOne(c)

  proc testCsetZero(output: ptr BigInt, a: BigInt, c: uint32) {.global.} =
    output[] = a
    output[].cSetZero(c.bool)

  proc testCadd(output: ptr BigInt, a, b: BigInt, c: bool) {.global.} =
    output[] = a
    output[].cadd(b, c)

  proc testCsub(output: ptr BigInt, a, b: BigInt, c: bool) {.global.} =
    output[] = a
    output[].csub(b, c)

  proc testDouble(output: ptr BigInt, a: BigInt) {.global.} =
    output[].doubleElement(a)

  proc testNsqr(output: ptr BigInt, a: BigInt, count: int) {.global.} =
    output[].nsqr(a, count)

  proc testIsZero(output: ptr bool, a: BigInt) {.global.} =
    output[].isZero(a)

  proc testIsOdd(output: ptr bool, a: BigInt) {.global.} =
    output[].isOdd(a)

  proc testNeg(output: ptr BigInt, a: BigInt) {.global.} =
    output[].neg(a)

  proc testCneg(output: ptr BigInt, a: BigInt, c: bool) {.global.} =
    output[].cneg(a, c)

  proc testShiftRight(output: ptr BigInt, a: BigInt, k: uint32) {.global.} =
    output[] = a
    output[].shiftRight(k)

  proc testDiv2(output: ptr BigInt, a: BigInt) {.global.} =
    output[] = a
    output[].div2()

from std / sequtils import mapIt
proc main =
  var nvrtc = initNvrtc(BigIntExample)
  # echo the generated CUDA code
  # echo BigIntExample
  writeFile("/tmp/kernel.cu", BigIntExample)

  nvrtc.compile()
  nvrtc.getPtx()

  var hOut: array[8, uint32] # storage for the output limbs (could also be a `Fp[BN254_Snarks]` instead)
  nvrtc.numBlocks = 1
  nvrtc.threadsPerBlock = 1

  block PassBigInt:
    hOut.reset()
    nvrtc.execute("testPassBigInt", (hOut), ())
    let exp = [0'u32, 1, 2, 3, 4, 5, 6, 7]
    for i in 0 ..< 8:
      doAssert exp[i] == hOut[i]

  block SetZero:
    # now use `setZero` to reset to zero
    # `hOut` should be zero, but let's change some numbers
    hOut.reset()
    hOut[0] = 123
    hOut[5] = 321
    nvrtc.execute("testSetZero", (hOut), ())
    let exp = [0'u32, 0, 0, 0, 0, 0, 0, 0]
    for i in 0 ..< 8:
      doAssert exp[i] == hOut[i]

  block SetOne:
    # and `setOne` to set to Montgomery representation of 1
    hOut.reset()
    nvrtc.execute("testSetOne", (hOut), ())
    let expFp = T.fromUInt(1'u32)
    doAssert bool(expFp == toFp(T, hOut))

  block Add:
    # add one and one
    hOut.reset()
    let inFp = T.fromUInt(1'u32)
    nvrtc.execute("testAdd", (hOut), (inFp, inFp)) # inputs 1 and 1
    let expFp = T.fromUInt(2'u32)
    doAssert bool(expFp == toFp(T, hOut))

  block Sub:
    hOut.reset()
    let inFp = T.fromUInt(1'u32)
    nvrtc.execute("testSub", (hOut), (inFp, inFp)) # inputs 1 and 1
    let expFp1 = T.fromUInt(0'u32)
    doAssert bool(expFp1 == toFp(T, hOut))

    hOut.reset()
    let inFp1 = T.fromUInt(5'u32)
    let inFp2 = T.fromUInt(2'u32)
    nvrtc.execute("testSub", (hOut), (inFp1, inFp2)) # inputs 1 and 1
    let expFp2 = T.fromUInt(3'u32)
    doAssert bool(expFp2 == toFp(T, hOut))

  block Mul:
    # mul 2 and 2
    hOut.reset()
    let inFp = T.fromUInt(2'u32)
    nvrtc.execute("testMul", (hOut), (inFp, inFp)) # inputs 2 and 2
    let expFp = T.fromUInt(4'u32)
    doAssert bool(expFp == toFp(T, hOut))

  block Ccopy:
    # ccopy based on true (false means we do not copy b into a)
    hOut.reset()
    let one = T.fromUInt(1'u32)
    let two = T.fromUInt(2'u32)
    nvrtc.execute("testCcopy", (hOut), (one, two, false)) # inputs 1 and 2
    doAssert bool(one == toFp(T, hOut))
    # and based on false (true means we do copy b into a)
    nvrtc.execute("testCcopy", (hOut), (one, two, true)) # inputs 1 and 2
    doAssert bool(two == toFp(T, hOut))

  block CsetZero:
    hOut.reset()
    hOut[0] = 123
    hOut[5] = 321
    var input: array[8, uint32]
    input = hOut
    nvrtc.execute("testCsetZero", (hOut), (input, 0'u32))
    let expF = [123'u32, 0, 0, 0, 0, 321, 0, 0]
    for i in 0 ..< 8:
      doAssert expF[i] == hOut[i]

    nvrtc.execute("testCsetZero", (hOut), (input, 1'u32))
    let expT = [0'u32, 0, 0, 0, 0, 0, 0, 0]
    for i in 0 ..< 8:
      doAssert expT[i] == hOut[i]

  block CsetOne:
    hOut.reset()
    hOut[0] = 123
    hOut[5] = 321
    var input: array[8, uint32]
    input = hOut
    nvrtc.execute("testCsetOne", (hOut), (input, false))
    let expF = [123'u32, 0, 0, 0, 0, 321, 0, 0]
    for i in 0 ..< 8:
      doAssert expF[i] == hOut[i]

    nvrtc.execute("testCsetOne", (hOut), (input, true))
    let expT = T.fromUInt(1'u32)
    doAssert bool(expT == toFp(T, hOut))

  block Cadd:
    # add one and one
    hOut.reset()
    let inFp = T.fromUInt(1'u32)
    nvrtc.execute("testCadd", (hOut), (inFp, inFp, false)) # inputs 1 and 1
    let expF = T.fromUInt(1'u32)
    doAssert bool(expF == toFp(T, hOut))

    hOut.reset()
    nvrtc.execute("testCadd", (hOut), (inFp, inFp, true)) # inputs 1 and 1
    let expT = T.fromUInt(2'u32)
    doAssert bool(expT == toFp(T, hOut))

  block Csub:
    hOut.reset()
    # add one and one
    let inFp1 = T.fromUInt(5'u32)
    let inFp2 = T.fromUInt(2'u32)
    nvrtc.execute("testCsub", (hOut), (inFp1, inFp2, false))
    let expF = T.fromUInt(5'u32)
    doAssert bool(expF == toFp(T, hOut))

    hOut.reset()
    nvrtc.execute("testCsub", (hOut), (inFp1, inFp2, true))
    let expT = T.fromUInt(3'u32)
    doAssert bool(expT == toFp(T, hOut))

  block DoubleElement:
    # add one and one
    hOut.reset()
    let inFp = T.fromUInt(6'u32)
    nvrtc.execute("testDouble", (hOut), (inFp))
    let exp = T.fromUInt(12'u32)
    doAssert bool(exp == toFp(T, hOut))

  block Nsqr:
    # add one and one
    hOut.reset()
    let inFp = T.fromUInt(2'u32)
    nvrtc.execute("testNsqr", (hOut), (inFp, 2))
    let exp1 = T.fromUInt(16'u32)
    doAssert bool(exp1 == toFp(T, hOut))

    hOut.reset()
    nvrtc.execute("testNsqr", (hOut), (inFp, 4))
    let exp2 = T.fromUInt(65536'u32)
    doAssert bool(exp2 == toFp(T, hOut))

  block IsZero:
    hOut.reset()
    let inFp1 = T.fromUInt(132'u32)
    var res: bool
    nvrtc.execute("testIsZero", (res), (inFp1))
    doAssert res == false

    hOut.reset()
    let inFp2 = T.fromUInt(0'u32)
    nvrtc.execute("testIsZero", (res), (inFp2))
    doAssert res == true

    hOut.reset()
    var inFp3: array[8, uint32] # zero initialized
    nvrtc.execute("testIsZero", (res), (inFp3))
    doAssert res == true

  block IsOdd:
    hOut.reset()
    var inp: array[8, uint32]
    inp[0] = 2 # even
    var res: bool
    nvrtc.execute("testIsOdd", (res), (inp))
    doAssert res == false

    hOut.reset()
    inp[0] = 0 # even
    inp[5] = 555
    nvrtc.execute("testIsOdd", (res), (inp))
    doAssert res == false

    hOut.reset()
    inp[0] = 123 # odd
    nvrtc.execute("testIsOdd", (res), (inp))
    doAssert res == true

  block Neg:
    hOut.reset()
    let inFp1 = T.fromUInt(2'u32)
    nvrtc.execute("testNeg", (hOut), (inFp1))
    var exp = inFp1
    exp.neg()
    doAssert bool(exp == toFp(T, hOut))

    hOut.reset()
    let inFp2 = T.fromUInt(123547'u32)
    nvrtc.execute("testNeg", (hOut), (inFp2))
    exp = inFp2
    exp.neg()
    doAssert bool(exp == toFp(T, hOut))

  block CNeg:
    hOut.reset()
    let inFp1 = T.fromUInt(2'u32)
    nvrtc.execute("testCneg", (hOut), (inFp1, false))
    doAssert bool(inFp1 == toFp(T, hOut))

    hOut.reset()
    nvrtc.execute("testCneg", (hOut), (inFp1, true))
    var exp1 = inFp1
    exp1.neg()
    doAssert bool(exp1 == toFp(T, hOut))

    hOut.reset()
    let inFp2 = T.fromUInt(123547'u32)
    nvrtc.execute("testCneg", (hOut), (inFp2, false))
    doAssert bool(inFp2 == toFp(T, hOut))

    hOut.reset()
    nvrtc.execute("testCneg", (hOut), (inFp2, true))
    var exp2 = inFp2
    exp2.neg()
    doAssert bool(exp2 == toFp(T, hOut))

  block ShiftRight:
    #let inFp1 = T.fromUInt(8'u32)
    hOut.reset()
    var inp: array[8, uint32]
    inp[0] = 8
    nvrtc.execute("testShiftRight", (hOut), (inp, 2))
    var exp: array[8, uint32]
    exp[0] = 2
    doAssert exp == hOut

    hOut.reset()
    nvrtc.execute("testShiftRight", (hOut), (inp, 3))
    exp[0] = 1
    doAssert exp == hOut

    hOut.reset()
    inp[0] = 15
    nvrtc.execute("testShiftRight", (hOut), (inp, 1))
    var exp3 = matchingBigInt(T.Name).fromUInt(15'u32)
    exp3.shiftRight(1)
    doAssert exp3.limbs.mapIt(it.uint32) == hOut.mapIt(it.uint32)

  block Div2:
    hOut.reset()
    let inFp1 = T.fromUInt(8'u32)
    nvrtc.execute("testDiv2", (hOut), (inFp1))
    let exp1 = T.fromUInt(4'u32)
    var expAF = inFp1
    expAF.div2()
    doAssert bool(exp1 == toFp(T, hOut))

    hOut.reset()
    let inFp2 = T.fromUInt(4096'u32)
    nvrtc.execute("testDiv2", (hOut), (inFp2))
    let exp2 = T.fromUInt(2048'u32)
    doAssert bool(exp2 == toFp(T, hOut))

    hOut.reset()
    let inFp3 = T.fromUInt(15'u32)
    nvrtc.execute("testDiv2", (hOut), (inFp3))
    var exp3 = T.fromUInt(15'u32)
    exp3.div2()
    doAssert bool(exp3 == toFp(T, hOut))


when isMainModule:
  main()
