# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark results for zka.lc
#
# ############################################################

# https://zka.lc/
# https://github.com/mmaker/zkalc

import
  constantine/threadpool,
  constantine/hashes,
  constantine/lowlevel_fields,
  # constantine/lowlevel_extension_fields,
  constantine/math/extension_fields,
  constantine/lowlevel_elliptic_curves,
  constantine/lowlevel_elliptic_curves_parallel,
  constantine/lowlevel_pairing_curves,

  # Helpers
  helpers/prng_unsafe,
  # Standard library
  std/[stats, monotimes, times, strformat, strutils, os, macros],
  # Third-party
  jsony, cliche

# Workarounds generic sandwich bug in 1.6.x
from constantine/named/algebras import matchingBigInt, matchingOrderBigInt, getLimbs2x

type
  ZkalcBenchDetails = object
    `range`: seq[int]
    results: seq[float64]
    stddev: seq[float64]

  ZkalcBenchResult = object
    add_ff, mul_ff, invert: ZkalcBenchDetails
    ip_ff: ZkalcBenchDetails # ip: inner-product
    fft: ZkalcBenchDetails

    add_G1, mul_G1, msm_G1: ZkalcBenchDetails
    is_in_sub_G1: ZkalcBenchDetails
    hash_G1: ZkalcBenchDetails

    add_G2, mul_G2, msm_G2: ZkalcBenchDetails
    is_in_sub_G2: ZkalcBenchDetails
    hash_G2: ZkalcBenchDetails

    mul_Gt: ZkalcBenchDetails
    exp_Gt: ZkalcBenchDetails
    multiexp_Gt: ZkalcBenchDetails

    pairing: ZkalcBenchDetails
    multipairing: ZkalcBenchDetails

type AggStats = tuple[rs: RunningStat, batchSize: int]

# Utilities
# -------------------------------------------------------------------------------------

template bench(body: untyped): AggStats =
  const warmupMs = 100
  const batchMs = 10
  const benchMs = 5000

  block:
    var stats: RunningStat
    stats.clear()

    proc warmup(warmupMs: int): tuple[num_iters: int, elapsedNs: int64] =
      ## Warmup for the specified time and returns the number of iterations and time used
      let start = getMonotime().ticks()
      let stop = start + 1_000_000'i64*int64(warmupMs)

      var num_iters = 0

      while true:
        body

        let cur = getMonotime().ticks()
        num_iters += 1

        if cur >= stop:
          return (num_iters, cur - start)

    # Warmup and measure how many iterations are done during warmup
    let (candidateIters, elapsedNs) = warmup(warmupMs)

    # Deduce batch size for bench iterations so that each batch is atleast 10ms to amortize clock overhead
    # See https://gms.tf/on-the-costs-of-syscalls.html on clock and syscall latencies and vDSO.
    let batchSize = max(1, int(candidateIters.float64 * batchMs.float64 / warmupMs.float64))
    # Compute the number of iterations for ~5s of benchmarks
    let iters = int(
      (candidateIters.float64 / batchSize.float64) *       # Divide the computed number of iterations by the size of the batch
      max(1, benchMs.float64 / (elapsedNs.float64 * 1e-6)) # Scale by the ratio of bench time / warmup time
    )

    for _ in 0 ..< iters:
      let start = getMonotime()

      for _ in 0 ..< batchSize:
        body

      let stop = getMonotime()
      let elapsedNs = (stop.ticks() - start.ticks()) div batchSize

      # We can store integers up to 2⁵³ in a float64 without loss of precision (see also ulp)
      # 1 billion is ~ 2³⁰, so you would need 2²³ seconds = 8388608s = 13 weeks 6 days 2 hours 10 minutes 8 seconds
      stats.push(elapsedNs.int)

    (stats, batchSize)

