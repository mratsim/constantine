# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Benchmark of pairings
#
# ############################################################

import
  # Internals
  ../constantine/platforms/abstractions,
  ../constantine/math/config/curves,
  ../constantine/math/arithmetic,
  ../constantine/math/extension_fields,
  ../constantine/math/ec_shortweierstrass,
  ../constantine/math/curves/zoo_subgroups,
  ../constantine/math/pairing/[
    cyclotomic_subgroup,
    lines_eval,
    pairing_bls12,
    pairing_bn
  ],
  ../constantine/math/curves/zoo_pairings,
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_blueprint

export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225
export notes
proc separator*() = separator(132)

proc report(op, curve: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<40} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, C: static Curve, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, $C, startTime, stopTime, startClk, stopClk, iters)

func clearCofactor[F; G: static Subgroup](
       ec: var ECP_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: ECP_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactor()
  ec.affine(t)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactor()

proc lineDoubleBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  bench("Line double", C, iters):
    line.line_double(T, P)

proc lineAddBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])
  bench("Line add", C, iters):
    line.line_add(T, Q, P)

proc mulFp12byLine_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line", C, iters):
    f.mul_by_line(line)

proc mulLinebyLine_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f {.noInit.}: Fp12[C]

  bench("Mul line by line", C, iters):
    f.prod_from_2_lines(l0, l1)

proc mulFp12by_prod2lines_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])
  let g = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by product of 2 lines", C, iters):
    f.mul_by_prod_of_2_lines(g)

proc mulFp12_by_2lines_v1_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v1", C, iters):
    f.mul_by_line(l0)
    f.mul_by_line(l1)

proc mulFp12_by_2lines_v2_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v2", C, iters):
    var f2 {.noInit.}: Fp12[C]
    f2.prod_from_2_lines(l0, l1)
    f.mul_by_prod_of_2_lines(f2)

proc mulBench*(C: static Curve, iters: int) =
  var r: Fp12[C]
  let x = rng.random_unsafe(Fp12[C])
  let y = rng.random_unsafe(Fp12[C])
  preventOptimAway(r)
  bench("Multiplication 𝔽p12", C, iters):
    r.prod(x, y)

proc sqrBench*(C: static Curve, iters: int) =
  var r: Fp12[C]
  let x = rng.random_unsafe(Fp12[C])
  preventOptimAway(r)
  bench("Squaring  𝔽p12", C, iters):
    r.square(x)

proc cyclotomicSquare_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])

  bench("Squaring 𝔽p12 in cyclotomic subgroup", C, iters):
    f.cyclotomic_square()

proc expCurveParamBench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])

  bench("Cyclotomic Exp by curve parameter", C, iters):
    f.cycl_exp_by_curve_param(f)

proc cyclotomicSquareCompressed_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])
  var g: G2345[Fp2[C]]
  g.fromFpk(f)

  bench("Cyclotomic Compressed Squaring 𝔽p12", C, iters):
    g.cyclotomic_square_compressed()

proc cyclotomicDecompression_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])
  var gs: array[1, G2345[Fp2[C]]]
  gs[0].fromFpk(f)

  var g1s_ratio: array[1, tuple[g1_num, g1_den: Fp2[C]]]
  var g0s, g1s: array[1, Fp2[C]]

  bench("Cyclotomic Decompression 𝔽p12", C, iters):
    recover_g1(g1s_ratio[0].g1_num, g1s_ratio[0].g1_den, gs[0])
    g1s.batch_ratio_g1s(g1s_ratio)
    g0s[0].recover_g0(g1s[0], gs[0])

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

proc finalExpEasyBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  bench("Final Exponentiation Easy", C, iters):
    r.finalExpEasy()

proc finalExpHardBLS12Bench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BLS12", C, iters):
    r.finalExpHard_BLS12()

proc finalExpHardBNBench*(C: static Curve, iters: int) =
  var r = rng.random_unsafe(Fp12[C])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BN", C, iters):
    r.finalExpHard_BN()

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

proc pairing_multisingle_BLS12Bench*(C: static Curve, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[C], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[C], G2]]

    GTs {.noInit.}: array[N, Fp12[C]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[C]
  bench("Pairing BLS12 non-batched: " & $N, C, iters):
    for i in 0 ..< N:
      GTs[i].pairing_bls12(Ps[i], Qs[i])

    f = GTs[0]
    for i in 1 ..< N:
      f *= GTs[i]

proc pairing_multipairing_BLS12Bench*(C: static Curve, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[C], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[C], G2]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[C]
  bench("Pairing BLS12 batched:     " & $N, C, iters):
    f.pairing_bls12(Ps, Qs)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)

proc pairing_multisingle_BNBench*(C: static Curve, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[C], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[C], G2]]

    GTs {.noInit.}: array[N, Fp12[C]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[C]
  bench("Pairing BN non-batched: " & $N, C, iters):
    for i in 0 ..< N:
      GTs[i].pairing_bn(Ps[i], Qs[i])

    f = GTs[0]
    for i in 1 ..< N:
      f *= GTs[i]

proc pairing_multipairing_BNBench*(C: static Curve, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[C], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[C], G2]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[C]
  bench("Pairing BN batched:     " & $N, C, iters):
    f.pairing_bn(Ps, Qs)
