# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/algebras,
  constantine/math/extension_fields/towers {.all.},
  constantine/math/pairings/[pairings_generic, gt_prj],
  # Helpers
  helpers/prng_unsafe,
  ./bench_fields_template,
  ./bench_blueprint

const Iters = 100_000
const BatchIters = 1_000
const AvailableCurves = [
  BLS12_381,
  # BN254_Snarks
]

proc mulFp6_karatsuba_Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba", Fp6[C], iters):
    r.prodImpl(x, y)

proc mulFp6_karatsubaUnreduced_Bench(C: static Algebra, iters: int) =
  var r: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba unreduced", Fp6[C], iters):
    r.prod2x(x, y)

proc mulFp6_karatsubaLazyReduced_Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  var d: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba lazy-reduced", Fp6[C], iters):
    d.prod2x(x, y)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

proc mulFp6_longa22_Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Longa22", Fp6[C], iters):
    r.prodImpl_fp6o2_complex_snr_1pi(x, y)

proc mulFp6TCDFTBench(C: static Algebra, iters: int) =
  var r: Fp6prj[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Toom-Cook-3 + DFT", Fp6[C], iters):
    r.prod_prj(x, y)

proc sqrFp6CH_SQR2Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2", Fp6[C], iters):
    r.square_Chung_Hasan_SQR2(x)

proc sqrFp6CH_SQR2_unreduced_Bench(C: static Algebra, iters: int) =
  var r: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2 unreduced", Fp6[C], iters):
    r.square2x_Chung_Hasan_SQR2(x)

proc sqrFp6CH_SQR2_lazyRed_Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  var d: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2 lazy-reduced", Fp6[C], iters):
    d.square2x_Chung_Hasan_SQR2(x)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

proc sqrFp6CH_SQR3Bench(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR3", Fp6[C], iters):
    r.square_Chung_Hasan_SQR3(x)

proc sqrFp6TCDFTBench(C: static Algebra, iters: int) =
  var r: Fp6prj[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Toom-Cook-3 + DFT", Fp6[C], iters):
    r.square_prj(x)

func random_gt(rng: var RngState, F: typedesc): F {.noInit.} =
  let r = rng.random_long01Seq(F)
  result = r
  result.finalExp()

  # doAssert bool result.isInCyclotomicSubgroup(), block:
  #   $F.Name & ": input was not in the cyclotomic subgroup despite a final exponentiation:\n" &
  #   "    " & r.toHex(indent = 4)
  # doAssert bool result.isInPairingSubgroup(), block:
  #   $F.Name & ": input was not in the pairing subgroup despite a final exponentiation:\n" &
  #   "    " & r.toHex(indent = 4)

type
  Quad[F] = QuadraticExt[F]
  Cube[F] = CubicExt[F]

proc torusFromGt(C: static Algebra, iters: int) =
  var r: T2Aff[Fp6[C]]
  let x = rng.random_gt(Quad[Fp6[C]])
  bench("T₂(𝔽p6) <- 𝔾ₜ conversion", Quad[Fp6[C]], iters):
    r.fromGT_vartime(x)

proc gtFromTorus(C: static Algebra, iters: int) =
  var r: Quad[Fp6[C]]
  let x = rng.random_gt(Quad[Fp6[C]])
  var t: T2Aff[Fp6[C]]
  t.fromGT_vartime(x)
  bench("𝔾ₜ <- T₂(𝔽p6) conversion", Quad[Fp6[C]], iters):
    r.fromTorus2_vartime(t)

proc torusFromGtMultiNaive(C: static Algebra, batchSize, iters: int) =
  var r = newSeq[T2Aff[Fp6[C]]](batchSize)
  var xx = newSeq[Quad[Fp6[C]]](batchSize)
  for x in xx.mitems():
    x = rng.random_gt(Quad[Fp6[C]])
  bench("T₂(𝔽p6) <- 𝔾ₜ multi-conversion naive - " & $batchSize, Quad[Fp6[C]], iters):
    for i in 0 ..< batchSize:
      r[i].fromGT_vartime(xx[i])

proc torusFromGtMultiBatch(C: static Algebra, batchSize, iters: int) =
  var r = newSeq[T2Aff[Fp6[C]]](batchSize)
  var xx = newSeq[Quad[Fp6[C]]](batchSize)
  for x in xx.mitems():
    x = rng.random_gt(Quad[Fp6[C]])
  bench("T₂(𝔽p6) <- 𝔾ₜ multi-conversion batched - " & $batchSize, Quad[Fp6[C]], iters):
    r.batchFromGT_vartime(xx)

proc gtFromTorus2MultiNaive(C: static Algebra, batchSize, iters: int) =
  var tt = newSeq[T2Prj[Fp6[C]]](batchSize)
  var aa = newSeq[Quad[Fp6[C]]](batchSize)
  for a in aa.mitems():
    a = rng.random_gt(Quad[Fp6[C]])
  for i in 0 ..< batchSize:
    tt[i].fromGT_vartime(aa[i])
  bench("𝔾ₜ <- T₂(𝔽p6) multi-conversion naive - " & $batchSize, Quad[Fp6[C]], iters):
    aa.batchfromTorus2_vartime(tt)

proc gtFromTorus2MultiBatch(C: static Algebra, batchSize, iters: int) =
  var tt = newSeq[T2Aff[Fp6[C]]](batchSize)
  var aa = newSeq[Quad[Fp6[C]]](batchSize)
  for a in aa.mitems():
    a = rng.random_gt(Quad[Fp6[C]])
  tt.batchFromGT_vartime(aa)
  bench("𝔾ₜ <- T₂(𝔽p6) multi-conversion batched - " & $batchSize, Quad[Fp6[C]], iters):
    for i in 0 ..< batchSize:
      aa[i].fromTorus2_vartime(tt[i])

proc mulT2_aff(C: static Algebra, iters: int) =
  let a = rng.random_gt(Quad[Fp6[C]])
  let b = rng.random_gt(Quad[Fp6[C]])

  var a_taff, b_taff: T2Aff[Fp6[C]]
  var r_tprj: T2Prj[Fp6[C]]
  a_taff.fromGT_vartime(a)
  b_taff.fromGT_vartime(b)

  bench("T₂prj(𝔽p6) <- T₂aff(𝔽p6) * T₂aff(𝔽p6)", Quad[Fp6[C]], iters):
    r_tprj.affineProd(a_taff, b_taff)

proc mulT2_mix(C: static Algebra, iters: int) =
  let a = rng.random_gt(Quad[Fp6[C]])
  let b = rng.random_gt(Quad[Fp6[C]])

  var b_taff: T2Aff[Fp6[C]]
  var a_tprj, r_tprj: T2Prj[Fp6[C]]
  a_tprj.fromGT_vartime(a)
  b_taff.fromGT_vartime(b)

  bench("T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂aff(𝔽p6)", T2Prj[Fp6[C]], iters):
    r_tprj.mixedProd(a_tprj, b_taff)

proc mulT2_prj(C: static Algebra, iters: int) =
  let a = rng.random_gt(Quad[Fp6[C]])
  let b = rng.random_gt(Quad[Fp6[C]])

  var a_tprj, b_tprj, r_tprj: T2Prj[Fp6[C]]
  a_tprj.fromGT_vartime(a)
  b_tprj.fromGT_vartime(b)

  bench("T₂prj(𝔽p6) <- T₂prj(𝔽p6) * T₂prj(𝔽p6)", T2Prj[Fp6[C]], iters):
    r_tprj.prod(a_tprj, b_tprj)

proc sqrT2_aff(C: static Algebra, iters: int) =
  let a = rng.random_gt(Quad[Fp6[C]])

  var a_taff: T2Aff[Fp6[C]]
  var r_tprj: T2Prj[Fp6[C]]
  a_taff.fromGT_vartime(a)

  bench("T₂prj(𝔽p6) <- T₂aff(𝔽p6)²", T2Aff[Fp6[C]], iters):
    r_tprj.affineSquare(a_taff)

proc sqrT2_prj(C: static Algebra, iters: int) =
  let a = rng.random_gt(Quad[Fp6[C]])

  var a_tprj, r_tprj: T2Prj[Fp6[C]]
  a_tprj.fromGT_vartime(a)

  bench("T₂prj(𝔽p6) <- T₂prj(𝔽p6)²", T2Prj[Fp6[C]], iters):
    r_tprj.square(a_tprj)

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    separator()
    mulFp6_karatsuba_Bench(curve, Iters)
    mulFp6_karatsubaUnreduced_Bench(curve, Iters)
    mulFp6_karatsubaLazyReduced_Bench(curve, Iters)
    when curve.getNonResidueFp2() == (1, 1):
      mulFp6_longa22_Bench(curve, Iters)
    mulFp6TCDFTBench(curve, Iters)
    separator()
    sqrFp6CH_SQR2_Bench(curve, Iters)
    sqrFp6CH_SQR2_unreduced_Bench(curve, Iters)
    sqrFp6CH_SQR2_lazyRed_Bench(curve, Iters)
    sqrFp6CH_SQR3Bench(curve, Iters)
    sqrFp6TCDFTBench(curve, Iters)
    separator()
    mulBench(Quad[Fp6[curve]], Iters)
    mulBench(Cube[Fp4[curve]], Iters)
    sqrBench(Quad[Fp6[curve]], Iters)
    sqrBench(Cube[Fp4[curve]], Iters)
    separator()
    torusFromGt(curve, Iters)
    gtFromTorus(curve, Iters)
    separator()
    torusFromGtMultiNaive(curve, batchSize = 256, BatchIters)
    torusFromGtMultiBatch(curve, batchSize = 256, BatchIters)
    gtFromTorus2MultiNaive(curve, batchSize = 256, BatchIters)
    gtFromTorus2MultiBatch(curve, batchSize = 256, BatchIters)
    separator()
    mulT2_aff(curve, Iters)
    mulT2_mix(curve, Iters)
    mulT2_prj(curve, Iters)
    sqrT2_aff(curve, Iters)
    sqrT2_prj(curve, Iters)
    separator()

main()
notes()
