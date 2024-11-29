import std / strformat
import nimcuda/cuda12_5/[nvrtc, check, cuda, cuda_runtime_api, driver_types]

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions {.all.},
  constantine/math_compiler/experimental/runtime_compile

type T = Fp[BN254_Snarks]
const WordSize = 32
# Example showing warp behavior with different thread counts
const BigIntExample = cuda:
  # Utility for add with carry operations
  type
    BigInt = object
      limbs: array[8, uint32]
  template `[]`(x: BigInt, idx: int): untyped = x.limbs[idx]
  template `[]=`(x: BigInt, idx: int, val: uint32): untyped = x.limbs[idx] = val
  template len(x: BigInt): int = 8 # static: BigInt().limbs.len

  # Need to get the limbs & spare bits data in a static context
  template getFieldModulus(): untyped = static: T.getModulus().limbs
  template spareBits(): untyped = static: (BigInt().limbs.len * WordSize - T.bits())

  ## Note: the below would just be generated from a macro of course, similar to
  ## `constantine/platforms/llvm/asm_nvidia.nim`.
  proc add_cio(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"addc.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc add_ci(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"addc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc add_co(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"add.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bo(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"sub.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bi(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"subc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc sub_bio(a, b: uint32): uint32 {.device, forceinline.} =
    var res: uint32
    asm """
"subc.cc.u32 %0, %1, %2;" : "=r"(res) : "r"(a), "r"(b)
"""
    return res

  proc slct(a, b: uint32, pred: uint32): uint32 {.device, forceinline.} =
    var res: uint32
# "slct.s32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(pred)
    asm """
"slct.u32.s32 %0, %1, %2, %3;" : "=r"(res) : "r"(a), "r"(b), "r"(pred)
"""
    return res

  proc finalSubMayOverflow(a, M: BigInt): BigInt {.device.} =
    ## If a >= Modulus: r <- a-M
    ## else:            r <- a
    ##
    ## This is constant-time straightline code.
    ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
    ##
    ## To be used when the final substraction can
    ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)
    let N = a.len
    var scratch: BigInt

    # Contains 0x0001 (if overflowed limbs) or 0x0000
    let overflowedLimbs = add_ci(0'u32, 0'u32)

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    for i in 1 ..< N:
      scratch[i] = sub_bio(a[i], M[i])

    # 1. if `overflowedLimbs`, underflowedModulus >= 0
    # 2. if a >= M, underflowedModulus >= 0
    # if underflowedModulus >= 0: a-M else: a
    # TODO: predicated mov instead?
    let underflowedModulus = sub_bi(overflowedLimbs, 0'u32)

    var r: BigInt
    for i in 0 ..< N:
      r[i] = slct(scratch[i], a[i], underflowedModulus)
    return r

  proc finalSubNoOverflow(a, M: BigInt): BigInt {.device.} =
    ## If a >= Modulus: r <- a-M
    ## else:            r <- a
    ##
    ## This is constant-time straightline code.
    ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
    ##
    ## To be used when the modulus does not use the full bitwidth of the storing words
    ## (say using 255 bits for the modulus out of 256 available in words)
    let N = a.len
    var scratch: BigInt

    # Now substract the modulus, and test a < M with the last borrow
    scratch[0] = sub_bo(a[0], M[0])
    for i in 1 ..< N:
      scratch[i] = sub_bio(a[i], M[i])

    # If it underflows here, `a` was smaller than the modulus, which is what we want
    let underflowedModulus = sub_bi(0'u32, 0'u32)

    var r: BigInt
    for i in 0 ..< N:
      r[i] = slct(scratch[i], a[i], underflowedModulus)
    return r

  proc modadd(a, b, M: BigInt): BigInt {.device.} =
    # try to add two bigints
    let N = a.len
    #var res: BigInt[N]
    var res: BigInt

    var t: BigInt # temporary

    t[0] = add_co(a[0], b[0])
    for i in 1 ..< N:
      t[i] = add_cio(a[i], b[i])
      printf("element i %d = %d\n", i, t[i])

    # can use `when` of course!
    when spareBits() >= 1: # if spareBits() >= 1: # would also work
      t = finalSubNoOverflow(t, M)
    else:
      t = finalSubMayOverflow(t, M)

    return t

  #proc bigintTest(output: ptr UncheckedArray[uint32], aIn, bIn: ptr BigInt) {.global.} =
  proc bigintTest(output: ptr UncheckedArray[uint32], a, b: BigInt) {.global.} =
    # Get global thread ID for example
    let tid = blockIdx.x * blockDim.x + threadIdx.x
    # or warp ID and lane ID
    let warp_id = threadIdx.x div 32
    let lane_id = threadIdx.x mod 32

    ## Example: Construct via static array would work:
    #let b = BigInt(limbs: [1'u32, 2, 3, 4, 5, 6, 7, 8])

    ## If the bigints are passed as ptrs:
    #let a = aIn[]
    #let b = bIn[]
    for i in 0 ..< 8: # print an input
      printf("b: %d = %u\n", i, b[i])

    let M64 = getFieldModulus() # need a let variable, otherwise modulus does not have an address
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

    for i in 0 ..< 4: # let's print M64 as uint64 values
      printf("M64: %d = %llu\n", i, M64[i])
    for i in 0 ..< 8: # let's print m64 as 32 bit data and assigned
      printf("M: %d = %u\n", i, M[i])
      printf("M64 as 32: %d = %u\n", i, data[i])

    # Call `modadd` and assign to result
    let res = modadd(a, b, M)
    for i in 0 ..< b.len:
      output[i] = res[i]

proc getBigints(): (Fp[BN254_Snarks], Fp[BN254_Snarks]) =
  # return some bigint values of a finite field
  let a = Fp[BN254_Snarks].fromUInt(1'u32)
  let b = Fp[BN254_Snarks].fromHex("0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a")

  result = (a, b)

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
  nvrtc.execute("bigintTest", (hOut), (a, b))

  # Output:
  echo "hOut = ", hOut

when isMainModule:
  main()
