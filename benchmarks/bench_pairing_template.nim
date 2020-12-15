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
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_blueprint

export notes
proc separator*() = separator(177)

proc report(op, curve: string, startTime, stopTime: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stopTime-startTime) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<60} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<60} {curve:<15} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

template bench(op: string, C: static Curve, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, $C, startTime, stopTime, startClk, stopClk, iters)

func random_point*(rng: var RngState, EC: typedesc): EC {.noInit.} =
  result = rng.random_unsafe(EC)
  result.clearCofactorReference()

proc lineDoubleBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)
  bench("Line double", C, iters):
    line.line_double(T, Paff)

proc lineAddBench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  bench("Line add", C, iters):
    line.line_add(T, Qaff, Paff)

proc mulFp12byLine_xyz000_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)

  line.line_double(T, Paff)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xyz000", C, iters):
    f.mul_sparse_by_line_xyz000(line)

proc mulFp12byLine_xy000z_Bench*(C: static Curve, iters: int) =
  var line: Line[Fp2[C]]
  var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  let P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
  var Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  Paff.affineFromProjective(P)

  line.line_double(T, Paff)
  var f = rng.random_unsafe(Fp12[C])

  bench("Mul 𝔽p12 by line xy000z", C, iters):
    f.mul_sparse_by_line_xy000z(line)

proc millerLoopBLS12Bench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)

  var f: Fp12[C]

  bench("Miller Loop BLS12", C, iters):
    f.millerLoopGenericBLS12(Paff, Qaff)

proc millerLoopBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])
  var
    Paff: ECP_ShortW_Aff[Fp[C], NotOnTwist]
    Qaff: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)

  var f: Fp12[C]

  bench("Miller Loop BN", C, iters):
    f.millerLoopGenericBN(Paff, Qaff)

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
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])

  var f: Fp12[C]

  bench("Pairing BLS12", C, iters):
    f.pairing_bls12(P, Q)

proc pairingBNBench*(C: static Curve, iters: int) =
  let
    P = rng.random_point(ECP_ShortW_Proj[Fp[C], NotOnTwist])
    Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist])

  var f: Fp12[C]

  bench("Pairing BN", C, iters):
    f.pairing_bn(P, Q)
