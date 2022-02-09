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
  ../constantine/config/[curves, common],
  ../constantine/arithmetic,
  ../constantine/towers,
  ../constantine/ec_shortweierstrass,
  ../constantine/curves/zoo_subgroups,
  ../constantine/pairing/[
    cyclotomic_fp12,
    lines_projective,
    mul_fp12_by_lines,
    pairing_bls12,
    pairing_bn
  ],
  ../constantine/curves/zoo_pairings,
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

proc mulFp12byLine_xyz000_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xyz000", C, iters):
    f.mul_sparse_by_line_xyz000(line)

proc mulFp12byLine_xy000z_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xy000z", C, iters):
    f.mul_sparse_by_line_xy000z(line)

proc mulLinebyLine_xyz000_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul line xyz000 by line xyz000", C, iters):
    f.prod_xyz000_xyz000_into_abcdefghij00(l0, l1)

proc mulLinebyLine_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul line xy000z by line xy000z", C, iters):
    f.prod_xy000z_xy000z_into_abcd00efghij(l0, l1)

proc mulFp12by_abcdefghij00_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])
  let g = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by abcdefghij00", C, iters):
    f.mul_sparse_by_abcdefghij00(g)

proc mulFp12by_abcd00efghij_Bench*(C: static Curve, iters: int) =
  var f = rng.random_unsafe(Fp12[C])
  let g = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by abcd00efghij", C, iters):
    f.mul_sparse_by_abcd00efghij(g)

proc mulFp12_by_2lines_v1_xyz000_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v1", C, iters):
    f.mul_sparse_by_line_xyz000(l0)
    f.mul_sparse_by_line_xyz000(l1)

proc mulFp12_by_2lines_v2_xyz000_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v2", C, iters):
    var f2 {.noInit.}: Fp12[C]
    f2.prod_xyz000_xyz000_into_abcdefghij00(l0, l1)
    f.mul_sparse_by_abcdefghij00(f2)

proc mulFp12_by_2lines_v1_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v1", C, iters):
    f.mul_sparse_by_line_xy000z(l0)
    f.mul_sparse_by_line_xy000z(l1)

proc mulFp12_by_2lines_v2_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], G2])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v2", C, iters):
    var f2 {.noInit.}: Fp12[C]
    f2.prod_xy000z_xy000z_into_abcd00efghij(l0, l1)
    f.mul_sparse_by_abcd00efghij(f2)

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
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[C], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[C], G2]]

    GTs {.noInit.}: array[N, Fp12[C]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  var f: Fp12[C]
  bench("Pairing BLS12 multi-single " & $N & " pairings", C, iters):
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
  bench("Pairing BLS12 multipairing " & $N & " pairings", C, iters):
    f.pairing_bls12(Ps, Qs)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], G1])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], G2])

  var f: Fp12[C]
  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)
