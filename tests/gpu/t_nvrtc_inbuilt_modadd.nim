import std / strformat

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions {.all.},
  constantine/platforms/abis/nvidia_abi,
  constantine/math_compiler/experimental/runtime_compile,
  constantine/serialization/io_limbs

import constantine/math_compiler/experimental/nvrtc_field_ops

const N = 8
type T = Fp[BN254_Snarks]
const WordSize = 32
const BigIntExample* = cuda:

  defBigInt(N)
  defPtxHelpers()
  defCoreFieldOps(T)

  template getFieldModulus(): untyped = static: T.getModulus().limbs

  proc modaddTest(output: ptr UncheckedArray[uint32], a, b: BigInt) {.global.} =
    let M64 = getFieldModulus()
    # Cast the 64bit limbs of field modulus to 32bit limbs to copy
    var data = cast[ptr UncheckedArray[uint32]](addr M64[0])
    ## NOTE: you cannot do `BigInt(limbs: data)`. Leads to invalid C/CUDA code. We might turn calls
    ## like that into memcpy in the future.
    var M = BigInt()
    ## Or copy data from a runtime array
    for i in 0 ..< 8:
      M[i] = data[i]
    ## also works of course (in which case cast is not needed)
    #memcpy(addr M[0], addr M64[0], sizeof(M64))

    # Call `modadd` and assign to result
    let res = modadd(a, b, M)
    for i in 0 ..< b.len:
      output[i] = res[i]

  proc modsubTest(output: ptr UncheckedArray[uint32], a, b: BigInt) {.global.} =
    let M64 = getFieldModulus() # need a let variable, otherwise modulus does not have an address
    var M = BigInt()
    ## TODO: avoid this memcopy
    memcpy(addr M[0], addr M64[0], sizeof(M64))

    # Call `modadd` and assign to result
    let res = modsub(a, b, M)
    for i in 0 ..< b.len:
      output[i] = res[i]

  proc mtymulTest(output: ptr UncheckedArray[uint32], a, b: BigInt) {.global.} =
    let M64 = getFieldModulus() # need a let variable, otherwise modulus does not have an address
    var M = BigInt()
    ## TODO: avoid this memcopy
    memcpy(addr M[0], addr M64[0], sizeof(M64))

    # Call `modadd` and assign to result
    let res = mtymul_CIOS_sparebit(a, b, M, true)
    #let res = mtymul_CIOS_concise(a, b, M, true)
    for i in 0 ..< b.len:
      output[i] = res[i]


proc getBigints(): (Fp[BN254_Snarks], Fp[BN254_Snarks]) =
  # return some bigint values of a finite field
  let a = Fp[BN254_Snarks].fromUInt(1'u32)
  let b = Fp[BN254_Snarks].fromHex("0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a")
  #let b = Fp[BN254_Snarks].fromUint(1'u32)

  result = (a, b)

template checkOp(kernel, exp, hOut, a, b: untyped): untyped =
  nvrtc.execute(kernel, (hOut), (a, b))

  ## Compare with expected
  # Get expected as array of 8 uint32
  let expU32: array[8, uint32] = cast[ptr array[8, uint32]](exp.mres.limbs[0].addr)[]

  # both arrays must match
  #doAssert hOut == expU32
  # now compare as field elements
  # Things to note:
  # - the `modadd` `hOut` data is in Montgomery representation
  # - we need to convert `array[8, uint32]` into `array[32, byte]`
  #   to unmarshal into a `BigInt[254]`
  # - need to undo Montgomery representation on the `BigInt[254]` before
  #   constructing the finite field element
  var res: Fp[BN254_Snarks]
  var resBI: matchingBigInt(BN254_Snarks)
  var hOutBytes: array[32, byte]
  hOutBytes.marshal(hOut, 32, littleEndian) # convert to 32 bytes
  resBI.unmarshal(hOutBytes, littleEndian)  # convert bytes to BigInt[254]
  type T = Fp[BN254_Snarks]
  # undo Montgomery representation
  resBI.fromMont(resBI, T.getModulus(), T.getNegInvModWord(), T.getSpareBits())
  res.fromBig(resBI)                        # convert `BigInt[254]` to finite field element

  echo "Res = ", res.toHex()
  echo "Exp = ", exp.toHex()
  doAssert bool(res == exp)

proc main =
  var nvrtc = initNvrtc(BigIntExample)
  # echo the generated CUDA code
  echo BigIntExample

  nvrtc.compile()
  nvrtc.getPtx()

  var hOut: array[8, uint32] # storage for the output limbs (could also be a `Fp[BN254_Snarks]` instead)
  nvrtc.numBlocks = 1
  nvrtc.threadsPerBlock = 1

  let (a, b) = getBigInts()

  ## If arguments were `prt BigInt`:
  #nvrtc.execute("bigintTest", (hOut), (addr a, addr b))
  # for regular `BigInt` arguments

  echo "M0NINV::: ", Fp[BN254_Snarks].getModulus().negInvModWord()
  echo "M0NINV::: ", Fp[BN254_Snarks].getModulus().negInvModWord().sizeof()

  let exp1 = a + b
  checkOp("modaddTest", exp1, hOut, a, b)
  let exp2 = a - b
  checkOp("modsubTest", exp2, hOut, a, b)
  let exp3 = a * b
  checkOp("mtymulTest", exp3, hOut, a, b)


when isMainModule:
  main()
