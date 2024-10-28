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
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_jacobian],
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, pub_curves_jacobian, codegen_nvidia, impl_fields_globals],
  # Test utilities
  helpers/prng_unsafe

type
  EC = EC_ShortW_Jac[Fp[BN254_Snarks], G1]
  ECAff = EC_ShortW_Aff[Fp[BN254_Snarks], G1]
const wordSize = 32

let x = "0x2ef34a5db00ff691849861d49415d8081d9d0e10cba33b57b2dd1f37f13eeee0"
let y = "0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a"
let pt = EC.fromHex(x, y)
echo pt.toHex()

let x2 = "0x226c85cf65f4596a77da7d247310a81ac9aa9220e819e3ef23b6cbe0218ce272"
let y2 = "0xf53265870f65aa18bded3ccb9c62a4d8b060a32a05a75d455710bce95a991df"
let pt2 = EC.fromHex(x2, y2)

block Neg:
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC, wordSize)
  let kernel = nv.compile(genEcNeg)

  # For CPU:
  var rCPU = pt
  rCPU.neg()

  # For GPU:
  var rGPU = pt
  kernel.execCuda(res = rGPU)

  # Verify CPU and GPU agree
  doAssert bool(rCPU == rGPU)

block CNeg:
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC, wordSize)
  let kernel = nv.compile(genEcCNeg)

  block True:
    let c = false
    # For CPU:
    var rCPU = pt
    rCPU.cneg(SecretBool c)

    # For GPU:
    var rGPU = pt
    kernel.execCuda(res = rGPU, inputs = c)

    # Verify CPU and GPU agree
    doAssert bool(rCPU == rGPU)

  block False:
    let c = true
    # For CPU:
    var rCPU = pt
    rCPU.cneg(SecretBool c)

    # For GPU:
    var rGPU = pt
    kernel.execCuda(res = rGPU, inputs = c)

    # Verify CPU and GPU agree
    doAssert bool(rCPU == rGPU)

block Double:
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC, wordSize)
  let kernel = nv.compile(genEcDouble)

  # For CPU:
  var rCPU: typeof(pt)
  rCPU.double(pt)

  # For GPU:
  var rGPU: typeof(pt)
  kernel.execCuda(res = rGPU, inputs = pt)

  echo "CPU: ", rCPU.toHex()
  echo "GPU: ", rGPU.toHex()

  # Verify CPU and GPU agree
  doAssert bool(rCPU == rGPU)

block AffineToJac:
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC, wordSize)
  let kernel = nv.compile(genEcFromAffine)

  var ptAff: ECAff
  ptAff.affine(pt)

  var rCPU: typeof(pt)
  rCPU.fromAffine(ptAff)

  # For GPU:
  var rGPU: typeof(pt)
  kernel.execCuda(res = rGPU, inputs = pt)

  echo "CPU: ", rCPU.toHex()
  echo "GPU: ", rGPU.toHex()

  # Verify CPU and GPU agree
  #doAssert ptAff != pt # verify equality of points does not exist for different
  doAssert bool(rCPU == rGPU)

block SetNeutral:
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC, wordSize)
  let kernel = nv.compile(genEcSetNeutral)

  var rCPU: typeof(pt) = pt
  rCPU.setNeutral()

  # For GPU:
  var rGPU: typeof(pt) = pt
  kernel.execCuda(rGPU)

  echo "CPU: ", rCPU.toHex()
  echo "GPU: ", rGPU.toHex()

  # Verify CPU and GPU agree
  doAssert bool(rCPU == rGPU)
