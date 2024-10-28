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

block:
  var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321CAFECAFE")
  let b = fromHex(BigInt[128], "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

  var expected = a
  a.ccopy(b, CtFalse)

  doAssert bool(expected == a)

block:
  var a = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFF")
  let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")

  var expected = b
  a.ccopy(b, CtTrue)

  doAssert bool(expected == b)

proc testName[Name: static Algebra](field: type FF[Name], wordSize: int, a, b: FF[Name]) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(field, wordSize)
  let kernel = nv.compile(genFpCcopy)

  template executeCompare(cond): untyped {.dirty.} =
    var rCPU, rGPU: field
    rCPU = a
    rGPU = a

    rCPU.ccopy(b, SecretBool(cond))

    let c = cond # needs to be a runtime value so that it has an address!
    kernel.execCuda(res = rGPU, inputs = (b, c))

    echo "CPU = ", rCPU.toHex()
    echo "GPU = ", rGPU.toHex()
    doAssert bool(rCPU == rGPU)

  block True:
    executeCompare(true)
  block False:
    executeCompare(false)


let a = Fp[BN254_Snarks].fromHex("0x12345678FF11FFAA00321321CAFECAFE")
let b = Fp[BN254_Snarks].fromHex("0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")


testName(Fp[BN254_Snarks], 32, a, b)
