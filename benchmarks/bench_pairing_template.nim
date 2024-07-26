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
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/math/ec_shortweierstrass,
  constantine/named/zoo_subgroups,
  constantine/math/pairings/[
    cyclotomic_subgroups,
    lines_eval,
    pairings_bls12,
    pairings_bn
  ],
  constantine/named/zoo_pairings,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

export abstractions
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

template bench(op: string, Name: static Algebra, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, $Name, startTime, stopTime, startClk, stopClk, iters)

func clearCofactor[F; G: static Subgroup](
       ec: var EC_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: EC_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactor()
  ec.affine(t)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactor()

proc lineDoubleBench*(Name: static Algebra, iters: int) =
  var line: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
  bench("Line double", Name, iters):
    line.line_double(T, P)

proc lineAddBench*(Name: static Algebra, iters: int) =
  var line: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[Name], G2])
  bench("Line add", Name, iters):
    line.line_add(T, Q, P)

proc mulFp12byLine_Bench*(Name: static Algebra, iters: int) =
  var line: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[Name])

  bench("Mul 𝔽p12 by line", Name, iters):
    f.mul_by_line(line)

proc mulLinebyLine_Bench*(Name: static Algebra, iters: int) =
  var l0, l1: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f {.noInit.}: Fp12[Name]

  bench("Mul line by line", Name, iters):
    f.prod_from_2_lines(l0, l1)

proc mulFp12by_prod2lines_Bench*(Name: static Algebra, iters: int) =
  var f = rng.random_unsafe(Fp12[Name])
  let g = rng.random_unsafe(Fp12[Name])

  bench("Mul 𝔽p12 by product of 2 lines", Name, iters):
    f.mul_by_prod_of_2_lines(g)

proc mulFp12_by_2lines_v1_Bench*(Name: static Algebra, iters: int) =
  var l0, l1: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[Name])

  bench("mulFp12 by 2 lines v1", Name, iters):
    f.mul_by_line(l0)
    f.mul_by_line(l1)

proc mulFp12_by_2lines_v2_Bench*(Name: static Algebra, iters: int) =
  var l0, l1: Line[Fp2[Name]]
  var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2])
  let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[Name])

  bench("mulFp12 by 2 lines v2", Name, iters):
    var f2 {.noInit.}: Fp12[Name]
    f2.prod_from_2_lines(l0, l1)
    f.mul_by_prod_of_2_lines(f2)

proc mulBench*(Name: static Algebra, iters: int) =
  var r: Fp12[Name]
  let x = rng.random_unsafe(Fp12[Name])
  let y = rng.random_unsafe(Fp12[Name])
  preventOptimAway(r)
  bench("Multiplication 𝔽p12", Name, iters):
    r.prod(x, y)

proc sqrBench*(Name: static Algebra, iters: int) =
  var r: Fp12[Name]
  let x = rng.random_unsafe(Fp12[Name])
  preventOptimAway(r)
  bench("Squaring  𝔽p12", Name, iters):
    r.square(x)

proc cyclotomicSquare_Bench*(Name: static Algebra, iters: int) =
  var f = rng.random_unsafe(Fp12[Name])

  bench("Squaring 𝔽p12 in cyclotomic subgroup", Name, iters):
    f.cyclotomic_square()

proc expCurveParamBench*(Name: static Algebra, iters: int) =
  var f = rng.random_unsafe(Fp12[Name])

  bench("Cyclotomic Exp by curve parameter", Name, iters):
    f.cycl_exp_by_curve_param(f)

proc cyclotomicSquareCompressed_Bench*(Name: static Algebra, iters: int) =
  var f = rng.random_unsafe(Fp12[Name])
  var g: G2345[Fp2[Name]]
  g.fromFpk(f)

  bench("Cyclotomic Compressed Squaring 𝔽p12", Name, iters):
    g.cyclotomic_square_compressed()

proc cyclotomicDecompression_Bench*(Name: static Algebra, iters: int) =
  var f = rng.random_unsafe(Fp12[Name])
  var gs: array[1, G2345[Fp2[Name]]]
  gs[0].fromFpk(f)

  var g1s_ratio: array[1, tuple[g1_num, g1_den: Fp2[Name]]]
  var g0s, g1s: array[1, Fp2[Name]]

  bench("Cyclotomic Decompression 𝔽p12", Name, iters):
    recover_g1(g1s_ratio[0].g1_num, g1s_ratio[0].g1_den, gs[0])
    g1s.batch_ratio_g1s(g1s_ratio)
    g0s[0].recover_g0(g1s[0], gs[0])

