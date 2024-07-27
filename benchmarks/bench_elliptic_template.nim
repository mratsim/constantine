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
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_bigints,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended,
    ec_shortweierstrass_batch_ops,
    ec_scalar_mul],
    constantine/named/zoo_subgroups,
  # Helpers
  helpers/prng_unsafe,
  ./platforms,
  ./bench_blueprint,
  # Reference unsafe scalar multiplication
  constantine/math/elliptic/ec_scalar_mul_vartime

export notes
export abstractions # generic sandwich on SecretBool and SecretBool in Jacobian sum
export bench_blueprint

proc separator*() = separator(179)

macro fixEllipticDisplay(EC: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = EC.getTypeInst()
  var name = $instantiated[1][0] # EllipticEquationFormCoordinates
  let fieldName = $instantiated[1][1][0]
  let curve = Algebra(instantiated[1][1][1].intVal)
  let curveName = $curve
  name.add "[" &
      fieldName & "[" & curveName & "]" &
      (if family(curve) != NoFamily:
        ", " & $Subgroup(instantiated[1][2].intVal)
      else: "") &
      "]"
  result = newLit name

proc report(op, elliptic: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<68} {elliptic:<36} {throughput:>15.3f} ops/s {ns:>16} ns/op {(stopClk - startClk) div iters:>12} CPU cycles (approx)"
  else:
    echo &"{op:<68} {elliptic:<36} {throughput:>15.3f} ops/s {ns:>16} ns/op"

template bench*(op: string, EC: typedesc, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixEllipticDisplay(EC), startTime, stopTime, startClk, stopClk, iters)

func `+=`[F; G: static Subgroup](P: var EC_ShortW_JacExt[F, G], Q: EC_ShortW_JacExt[F, G]) {.inline.}=
  P.sum_vartime(P, Q)
func `+=`[F; G: static Subgroup](P: var EC_ShortW_JacExt[F, G], Q: EC_ShortW_Aff[F, G]) {.inline.}=
  P.mixedSum_vartime(P, Q)

proc addBench*(EC: typedesc, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  let Q = rng.random_unsafe(EC)

  when EC is EC_ShortW_JacExt:
    bench("EC Add vartime " & $EC.G, EC, iters):
      r.sum_vartime(P, Q)
  else:
    block:
      bench("EC Add " & $EC.G, EC, iters):
        r.sum(P, Q)
    block:
      bench("EC Add vartime " & $EC.G, EC, iters):
        r.sum_vartime(P, Q)

proc mixedAddBench*(EC: typedesc, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  let Q = rng.random_unsafe(EC)
  var Qaff: EC_ShortW_Aff[EC.F, EC.G]
  Qaff.affine(Q)

  when EC is EC_ShortW_JacExt:
    bench("EC Mixed Addition vartime " & $EC.G, EC, iters):
      r.mixedSum_vartime(P, Qaff)
  else:
    block:
      bench("EC Mixed Addition " & $EC.G, EC, iters):
        r.mixedSum(P, Qaff)
    block:
      bench("EC Mixed Addition vartime " & $EC.G, EC, iters):
        r.mixedSum_vartime(P, Qaff)

proc doublingBench*(EC: typedesc, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  bench("EC Double " & $EC.G, EC, iters):
    r.double(P)

proc affFromProjBench*(EC: typedesc, iters: int) {.noinline.} =
  var r {.noInit.}: EC_ShortW_Aff[EC.F, EC.G]
  let P = rng.random_unsafe(EC)
  bench("EC Projective to Affine " & $EC.G, EC, iters):
    r.affine(P)

proc affFromJacBench*(EC: typedesc, iters: int) {.noinline.} =
  var r {.noInit.}: EC_ShortW_Aff[EC.F, EC.G]
  let P = rng.random_unsafe(EC)
  bench("EC Jacobian to Affine " & $EC.G, EC, iters):
    r.affine(P)

proc affFromProjBatchBench*(EC: typedesc, numPoints: int, useBatching: bool, iters: int) {.noinline.} =
  var r = newSeq[affine(EC)](numPoints)
  var points = newSeq[EC](numPoints)

  for i in 0 ..< numPoints:
    points[i] = rng.random_unsafe(EC)

  if useBatching:
    bench("EC Projective to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
  else:
    bench("EC Projective to Affine - unbatched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      for i in 0 ..< numPoints:
        r[i].affine(points[i])

proc affFromJacBatchBench*(EC: typedesc, numPoints: int, useBatching: bool, iters: int) {.noinline.} =
  var r = newSeq[affine(EC)](numPoints)
  var points = newSeq[EC](numPoints)

  for i in 0 ..< numPoints:
    points[i] = rng.random_unsafe(EC)

  if useBatching:
    bench("EC Jacobian to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
  else:
    bench("EC Jacobian to Affine - unbatched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      for i in 0 ..< numPoints:
        r[i].affine(points[i])

proc scalarMulGenericBench*(EC: typedesc, bits, window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (window-" & $window & ", constant-time)", EC, iters):
    r = P
    r.scalarMulGeneric(exponent, window)

proc scalarMulEndo*(EC: typedesc, bits: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (constant-time, endomorphism)", EC, iters):
    r = P
    r.scalarMulEndo(exponent)

proc scalarMulEndoWindow*(EC: typedesc, bits: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (constant-time, window-2, endomorphism)", EC, iters):
    r = P
    when EC.F is Fp:
      r.scalarMulGLV_m2w2(exponent)
    else:
      {.error: "Not implemented".}

proc scalarMulVartimeDoubleAddBench*(EC: typedesc, bits: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (vartime reference DoubleAdd)", EC, iters):
    r = P
    r.scalarMul_doubleAdd_vartime(exponent)

proc scalarMulVartimeMinHammingWeightRecodingBench*(EC: typedesc, bits: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (vartime min Hamming Weight recoding)", EC, iters):
    r = P
    r.scalarMul_jy00_vartime(exponent)

proc scalarMulVartimeWNAFBench*(EC: typedesc, bits, window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (vartime wNAF-" & $window & ")", EC, iters):
    r = P
    r.scalarMul_wNAF_vartime(exponent, window)

proc scalarMulVartimeEndoWNAFBench*(EC: typedesc, bits, window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC ScalarMul " & $bits & "-bit " & $EC.G & " (vartime endomorphism + wNAF-" & $window & ")", EC, iters):
    r = P
    r.scalarMulEndo_wNAF_vartime(exponent, window)

proc subgroupCheckBench*(EC: typedesc, iters: int) {.noinline.} =
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("Subgroup check", EC, iters):
    discard P.isInSubgroup()

proc subgroupCheckScalarMulVartimeEndoWNAFBench*(EC: typedesc, bits, window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  let exponent = rng.random_unsafe(BigInt[bits])

  bench("EC subgroup check + ScalarMul " & $bits & "-bit " & $EC.G & " (vartime endo + wNAF-" & $window & ")", EC, iters):
    r = P
    discard r.isInSubgroup()
    r.scalarMulEndo_wNAF_vartime(exponent, window)

proc multiAddBench*(EC: typedesc, numPoints: int, useBatching: bool, iters: int) {.noinline.} =
  var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](numPoints)

  for i in 0 ..< numPoints:
    points[i] = rng.random_unsafe(EC_ShortW_Aff[EC.F, EC.G])

  var r{.noInit.}: EC

  if useBatching:
    bench("EC Multi Add batched                  " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.sum_reduce_vartime(points)
  else:
    bench("EC Multi Mixed-Add unbatched          " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      r.setNeutral()
      for i in 0 ..< numPoints:
        r += points[i]


proc msmBench*(EC: typedesc, numPoints: int, iters: int) {.noinline.} =
  const bits = EC.getScalarField().bits()
  var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](numPoints)
  var scalars = newSeq[BigInt[bits]](numPoints)

  for i in 0 ..< numPoints:
    var tmp = rng.random_unsafe(EC)
    tmp.clearCofactor()
    points[i].affine(tmp)
    scalars[i] = rng.random_unsafe(BigInt[bits])

  var r{.noInit.}: EC
  var startNaive, stopNaive, startMSMbaseline, stopMSMbaseline, startMSMopt, stopMSMopt: MonoTime

  if numPoints <= 100000:
    bench("EC scalar muls                " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startNaive = getMonotime()
      var tmp: EC
      r.setNeutral()
      for i in 0 ..< points.len:
        tmp.fromAffine(points[i])
        tmp.scalarMul(scalars[i])
        r += tmp
      stopNaive = getMonotime()

  block:
    bench("EC multi-scalar-mul baseline  " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startMSMbaseline = getMonotime()
      r.multiScalarMul_reference_vartime(scalars, points)
      stopMSMbaseline = getMonotime()

  block:
    bench("EC multi-scalar-mul optimized " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startMSMopt = getMonotime()
      r.multiScalarMul_vartime(scalars, points)
      stopMSMopt = getMonotime()

  let perfNaive = inNanoseconds((stopNaive-startNaive) div iters)
  let perfMSMbaseline = inNanoseconds((stopMSMbaseline-startMSMbaseline) div iters)
  let perfMSMopt = inNanoseconds((stopMSMopt-startMSMopt) div iters)

  if numPoints <= 100000:
    let speedupBaseline = float(perfNaive) / float(perfMSMbaseline)
    echo &"Speedup ratio baseline over naive linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = float(perfNaive) / float(perfMSMopt)
    echo &"Speedup ratio optimized over naive linear combination: {speedupOpt:>6.3f}x"

  let speedupOptBaseline = float(perfMSMbaseline) / float(perfMSMopt)
  echo &"Speedup ratio optimized over baseline linear combination: {speedupOptBaseline:>6.3f}x"
