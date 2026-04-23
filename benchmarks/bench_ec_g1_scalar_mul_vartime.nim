# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/[algebras, zoo_endomorphisms, zoo_subgroups],
  constantine/math/arithmetic,
  constantine/math/io/io_bigints,
  constantine/math/ec_shortweierstrass,
  constantine/math/elliptic/ec_scalar_mul_vartime,
  constantine/math_arbitrary_precision/arithmetic/[limbs_views, limbs_multiprec],
  # Helpers
  helpers/prng_unsafe,
  ./platforms,
  ./bench_blueprint,
  # Reference unsafe scalar multiplication
  constantine/math/elliptic/ec_scalar_mul_vartime

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
#               Benchmark of scalar multiplication
#            for G1 group of short Weierstrass curves
#          investigating vartime acceleration thresholds
#
#  Key insight: scalarMul_vartime uses getBits_LE_vartime() at runtime
#  to determine how many bits are set (usedBits), not the compile-time
#  bit size. This means BigInt[255] with only 4 bits set will use the
#  4-bit addchain algorithm.
#
# ############################################################

const curve = BLS12_381
const bits = Fr[curve].bits()
const hasEndo = curve.hasEndomorphismAcceleration()
const Iters = 1000

proc scalarMulVartimeDoubleAddBench*(EC: typedesc, scalar: BigInt[bits], iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("EC ScalarMul " & $scalar.limbs.getBits_LE_vartime() & "-bit " & $EC.G & " (vartime reference DoubleAdd)", EC, iters):
    r = P
    r.scalarMul_doubleAdd_vartime(scalar)

proc scalarMulVartimeMinHammingWeightRecodingBench*(EC: typedesc, scalar: BigInt[bits], iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("EC ScalarMul " & $scalar.limbs.getBits_LE_vartime() & "-bit " & $EC.G & " (vartime min Hamming Weight recoding)", EC, iters):
    r = P
    r.scalarMul_jy00_vartime(scalar)

proc scalarMulVartimeWNAFBench*(EC: typedesc, scalar: BigInt[bits], window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("EC ScalarMul " & $scalar.limbs.getBits_LE_vartime() & "-bit " & $EC.G & " (vartime wNAF-" & $window & ")", EC, iters):
    r = P
    r.scalarMul_wNAF_vartime(scalar, window)

proc scalarMulVartimeEndoWNAFBench*(EC: typedesc, scalar: BigInt[bits], window: static int, iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("EC ScalarMul " & $scalar.limbs.getBits_LE_vartime() & "-bit " & $EC.G & " (vartime endo + wNAF-" & $window & ")", EC, iters):
    r = P
    r.scalarMulEndo_wNAF_vartime(scalar, window)

proc scalarMulVartimeBench*(EC: typedesc, scalar: BigInt[bits], iters: int) {.noinline.} =
  var r {.noInit.}: EC
  var P = rng.random_unsafe(EC)
  P.clearCofactor()

  bench("EC ScalarMul " & $scalar.limbs.getBits_LE_vartime() & "-bit " & $EC.G & " (vartime auto)", EC, iters):
    r = P
    r.scalarMul_vartime(scalar)

proc makeSmallScalar(rng: var RngState, size: int): BigInt[bits] =
  result = rng.random_unsafe(BigInt[bits])
  # Note there is a BigInt.shiftRight(k) for 0 < k < WordBitwidth
  # and there is a arbitrary precision limbs shiftRight_vartime for any k
  result.limbs.shiftRight_vartime(result.limbs, bits-size)

proc main() =
  separator()
  echo "BLS12-381 G1 Scalar Multiplication benchmarks"
  echo "=============================================="
  echo "Scalar field bits: ", bits
  echo "Endomorphism acceleration: ", hasEndo
  echo "EndomorphismThreshold: ", EndomorphismThreshold
  echo ""
  echo "NOTE: Using BigInt[255] with controlled bit patterns to test"
  echo "      runtime threshold detection via getBits_LE_vartime()"
  echo ""

  const sizes = [1, 2, 4, 5, 6, 7, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224, 255]

  staticFor s, 0, sizes.len:
    const size = sizes[s]
    echo "Testing scalar with ", size, " bits set (runtime-detected)"
    let smallScalar = rng.makeSmallScalar(size)
    echo "Scalar: ", smallScalar.toHex()
    scalarMulVartimeDoubleAddBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, Iters)
    scalarMulVartimeMinHammingWeightRecodingBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, Iters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, window = 3, Iters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, window = 4, Iters)
    when hasEndo:
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, window = 3, Iters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, window = 4, Iters)
    scalarMulVartimeBench(EC_ShortW_Jac[Fp[curve], G1], smallScalar, Iters)
    separator()

main()
notes()