proc millerLoopBLS12Bench*(Name: static Algebra, iters: int) =
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[Name], G2])

  var f: Fp12[Name]
  bench("Miller Loop BLS12", Name, iters):
    f.millerLoopGenericBLS12(Q, P)

proc millerLoopBNBench*(Name: static Algebra, iters: int) =
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[Name], G2])

  var f: Fp12[Name]
  bench("Miller Loop BN", Name, iters):
    f.millerLoopGenericBN(Q, P)

proc finalExpEasyBench*(Name: static Algebra, iters: int) =
  var r = rng.random_unsafe(Fp12[Name])
  bench("Final Exponentiation Easy", Name, iters):
    r.finalExpEasy()

proc finalExpHardBLS12Bench*(Name: static Algebra, iters: int) =
  var r = rng.random_unsafe(Fp12[Name])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BLS12", Name, iters):
    r.finalExpHard_BLS12()

proc finalExpHardBNBench*(Name: static Algebra, iters: int) =
  var r = rng.random_unsafe(Fp12[Name])
  r.finalExpEasy()
  bench("Final Exponentiation Hard BN", Name, iters):
    r.finalExpHard_BN()

proc finalExpBLS12Bench*(Name: static Algebra, iters: int) =
  var r = rng.random_unsafe(Fp12[Name])
  bench("Final Exponentiation BLS12", Name, iters):
    r.finalExpEasy()
    r.finalExpHard_BLS12()

proc finalExpBNBench*(Name: static Algebra, iters: int) =
  var r = rng.random_unsafe(Fp12[Name])
  bench("Final Exponentiation BN", Name, iters):
    r.finalExpEasy()
    r.finalExpHard_BN()

proc pairingBLS12Bench*(Name: static Algebra, iters: int) =
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[Name], G2])

  var f: Fp12[Name]
  bench("Pairing BLS12", Name, iters):
    f.pairing_bls12(P, Q)

proc pairing_multisingle_BLS12Bench*(Name: static Algebra, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, EC_ShortW_Aff[Fp[Name], G1]]
    Qs {.noInit.}: array[N, EC_ShortW_Aff[Fp2[Name], G2]]

    GTs {.noInit.}: array[N, Fp12[Name]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[Name]
  bench("Pairing BLS12 non-batched: " & $N, Name, iters):
    for i in 0 ..< N:
      GTs[i].pairing_bls12(Ps[i], Qs[i])

    f = GTs[0]
    for i in 1 ..< N:
      f *= GTs[i]

proc pairing_multipairing_BLS12Bench*(Name: static Algebra, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, EC_ShortW_Aff[Fp[Name], G1]]
    Qs {.noInit.}: array[N, EC_ShortW_Aff[Fp2[Name], G2]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[Name]
  bench("Pairing BLS12 batched:     " & $N, Name, iters):
    f.pairing_bls12(Ps, Qs)

proc pairingBNBench*(Name: static Algebra, iters: int) =
  let
    P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1])
    Q = rng.random_point(EC_ShortW_Aff[Fp2[Name], G2])

  var f: Fp12[Name]
  bench("Pairing BN", Name, iters):
    f.pairing_bn(P, Q)

proc pairing_multisingle_BNBench*(Name: static Algebra, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, EC_ShortW_Aff[Fp[Name], G1]]
    Qs {.noInit.}: array[N, EC_ShortW_Aff[Fp2[Name], G2]]

    GTs {.noInit.}: array[N, Fp12[Name]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[Name]
  bench("Pairing BN non-batched: " & $N, Name, iters):
    for i in 0 ..< N:
      GTs[i].pairing_bn(Ps[i], Qs[i])

    f = GTs[0]
    for i in 1 ..< N:
      f *= GTs[i]

proc pairing_multipairing_BNBench*(Name: static Algebra, N: static int, iters: int) =
  var
    Ps {.noInit.}: array[N, EC_ShortW_Aff[Fp[Name], G1]]
    Qs {.noInit.}: array[N, EC_ShortW_Aff[Fp2[Name], G2]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[Name]
  bench("Pairing BN batched:     " & $N, Name, iters):
    f.pairing_bn(Ps, Qs)