proc report(op: string, curve: Algebra, aggStats: AggStats) =
  let avg = aggStats.rs.mean()
  let stddev = aggStats.rs.standardDeviationS() # Sample standard deviation (and not population)
  let coefvar = stddev / avg * 100 # coefficient of variation
  let throughput = 1e9 / float64(avg)
  let iters = aggStats.rs.n
  let batchSize = aggStats.batchSize
  echo &"{op:<50} {$curve:<10} {throughput:>15.3f} ops/s {avg:>15.1f} ns/op (avg)    ±{coefvar:>4.1f}% (coef var)    {iters:>4} iterations of {batchSize:>6} operations"

proc separator(length: int) =
  echo "-".repeat(length)

proc separator() = separator(174)

proc toZkalc(stats: AggStats, size = 1): ZkalcBenchDetails =
  ZkalcBenchDetails(
    `range`: @[size],
    results: @[stats.rs.mean()],
    stddev: @[stats.rs.standardDeviationS()] # Sample standard deviation (and not population)
  )

proc append(details: var ZkalcBenchDetails, stats: AggStats, size: int) =
  details.`range`.add size
  details.results.add stats.rs.mean()
  details.stddev.add  stats.rs.standardDeviationS() # Sample standard deviation (and not population)

# Prevent compiler optimizing benchmark away
# -------------------------------------------------------------------------------------
# This doesn't always work unfortunately ...

proc volatilize(x: ptr byte) {.codegenDecl: "$# $#(char const volatile *x)", inline.} =
  discard

template preventOptimAway*[T](x: var T) =
  volatilize(cast[ptr byte](addr x))

template preventOptimAway*[T](x: T) =
  volatilize(cast[ptr byte](unsafeAddr x))

# Field benches
# -------------------------------------------------------------------------------------

proc benchFrAdd(rng: var RngState, curve: static Algebra): ZkalcBenchDetails =
  var x = rng.random_unsafe(Fr[curve])
  let y = rng.random_unsafe(Fr[curve])

  preventOptimAway(x)
  preventOptimAway(y)

  let stats = bench():
    x += y

  report("𝔽r Addition", curve, stats)
  stats.toZkalc()

proc benchFrMul(rng: var RngState, curve: static Algebra): ZkalcBenchDetails =
  var x = rng.random_unsafe(Fr[curve])
  let y = rng.random_unsafe(Fr[curve])

  preventOptimAway(x)
  preventOptimAway(y)

  let stats = bench():
    x *= y

  report("𝔽r Multiplication", curve, stats)
  stats.toZkalc()

proc benchFrInv(rng: var RngState, curve: static Algebra, useVartime: bool): ZkalcBenchDetails =
  var x = rng.random_unsafe(Fr[curve])

  if useVartime:
    let stats = bench():
      x.inv_vartime()

    report("𝔽r Inversion " & align("| vartime", 28), curve, stats)
    stats.toZkalc()
  else:
    let stats = bench():
      x.inv()

    report("𝔽r Inversion " & align("| constant-time", 28), curve, stats)
    stats.toZkalc()

proc benchFrIP(rng: var RngState, curve: static Algebra): ZkalcBenchDetails =

  var r: Fr[curve]
  let a = rng.random_unsafe(Fr[curve])
  let b = rng.random_unsafe(Fr[curve])
  let u = rng.random_unsafe(Fr[curve])
  let v = rng.random_unsafe(Fr[curve])

  preventOptimAway(r)
  preventOptimAway(a)
  preventOptimAway(b)
  preventOptimAway(u)
  preventOptimAway(v)

  let stats = bench():
    r.sumprod([a, b], [u, v])

  report("𝔽r Sum of products of size 2", curve, stats)
  stats.toZkalc(2)

# EC benches
# -------------------------------------------------------------------------------------

proc benchEcAdd(rng: var RngState, EC: typedesc, useVartime: bool): ZkalcBenchDetails =
  const G =
    when EC.G == G1: "𝔾₁"
    else: "𝔾₂"
  const curve = EC.getName()

  var r {.noInit.}: EC
  let P = rng.random_unsafe(EC)
  let Q = rng.random_unsafe(EC)

  preventOptimAway(r)
  preventOptimAway(P)
  preventOptimAway(Q)

  if useVartime:
    let stats = bench():
      r.sum_vartime(P, Q)

    report(G & " Addition " & align("| vartime", 29), curve, stats)
    stats.toZkalc()
  else:
    let stats = bench():
      r.sum(P, Q)

    report(G & " Addition " & align("| constant-time", 29), curve, stats)
    stats.toZkalc()

