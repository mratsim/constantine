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

proc testName[Name: static Algebra](field: type FF[Name], wordSize: int, a: FF[Name]) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(field, wordSize)
  let kernel = nv.compile(genFpNeg)

  block Logic:
    # For CPU:
    var rCPU: field
    rCPU = a
    rCPU.neg()

    # For GPU:
    var rGPU: field
    kernel.execCuda(res = rGPU, inputs = a)

    echo "Input: ", a.toHex()
    echo "CPU:   ", rCPU.toHex()
    echo "GPU:   ", rGPU.toHex()
    doAssert bool(rCPU == rGPU)

let a = Fp[BN254_Snarks].fromHex("0x12345678FF11FFAA00321321CAFECAFE")

testName(Fp[BN254_Snarks], 32, a)
