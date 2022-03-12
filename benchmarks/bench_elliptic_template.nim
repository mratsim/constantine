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
  ../src/constantine/platforms/abstractions,
  ../src/constantine/math/config/curves,
  ../src/constantine/math/arithmetic,
  ../src/constantine/math/io/io_bigints,
  ../src/constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_scalar_mul, ec_endomorphism_accel],
  # Helpers
  ../helpers/[prng_unsafe, static_for],
  ./platforms,
  ./bench_blueprint,
  # Reference unsafe scalar multiplication
  ../tests/math/support/ec_reference_scalar_mult

export notes
proc separator*() = separator(177)

macro fixEllipticDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curveName = $Curve(instantiated[1][1][1].intVal)
  name.add "[" & fieldName & "[" & curveName & "]]"
  result = newLit name

proc report(op, elliptic: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {elliptic:<40} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, T: typedesc, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixEllipticDisplay(T), startTime, stopTime, startClk, stopClk, iters)

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

proc affFromProjBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: ECP_ShortW_Aff[T.F, T.G]
  let P = rng.random_unsafe(T)
  bench("EC Projective to Affine " & G1_or_G2, T, iters):
    r.affine(P)

proc affFromJacBench*(T: typedesc, iters: int) =
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"
  var r {.noInit.}: ECP_ShortW_Aff[T.F, T.G]
  let P = rng.random_unsafe(T)
  bench("EC Jacobian to Affine " & G1_or_G2, T, iters):
    r.affine(P)

proc scalarMulGenericBench*(T: typedesc, window: static int, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & G1_or_G2 & " (window-" & $window & ", generic)", T, iters):
    r = P
    r.scalarMulGeneric(exponent, window)

proc scalarMulEndo*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & G1_or_G2 & " (endomorphism accelerated)", T, iters):
    r = P
    r.scalarMulEndo(exponent)

proc scalarMulEndoWindow*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & G1_or_G2 & " (window-2, endomorphism accelerated)", T, iters):
    r = P
    when T.F is Fp:
      r.scalarMulGLV_m2w2(exponent)
    else:
      {.error: "Not implemented".}

proc scalarMulUnsafeDoubleAddBench*(T: typedesc, iters: int) =
  const bits = T.F.C.getCurveOrderBitwidth()
  const G1_or_G2 = when T.F is Fp: "G1" else: "G2"

  var r {.noInit.}: T
  let P = rng.random_unsafe(T) # TODO: clear cofactor

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & G1_or_G2 & " (unsafe reference DoubleAdd)", T, iters):
    r = P
    r.unsafe_ECmul_double_add(exponent)