proc benchEcMul(rng: var RngState, EC: typedesc, useVartime: bool): ZkalcBenchDetails =
  const G =
    when EC.G == G1: "𝔾₁"
    else: "𝔾₂"
  const curve = EC.getName()

  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()
  let k = rng.random_unsafe(Fr[curve].getBigInt())

  preventOptimAway(r)
  preventOptimAway(P)

  if useVartime:
    let stats = bench():
      r.scalarMul_vartime(k, P)

    report(G & " Scalar Multiplication " & align("| vartime", 16), curve, stats)
    stats.toZkalc()
  else:
    let stats = bench():
      r.scalarMul(k, P)

    report(G & " Scalar Multiplication " & align("| constant-time", 16), curve, stats)
    stats.toZkalc()

# EC Msm benches
# -------------------------------------------------------------------------------------

type BenchMsmContext[EC] = object
  numInputs: int
  coefs: seq[getBigInt(EC.getName(), kScalarField)]
  points: seq[affine(EC)]

proc createBenchMsmContext*(rng: var RngState, EC: typedesc, maxNumInputs: int): BenchMsmContext[EC] =
  let tp = Threadpool.new()

  type Big = typeof(result.coefs[0])
  type ECaff = affine(EC)

  result.numInputs = maxNumInputs
  result.points = newSeq[ECaff](maxNumInputs)
  result.coefs = newSeq[Big](maxNumInputs)

  proc genCoefPointPairsChunk[EC, ECaff](rngSeed: uint64, start, len: int, points: ptr ECaff, coefs: ptr Big) {.nimcall.} =
    let points = cast[ptr UncheckedArray[ECaff]](points)
    let coefs = cast[ptr UncheckedArray[Big]](coefs)

    # RNGs are not threadsafe, create a threadlocal one seeded from the global RNG
    var threadRng: RngState
    threadRng.seed(rngSeed)

    for i in start ..< start + len:
      var tmp = threadRng.random_unsafe(EC)
      tmp.clearCofactor()
      points[i].affine(tmp)
      coefs[i] = threadRng.random_unsafe(Big)

  let chunks = balancedChunksPrioNumber(0, maxNumInputs, tp.numThreads)

  stdout.write &"Generating {maxNumInputs} (coefs, points) pairs ... "
  stdout.flushFile()

  let start = getMonotime()

  syncScope:
    for (id, start, size) in items(chunks):
      tp.spawn genCoefPointPairsChunk[EC, ECaff](rng.next(), start, size, result.points[0].addr, result.coefs[0].addr)

  # Even if child threads are sleeping, it seems like perf is lower when there are threads around
  # maybe because the kernel has more overhead or time quantum to keep track off so shut them down.
  tp.shutdown()

  let stop = getMonotime()
  stdout.write &"in {float64(inNanoSeconds(stop-start)) / 1e6:6.3f} ms\n"

proc benchEcMsm[EC](ctx: BenchMsmContext[EC]): ZkalcBenchDetails =
  const G =
    when EC.G == G1: "𝔾₁"
    else: "𝔾₂"
  const curve = EC.getName()

  let tp = Threadpool.new()
  var size = 2
  while size <= ctx.numInputs:
    var r{.noInit.}: EC
    template coefs: untyped = ctx.coefs.toOpenArray(0, size-1)
    template points: untyped = ctx.points.toOpenArray(0, size-1)

    let stats = bench():
      tp.multiScalarMul_vartime_parallel(r, coefs, points)

    report(G & " MSM " & align($size, 9) & ", " & align($tp.numThreads & " threads", 11) & align("| vartime", 12), curve, stats)
    result.append(stats, size)

    size *= 2

  tp.shutdown()

# EC serialization benches
# -------------------------------------------------------------------------------------

