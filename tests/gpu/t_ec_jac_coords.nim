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
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/arithmetic,
  constantine/math/elliptic/ec_shortweierstrass_jacobian,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, pub_curves, codegen_nvidia, impl_fields_globals],
  # Test utilities
  helpers/prng_unsafe

template genGetComponent*(asy: Assembler_LLVM, ed: CurveDescriptor, fn: typed): string =
  let name = ed.name & astToStr(fn)
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.fd.fieldTy, ed.curveTy]):
    let M = asy.getModulusPtr(ed.fd)
    let (r, a) = llvmParams

    let ec = asy.asEcPoint(a, ed.curveTy)
    let rA = asy.asField(r, ed.fd.fieldTy)

    let x = fn(ec)
    asy.store(rA, x)

    asy.br.retVoid()
  name

proc genGetX*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getX)
proc genGetY*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getY)
proc genGetZ*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getZ)

template test[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1], fn, cpuField: untyped): untyped =
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC_ShortW_Jac[field, G1], wordSize)
  let kernel = nv.compile(fn)

  # For CPU:
  var rCPU: field
  rCPU = a.cpuField

  # For GPU:
  var rGPU: field
  kernel.execCuda(rGPU, a)

  echo "Input: ", a.toHex()
  echo "CPU:   ", rCPU.toHex()
  echo "GPU:   ", rGPU.toHex()
  doAssert bool(rCPU == rGPU)

proc testX[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetX, x)
proc testY[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetY, y)
proc testZ[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetZ, z)

let x = "0x2ef34a5db00ff691849861d49415d8081d9d0e10cba33b57b2dd1f37f13eeee0"
let y = "0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a"
let pt = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x, y)
echo pt.toHex()

testX(Fp[BN254_Snarks], 64, pt)
testY(Fp[BN254_Snarks], 64, pt)
testZ(Fp[BN254_Snarks], 64, pt)
