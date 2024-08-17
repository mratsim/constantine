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
  constantine/math/pairings/gt_prj,
  # Helpers
  helpers/prng_unsafe,
  ./bench_fields_template,
  ./bench_blueprint

const Iters = 100_000
const AvailableCurves = [
  BLS12_381,
  BN254_Snarks
]

proc mulFp6_karatsuba_Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba", Fp6[C], iters):
    r.prodImpl(x, y)

proc mulFp6_karatsubaUnreduced_Bench*(C: static Algebra, iters: int) =
  var r: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba unreduced", Fp6[C], iters):
    r.prod2x(x, y)

proc mulFp6_karatsubaLazyReduced_Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  var d: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Karatsuba lazy-reduced", Fp6[C], iters):
    d.prod2x(x, y)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

proc mulFp6_longa22_Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Longa22", Fp6[C], iters):
    r.prodImpl_fp6o2_complex_snr_1pi(x, y)

proc mulFp6TCDFTBench*(C: static Algebra, iters: int) =
  var r: Fp6prj[C]
  let x = rng.random_unsafe(Fp6[C])
  let y = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Mul - Toom-Cook-3 + DFT", Fp6[C], iters):
    r.prod_prj(x, y)

proc sqrFp6CH_SQR2Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2", Fp6[C], iters):
    r.square_Chung_Hasan_SQR2(x)

proc sqrFp6CH_SQR2_unreduced_Bench*(C: static Algebra, iters: int) =
  var r: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2 unreduced", Fp6[C], iters):
    r.square2x_Chung_Hasan_SQR2(x)

proc sqrFp6CH_SQR2_lazyRed_Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  var d: doublePrec(Fp6[C])
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR2 lazy-reduced", Fp6[C], iters):
    d.square2x_Chung_Hasan_SQR2(x)
    r.c0.redc2x(d.c0)
    r.c1.redc2x(d.c1)
    r.c2.redc2x(d.c2)

proc sqrFp6CH_SQR3Bench*(C: static Algebra, iters: int) =
  var r: Fp6[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Chung-Hasan06 SQR3", Fp6[C], iters):
    r.square_Chung_Hasan_SQR3(x)

proc sqrFp6TCDFTBench*(C: static Algebra, iters: int) =
  var r: Fp6prj[C]
  let x = rng.random_unsafe(Fp6[C])
  bench("𝔽p6 Sqr - Toom-Cook-3 + DFT", Fp6[C], iters):
    r.square_prj(x)

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

main()
notes()
