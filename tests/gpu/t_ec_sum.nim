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
  constantine/math/elliptic/[ec_shortweierstrass_jacobian, ec_shortweierstrass_affine],
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, pub_curves_jacobian, codegen_nvidia, impl_fields_globals],
  # Test utilities
  helpers/prng_unsafe

proc testSum[Name: static Algebra](field: type FF[Name], wordSize: int,
                                   a, b: EC_ShortW_Jac[field, G1]) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC_ShortW_Jac[field, G1], wordSize)
  let kernel = nv.compile(genEcSum)

  template checkSum(a, b): untyped =
    # For CPU:
    var rCPU: EC_ShortW_Jac[field, G1]
    rCPU = a + b

    # For GPU:
    var rGPU: EC_ShortW_Jac[field, G1]
    kernel.execCuda(res = rGPU, inputs = (a, b))

    # Verify CPU and GPU agree
    doAssert bool(rCPU == rGPU)

    # return point
    rGPU
  var res = a
  for i in 0 ..< 1000: # `res = res + b`, starting with `a + b`
    res = checkSum(res, b)

proc testMixedSum[Name: static Algebra](field: type FF[Name], wordSize: int,
                                        a: EC_ShortW_Jac[field, G1], b: EC_ShortW_Aff[field, G1]) =
  # Codegen
  # -------------------------
  let nv = initNvAsm(EC_ShortW_Jac[field, G1], wordSize)
  let kernel = nv.compile(genEcMixedSum)

  template checkSum(a, b): untyped =
    # For CPU:
    var rCPU: EC_ShortW_Jac[field, G1]
    rCPU = a + b

    # For GPU:
    var rGPU: EC_ShortW_Jac[field, G1]
    kernel.execCuda(res = rGPU, inputs = (a, b))

    # Verify CPU and GPU agree
    doAssert bool(rCPU == rGPU)

    # return point
    rGPU
  var res = a
  for i in 0 ..< 1000: # `res = res + b`, starting with `a + b`
    res = checkSum(res, b)


let x = "0x2ef34a5db00ff691849861d49415d8081d9d0e10cba33b57b2dd1f37f13eeee0"
let y = "0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a"
let pt = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x, y)
echo pt.toHex()

let x2 = "0x226c85cf65f4596a77da7d247310a81ac9aa9220e819e3ef23b6cbe0218ce272"
let y2 = "0xf53265870f65aa18bded3ccb9c62a4d8b060a32a05a75d455710bce95a991df"
let pt2 = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x2, y2)

## If `skipFinalSub` is set to `true` in the EC sum implementation
##   `S1.prod(Q.z, Z2Z2, skipFinalSub = true)`
## the following fails at iteration 57.
testSum(Fp[BN254_Snarks], 32, pt, pt2)

var pt2Aff: EC_ShortW_Aff[Fp[BN254_Snarks], G1]
pt2Aff.affine(pt2)

testMixedSum(Fp[BN254_Snarks], 32, pt, pt2Aff)


## NOTE: While these inputs a, b are the ones that end up causing the
## CPU / GPU mismatch:
##
## CPU: EC_ShortW_Jac[Fp[BN254_Snarks], G1](
##  x: 0x2759f36c1d1b3d32c6987871ea61f66081d8367fea7dddf86ec9affd873ed276,
##  y: 0x20ca7695cbae18fee699265b384042f168d57a2de3cf617f8b8a2db32f441645
##)
##GPU: EC_ShortW_Jac[Fp[BN254_Snarks], G1](
##  x: 0x0388614357ca250f0c57b68bffe62fb373e7b0080dc744d00306aaa3249a794b,
##  y: 0x20ca7695cbae18fee699265b384042f168d57a2de3cf617f8b8a2db32f441645
##)
##
## at iteration i = 57 with the parameters `pt`, `pt2` in `testSum` above,
## we cannot reproduce the same issue by just starting from those values.
## This seems to imply some kind of 'state' of the code affecting the result.
## Both produce the CPU result in this case.

block SkipFinalSubIssue:
  let x = "0x04abee794a3361abc8ae74599ac1e3dfa2c10cefec9a1a6db22933c1fc1a6cc6"
  let y = "0x1834122923169e8bec29a59103682846f4caf5fb3694a811ed1f66c823b3bd20"
  let a = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x, y)

  let x2 = "0x226c85cf65f4596a77da7d247310a81ac9aa9220e819e3ef23b6cbe0218ce272"
  let y2 = "0x0f53265870f65aa18bded3ccb9c62a4d8b060a32a05a75d455710bce95a991df"
  let b = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x2, y2)

  let nv = initNvAsm(EC_ShortW_Jac[Fp[BN254_Snarks], G1], 32)
  let kernel = nv.compile(genEcMixedSum)

  template checkSum(a, b): untyped =
    # For CPU:
    var rCPU: EC_ShortW_Jac[Fp[BN254_Snarks], G1]
    rCPU = a + b

    # For GPU:
    var rGPU: EC_ShortW_Jac[Fp[BN254_Snarks], G1]
    kernel.execCuda(res = rGPU, inputs = (a, b))

    echo "CPU: ", rCPU.toHex()
    echo "GPU: ", rGPU.toHex()

    # Verify CPU and GPU agree
    doAssert bool(rCPU == rGPU)

  checkSum(a, b)
