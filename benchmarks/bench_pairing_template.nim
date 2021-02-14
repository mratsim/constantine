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
  ../constantine/io/io_bigints,
  ../constantine/towers,
  ../constantine/elliptic/[ec_shortweierstrass_projective, ec_shortweierstrass_affine],
  ../constantine/hash_to_curve/cofactors,
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

func clearCofactorReference[F; Tw: static Twisted](
       ec: var ECP_ShortW_Aff[F, Tw]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: ECP_ShortW_Prj[F, Tw]
  t.projectiveFromAffine(ec)
  t.clearCofactorReference()
  ec.affineFromProjective(t)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactorReference()

proc lineDoubleBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  bench("Line double", C, iters):
    line.line_double(T, P)

proc lineAddBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], OnTwist])
  bench("Line add", C, iters):
    line.line_add(T, Q, P)

proc mulFp12byLine_xyz000_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xyz000", C, iters):
    f.mul_sparse_by_line_xyz000(line)

proc mulFp12byLine_xy000z_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  line.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xy000z", C, iters):
    f.mul_sparse_by_line_xy000z(line)

proc mulLinebyLine_xyz000_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul line xyz000 by line xyz000", C, iters):
    f.mul_xyz000_xyz000_into_abcdefghij00(l0, l1)

proc mulLinebyLine_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul line xy000z by line xy000z", C, iters):
    f.mul_xy000z_xy000z_into_abcd00efghij(l0, l1)

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
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v1", C, iters):
    f.mul_sparse_by_line_xyz000(l0)
    f.mul_sparse_by_line_xyz000(l1)

proc mulFp12_by_2lines_v2_xyz000_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v2", C, iters):
    var f2 {.noInit.}: Fp12[C]
    f2.mul_xyz000_xyz000_into_abcdefghij00(l0, l1)
    f.mul_sparse_by_abcdefghij00(f2)

proc mulFp12_by_2lines_v1_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v1", C, iters):
    f.mul_sparse_by_line_xy000z(l0)
    f.mul_sparse_by_line_xy000z(l1)

proc mulFp12_by_2lines_v2_xy000z_Bench*(C: static Curve, iters: int) =
  var l0, l1: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Prj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
  l0.line_double(T, P)
  l1.line_double(T, P)
  var f = rng.random_unsafe(Fp12[C])

  bench("mulFp12 by 2 lines v2", C, iters):
    var f2 {.noInit.}: Fp12[C]
    f2.mul_xy000z_xy000z_into_abcd00efghij(l0, l1)
    f.mul_sparse_by_abcd00efghij(f2)

proc millerLoopBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], OnTwist])

  var f: Fp12[C]
  bench("Miller Loop BLS12", C, iters):
    f.millerLoopGenericBLS12(P, Q)

proc millerLoopBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], OnTwist])

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
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], OnTwist])

  var f: Fp12[C]
  bench("Pairing BLS12", C, iters):
    f.pairing_bls12(P, Q)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Aff[Fp2[C], OnTwist])

  var f: Fp12[C]
  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)
