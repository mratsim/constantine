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
    ec_multi_scalar_mul_precomp,
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
export arithmetic # generic sandwich with square from zoo_subgroups

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

# ############################################################
#
#               Primitive operations
#
# ############################################################

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
    block:
      bench("EC Projective to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
        r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
    block:
      bench("EC Projective to Affine -   batched_vt " & $EC.G & " (" & $numPoints & " points)", EC, iters):
        r.asUnchecked().batchAffine_vartime(points.asUnchecked(), numPoints)
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
    block:
      bench("EC Jacobian to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
        r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
    block:
      bench("EC Jacobian to Affine -   batched_vt " & $EC.G & " (" & $numPoints & " points)", EC, iters):
        r.asUnchecked().batchAffine_vartime(points.asUnchecked(), numPoints)
  else:
    bench("EC Jacobian to Affine - unbatched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
      for i in 0 ..< numPoints:
        r[i].affine(points[i])


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

# ############################################################
#
#               Scalar Multiplication
#
# ############################################################

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

# ############################################################
#
#               Multi Scalar Multiplication
#
# ############################################################

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

# ############################################################
#
#             Precomputed Multi Scalar Multiplication
#
# ############################################################


type
  PrecompBenchContext[EC; N, t, b: static int] = ref object
    precomp: PrecomputedMSM[EC, N, t, b]
    basisJac: seq[EC]
    basis: seq[EC.affine]
    scalars: seq[BigInt[EC.getScalarField().bits()]]
    rng: RngState
    precompTimeMs: float64
    precompMemMiB: float64


proc benchPrecompMSM[EC; N, t, b: static int](
      ctx: PrecompBenchContext[EC, N, t, b],
      iters: int) {.noinline.}=
  const bits = EC.getScalarField().bits()
  var result: EC

  # Track actual operation counts from runtime
  var totalOps: tuple[add, dbl: int]

  # Manual benchmark to control output format
  let start = getMonotime()
  when SupportsGetTicks:
    let startClk = getTicks()

  for _ in 0..<iters:
    let ops = ctx.precomp.msm_vartime(result, ctx.scalars)
    totalOps.add += ops.add
    totalOps.dbl += ops.dbl

  when SupportsGetTicks:
    let stopClk = getTicks()
  let stop = getMonotime()

  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  let cycles = (stopClk - startClk) div iters

  # Average ops per iteration
  let avgDbl = totalOps.dbl div iters
  let avgAdd = totalOps.add div iters

  # Estimated ops for comparison
  let (estAdd, estDbl) = msmPrecompEstimateOps(EC, N, t, b)

  let configStr = fmt"t={t:>3}, b={b:>2}"
  let c1 = (align(fmt"{ctx.precompTimeMs:7.3f} ms", 12), "  ",
    align(fmt"{ctx.precompMemMiB:6.2f} MiB", 10), "  ",
    align(fmt"{throughput:10.3f}", 12), "  ",
    align(fmt"{ns:10}", 12))
  let ops = (align(fmt"{avgDbl:3}", 6), " (", align(fmt"{estDbl:3}", 3), ")", "      ",
    align(fmt"{avgAdd:5}", 7), " (", align(fmt"{estAdd:5}", 4), ")")

  when SupportsGetTicks:
    echo align(configStr, 20), "  ", c1, "  ", align(fmt"{cycles:10}", 14), "  ", ops
  else:
    echo align(configStr, 20), "  ", c1, ops

proc benchPrecompMSMTable[EC](
        _: typedesc[EC],
        N: static int,
        iters: int,
        precompConfigs: static openarray[tuple[t, b: int]]) =
  ## Run precomputed MSM benchmarks for a given curve and MSM size
  const bits = EC.getScalarField().bits()

  separator(130)
  echo "MSM Size: " & $N & " points"
  separator(130)
  echo ""

  # Column headers
  echo align("Config", 20), "  ",
       align("Precomp", 12), "  ",
       align("Memory", 10), "  ",
       align("Ops/s", 12), "  ",
       align("ns/op", 12), "  ",
       align("Cycles", 14), "  ",
       align("Dbl real (est)", 16), "  ",
       align("Add real (est)", 16)
  echo repeat('-', 130)

  proc doBench(_: typedesc[EC], N, t, b: static int, iters: int) {.noInline.} =
    # Wrap in a proc to ensure destruction of the large context
    let ctx = new(PrecompBenchContext[EC, N, t, b], seed = 42'u64)
    ctx.benchPrecompMSM(iters div max(1, N div 10))

  staticFor cfgIdx, 0, precompConfigs.len:
    const (t, b) = precompConfigs[cfgIdx]
    doBench(EC, N, t, b, iters)

  echo ""
  echo "Reference MSM (no precomputation):"
  var rng2: RngState
  rng2.seed(42)
  var basisJac2 = newSeq[EC](N)
  var basis2 = newSeq[EC.affine()](N)
  var scalars2 = newSeq[BigInt[bits]](N)

  for i in 0 ..< N:
    basisJac2[i] = rng2.random_unsafe(EC)
    basisJac2[i].clearCofactor()

  basis2.asUnchecked().batchAffine_vartime(basisJac2.asUnchecked(), N)

  for i in 0 ..< N:
    scalars2[i] = rng2.random_unsafe(BigInt[bits])

  var refResult: EC
  let start2 = getMonotime()
  for _ in 0 ..< iters div max(1, N div 10):
    refResult.multiScalarMul_vartime(scalars2, basis2)
  let stop2 = getMonotime()

  let ns2 = inNanoseconds((stop2-start2) div (iters div max(1, N div 10)))
  let throughput2 = 1e9 / float64(ns2)
  echo align("Reference MSM", 20), "  ",
       align("-", 12), "  ",
       align("-", 10), "  ",
       align(fmt"{throughput2:10.3f}", 12), "  ",
       align(fmt"{ns2:10}", 12)
  echo ""


proc runPrecompMSMBench*[EC](
      _: typedesc[EC],
      listNumPoints: static openArray[int],
      precompConfigs: static openarray[tuple[t, b: int]],
      iters: int) =
  ## Run complete precomputed MSM benchmark suite for a curve
  separator(130)
  echo "Precomputed MSM Benchmark"
  separator(130)
  echo ""
  echo "Legend: t = stride (bits between precomp powers), b = window size (bits per bucket)"
  echo ""

  staticFor i, 0, listNumPoints.len:
    const N = listNumPoints[i]
    benchPrecompMSMTable(EC, N, iters, precompConfigs)

  separator(130)
  echo "Benchmark complete"
  echo "Lower ns/op and Cycles is better. Higher Ops/s is better."