proc benchEcIsInSubgroup(rng: var RngState, EC: type): ZkalcBenchDetails =
  const G =
    when EC.G == G1: "𝔾₁"
    else: "𝔾₂"
  const curve = EC.getName()

  var P = rng.random_unsafe(EC)
  P.clearCofactor()
  preventOptimAway(P)

  let stats = bench():
    discard P.isInSubgroup()

  report(G & " Subgroup Check", curve, stats)
  stats.toZkalc()

proc benchEcHashToCurve(rng: var RngState, EC: type): ZkalcBenchDetails =
  const G =
    when EC.G == G1: "𝔾₁"
    else: "𝔾₂"
  const curve = EC.getName()

  const dst = "Constantine_Zkalc_Bench_HashToCurve"
  # Gnark uses a message of size 54, probably to not spill over padding with SHA256
  let msg = "Privacy is necessary for an open society [...]"

  var P {.noInit.}: EC

  let stats = bench():
    sha256.hashToCurve(
      k = 128,
      output = P,
      augmentation = "",
      message = msg,
      domainSepTag = dst
    )

  report(G & " Hash-to-Curve", curve, stats)
  stats.toZkalc()

# 𝔾ₜ benches
# -------------------------------------------------------------------------------------

func random_gt*(rng: var RngState, F: typedesc): F {.inline, noInit.} =
  result = rng.random_unsafe(F)
  result.finalExp()

proc benchGtMul(rng: var RngState, curve: static Algebra): ZkalcBenchDetails =
  when curve in {BN254_Snarks, BLS12_377, BLS12_381}:
    type Gt = Fp12[curve]
  else:
    {.error: "𝔾ₜ multiplication is not configured for " & $curve.}

  var x = rng.random_gt(Gt)
  let y = rng.random_gt(Gt)

  preventOptimAway(x)
  preventOptimAway(y)

  let stats = bench():
    x *= y

  report("𝔾ₜ Multiplication", curve, stats)
  stats.toZkalc()

proc benchGtExp(rng: var RngState, curve: static Algebra, useVartime: bool): ZkalcBenchDetails =
  when curve in {BN254_Snarks, BLS12_377, BLS12_381}:
    type Gt = Fp12[curve]
  else:
    {.error: "𝔾ₜ exponentiation is not configured for " & $curve.}

  var r {.noInit.}: Gt
  let a = rng.random_gt(Gt)
  let k = rng.random_unsafe(Fr[curve].getBigInt())

  preventOptimAway(r)
  preventOptimAway(a)

  if useVartime:
    let stats = bench():
      r.gtExp_vartime(a, k)

    report("𝔾ₜ exponentiation" & align("| vartime", 16), curve, stats)
    stats.toZkalc()
  else:
    let stats = bench():
      r.gtExp(a, k)

    report("𝔾ₜ exponentiation" & align("| constant-time", 16), curve, stats)
    stats.toZkalc()

# Pairing benches
# -------------------------------------------------------------------------------------

func clearCofactor[F; G: static Subgroup](
       ec: var EC_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: EC_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactor()
  ec.affine(t)

func random_point*(rng: var RngState, EC: typedesc): EC {.inline, noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactor()

proc benchPairing*(rng: var RngState, curve: static Algebra): ZkalcBenchDetails =
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[curve], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[curve], G2])

  var f: Fp12[curve]
  let stats = bench():
    f.pairing(P, Q)

  report("Pairing", curve, stats)
  stats.toZkalc()

proc benchMultiPairing*(rng: var RngState, curve: static Algebra, maxNumInputs: int): ZkalcBenchDetails =
  var
    Ps = newSeq[EC_ShortW_Aff[Fp[curve], G1]](maxNumInputs)
    Qs = newSeq[EC_ShortW_Aff[Fp2[curve], G2]](maxNumInputs)

  stdout.write &"Generating {maxNumInputs} (𝔾₁, 𝔾₂) pairs ... "
  stdout.flushFile()

  let start = getMonotime()

  for i in 0 ..< maxNumInputs:
    Ps[i] = rng.random_point(typeof(Ps[0]))
    Qs[i] = rng.random_point(typeof(Qs[0]))

  let stop = getMonotime()
  stdout.write &"in {float64(inNanoSeconds(stop-start)) / 1e6:6.3f} ms\n"
  separator()

  var size = 2
  while size <= maxNumInputs:
    var f{.noInit.}: Fp12[curve]
    let stats = bench():
      f.pairing(Ps.toOpenArray(0, size-1), Qs.toOpenArray(0, size-1))

    report("Multipairing " & align($size, 5), curve, stats)
    result.append(stats, size)

    size *= 2

