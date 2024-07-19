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
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/pairings/[
    pairings_generic,
    cyclotomic_subgroups,
    gt_exponentiations,
    gt_exponentiations_vartime
  ],
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

export notes
export abstractions
proc separator*() = separator(168)

proc report(op, domain: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<68} {domain:<20} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<68} {domain:<20} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Algebra(instantiated[1][1].intVal) & "]"
  result = newLit name

func fixDisplay(T: typedesc): string =
  when T is (Fp or Fp2 or Fp4 or Fp6 or Fp12):
    fixFieldDisplay(T)
  else:
    $T

func fixDisplay(T: Algebra): string =
  $T

template bench(op: string, T: typed, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixDisplay(T), startTime, stopTime, startClk, stopClk, iters)

func random_gt*(rng: var RngState, F: typedesc): F {.inline, noInit.} =
  result = rng.random_unsafe(F)
  result.finalExp()

proc mulBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_gt(T)
  let y = rng.random_gt(T)
  preventOptimAway(r)
  bench("Multiplication", T, iters):
    r.prod(x, y)

proc sqrBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_gt(T)
  preventOptimAway(r)
  bench("Squaring", T, iters):
    r.square(x)

proc invBench*(T: typedesc, iters: int) =
  var r: T
  let x = rng.random_gt(T)
  preventOptimAway(r)
  bench("Inversion", T, iters):
    r.inv(x)

proc cyclotomicSquare_Bench*(T: typedesc, iters: int) =
  var f = rng.random_gt(T)

  bench("Squaring in cyclotomic subgroup", T, iters):
    f.cyclotomic_square()

proc cyclotomicInv_Bench*(T: typedesc, iters: int) =
  var f = rng.random_gt(T)

  bench("Inversion in cyclotomic subgroup", T, iters):
    f.cyclotomic_inv()

proc cyclotomicSquareCompressed_Bench*(T: typedesc, iters: int) =
  var f = rng.random_gt(T)

  when T is Fp12:
    type F = Fp2[T.Name]
  else:
    {.error: "Only compression of Fp12 extension is configured".}

  var g: G2345[F]
  g.fromFpk(f)

  bench("Cyclotomic Compressed Squaring", T, iters):
    g.cyclotomic_square_compressed()

proc cyclotomicDecompression_Bench*(T: typedesc, iters: int) =
  var f = rng.random_gt(T)

  when T is Fp12:
    type F = Fp2[T.Name]
  else:
    {.error: "Only compression of Fp12 extension is configured".}

  var gs: array[1, G2345[F]]
  gs[0].fromFpk(f)

  var g1s_ratio: array[1, tuple[g1_num, g1_den: F]]
  var g0s, g1s: array[1, F]

  bench("Cyclotomic Decompression", T, iters):
    recover_g1(g1s_ratio[0].g1_num, g1s_ratio[0].g1_den, gs[0])
    g1s.batch_ratio_g1s(g1s_ratio)
    g0s[0].recover_g0(g1s[0], gs[0])

proc powVartimeBench*(T: typedesc, window: static int, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r = x
  bench("Field Exponentiation " & $exponent.bits & "-bit (window-" & $window & ", vartime)", T, iters):
    r.pow_vartime(exponent, window)

proc gtExp_sqrmul_vartimeBench*(T: typedesc, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r {.noInit.}: T
  bench("𝔾ₜ Exponentiation " & $exponent.bits & "-bit (cyclotomic square-multiply, vartime)", T, iters):
    r.gtExp_sqrmul_vartime(x, exponent)

proc gtExp_jy00_vartimeBench*(T: typedesc, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r {.noInit.}: T
  bench("𝔾ₜ Exponentiation " & $exponent.bits & "-bit (signed recoding, vartime)", T, iters):
    r.gtExp_jy00_vartime(x, exponent)

proc gtExp_wNAF_vartimeBench*(T: typedesc, window: static int, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r {.noInit.}: T
  bench("𝔾ₜ Exponentiation " & $exponent.bits & "-bit (wNAF-" & $window & ", vartime)", T, iters):
    r.gtExp_wNAF_vartime(x, exponent, window)

proc gtExp_endo_wNAF_vartimeBench*(T: typedesc, window: static int, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r {.noInit.}: T
  bench("𝔾ₜ Exponentiation " & $exponent.bits & "-bit (endomorphism, wNAF-" & $window & ", vartime)", T, iters):
    r.gtExpEndo_wNAF_vartime(x, exponent, window)

proc gtExpEndo_constanttimeBench*(T: typedesc, iters: int) =
  let x = rng.random_gt(T)
  let exponent = rng.random_unsafe(BigInt[Fr[T.Name].bits()])
  var r {.noInit.}: T
  bench("𝔾ₜ Exponentiation " & $exponent.bits & "-bit (endomorphism, constant-time)", T, iters):
    r.gtExpEndo(x, exponent)
