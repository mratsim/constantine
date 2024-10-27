# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, codegen_nvidia]

proc testName[Name: static Algebra](field: type FF[Name], wordSize: int, a: FF[Name], count: int) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(field, wordSize)

  ## NOTE: We need to call `genFpNsqr` manually, because of the 'compile time'
  ## count parameter, which deviates from the normal `pub_fields.nim` function
  ## signatures.
  let kernName = nv.asy.genFpNsqr(nv.fd, count)
  let kernel = nv.compile(kernName)

  block Logic:
    # For CPU:
    var rCPU: field
    rCPU = a

    for i in countdown(count, 1):
      rCPU = rCPU * rCPU

    # For GPU:
    var rGPU: field
    kernel.execCuda(rGPU, a)

    echo rCPU.toHex()
    echo rGPU.toHex()
    doAssert bool(rCPU == rGPU)

let a = Fp[BN254_Snarks].fromHex("0x12345678FF11FFAA00321321CAFECAFE")

testName(Fp[BN254_Snarks], 32, a, 2)
testName(Fp[BN254_Snarks], 32, a, 3)
testName(Fp[BN254_Snarks], 32, a, 4)
