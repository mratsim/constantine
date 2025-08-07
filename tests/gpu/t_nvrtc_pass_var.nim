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

  proc testPointer(x: var BigInt) {.device.} =
    ## just write data to the bigint
    for i in 0 ..< 8:
      x[i] = i.uint32

  proc test(output: ptr UncheckedArray[uint32]) {.global.} =
    # Call `modadd` and assign to result

    var t = BigInt()

    testPointer(t)

    for i in 0 ..< 8:
      output[i] = t[i]

proc main =
  var nvrtc = initNvrtc(BigIntExample)
  # echo the generated CUDA code
  # echo BigIntExample

  nvrtc.compile()
  nvrtc.getPtx()

  var hOut: array[8, uint32] # storage for the output limbs (could also be a `Fp[BN254_Snarks]` instead)
  nvrtc.numBlocks = 1
  nvrtc.threadsPerBlock = 1

  nvrtc.execute("test", (hOut), ())
  var exp = [0'u32, 1, 2, 3, 4, 5, 6, 7]
  for i in 0 ..< 8:
    doAssert exp[i] == hOut[i]



when isMainModule:
  main()
