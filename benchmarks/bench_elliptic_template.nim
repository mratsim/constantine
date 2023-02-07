# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of elliptic curves
#
# ############################################################

import
  # Internals
  ../constantine/platforms/abstractions,
  ../constantine/math/config/curves,
  ../constantine/math/arithmetic,
  ../constantine/math/io/io_bigints,
  ../constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_batch_ops,
    ec_scalar_mul, ec_endomorphism_accel],
    ../constantine/math/constants/zoo_subgroups,
  # Helpers
  ../helpers/prng_unsafe,
  ./platforms,
  ./bench_blueprint,
  # Reference unsafe scalar multiplication
  ../tests/math/support/ec_reference_scalar_mult

export notes
export abstractions # generic sandwich on SecretBool and SecretBool in Jacobian sum

proc separator*() = separator(206)

macro fixEllipticDisplay(EC: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = EC.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Curve(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
  result = newLit name

proc report(op, elliptic: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<80} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>12} ns/op     {(stopClk - startClk) div iters:>12} CPU cycles (approx)"
  else:
    echo &"{op:<80} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>12} ns/op"

template bench*(op: string, EC: typedesc, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixEllipticDisplay(EC), startTime, stopTime, startClk, stopClk, iters)

proc addBench*(EC: typedesc, iters: int) =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  let Q = rng.random_unsafe(EC)
  bench("EC Add " & $EC.G, EC, iters):
    r.sum(P, Q)

proc mixedAddBench*(EC: typedesc, iters: int) =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  let Q = rng.random_unsafe(EC)
  var Qaff: ECP_ShortW_Aff[EC.F, EC.G]
  Qaff.affine(Q)
  bench("EC Mixed Addition " & $EC.G, EC, iters):
    r.madd(P, Qaff)

proc doublingBench*(EC: typedesc, iters: int) =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  bench("EC Double " & $EC.G, EC, iters):
    r.double(P)

proc affFromProjBench*(EC: typedesc, iters: int) =
  var r {.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
  let P = rng.random_unsafe(EC)
  bench("EC Projective to Affine " & $EC.G, EC, iters):
    r.affine(P)

proc affFromJacBench*(EC: typedesc, iters: int) =
  var r {.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
  let P = rng.random_unsafe(EC)
  bench("EC Jacobian to Affine " & $EC.G, EC, iters):
    r.affine(P)

proc scalarMulGenericBench*(EC: typedesc, window: static int, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (window-" & $window & ", generic)", EC, iters):
    r = P
    r.scalarMulGeneric(exponent, window)

proc scalarMulEndo*(EC: typedesc, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (endomorphism accelerated)", EC, iters):
    r = P
    r.scalarMulEndo(exponent)

proc scalarMulEndoWindow*(EC: typedesc, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (window-2, endomorphism accelerated)", EC, iters):
    r = P
    when EC.F is Fp:
      r.scalarMulGLV_m2w2(exponent)
    else:
      {.error: "Not implemented".}

proc scalarMulUnsafeDoubleAddBench*(EC: typedesc, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (unsafe reference DoubleAdd)", EC, iters):
    r = P
    r.unsafe_ECmul_double_add(exponent)

proc scalarMulUnsafeMinHammingWeightRecodingBench*(EC: typedesc, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (unsafe min Hamming Weight recoding)", EC, iters):
    r = P
    r.unsafe_ECmul_minHammingWeight(exponent)

proc multiAddBench*(EC: typedesc, numPoints: int, useBatching: bool, iters: int) =
  var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](numPoints)

  for i in 0 ..< numPoints:
    points[i] = rng.random_unsafe(ECP_ShortW_Aff[EC.F, EC.G])

  var r{.noInit.}: EC

  if useBatching:
    bench("EC Multi Add batched                  " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.sum_batch_vartime(points)
  else:
    bench("EC Multi Mixed-Add unbatched          " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.setInf()
      for i in 0 ..< numPoints:
        r += points[i]
