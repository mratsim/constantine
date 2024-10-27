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

proc testName[Name: static Algebra](field: type FF[Name], wordSize: int, a, b: FF[Name]) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(field, wordSize)
  let kernel = nv.compile(genFpMul)

  block Logic:
    # For CPU:
    var rCPU: field
    rCPU = a * b

    # For GPU:
    var rGPU: field
    kernel.execCuda(res = [rGPU], inputs = [a, b])

    echo "CPU = ", rCPU.toHex()
    echo "GPU = ", rGPU.toHex()
    doAssert bool(rCPU == rGPU)

let a = Fp[BN254_Snarks].fromUInt(1'u32)
let b = Fp[BN254_Snarks].fromHex("0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a")

testName(Fp[BN254_Snarks], 32, a, b)

# We get incorrect result for modular multiplication with 64-bit limbs due to a fused-multiuply-add with carry bug.
#
# - https://gist.github.com/mratsim/a34df1e091925df15c13208df7eda569#file-mul-py
# - https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067