# Run benches
# -------------------------------------------------------------------------------------

proc runBenches(curve: static Algebra, useVartime: bool): ZkalcBenchResult =
  var rng: RngState
  rng.seed(42)

  var zkalc: ZkalcBenchResult

  # Fields
  # --------------------------------------------------------------------
  separator()
  zkalc.add_ff = rng.benchFrAdd(curve)
  zkalc.mul_ff = rng.benchFrMul(curve)
  zkalc.invert = rng.benchFrInv(curve, useVartime)
  zkalc.ip_ff  = rng.benchFrIP(curve)
  separator()

  # Elliptic curve
  # --------------------------------------------------------------------
  type EcG1 = EC_ShortW_Jac[Fp[curve], G1]

  zkalc.add_g1 = rng.benchEcAdd(EcG1, useVartime)
  zkalc.mul_g1 = rng.benchEcMul(EcG1, useVartime)
  separator()
  let ctxG1    = rng.createBenchMsmContext(EcG1, maxNumInputs = 2097152)
  separator()
  zkalc.msm_g1 = benchEcMsm(ctxG1)
  separator()
  zkalc.is_in_sub_G1 = rng.benchEcIsInSubgroup(EcG1)
  when curve in {BN254_Snarks, BLS12_381}:
    zkalc.hash_G1 = rng.benchEcHashToCurve(EcG1)
  separator()

  # Pairing-friendly curve only
  # --------------------------------------------------------------------

  when curve.isPairingFriendly():

    # Elliptic curve 𝔾2
    # --------------------------------------------------------------------

    type EcG2 = EC_ShortW_Jac[Fp2[curve], G2] # For now we only supports G2 on Fp2 (not Fp like BW6 or Fp4 like BLS24)

    zkalc.add_g2 = rng.benchEcAdd(EcG2, useVartime)
    zkalc.mul_g2 = rng.benchEcMul(EcG2, useVartime)
    separator()
    let ctxG2    = rng.createBenchMsmContext(EcG2, maxNumInputs = 2097152)
    separator()
    zkalc.msm_g2 = benchEcMsm(ctxG2)
    separator()
    zkalc.is_in_sub_G2 = rng.benchEcIsInSubgroup(EcG2)
    when curve in {BN254_Snarks, BLS12_381}:
      zkalc.hash_G2 = rng.benchEcHashToCurve(EcG2)
    separator()

    # Pairings
    # --------------------------------------------------------------------

    zkalc.pairing = rng.benchPairing(curve)
    separator()
    zkalc.multipairing = rng.benchMultiPairing(curve, maxNumInputs = 1024)
    separator()

    # Target group 𝔾ₜ
    # --------------------------------------------------------------------
    zkalc.mul_Gt = rng.benchGtMul(curve)
    zkalc.exp_Gt = rng.benchGtExp(curve, useVartime)

  return zkalc

proc main() =
  let cmd = commandLineParams()
  cmd.getOpt (curve: BN254_Snarks, vartime: true, o: "constantine-bench-zkalc-" & $curve & "-" & now().format("yyyy-MM-dd--HH-mm-ss") & ".bench.json")

  let results =
    case curve
    of BN254_Snarks: BN254_Snarks.runBenches(vartime)
    of Pallas:       Pallas      .runBenches(vartime)
    of Vesta:        Vesta       .runBenches(vartime)
    of BLS12_377:    BLS12_377   .runBenches(vartime)
    of BLS12_381:    BLS12_381   .runBenches(vartime)
    else:
      raise newException(ValueError, "This curve '" & $curve & "' is not configured for benchmarking at the moment.")

  writeFile(o, results.toJSON())

when isMainModule:
  main()
