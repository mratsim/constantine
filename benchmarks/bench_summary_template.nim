# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Summary of the performance of a curve
#
# ############################################################

import
  # Internals
  ../constantine/platforms/abstractions,
  ../constantine/math/config/curves,
  ../constantine/math/[arithmetic, extension_fields],
  ../constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_scalar_mul, ec_endomorphism_accel],
  ../constantine/math/curves/zoo_subgroups,
  ../constantine/math/pairing/[
    cyclotomic_subgroup,
    pairing_bls12,
    pairing_bn
  ],
  ../constantine/math/curves/zoo_pairings,
  ../constantine/hashes,
  ../constantine/hash_to_curve/hash_to_curve,
  # Helpers
  ../helpers/[prng_unsafe, static_for],
  ./bench_blueprint

export
  ec_shortweierstrass_projective,
  ec_shortweierstrass_jacobian

export abstractions # generic sandwich on SecretBool and SecretBool in Jacobian sum
export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225
export notes
proc separator*() = separator(152)

proc report(op, domain: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<35} {domain:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<35} {domain:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixEllipticDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Curve(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
  result = newLit name

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Curve(instantiated[1][1].intVal) & "]"
  result = newLit name

func fixDisplay(T: typedesc): string =
  when T is (ECP_ShortW_Prj or ECP_ShortW_Jac or ECP_ShortW_Aff):
    fixEllipticDisplay(T)
  elif T is (Fp or Fp2 or Fp4 or Fp6 or Fp12):
    fixFieldDisplay(T)
  else:
    $T

func fixDisplay(T: Curve): string =
  $T

template bench(op: string, T: typed, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixDisplay(T), startTime, stopTime, startClk, stopClk, iters)

func clearCofactorReference[F; G: static Subgroup](
       ec: var ECP_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: ECP_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactorReference()
  ec.affine(t)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactorReference()

proc mulBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  let y = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Multiplication", T, iters):
    r.prod(x, y)

proc sqrBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Squaring", T, iters):
    r.square(x)

proc invBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_unsafe(T)
  preventOptimAway(r)
  bench("Inversion", T, iters):
    r.inv(x)

proc sqrtBench*(T: typedesc, iters: int) =
  let x = rng.random_unsafe(T)
  bench("Square Root + isSquare", T, iters):
    var r = x
    discard r.sqrt_if_square()

proc addBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  let Q = rng.random_unsafe(T)
  bench("EC Add " & G1_or_G2, T, iters):
    r.sum(P, Q)

proc mixedAddBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  let Q = rng.random_unsafe(T)
  var Qaff: ECP_ShortW_Aff[T.F, T.G]
  Qaff.affine(Q)
  bench("EC Mixed Addition " & G1_or_G2, T, iters):
    r.madd(P, Qaff)

proc doublingBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: T
  let P = rng.random_unsafe(T)
  bench("EC Double " & G1_or_G2, T, iters):
    r.double(P)

proc scalarMulBench*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor
  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & G1_or_G2, T, iters):
    r = P
    when T.F is Fp:
      r.scalarMulGLV_m2w2(exponent)
    else:
      r.scalarMulEndo(exponent)

proc millerLoopBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Miller Loop BLS12", C, iters):
    f.millerLoopGenericBLS12(P, Q)

proc millerLoopBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Miller Loop BN", C, iters):
    f.millerLoopGenericBN(P, Q)

proc finalExpBLS12Bench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation BLS12", C, iters):
    r.finalExpEasy()
    r.finalExpHard_BLS12()

proc finalExpBNBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation BN", C, iters):
    r.finalExpEasy()
    r.finalExpHard_BN()

proc pairingBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Pairing BLS12", C, iters):
    f.pairing_bls12(P, Q)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)

proc hashToCurveBLS12381G1Bench*(iters: int) =
  # Hardcode BLS12_381
  # otherwise concept symbol
  # 'CryptoHash' resolution issue
  const dst = "BLS_SIG_BLS12381G1-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"
  var P: ECP_ShortW_Prj[Fp[BLS12_381], G1]

  bench("Hash to G1 (SSWU - Draft #14)", BLS12_381, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc hashToCurveBLS12381G2Bench*(iters: int) =
  # Hardcode BLS12_381
  # otherwise concept symbol
  # 'CryptoHash' resolution issue
  const dst = "BLS_SIG_BLS12381G2-SHA256-SSWU-RO_POP_"
  let msg = "Mr F was here"
  var P: ECP_ShortW_Prj[Fp2[BLS12_381], G2]

  bench("Hash to G2 (SSWU - Draft #14)", BLS12_381, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )


proc hashToCurveBN254SnarksG1Bench*(iters: int) =
  # Hardcode BN254_Snarks
  # otherwise concept symbol
  # 'CryptoHash' resolution issue
  const dst = "BLS_SIG_BN254SNARKSG1-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"
  var P: ECP_ShortW_Prj[Fp[BN254_Snarks], G1]

  bench("Hash to G1 (SVDW - Draft #14)", BN254_Snarks, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

proc hashToCurveBN254SnarksG2Bench*(iters: int) =
  # Hardcode BN254_Snarks
  # otherwise concept symbol
  # 'CryptoHash' resolution issue
  const dst = "BLS_SIG_BN254SNARKSG2-SHA256-SVDW-RO_POP_"
  let msg = "Mr F was here"
  var P: ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]

  bench("Hash to G2 (SVDW - Draft #14)", BN254_Snarks, iters):
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )
